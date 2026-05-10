import Foundation

final class BrightnessControl {

    // MARK: - Types

    struct ConnectedDisplay {
        let name: String
        let serial: String
        let m1ddcIndex: Int
        let cgDisplayID: UInt32
        var brightness: Int       // 0–100, cached
    }

    enum TargetMode: Equatable {
        case all
        case single(Int)          // index into connectedDisplays
    }

    // MARK: - Properties

    private let m1ddcPath: String
    private let configuredDisplays: [DisplayConfig]
    private(set) var connectedDisplays: [ConnectedDisplay] = []
    private var targetMode: TargetMode = .all
    private var cacheValid = false

    private let queue = DispatchQueue(label: "streamdeck.brightness")
    private let writeQueue = DispatchQueue(label: "streamdeck.m1ddc.write", qos: .userInteractive)
    private var inactivityTimer: DispatchSourceTimer?
    private var debounceTimer: DispatchSourceTimer?
    private var pendingDelta: Int = 0

    private static let inactivityTimeout: TimeInterval = 30
    private static let debounceInterval: TimeInterval = 0.08

    // MARK: - Init

    init?(displays: [DisplayConfig]) {
        guard !displays.isEmpty else {
            print("BrightnessControl: no displays configured")
            return nil
        }
        guard let path = Self.findM1DDC() else {
            print("BrightnessControl: m1ddc not found — install with 'brew install m1ddc'")
            return nil
        }
        self.m1ddcPath = path
        self.configuredDisplays = displays
        refreshDisplays()
        if connectedDisplays.isEmpty {
            print("BrightnessControl: no configured displays are currently connected")
        }
    }

    deinit {
        inactivityTimer?.cancel()
        debounceTimer?.cancel()
    }

    /// Graceful teardown — cancel timers on their own queue (thread-safe).
    /// Called before replacing the dispatcher on SIGHUP reload.
    func shutdown() {
        queue.sync {
            inactivityTimer?.cancel()
            inactivityTimer = nil
            debounceTimer?.cancel()
            debounceTimer = nil
        }
    }

    // MARK: - Public API

    func adjust(step: Int) {
        queue.async { [self] in
            pendingDelta += step
            resetInactivityTimer()
            scheduleDebounce()
        }
    }

    func cycleMode() {
        queue.async { [self] in
            // Refresh display mapping on each cycle — handles hot-plug/renumber
            refreshDisplays()
            guard !connectedDisplays.isEmpty else { return }

            switch targetMode {
            case .all:
                targetMode = .single(0)
            case .single(let idx):
                let next = idx + 1
                targetMode = next < connectedDisplays.count ? .single(next) : .all
            }

            // Show mode label IMMEDIATELY — don't block on hardware reads
            let label = currentModeLabel()
            DispatchQueue.main.async {
                BrightnessHUD.show(text: "◉ \(label)")
            }

            // Cache was already synced by refreshDisplays above
            cacheValid = true

            let targets = currentTargetIndices()
            let brightness = targets.isEmpty ? 0 : connectedDisplays[targets[0]].brightness
            DispatchQueue.main.async {
                BrightnessHUD.show(text: "◉ \(label)  \(brightness)%")
            }

            resetInactivityTimer()
        }
    }

    // MARK: - Display discovery

    func refreshDisplays() {
        guard let output = runProcess(m1ddcPath, args: ["display", "list", "detailed"]) else {
            print("BrightnessControl: failed to list displays")
            return
        }

        let blocks = parseDisplayBlocks(output)

        var connected: [ConnectedDisplay] = []
        for cfg in configuredDisplays {
            if let block = blocks.first(where: { $0.anSerial == cfg.serial }) {
                let brightness = readBrightness(displayNumber: block.number)
                connected.append(ConnectedDisplay(
                    name: cfg.name, serial: cfg.serial,
                    m1ddcIndex: block.number,
                    cgDisplayID: block.displayID,
                    brightness: brightness))
                print("BrightnessControl: \(cfg.name) (\(cfg.serial)) → display \(block.number), brightness \(brightness)")
            } else {
                print("BrightnessControl: \(cfg.name) (\(cfg.serial)) not connected")
            }
        }
        connectedDisplays = connected
        targetMode = .all
        cacheValid = true
    }

    // MARK: - m1ddc parsing

    private struct DisplayBlock {
        let number: Int
        let anSerial: String
        let displayID: UInt32
    }

    private func parseDisplayBlocks(_ output: String) -> [DisplayBlock] {
        var blocks: [DisplayBlock] = []
        var curNum: Int?
        var curSerial: String?
        var curDisplayID: UInt32?

        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)

            if let r = t.range(of: #"^\[(\d+)\]"#, options: .regularExpression) {
                if let n = curNum, let s = curSerial, let d = curDisplayID {
                    blocks.append(DisplayBlock(number: n, anSerial: s, displayID: d))
                }
                curNum = Int(t[r].dropFirst().dropLast())
                curSerial = nil
                curDisplayID = nil
            }
            if t.hasPrefix("- AN Serial:") {
                curSerial = t.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            }
            if t.hasPrefix("- Display ID:") {
                if let s = t.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) {
                    curDisplayID = UInt32(s)
                }
            }
        }
        if let n = curNum, let s = curSerial, let d = curDisplayID {
            blocks.append(DisplayBlock(number: n, anSerial: s, displayID: d))
        }
        return blocks
    }

    // MARK: - Brightness operations

    private func readBrightness(displayNumber: Int) -> Int {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let output = runProcess(m1ddcPath, args: ["display", "\(displayNumber)", "get", "luminance"]) else {
            return 50
        }
        let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        let val = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50
        print("BrightnessControl: read display \(displayNumber) → \(val) (\(ms)ms)")
        return val
    }

    private func syncCacheFromHardware() {
        for idx in currentTargetIndices() {
            connectedDisplays[idx].brightness = readBrightness(displayNumber: connectedDisplays[idx].m1ddcIndex)
        }
        cacheValid = true
    }

    /// Async write — doesn't block caller. Invalidates cache on failure.
    private func writeBrightnessAsync(displayNumber: Int, value: Int) {
        let path = m1ddcPath
        writeQueue.async { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["display", "\(displayNumber)", "set", "luminance", "\(value)"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    print("BrightnessControl: m1ddc set failed (exit \(proc.terminationStatus)) for display \(displayNumber)")
                    self?.queue.async { self?.cacheValid = false }
                }
            } catch {
                print("BrightnessControl: m1ddc launch failed: \(error)")
                self?.queue.async { self?.cacheValid = false }
            }
        }
    }

    private func applyPendingDelta() {
        let delta = pendingDelta
        pendingDelta = 0
        guard delta != 0 else { return }

        let targets = currentTargetIndices()
        guard !targets.isEmpty else { return }

        // First interaction after idle → read real brightness from hardware
        if !cacheValid {
            syncCacheFromHardware()
        }

        for idx in targets {
            let newVal = max(0, min(100, connectedDisplays[idx].brightness + delta))
            if newVal != connectedDisplays[idx].brightness {
                writeBrightnessAsync(displayNumber: connectedDisplays[idx].m1ddcIndex, value: newVal)
                connectedDisplays[idx].brightness = newVal
            }
        }

        let brightness = connectedDisplays[targets[0]].brightness
        let label = currentModeLabel()

        DispatchQueue.main.async {
            BrightnessHUD.show(text: "☀ \(brightness)%  \(label)")
        }
    }

    // MARK: - Target helpers

    private func currentTargetIndices() -> [Int] {
        switch targetMode {
        case .all:
            return Array(connectedDisplays.indices)
        case .single(let idx):
            return idx < connectedDisplays.count ? [idx] : []
        }
    }

    private func currentModeLabel() -> String {
        switch targetMode {
        case .all:
            return "All"
        case .single(let idx):
            return idx < connectedDisplays.count ? connectedDisplays[idx].name : "?"
        }
    }

    // MARK: - Timers

    private func resetInactivityTimer() {
        inactivityTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.inactivityTimeout)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.cacheValid = false
            if self.targetMode != .all {
                self.targetMode = .all
                DispatchQueue.main.async {
                    BrightnessHUD.show(text: "◉ All")
                }
                print("BrightnessControl: inactivity → reverted to all displays")
            }
        }
        timer.resume()
        inactivityTimer = timer
    }

    private func scheduleDebounce() {
        guard debounceTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.debounceInterval)
        timer.setEventHandler { [weak self] in
            self?.applyPendingDelta()
            self?.debounceTimer = nil
        }
        timer.resume()
        debounceTimer = timer
    }

    // MARK: - Process helpers

    private func runProcess(_ path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            // Read stdout BEFORE waitUntilExit to avoid pipe buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func findM1DDC() -> String? {
        ["/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
