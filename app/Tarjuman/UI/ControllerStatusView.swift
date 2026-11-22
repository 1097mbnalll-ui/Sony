// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

/// Shows whether the player's controller is paired with the phone, and how to pair it.
struct ControllerStatusView: View {
    @ObservedObject var gamepad: GamepadInput
    @State private var showHelp = false

    var body: some View {
        if let name = gamepad.controllerName {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill").foregroundStyle(Theme.accent)
                Text("يد التحكم متصلة بالجوال: \(name)")
                    .font(.footnote)
                Spacer()
            }
            .padding(.horizontal, 6)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gamecontroller").foregroundStyle(Theme.warning)
                    Text("وصّل يد التحكم بالجوال").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(showHelp ? "إخفاء" : "كيف؟") { showHelp.toggle() }
                        .font(.footnote)
                }
                Text("لما يشتغل البث، الـPS5 يعطي التحكم للجوال. وصّل يدك بالجوال وتلعب فيها عادي على الشاشة.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if showHelp {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("١. طفّ اليد، بعدين اضغط زر Create (الصغير يسار لوحة اللمس) مع زر PS مع بعض لين يرمش الضوء بسرعة.")
                        Text("٢. في الآيفون: الإعدادات ← البلوتوث ← اختر DualSense Wireless Controller.")
                        Text("٣. ارجع لترجمان، بيطلع لك إن اليد متصلة.")
                        Text("لما تبي ترجع اليد للـPS5 بدون الجوال: وصّلها بسلك USB بالجهاز واضغط زر PS.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .font(.footnote)
                }
            }
            .card()
        }
    }
}
