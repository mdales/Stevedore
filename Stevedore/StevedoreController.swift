//
//  StevedoreController.swift
//  Stevedore
//
//  Created by Michael Dales on 23/03/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import os.log

import Cocoa
import ServiceManagement

class StevedoreController: NSObject, DockerControllerDelegate, NSMenuDelegate {

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var infoMenuItem: NSMenuItem!
    @IBOutlet weak var containersMenuItem: NSMenuItem!
    @IBOutlet weak var automaticallyStartOnLoginMenuItem: NSMenuItem!
    @IBOutlet weak var inactiveContainersSubMenu: NSMenuItem!
    
    static let logger = OSLog(subsystem: "com.digitalflapjack.stevedore", category: "general")
    
    let automaticallyStartOnLoginPreferenceKey = "automaticallyuStartOnLogin"
    
    let docker = DockerController()
    let healthyIcon: NSImage?
    let activeIcon: NSImage?
    let unknownIcon: NSImage?
    let unhealthyIcon: NSImage?
    
    // Only access on main thread
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var activeContainerMenuItems = [NSMenuItem]()
    var inactiveContainersMenuItems = [NSMenuItem]()
    
    override init() {
        self.healthyIcon = NSImage(named: "status-healthy")
        self.healthyIcon?.isTemplate = true
        self.activeIcon = NSImage(named: "status-active")
        self.activeIcon?.isTemplate = true
        self.unknownIcon = NSImage(named: "status-unknown")
        self.unhealthyIcon = NSImage(named: "status-unhealthy")
    }
    
    @IBAction func quitCommand(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
    override func awakeFromNib() {
        
        statusItem.image = self.unknownIcon
        statusItem.menu = statusMenu
        
        let defaults = UserDefaults.standard
        automaticallyStartOnLoginMenuItem.state = defaults.bool(forKey: automaticallyStartOnLoginPreferenceKey) ? .on : .off
        
        connectToDocker()
    }
    
    // MARK: - Manage docker connection
    
    func connectToDocker() {

        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

        do {
            try docker.connect(delegate: self)
        } catch {
            os_log("Error connecting to Docker: %@", log: StevedoreController.logger, type: .error, error.localizedDescription)
            statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
            
            // if we fail to connect, try again periodically, as we might have raced with docker launching
            let deadline = DispatchTime.now() + .seconds(5)
            DispatchQueue.main.asyncAfter(deadline: deadline) { [unowned self] in
                self.connectToDocker()
            }
            return
        }
        
        do {
            try docker.requestDockerInfo()
        } catch {
            os_log("Error talking to Docker: %@", log: StevedoreController.logger, type: .error, error.localizedDescription)
            statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
        }
    }
    
    func resetDockerConnection() {
        
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
        
        do {
            try docker.disconnect()
        } catch {
            os_log("Error thrown when closing docker channel: %@", log: StevedoreController.logger, error.localizedDescription)
            
            // if we can't close the channel nicely, give up
            statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommunicative"
            return
        }
        
        statusItem.image = self.unknownIcon
        self.infoMenuItem.title = "Docker Status: Connecting"
        
        let deadline = DispatchTime.now() + .seconds(1)
        DispatchQueue.main.asyncAfter(deadline: deadline) { [unowned self] in
            self.connectToDocker()
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
    
    func buildMenuItemFroContainer(containerInfo: DockerAPIResponseContainer) -> NSMenuItem {
        
        let newItem = NSMenuItem(title: containerInfo.humanName, action: nil, keyEquivalent: "")
        
        let submenu = NSMenu(title: "")
        submenu.autoenablesItems = false

        if (!containerInfo.isActive) {
            let runMenu = NSMenuItem(title: "Run", action: #selector(self.runContainer(sender:)), keyEquivalent: "")
            runMenu.representedObject = containerInfo
            runMenu.target = self
            submenu.addItem(runMenu)
            
            let delMenu = NSMenuItem(title: "Delete…", action: #selector(self.deleteContainer(sender:)), keyEquivalent: "")
            delMenu.representedObject = containerInfo
            delMenu.target = self
            submenu.addItem(delMenu)
        } else {
            let attachMenu = NSMenuItem(title: "Attach terminal...", action: #selector(self.attachContainer(sender:)), keyEquivalent: "")
            attachMenu.representedObject = containerInfo
            attachMenu.target = self
            submenu.addItem(attachMenu)

            let stopMenu = NSMenuItem(title: "Stop", action: #selector(self.stopContainer(sender:)), keyEquivalent: "")
            stopMenu.representedObject = containerInfo
            stopMenu.target = self
            submenu.addItem(stopMenu)
        }
        
        newItem.submenu = submenu
        
        return newItem
    }
    
    func dockerControllerReceivedContainerList(list: [DockerAPIResponseContainer]) {
        DispatchQueue.main.async { [unowned self] in
            
            // tear down what we have now
            for containerMenu in self.activeContainerMenuItems {
                self.statusMenu.removeItem(containerMenu)
            }
            for containerMenu in self.inactiveContainersMenuItems {
                self.inactiveContainersSubMenu.submenu?.removeItem(containerMenu)
            }
            
            let sortedList = list.sorted(by: { (containerA, containerB) -> Bool in
                return containerA.Created < containerB.Created
            })
            
            self.activeContainerMenuItems = sortedList.filter({ $0.isActive }).map({ (containerInfo) -> NSMenuItem in
                return self.buildMenuItemFroContainer(containerInfo: containerInfo);
            })
            self.inactiveContainersMenuItems = sortedList.filter({ !$0.isActive }).map({ (containerInfo) -> NSMenuItem in
                return self.buildMenuItemFroContainer(containerInfo: containerInfo);
            })
            
            for containerMenu in self.activeContainerMenuItems {
                self.statusMenu.insertItem(containerMenu, at: self.statusMenu.items.count - 5)
            }
            for containerMenu in self.inactiveContainersMenuItems {
                self.inactiveContainersSubMenu.submenu?.insertItem(containerMenu, at: 0)
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
    
    func dockerControllerReceivedError(message: String) {
        os_log("Received message from Docker: %@", log: StevedoreController.logger, type: .info, message)
        DispatchQueue.main.async { [unowned self] in
            self.resetDockerConnection()
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
    
    @objc func deleteContainer(sender: NSMenuItem) {
        guard let containerInfo = sender.representedObject as! DockerAPIResponseContainer? else {
            os_log("Failed to cast container record", log: StevedoreController.logger, type: .error)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Delete Container?"
        alert.informativeText = "Are you shure that you want to delete \(containerInfo.humanName)?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        if (alert.runModal() == .alertFirstButtonReturn) {
            do {
                try docker.deleteContainer(containerId: containerInfo.Id)
            } catch {
                os_log("Failed to talk to docker: %@", log: StevedoreController.logger, type: .error, error.localizedDescription)
                self.statusItem.image = self.unhealthyIcon
                self.infoMenuItem.title = "Docker Status: Uncommunicative"
            }
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
    
    @IBAction func automaticallyStartOnLoginToggle(_ sender: Any) {
        
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
        
        let defaults = UserDefaults.standard
        let newVal = !defaults.bool(forKey: automaticallyStartOnLoginPreferenceKey)
        defaults.set(newVal, forKey: automaticallyStartOnLoginPreferenceKey)
        automaticallyStartOnLoginMenuItem.state = newVal ? .on : .off

        if !SMLoginItemSetEnabled("com.digitalflapjack.StevedoreLoginLauncher" as CFString, newVal) {
            os_log("Failed to set login status.", log: StevedoreController.logger, type: .error)
        }
    }
    
}
