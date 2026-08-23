# Homebrew Cask distribution for MarkdownEditor

## Context

The app currently only runs from a local Xcode build (`scripts/build-and-install.sh` installs to `~/Applications`). The goal is to distribute it via a personal Homebrew Cask tap so it can be installed on multiple laptops and shared with other people, without an Apple Developer Program membership. Without notarization, Gatekeeper will block first launch on any Mac other than the one it was built on — the accepted mitigation is handling that via System Settings → Privacy & Security → "Open Anyway" per machine/version, so no Gatekeeper-bypass automation (e.g. `--no-quarantine`) is needed.

Decisions locked in:
- **`primeminister/markdown-editor` becomes public**, after a pre-publicity audit (step 1). Keeping it private would force every installer to configure a GitHub PAT (`HOMEBREW_GITHUB_API_TOKEN`) and be added as a collaborator just to `brew install`.
- **Releases are built by GitHub Actions on tag push**, not a local script, so cutting a release doesn't depend on running Xcode on the owner's own Mac.
- **License: MIT**, on both repos.
- The git history contains a commit author email tied to an employer (`charlie.van.de.kerkhof@external.mercell.com`). Decision: **leave it** — it's not a secret, and rewriting history (force-push, new commit hashes) is a bigger risk than the exposure itself.

Relevant current state (verified by reading the repo, not assumed):
- `MarkdownEditor.xcodeproj`: `CODE_SIGN_STYLE = Automatic`, no team set, `ENABLE_APP_SANDBOX = YES`, `REGISTER_APP_GROUPS = YES`, `MARKETING_VERSION = 1.0`, bundle id `nl.mowd.MarkdownEditor`.
- Git tags already exist (`1.0.0`, `1.1.0`, `1.1.1`, `1.1.2`) with matching GitHub Releases, but **none have binary assets attached** — the `MARKETING_VERSION` in the project (`1.0`) has never tracked these tags.
- `scripts/build-and-install.sh` does a local Release build + copy to `~/Applications`; it's a useful reference for the build invocation but doesn't zip/sign/publish anything.
- CI (`.github/workflows/ci.yml`) already runs `xcodebuild test` on `macos-latest`, so a `macos-latest` Actions runner is already known to work for this project.

## Steps

### 1. Pre-publicity safety audit (do this before flipping visibility)
Already checked, results below — re-verify at execution time in case anything changed since:
- **Secrets/credentials**: full `git log -p --all` scan for key/token/password patterns and a filename scan (`.env`, `.p12`, `.pem`, `.mobileprovision`, `id_rsa`, etc.) both came back clean. No tracked file matches either.
- **Signing material**: no `DEVELOPMENT_TEAM` value anywhere in `project.pbxproj` (all blank/Automatic with no team) — no Apple Developer team ID to leak.
- **`REGISTER_APP_GROUPS = YES`**: no `.entitlements` file exists in the repo and no app-group identifier is configured anywhere — this looks like an inert leftover Xcode default, not a real capability. Worth confirming it's truly unused (nothing in code references an app-group container) before going public, since an app group ID can imply a specific Apple Developer account.
- **CI exposure surface**: `.github/workflows/ci.yml` triggers on plain `pull_request` (not `pull_request_target`), and the repo has no configured Actions secrets (`gh secret list` is empty). This is the safe pattern — GitHub does not forward secrets/write-scoped tokens to `pull_request` runs from forks — so once public, strangers opening PRs can't exfiltrate anything via CI. No change needed here, just confirmed safe.
- **Commit author identity**: history contains `charlie.van.de.kerkhof@external.mercell.com` (see decision above — leaving as-is).
- **`.gitignore`**: standard Xcode template, covers `xcuserdata/`, `.DS_Store`, `.build/` — adequate, nothing sensitive is being tracked that shouldn't be.

Net result: nothing blocks going public. If re-running this audit later turns up a hit in the secret/filename scans, stop and rotate/remove before proceeding — that's the one category worth treating as a hard blocker.

### 2. Make the repo public
One-time `gh repo edit primeminister/markdown-editor --visibility public` (requires explicit owner confirmation at execution time — this is a real, hard-to-reverse visibility change, not something to do silently).

### 3. Add a license
MIT on both `markdown-editor` and `homebrew-tap` — add a `LICENSE` file (standard MIT text, copyright holder Charlie van de kerkhof) at the root of each repo. Since the app links Apple's `swift-markdown` (Apache-2.0) via SwiftPM and now redistributes compiled binaries publicly, also add a short third-party notices note (e.g. in the README) crediting swift-markdown and its license — MIT itself doesn't require this, but Apache-2.0's redistribution terms expect the license/notice to travel with binaries built from it.

### 4. Decouple app version from the Xcode project default
`MARKETING_VERSION = 1.0` in the pbxproj is a static build setting baked into the generated `Info.plist` as `CFBundleShortVersionString` (via `GENERATE_INFOPLIST_FILE = YES`) — it's what shows up as the app's version (About panel, `CFBundleShortVersionString`), and today it's stale (`1.0`, never bumped even though 4 releases have shipped).

The fix: **don't hand-edit the pbxproj per release.** In the release workflow (step 5), pass the tag as a command-line build-setting override —
```
xcodebuild ... build MARKETING_VERSION="$VERSION"
```
An `xcodebuild` command-line override always wins over the project file's default for that invocation, and because `GENERATE_INFOPLIST_FILE = YES`, Xcode substitutes it straight into the generated `Info.plist`'s `CFBundleShortVersionString` — no separate Info.plist edit needed. `$VERSION` comes directly from the pushed tag (`GITHUB_REF_NAME` in Actions, e.g. `1.2.0` — no `v` prefix to strip, matching the existing tag convention).

This makes the **git tag the single source of truth** for what version ships — the pbxproj's checked-in `1.0` is only ever seen in ad-hoc local Xcode debug builds, which is fine (dev builds aren't expected to show a meaningful version). The Homebrew Cask's own `version` field (step 7) is a separate, manually-set value in the tap formula that must match the tag when bumping — Homebrew doesn't introspect the app to discover it, it's just used to build the release-asset download URL.

### 5. Add `.github/workflows/release.yml`
Triggered on tag push matching the existing semver pattern (e.g. `on: push: tags: ['[0-9]+.[0-9]+.[0-9]+']`). Job on `macos-latest`:
1. Checkout, let Xcode/SwiftPM resolve `swift-markdown` (same as CI).
2. Build Release **with explicit ad-hoc signing overrides**, since Actions runners have no Apple ID/team signed into Xcode and `CODE_SIGN_STYLE=Automatic` will otherwise fail trying to contact Apple's developer portal for provisioning (App Sandbox + the registered App Group both normally go through that):
   ```
   xcodebuild -project MarkdownEditor/MarkdownEditor.xcodeproj -scheme MarkdownEditor \
     -configuration Release build \
     CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES \
     DEVELOPMENT_TEAM="" MARKETING_VERSION="$VERSION"
   ```
   **Verify this override actually builds cleanly before wiring up the workflow** — test it locally first (it's a good proxy for "no Apple ID available"). Step 1's audit found `REGISTER_APP_GROUPS` has no backing entitlements/group ID, so it shouldn't force portal access, but confirm the local test build agrees.
3. Locate the built `.app` (same `-showBuildSettings` / `BUILT_PRODUCTS_DIR` trick as `scripts/build-and-install.sh`), zip it with `ditto -c -k --keepParent` (preserves the bundle correctly, unlike plain `zip -r`) as `MarkdownEditor-$VERSION.zip`.
4. Compute its sha256.
5. `gh release upload` the zip (and a `.sha256` file) onto the release for the pushed tag — reuse the existing release if the tag already has one (as it will for future tags created the way `1.1.2` etc. were), or create it if not.

### 6. Cut a real release through the new pipeline
Bump to a new tag (e.g. `1.2.0`) once the workflow is in place, rather than trying to backfill assets onto the existing asset-less tags. This becomes the first version the tap can actually install.

### 7. Create the tap repo: `primeminister/homebrew-tap`
Public, separate from the app repo (standard Homebrew convention — lets `brew tap primeminister/tap` work). Contains `Casks/markdown-editor.rb`:
```ruby
cask "markdown-editor" do
  version "1.2.0"
  sha256 "<from step 3's checksum output>"

  url "https://github.com/primeminister/markdown-editor/releases/download/#{version}/MarkdownEditor-#{version}.zip"
  name "MarkdownEditor"
  desc "Simple two-pane markdown editor with live HTML preview"
  homepage "https://github.com/primeminister/markdown-editor"

  depends_on macos: ">= :sequoia"  # matches MACOSX_DEPLOYMENT_TARGET = 15.6

  app "MarkdownEditor.app"
end
```
No `zap` stanza needed for now — the app is sandboxed, so its data lives in the sandbox container rather than scattered `~/Library` locations. Skip `livecheck` for now (low release frequency, manual bump is fine); can add later if desired.

### 8. Install / update flow (for the owner and anyone they share this with)
- Install: `brew tap primeminister/tap && brew install --cask markdown-editor`
- First launch: Gatekeeper blocks it → System Settings → Privacy & Security → "Open Anyway" → confirm in the follow-up dialog. This repeats **once per new version** (new build = new ad-hoc signature), not just once ever.
- Update: after the tap repo's cask is bumped for a new release, `brew upgrade --cask markdown-editor`.

### 9. Repo workflow conventions
Per `CLAUDE.md`: the `release.yml` workflow, version-handling change, and `LICENSE` addition in the main repo are infra/chore work, not a plan milestone, so they go on a short-lived branch (e.g. `homebrew-release-pipeline`) with a normal PR — run `/code-review` on the diff before opening it, same as any other change. The new `homebrew-tap` repo is separate, low-stakes, and solo-maintained; a direct commit there (no PR ceremony) is reasonable, but that's the owner's call at execution time.

### 10. End-to-end verification
1. Push the new tag, confirm the Actions run is green and the release asset + sha256 are attached with the expected filename.
2. Fill in the tap's cask file with that version/sha256, commit/push.
3. On the owner's Mac (or ideally a second one), `brew tap primeminister/tap` + `brew install --cask markdown-editor` into a clean state, confirm the Open Anyway flow works, and confirm the app actually launches and can open/save a `.md` file (sandbox entitlements still behaving correctly outside of a debug-run-from-Xcode environment is the main thing worth double-checking here).
4. Cut a second dummy version bump end-to-end to confirm `brew upgrade --cask markdown-editor` picks it up correctly, before considering the pipeline done.

### 11. Repo security hardening (do this right after step 2, once public)
Confirmed via the GitHub API today: branch protection and rulesets are **unavailable on this repo right now** — `gh api repos/primeminister/markdown-editor/branches/main/protection` returns 403 "Upgrade to GitHub Pro or make this repository public." Also confirmed: `primeminister` is currently the *only* collaborator (admin), so this is about locking in that model technically and adding public-repo-specific safety nets, not fixing an existing access problem.

Decision: require PR + passing CI on `main`, but **not** a numeric approval count — GitHub blocks self-approval, so a "1 approval required" rule is unenforceable for a true solo maintainer without either a bypass-list workaround or a second account/bot. If outside collaborators or a steady stream of external PRs materialize later, revisit with a Ruleset + `CODEOWNERS` (`* @primeminister`) instead of classic branch protection.

Once public, set up (via repo Settings, or `gh api` PUT):
1. **Branch protection rule on `main`**: require a pull request before merging (blocks direct `git push` to `main`, including from the owner — merging your own PR via the button after CI passes is still how you land changes); require the existing `CI / test` status check (`.github/workflows/ci.yml`) to pass before merging; block force-pushes and branch deletion on `main`; include administrators in these restrictions (so the "always use a PR" rule in `CLAUDE.md` is enforced, not just conventional).
2. **Actions fork-PR gate**: Settings → Actions → General → set "Fork pull request workflows from outside collaborators" to *Require approval for all outside collaborators*. CI already only triggers on `pull_request` (not `pull_request_target`) with no repo secrets configured, so this isn't plugging a secret leak — it stops random forks from running arbitrary code on your Actions minutes without you clicking "Approve and run" first.
3. **Secret scanning + push protection**: enable under Settings → Code security. Free and automatic once public; push protection actively blocks a future commit containing a recognizable secret pattern before it's even pushed — cheap extra insurance layered on top of the one-time manual audit already done in step 1.
4. **Private vulnerability reporting** (optional, low effort): enable so a real security report lands privately instead of as a public issue.
5. Add one line to `CLAUDE.md`'s workflow section noting the "never commit directly to main" rule is now GitHub-enforced (branch protection), not just convention.
