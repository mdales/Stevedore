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
    let healthyIcon: NSImage
    let activeIcon: NSImage
    let unknownIcon: NSImage
    let unhealthyIcon: NSImage
    
    // Only access on main thread
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var containerMenuItems = [NSMenuItem]()
    
    override init() {
        self.healthyIcon = StevedoreController.makeIcon(color: NSColor.black)
        self.activeIcon = StevedoreController.makeIcon(color: NSColor.green)
        self.unknownIcon = StevedoreController.makeIcon(color: NSColor.gray)
        self.unhealthyIcon = StevedoreController.makeIcon(color: NSColor.red)
    }
    
    // As a UX choice colour on the status bar is not a good idea for many reasons (colour blindness, it's visually
    // distracting, and so forth), but this is just a simple test for now, and we'll make something better later.
    class func makeIcon(color: NSColor) -> NSImage {
        let area = NSRect(x: 0, y: 0, width: 22, height: 22)
        let image = NSImage(size: area.size)
        image.lockFocus()
        NSColor.clear.setFill()
        let rect = NSBezierPath(rect: area)
        rect.fill()
        color.setStroke()
        let lineWidth: CGFloat = 3.0
        let smallerArea = NSRect(x: area.origin.x + lineWidth, y: area.origin.y + lineWidth,
                                 width: area.size.width - (2 * lineWidth), height: area.size.height - (2 * lineWidth))
        let circle = NSBezierPath(ovalIn: smallerArea)
        circle.lineWidth = lineWidth
        circle.stroke()
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
            statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommincative"
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
                try self.docker.requestInfo()
            } catch {
                os_log("Error talking to Docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
                DispatchQueue.main.async { [unowned self] in
                    self.statusItem.image = self.unhealthyIcon
                    self.infoMenuItem.title = "Docker Status: Uncommincative"
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
            try docker.requestContainers()
        } catch {
            os_log("Failed to talk to docker: %s", log: StevedoreController.logger, type: .error, error.localizedDescription)
            self.statusItem.image = self.unhealthyIcon
            self.infoMenuItem.title = "Docker Status: Uncommincative"
        }
    }
}
