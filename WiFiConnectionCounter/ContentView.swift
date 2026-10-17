import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ScanViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Devices found (\(vm.devices.count))") {
                    if vm.devices.isEmpty {
                        Text("Nothing yet. Tap Scan.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(vm.sortedDevices) { d in
                        row(d)
                    }
                }

                Section("Good to know") {
                    Text("This is a real scan, not a guess. The number is devices that actually answered, so the true total can be higher: phones asleep, devices that block pings, or Wi-Fi (like many Piso WiFi) that isolates clients may not appear.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("iOS does not let apps read MAC addresses or the router's client list, so only IP addresses and names (when the router shares them) are shown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("WiFi Counter")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: vm.exportText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(vm.devices.isEmpty)
                }
            }
            .onAppear { if vm.lastScan == nil { vm.scan() } }
            .refreshable { vm.scan() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.blue)

            Text(vm.isScanning ? "Scanning…" : "\(vm.devices.count)")
                .font(.system(size: 64, weight: .bold, design: .rounded))

            Text(vm.devices.count == 1 ? "device found on this Wi-Fi" : "devices found on this Wi-Fi")
                .foregroundStyle(.secondary)

            if let net = vm.network {
                Text("Network \(net.cidr)  ·  You are \(net.ipString)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                if net.isCapped {
                    Text("Large network: scanning the 1022 addresses around you.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if vm.isScanning {
                ProgressView(value: vm.progress)
                    .padding(.horizontal)
            }

            Text(vm.status)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button {
                vm.scan()
            } label: {
                Label(vm.isScanning ? "Scanning" : "Scan again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isScanning)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func row(_ d: Device) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.ipString).font(.body.monospaced())
                if let h = d.hostname {
                    Text(h).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if d.isSelf {
                tag("This iPhone", .blue)
            } else if d.isLikelyRouter {
                tag("Likely router", .orange)
            } else {
                tag(d.foundBy, .gray)
            }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = d.ipString } label: {
                Label("Copy IP", systemImage: "doc.on.doc")
            }
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
