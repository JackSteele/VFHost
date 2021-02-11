![Image with icon and text "VFHost.app"](https://github.com/JackSteele/VFHost/raw/main/header.png)

### VFHost is a simple GUI for hosting Linux VMs on macOS Big Sur's Virtualization.framework.

## Downloads
Downloads are available [for version 0.2.x](https://github.com/JackSteele/VFHost/releases). These builds are notarized by Apple.

## You should know
This information will be incorporated in the app, but for now...
- Managed Mode
    - Your installations are located at ~/Library/Application Support/VFHost
    - You can't currently change your CPU/memory allocation through Managed Mode. Turning off Managed Mode and pointing VFHost to the files in the directory above is a workaround for now, though this will be implemented soon.
    - During the install process, the root disk is resized to ~8GB. You can manually resize it if you wish. Disk resize through VFHost is a high priority feature, and will be implemented soon.
    - To boot your VM outside of Managed Mode, you'll need to set the kernel parameters `console=hvc0 root=/dev/vda`

## Building
Open `VFHost.xcodeproj`, add your certificate, and you're off to the races.

## Known issues & workarounds
- VFHost uses `screen` internally to attach to your VM. On rare occasion, `screen` sessions are left behind and error messages appear, even after the app is restarted. First, make sure you're not using any `screen` sessions yourself - we're about to kill them all. Open Terminal and run `% pkill SCREEN`.
- If you find issues, please report them!

## Similar projects
**[evansm7/vftool](https://github.com/evansm7/vftool)** - this is a more mature (CLI-only) wrapper for Virtualization.framework

## License
VFHost is under the BSD license - you can find it [here](https://github.com/JackSteele/VFHost/blob/main/LICENSE)
