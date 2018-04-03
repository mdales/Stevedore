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
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let docker = DockerController()
    
    var latestDockerInfo: DockerAPIResponseInfo? = nil
    
    let healthyIcon: NSImage
    let unknownIcon: NSImage
    let unhealthyIcon: NSImage
    
    override init() {
        self.healthyIcon = StevedoreController.makeIcon(color: NSColor.black)
        self.unknownIcon = StevedoreController.makeIcon(color: NSColor.gray)
        self.unhealthyIcon = StevedoreController.makeIcon(color: NSColor.red)
    }
    
    class func makeIcon(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        color.drawSwatch(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        image.unlockFocus()
        return image
    }
    
    @IBAction func quitCommand(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
    override func awakeFromNib() {
        
        statusItem.image = self.unknownIcon
        statusItem.menu = statusMenu
        
        do {
            try docker.connect(delegate: self)
            try docker.requestInfo()
        } catch {
            os_log("Error talking to Docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
        }
    }
    
    func dockerControllerReceivedInfo(info: DockerAPIResponseInfo) {
        DispatchQueue.main.async { [unowned self] in
            self.statusItem.image = self.healthyIcon
            self.infoMenuItem.title = "Docker Status: OK"
            self.containersMenuItem.title = String(format: "Containers: %d", info.ContainersRunning)
        }
    }
    
    func dockerControllerReceivedUnexpectedMessage(message: String) {	
        os_log("Received unexpected message from Docker: %s", log: StevedoreController.logger, type: .info, message)
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        do {
            try docker.requestInfo()
        } catch {
            os_log("Failed to talk to docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
            self.statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommincative"
        }
    }
}
