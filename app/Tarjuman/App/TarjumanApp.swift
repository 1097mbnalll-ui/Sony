// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

@main
struct TarjumanApp: App {
    @StateObject private var model = AppModel()

    init() { TrjmCore.start() }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .environmentObject(model.consoles)
                .environmentObject(model.scanner)
                .environmentObject(model.stream)
                .environmentObject(model.settings)
                .environmentObject(model.translator)
                .environmentObject(model.translator.apple)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

/// Wires the long-lived objects together.
@MainActor
final class AppModel: ObservableObject {
    let consoles = ConsoleStore()
    let scanner = HostScanner()
    let stream = StreamController()
    let settings = AppSettings()
    let translator = LiveTranslator()

    init() {
        let decoder = stream.decoder
        translator.attach(settings: settings) { [weak decoder] in decoder?.latestFrame }
        for c in consoles.consoles { scanner.addTarget(c.host) }
    }

    /// Keeps the saved console's address fresh if DHCP gave it a new IP.
    func reconcile() {
        for c in consoles.consoles {
            if scanner.host(for: c.host) == nil, let moved = scanner.host(matchingName: c.name) {
                consoles.updateHost(id: c.id, host: moved.addr)
                scanner.addTarget(moved.addr)
            }
        }
    }
}
