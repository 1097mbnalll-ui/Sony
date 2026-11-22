// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import Translation

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var consoles: ConsoleStore
    @EnvironmentObject private var scanner: HostScanner
    @EnvironmentObject private var stream: StreamController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var translator: LiveTranslator
    @EnvironmentObject private var apple: AppleTranslator
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPairing = false
    @State private var showSettings = false
    @State private var editingRegion = false
    @State private var loginPin = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let console = consoles.current {
                        header(console)
                        ControllerStatusView(gamepad: stream.gamepad)
                        preview
                        translationCard
                        historyList
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
            .navigationBarTitleDisplayMode(.inline)
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
        .translationTask(apple.configuration) { session in
            await apple.serve(session)
        }
        .onAppear { scanner.start() }
        .onReceive(scanner.$hosts) { _ in model.reconcile() }
        .onChange(of: stream.state) { state in
            if state == .streaming { translator.streamStarted() }
            else if !stream.isActive { translator.streamStopped() }
        }
        .onChange(of: settings.autoTranslate) { on in translator.setAuto(on) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { scanner.start() } else if phase == .background { scanner.stop() }
        }
    }

    // MARK: - header

    private func header(_ console: Console) -> some View {
        let found = scanner.host(for: console.host)
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(console.name).font(.headline)
                Text(subtitle(found, console))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            status(found)
        }
        .card()
    }

    private func subtitle(_ found: DiscoveredHost?, _ console: Console) -> String {
        if !settings.gameName.isEmpty { return settings.gameName }
        if let app = found?.runningApp, !app.isEmpty { return app }
        return console.host
    }

    @ViewBuilder
    private func status(_ found: DiscoveredHost?) -> some View {
        switch stream.state {
        case .streaming:
            StatusPill(text: settings.autoTranslate ? "متصل · تلقائي" : "متصل · يدوي", color: Theme.accent)
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

    // MARK: - preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                StreamPreview(renderer: stream.renderer)
                    .environment(\.layoutDirection, .leftToRight)
                if stream.state == .streaming {
                    RegionOverlay(region: $settings.region, editing: editingRegion)
                } else {
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if stream.state == .streaming {
                HStack {
                    Text("\(stream.videoSize) · \(stream.fps) إطار/ث")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button(editingRegion ? "تم" : "حدد منطقة الحوار") {
                        editingRegion.toggle()
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardBorder))
    }

    private var previewMessage: String {
        switch stream.state {
        case .waking: return "نصحّي الجهاز من وضع الراحة…"
        case .connecting: return "نتصل بالجهاز…"
        case .failed(let msg): return msg
        default: return "اضغط «ابدأ البث» عشان تشوف الصورة هنا"
        }
    }

    // MARK: - translation

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = translator.current {
                if let speaker = line.speaker {
                    Text(speaker)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
                Text(line.translated)
                    .font(.system(size: settings.fontSize, weight: .semibold))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Text(line.original)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("الترجمة").font(.headline)
                Text(placeholderText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            statusLine
        }
        .card()
        .animation(.easeOut(duration: 0.2), value: translator.current)
    }

    private var placeholderText: String {
        if stream.state != .streaming { return "ابدأ البث، وبعدها حدد مكان الحوار في الصورة. الترجمة بتظهر هنا." }
        return settings.autoTranslate
            ? "ننتظر نص في المنطقة المحددة…"
            : "الوضع يدوي: اضغط «ترجم الحين» لما يطلع حوار."
    }

    @ViewBuilder
    private var statusLine: some View {
        if apple.availability == .needsDownload {
            Button("نزّل لغة العربي للترجمة (مرة وحدة)") { apple.activate() }
                .font(.footnote.weight(.semibold))
        } else if apple.availability == .unsupported {
            Text("ترجمة أبل غير متاحة على هذا الجهاز.")
                .font(.footnote).foregroundStyle(Theme.danger)
        } else if case .error(let msg) = translator.status {
            Text(msg).font(.footnote).foregroundStyle(Theme.warning)
        } else if translator.status == .translating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("يترجم…").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(translator.history.prefix(8).enumerated()), id: \.element.id) { index, line in
                Text((line.speaker.map { "\($0): " } ?? "") + line.translated)
                    .font(.system(size: max(14, settings.fontSize * 0.62)))
                    .foregroundStyle(Color.white)
                    .opacity(max(0.15, 0.45 - Double(index) * 0.05))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - empty state & controls

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
        HStack(spacing: 8) {
            if stream.state == .streaming {
                Button("إيقاف") { stream.stop() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("ترجم الحين") { translator.translateNow() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("اقرأ بصوت") { translator.speakCurrent() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(translator.current == nil)
            } else if stream.isActive {
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
