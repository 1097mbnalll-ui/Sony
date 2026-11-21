// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var consoles: ConsoleStore
    @EnvironmentObject private var scanner: HostScanner
    @EnvironmentObject private var stream: StreamController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPairing = false
    @State private var showSettings = false
    @State private var loginPin = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let console = consoles.current {
                        consoleHeader(console)
                        preview
                        translationPlaceholder
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let console = consoles.current { controls(console) }
            }
            .navigationTitle("ترجمان")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .sheet(isPresented: $showPairing) { PairingView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert(stream.loginPinWasWrong ? "الرمز غلط، جرّب مرة ثانية" : "رمز الدخول للجهاز",
                   isPresented: $stream.loginPinRequested) {
                TextField("الرمز", text: $loginPin).keyboardType(.numberPad)
                Button("إرسال") { stream.submitLoginPin(loginPin); loginPin = "" }
                Button("إلغاء", role: .cancel) { stream.stop() }
            } message: {
                Text("جهازك عليه رمز دخول. اكتبه عشان يكمل الاتصال.")
            }
        }
        .onAppear { scanner.start() }
        .onReceive(scanner.$hosts) { _ in model.reconcile() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { scanner.start() } else if phase == .background { scanner.stop() }
        }
    }

    // MARK: - sections

    private func consoleHeader(_ console: Console) -> some View {
        let found = scanner.host(for: console.host)
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(console.name).font(.title3.weight(.bold))
                Text(found?.runningApp.isEmpty == false ? found!.runningApp : console.host)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            status(found)
        }
        .card()
    }

    @ViewBuilder
    private func status(_ found: DiscoveredHost?) -> some View {
        switch stream.state {
        case .streaming: StatusPill(text: "متصل", color: Theme.accent)
        case .connecting: StatusPill(text: "يتصل…", color: Theme.warning)
        case .waking: StatusPill(text: "يصحّي الجهاز…", color: Theme.warning)
        default:
            switch found?.state {
            case .ready?: StatusPill(text: "جاهز", color: Theme.accent)
            case .standby?: StatusPill(text: "وضع الراحة", color: Theme.warning)
            default: StatusPill(text: "غير موجود", color: Theme.danger)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                StreamPreview(renderer: stream.renderer)
                    .environment(\.layoutDirection, .leftToRight)
                if stream.state != .streaming {
                    VStack(spacing: 8) {
                        if stream.state == .connecting || stream.state == .waking {
                            ProgressView()
                        } else {
                            Image(systemName: "tv").font(.largeTitle)
                        }
                        Text(previewMessage)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if stream.state == .streaming {
                HStack {
                    Text(stream.videoSize)
                    Text("·")
                    Text("\(stream.fps) إطار/ث")
                    Spacer()
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private var previewMessage: String {
        switch stream.state {
        case .waking: return "نصحّي الجهاز من وضع الراحة…"
        case .connecting: return "نتصل بالجهاز…"
        case .failed(let msg): return msg
        default: return "اضغط «ابدأ البث» عشان تشوف الصورة هنا"
        }
    }

    private var translationPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("الترجمة").font(.headline)
            Text("قراءة النص والترجمة بتنضاف في النسخة الجاية. هذي النسخة لتجربة الاتصال والصورة.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
        .opacity(0.7)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("اربط جهازك أول مرة").font(.title2.weight(.bold))
            Text("ترجمان يشبك على جهاز الـPS5 في بيتك ويستقبل الصورة عشان يترجم نصوص اللعبة. ما يتحكم في اللعبة، أنت تكمل لعب على الشاشة عادي.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("ابدأ الربط") { showPairing = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .card()
        .padding(.top, 40)
    }

    private func controls(_ console: Console) -> some View {
        HStack(spacing: 12) {
            if stream.isActive {
                Button("إيقاف") { stream.stop() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.danger))
            } else {
                Button(scanner.host(for: console.host)?.state == .standby ? "شغّل الجهاز وابدأ" : "ابدأ البث") {
                    stream.start(console: console, settings: settings, scanner: scanner)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
