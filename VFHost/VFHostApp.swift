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
            let alert = NSAlert()
            alert.messageText = "Really quit?"
            alert.informativeText = "You're about to close VFHost with a VM running. Is this what you want?"
            alert.addButton(withTitle: "No, don't quit.")
            alert.addButton(withTitle: "Yes, quit.")
            alert.alertStyle = .critical
            let res = alert.runModal()
            if res == .alertFirstButtonReturn {
                return .terminateCancel
            } else if res == .alertSecondButtonReturn {
                return .terminateNow
            }

            return .terminateNow
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
