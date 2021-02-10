//
//  VFHostApp.swift
//  VFHost
//
//  Created by Jack Steele on 2/4/21.
//

import SwiftUI

@main
struct VFHostApp: App {
//    @Environment var willTerminate: Bool = false

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
//    @State var quitAttempted: Bool

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.newItem, addition: { })
        }

    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var shouldTerminate = false
    @Published var canTerminate = true
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if canTerminate {
            return .terminateNow
        }
        
        if NSApplication.shared.windows.count == 0 {
            return .terminateNow
        } else {
            shouldTerminate = true
            return .terminateLater
        }
    }
    
    func noQuit() {
        NSApplication.shared.reply(toApplicationShouldTerminate: false)
    }
    
    func quit() {
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
//        self.willTerminate = true
    }
}
