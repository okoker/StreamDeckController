// TreasLin N3 / CRT protocol layer

// MARK: - Device constants

enum Deck {
    static let vendorID: Int  = 0x5548
    static let productID: Int = 0x1001
    static let usagePage: Int = 0xFFA0
    static let usage: Int     = 0x0001
    static let packetSize: Int = 1025   // 1 byte report ID + 1024 data
}

// MARK: - Packet builders

enum CRTCommand {

    // Private helper: builds the full 1025-byte packet.
    // Layout: [0x00] [CRT\0\0] [cmd bytes...] [zero-pad to 1025]
    private static func makePacket(cmd: [UInt8]) -> [UInt8] {
        let header: [UInt8] = [0x00,           // report ID
                               0x43, 0x52, 0x54, 0x00, 0x00]  // "CRT\0\0"
        var packet = header + cmd
        if packet.count < Deck.packetSize {
            packet += [UInt8](repeating: 0x00, count: Deck.packetSize - packet.count)
        }
        return packet
    }

    /// Wake / display-on command (DIS)
    static func makeDIS() -> [UInt8] {
        makePacket(cmd: [0x44, 0x49, 0x53])
    }

    /// Set brightness (LIG)
    static func makeLIG(_ brightness: UInt8) -> [UInt8] {
        makePacket(cmd: [0x4C, 0x49, 0x47, 0x00, 0x00, brightness])
    }

    /// Refresh / commit frame (STP)
    static func makeSTP() -> [UInt8] {
        makePacket(cmd: [0x53, 0x54, 0x50])
    }

    /// Clear all LCD regions (CLE)
    static func makeCLE() -> [UInt8] {
        makePacket(cmd: [0x43, 0x4C, 0x45, 0x00, 0x00, 0x00, 0xFF])
    }

    /// Keepalive (CONNECT)
    static func makeCONNECT() -> [UInt8] {
        makePacket(cmd: [0x43, 0x4F, 0x4E, 0x4E, 0x45, 0x43, 0x54])
    }

    /// BAT image header — begins image transfer for a key (0-indexed input, sent as 1-indexed)
    static func makeBAT(imageLength: Int, keyIndex: Int) -> [UInt8] {
        let lenHi = UInt8((imageLength >> 8) & 0xFF)
        let lenLo = UInt8(imageLength & 0xFF)
        let key = UInt8(keyIndex + 1)  // protocol uses 1-indexed keys
        return makePacket(cmd: [0x42, 0x41, 0x54, 0x00, 0x00, lenHi, lenLo, key])
    }

    /// Raw image data chunk — no CRT prefix, just report ID + payload
    static func makeDataChunk(data: [UInt8]) -> [UInt8] {
        var packet = [UInt8(0x00)] + data
        if packet.count < Deck.packetSize {
            packet += [UInt8](repeating: 0x00, count: Deck.packetSize - packet.count)
        }
        return packet
    }
}

// MARK: - Event types

enum ButtonID: String {
    case lcd1, lcd2, lcd3, lcd4, lcd5, lcd6
    case btn1, btn2, btn3

    var configKey: String {
        switch self {
        case .lcd1: return "lcd_1"
        case .lcd2: return "lcd_2"
        case .lcd3: return "lcd_3"
        case .lcd4: return "lcd_4"
        case .lcd5: return "lcd_5"
        case .lcd6: return "lcd_6"
        case .btn1: return "btn_1"
        case .btn2: return "btn_2"
        case .btn3: return "btn_3"
        }
    }
}

enum KnobID: String {
    case big, small1, small2

    var configKey: String {
        switch self {
        case .big: return "big"
        case .small1: return "small_1"
        case .small2: return "small_2"
        }
    }
}

enum DeckEvent {
    case buttonPress(ButtonID)
    case buttonRelease(ButtonID)
    case knobRotateCW(KnobID)
    case knobRotateCCW(KnobID)
    case knobPress(KnobID)
    case knobRelease(KnobID)
}

// MARK: - Event parser

enum DeckEventParser {

    /// Parse a raw HID report into a DeckEvent.
    /// Returns nil for unrecognised or malformed packets.
    static func parse(data: [UInt8]) -> DeckEvent? {
        guard data.count >= 11 else { return nil }

        // Verify ACK prefix: "ACK" = 0x41 0x43 0x4B
        guard data[0] == 0x41, data[1] == 0x43, data[2] == 0x4B else { return nil }

        let eventCode = data[9]
        let state     = data[10]

        // ── Button press / release ──────────────────────────────────────────
        let buttonMap: [UInt8: ButtonID] = [
            0x01: .lcd1, 0x02: .lcd2, 0x03: .lcd3,
            0x04: .lcd4, 0x05: .lcd5, 0x06: .lcd6,
            0x25: .btn1, 0x30: .btn2, 0x31: .btn3
        ]
        if let buttonID = buttonMap[eventCode] {
            switch state {
            case 0x01: return .buttonPress(buttonID)
            case 0x00: return .buttonRelease(buttonID)
            default:   return nil
            }
        }

        // ── Knob press / release ────────────────────────────────────────────
        let knobPressMap: [UInt8: KnobID] = [
            0x35: .big, 0x33: .small1, 0x34: .small2
        ]
        if let knobID = knobPressMap[eventCode] {
            switch state {
            case 0x01: return .knobPress(knobID)
            case 0x00: return .knobRelease(knobID)
            default:   return nil
            }
        }

        // ── Knob rotation (state is always 0x00 for rotation events) ────────
        switch eventCode {
        case 0x50: return .knobRotateCCW(.big)
        case 0x51: return .knobRotateCW(.big)
        case 0x90: return .knobRotateCCW(.small1)
        case 0x91: return .knobRotateCW(.small1)
        case 0x60: return .knobRotateCCW(.small2)
        case 0x61: return .knobRotateCW(.small2)
        default:   return nil
        }
    }
}
