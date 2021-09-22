//
//  AutoInstall.swift
//  VFHost
//
//  Created by Jack Steele on 2/5/21.
//

import Foundation
import os.log

class ManagedMode: NSObject, ObservableObject {
    @Published var installing: Bool = false
    @Published var installProgress: Progress?
    @Published var fractionCompleted: Double?
    @Published var installed: [Distro?] = []
    
    private var progressObs: [NSKeyValueObservation?] = []
    let fm = FileManager.default
    
    var vm = VirtualMachine()
    
    func getArch() -> Arch {
        let archInfo = NSString(utf8String: NXGetLocalArchInfo().pointee.description)
        return archInfo!.contains("ARM64") ? .arm64 : .x86_64
    }
    
    func startVM(_ dist: Distro) {
        let arch = String(describing: getArch())
        let distDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost").appendingPathComponent(String(describing: dist))
        let kernelPath = distDir.appendingPathComponent("kernel-\(arch)").path
        let ramdiskPath = distDir.appendingPathComponent("ramdisk-\(arch)").path
        let diskPath = distDir.appendingPathComponent("disk-\(arch)").path
        let kernelParams = "console=hvc0 root=/dev/vda"
        let memoryAlloc = 2.0
        let autoCore = false
        let autoMem = false
        let coreAlloc = 2.0
        let vp = VMParameters(kernelParams: kernelParams, kernelPath: kernelPath, ramdiskPath: ramdiskPath, diskPath: diskPath, memoryAlloc: memoryAlloc, autoCore: autoCore, autoMem: autoMem, coreAlloc: coreAlloc)
        
        do {
            try vm.configure(vp)
            try vm.start()
        } catch {
            os_log(.error, "Something went wrong starting the VM")
            return
        }
        // msg from kernel:
        // Check rootdelay= (did the system wait long enough?)
        // doesn't need to wait at all on first launch
    }
    
    func extractKernel(_ dist: Distro, arch: Arch) -> Bool {
        if (arch == .x86_64 && dist == .Focal) || (arch == .x86_64 && dist == .Hirsute) { return true } // x86_64 kernel doesn't seem to be gzipped
        // This only works on amd64 images. am I missing something?
        var task = Process()
        let distDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost").appendingPathComponent(String(describing: dist))
        let kernelPath = distDir.appendingPathComponent("kernel-\(arch)").path
        installProgress?.becomeCurrent(withPendingUnitCount: 2)
        task.launchPath = "/bin/mv"
        task.arguments = [kernelPath, kernelPath + ".gz"]
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus != 0 { return false }
        installProgress?.resignCurrent()
        installProgress?.becomeCurrent(withPendingUnitCount: 2)
        task = Process()
        task.launchPath = "/usr/bin/gunzip"
        task.arguments = [kernelPath + ".gz"]
        task.launch()
        task.waitUntilExit()
        installProgress?.resignCurrent()
        if task.terminationStatus != 0 { return false }
        return true
    }
    
    func extractDisk(_ dist: Distro, arch: Arch) -> Bool {
        var task = Process()
        let distDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost").appendingPathComponent(String(describing: dist))
        let diskPath = distDir.appendingPathComponent("disk-\(arch)").path
        installProgress?.becomeCurrent(withPendingUnitCount: 2)
        // Cmd + C
        // Cmd + V lol
        task = Process()
        task.launchPath = "/usr/bin/tar"
        task.arguments = ["xvf", diskPath, "-C", distDir.path]
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus != 0 { return false }
        
        task = Process()
        task.launchPath = "/bin/rm"
        task.arguments = [diskPath]
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus != 0 { return false }
        
        var archString = ""
        if (arch == .x86_64) {
            archString = "amd64"
        } else if (arch == .arm64) {
            archString = "arm64"
        }
        
        task = Process()
        task.launchPath = "/usr/bin/env"
        let emptyPath = distDir.appendingPathComponent("disk-\(String(describing: arch))").path
        task.arguments = ["dd", "if=/dev/zero", "of=\(emptyPath)", "bs=1g", "count=8", "conv=notrunc"]    // , ">>", diskPath]
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus != 0 { return false }
        
        let extracted = distDir.appendingPathComponent("\(String(describing: dist).lowercased())-server-cloudimg-\(archString).img").path
        
        task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["dd", "if=\(extracted)", "of=\(emptyPath)", "bs=4m", "conv=notrunc"]    // , ">>", diskPath]
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus != 0 { return false }
        
        installProgress?.resignCurrent()
        return true
    }
    
    func stopVM() {
        vm.stop()
    }
    
    func detectInstalled() {
        let fm = FileManager.default
        let ourDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost")
        
        var installed = [Distro]()
        
        for dist in Distro.allCases {
            let distDir = ourDir.appendingPathComponent(String(describing: dist)).path
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: distDir, isDirectory: &isDir) {
                if isDir.boolValue {
                    installed.append(dist)
                }
            }
        }
        
        self.installed = installed
    }
    
    func firstLaunch(_ dist: Distro, arch: Arch) {
        installProgress = Progress(totalUnitCount: 20)
        switch dist {
        case .Focal:
            if extractKernel(dist, arch: arch) {
                if extractDisk(dist, arch: arch) {
                    focalFirstLaunch(arch)
                }
            } else {
                os_log(.error, "Kernel extraction failed")
            }
        case .Hirsute:
            if extractKernel(dist, arch: arch) {
                if extractDisk(dist, arch: arch) {
                    hirsuteFirstLaunch(arch)
                }
            } else {
                os_log(.error, "Kernel extraction failed")
            }
        }
    }
    
    func focalFirstLaunch(_ a: Arch) {
        installProgress?.becomeCurrent(withPendingUnitCount: 1)
        let arch = String(describing: a)
        let distDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost").appendingPathComponent("Focal")
        let kernelPath = distDir.appendingPathComponent("kernel-\(arch)").path
        let ramdiskPath = distDir.appendingPathComponent("ramdisk-\(arch)").path
        let diskPath = distDir.appendingPathComponent("disk-\(arch)").path
        let kernelParams = "console=hvc0"
        let memoryAlloc = 2.0
        let autoCore = false
        let autoMem = false
        let coreAlloc = 2.0
        vm = VirtualMachine()
        installProgress?.resignCurrent()
        installProgress?.becomeCurrent(withPendingUnitCount: 1)
        
        let vp = VMParameters(kernelParams: kernelParams, kernelPath: kernelPath, ramdiskPath: ramdiskPath, diskPath: diskPath, memoryAlloc: memoryAlloc, autoCore: autoCore, autoMem: autoMem, coreAlloc: coreAlloc)
        
        do {
            try vm.configure(vp)
            try vm.start()
        } catch {
            os_log(.error, "Something went wrong starting the VM")
            return
        }
        
        installProgress?.resignCurrent()
        
        self.vm.startScreen()
        
        DispatchQueue.global().async {
            for _ in 0...5 {
                self.installProgress?.becomeCurrent(withPendingUnitCount: 1)
                sleep(10)
                self.installProgress?.resignCurrent()
            }
            self.installProgress?.becomeCurrent(withPendingUnitCount: 1)
            sleep(5)
            self.vm.execute("")
            self.vm.execute("")
            self.vm.execute("")
            self.vm.execute("mkdir /mnt")
            self.vm.execute("mount /dev/vda /mnt")
            self.vm.execute("chroot /mnt")
            self.vm.execute("touch /etc/cloud/cloud-init.disabled")
            self.vm.execute("echo 'root:toor' | chpasswd")
            self.vm.execute("ssh-keygen -A")
            let path = "/etc/netplan/01-dhcp.yaml"
            self.vm.execute("echo \"network:\" >> \(path)")
            self.vm.execute("echo \"    renderer: networkd\" >> \(path)")
            self.vm.execute("echo \"    version: 2\" >> \(path)")
            self.vm.execute("echo \"    ethernets:\" >> \(path)")
            self.vm.execute("echo \"        enp0s1:\" >> \(path)")
            self.vm.execute("echo \"            dhcp4: true\" >> \(path)")
            self.vm.execute("exit")
            self.vm.execute("umount /dev/vda")
            sleep(5)
            self.installProgress?.resignCurrent()
            DispatchQueue.main.async {
                self.stopVM()
                
                let vp = VMParameters(kernelParams: "\(kernelParams) root=/dev/vda", kernelPath: kernelPath, ramdiskPath: ramdiskPath, diskPath: diskPath, memoryAlloc: memoryAlloc, autoCore: autoCore, autoMem: autoMem, coreAlloc: coreAlloc)
                
                do {
                    try self.vm.configure(vp)
                    try self.vm.start()
                } catch {
                    os_log(.error, "Something went wrong starting the VM")
                    return
                }
                
                self.vm.startScreen()
                DispatchQueue.global().async {
                    for _ in 0...5 {
                        self.installProgress?.becomeCurrent(withPendingUnitCount: 1)
                        sleep(10)
                        self.installProgress?.resignCurrent()
                    }
                    self.installProgress?.becomeCurrent(withPendingUnitCount: 1)
                    sleep(5)
                    self.vm.execute("root")
                    sleep(1)
                    self.vm.execute("toor")
                    sleep(1)
                    self.vm.execute("resize2fs /dev/vda")
                    sleep(10)
                    DispatchQueue.main.async {
                        self.stopVM()
                        self.installing = false
                        self.detectInstalled()
                    }
                }
            }
        }
    }
    
    func hirsuteFirstLaunch(_ a: Arch) {
        installProgress?.becomeCurrent(withPendingUnitCount: 1)
        let arch = String(describing: a)
        let distDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost").appendingPathComponent("Hirsute")
        let kernelPath = distDir.appendingPathComponent("kernel-\(arch)").path
        let ramdiskPath = distDir.appendingPathComponent("ramdisk-\(arch)").path
        let diskPath = distDir.appendingPathComponent("disk-\(arch)").path
        let kernelParams = "console=hvc0"
        let memoryAlloc = 2.0
        let autoCore = false
        let autoMem = false
        let coreAlloc = 2.0
        vm = VirtualMachine()
        installProgress?.resignCurrent()
        installProgress?.becomeCurrent(withPendingUnitCount: 1)
        
        let vp = VMParameters(kernelParams: kernelParams, kernelPath: kernelPath, ramdiskPath: ramdiskPath, diskPath: diskPath, memoryAlloc: memoryAlloc, autoCore: autoCore, autoMem: autoMem, coreAlloc: coreAlloc)
        
        do {
            try vm.configure(vp)
            try vm.start()
        } catch {
            os_log(.error, "Something went wrong starting the VM")
            return
        }
        
        installProgress?.resignCurrent()
        
        self.vm.startScreen()
        
        DispatchQueue.global().async {
            for _ in 0...5 {
                self.installProgress?.becomeCurrent(withPendingUnitCount: 1)
                sleep(10)
                self.installProgress?.resignCurrent()
            }
            self.installProgress?.becomeCurrent(withPendingUnitCount: 1)
            sleep(5)
            self.vm.execute("")
            self.vm.execute("")
            self.vm.execute("")
            self.vm.execute("mkdir /mnt")
            self.vm.execute("mount /dev/vda /mnt")
            self.vm.execute("chroot /mnt")
            self.vm.execute("touch /etc/cloud/cloud-init.disabled")
            self.vm.execute("echo 'root:toor' | chpasswd")
            self.vm.execute("ssh-keygen -A")
            let path = "/etc/netplan/01-dhcp.yaml"
            self.vm.execute("echo \"network:\" >> \(path)")
            self.vm.execute("echo \"    renderer: networkd\" >> \(path)")
            self.vm.execute("echo \"    version: 2\" >> \(path)")
            self.vm.execute("echo \"    ethernets:\" >> \(path)")
            self.vm.execute("echo \"        enp0s1:\" >> \(path)")
            self.vm.execute("echo \"            dhcp4: true\" >> \(path)")
            self.vm.execute("exit")
            self.vm.execute("umount /dev/vda")
            sleep(5)
            self.installProgress?.resignCurrent()
            DispatchQueue.main.async {
                self.stopVM()
                
                let vp = VMParameters(kernelParams: "\(kernelParams) root=/dev/vda", kernelPath: kernelPath, ramdiskPath: ramdiskPath, diskPath: diskPath, memoryAlloc: memoryAlloc, autoCore: autoCore, autoMem: autoMem, coreAlloc: coreAlloc)
                
                do {
                    try self.vm.configure(vp)
                    try self.vm.start()
                } catch {
                    os_log(.error, "Something went wrong starting the VM")
                    return
                }
                
                self.vm.startScreen()
                DispatchQueue.global().async {
                    for _ in 0...5 {
                        self.installProgress?.becomeCurrent(withPendingUnitCount: 1)
                        sleep(10)
                        self.installProgress?.resignCurrent()
                    }
                    self.installProgress?.becomeCurrent(withPendingUnitCount: 1)
                    sleep(5)
                    self.vm.execute("root")
                    sleep(1)
                    self.vm.execute("toor")
                    sleep(1)
                    self.vm.execute("resize2fs /dev/vda")
                    sleep(10)
                    DispatchQueue.main.async {
                        self.stopVM()
                        self.installing = false
                        self.detectInstalled()
                    }
                }
            }
        }
    }
    
    func getDistro(_ dist: Distro, arch: Arch) {
        guard let path = Bundle.main.path(forResource: "DownloadURLs", ofType: "plist") else { return }
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        let urls = try! PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil) as! [String: [String: String]]
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        let distURLs = urls[String(describing: dist) + " " + String(describing: arch)]!
        let fm = FileManager.default
        let ourDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost")
        let distDir = ourDir.appendingPathComponent(String(describing: dist))
        
        installProgress = Progress(totalUnitCount: Int64(distURLs.count))
        
        do {
            try fm.createDirectory(at: distDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return
        }
        
        installing = true
        
        for (type, urlString) in distURLs {
            var req = URLRequest(url: URL(string: urlString)!)
            req.httpMethod = "GET"
            let task = session.dataTask(with: req) { (data, res, error) in
                guard let res = res as? HTTPURLResponse else { return }
                if res.statusCode != 200 { return }
                if let data = data {
                    do {
                        try data.write(to: distDir.appendingPathComponent(type + "-" + String(describing: arch)))
                    } catch {
                        os_log(.error, "dataTask failed. Check network connection")
                        return
                        
                    }
                    if self.installProgress!.isFinished {
                        DispatchQueue.main.async {
                            self.firstLaunch(dist, arch: arch)
                        }
                    }
                }
            }
            self.installProgress?.addChild(task.progress, withPendingUnitCount: 1)
            task.resume()
        }
    }
    
    func rmDistro(_ dist: Distro) {
        let fm = FileManager.default
        let ourDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost")
        let distDir = ourDir.appendingPathComponent(String(describing: dist))
        do {
            try fm.removeItem(at: distDir)
            detectInstalled()
        } catch {
            os_log(.error, "Could not remove distribution directory. Manually remove at ~/Library/Application Support/VFHost/")
        }
    }
}

// We have one option right now
enum Distro: CaseIterable {
    case Focal
    case Hirsute
}

enum Arch {
    case arm64
    case x86_64
}
