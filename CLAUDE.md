# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

M1–M4 (all milestones in `docs/plan.md`) are complete and merged. This is a working macOS SwiftUI document-based markdown editor with a two-pane editor/preview layout.

## Project intent

Per the README, this is a personal macOS markdown editor: classic two-pane layout (plain-text editor with syntax highlighting on one side, rendered HTML preview on the other), plain `.md` files on disk, no App Store distribution — build & run from Xcode on the owner's own Macs. Full design rationale and milestone breakdown is in `docs/plan.md`.

## Build/run/test commands

The Xcode project is at `MarkdownEditor/MarkdownEditor.xcodeproj`, scheme `MarkdownEditor`.

- **Build:** `xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -configuration Debug build`
- **Test (full suite):** `xcodebuild test -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor -destination 'platform=macOS'`
- **Test (single test/suite):** add `-only-testing:MarkdownEditorTests/<SuiteName>/<testName>` (or just `.../<SuiteName>` for a whole suite) to the test command, e.g. `-only-testing:MarkdownEditorTests/MarkdownHighlighterTests/headerMatchesHashPrefixedLine`.
- **Run:** `open` the built `.app` from DerivedData after `xcodebuild build` (path printed in the build log), or open `MarkdownEditor/MarkdownEditor.xcodeproj` in Xcode and Cmd+R.
- CI (`.github/workflows/ci.yml`) runs the same `xcodebuild test` command on `macos-latest` for every push/PR.
- No linter/formatter (SwiftLint/SwiftFormat) is configured.

## Architecture

- **`MarkdownEditorApp.swift`** — `@main` entry point. `DocumentGroup(newDocument: MarkdownDocument())` scene; passes each open file's document binding and `fileURL` into `ContentView`.
- **`MarkdownDocument.swift`** — `FileDocument` wrapping a plain `String`. Reads/writes UTF-8 `Data`; declares `UTType.markdownText` (imports `net.daringfireball.markdown`).
- **`ContentView.swift`** — top-level view per document window. Owns `@AppStorage("isPreviewVisible")` (preview toggle, shared across windows) and a per-document `autosaveIdentifier` (the file's path, or a random per-window fallback for untitled documents) used to scope AppKit autosave keys so multiple open windows don't clobber each other's saved layout. Renders `SplitView` plus a toolbar button that toggles preview visibility.
- **`SplitView.swift`** — `NSViewControllerRepresentable` wrapping `MainSplitViewController`, an `NSSplitViewController` with two items (editor, preview), each hosting `EditorView`/`PreviewView` via `NSHostingController<AnyView>`. Handles: divider-position persistence (`splitView.autosaveName`), window-frame persistence (`setFrameAutosaveName`, guarded to only apply once per appearance), and animated preview collapse/expand. `updateNSViewController` reassigns both hosting controllers' `rootView` on every SwiftUI update — required for `EditorView`/`PreviewView` to keep receiving live text changes, since AppKit doesn't re-diff a hosting controller's `rootView` on its own.
- **`EditorView.swift`** — `NSViewRepresentable` wrapping an `NSTextView` (via `NSTextView.scrollableTextView()`). `Coordinator` is both `NSTextViewDelegate` (pushes keystrokes into the `text` binding) and `NSTextStorageDelegate` (re-applies highlighting via `MarkdownHighlighter` on every edit — full-document rescan, no incremental/debounced highlighting).
- **`MarkdownHighlighter.swift`** — static `NSRegularExpression`-based rules for 7 token types: headers, bold, italic, inline code, links, fenced code, blockquotes.
- **`PreviewView.swift`** — `NSViewRepresentable` wrapping a `WKWebView`. Debounces re-render (~275ms) via `MarkdownRenderer`; `WKNavigationDelegate` opens clicked links in the default browser instead of in-pane.
- **`MarkdownRenderer.swift`** — uses Apple's `swift-markdown` package (a `MarkupVisitor`) to turn markdown into an HTML string, escaping raw HTML from the source; wraps it in an HTML document shell with `PreviewStyle.css` inlined.
- **`PreviewStyle.css`** — bundled resource: typography/code/table/blockquote styling, dark mode via `prefers-color-scheme`.
- **`Info.plist`** — UTI declarations (`UTImportedTypeDeclarations`/`UTExportedTypeDeclarations`/`CFBundleDocumentTypes`) for `.md` file association.
- **Tests** — `MarkdownEditorTests` (Swift Testing): `MarkdownDocumentTests`, `MarkdownHighlighterTests`, `MarkdownRendererTests`, covering only pure logic (no AppKit/WebKit). `MarkdownEditorUITests` has the Xcode-template launch/performance tests only.

## Development workflow

This is a solo/personal project (`primeminister/markdown-editor` on GitHub, default branch `main`), but it still uses a PR-based workflow for review discipline:

- **Never commit directly to `main`.** All work happens on a feature branch, pushed and opened as a PR via `gh pr create`. This is now GitHub-enforced, not just convention: branch protection on `main` requires a PR (including for admins) and a passing `test` status check, and blocks force-pushes/deletion — set up 2026-08-23 per `docs/plan-homebrew.md` step 11.
- **One PR per milestone.** `docs/plan.md` defines milestones M1–M4, each independently runnable/testable — each milestone is one PR (e.g. branch `m1-skeleton-open-save`, PR title `M1: skeleton, open/save round-trip`). If work doesn't map to a plan milestone (bugfix, chore, plan update), use a short descriptive branch name instead.
- **Before opening a PR, run `/code-review` on the diff.** Fix findings you're confident about; if anything uncertain remains, note it explicitly in the PR description rather than silently dropping it.
- **Verify the build/tests before opening the PR** — once the Xcode project exists, run `xcodebuild build` and `xcodebuild test -scheme MarkdownEditor -destination 'platform=macOS'` locally, not just eyeball the diff. CI (`.github/workflows/ci.yml`, added in the M1 PR) re-runs the same test command on every push/PR as a second check.
- **Testing has two layers — see `docs/plan.md`'s "Testing strategy" section:**
  - *Automated* (Swift Testing, `MarkdownEditorTests` target): unit tests for pure logic only (`MarkdownDocument` round-trip, `MarkdownHighlighter` token matching, `MarkdownRenderer` HTML output, small pure helpers). Add these as part of the milestone that introduces the logic, not as a separate follow-up PR.
  - *Manual* (per milestone, owner's Mac): anything involving real AppKit/WKWebView behavior or typing feel. After a milestone's automated tests and code review pass, build and launch the app (`xcodebuild build` then `open`) and hand the owner the milestone's "Verify:" checklist from `docs/plan.md`. **Wait for the owner's go-ahead on the manual checklist before merging** — automated tests passing is not sufficient on its own for milestone PRs.
- **Never merge the PR.** Once the PR is opened (code review clean, automated tests passing, and — for milestone PRs — the owner has confirmed the manual checklist), stop there. The owner merges every PR themselves, manually. Do not run `gh pr merge` under any circumstances, even if asked to "finish up" or "wrap up" the PR — surface that it's ready and wait.
- PR descriptions should reference the milestone/plan section they implement, list what automated tests were added, and list the manual "Verify:" bullets to be checked.

## Subagents/forks must never touch git or GitHub state

This happened twice already: a subagent/fork dispatched for a narrow, read-only task (checking one code detail, verifying one `/code-review` finding) instead went on to run `git commit`, `git push`, and `gh pr create` on its own initiative — because it inherited this file's workflow instructions as context and treated "open the PR" as the obvious next step, even though nothing in its prompt asked for that.

- **Never delegate `git commit`, `git push`, `gh pr create`, `gh pr merge`, or any other mutating git/GitHub command to a subagent or fork, regardless of what the task is framed as.** Only the primary agent runs these, directly, after the user has approved the specific action (per the standard risky-action confirmation policy) — never as a side effect of a research/verification/fix task handed to a subagent.
- When prompting a subagent/fork for research, review, or verification, explicitly state it is read-only and must not run any mutating command — but treat this as a mitigation, not a guarantee: a fork's tool access is never actually scoped down to match its prompt.
- After any subagent/fork finishes a task that touched this repo, verify ground truth (`git status`, `git log`, `gh pr list`) before trusting its self-report — a fork's summary of what it did can itself be wrong.
- If a subagent/fork is found to have pushed or opened a PR without authorization, surface this to the user explicitly and immediately — do not quietly adopt the result into the plan.
