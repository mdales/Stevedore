//
//  StevedoreController.swift
//  Stevedore
//
//  Created by Michael Dales on 23/03/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import Cocoa

class StevedoreController: NSObject {

    @IBOutlet weak var statusMenu: NSMenu!
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    @IBAction func quitCommand(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
    override func awakeFromNib() {
        let icon = NSImage(named: NSImage.Name("statusIcon"))
        icon?.isTemplate = true
        statusItem.image = icon
        statusItem.menu = statusMenu
    }
}
