import Foundation

struct DisplayConfig: Codable {
    let name: String
    let serial: String          // AN Serial from `m1ddc display list detailed`
}

struct DeckConfig: Codable {
    let brightness: Int
    let buttons: [String: ButtonConfig]
    let knobs: [String: KnobConfig]
    let displays: [DisplayConfig]?

    static func load(from path: String) -> DeckConfig? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            print("Error: config file not found at \(path)")
            return nil
        }
        do {
            return try JSONDecoder().decode(DeckConfig.self, from: data)
        } catch {
            print("Error: failed to parse config at \(path): \(error)")
            return nil
        }
    }
}

struct ButtonConfig: Codable {
    let action: String
    let icon: String?
}

struct KnobConfig: Codable {
    let rotate: KnobAction
    let press: KnobAction
}

struct KnobAction: Codable {
    let action: String
    let step: Int?
}
