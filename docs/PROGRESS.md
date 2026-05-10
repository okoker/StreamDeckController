# Progress

## Current Status
v2 daemon running as launchd service. All buttons, knobs, LCD icons, system volume, and ZR7 volume working.

## Active Work
_(None)_

## Completed
- Phase 1: Core daemon — HID device, CRT protocol, event parsing, action dispatch
- Phase 2: LCD key icons via BAT protocol (85x85, auto-trim transparency, calibrated viewport offset)
- ZR7Player volume/mute via DistributedNotifications (com.zr7.volumeUp/Down/muteToggle)
- SIGHUP config hot-reload (new action mappings + LCD icons without restart)
- launchd daemon installed: ~/Library/Application Support/StreamDeckController/, ~/.config/vsd/config.json
- Volume control via NSEvent media key simulation (shows HUD)
- Bug fixes: sendPacket report ID stripping, configKey mapping, CFRunLoop requirement

## Completed Phases
_(Completed phases move to `old_progress/XX_phase_name.md`)_
