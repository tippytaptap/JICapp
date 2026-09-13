import Foundation

struct WatchPrayer: Codable, Identifiable {
    let name: String
    let at: Double
    var id: String { "\(name)-\(at)" }
    var date: Date { Date(timeIntervalSince1970: at / 1000) }
}
struct WatchPrayerTimeline: Codable {
    let organisation: String
    let timeZone: String
    let prayers: [WatchPrayer]
    static func parse(_ raw: String) -> WatchPrayerTimeline? {
        guard raw.utf8.count <= 24000, let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data), !value.organisation.isEmpty, value.organisation.count <= 120, value.timeZone.count <= 80, value.prayers.count <= 100, value.prayers.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 80 && $0.at >= 0 && $0.at <= 4102444800000 }) else { return nil }
        return value
    }
}
struct WatchCounter: Codable {
    let sourceId: String
    let sessionId: String
    let revision: Int
    let count: Int
    let target: Int
    static func parse(_ raw: String) -> WatchCounter? {
        guard raw.utf8.count <= 2000, let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data), !value.sourceId.isEmpty, value.sourceId.count <= 100, !value.sessionId.isEmpty, value.sessionId.count <= 100, value.revision >= 0, (0...99999999).contains(value.count), [33,99,100].contains(value.target) else { return nil }
        return value
    }
    var raw: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "" }
    static func receive(_ raw: String, defaults: UserDefaults) {
        guard let value = parse(raw) else { return }
        let stamp = "seen.\(value.sourceId).\(value.sessionId)"
        if defaults.object(forKey: stamp) != nil && value.revision <= defaults.integer(forKey: stamp) { return }
        defaults.set(value.revision, forKey: stamp)
        defaults.set(raw, forKey: "incomingCounter")
    }
}
