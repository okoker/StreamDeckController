# Known Issues

Edge cases, uncertain solutions, and accepted limitations we're aware of but not ready to act on.

- **Know what to do, just not now?** → `BACKLOG.md`
- **Don't know the fix / need more info / accepting for now?** → here.

When ready to address: move to `BACKLOG.md` or `TODO.md`, delete from here.

---

| ID | Date | Description |
|----|------|-------------|
| KI-001 | 27/03/2026 | macOS IOKit HID requires CFRunLoop running for input report delivery — Swift uses CFRunLoopRun() on main thread |
| ~~KI-002~~ | 27/03/2026 | ~~ZR7Player volume IPC~~ — Resolved: DistributedNotifications (com.zr7.volumeUp/Down/muteToggle) |
| ~~KI-003~~ | 27/03/2026 | ~~configKey mismatch~~ — Resolved: configKey property wired into dispatcher |
| ~~KI-004~~ | 27/03/2026 | ~~BAT image protocol~~ — Resolved: working, previous corruption was sendPacket report-ID bug |
| KI-005 | 27/03/2026 | IOHIDDeviceSetReport requires data WITHOUT report ID prefix byte — unlike hidapi which includes it. Fixed in sendPacket but be aware when adding new packet types |

## Accepted Risks

| ID | Date | Description |
|----|------|-------------|
| KI-006 | 01/04/2026 | USB device spoofing: device matching trusts VID/PID only. A spoofed USB device with matching IDs could drive configured actions. Accepted: requires physical access to plug in a malicious device, and actions are limited to user-level privileges. No device-specific handshake available in hardware. |
| KI-007 | 01/04/2026 | Optimistic brightness cache: HUD shows brightness value before async m1ddc write confirms success. If m1ddc fails silently, displayed value may not match hardware. Accepted: m1ddc failures are rare in practice and cache re-syncs on next idle→active transition. |
