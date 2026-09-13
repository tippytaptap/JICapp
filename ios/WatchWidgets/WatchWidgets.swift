import SwiftUI
import WidgetKit

struct PrayerEntry: TimelineEntry {
    let date: Date
    let organisation: String
    let prayer: WatchPrayer?
    let timeZone: String
}
struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry { PrayerEntry(date: .now, organisation: "Community", prayer: nil, timeZone: "UTC") }
    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) { completion(entries().first!) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) { completion(Timeline(entries: entries(), policy: .after(Date().addingTimeInterval(3600)))) }
    private func entries() -> [PrayerEntry] {
        let defaults = UserDefaults(suiteName: "group.com.mastir.communityApp")
        let cache = WatchPrayerTimeline.parse(defaults?.string(forKey: "timeline") ?? "")
        let now = Date()
        let future = cache?.prayers.filter { $0.date > now }.sorted { $0.at < $1.at } ?? []
        let dates = [now] + future.prefix(20).map { $0.date.addingTimeInterval(1) }
        return dates.map { at in PrayerEntry(date: at, organisation: cache?.organisation ?? "Community", prayer: future.first { $0.date > at }, timeZone: cache?.timeZone ?? "UTC") }
    }
}
struct PrayerComplicationView: View {
    let entry: PrayerEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if let prayer = entry.prayer {
                switch family {
                case .accessoryInline: Text("\(prayer.name) ") + Text(prayer.date, style: .time)
                case .accessoryCircular: VStack { Text(prayer.name).font(.caption2).minimumScaleFactor(0.6); Text(prayer.date, style: .time).font(.caption) }
                default: VStack(alignment: .leading) { Text(entry.organisation).font(.caption2); Text(prayer.name).font(.headline); Text(prayer.date, style: .time) }
                }
            } else { VStack { Image(systemName: "moon.stars"); Text("Open phone").font(.caption2) } }
        }
        .environment(\.timeZone, TimeZone(identifier: entry.timeZone) ?? .gmt)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
@main
struct PrayerComplication: Widget {
    let kind = "WatchPrayer"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerProvider()) { PrayerComplicationView(entry: $0) }
            .configurationDisplayName("Next prayer")
            .description("The mosque’s next prayer from your saved phone timetable.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
