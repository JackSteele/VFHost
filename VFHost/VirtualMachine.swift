//
//  VirtualMachine.swift
//  VFHost
//
//  Created by Jack Steele on 2/4/21.
//

import Foundation
import Cocoa
import Darwin
import Virtualization
import os.log

class VirtualMachine: ObservableObject {
    var cfg: VZVirtualMachineConfiguration?
    var vm: VZVirtualMachine?

    var ptyFD: Int32 = 0
    var ptyPath = ""
    var screenPID: Int32 = 0
    var screenSession: Process?

    @Published var running = false

    func configure(_ vp: VMParameters) throws {
        let config = VZVirtualMachineConfiguration()

        let bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: vp.kernelPath))
        if vp.ramdiskPath != "" {
            bootLoader.initialRamdiskURL = URL(fileURLWithPath: vp.ramdiskPath)
        }
        bootLoader.commandLine = vp.kernelParams

        config.bootLoader = bootLoader

        do {
            let storage = try VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: vp.diskPath), readOnly: false)
            let blockDevice = VZVirtioBlockDeviceConfiguration(attachment: storage)
            config.storageDevices = [blockDevice]
        } catch {
            os_log("Couldn't attach disk image")
            throw VZError(.internalError)
        }

        let ptyFD = configurePTY()
        if ptyFD == -1 {
            // should throw something more descriptive
            throw VZError(.internalError)
        }

        let mfile = FileHandle.init(fileDescriptor: ptyFD)
        let console = VZVirtioConsoleDeviceSerialPortConfiguration()
        console.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: mfile, fileHandleForWriting: mfile)
        config.serialPorts = [console]

        let balloonConfig = VZVirtioTraditionalMemoryBalloonDeviceConfiguration()
        config.memoryBalloonDevices = [balloonConfig]

        let entropyConfig = VZVirtioEntropyDeviceConfiguration()
        config.entropyDevices = [entropyConfig]

        let networkConfig = VZVirtioNetworkDeviceConfiguration()
        networkConfig.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [networkConfig]

        if !vp.autoCore {
            config.cpuCount = Int(vp.coreAlloc)
        }

        if !vp.autoMem {
            config.memorySize = UInt64(vp.memoryAlloc * 1024*1024*1024)
        } else {
            let minMem = VZVirtualMachineConfiguration.minimumAllowedMemorySize/(1024*1024*1024)
            let memRange = (VZVirtualMachineConfiguration.maximumAllowedMemorySize - VZVirtualMachineConfiguration.minimumAllowedMemorySize)/(1024*1024*1024)
            var mem = (memRange / 4) + minMem
            mem = mem * 1024*1024*1024
            config.memorySize = mem
        }

        try config.validate()

        os_log(.error, "VM configuration validation succeeded")
        cfg = config
    }

    func configurePTY() -> Int32 {
        var ptyFD: Int32 = 0
        var sfd: Int32 = 1

        if openpty(&ptyFD, &sfd, nil, nil, nil) == -1 {
            os_log(.error, "Error opening PTY")
            return -1
        }

        self.ptyPath = String(cString: ptsname(ptyFD))
        self.ptyFD = ptyFD

        return ptyFD
    }

    func start() throws {
        vm = VZVirtualMachine(configuration: cfg!)
        vm?.start { result in
            switch result {
            case .success:
                os_log("VM started")
            case .failure:
                os_log(.error, "Error starting VM")
            }
        }
    }

    // Calling this breaks everything, I might be an idiot
    func gracefulStop() {
        guard let vm = vm else { return }
        if vm.canRequestStop {
            do {
                try vm.requestStop()
            } catch {
                os_log(.error, "Couldn't stop VM gracefully")
            }
        }
    }

    func stop() {
        if vm != nil {
            // lol
            vm = nil
            // got 'em
            os.close(ptyFD)
            os_log("VM stopped")
        }
    }

    func isRunning() -> Bool {
        if vm?.state == .running {
            return true
        } else {
            return false
        }
    }

    func startScreen() {
        let task = Process()
        task.launchPath = "/usr/bin/screen"
        task.arguments = ["-S", "VFHost", "-dm", ptyPath]
//        print(task.arguments)
        task.launch()
        self.screenPID = task.processIdentifier + 1
        task.waitUntilExit()
    }

    func wipeScreens() {
        let task = Process()
        task.launchPath = "/usr/bin/screen"
        task.arguments = ["-wipe"]
        task.launch()
        task.waitUntilExit()
    }

    func attachScreen() {
        let script = "tell application \"Terminal\" to activate do script \"screen -x VFHost\""
        let applescript = NSAppleScript(source: script)
        var error: NSDictionary?
        applescript?.executeAndReturnError(&error)
        if let error = error {
            NSLog(error["NSAppleScriptErrorMessage"] as! String)
        }
//        let task = Process()
//        task.launchPath = "/usr/bin/env"
//        task.arguments = ["screen", "-x", "VFHost"]
//        task.launch()
//        self.screenSession = task
    }

    func execute(_ cmd: String) {
        let task = Process()
        task.launchPath = "/usr/bin/screen"
        task.arguments = ["-S", "VFHost", "-p0", "-X", "stuff", "\(cmd)\n"]
        task.launch()
        task.waitUntilExit()
    }

    func status() -> VZVirtualMachine.State? {
        return vm?.state
    }

    func connect() {
        let script = "tell application \"Terminal\" to do script \"screen \(ptyPath)\""
        let applescript = NSAppleScript(source: script)
        var error: NSDictionary?
        applescript?.executeAndReturnError(&error)
        if let error = error {
            NSLog(error["NSAppleScriptErrorMessage"] as! String)
        }
    }
}

struct VMParameters {
    var kernelParams = "console=hvc0"
    var kernelPath = ""
    var ramdiskPath = ""
    var diskPath = ""
    // in GB - very lazy
    var memoryAlloc: Double
    var autoCore = true
    var autoMem = true
    var coreAlloc: Double
}
