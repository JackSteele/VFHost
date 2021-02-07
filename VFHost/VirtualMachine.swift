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
            case .success():
                os_log("VM started")
            case .failure(_):
                os_log(.error, "Error starting VM")
            }
        }
    }
    
    func stop() {
        if vm != nil {
            vm = nil
            // lol
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
