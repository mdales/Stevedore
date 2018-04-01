//
//  HTTPResponseParser.swift
//  Stevedore
//
//  Created by Michael Dales on 29/03/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import Foundation

enum HTTPResponseParserError: Error {
    case DataInvalid
    case UnexpectedEmptyHeaderSection
    case InvalidHeader(String)
    case InvalidHeaderValue(String, String)
    case InvalidStatus(String)
    case UnsupportedTransferEncoding(String)
    case ChunkLengthMissing(String)
    case ChunkLengthInvalid(String)
}

// This is just a minimal HTTP parser designed to cope with the things the docker API will spit at us. It in
// no way attempts to implement any RFC level compatibility. I could (should) have pulled in a third party
// library, but I wanted to write something that used callbacks rather than delegation for handling interactions.
//
class HTTPResponseParser {
    
    let HTTPResponseParserHTTPHeaderStart = "HTTP/"

    let headersReadCallback: (Int, [String: String]) -> Void
    let chunkReadCallback: (String) -> Void
    let syncQueue = DispatchQueue(label: "com.digitalflapjack.HTTPResponseParser.SyncQueue")
    // We want to have a serial queue rather than the global concurrent queue for responses
    let callbackQueue = DispatchQueue(label: "com.digitalflapjack.HTTPResponseParser.CallbackQueue")
    
    // should only be accessed on syncQueue
    var buffer = String()
    var currentStatusCode = 0
    var currentHeaders = [String: String]()
    
    var count: Int {
        get {
            return buffer.count
        }
    }
    
    init(headersReadCallback: @escaping(Int, [String:String]) -> Void,
         chunkReadCallback: @escaping (String) -> Void) {
        self.headersReadCallback = headersReadCallback
        self.chunkReadCallback = chunkReadCallback
    }
    
    func processResponseData(responseData: Data) throws
    {
        dispatchPrecondition(condition: .notOnQueue(syncQueue))
        
        let s = String(data: responseData, encoding: String.Encoding.utf8) as String?
        guard let response = s else {
            throw HTTPResponseParserError.DataInvalid
        }
        guard response.count > 0 else {
            return
        }
        try syncQueue.sync {
            buffer += response
            try parseBuffer()
        }
    }
    
    private func parseBuffer() throws {
        dispatchPrecondition(condition: .onQueue(syncQueue))
        
        loop: repeat {
            if currentStatusCode == 0 {
                // on body, so see if we can find the end of the headers yet
                
                // check that the buffer starts with something sensible as early as we can,
                // so we don't just build up data indefinitely if this is a garbage stream
                if buffer.count >= HTTPResponseParserHTTPHeaderStart.count  {
                    guard buffer.starts(with: HTTPResponseParserHTTPHeaderStart) else {
                        throw HTTPResponseParserError.InvalidStatus(buffer)
                    }
                }
                
                // check whether we have the header yet
                let rangeOptional = buffer.range(of: "\r\n\r\n")
                guard let range = rangeOptional else {
                    // header is not yet complete, so just wait until we have more data
                    break loop
                }
                
                let headerString = buffer[..<range.lowerBound]
                buffer = String(buffer[range.upperBound...])
                
                let lines = headerString.components(separatedBy: "\r\n")
                guard lines.count > 0 else {
                    throw HTTPResponseParserError.UnexpectedEmptyHeaderSection
                }
                
                // The first line should be the HTTP status line
                let statusString = lines.first!
                let headers = lines.dropFirst()
                
                // This is lazy, but given I don't care about the description right now, but we just care
                // about the status code
                let statusParts = statusString.components(separatedBy: " ")
                guard statusParts.count >= 2 else {
                    throw HTTPResponseParserError.InvalidStatus(statusString)
                }
                let statusCodeString = statusParts[1]
                let statusCodeOptional = Int(statusCodeString)
                guard let statusCode = statusCodeOptional else {
                    throw HTTPResponseParserError.InvalidStatus(statusString)
                }
                currentStatusCode = statusCode
                
                // the rest is key: value headers
                for line in headers {
                    let parts = line.components(separatedBy: ": ")
                    guard parts.count == 2 else {
                        throw HTTPResponseParserError.InvalidHeader(line)
                    }
                    currentHeaders[parts[0]] = parts[1]
                }
                
                let callback = self.headersReadCallback
                let headersCopy = self.currentHeaders
                callbackQueue.async {
                    callback(statusCode, headersCopy)
                }
            } else {
                // this is expected to be content
                let callback = self.chunkReadCallback
                var encoding = "identity"
                if let e = currentHeaders["Transfer-Encoding"] {
                    encoding = e
                }
                
                switch encoding {
                case "chunked":
                    
                    while buffer.count > 0 {
                        let s = buffer.range(of: "\r\n")
                        guard let lengthSplit = s else {
                            throw HTTPResponseParserError.ChunkLengthMissing(buffer)
                        }
                        let lengthString = buffer[..<lengthSplit.lowerBound]
                        let l = Int(lengthString, radix: 16)
                        guard let length = l else {
                            throw HTTPResponseParserError.ChunkLengthInvalid(String(lengthString))
                        }
                        
                        if length == 0 {
                            let newStart = buffer.index(lengthSplit.upperBound, offsetBy: 1)
                            buffer = String(buffer[newStart...])
                            resetState()
                            break loop
                        }
                        
                        let contentStart = lengthSplit.upperBound
                        let contentEnd = buffer.index(contentStart, offsetBy:length)
                        
                        let content = String(buffer[contentStart..<contentEnd])
                        callbackQueue.async {
                            callback(content)
                        }
                        
                        let newStart = buffer.index(after:contentEnd)
                        buffer = String(buffer[newStart...])
                    }
                    
                    
                case "identity":
                    // did we get a content length?
                    if let contentLengthString = currentHeaders["Content-Length"] {
                        guard let contentLength = Int(contentLengthString) else {
                            throw HTTPResponseParserError.InvalidHeaderValue("Content-Length", contentLengthString)
                        }
                        
                        // we got a content length, so use that
                        guard contentLength <= buffer.count else {
                            // not enough data yet, so wait until we get more
                            break loop
                        }
                        
                        let contentEnd = buffer.index(buffer.startIndex, offsetBy: contentLength)
                        let content = String(buffer[..<contentEnd])
                        callbackQueue.async {
                            callback(content)
                        }
                        
                        // the end of the content should have a \r\n\r\n on it?
                        let newStart = buffer.index(after:buffer.index(after:contentEnd))
                        buffer = String(buffer[newStart...])
                        resetState()
                        
                    } else {
                        // we didn't get a content length, so just read until
                        // \r\n\r\n
                        let rangeOptional = buffer.range(of: "\r\n\r\n")
                        guard let range = rangeOptional else {
                            // content is not yet complete, so just wait until we have more data
                            break loop
                        }
                        let content = String(buffer[..<range.lowerBound])
                        callbackQueue.async {
                            callback(content)
                        }
                        
                        buffer = String(buffer[range.upperBound...])
                        resetState()
                    }
                default:
                    throw HTTPResponseParserError.UnsupportedTransferEncoding(encoding)
                }
            }
        } while true
        
    }
    
    private func resetState() {
        dispatchPrecondition(condition: .onQueue(syncQueue))
        self.currentStatusCode = 0
        self.currentHeaders.removeAll()
    }
}
