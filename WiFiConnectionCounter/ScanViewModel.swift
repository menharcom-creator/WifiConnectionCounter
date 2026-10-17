import Foundation
import SwiftUI

struct Device: Identifiable {
    let ip: UInt32
    var hostname: String?
    var isSelf: Bool
    var foundBy: String
    var id: UInt32 { ip }
    var ipString: String { IPv4.string(ip) }
    var isLikelyRouter: Bool { (ip & 0xFF) == 1 }
}

private final class FoundSet {
    private var set = Set<UInt32>()
    private let lock = NSLock()
    func insert(_ v: UInt32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return set.insert(v).inserted
    }
    func contains(_ v: UInt32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return set.contains(v)
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var network: LocalNetwork?
    @Published var devices: [Device] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var status = "Tap Scan to look for devices"
    @Published var lastScan: Date?

    var sortedDevices: [Device] { devices.sorted { $0.ip < $1.ip } }

    var exportText: String {
        var lines = ["Devices on \(network?.cidr ?? "Wi-Fi")"]
        for d in sortedDevices {
            var line = d.ipString
            if let h = d.hostname { line += "  \(h)" }
            if d.isSelf { line += "  (this iPhone)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    func scan() {
        guard !isScanning else { return }
        guard let net = NetworkInfo.current() else {
            network = nil
            devices = []
            lastScan = Date()
            status = "Not connected to Wi-Fi. Connect to a network and try again."
            return
        }
        network = net
        devices = [Device(ip: net.ip, hostname: nil, isSelf: true, foundBy: "This iPhone")]
        isScanning = true
        progress = 0
        status = "Step 1 of 2: pinging every address…"

        let targets = net.targets
        let targetSet = Set(targets)

        Task.detached(priority: .userInitiated) { [weak self] in
            let found = FoundSet()
            let report: (UInt32, String) -> Void = { ip, via in
                guard targetSet.contains(ip), found.insert(ip) else { return }
                Task { @MainActor in self?.addDevice(ip: ip, via: via) }
            }

            ICMPScanner.sweep(targets: targets, rounds: 2,
                              onFound: { report($0, "Ping") },
                              onProgress: { p in Task { @MainActor in self?.progress = p * 0.5 } })

            await self?.update(status: "Step 2 of 2: checking devices that ignore ping…", progress: 0.5)

            let silent = targets.filter { !found.contains($0) }
            TCPScanner.sweep(targets: silent,
                             onAlive: { report($0, "Open port") },
                             onProgress: { p in Task { @MainActor in self?.progress = 0.5 + p * 0.5 } })

            await self?.finish()
        }
    }

    private func update(status: String, progress: Double) {
        self.status = status
        self.progress = progress
    }

    private func addDevice(ip: UInt32, via: String) {
        guard !devices.contains(where: { $0.ip == ip }) else { return }
        devices.append(Device(ip: ip, hostname: nil, isSelf: false, foundBy: via))
        Task.detached {
            let name = NetworkInfo.hostname(for: ip)
            await MainActor.run { [weak self] in
                guard let self, let name else { return }
                if let i = self.devices.firstIndex(where: { $0.ip == ip }) {
                    self.devices[i].hostname = name
                }
            }
        }
    }

    private func finish() {
        isScanning = false
        progress = 1
        lastScan = Date()
        let others = devices.count - 1
        status = others == 0
            ? "No other devices answered. The network may isolate clients, or Local Network access is off."
            : "Scan finished."
    }
}
