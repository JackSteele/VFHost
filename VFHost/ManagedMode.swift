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
    @Published var downloadProgress: Progress?
    @Published var fractionCompleted: Double?
    @Published var installed: [Distro?] = []
    
    private var progressObs: [NSKeyValueObservation?] = []
    
    func getArch() -> Arch {
        let archInfo = NSString(utf8String: NXGetLocalArchInfo().pointee.description)
        return archInfo!.contains("ARM64") ? .arm64 : .x86_64
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
    
    func firstLaunch(dist: Distro) {
        switch dist {
        case .Focal:
            focalFirstLaunch()
        }
    }
    
    func focalFirstLaunch() {
        
    }
    
    func getDistro(_ dist: Distro, arch: Arch) {
        guard let path = Bundle.main.path(forResource: "DownloadURLs", ofType: "plist") else { return }
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        let urls = try! PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil) as! [String : [String : String]]
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        let distURLs = urls[String(describing: dist) + " " + String(describing: arch)]!
        let fm = FileManager.default
        let ourDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VFHost")
        let distDir = ourDir.appendingPathComponent(String(describing: dist))
        
        downloadProgress = Progress(totalUnitCount: Int64(distURLs.count))
        
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
                        os_log(.error, "I just couldn't pull it off this time. Sorry guys.")
                        return
                        
                    }
                    if self.downloadProgress!.isFinished {
                        
//                        DispatchQueue.main.async {
//                        self.installing = false
//                            self.detectInstalled()
//                        }
                    }
                }
            }
            self.downloadProgress?.addChild(task.progress, withPendingUnitCount: 1)
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
            os_log(.error, "had trouble removing distro directory")
        }
    }
}

// We have one option right now
enum Distro: CaseIterable {
    case Focal
}

enum Arch {
    case arm64
    case x86_64
}
