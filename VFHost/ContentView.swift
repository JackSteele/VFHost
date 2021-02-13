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
    @EnvironmentObject var appDelegate: AppDelegate
    @State var windowDelegate = WindowDelegate()
    
    @State private var window: NSWindow?
    @State var installProgress = 0.0
    @State var errorShown = false
    @State var killConfirmationShown = false
    @State var killCancelled = false
    @State var uninstallConfirmationShown = false
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
            HStack {
                Spacer()
                if killConfirmationShown {
                    Text("VM stopping").font(.largeTitle)
                } else {
                    Text(started ? "VM running" : "VM stopped").font(.largeTitle)
                }
                Spacer()
                
                Toggle(isOn: $started) {
                    Text("")
                }
                .onChange(of: started, perform: { running in
                    if killCancelled {
                        killCancelled = false
                        return
                    }
                    if running {
                        if managed {
                            appDelegate.canTerminate = false
                            windowDelegate.canTerminate = false
                            if let distro = MM.installed.first {
                                MM.startVM(distro!)
                                MM.vm.startScreen()
                                MM.vm.attachScreen()
                            }
                        } else {
                            appDelegate.canTerminate = false
                            windowDelegate.canTerminate = false
                            if validateParams() {
                                saveDefaults()
                                startVM()
                            }
                        }
                    } else {
                        self.killConfirmationShown.toggle()
                    }
                })
                .toggleStyle(SwitchToggleStyle())
                .disabled(managed ? (MM.installed.count == 0) : false)
                .alert(isPresented: $killConfirmationShown, content: {
                    Alert(title: Text("Really stop this VM?"), primaryButton: .default(Text("Keep running"), action: {
                        self.killCancelled = true
                        self.started = true
                    }), secondaryButton: .destructive(Text("Stop VM"), action: {
                        kill()
                    }))
                })
            }
            Divider()
            if managed {
                Spacer()
                VStack {
                    if MM.installed.count > 0 {
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
                            self.uninstallConfirmationShown.toggle()
                        }
                        .alert(isPresented: $uninstallConfirmationShown, content: {
                            Alert(title: Text("Uninstall?"),
                                  message: Text("Are you sure you'd like to uninstall this VM?"),
                                  primaryButton: .cancel(Text("Don't do it!"), action: {
                                  }), secondaryButton: .destructive(Text("Uninstall"), action: {
                                    for distro in MM.installed {
                                        MM.rmDistro(distro!)
                                    }
                                  }))
                        })
                        .disabled(started)
                        .font(.footnote)
                    } else {
                        Text(MM.installing ? "Linux is installing." : "Linux is not installed.")
                            .font(.title)
                            .padding()
                        Text("Installation requires about 10GB of space.")
                            .font(.title2)
                            .padding()
                        Text("\(String(describing: MM.getArch())) Mac detected.")
                            .font(.title2)
                            .padding()
                        Button("Install Ubuntu Focal") {
                            MM.getDistro(.Focal, arch: MM.getArch())
                        }
                        .disabled(MM.installing)
                        .padding()
                        
                        if MM.installing {
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
                .alert(isPresented: $errorShown, content: {
                    Alert(title: Text(errorMessage))
                })
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
            }
            
            /// Bottom bit
            Divider()
            
            HStack {
                Button("Reconnect") {
                    if managed {
                        MM.vm.attachScreen()
                    } else {
                        VM.connect()
                    }
                }
                .disabled(!started)
                Spacer()
                Toggle(isOn: $managed, label: {
                    Text("Managed mode")
                })
                .onChange(of: managed, perform: { _ in
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
        .background(WindowAccessor(window: self.$window, windowDelegate: self.$windowDelegate))
        //        .alert(isPresented: Binding<Bool>(get: { appDelegate.shouldTerminate ? self.started : false }, set: { appDelegate.shouldTerminate = $0 }), content: {
        //            Alert(title: Text("Quit requested."),
        //                  message: Text("Do you really want to quit while the VM is running?"),
        //                  primaryButton: .default(Text("Don't quit!"), action: {
        //                    self.appDelegate.noQuit()
        //                  }),
        //                  secondaryButton: .destructive(Text("Quit"), action: {
        //                    self.appDelegate.quit()
        //                  }))
        //        })
    }
    
    func kill() {
        if managed {
            appDelegate.canTerminate = true
            windowDelegate.canTerminate = true
            MM.stopVM()
        } else {
            appDelegate.canTerminate = true
            windowDelegate.canTerminate = true
            VM.stop()
        }
    }
    
    func killUnmanaged() {
        
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
        
        if dialog.runModal() == NSApplication.ModalResponse.OK {
            if let url = dialog.url {
                return url.path
            }
        }
        return ""
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    @Binding var windowDelegate: WindowDelegate
    
    func makeNSView(context: Context) -> some NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.delegate = self.windowDelegate
            self.window = view.window
        }
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    var canTerminate = true
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApplication.shared.hide(sender)
        return false
        
        //        if canTerminate {
        //            return true
        //        } else {
        //            let alert = NSAlert()
        //            alert.messageText = "Really quit?"
        //            alert.informativeText = "You're about to close VFHost with a VM running. Is this what you want?"
        //            alert.addButton(withTitle: "No, don't quit.")
        //            alert.addButton(withTitle: "Yes, quit.")
        //            alert.alertStyle = .critical
        //            let res = alert.runModal()
        //            if res == .alertFirstButtonReturn {
        //                return false
        //            } else if res == .alertSecondButtonReturn {
        //                // I feel bad for this
        //                // sincerely
        //                exit(0)
        ////                return true
        //            }
        //            return true
        //        }
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
