// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Finds consoles on the local network.
///
/// iOS blocks UDP broadcast unless the app has Apple's multicast entitlement,
/// so we unicast the discovery packet to every address of the Wi-Fi subnet
/// instead (and to any address the user typed in).
final class HostScanner: ObservableObject {
    @Published private(set) var hosts: [DiscoveredHost] = []
    @Published private(set) var isScanning = false

    private var scanner: OpaquePointer?
    private var timer: Timer?
    private var extraTargets: Set<String> = []
    private let queue = DispatchQueue(label: "tarjuman.scanner")

    deinit {
        timer?.invalidate()
        if let s = scanner { trjm_scanner_free(s) }
    }

    func start() {
        guard timer == nil else { return }
        if scanner == nil {
            let user = Unmanaged.passUnretained(self).toOpaque()
            scanner = trjm_scanner_new({ hostPtr, user in
                guard let hostPtr, let user else { return }
                let me = Unmanaged<HostScanner>.fromOpaque(user).takeUnretainedValue()
                let host = DiscoveredHost(hostPtr.pointee)
                DispatchQueue.main.async { me.update(host) }
            }, user)
            if scanner == nil {
                LogStore.shared.error("Could not open discovery socket")
                return
            }
        }
        isScanning = true
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isScanning = false
    }

    /// Also probe this address on every tick (manual IP / saved console).
    func addTarget(_ ip: String) {
        let ip = ip.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        extraTargets.insert(ip)
        ping(ip)
    }

    func ping(_ ip: String) {
        guard let s = scanner else { return }
        queue.async { _ = trjm_scanner_ping(s, ip) }
    }

    func host(for ip: String) -> DiscoveredHost? { hosts.first { $0.addr == ip } }

    func host(matchingName name: String) -> DiscoveredHost? { hosts.first { $0.name == name } }

    private var sweepCounter = 0

    private func tick() {
        guard let s = scanner else { return }
        let targets = extraTargets
        // A full subnet sweep every other tick, saved/manual targets every tick.
        let sweep = sweepCounter % 2 == 0
        sweepCounter += 1
        queue.async {
            for t in targets { _ = trjm_scanner_ping(s, t) }
            if sweep { _ = trjm_scanner_sweep(s) }
        }
        let now = Date()
        hosts.removeAll { now.timeIntervalSince($0.lastSeen) > 15 }
    }

    private func update(_ h: DiscoveredHost) {
        if let i = hosts.firstIndex(where: { $0.addr == h.addr }) {
            hosts[i] = h
        } else {
            hosts.append(h)
            LogStore.shared.info("Found \(h.name) at \(h.addr) (\(h.ps5 ? "PS5" : "PS4"), \(h.state))")
        }
    }
}
