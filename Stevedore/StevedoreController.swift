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
    @IBOutlet weak var hideInactiveContainersMenuItem: NSMenuItem!
    @IBOutlet weak var automaticallyStartOnLoginMenuItem: NSMenuItem!
    
    static let logger = OSLog(subsystem: "com.digitalflapjack.stevedore", category: "general")
    
    let hideInactiveContainersPreferenceKey = "hideInactiveContainers"
    let automaticallyStartOnLoginPreferenceKey = "automaticallyuStartOnLogin"
    
    
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
        
        let defaults = UserDefaults.standard
        hideInactiveContainersMenuItem.state = defaults.bool(forKey: hideInactiveContainersPreferenceKey) ? .on : .off
        automaticallyStartOnLoginMenuItem.state = defaults.bool(forKey: automaticallyStartOnLoginPreferenceKey) ? .on : .off
        
        do {
            try docker.connect(delegate: self)
            try docker.requestDockerInfo()
        } catch {
            os_log("Error talking to Docker: %@", log: StevedoreController.logger, type: .error, error.localizedDescription)
            statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
        }
    }
    
    // MARK: - Docker controller delegate methods
    
    func dockerControllerReceivedInfo(info: DockerAPIResponseInfo) {
        DispatchQueue.main.async { [unowned self] in
            self.statusItem.image = info.ContainersRunning > 0 ? self.activeIcon : self.healthyIcon
            self.infoMenuItem.title = "Docker Status: OK"
            self.containersMenuItem.title = String(format: "Active containers: %d", info.ContainersRunning)
        }
        
        // having got a successful response, scheduled to do so again in the future. If we ever get an error doing this
        // we'll never rescheduled, which for this WIP point is acceptable. In future we'll use the proper update API
        // from docker, but this is mostly just so I have something I can actually use right now :)
        let deadline = DispatchTime.now() + .seconds(5)
        DispatchQueue.global().asyncAfter(deadline: deadline) { [unowned self] in
            
            do {
                try self.docker.requestDockerInfo()
            } catch {
                os_log("Error talking to Docker: %@", log: StevedoreController.logger, type: .error, error.localizedDescription)
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
            
            let defaults = UserDefaults.standard
            let hideInactiveContainers = defaults.bool(forKey: self.hideInactiveContainersPreferenceKey)
            
            let visibleList = list.filter({ !hideInactiveContainers || $0.isActive })
            self.containerMenuItems = visibleList.map({ (containerInfo) -> NSMenuItem in
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
                newItem.state = containerInfo.isActive ? .on : .off
                
                let submenu = NSMenu(title: "")
                submenu.autoenablesItems = false
                if !hideInactiveContainers {
                    let runMenu = NSMenuItem(title: "Run", action: #selector(self.runContainer), keyEquivalent: "")
                    runMenu.representedObject = containerInfo
                    runMenu.target = self
                    runMenu.isEnabled = !containerInfo.isActive
                    submenu.addItem(runMenu)
                }
                let attachMenu = NSMenuItem(title: "Attach terminal...", action: #selector(self.attachContainer), keyEquivalent: "")
                attachMenu.representedObject = containerInfo
                attachMenu.target = self
                attachMenu.isEnabled = containerInfo.isActive
                submenu.addItem(attachMenu)
                let stopMenu = NSMenuItem(title: "Stop", action: #selector(self.stopContainer), keyEquivalent: "")
                stopMenu.representedObject = containerInfo
                stopMenu.target = self
                stopMenu.isEnabled = containerInfo.isActive
                submenu.addItem(stopMenu)
                
                newItem.submenu = submenu
                
                return newItem
            })
            
            for containerMenu in self.containerMenuItems {
                self.statusMenu.insertItem(containerMenu, at: self.statusMenu.items.count - 3)
            }
        }
    }
    
    func dockerControllerReceivedUnexpectedMessage(message: String) {
        os_log("Received unexpected message from Docker: %@", log: StevedoreController.logger, type: .info, message)
    }
    
    func dockerControllerReceivedMessage(message: String) {
        os_log("Received message from Docker: %@", log: StevedoreController.logger, type: .info, message)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Message from Docker"
            alert.informativeText = message
            alert.alertStyle = NSAlert.Style.informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Menu handling code
    
    func menuWillOpen(_ menu: NSMenu) {
        do {
            try docker.requestContainerInfo()
        } catch {
            os_log("Failed to talk to docker: %@", log: StevedoreController.logger, type: .error, error.localizedDescription)
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
            os_log("Failed to talk to docker: %@", log: StevedoreController.logger, type: .error, error.localizedDescription)
            self.statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
        }
    }
    
    @objc func attachContainer(sender: NSMenuItem) {
        guard let containerInfo = sender.representedObject as! DockerAPIResponseContainer? else {
            os_log("Failed to cast container record", log: StevedoreController.logger, type: .error)
            return
        }
        
        // there has to be a better way to do this than using applescript?
        let containerId = containerInfo.Id
        let attachScript = """
tell application "terminal"
    activate
    do script "docker attach \(containerId)"
end tell
"""
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: attachScript) else {
            os_log("Failed to create applescript", log: StevedoreController.logger, type: .error)
            return
        }
        scriptObject.executeAndReturnError(&error)
        if let actualError = error {
            os_log("Failed to execute applescript: %@", log: StevedoreController.logger, type: .error, actualError)
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
            os_log("Failed to talk to docker: %@", log: StevedoreController.logger, type: .error, error.localizedDescription)
            self.statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
        }
    }
    
    // MARK: - Menu handling code
    
    @IBAction func hideInactiveContainersToggle(_ sender: Any) {
        
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
        
        let defaults = UserDefaults.standard
        let newVal = !defaults.bool(forKey: hideInactiveContainersPreferenceKey)
        defaults.set(newVal, forKey: hideInactiveContainersPreferenceKey)
        hideInactiveContainersMenuItem.state = newVal ? .on : .off
    }
    
    @IBAction func automaticallyStartOnLoginToggle(_ sender: Any) {
        
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
        
        let defaults = UserDefaults.standard
        let newVal = !defaults.bool(forKey: automaticallyStartOnLoginPreferenceKey)
        defaults.set(newVal, forKey: automaticallyStartOnLoginPreferenceKey)
        automaticallyStartOnLoginMenuItem.state = newVal ? .on : .off
    }
    
}
