import Flutter
import Foundation
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private let defaults = UserDefaults.standard
    private var pending: [String: Any] = [:]
    private override init() {
        super.init()
        if let raw = defaults.string(forKey: "watch.outgoingTimeline") { pending["timeline"] = raw }
        if let raw = defaults.string(forKey: "watch.outgoingCounter") { pending["counter"] = raw }
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func attach(messenger: FlutterBinaryMessenger) {
        FlutterMethodChannel(name: "community/watch", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
            guard let self else { result(FlutterError(code: "watch_unavailable", message: "Watch unavailable", details: nil)); return }
            switch call.method {
            case "getIncomingCounter": result(self.defaults.string(forKey: "incomingCounter"))
            case "clearIncomingCounter":
                if let raw = call.arguments as? String, raw == self.defaults.string(forKey: "incomingCounter") { self.defaults.removeObject(forKey: "incomingCounter") }
                result(nil)
            case "publishTimeline", "publishCounter":
                guard WCSession.isSupported(), let raw = call.arguments as? String else { result(FlutterError(code: "watch_unavailable", message: "Use a paired Apple Watch.", details: nil)); return }
                let timeline = call.method == "publishTimeline"
                guard timeline ? WatchPrayerTimeline.parse(raw) != nil : WatchCounter.parse(raw) != nil else { result(FlutterError(code: "payload", message: "Watch data could not be read.", details: nil)); return }
                self.pending[timeline ? "timeline" : "counter"] = raw
                self.defaults.set(raw, forKey: timeline ? "watch.outgoingTimeline" : "watch.outgoingCounter")
                do { try self.flush(); result(nil) } catch { result(FlutterError(code: "watch_unavailable", message: "Connect your paired watch and try again.", details: nil)) }
            default: result(FlutterMethodNotImplemented)
            }
        }
    }
    private func flush() throws {
        if WCSession.default.activationState == .activated && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled { try WCSession.default.updateApplicationContext(pending) }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { DispatchQueue.main.async { try? self.flush() } }
    func sessionWatchStateDidChange(_ session: WCSession) { DispatchQueue.main.async { try? self.flush() } }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let raw = applicationContext["counter"] as? String { DispatchQueue.main.async { WatchCounter.receive(raw, defaults: self.defaults) } }
    }
}
