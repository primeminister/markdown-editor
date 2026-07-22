# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

This repository is a placeholder — it currently contains only this file, a `README.md`, and a `.gitignore`. No source code, Xcode project, or Swift Package Manager manifest exists yet.

## Project intent

Per the README, this will be a macOS markdown editor. The `.gitignore` is the standard Xcode/Swift template, implying the app will be built with Xcode (Swift/SwiftUI or AppKit), rather than a web or cross-platform stack.
A plan is made and is written in docs/plan.md

## Next steps for whoever scaffolds this project

Once real source is added (e.g. an `.xcodeproj`/`.xcworkspace`, `Package.swift`, or SwiftUI app target), update this file with:
- Build/run/test commands (e.g. `xcodebuild`, `swift build`, `swift test`, or Xcode scheme names) and how to run a single test.
- The high-level architecture: app entry point, how the editor/preview views are structured, and any data model for documents.
- Any linting/formatting tooling adopted (e.g. SwiftLint/SwiftFormat) and its invocation.

## Development workflow

This is a solo/personal project (`primeminister/markdown-editor` on GitHub, default branch `main`), but it still uses a PR-based workflow for review discipline:

- **Never commit directly to `main`.** All work happens on a feature branch, pushed and opened as a PR via `gh pr create`.
- **One PR per milestone.** `docs/plan.md` defines milestones M1–M4, each independently runnable/testable — each milestone is one PR (e.g. branch `m1-skeleton-open-save`, PR title `M1: skeleton, open/save round-trip`). If work doesn't map to a plan milestone (bugfix, chore, plan update), use a short descriptive branch name instead.
- **Before opening a PR, run `/code-review` on the diff.** Fix findings you're confident about; if anything uncertain remains, note it explicitly in the PR description rather than silently dropping it.
- **Verify the build/tests before opening the PR** — once the Xcode project exists, run `xcodebuild build` and `xcodebuild test -scheme MarkdownEditor -destination 'platform=macOS'` locally, not just eyeball the diff. CI (`.github/workflows/ci.yml`, added in the M1 PR) re-runs the same test command on every push/PR as a second check.
- **Testing has two layers — see `docs/plan.md`'s "Testing strategy" section:**
  - *Automated* (Swift Testing, `MarkdownEditorTests` target): unit tests for pure logic only (`MarkdownDocument` round-trip, `MarkdownHighlighter` token matching, `MarkdownRenderer` HTML output, small pure helpers). Add these as part of the milestone that introduces the logic, not as a separate follow-up PR.
  - *Manual* (per milestone, owner's Mac): anything involving real AppKit/WKWebView behavior or typing feel. After a milestone's automated tests and code review pass, build and launch the app (`xcodebuild build` then `open`) and hand the owner the milestone's "Verify:" checklist from `docs/plan.md`. **Wait for the owner's go-ahead on the manual checklist before merging** — automated tests passing is not sufficient on its own for milestone PRs.
- **Merge the PR yourself** (`gh pr merge`) once: code review is clean, automated tests (local + CI) pass, and — for milestone PRs — the owner has confirmed the manual checklist. Still surface anything unusual before merging rather than merging silently.
- PR descriptions should reference the milestone/plan section they implement, list what automated tests were added, and list the manual "Verify:" bullets to be checked.
