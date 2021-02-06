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
        
    @State var errorShown = false
    @State var errorMessage = ""
    @State var started = false
    
    @StateObject var vp = VMParameters()
    
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
    }
    
    var body: some View {
        VStack {
            Text(started ? "VM running" : "VM stopped").font(.largeTitle)
            
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
                       in: VM.minCore...VM.maxCore,
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
                       in: (Double(VM.minMem)+0.5)...Double(VM.maxMem),
                       step: 0.5)
                    .padding(.horizontal, 10)
                    .disabled(vp.autoMem)
            }
            .disabled(started)
            .padding()
            .alert(isPresented: $errorShown, content: {
                Alert(title: Text(errorMessage))
            })
            
            Divider()
            
            HStack {
                Button("Connect") {
                    VM.connect()
                }
                .disabled(!started)
                
                Spacer()
                
                Toggle(isOn: $started) {
                    Text("VM")
                }
                .onChange(of: started, perform: { running in
                    if running {
                        startVM()
                    } else {
                        VM.stop()
                    }
                })
                .toggleStyle(SwitchToggleStyle())
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
        UserDefaults.standard.set(vp.autoCore, forKey: "autoCore")
        UserDefaults.standard.set(vp.autoMem, forKey: "autoMem")
        UserDefaults.standard.set(vp.memoryAlloc, forKey: "memAlloc")
        UserDefaults.standard.set(vp.coreAlloc, forKey: "coreAlloc")
        UserDefaults.standard.set(vp.ramdiskPath, forKey: "ramdiskPath")
        UserDefaults.standard.set(vp.kernelPath, forKey: "kernelPath")
        UserDefaults.standard.set(vp.diskPath, forKey: "diskPath")
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
