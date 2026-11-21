// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

struct LogView: View {
    @ObservedObject private var log = LogStore.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log.lines) { line in
                        Text(line.text)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(color(line.level))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(12)
                .environment(\.layoutDirection, .leftToRight)
            }
            .onChange(of: log.lines.count) { _ in
                if let last = log.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("سجل التشخيص")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: log.exportText) { Image(systemName: "square.and.arrow.up") }
                Button { UIPasteboard.general.string = log.exportText } label: { Image(systemName: "doc.on.doc") }
                Button(role: .destructive) { log.clear() } label: { Image(systemName: "trash") }
            }
        }
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case 3: return Theme.danger
        case 2: return Theme.warning
        case 0: return Color.white.opacity(0.4)
        default: return Color.white.opacity(0.85)
        }
    }
}
