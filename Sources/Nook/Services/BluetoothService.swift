import AppKit
import Combine
import Foundation

struct BluetoothDevice: Identifiable, Equatable {
    let address: String
    let name: String

    var id: String { address.isEmpty ? name : address }
}

/// Watches Bluetooth connections through `system_profiler`, which needs no
/// private APIs or permissions. Announces connect/disconnect in the notch.
final class BluetoothService: ObservableObject {
    static let shared = BluetoothService()

    @Published private(set) var connected: [BluetoothDevice] = []

    private var timer: Timer?
    private var polling = false
    private var baseline = false
    private var known: Set<String> = []
    private var announceToken = 0
    private let queue = DispatchQueue(label: "nook.bluetooth")

    private init() {}

    func start() {
        poll()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        queue.async { [weak self] in
            let devices = Self.readDevices()
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                guard let devices else { return }
                self.apply(devices)
            }
        }
    }

    private func apply(_ devices: [BluetoothDevice]) {
        let ids = Set(devices.map(\.id))
        defer {
            connected = devices
            known = ids
            baseline = true
        }
        guard baseline else { return }
        let joined = devices.filter { !known.contains($0.id) }
        let left = connected.filter { !ids.contains($0.id) }
        guard AppSettings.shared.showBluetoothActivity else { return }
        if let device = joined.first {
            announce(device, connected: true)
        } else if let device = left.first {
            announce(device, connected: false)
        }
    }

    private func announce(_ device: BluetoothDevice, connected isConnected: Bool) {
        announceToken += 1
        let token = announceToken
        let activity = NotchState.LiveActivity(kind: .bluetooth,
                                               symbol: "dot.radiowaves.left.and.right",
                                               text: device.name,
                                               detail: isConnected ? "Connected" : "Disconnected",
                                               progress: nil)
        NotchController.shared.setActivity(activity)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, token == self.announceToken else { return }
            NotchController.shared.clearActivity(.bluetooth)
        }
    }

    private static func readDevices() -> [BluetoothDevice]? {
        guard let out = Util.shell("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
              let data = out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else {
            return nil
        }

        var devices: [BluetoothDevice] = []
        for section in sections {
            let connected = section["device_connected"]
            if let list = connected as? [[String: Any]] {
                for entry in list {
                    for (name, value) in entry where !name.isEmpty {
                        let info = value as? [String: Any]
                        devices.append(BluetoothDevice(address: info?["device_address"] as? String ?? "",
                                                       name: name))
                    }
                }
            } else if let dict = connected as? [String: Any] {
                for (name, value) in dict where !name.isEmpty {
                    let info = value as? [String: Any]
                    devices.append(BluetoothDevice(address: info?["device_address"] as? String ?? "",
                                                   name: name))
                }
            }
        }
        return devices
    }
}
