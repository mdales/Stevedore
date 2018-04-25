//
//  DockerChannel.swift
//  Stevedore
//
//  Created by Michael Dales on 24/03/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import Foundation

struct DockerAPIResponseInfo: Decodable {
    let ID: String
    let Containers: Int
    let ContainersRunning: Int
    let ContainersPaused: Int
    let ContainersStopped: Int
    let Images: Int
}

struct DockerAPIResponseContainer: Decodable {
    let Id : String
    let Names: [String]
    let Image: String
    let ImageID: String
    let State: String
    let Created: Int
    
    var isActive: Bool {
        get {
            return State == "running"
        }
    }
}

struct DockerGenericMessageResponse: Decodable {
    let message: String
}

enum DockerAPIResponse: Decodable {
    case Info(DockerAPIResponseInfo)
    case ContainerList([DockerAPIResponseContainer])
    case GenericMessage(DockerGenericMessageResponse)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            let info = try container.decode(DockerAPIResponseInfo.self)
            self = .Info(info)
        } catch {
            do {
                let list = try container.decode([DockerAPIResponseContainer].self)
                self = .ContainerList(list)
            } catch {
                let message = try container.decode(DockerGenericMessageResponse.self)
                self = .GenericMessage(message)
            }
        }
    }
}

protocol DockerChannelDelegate: AnyObject {
    func dockerChannelReceivedInfo(info: DockerAPIResponseInfo)
    func dockerChannelReceivedContainerList(list: [DockerAPIResponseContainer])
    func dockerChannelReceivedGenericMessage(message: DockerGenericMessageResponse)
    func dockerChannelReceivedUnknownMessage(message: String)
}

enum DockerChannelError: Error {
    case ChannelNotConnected
    case FailedToCreateSocket(String)
    case FailedToConnectSocket(String)
}

class DockerChannel  {

    let channelPath: String
    
    weak var delegate: DockerChannelDelegate?
    
    let syncQueue = DispatchQueue(label: "com.digitalflapjack.DockerChannel.syncQueue")
    let socket_queue = DispatchQueue(label: "com.digitalflapjack.DockerChannel.socket_queue")
    let processing_queue = DispatchQueue(label: "com.digitalflapjack.DockerChannel.processing_queue")
    var ioChannel: DispatchIO? = nil
    var fd: Int32? = -1
    
    // Created in init, but captures self in callback
    var parser: HTTPResponseParser!
    
    init(channelPath: String = "/var/run/docker.sock") {
        self.channelPath = channelPath
        self.parser = HTTPResponseParser(headersReadCallback: { (statusCode, headers) in
        }, chunkReadCallback: { (body) in
            self.decodeAPIResponse(raw: body)
        })
    }
    
    func makeAPICall(path: String, method: String = "GET") throws {
        try syncQueue.sync {
            guard let d = ioChannel else {
                throw DockerChannelError.ChannelNotConnected
            }
            let formattedString = "\(method) /v1.30\(path) HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
            let len = formattedString.withCString{ Int(strlen($0)) }
            formattedString.withCString {
                let dd = DispatchData(bytes: UnsafeRawBufferPointer(start: $0, count: len))
                d.write(offset: 0, data: dd, queue: socket_queue, ioHandler: { (b, d, r) in
                    // todo
                })
            }
        }
    }
    
    func connect(delegate: DockerChannelDelegate) throws {
        try syncQueue.sync {
            
            let _fd = socket(AF_UNIX, SOCK_STREAM, 0)
            if _fd < 0 {
                let errn = errno
                let err = String(utf8String: strerror(errn)) ?? "Unknown error code: \(errn)"
                throw DockerChannelError.FailedToCreateSocket(err)
            }
            
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            
            let lengthOfPath = channelPath.withCString{ Int(strlen($0)) }
            _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                channelPath.withCString {
                    strncpy(ptr, $0, lengthOfPath)
                }
            }
            var res: Int32 = 0
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    res = Darwin.connect(_fd, UnsafePointer<sockaddr>($0), UInt32(MemoryLayout<sockaddr_un>.stride))
                }
            }
            
            if res != 0 {
                let errn = errno
                let err = String(utf8String: strerror(errn)) ?? "Unknown error code: \(errn)"
                close(_fd)
                throw DockerChannelError.FailedToConnectSocket(err)
            }
            
            let d = DispatchIO(type: DispatchIO.StreamType.stream, fileDescriptor: _fd, queue: socket_queue,
                               cleanupHandler: { (_fd) in
                                // todo
            })
            ioChannel = d
            
            d.setLimit(lowWater: 1)

            d.read(offset: 0, length: Int.max, queue: socket_queue) { [weak self] (a, b, c) in
                guard let `self` = self else { return }
                
                if let b = b {
                    guard b.count > 0 else {
                        return
                    }
                    var d = Data(count: b.count)
                    d.withUnsafeMutableBytes{(bytes: UnsafeMutablePointer<UInt8>)->Void in
                        b.copyBytes(to: bytes, count: b.count)
                    }
                    
                    do {
                        try self.parser.processResponseData(responseData: d)
                    } catch {
                        // todo
                    }
                }
            }
            
            self.delegate = delegate
        }
    }
    
    func disconnect() throws {
        syncQueue.sync {
            self.delegate = nil
            if let d = ioChannel {
                d.close()
            }
        }
    }
    
    private func decodeAPIResponse(raw: String) {
        
        guard let delegate = delegate else {
            return
        }
        
        guard let apiResponse = try? JSONDecoder().decode(DockerAPIResponse.self, from: raw.data(using: .utf8)!) else {
            delegate.dockerChannelReceivedUnknownMessage(message: raw)
            return
        }
        switch apiResponse {
            case let .Info(val):
                delegate.dockerChannelReceivedInfo(info: val)
            case let .ContainerList(val):
                delegate.dockerChannelReceivedContainerList(list: val)
            case let .GenericMessage(val):
                delegate.dockerChannelReceivedGenericMessage(message: val)
        }
    }
}

