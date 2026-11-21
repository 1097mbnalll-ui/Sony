// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.075)   // #0E0F13
    static let card = Color(red: 0.102, green: 0.110, blue: 0.133)         // #1A1C22
    static let cardBorder = Color.white.opacity(0.06)
    static let accent = Color(red: 0.184, green: 0.827, blue: 0.690)       // #2FD3B0
    static let warning = Color(red: 0.949, green: 0.710, blue: 0.267)      // #F2B544
    static let danger = Color(red: 0.937, green: 0.345, blue: 0.392)       // #EF5864
    static let secondaryText = Color.white.opacity(0.55)
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardBorder))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }
}
