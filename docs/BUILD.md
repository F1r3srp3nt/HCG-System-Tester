# Building and running HCG System Tester on macOS

Requirements: macOS 14 or later, Xcode 16 or later (Swift 5.10+ toolchain). Developed for a MacBook Pro 16" (M4 Max)
with Xcode 27.2. No administrator rights, drivers or Apple Developer account are needed for local builds.

## 1. Xcode (recommended for development)

```bash
open App/HCGSystemTester.xcodeproj
```

- Scheme **HCGSystemTester** → My Mac → **Run (⌘R)**.
- The app target is thin: `App/HCGSystemTester/AppMain.swift` launches `HCGSystemTesterApplication` from the local Swift
  package (`..`). Edit the code under `Sources/`; Xcode shows the package in the navigator.
- Signing: *Sign to Run Locally* (`CODE_SIGN_IDENTITY = -`), hardened runtime on, **not sandboxed** (see entitlements). To sign
  with your team, set *Signing & Capabilities → Team* and change the style to Automatic.
- If Xcode reports a package resolution error, use *File → Packages → Reset Package Caches*.

You can also open the package directly: `open Package.swift`, then pick the **HCGSystemTester** scheme. That runs the same app
without an `.app` bundle icon.

## 2. Build an .app without Xcode's IDE

```bash
scripts/build-app.sh            # release, this Mac's architecture, ad-hoc signed → dist/HCG System Tester.app
scripts/build-app.sh --universal --open
```

The script runs `swift build`, then assembles the bundle with `Packaging/Info.plist` and `Packaging/AppIcon.icns`, signs it
ad-hoc with the hardened runtime, and verifies it with `codesign --verify --strict`. The first launch of an ad-hoc signed app
copied from another Mac may need *right-click → Open*.

## 3. HCG Executable Maker

The repository is a SwiftPM package with an `AppPackaging.json` (`hcg-app-packaging/1`). In Executable Maker, choose
**New Build → this folder → product `HCGSystemTester`**. It uses the bundle identity, Info.plist template and icon from the contract.
There are no helpers or prebuild commands. Developer ID signing, notarisation and DMG/pkg creation are Executable Maker options.
Publishing stays manual.

## 4. Command line

```bash
swift build
swift test                       # core + hardware smoke tests
swift run hcg-probe              # one-shot list
swift run hcg-probe --watch      # live events: plug and unplug devices
swift run hcg-probe --json       # redacted JSON snapshot
swift run hcg-probe --diagnose   # read-only diagnostics on every device
swift run hcg-probe --synthetic --diagnose   # engine demo on labelled fixtures
swift run HCGSystemTester        # full app from SwiftPM
```

## Data locations

`~/Library/Application Support/com.hakmicapitalgroup.systemtester/`:

| File | Content |
|---|---|
| `laboratory.json` | Saved device profiles, sessions, runs, compatibility evidence (keyed by salted fingerprints) |
| `audit.jsonl` | Append-only audit trail of diagnostic operations and authorisation decisions |
| `Adapters/*.json` | Imported adapter manifests (untrusted until approved) |
| `studio-projects.json` | Adapter Developer Studio drafts |

Settings are stored in `UserDefaults` under `com.hakmicapitalgroup.systemtester.settings.v1`.

## Continuous integration

`.github/workflows/macos.yml` runs on a GitHub-hosted macOS runner. It builds the package, runs every test, probes the runner's
real IORegistry, diagnoses synthetic fixtures, builds the `.app` with `scripts/build-app.sh` and builds the Xcode project.
It publishes nothing.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Device not listed at all | The cable is charge-only, or the link is host-to-host (e.g. Mac ↔ console). Try a known data cable; check with `swift run hcg-probe --watch` and `system_profiler SPUSBDataType`. |
| Listed, but with no interfaces | Drivers are still attaching. The view refreshes after about 0.75 s, 2.5 s and 6 s. |
| Storage shows no BSD disk | The device is locked, encrypted, or not formatted for macOS. Discovery never mounts or reads the medium. |
| USB 3 device shows USB 2.0 | Cable, hub or port limitation. **Negotiated link speed** flags this as a warning. |
| `swift test` says "no such module XCTest" | Only the Command Line Tools are installed. Install Xcode or run `sudo xcode-select -s /Applications/Xcode.app`. |
