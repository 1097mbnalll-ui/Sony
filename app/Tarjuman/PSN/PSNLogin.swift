// SPDX-License-Identifier: AGPL-3.0-only
//
// Gets the PSN account id needed for registration by signing in to PSN in a
// web view, using the same OAuth flow as chiaki-ng (gui/src/psnaccountid.cpp).
// Only the numeric account id is kept; tokens are discarded.

import SwiftUI
import WebKit

enum PSNAuth {
    static let clientId = "ba495a24-818c-472b-b12d-ff231c1b5745"
    static let clientSecret = "mvaiZkRsAsI1IBkY"
    static let redirect = "https://remoteplay.dl.playstation.net/remoteplay/redirect"
    static let tokenURL = URL(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token")!
    static let scope = "psn:clientapp referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update"

    static var loginURL: URL {
        var c = URLComponents(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize")!
        c.queryItems = [
            .init(name: "service_entity", value: "urn:service-entity:psn"),
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: scope),
            .init(name: "request_locale", value: "en_US"),
            .init(name: "ui", value: "pr"),
            .init(name: "service_logo", value: "ps"),
            .init(name: "layout_type", value: "popup"),
            .init(name: "smcid", value: "remoteplay"),
            .init(name: "prompt", value: "always"),
            .init(name: "PlatformPrivacyWs1", value: "minimal"),
        ]
        return c.url!
    }

    private static var basicAuth: String {
        "Basic " + Data("\(clientId):\(clientSecret)".utf8).base64EncodedString()
    }

    enum Failure: Error { case badResponse(String) }

    /// Exchanges the redirect code for the account id (base64 of 8 LE bytes).
    static func accountId(fromCode code: String) async throws -> String {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue(basicAuth, forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "scope", value: scope),
            .init(name: "redirect_uri", value: redirect),
        ]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw Failure.badResponse(String(decoding: data.prefix(300), as: UTF8.self))
        }

        var info = URLRequest(url: tokenURL.appendingPathComponent(token))
        info.setValue(basicAuth, forHTTPHeaderField: "Authorization")
        let (data2, _) = try await URLSession.shared.data(for: info)
        guard let json2 = try JSONSerialization.jsonObject(with: data2) as? [String: Any] else {
            throw Failure.badResponse(String(decoding: data2.prefix(300), as: UTF8.self))
        }
        let userId: UInt64?
        if let s = json2["user_id"] as? String { userId = UInt64(s) }
        else if let n = json2["user_id"] as? NSNumber { userId = n.uint64Value }
        else { userId = nil }
        guard let userId else { throw Failure.badResponse("no user_id") }
        var le = userId.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }.base64EncodedString()
    }
}

/// Sheet that shows the PSN sign-in page and returns the account id.
struct PSNLoginView: View {
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PSNWebView { code in
                    working = true
                    Task {
                        do {
                            let id = try await PSNAuth.accountId(fromCode: code)
                            await MainActor.run {
                                LogStore.shared.info("PSN account id received")
                                onDone(id)
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                LogStore.shared.error("PSN login failed: \(error)")
                                self.error = "ما قدرت أجيب رقم الحساب. جرّب مرة ثانية أو أدخله يدوي."
                                working = false
                            }
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                if working {
                    ProgressView("لحظة…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("دخول PSN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
            .alert("خطأ", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("تمام", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}

private struct PSNWebView: UIViewRepresentable {
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: PSNAuth.loginURL))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, url.absoluteString.hasPrefix(PSNAuth.redirect) {
                decisionHandler(.cancel)
                if !done,
                   let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value {
                    done = true
                    onCode(code)
                }
                return
            }
            decisionHandler(.allow)
        }
    }
}
