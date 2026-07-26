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
    /// The editor's current cursor line (1-based, matching `MarkdownRenderer`'s `data-source-line`
    /// attributes). Read-only here — this pane never moves the editor's cursor, only follows it.
    var cursorLine: Int

    /// Full re-renders are cheap to compute but a WKWebView reload per keystroke would stutter,
    /// unlike the editor's cheap regex-based highlighter — debounce instead.
    private static let debounceInterval: TimeInterval = 0.275

    /// Debounces the cursor-follow scroll (click, arrow keys) so holding an arrow key or
    /// drag-selecting doesn't spam `evaluateJavaScript`. Much shorter than the render debounce
    /// since no content re-render is involved, just a scroll.
    private static let scrollDebounceInterval: TimeInterval = 0.06

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
        context.coordinator.lastKnownCursorLine = cursorLine
        context.coordinator.lastKnownText = text
        context.coordinator.loadInitialDocument(text, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            text: text,
            cursorLine: cursorLine,
            in: webView,
            renderDebounce: Self.debounceInterval,
            scrollDebounce: Self.scrollDebounceInterval
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var pendingRenderWorkItem: DispatchWorkItem?
        private var pendingScrollWorkItem: DispatchWorkItem?
        private var lastRenderedText: String?
        /// The `text` seen on the most recent `update(...)` call, regardless of whether it's been
        /// rendered yet. Distinct from `lastRenderedText`, which only advances once `render()`
        /// actually runs (i.e. once the debounce fires) -- comparing against `lastRenderedText`
        /// instead of this would mean *any* call to `update` during a pending render's debounce
        /// window looks like "new content," even a pure cursor move with unchanged text, and would
        /// keep re-arming the render timer for as long as the cursor kept moving.
        fileprivate var lastKnownText: String?
        /// The most recent cursor line seen, used to resync scroll position once a debounced
        /// re-render's reload finishes (see `webView(_:didFinish:)`).
        fileprivate var lastKnownCursorLine = 1
        /// Set once the initial `loadHTMLString` navigation finishes. `render` no-ops while this is
        /// false, since evaluating JS against a webview mid-navigation can silently fail -- without
        /// this guard, a render debounced during that window would mark itself as applied (via
        /// `lastRenderedText`) without actually patching the DOM, leaving the preview stuck on the
        /// initial content with no future edit able to retrigger it.
        private var isInitialLoadComplete = false

        /// The one real page navigation, done once up front to establish the document shell and
        /// inline stylesheet. Every later content change goes through `render`'s in-place DOM
        /// patch instead, since a full reload here means a full re-navigation there too.
        func loadInitialDocument(_ text: String, in webView: WKWebView) {
            lastRenderedText = text
            let html = MarkdownRenderer.htmlDocument(from: text, stylesheet: PreviewView.stylesheet)
            webView.loadHTMLString(html, baseURL: nil)
        }

        /// Replaces the rendered body content in place via JS rather than a fresh `loadHTMLString`
        /// navigation. A full-page reload flashes the preview blank and resets scroll before the
        /// resync JS can run to fix it back up -- very visible during normal typing, since the
        /// render debounce interval is on the same order as typing's natural inter-keystroke gaps
        /// and so fires often. An in-place DOM swap has no navigation, so nothing flashes; scroll
        /// only needs a resync afterward (below), not a full re-navigation to recover from.
        func render(_ text: String, in webView: WKWebView) {
            guard isInitialLoadComplete else { return }
            guard text != lastRenderedText else { return }
            lastRenderedText = text
            let fragment = MarkdownRenderer.htmlFragment(from: text)
            guard let encoded = try? JSONEncoder().encode(fragment), let jsString = String(data: encoded, encoding: .utf8) else { return }
            webView.evaluateJavaScript("document.body.innerHTML = \(jsString);") { [weak self, weak webView] _, _ in
                guard let self, let webView else { return }
                self.scrollToLine(self.lastKnownCursorLine, in: webView, animated: false)
            }
        }

        /// Only reschedules when `text` differs from what's already rendered/pending, so unrelated
        /// SwiftUI updates (window resize, split-divider drag) don't restart the debounce timer.
        func scheduleRender(of text: String, in webView: WKWebView, after interval: TimeInterval) {
            guard text != lastRenderedText else { return }
            pendingRenderWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.render(text, in: webView)
            }
            pendingRenderWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
        }

        /// Content changes take the existing debounced-render path above — `render` resyncs scroll
        /// position itself once its DOM patch completes, since a mid-typing scroll would run
        /// against a stale DOM. Pure cursor movement with no pending content change (a click or
        /// arrow key) scrolls directly instead, lightly debounced.
        func update(text: String, cursorLine: Int, in webView: WKWebView, renderDebounce: TimeInterval, scrollDebounce: TimeInterval) {
            guard text == lastKnownText else {
                lastKnownText = text
                lastKnownCursorLine = cursorLine
                // A scroll queued by an earlier pure cursor move is now stale against the incoming
                // content change and would otherwise fire independently of this render's own
                // post-patch resync -- drop it, `render` will resync once its DOM patch completes.
                pendingScrollWorkItem?.cancel()
                scheduleRender(of: text, in: webView, after: renderDebounce)
                return
            }
            guard cursorLine != lastKnownCursorLine else { return }
            lastKnownCursorLine = cursorLine
            pendingScrollWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.scrollToLine(cursorLine, in: webView, animated: true)
            }
            pendingScrollWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollDebounce, execute: workItem)
        }

        /// Finds the last block whose `data-source-line` is at or before `line` (block source lines
        /// are monotonically non-decreasing in document order, so a linear scan is correct and,
        /// at the file sizes this app targets, plenty fast) and centers it in the preview. Falls
        /// back to the first tagged block when `line` precedes every tagged line (e.g. the cursor
        /// sits on blank lines before the document's first heading/paragraph) rather than leaving
        /// the preview wherever it happened to be scrolled.
        func scrollToLine(_ line: Int, in webView: WKWebView, animated: Bool) {
            let behavior = animated ? "smooth" : "auto"
            let js = """
            (function() {
              var nodes = document.querySelectorAll('[data-source-line]');
              var target = null;
              for (var i = 0; i < nodes.length; i++) {
                if (parseInt(nodes[i].getAttribute('data-source-line'), 10) <= \(line)) {
                  target = nodes[i];
                } else {
                  break;
                }
              }
              if (!target && nodes.length > 0) {
                target = nodes[0];
              }
              if (target) {
                target.scrollIntoView({ block: 'center', behavior: '\(behavior)' });
              }
            })();
            """
            webView.evaluateJavaScript(js)
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

        /// Only fires for the one-time initial `loadHTMLString` navigation now (later content
        /// changes patch the DOM in place via `render`, which resyncs scroll itself once that JS
        /// call completes) — positions the freshly loaded page at the starting cursor line.
        ///
        /// A content change can arrive (via `update`) while this navigation is still in flight;
        /// `render` no-ops those until `isInitialLoadComplete` flips, so `lastKnownText` can be
        /// ahead of `lastRenderedText` here. Catch up with a real render (which resyncs scroll
        /// itself) instead of just scrolling the stale initial content.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isInitialLoadComplete = true
            if let lastKnownText, lastKnownText != lastRenderedText {
                pendingRenderWorkItem?.cancel()
                render(lastKnownText, in: webView)
            } else {
                scrollToLine(lastKnownCursorLine, in: webView, animated: false)
            }
        }
    }
}

#Preview {
    PreviewView(text: .constant("# Heading\n\nSome **bold** and *italic* text.\n"), cursorLine: 1)
        .frame(width: 500, height: 400)
}
