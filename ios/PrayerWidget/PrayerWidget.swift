import SwiftUI
import WidgetKit

private let appGroup = "group.com.mastir.communityApp"
private let prayersURL = URL(string: "community://prayers?homeWidget=1")!
private let tasbihURL = URL(string: "community://tasbih?homeWidget=1")!

private struct Prayer: Decodable {
    let name: String
    let at: Double
    var date: Date { Date(timeIntervalSince1970: at / 1000) }
}

private struct PrayerPayload: Decodable {
    let organisation: String
    let timeZone: String
    let prayers: [Prayer]

    static var saved: PrayerPayload {
        guard let text = UserDefaults(suiteName: appGroup)?.string(forKey: "prayer_timeline"),
              let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PrayerPayload.self, from: data) else {
            return PrayerPayload(organisation: "Prayer times", timeZone: "UTC", prayers: [])
        }
        return payload
    }
}

struct PrayerEntry: TimelineEntry {
    let date: Date
    let organisation: String
    let timeZone: String
    let name: String?
    let prayerDate: Date?

    var formattedTime: String {
        guard let prayerDate else { return "Open app to refresh" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: prayerDate)
    }
    var formattedDay: String {
        guard let prayerDate else { return "Timetable unavailable" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: prayerDate)
    }
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry {
        PrayerEntry(date: Date(), organisation: "Prayer times", timeZone: "UTC", name: nil, prayerDate: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(entry(at: Date(), from: .saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let payload = PrayerPayload.saved
        let now = Date()
        // Precomputed transitions let WidgetKit advance while the app is closed.
        let transitions = payload.prayers.map(\.date).filter { $0 > now }.sorted()
        let dates = [now] + transitions.map { $0.addingTimeInterval(1) }
        let entries = dates.map { entry(at: $0, from: payload) }
        // The final entry explicitly shows the exhausted timetable. App refresh
        // publishes a new timeline; there are no network requests in this target.
        completion(Timeline(entries: entries, policy: .never))
    }

    private func entry(at date: Date, from payload: PrayerPayload) -> PrayerEntry {
        let next = payload.prayers.filter { $0.date > date }.min { $0.at < $1.at }
        return PrayerEntry(date: date, organisation: payload.organisation, timeZone: payload.timeZone,
                           name: next?.name, prayerDate: next?.date)
    }
}

struct PrayerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry
    private let gold = Color(red: 0.83, green: 0.74, blue: 0.51)

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.name.map { "\($0) · \(entry.formattedTime)" } ?? "Open app for prayer times")
        case .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: "moon.stars")
                Text(entry.name ?? "Prayer").font(.caption2)
                if entry.prayerDate != nil { Text(entry.formattedTime).font(.caption2).minimumScaleFactor(0.5) }
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? "Prayer times").font(.headline)
                Text(entry.formattedTime).font(.caption)
                Text(entry.formattedDay).font(.caption2)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.organisation).font(.caption).foregroundStyle(gold).lineLimit(1)
                Text(entry.name ?? "Prayer times").font(.headline)
                Text(entry.formattedTime).font(entry.prayerDate == nil ? .callout : .title2)
                    .bold().minimumScaleFactor(0.6).lineLimit(1)
                Text(entry.formattedDay).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if family == .systemMedium {
                    Link(destination: tasbihURL) {
                        Label("Open Tasbih", systemImage: "circle.dotted").font(.subheadline).foregroundStyle(gold)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        Group {
            if #available(iOSApplicationExtension 17.0, *) {
                content.containerBackground(for: .widget) { Color(red: 0.06, green: 0.10, blue: 0.17) }
            } else {
                content.padding().background(Color(red: 0.06, green: 0.10, blue: 0.17))
            }
        }
        .foregroundStyle(.white)
        .widgetURL(prayersURL)
    }
}

@main
struct PrayerWidget: Widget {
    let kind = "PrayerWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerProvider()) { PrayerWidgetView(entry: $0) }
            .configurationDisplayName("Prayer times")
            .description("The next published prayer time, with quick access to Tasbih.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
