// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

/// One-time registration: PSN account id → pick console → 8-digit code.
struct PairingView: View {
    @EnvironmentObject private var consoles: ConsoleStore
    @EnvironmentObject private var scanner: HostScanner
    @Environment(\.dismiss) private var dismiss
    @StateObject private var registrar = Registrar()

    @State private var showLogin = false
    @State private var manualAccount = ""
    @State private var showManualAccount = false
    @State private var selectedAddr: String?
    @State private var manualIP = ""
    @State private var pin = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    accountStep
                    consoleStep
                    pinStep
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("ربط الجهاز")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { registrar.cancel(); dismiss() }
                }
            }
            .sheet(isPresented: $showLogin) {
                PSNLoginView { consoles.accountIdBase64 = $0 }
            }
            .onAppear { scanner.start() }
            .onChange(of: registrar.state) { state in
                if case .success(let console) = state {
                    consoles.upsert(console)
                    scanner.addTarget(console.host)
                    dismiss()
                }
            }
        }
    }

    private func stepTitle(_ n: Int, _ title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? Theme.accent : Color.white.opacity(0.1)).frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.black)
                } else {
                    Text("\(n)").font(.subheadline.weight(.bold))
                }
            }
            Text(title).font(.headline)
            Spacer()
        }
    }

    // MARK: step 1

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle(1, "حساب PSN", done: consoles.accountId != nil)
            if consoles.accountId != nil {
                Text("تم حفظ رقم حسابك.").font(.subheadline).foregroundStyle(Theme.secondaryText)
                Button("غيّره") { consoles.accountIdBase64 = "" }
                    .font(.subheadline)
            } else {
                Text("الجهاز يحتاج رقم حسابك في PSN عشان يقبل الربط. سجّل دخول مرة وحدة وبنجيبه تلقائي (ما نحفظ كلمة المرور).")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                Button("سجّل دخول PSN") { showLogin = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button(showManualAccount ? "إخفاء" : "عندي الرقم (إدخال يدوي)") { showManualAccount.toggle() }
                    .font(.subheadline)
                if showManualAccount {
                    TextField("Account ID (Base64)", text: $manualAccount)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    Button("حفظ") { consoles.accountIdBase64 = manualAccount }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(Data(base64Encoded: manualAccount.trimmingCharacters(in: .whitespaces))?.count != 8)
                }
            }
        }
        .card()
    }

    // MARK: step 2

    private var consoleStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle(2, "اختر الجهاز", done: selectedAddr != nil)
            Text("خل الجوال والـPS5 على نفس الشبكة. إذا طلب منك الجوال إذن «الشبكة المحلية» وافق.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)

            if scanner.hosts.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("ندوّر على الأجهزة…").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            ForEach(scanner.hosts) { host in
                Button { selectedAddr = host.addr } label: {
                    HStack {
                        Image(systemName: selectedAddr == host.addr ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name.isEmpty ? host.addr : host.name).font(.body.weight(.semibold))
                            Text("\(host.addr) · \(host.state == .standby ? "وضع الراحة" : "شغّال")")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(selectedAddr == host.addr ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            HStack {
                TextField("أو اكتب عنوان IP", text: $manualIP)
                    .keyboardType(.decimalPad)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Button("ابحث") {
                    scanner.addTarget(manualIP)
                    selectedAddr = manualIP.trimmingCharacters(in: .whitespaces)
                }
                .disabled(manualIP.isEmpty)
            }
        }
        .card()
    }

    // MARK: step 3

    private var pinStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle(3, "رمز الربط", done: false)
            Text("في الـPS5 روح: الإعدادات ← النظام ← التشغيل عن بُعد ← ربط جهاز. بيطلع لك رقم من 8 خانات، اكتبه هنا.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            TextField("12345678", text: $pin)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: pin) { v in pin = String(v.filter(\.isNumber).prefix(8)) }

            switch registrar.state {
            case .working:
                HStack { ProgressView(); Text("نربط…").foregroundStyle(Theme.secondaryText) }
            case .failed(let msg):
                Text(msg).font(.subheadline).foregroundStyle(Theme.danger)
            default:
                EmptyView()
            }

            Button("اربط") { startRegist() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canRegister)
                .opacity(canRegister ? 1 : 0.4)
        }
        .card()
    }

    private var canRegister: Bool {
        consoles.accountId != nil && selectedAddr != nil && pin.count == 8 && registrar.state != .working
    }

    private func startRegist() {
        guard let addr = selectedAddr, let acc = consoles.accountId, let code = UInt32(pin) else { return }
        let host = scanner.host(for: addr)
        registrar.start(host: addr, ps5: host?.ps5 ?? true, name: host?.name ?? "", accountId: acc, pin: code)
    }
}
