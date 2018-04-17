//
//  DockerController.swift
//  Stevedore
//
//  Created by Michael Dales on 23/03/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import Foundation

protocol DockerControllerDelegate: AnyObject {
    func dockerControllerReceivedInfo(info: DockerAPIResponseInfo)
    func dockerControllerReceivedContainerList(list: [DockerAPIResponseContainer])
    func dockerControllerReceivedUnexpectedMessage(message: String)
}

class DockerController: DockerChannelDelegate {
    
    weak var delegate: DockerControllerDelegate? = nil
    let channel = DockerChannel()
    let syncQueue = DispatchQueue(label: "com.digitalflapjack.DockerController.syncQueue")
    
    func connect(delegate: DockerControllerDelegate) throws {
        try syncQueue.sync {
            self.delegate = delegate
            try channel.connect(delegate:self)
        }
    }
    
    func disconnect() throws {
        try syncQueue.sync {
            self.delegate = nil
            try channel.disconnect()
        }
    }
    
    func requestDockerInfo() throws {
        try channel.makeAPICall(path: "/info")
    }
    
    func requestContainerInfo() throws {
        try channel.makeAPICall(path: "/containers/json?all=true")
    }
    
    func startContainer(containerId: String) throws {
        try channel.makeAPICall(path: "/containers/\(containerId)/start", method: "POST")
    }
    
    func stopContainer(containerId: String) throws {
        try channel.makeAPICall(path: "/containers/\(containerId)/stop", method: "POST")
    }
    
    func dockerChannelReceivedUnknownMessage(message: String) {
        guard let delegate = delegate else {
            return
        }
        delegate.dockerControllerReceivedUnexpectedMessage(message: message)
    }
    
    func dockerChannelReceivedInfo(info: DockerAPIResponseInfo) {
        guard let delegate = delegate else {
            return
        }
        delegate.dockerControllerReceivedInfo(info: info)
    }

    func dockerChannelReceivedContainerList(list: [DockerAPIResponseContainer]) {
        guard let delegate = delegate else {
            return
        }
        delegate.dockerControllerReceivedContainerList(list: list)
    }
    
    func dockerChannelReceivedGenericMessage(message: DockerGenericMessageResponse) {
        print(message.message)
    }
}
