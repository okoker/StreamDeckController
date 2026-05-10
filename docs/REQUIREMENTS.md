# StreamDeckController — Requirements

## Overview
Lightweight macOS daemon (Swift) that communicates with a TreasLin N3 stream deck (VID 0x5548, PID 0x1001) over USB HID. Reads button/knob events, maps them to configurable actions. No GUI — configured via JSON file.

## Device
- **6 LCD buttons** (event codes 0x01–0x06, press + release)
- **3 round buttons** (event codes 0x25, 0x30, 0x31, press + release)
- **3 rotary knobs** (each: clockwise, counter-clockwise, press + release)
  - Big knob: rotate 0x50/0x51, press 0x35
  - Small knob 1: rotate 0x90/0x91, press 0x33
  - Small knob 2: rotate 0x60/0x61, press 0x34

## Protocol (proven working)
- USB HID vendor interface: usage page 0xFFA0, usage 0x0001
- Packet size: 1025 bytes (0x00 report ID + 1024 data)
- Init sequence: CRT DIS → CRT LIG → CRT STP → CRT CLE
- Keepalive: CRT CONNECT every 5 seconds
- Input: 512-byte packets prefixed with "ACK\0\0OK\0\0", event at byte[9], state at byte[10]
- macOS requires CFRunLoop running for IOKit HID input delivery

## Configuration
Single JSON file (`config.json`) in the app's directory. Daemon reads on startup. Edit file and restart daemon to apply changes.

### Structure
```json
{
  "brightness": 50,
  "buttons": {
    "lcd_1": { "action": "shell:open -a Safari", "icon": "icons/safari.png" },
    "lcd_2": { "action": "shell:open -a Terminal" },
    "lcd_3": { "action": "key:cmd+shift+4" },
    "lcd_4": { "action": "none" },
    "lcd_5": { "action": "none" },
    "lcd_6": { "action": "none" },
    "btn_1": { "action": "shell:echo hello" },
    "btn_2": { "action": "none" },
    "btn_3": { "action": "none" }
  },
  "knobs": {
    "big": {
      "rotate": { "action": "system_volume", "step": 5 },
      "press":  { "action": "system_mute_toggle" }
    },
    "small_1": {
      "rotate": { "action": "zr7_volume", "step": 3 },
      "press":  { "action": "zr7_mute_toggle" }
    },
    "small_2": {
      "rotate": { "action": "display_brightness", "step": 5 },
      "press":  { "action": "display_brightness_cycle" }
    }
  },
  "displays": [
    { "name": "Left",  "serial": "AN_SERIAL_FROM_M1DDC" },
    { "name": "Right", "serial": "AN_SERIAL_FROM_M1DDC" }
  ]
}
```

## Actions

| Action | Description |
|--------|-------------|
| `shell:<command>` | Execute shell command |
| `key:<shortcut>` | Simulate keyboard shortcut (e.g. `cmd+shift+4`) |
| `system_volume` | Adjust macOS system volume by ±step per tick |
| `system_mute_toggle` | Toggle system mute (daemon tracks state, syncs with actual) |
| `zr7_volume` | Adjust ZR7Player volume by ±step per tick (interface TBD) |
| `zr7_mute_toggle` | Toggle ZR7Player mute (interface TBD) |
| `display_brightness` | Adjust external monitor brightness by ±step per tick (DDC/CI via m1ddc) |
| `display_brightness_cycle` | Cycle brightness target: All → per-display → All (30 s auto-revert) |
| `none` | No action |

## External Monitor Brightness (DDC/CI)

macOS has no native support for controlling brightness on non-Apple external displays. The built-in brightness keys and Control Centre slider only work on the internal panel and Apple-branded monitors (e.g. Apple Studio Display, Pro Display XDR). Third-party displays — including high-end LG, Dell, and Samsung panels connected via USB-C or DisplayPort — are invisible to macOS brightness controls.

The industry-standard workaround is **DDC/CI** (Display Data Channel / Command Interface), a protocol where the OS sends commands over the display cable to adjust settings like brightness and contrast. On Apple Silicon Macs, [`m1ddc`](https://github.com/waydabber/m1ddc) is the most reliable DDC/CI CLI tool (works on M1–M4, all variants despite the name).

### How it works in this daemon

- Optional `displays` array in config maps friendly names to monitor AN Serials (from `m1ddc display list detailed`)
- At startup, the daemon resolves serials to current m1ddc display numbers (handles reboot shuffling)
- Knob rotation fires async `m1ddc set luminance` calls with debouncing (80 ms) to keep the knob responsive
- Knob press cycles the brightness target: All connected displays → each display individually → back to All
- After 30 seconds of inactivity, the target auto-reverts to All
- A floating HUD overlay (80 pt text) appears on all screens showing current brightness and target mode
- Brightness is read from hardware on first interaction after idle, then cached during active use to avoid flaky DDC/CI reads

### Known DDC/CI quirks

- LG monitors do **not** show their native OSD bar for DDC/CI brightness changes (only for physical button presses) — hence the custom HUD
- `m1ddc get luminance` can return stale values on some LG models — the daemon reads once then tracks state internally
- `m1ddc chg luminance` (relative change) is unreliable on some LG panels — the daemon uses absolute `set luminance` instead
- Display numbers from `m1ddc` can change across reboots — the daemon matches by serial number, not display number

### Dependency

`m1ddc` is the only external dependency. Install via `brew install m1ddc`. Without it, all other daemon features work — brightness actions simply log a warning.

## LCD Icons (phase 2)
- Optional `icon` field per LCD button in config
- On startup, daemon sends each icon to the device via CRT BAT protocol
- Images resized to 64x64 JPEG, rotated -90°
- No icon = cleared/blank

## Daemon Behaviour
- Runs as background process (launchd plist for auto-start)
- Connects to device on startup, reconnects on USB replug
- Sends init sequence, then listens for events
- Sends CONNECT keepalive every 5 seconds
- On button press: executes mapped action (ignores release events for buttons)
- On knob rotate: applies ±step for each tick
- On knob press: toggles mute state
- Logs to stdout/file for debugging
- Graceful shutdown on SIGTERM/SIGINT

## Safety Constraints
- **HID isolation**: MUST only open the device matching VID 0x5548 / PID 0x1001 on usage page 0xFFA0. Never enumerate, open, or interfere with any other HID device (keyboards, mice, trackpads, etc.)
- **No kernel driver manipulation**: MUST NOT unload, detach, or modify any macOS kernel drivers or kexts. The daemon operates purely in userspace via IOKit HID API
- **USB passivity**: MUST NOT send USB control transfers, reset devices, or alter USB configuration of any device other than the target deck
- **launchd safety**: The launchd plist MUST only manage this daemon's own process. No modification of other launchd jobs, plists, or system services. Use `LaunchAgents` (user-level), never `LaunchDaemons` (system-level)
- **Shell command sandboxing**: `shell:` actions run with the user's normal permissions. The daemon itself requires no elevated privileges (no sudo, no root)
- **Graceful failure**: If the device is not connected, the daemon waits quietly and retries. No error storms, no resource hogging, no interference with other USB devices

## Non-Goals (for now)
- No GUI
- No CLI config tool
- Hot-reload supported via SIGHUP (`killall -HUP StreamDeckController`)
- No multi-deck support (multiple stream decks plugged in simultaneously)
- No Windows/Linux support
