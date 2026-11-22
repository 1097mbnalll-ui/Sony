// SPDX-License-Identifier: AGPL-3.0-only
import CoreGraphics
import Foundation

/// A console that finished registration. Keys are stored in the Keychain.
struct Console: Codable, Identifiable, Equatable {
    var id: String          // MAC address hex (stable)
    var name: String
    var host: String        // last known IPv4
    var ps5: Bool
    var registKey: Data     // 16 bytes
    var morning: Data       // 16 bytes
}

struct DiscoveredHost: Identifiable, Equatable {
    enum State { case unknown, ready, standby }
    var id: String { addr }
    var addr: String
    var name: String
    var hostId: String
    var ps5: Bool
    var state: State
    var runningApp: String
    var lastSeen: Date

    init(_ h: TrjmFoundHost) {
        addr = stringFromCTuple(h.addr)
        name = stringFromCTuple(h.name)
        hostId = stringFromCTuple(h.host_id)
        ps5 = h.ps5
        runningApp = stringFromCTuple(h.running_app_name)
        switch h.state {
        case TRJM_HOST_READY: state = .ready
        case TRJM_HOST_STANDBY: state = .standby
        default: state = .unknown
        }
        lastSeen = Date()
    }
}

/// Registered consoles + PSN account id, persisted in the Keychain.
final class ConsoleStore: ObservableObject {
    @Published private(set) var consoles: [Console] = []
    @Published var accountIdBase64: String = "" {
        didSet { Keychain.setString(accountIdBase64.isEmpty ? nil : accountIdBase64, for: "psn_account_id") }
    }

    init() {
        if let data = Keychain.get("consoles"),
           let list = try? JSONDecoder().decode([Console].self, from: data) {
            consoles = list
        }
        accountIdBase64 = Keychain.getString("psn_account_id") ?? ""
    }

    /// 8-byte PSN account id, if the stored value is valid.
    var accountId: Data? {
        guard let d = Data(base64Encoded: accountIdBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              d.count == 8 else { return nil }
        return d
    }

    var current: Console? { consoles.first }

    /// Account id read straight from the Keychain (usable off the main thread).
    static var storedAccountId: Data? {
        guard let s = Keychain.getString("psn_account_id"),
              let d = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              d.count == 8 else { return nil }
        return d
    }

    func upsert(_ c: Console) {
        consoles.removeAll { $0.id == c.id }
        consoles.insert(c, at: 0)
        save()
    }

    func updateHost(id: String, host: String) {
        guard let i = consoles.firstIndex(where: { $0.id == id }), consoles[i].host != host else { return }
        consoles[i].host = host
        save()
    }

    func remove(_ c: Console) {
        consoles.removeAll { $0.id == c.id }
        save()
    }

    private func save() {
        Keychain.set(try? JSONEncoder().encode(consoles), for: "consoles")
    }
}

/// Non-secret preferences.
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    // stream
    @Published var resolution: Int { didSet { d.set(resolution, forKey: "resolution") } }
    @Published var fps: Int { didSet { d.set(fps, forKey: "fps") } }
    @Published var useHEVC: Bool { didSet { d.set(useHEVC, forKey: "hevc") } }

    // translation
    @Published var autoTranslate: Bool { didSet { d.set(autoTranslate, forKey: "autoTranslate") } }
    @Published var autoSpeak: Bool { didSet { d.set(autoSpeak, forKey: "autoSpeak") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    @Published var gameName: String { didSet { d.set(gameName, forKey: "gameName") } }
    /// Dialogue region, normalized, origin top-left.
    @Published var region: CGRect {
        didSet { d.set([region.minX, region.minY, region.width, region.height], forKey: "region") }
    }

    static let defaultRegion = CGRect(x: 0.08, y: 0.72, width: 0.84, height: 0.24)

    init() {
        let d = UserDefaults.standard
        resolution = d.object(forKey: "resolution") as? Int ?? 720
        fps = d.object(forKey: "fps") as? Int ?? 30
        useHEVC = d.object(forKey: "hevc") as? Bool ?? false
        autoTranslate = d.object(forKey: "autoTranslate") as? Bool ?? true
        autoSpeak = d.object(forKey: "autoSpeak") as? Bool ?? false
        fontSize = d.object(forKey: "fontSize") as? Double ?? 24
        gameName = d.string(forKey: "gameName") ?? ""
        if let r = d.array(forKey: "region") as? [Double], r.count == 4, r[2] > 0.02, r[3] > 0.02 {
            region = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
        } else {
            region = AppSettings.defaultRegion
        }
    }
}
