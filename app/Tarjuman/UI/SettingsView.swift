// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var consoles: ConsoleStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stream: StreamController
    @Environment(\.dismiss) private var dismiss
    @State private var showPairing = false
    @State private var confirmRemove: Console?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("ترجمة تلقائية", isOn: $settings.autoTranslate)
                    Toggle("اقرأ الترجمة بصوت تلقائياً", isOn: $settings.autoSpeak)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("حجم الخط: \(Int(settings.fontSize))")
                        Slider(value: $settings.fontSize, in: 16...40, step: 1)
                        Text("مثال على حجم الترجمة")
                            .font(.system(size: settings.fontSize, weight: .semibold))
                    }
                    TextField("اسم اللعبة (اختياري)", text: $settings.gameName)
                    Button("رجّع منطقة القراءة للوضع الافتراضي") { settings.region = AppSettings.defaultRegion }
                } header: {
                    Text("الترجمة")
                } footer: {
                    Text("التلقائي يترجم أول ما يتغير النص في المنطقة المحددة. اليدوي يترجم بس لما تضغط «ترجم الحين».")
                }

                Section {
                    HStack {
                        Text("المحرك")
                        Spacer()
                        Text(TranslationProviderID.apple.title).foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text("محرك الترجمة")
                } footer: {
                    Text("الترجمة تصير على جوالك نفسه، مجانية وبدون حد وتشتغل بدون إنترنت.")
                }

                Section {
                    Picker("الدقة", selection: $settings.resolution) {
                        Text("540p").tag(540)
                        Text("720p").tag(720)
                        Text("1080p").tag(1080)
                    }
                    Picker("الإطارات", selection: $settings.fps) {
                        Text("30").tag(30)
                        Text("60").tag(60)
                    }
                    Toggle("ترميز HEVC (جودة أعلى بنفس السرعة)", isOn: $settings.useHEVC)
                } header: {
                    Text("جودة البث")
                } footer: {
                    Text("720p و30 إطار تكفي لقراءة النص وتريّح الشبكة والبطارية. التغيير يطبّق في البث الجاي.")
                }

                Section("الأجهزة") {
                    ForEach(consoles.consoles) { c in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(c.name)
                                Text(c.host).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Button(role: .destructive) { confirmRemove = c } label: { Image(systemName: "trash") }
                        }
                    }
                    Button("ربط جهاز جديد") { showPairing = true }
                }

                Section {
                    Toggle("استخدم يد متصلة بالجوال", isOn: $settings.phoneController)
                } header: {
                    Text("متقدم")
                } footer: {
                    Text("للي ربط الجوال بحسابه الأساسي: توصّل اليد بالجوال بالبلوتوث، وترجمان يرسل ضغطاتك للـPS5. الطريقة العادية هي حساب ثاني للجوال ويدك تبقى على الـPS5.")
                }

                Section("حساب PSN") {
                    if consoles.accountId != nil {
                        Text("محفوظ")
                        Button("حذف رقم الحساب", role: .destructive) { consoles.accountIdBase64 = "" }
                    } else {
                        Text("غير محفوظ").foregroundStyle(Theme.secondaryText)
                    }
                }

                Section {
                    NavigationLink("سجل التشخيص") { LogView() }
                } footer: {
                    Text("إذا صار خطأ، افتح السجل واضغط «مشاركة» وأرسله.")
                }

                Section {
                    Text("ترجمان مشروع مفتوح المصدر (AGPL-3.0) مبني على chiaki-ng. غير تابع لشركة Sony.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } }
            }
            .sheet(isPresented: $showPairing) { PairingView() }
            .confirmationDialog("حذف الجهاز؟", isPresented: Binding(get: { confirmRemove != nil },
                                                                   set: { if !$0 { confirmRemove = nil } })) {
                Button("حذف", role: .destructive) {
                    if let c = confirmRemove {
                        stream.stop()
                        consoles.remove(c)
                    }
                    confirmRemove = nil
                }
            } message: {
                Text("بتحتاج تربطه من جديد برمز.")
            }
        }
    }
}
