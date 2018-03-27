//
//  DockerController.swift
//  Stevedore
//
//  Created by Michael Dales on 23/03/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import Foundation
import DockerClient

protocol DockerControllerDelegate: AnyObject {
    func dockerControllerReceivedInfo(info: DockerAPIResponseInfo)
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
    
    func requestInfo() throws {
        try channel.makeInfoAPICall()
    }
    
    func dockerChannelRecievedUnknownMessage(message: String) {
        print("We got unexpected message: \(message)")
    }
    
    func dockerChannelReceivedInfo(info: DockerAPIResponseInfo) {
        guard let delegate = delegate else {
            return
        }
        delegate.dockerControllerReceivedInfo(info: info)
    }

}
