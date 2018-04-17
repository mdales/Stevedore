//
//  StevedoreController.swift
//  Stevedore
//
//  Created by Michael Dales on 23/03/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import Cocoa
import os.log

class StevedoreController: NSObject, DockerControllerDelegate, NSMenuDelegate {

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var infoMenuItem: NSMenuItem!
    @IBOutlet weak var containersMenuItem: NSMenuItem!
    
    static let logger = OSLog(subsystem: "com.digitalflapjack.stevedore", category: "general")
    
    let docker = DockerController()
    let healthyIcon: NSImage?
    let activeIcon: NSImage?
    let unknownIcon: NSImage?
    let unhealthyIcon: NSImage?
    
    // Only access on main thread
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var containerMenuItems = [NSMenuItem]()
    
    override init() {
        self.healthyIcon = NSImage(named: NSImage.Name("status-healthy"))
        self.healthyIcon?.isTemplate = true
        self.activeIcon = NSImage(named: NSImage.Name("status-active"))
        self.activeIcon?.isTemplate = true
        self.unknownIcon = NSImage(named: NSImage.Name("status-unknown"))
        self.unhealthyIcon = NSImage(named: NSImage.Name("status-unhealthy"))
    }
    
    @IBAction func quitCommand(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
    override func awakeFromNib() {
        
        statusItem.image = self.unknownIcon
        statusItem.menu = statusMenu
        
        do {
            try docker.connect(delegate: self)
            try docker.requestDockerInfo()
        } catch {
            os_log("Error talking to Docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
            statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
        }
    }
    
    func dockerControllerReceivedInfo(info: DockerAPIResponseInfo) {
        DispatchQueue.main.async { [unowned self] in
            self.statusItem.image = info.ContainersRunning > 0 ? self.activeIcon : self.healthyIcon
            self.infoMenuItem.title = "Docker Status: OK"
            self.containersMenuItem.title = String(format: "Containers: %d", info.ContainersRunning)
        }
        
        // having got a successful response, scheduled to do so again in the future. If we ever get an error doing this
        // we'll never rescheduled, which for this WIP point is acceptable. In future we'll use the proper update API
        // from docker, but this is mostly just so I have something I can actually use right now :)
        let deadline = DispatchTime.now() + .seconds(5)
        DispatchQueue.global().asyncAfter(deadline: deadline) { [unowned self] in
            
            do {
                try self.docker.requestDockerInfo()
            } catch {
                os_log("Error talking to Docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
                DispatchQueue.main.async { [unowned self] in
                    self.statusItem.image = self.unhealthyIcon
                    self.infoMenuItem.title = "Docker Status: Uncommunicative"
                }
            }
        }
    }
    
    func dockerControllerReceivedContainerList(list: [DockerAPIResponseContainer]) {
        DispatchQueue.main.async { [unowned self] in
            
            // tear down what we have now
            for containerMenu in self.containerMenuItems {
                self.statusMenu.removeItem(containerMenu)
            }
            
            self.containerMenuItems = list.map({ (containerInfo) -> NSMenuItem in
                var name = containerInfo.Id
                
                // Docker containers list API will return not the human name, but a list of names used by both
                // humans and other containers of the form:
                // ["/other-container/hostname-for-this-container", "/actual-container-name"]
                // Which is useful for building a dependancy graph from the one call, but less good for building
                // just a UI like ours simply. The below algorithm is just a minimal hack to get something pretty
                // until we build a better model
                
                for protoname in containerInfo.Names {
                    let parts = protoname.split(separator: "/")
                    if parts.count == 1 {
                        name = String(parts[0])
                        break
                    }
                }
                
                let newItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                newItem.state = containerInfo.State == "running" ? .on : .off
                
                let submenu = NSMenu(title: "")
                submenu.autoenablesItems = false
                let runMenu = NSMenuItem(title: "Run", action: #selector(self.runContainer), keyEquivalent: "")
                runMenu.representedObject = containerInfo
                runMenu.target = self
                runMenu.isEnabled = containerInfo.State != "running"
                submenu.addItem(runMenu)
                let stopMenu = NSMenuItem(title: "Stop", action: #selector(self.stopContainer), keyEquivalent: "")
                stopMenu.representedObject = containerInfo
                stopMenu.target = self
                stopMenu.isEnabled = containerInfo.State == "running"
                submenu.addItem(stopMenu)
                
                newItem.submenu = submenu
                
                return newItem
            })
            
            for containerMenu in self.containerMenuItems {
                self.statusMenu.insertItem(containerMenu, at: self.statusMenu.items.count - 2)
            }
        }
    }
    
    func dockerControllerReceivedUnexpectedMessage(message: String) {
        os_log("Received unexpected message from Docker: %s", log: StevedoreController.logger, type: .info, message)
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        do {
            try docker.requestContainerInfo()
        } catch {
            os_log("Failed to talk to docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
            self.statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
        }
    }
    
    @objc func runContainer(sender: NSMenuItem) {
        guard let containerInfo = sender.representedObject as! DockerAPIResponseContainer? else {
            os_log("Failed to cast container record", log: StevedoreController.logger, type: .error)
            return
        }

        do {
            try docker.startContainer(containerId: containerInfo.Id)
        } catch {
            os_log("Failed to talk to docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
            self.statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
        }
    }
    
    @objc func stopContainer(sender: NSMenuItem) {
        guard let containerInfo = sender.representedObject as! DockerAPIResponseContainer? else {
            os_log("Failed to cast container record", log: StevedoreController.logger, type: .error)
            return
        }
        
        do {
            try docker.stopContainer(containerId: containerInfo.Id)
        } catch {
            os_log("Failed to talk to docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
            self.statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
        }
    }
}
