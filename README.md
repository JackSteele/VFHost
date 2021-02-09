# VFHost - work in progress
#### VFHost is a (currently) very simple GUI for hosting Linux VMs on macOS Big Sur's Virtualization.framework.

## Building
Open `VFHost.xcodeproj`, add your certificate, and you're off to the races.

## Binaries
Notarized binary (pre-release!) available: [VFHost.zip](jds.lol/VFHost.zip)

## Known issues
- On x86_64, install will likely fail.
- If install fails on arm64, hit the uninstall button and try again - it should work. 
- If you find issues, please report them!

## Similar projects
**[evansm7/vftool](https://github.com/evansm7/vftool)** - this is a more mature (CLI-only) wrapper for Virtualization.framework
