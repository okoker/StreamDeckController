# TreasLin N3 — Device Quirks

Hard-won knowledge from reverse-engineering. Do not skip any of these.

## Device Identity
- VID: 0x5548, PID: 0x1001
- Firmware: V3.VSDN3_PXL.02.010
- Protocol version: 3
- USB descriptor: "HOTSPOTEKUSB HID DEMO"
- OEM: MiraBox / Hotspot-Tek (Shenzhen)
- Same hardware sold as: TreasLin N3, Annadue, VBESTLIFE, Redragon SS551, Soomfon CN002, AJAZZ AKP03

## macOS CFRunLoop Requirement (CRITICAL)
IOKit HID input reports are ONLY delivered when CFRunLoop is running on the main thread. Without it, `IOHIDDeviceRegisterInputReportCallback` silently receives nothing. This is not documented by Apple. Every read/sniff attempt will fail unless `CFRunLoopRun()` or `CFRunLoopRunInMode()` is active. We spent hours debugging this — the device, protocol, and packet format were correct the whole time.

## IOHIDDeviceSetReport — Strip Report ID Byte
`IOHIDDeviceSetReport` expects data WITHOUT the report ID prefix byte. The report ID is passed as a separate parameter. Python's `hidapi` library includes the report ID in the data buffer and strips it internally — but when calling IOKit directly from Swift, you must do `Array(data.dropFirst())`. Failing to strip it shifts all payload bytes by 1, causing the device to ignore commands silently (no error returned).

## Init Sequence Order
The device requires this EXACT sequence to start sending input events:
1. CRT DIS (wake display)
2. CRT LIG (set brightness)
3. CRT STP (refresh/commit)
4. CRT CLE (clear all screens)

Changing the order (e.g. STP before LIG, or omitting CLE) can cause the device to not report events. The Python init_then_monitor.py test proved this sequence works.

## Packet Size
Protocol v3 uses 1024-byte data packets (1025 with report ID byte). Sending 512-byte packets (protocol v1 size) is silently ignored by the device. The CRT prefix is always: `[0x43, 0x52, 0x54, 0x00, 0x00]` ("CRT\0\0").

## CONNECT Keepalive
The device requires a CRT CONNECT packet every 5-10 seconds or it stops responding. Send via a Timer scheduled on the main run loop.

## Input Event Format
- 512-byte packets prefixed with "ACK\0\0OK\0\0" (bytes: 41 43 4B 00 00 4F 4B 00 00)
- Event code at byte[9], state at byte[10]
- State: 0x01=press, 0x00=release for buttons/knob presses
- Rotation events: state is always 0x00, direction encoded in event code (even=CCW, odd=CW)

## AppKit Import Does NOT Break IOKit
Importing AppKit (for NSEvent media key simulation) does NOT interfere with IOKit HID communication. Earlier we thought it did — the actual issue was the init sequence order change and malformed BAT image packets happening at the same time.

## BAT Image Protocol — Working
LCD key images are sent via CRT BAT. Sequence: BAT header (with JPEG length + 1-indexed key ID) → raw JPEG data in 1024-byte chunks → STP to commit. Protocol sourced from `4ndv/mirajazz` Rust library (same VID/PID).

### Calibrated Image Parameters
- **Size: 85x85 pixels** (official SDK says 64x64, Rust lib uses 60x60 — both too small for actual LCD)
- **Rotation: 90° CW** (protocol v3 requirement)
- **JPEG quality: 0.9**
- **LCD viewport offset: shiftX=-9 (vertical/down), shiftY=+8 (horizontal/left)** — the 90° rotation swaps axes in CoreGraphics.
- **Auto-trim transparency**: .icns files have varying internal padding. ImageLoader scans for non-transparent pixel bounds and crops before centering. Without this, icons with more padding appear offset.
- **4px margin** around trimmed icon content within the output image.
- **Black background** fill for transparency in .icns source files.
- Different .icns files still have slightly different artwork proportions — perfect alignment across all keys requires custom uniform icons.
- Previous corruption was caused by the sendPacket report-ID stripping bug, not the BAT protocol itself.

## osascript Blocks CFRunLoop
Do NOT call osascript (Process with waitUntilExit) on the main thread — it blocks the CFRunLoop and freezes all HID event delivery. Either use a background DispatchQueue or (better) avoid osascript entirely. For volume control, use NSEvent media key simulation instead.

## Volume Control — Use CoreAudio API
Three approaches tried, in order:
1. **osascript** — blocks CFRunLoop, no HUD from daemon context. Rejected.
2. **NSEvent media key simulation** — works + shows HUD, but requires Accessibility permission. macOS TCC invalidates trust on every binary replacement (CDHash changes), causing silent failure after every reinstall. Rejected.
3. **CoreAudio `kAudioDevicePropertyVolumeScalar`** — direct API, no permissions needed, survives binary replacement. No HUD overlay but reliable. Set on all channels (master/left/right) for compatibility. This is what we use.

## Chrome Tab Groups — Not Accessible via CLI
Chrome's saved tab groups cannot be opened from command line, AppleScript, or extensions. This is an intentional Chrome limitation. Best you can do is `open -a "Google Chrome"` to bring it to front.

## Device Power Cycle
If the device gets into a bad state (commands accepted but no events returned), unplug for 5-10 seconds to reset firmware. A quick replug may not be enough.

## Config Key Mapping
JSON config uses underscored keys (lcd_1, btn_1, small_1) but Swift enum rawValues are camelCase (lcd1, btn1, small1). The `configKey` computed property on ButtonID/KnobID handles this mapping. Do not use `rawValue` for config lookups.
