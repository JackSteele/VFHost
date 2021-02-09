//
//  VFHostApp.swift
//  VFHost
//
//  Created by Jack Steele on 2/4/21.
//

import SwiftUI

@main
struct VFHostApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.newItem, addition: { })
        }
    }
    
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
