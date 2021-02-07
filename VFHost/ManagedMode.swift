//
//  AutoInstall.swift
//  VFHost
//
//  Created by Jack Steele on 2/5/21.
//

import Foundation
import os.log

class ManagedMode: NSObject, ObservableObject {
    @Published var downloading: Bool = false
    @Published var downloadProgress: Progress?
    @Published var fractionCompleted: Double?
    
    private var progressObs: [NSKeyValueObservation?] = []
    
    func getArch() -> Arch {
        let archInfo = NSString(utf8String: NXGetLocalArchInfo().pointee.description)
        return archInfo!.contains("ARM64") ? .arm64 : .x86_64
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
        
        downloading = true
        
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
                        self.downloading = false
                    }
                }
            }
            self.downloadProgress?.addChild(task.progress, withPendingUnitCount: 1)

            task.resume()
        }
    }
}

// We have one option right now
enum Distro: String {
    case Focal
}

enum Arch {
    case arm64
    case x86_64
}
