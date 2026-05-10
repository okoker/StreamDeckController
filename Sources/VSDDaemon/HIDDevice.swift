import Foundation
import IOKit
import IOKit.hid

final class HIDDevice {

    // MARK: - Properties

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var keepaliveTimer: Timer?
    // Stable allocation for IOKit input report writes. Must outlive the
    // IOHIDDeviceRegisterInputReportCallback registration (i.e. process lifetime).
    private let reportBuffer: UnsafeMutablePointer<UInt8>
    private let reportBufferSize = 512
    private var config: DeckConfig

    var onEvent: ((DeckEvent) -> Void)?

    // MARK: - Init

    init(config: DeckConfig) {
        self.config = config
        self.reportBuffer = .allocate(capacity: 512)
        self.reportBuffer.initialize(repeating: 0, count: 512)
    }

    // MARK: - Public API

    /// Hot-reload config: update action mappings and resend LCD icons
    func reloadConfig(_ newConfig: DeckConfig) {
        self.config = newConfig
        guard device != nil else { return }
        sendPacket(CRTCommand.makeCLE())
        sendLCDIcons()
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        // Build matching dictionary — all four keys must match
        let match: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String:  Deck.vendorID,
                kIOHIDProductIDKey as String: Deck.productID,
                kIOHIDDeviceUsagePageKey as String: Deck.usagePage,
                kIOHIDDeviceUsageKey as String: Deck.usage
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, match as CFArray)

        // SAFETY: HIDDevice is created once in main.swift and lives for the
        // entire process. passUnretained is safe because `self` outlives the
        // IOKit manager. Do NOT create/destroy HIDDevice dynamically without
        // switching to passRetained + explicit release.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Register device matching callback
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchingCallback, selfPtr)

        // Register device removal callback
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovalCallback, selfPtr)

        // Schedule with the current run loop (MUST be main thread run loop)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Open
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("Error: IOHIDManagerOpen failed with code \(openResult)")
        }
    }

    func sendPacket(_ data: [UInt8]) {
        guard !data.isEmpty else { return }
        guard let device = device else { return }
        // Report ID is byte 0; IOKit expects data WITHOUT the report ID byte
        let reportID = CFIndex(data[0])
        let payload = Array(data.dropFirst())  // skip report ID
        payload.withUnsafeBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return }
            let result = IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                reportID,
                ptr,
                buf.count
            )
            if result != kIOReturnSuccess {
                print("Warning: sendPacket failed with code \(result)")
            }
        }
    }

    // MARK: - Device lifecycle (called from C callbacks)

    fileprivate func handleDeviceConnected(_ hidDevice: IOHIDDevice) {
        self.device = hidDevice

        // Register input report callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            hidDevice,
            reportBuffer,
            reportBufferSize,
            inputReportCallback,
            selfPtr
        )

        // Send initialisation sequence
        sendPacket(CRTCommand.makeDIS())
        sendPacket(CRTCommand.makeLIG(UInt8(clamping: config.brightness)))
        sendPacket(CRTCommand.makeSTP())
        sendPacket(CRTCommand.makeCLE())

        // Send LCD icons (after init, before keepalive)
        sendLCDIcons()

        // Start keepalive timer (every 5 seconds)
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sendPacket(CRTCommand.makeCONNECT())
        }

        print("Device connected")
    }

    // MARK: - LCD image sending

    private func sendLCDIcons() {
        let lcdKeys: [(String, Int)] = [
            ("lcd_1", 0), ("lcd_2", 1), ("lcd_3", 2),
            ("lcd_4", 3), ("lcd_5", 4), ("lcd_6", 5)
        ]
        var sent = 0
        for (configKey, keyIndex) in lcdKeys {
            guard let buttonConfig = config.buttons[configKey],
                  let iconPath = buttonConfig.icon else { continue }
            guard let jpegData = ImageLoader.loadAsJPEG(path: iconPath) else {
                print("Warning: failed to load icon for \(configKey): \(iconPath)")
                continue
            }
            sendKeyImage(keyIndex: keyIndex, jpegData: jpegData)
            sent += 1
            print("Sent icon for \(configKey) (\(jpegData.count) bytes)")
        }
        if sent > 0 {
            sendPacket(CRTCommand.makeSTP())
            print("LCD icons committed")
        }
    }

    private func sendKeyImage(keyIndex: Int, jpegData: Data) {
        let bytes = [UInt8](jpegData)

        guard bytes.count <= 65535 else {
            print("Warning: icon JPEG too large (\(bytes.count) bytes, max 65535) for key \(keyIndex)")
            return
        }

        // BAT header with image length and key index
        sendPacket(CRTCommand.makeBAT(imageLength: bytes.count, keyIndex: keyIndex))

        // Send raw JPEG data in 1024-byte chunks
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 1024, bytes.count)
            let chunk = Array(bytes[offset..<end])
            sendPacket(CRTCommand.makeDataChunk(data: chunk))
            offset = end
        }
    }

    fileprivate func handleDeviceRemoved() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        device = nil
        print("Device disconnected, waiting for reconnect...")
    }

    fileprivate func handleInputReport(_ report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
        if let event = DeckEventParser.parse(data: bytes) {
            onEvent?(event)
        }
    }
}

// MARK: - C function pointer callbacks (free functions)

private func deviceMatchingCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context = context else { return }
    let hidDevice = Unmanaged<HIDDevice>.fromOpaque(context).takeUnretainedValue()
    hidDevice.handleDeviceConnected(device)
}

private func deviceRemovalCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context = context else { return }
    let hidDevice = Unmanaged<HIDDevice>.fromOpaque(context).takeUnretainedValue()
    hidDevice.handleDeviceRemoved()
}

private func inputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard result == kIOReturnSuccess else { return }
    guard reportLength >= 11 else { return }
    guard let context = context else { return }
    let hidDevice = Unmanaged<HIDDevice>.fromOpaque(context).takeUnretainedValue()
    hidDevice.handleInputReport(report, length: reportLength)
}
