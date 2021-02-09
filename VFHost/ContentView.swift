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
    
    @State var installProgress = 0.0
    @State var errorShown = false
    @State var errorMessage = ""
    @State var started = false
    @State var managed = true
    @State var height = 300
    @State var installed: [Distro?] = []
    
    @StateObject var params = UIParameters()
    
    let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    
    func loadData() {
        if let def = UserDefaults.standard.string(forKey: "kernelPath") {
            params.kernelPath = def
        }
        if let def = UserDefaults.standard.string(forKey: "ramdiskPath") {
            params.ramdiskPath = def
        }
        if let def = UserDefaults.standard.string(forKey: "diskPath") {
            params.diskPath = def
        }
        if let def = UserDefaults.standard.string(forKey: "kernelParams") {
            params.kernelParams = def
        }
        let def = UserDefaults.standard.object(forKey: "managed") as? Bool
        if let def = def {
            self.managed = def
        } else {
            self.managed = true
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
                    if managed {
                        if running {
                            if let distro = MM.installed.first {
                                MM.startVM(distro!)
                                MM.vm.startScreen()
                                MM.vm.attachScreen()
                            }
                        } else {
                            MM.stopVM()
                        }
                    } else {
                        if running {
                            if validateParams() {
                                saveDefaults()
                                startVM()
                            }
                        } else {
                            VM.stop()
                        }
                    }
                })
                .toggleStyle(SwitchToggleStyle())
                .disabled(managed ? (MM.installed.count == 0) : false)
            }
            Divider()
            if managed {
                Spacer()
                VStack {
                    if (MM.installed.count > 0) {
                        Spacer()
                        Text("Linux is installed.")
                            .font(.title)
                            .padding()
                        Text("root : toor")
                            .font(.body)
                            .padding(.horizontal)
                        Spacer()
                        Text("Something wrong?")
                            .font(.footnote)
                        Button("Uninstall Ubuntu Focal") {
                            for distro in MM.installed {
                                MM.rmDistro(distro!)
                            }
                        }
                        .disabled(started)
                        .font(.footnote)
                    } else {
                        Text(MM.installing ? "Linux is installing." : "Linux is not installed.")
                            .font(.title)
                            .padding()
                        Text("\(String(describing: MM.getArch())) Mac detected.")
                            .font(.title2)
                            .padding()
                        Button("Install Ubuntu Focal") {
//                            if termPerms() {
                                MM.getDistro(.Focal, arch: MM.getArch())
//                            } else {
//                                self.errorMessage = "Terminal permission is necessary."
//                                self.errorShown = true
//                            }
                        }
                        .disabled(MM.installing)
                        .padding()
                        
                        if (MM.installing) {
                            ProgressView(value: installProgress)
                                .padding()
                                .onReceive(timer, perform: { _ in
                                    // had trouble observing MM.installProgress for some reason
                                    // went with this dirty timer instead
                                    // kinda sucks
                                    if let dp = MM.installProgress {
                                        installProgress = dp.fractionCompleted
                                    }
                                })
                        }
                    }
                }.onAppear(perform: {
                    MM.detectInstalled()
                })
                Spacer()
            } else {
                Form {
                    Text("Kernel path")
                    HStack {
                        TextField("~/distribution/vmlinuz", text: $params.kernelPath)
                        Button("Select file") {
                            params.kernelPath = openFile(kind: "kernel")
                        }
                    }
                    
                    Text("Ramdisk path")
                    HStack {
                        TextField("~/distribution/initrd", text: $params.ramdiskPath)
                        Button("Select file") {
                            params.ramdiskPath = openFile(kind: "ramdisk")
                        }
                    }
                    
                    Text("Disk image path")
                    HStack {
                        TextField("~/distribution/disk.img", text: $params.diskPath)
                        Button("Select file") {
                            params.diskPath = openFile(kind: "disk image")
                        }
                    }
                    
                    Text("Kernel parameters")
                    HStack {
                        TextField("console=hvc0", text: $params.kernelParams)
                    }
                }
                .disabled(started)
                .padding()
                
                Form {
                    HStack {
                        Text("CPU cores allocated")
                        Toggle(isOn: $params.autoCore, label: {
                            Text("Auto")
                        })
                        Spacer()
                        Text(params.autoCore ? "" : "\(Int(params.coreAlloc)) core(s)")
                    }
                    
                    Slider(value: $params.coreAlloc,
                           in: paramLimits.minCores...paramLimits.maxCores,
                           step: 1
                    )
                    .padding(.horizontal, 10)
                    .disabled(params.autoCore)
                    
                    HStack {
                        Text("Memory allocated")
                        Toggle(isOn: $params.autoMem, label: {
                            Text("Auto")
                        })
                        Spacer()
                        Text(params.autoMem ? "" : String(format: "%.2f GB", params.memoryAlloc))
                    }
                    
                    Slider(value: $params.memoryAlloc,
                           in: paramLimits.minMem...paramLimits.maxMem,
                           step: 0.5)
                        .padding(.horizontal, 10)
                        .disabled(params.autoMem)
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
                    if managed {
                        MM.vm.connect()
                    } else {
                        VM.connect()
                    }
                }
                .disabled(!started)
                Spacer()
                Toggle(isOn: $managed, label: {
                    Text("Managed mode")
                })
                .onChange(of: managed, perform: { value in
                    UserDefaults.standard.set(self.managed, forKey: "managed")
                })
                .disabled(MM.installing)
                .disabled(started)
            }
            .padding()
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 500, maxWidth: .infinity, minHeight: 550, idealHeight: 550, maxHeight: .infinity, alignment: .center)
        .onAppear {
            loadData()
        }
        
    }
    
    func saveDefaults() {
        UserDefaults.standard.set(params.ramdiskPath, forKey: "ramdiskPath")
        UserDefaults.standard.set(params.kernelPath, forKey: "kernelPath")
        UserDefaults.standard.set(params.diskPath, forKey: "diskPath")
        UserDefaults.standard.set(params.kernelParams, forKey: "kernelParams")
    }
    
    func validateParams() -> Bool {
        guard params.kernelPath != "" else {
            started = false
            errorMessage = "Missing kernel path."
            errorShown = true
            return false
        }
        guard params.ramdiskPath != "" else {
            started = false
            errorMessage = "Missing ramdisk path."
            errorShown = true
            return false
        }
        guard params.diskPath != "" else {
            started = false
            errorMessage = "Missing disk path."
            errorShown = true
            return false
        }
        return true
    }
    
    func startVM() {
        do {
            let vp = VMParameters(kernelParams: params.kernelParams, kernelPath: params.kernelPath, ramdiskPath: params.ramdiskPath, diskPath: params.diskPath, memoryAlloc: params.memoryAlloc, autoCore: params.autoCore, autoMem: params.autoMem, coreAlloc: params.coreAlloc)
            try VM.configure(vp)
            try VM.start()
            VM.connect()
        } catch {
            started.toggle()
        }
    }
    
    func termPerms() -> Bool {
        let script = "tell application \"Terminal\" to activate"
        let applescript = NSAppleScript(source: script)
        var error: NSDictionary?
        applescript?.executeAndReturnError(&error)
        if let _ = error {
            return false
        }
        return true
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

class UIParameters: NSObject, ObservableObject {
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
