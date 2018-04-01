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

enum DockerAPIResponse: Decodable {
    case Info(DockerAPIResponseInfo)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let info = try container.decode(DockerAPIResponseInfo.self)
        self = .Info(info)
//        } catch {
//            let inf = try container.decode(InfoStruct.self)
//            self = .Info(inf)
//        }
    }
}

protocol DockerChannelDelegate: AnyObject {
    func dockerChannelReceivedInfo(info: DockerAPIResponseInfo)
    func dockerChannelRecievedUnknownMessage(message: String)
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
    
    init(channelPath: String = "/var/run/docker.sock") {
        self.channelPath = channelPath
    }
    
    func makeInfoAPICall() throws {
        try syncQueue.sync {
            guard let d = ioChannel else {
                throw DockerChannelError.ChannelNotConnected
            }
            
            let formattedString = "GET /v1.30/info HTTP/1.0\r\n\r\n"
            let len = formattedString.withCString{ Int(strlen($0)) }
            formattedString.withCString {
                let dd = DispatchData(bytes: UnsafeRawBufferPointer(start: $0, count: len))
                d.write(offset: 0, data: dd, queue: socket_queue, ioHandler: { (b, d, r) in
                    print(b)
                    print(r)
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
                               cleanupHandler: { (_fd) in print("closed \(_fd)") })
            ioChannel = d
            
            d.setLimit(lowWater: 1)

            d.read(offset: 0, length: Int.max, queue: socket_queue) { [weak self] (a, b, c) in
                print("boo")
                guard let slf = self else {
                    return
                }
                
                if let b = b {
                    guard b.count > 0 else {
                        return
                    }
                    var d = Data(count: b.count)
                    d.withUnsafeMutableBytes{(bytes: UnsafeMutablePointer<UInt8>)->Void in
                        b.copyBytes(to: bytes, count: b.count)
                    }
                    let s = String(data: d, encoding: String.Encoding.utf8) as String?
                    guard let response = s else {
                        return
                    }
                    let parts = response.components(separatedBy:"\r\n\r\n")
                    guard let delegate = slf.delegate else {
                        return
                    }
                    slf.processing_queue.async {
                        guard let apiResponse = try? JSONDecoder().decode(DockerAPIResponse.self, from: parts[1].data(using: .utf8)!) else {
                            delegate.dockerChannelRecievedUnknownMessage(message: parts[1])
                            return
                        }
                        print(apiResponse)
                        switch apiResponse {
                        case let .Info(val):
                            delegate.dockerChannelReceivedInfo(info: val)
                        }
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
                print("Closing channel")
                d.close()
            }
        }
    }
}

