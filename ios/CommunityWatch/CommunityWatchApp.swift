import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit
import CoreLocation

final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let group = "group.com.mastir.communityApp"
    let defaults = UserDefaults(suiteName: group) ?? .standard
    @Published var timeline: WatchPrayerTimeline?
    @Published var count = 0
    @Published var target = 33
    @Published var incoming: WatchCounter?
    @Published var message = ""
    override init() {
        super.init()
        timeline = WatchPrayerTimeline.parse(defaults.string(forKey: "timeline") ?? "")
        count = defaults.integer(forKey: "count")
        target = [33,99,100].contains(defaults.integer(forKey: "target")) ? defaults.integer(forKey: "target") : 33
        incoming = WatchCounter.parse(defaults.string(forKey: "incomingCounter") ?? "")
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func change(_ amount: Int) {
        count = min(99999999, max(0, count + amount)); defaults.set(count, forKey: "count")
        WKInterfaceDevice.current().play(count > 0 && count % target == 0 ? .success : .click)
    }
    func setTarget(_ value: Int) { target = value; defaults.set(value, forKey: "target") }
    func reset() { count = 0; defaults.set(0, forKey: "count") }
    func importCounter(_ value: WatchCounter) {
        count = value.count; setTarget(value.target); defaults.set(count, forKey: "count")
        if incoming?.sourceId == value.sourceId && incoming?.sessionId == value.sessionId && incoming?.revision == value.revision { defaults.removeObject(forKey: "incomingCounter"); incoming = nil }
    }
    func send() {
        let source = defaults.string(forKey: "sourceId") ?? UUID().uuidString
        defaults.set(source, forKey: "sourceId")
        let revision = defaults.integer(forKey: "revision") + 1
        defaults.set(revision, forKey: "revision")
        let raw = WatchCounter(sourceId: source, sessionId: "local", revision: revision, count: count, target: target).raw
        defaults.set(raw, forKey: "outgoingCounter")
        do { try flush(); message = "Ready for phone. Import it in phone Tasbih." } catch { message = "Could not send. Open the phone app and try again." }
    }
    private func flush() throws {
        if WCSession.default.activationState == .activated, let raw = defaults.string(forKey: "outgoingCounter") { try WCSession.default.updateApplicationContext(["counter": raw]) }
    }
    private func receive(_ context: [String: Any]) {
        if let raw = context["timeline"] as? String, let value = WatchPrayerTimeline.parse(raw) {
            defaults.set(raw, forKey: "timeline"); defaults.set(Date().timeIntervalSince1970, forKey: "receivedAt"); timeline = value
            WidgetCenter.shared.reloadAllTimelines()
        }
        if let raw = context["counter"] as? String {
            WatchCounter.receive(raw, defaults: defaults)
            incoming = WatchCounter.parse(defaults.string(forKey: "incomingCounter") ?? "")
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.receive(session.receivedApplicationContext); try? self.flush() }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) { DispatchQueue.main.async { self.receive(applicationContext) } }
}

@main
struct CommunityWatchApp: App {
    @StateObject private var store = WatchStore()
    var body: some Scene { WindowGroup { WatchHome().environmentObject(store).tint(Color(red: 0.83, green: 0.68, blue: 0.38)) } }
}
struct WatchHome: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(store.timeline?.organisation ?? "Community").font(.headline)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let prayers = store.timeline?.prayers.filter { $0.date > context.date }.sorted { $0.at < $1.at } ?? []
                        if let next = prayers.first {
                            Text("Next: \(next.name)").font(.title3)
                            Text(next.date, style: .time).font(.title2)
                                .environment(\.timeZone, TimeZone(identifier: store.timeline?.timeZone ?? "UTC") ?? .gmt)
                            Text("Mosque time · saved on watch").font(.caption2)
                            if context.date.timeIntervalSince1970 - store.defaults.double(forKey: "receivedAt") > 86400 { Text("Saved over a day ago. Open phone to refresh.").font(.caption2) }
                            NavigationLink("Prayer times") { List(prayers.prefix(20)) { prayer in VStack(alignment: .leading) { Text(prayer.name); Text(prayer.date, format: .dateTime.weekday().hour().minute()).environment(\.timeZone, TimeZone(identifier: store.timeline?.timeZone ?? "UTC") ?? .gmt) } } }
                        } else { Text("Open the phone app to refresh prayer times.").font(.caption) }
                    }
                    NavigationLink("Tasbih") { WatchTasbih() }
                    NavigationLink("Qibla") { WatchQibla() }
                }
            }
        }
    }
}
struct WatchTasbih: View {
    @EnvironmentObject private var store: WatchStore
    @State private var reset = false
    @State private var importing = false
    @State private var importValue: WatchCounter?
    var body: some View {
        ScrollView {
            VStack {
                Button { store.change(1) } label: { VStack { Text("\(store.count)").font(.system(size: 42, weight: .medium, design: .rounded)); Text("Tap +1").font(.caption) }.frame(maxWidth: .infinity) }
                Text("Target \(store.target)")
                Button("Undo −1") { store.change(-1) }.disabled(store.count == 0)
                Picker("Target", selection: Binding(get: { store.target }, set: { store.setTarget($0) })) { ForEach([33,99,100], id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.navigationLink)
                Button("Reset", role: .destructive) { reset = true }
                Button("Send to phone") { store.send() }
                if store.incoming != nil { Button("Import phone count") { importValue = store.incoming; importing = true } }
                if !store.message.isEmpty { Text(store.message).font(.caption2) }
            }
        }.navigationTitle("Tasbih")
        .confirmationDialog("Reset this watch count?", isPresented: $reset) { Button("Reset", role: .destructive) { store.reset() } }
        .confirmationDialog("Replace \(store.count) with \(importValue?.count ?? 0)? Counts are not added together.", isPresented: $importing) { Button("Replace count") { if let value = importValue { store.importCounter(value) } } }
    }
}
final class WatchCompass: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var message = "Use your location once. Keep the watch flat and away from metal."
    private let location = CLLocationManager()
    private var bearing: Double?
    private var active = false
    private var timeout: Timer?
    override init() { super.init(); location.delegate = self; location.desiredAccuracy = kCLLocationAccuracyHundredMeters; location.headingFilter = 3 }
    func start() {
        stop(); active = true
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locate()
        default: message = "Enable location for this app in watch settings."
        }
    }
    private func locate() {
        message = "Finding your position…"; location.requestLocation()
        timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.bearing == nil else { return }; self.stop(); self.message = "Location timed out. Try outdoors."
        }
    }
    func stop() { active = false; location.stopUpdatingLocation(); location.stopUpdatingHeading(); timeout?.invalidate(); timeout = nil; bearing = nil; message = "Tap Find direction to refresh the compass." }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard active else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { locate() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { message = "Enable location for this app in watch settings."; active = false }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active, let point = locations.last, point.horizontalAccuracy >= 0, abs(point.timestamp.timeIntervalSinceNow) < 120 else { return }
        timeout?.invalidate()
        let latitude = point.coordinate.latitude * .pi / 180
        let destination = 21.422487 * .pi / 180
        let difference = (39.826206 - point.coordinate.longitude) * .pi / 180
        bearing = (atan2(sin(difference), cos(latitude) * tan(destination) - sin(latitude) * cos(difference)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        message = "Qibla \(Int(bearing!.rounded()))° from true north."
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() } else { message += " This watch has no compass sensor." }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        guard active, let bearing else { return }
        guard heading.headingAccuracy >= 0, heading.trueHeading >= 0 else { message = "Calibrate by moving your wrist. Keep away from metal."; return }
        let turn = (bearing - heading.trueHeading + 540).truncatingRemainder(dividingBy: 360) - 180
        message = abs(turn) < 7 ? "↑ Facing Qibla" : "Turn \(turn > 0 ? "right" : "left") \(Int(abs(turn).rounded()))°"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { guard active else { return }; stop(); message = "Location unavailable. Check permission and try outdoors." }
}
struct WatchQibla: View {
    @StateObject private var compass = WatchCompass()
    @Environment(\.scenePhase) private var phase
    var body: some View { ScrollView { VStack(spacing: 16) { Text(compass.message); Button("Find direction") { compass.start() } } }.navigationTitle("Qibla").onDisappear { compass.stop() }.onChange(of: phase) { _, value in if value != .active { compass.stop() } } }
}
