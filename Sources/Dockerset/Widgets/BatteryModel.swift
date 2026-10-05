import Foundation
import IOKit
import IOKit.ps

struct BatteryDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let percent: Int
    let charging: Bool
}

/// Battery levels for this Mac, Bluetooth keyboards/mice/trackpads (IORegistry) and Bluetooth audio such as
/// AirPods (system_profiler). Devices only report a level while they're connected.
@MainActor
final class BatteryModel: ObservableObject {
    static let shared = BatteryModel()

    @Published private(set) var devices: [BatteryDevice] = []

    private let queue = DispatchQueue(label: "dockerset.battery", qos: .utility)
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        queue.async {
            let found = Self.read()
            Task { @MainActor in
                if self.devices != found { self.devices = found }
            }
        }
    }

    private nonisolated static func read() -> [BatteryDevice] {
        var result = macBattery()
        result += hidBatteries()
        let known = Set(result.map(\.name))
        result += bluetoothBatteries().filter { !known.contains($0.name) }
        return result
    }

    private nonisolated static func macBattery() -> [BatteryDevice] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return sources.compactMap { source in
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
            let charging = d[kIOPSIsChargingKey] as? Bool == true || d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return BatteryDevice(id: "mac", name: "This Mac", symbol: "laptopcomputer",
                                 percent: current * 100 / max, charging: charging)
        }
    }

    private nonisolated static func hidBatteries() -> [BatteryDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [BatteryDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            if let percent = property("BatteryPercent") as? Int, let name = property("Product") as? String {
                result.append(BatteryDevice(id: "hid-\(name)", name: name, symbol: symbol(for: name, type: nil),
                                            percent: percent, charging: false))
            }
            IOObjectRelease(service)
        }
        return result
    }

    private nonisolated static func bluetoothBatteries() -> [BatteryDevice] {
        guard let out = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
              let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let root = (json["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = root["device_connected"] as? [[String: [String: Any]]] else { return [] }

        func level(_ info: [String: Any], _ key: String) -> Int? {
            (info[key] as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        }
        return connected.flatMap { $0 }.compactMap { name, info in
            let buds = [level(info, "device_batteryLevelLeft"), level(info, "device_batteryLevelRight")].compactMap { $0 }
            guard let percent = level(info, "device_batteryLevelMain") ?? buds.min() else { return nil }
            return BatteryDevice(id: "bt-\(name)", name: name, symbol: symbol(for: name, type: info["device_minorType"] as? String),
                                 percent: percent, charging: false)
        }
    }

    private nonisolated static func symbol(for name: String, type: String?) -> String {
        let n = name.lowercased()
        let t = type?.lowercased() ?? ""
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("keyboard") || t.contains("keyboard") { return "keyboard" }
        if n.contains("trackpad") || t.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("mouse") || t.contains("mouse") { return "magicmouse" }
        if t.contains("headphones") || t.contains("headset") { return "headphones" }
        if t.contains("speaker") { return "hifispeaker" }
        return "dot.radiowaves.left.and.right"
    }
}
