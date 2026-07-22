//
//  PreviewView.swift
//  MarkdownEditor
//
//  Created by Charlie van de Kerkhof on 22/07/2026.
//

import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    @Binding var text: String

    /// Full re-renders are cheap to compute but a WKWebView reload per keystroke would stutter,
    /// unlike the editor's cheap regex-based highlighter — debounce instead.
    private static let debounceInterval: TimeInterval = 0.275

    private static let stylesheet: String = {
        guard let url = Bundle.main.url(forResource: "PreviewStyle", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return css
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.render(text, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.scheduleRender(of: text, in: webView, after: Self.debounceInterval)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var pendingWorkItem: DispatchWorkItem?
        private var lastRenderedText: String?

        func render(_ text: String, in webView: WKWebView) {
            guard text != lastRenderedText else { return }
            lastRenderedText = text
            let html = MarkdownRenderer.htmlDocument(from: text, stylesheet: PreviewView.stylesheet)
            webView.loadHTMLString(html, baseURL: nil)
        }

        /// Only reschedules when `text` differs from what's already rendered/pending, so unrelated
        /// SwiftUI updates (window resize, split-divider drag) don't restart the debounce timer.
        func scheduleRender(of text: String, in webView: WKWebView, after interval: TimeInterval) {
            guard text != lastRenderedText else { return }
            pendingWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.render(text, in: webView)
            }
            pendingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
        }

        /// Only the initial `loadHTMLString` navigation (not link-activated) is allowed in-pane;
        /// clicked links open in the user's default browser instead.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}

#Preview {
    PreviewView(text: .constant("# Heading\n\nSome **bold** and *italic* text.\n"))
        .frame(width: 500, height: 400)
}
