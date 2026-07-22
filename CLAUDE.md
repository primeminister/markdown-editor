# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

This repository is a placeholder — it currently contains only this file, a `README.md`, and a `.gitignore`. No source code, Xcode project, or Swift Package Manager manifest exists yet.

## Project intent

Per the README, this will be a macOS markdown editor. The `.gitignore` is the standard Xcode/Swift template, implying the app will be built with Xcode (Swift/SwiftUI or AppKit), rather than a web or cross-platform stack.

## Next steps for whoever scaffolds this project

Once real source is added (e.g. an `.xcodeproj`/`.xcworkspace`, `Package.swift`, or SwiftUI app target), update this file with:
- Build/run/test commands (e.g. `xcodebuild`, `swift build`, `swift test`, or Xcode scheme names) and how to run a single test.
- The high-level architecture: app entry point, how the editor/preview views are structured, and any data model for documents.
- Any linting/formatting tooling adopted (e.g. SwiftLint/SwiftFormat) and its invocation.
