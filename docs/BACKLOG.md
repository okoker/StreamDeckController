# Backlog

Items discovered during builds, reviews, or revisits. Not blocking current work.
Promote to `TODO.md` when ready to tackle.

Use priority tags: `[P0]` `[P1]` `[P2]` and domain tags: `[security]` `[feature]` `[bug]` `[debt]`

---

### Fixed (01/04/2026)

- ~~[P0] [security] Config permissions: reject load when writable/wrong owner/symlink. `main.swift`~~
- ~~[P0] [bug] SIGHUP reload race: explicit `shutdown()` before replacing dispatcher. `main.swift`~~
- ~~[P1] [debt] `reportBuffer` replaced with `UnsafeMutablePointer`. `HIDDevice.swift`~~
- ~~[P1] [debt] `Unmanaged.passUnretained` lifetime documented. `HIDDevice.swift`~~
- ~~[P1] [security] HID input report: check `IOReturn` result + min length. `HIDDevice.swift`~~
- ~~[P1] [bug] Shell timeout (30s) + stderr handler cleanup in catch. `ActionDispatcher.swift`~~

### Fixed (02/04/2026)

- ~~[P1] [debt] `key:` silent failure: `AXIsProcessTrusted()` check at startup with clear log message. `ActionDispatcher.swift`~~
- ~~[P1] [bug] Pipe deadlock: read stdout before `waitUntilExit()` in `runProcess`. `BrightnessControl.swift`~~
- ~~[P1] [bug] Stale display mapping: `refreshDisplays()` on mode cycle + cache invalidation on write failure. `BrightnessControl.swift`~~
- ~~[P2] [debt] Icon size cap: reject source images >1024px before full decode. `ImageLoader.swift`~~

### Open

_(No items)_
