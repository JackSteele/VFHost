//
//  ContentView.swift
//  VFHost
//
//  Created by Jack Steele on 2/4/21.
//

import SwiftUI
import Virtualization

struct ContentView: View {
    @ObservedObject var VM = VirtualMachine()
    @ObservedObject var MM = ManagedMode()
    
    let paramLimits = ParameterLimits()
    
    @State var downloadProgress = 0.0
    @State var errorShown = false
    @State var errorMessage = ""
    @State var started = false
    @State var managed = true
    @State var height = 300
    
    @StateObject var vp = VMParameters()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    func loadData() {
        if let def = UserDefaults.standard.string(forKey: "kernelPath") {
            vp.kernelPath = def
        }
        if let def = UserDefaults.standard.string(forKey: "ramdiskPath") {
            vp.ramdiskPath = def
        }
        if let def = UserDefaults.standard.string(forKey: "diskPath") {
            vp.diskPath = def
        }
        if let def = UserDefaults.standard.string(forKey: "kernelParams") {
            vp.kernelParams = def
        }
    }
    
    var body: some View {
        VStack {
            HStack{
                Spacer()
                Text(started ? "VM running" : "VM stopped").font(.largeTitle)
                Spacer()
                
                Toggle(isOn: $started) {
                    Text("")
                }
                .onChange(of: started, perform: { running in
                    if running {
                        startVM()
                    } else {
                        VM.stop()
                    }
                })
                .toggleStyle(SwitchToggleStyle())
                .disabled(managed)
            }
            Divider()
            if managed {
                Spacer()
                Text("Ubuntu is not installed.")
                    .font(.title2)
                Text("\(String(describing: MM.getArch())) Mac detected")
                    .font(.title3)
                Button("Install Ubuntu 20.04 LTS") {
                        MM.getDistro(.Focal, arch: MM.getArch())
                }.disabled(MM.downloading)
                
                if (MM.downloading) {
                    ProgressView(value: downloadProgress)
                        .padding()
                        .onReceive(timer, perform: { _ in
                            if let dp = MM.downloadProgress {
                                downloadProgress = dp.fractionCompleted
                            }
                        })
                }
                Spacer()
            } else {
                Form {
                    Text("Kernel path")
                    HStack {
                        TextField("~/distribution/vmlinuz", text: $vp.kernelPath)
                        Button("Select file") {
                            vp.kernelPath = openFile(kind: "kernel")
                        }
                    }
                    
                    Text("Ramdisk path")
                    HStack {
                        TextField("~/distribution/initrd", text: $vp.ramdiskPath)
                        Button("Select file") {
                            vp.ramdiskPath = openFile(kind: "ramdisk")
                        }
                    }
                    
                    Text("Disk image path")
                    HStack {
                        TextField("~/distribution/disk.img", text: $vp.diskPath)
                        Button("Select file") {
                            vp.diskPath = openFile(kind: "disk image")
                        }
                    }
                    
                    Text("Kernel parameters")
                    HStack {
                        TextField("console=hvc0", text: $vp.kernelParams)
                    }
                }
                .disabled(started)
                .padding()
                
                Form {
                    HStack {
                        Text("CPU cores allocated")
                        Toggle(isOn: $vp.autoCore, label: {
                            Text("Auto")
                        })
                        Spacer()
                        Text(vp.autoCore ? "" : "\(Int(vp.coreAlloc)) core(s)")
                    }
                    
                    Slider(value: $vp.coreAlloc,
                           in: paramLimits.minCores...paramLimits.maxCores,
                           step: 1
                    )
                    .padding(.horizontal, 10)
                    .disabled(vp.autoCore)
                    
                    HStack {
                        Text("Memory allocated")
                        Toggle(isOn: $vp.autoMem, label: {
                            Text("Auto")
                        })
                        Spacer()
                        Text(vp.autoMem ? "" : String(format: "%.2f GB", vp.memoryAlloc))
                    }
                    
                    Slider(value: $vp.memoryAlloc,
                           in: paramLimits.minMem...paramLimits.maxMem,
                           step: 0.5)
                        .padding(.horizontal, 10)
                        .disabled(vp.autoMem)
                }
                .disabled(started)
                .padding()
                .alert(isPresented: $errorShown, content: {
                    Alert(title: Text(errorMessage))
                })
            }
            
            /// Bottom bit
            Divider()
            
            HStack {
                Button("Reconnect") {
                    VM.connect()
                }
                .disabled(!started)
                Spacer()
                Toggle(isOn: $managed, label: {
                    Text("Managed mode")
                })
            }
            .padding()
        }
        .padding()
        .frame(width: 500, height: 550, alignment: .center)
        .onAppear {
            loadData()
        }
        
    }
    
    func saveDefaults() {
        UserDefaults.standard.set(vp.ramdiskPath, forKey: "ramdiskPath")
        UserDefaults.standard.set(vp.kernelPath, forKey: "kernelPath")
        UserDefaults.standard.set(vp.diskPath, forKey: "diskPath")
        UserDefaults.standard.set(vp.kernelParams, forKey: "kernelParams")
    }
    
    func startVM() {
        guard vp.kernelPath != "" else {
            started = false
            errorMessage = "Missing kernel path."
            errorShown = true
            return
        }
        guard vp.ramdiskPath != "" else {
            started = false
            errorMessage = "Missing ramdisk path."
            errorShown = true
            return
        }
        guard vp.diskPath != "" else {
            started = false
            errorMessage = "Missing disk path."
            errorShown = true
            return
        }
        
        saveDefaults()
        
        do {
            try VM.configure(vp: self.vp)
            try VM.start()
            VM.connect()
        } catch {
            started.toggle()
        }
    }
    
    func openFile(kind: String) -> String {
        let dialog = NSOpenPanel()
        dialog.title = "Select your \(kind)"
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories = false
        dialog.showsResizeIndicator = true
        
        if (dialog.runModal() == NSApplication.ModalResponse.OK) {
            if let url = dialog.url {
                return url.path
            }
        }
        
        return ""
    }
}

struct ParameterLimits {
    // (10
    let minMem = Double(VZVirtualMachineConfiguration.minimumAllowedMemorySize/(1073741824)) + 0.5
    let maxMem = Double(VZVirtualMachineConfiguration.maximumAllowedMemorySize/(1073741824))
    let memRange = Double((VZVirtualMachineConfiguration.maximumAllowedMemorySize - VZVirtualMachineConfiguration.minimumAllowedMemorySize)/(1073741824))
    let minCores = Double(VZVirtualMachineConfiguration.minimumAllowedCPUCount)
    let maxCores = Double(VZVirtualMachineConfiguration.maximumAllowedCPUCount)
    let coreRange = Double(VZVirtualMachineConfiguration.maximumAllowedCPUCount - VZVirtualMachineConfiguration.minimumAllowedCPUCount)
}

class VMParameters: NSObject, ObservableObject {
    @Published var kernelParams = "console=hvc0"
    @Published var kernelPath = ""
    @Published var ramdiskPath = ""
    @Published var diskPath = ""
    // in GB - very lazy
    @Published var memoryAlloc: Double = Double(VZVirtualMachineConfiguration.minimumAllowedMemorySize/(1024*1024*1024)) + 0.5
    @Published var autoCore = true
    @Published var autoMem = true
    @Published var coreAlloc: Double = Double(VZVirtualMachineConfiguration.minimumAllowedCPUCount)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
