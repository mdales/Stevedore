//
//  AppDelegate.swift
//  StevedoreLoginLauncher
//
//  Created by Michael Dales on 25/04/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSWorkspace.shared.launchApplication(withBundleIdentifier: "com.digitalflapjack.Stevedore",
                                             options: [],
                                             additionalEventParamDescriptor: nil,
                                             launchIdentifier: nil)
        NSApp.terminate(nil)
    }
    
}
