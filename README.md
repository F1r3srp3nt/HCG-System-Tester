# HCG System Tester

**Modular system connectivity, hardware discovery and diagnostics for macOS.**
Hakmi Capital Group · `com.hakmicapitalgroup.systemtester` · version 0.1.0 · LifeOS realm: Sovereign Technology

> **EVERYTHING IS INTERCHANGEABLE.** Build. Connect. Discover. Diagnose. Improve.

Connect a device to your Mac through USB-C, USB-A (through an adapter), a hub or Thunderbolt. HCG System Tester finds it through
macOS's own IOKit registry and shows what it is. It also shows exactly how far communication actually goes:

| Layer | What it proves |
|---|---|
| Physical | An electrical data link exists |
| Enumeration | macOS read the device's descriptors |
| Protocol compatibility | A driver or adapter can speak one of its protocols |
| Authorization | You (and the device, where needed) authorised a session |
| Functional communication | Data was actually exchanged |

A recognised name or USB ID only ever results in **Identified**. A device is only shown as **Connected** after it has actually
exchanged data. Unknown devices are shown with their raw descriptors and are never assumed to support anything.

## Quick start (MacBook Pro, Apple silicon, Xcode)

```bash
git clone https://github.com/F1r3srp3nt/HCG-System-Tester.git
cd HCG-System-Tester
open App/HCGSystemTester.xcodeproj      # then press ⌘R
```

Plug in any USB device: it appears in the **Command Center** within about a second. Unplug it, and the disconnection is recorded.

**Without opening Xcode:**

```bash
scripts/build-app.sh --open             # builds dist/HCG System Tester.app (ad-hoc signed) and launches it
```

**From the terminal only:**

```bash
swift run hcg-probe --watch             # live attach/detach stream
swift run hcg-probe --diagnose          # list + read-only diagnostics on every device
swift run HCGSystemTester               # launch the full app from SwiftPM
```

See [docs/BUILD.md](docs/BUILD.md) for details and troubleshooting.

## What 0.1.0 contains

| Area | Status |
|---|---|
| Real USB discovery (IOKit `IOUSBHostDevice`, first-match + terminated notifications) | ✅ live |
| Thunderbolt / USB4 switch discovery (`IOThunderboltSwitch`) | ✅ live (switch-level) |
| Interfaces, drivers, BSD disks, serial `/dev/cu.*` nodes, link speed, topology | ✅ live |
| Universal Device Identification Engine (40+ profiles, confidence + evidence) | ✅ |
| Five-layer connectivity assessment + lifecycle state machine | ✅ |
| Hardware Adapter SDK (`hcg.adapter-manifest/1`), validator, registry, 11 first-party adapters | ✅ |
| Diagnostic Engine: 14 host operations, authorisation gate, audit log | ✅ read-only |
| Device Laboratory: profiles, history, sessions, timelines, comparison, compatibility evidence | ✅ |
| Connection Visualizer (animated, built from discovery data only) | ✅ |
| Adapter Developer Studio (manifest/profile editors, validation, synthetic testing, versions, import/export) | ✅ |
| Reports: Markdown, JSON, HCG Device Link `hcg.diagnostic-report/1` | ✅ redacted |
| Synthetic fixtures (opt-in, labelled SYNTHETIC everywhere) | ✅ |
| HCG ecosystem panel (Server, Terminal, Sentinel, Nexus, Connect, Signal Contractor, Executable Maker) | ✅ contracts only |
| Serial sessions, network/Bluetooth discovery, IoT, Device Link pairing, HCG Connect sign-in | 🔜 [roadmap](docs/ROADMAP.md) |

## Repository layout

```
Package.swift                 SwiftPM package (the single source of truth for code)
Sources/HCGCore               Platform-neutral engine: models, identification, adapters, diagnostics, lab, reports, redaction
Sources/HCGHardware           IOKit discovery backends (macOS)
Sources/HCGSystemTesterUI     SwiftUI workstation (10 sections)
Sources/HCGSystemTester       SwiftPM app executable
Sources/hcg-probe             Command-line probe
Tests/                        XCTest suites (core + live hardware smoke tests)
App/                          Native Xcode project (app target linking the package)
Packaging/, AppPackaging.json HCG Executable Maker packaging contract (hcg-app-packaging/1)
scripts/build-app.sh          Builds the .app from the package without Xcode
Examples/Adapters             SDK example manifest
docs/                         Architecture, SDK, testing, limitations, ecosystem, roadmap, LifeOS import
```

## Documentation

- [Build & run on macOS](docs/BUILD.md)
- [Physical-device test checklist](docs/PHYSICAL-TESTING.md)
- [Actual hardware compatibility limitations](docs/HARDWARE-LIMITATIONS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Hardware Adapter SDK](docs/ADAPTER-SDK.md)
- [HCG ecosystem integration](docs/ECOSYSTEM.md)
- [Security & privacy](docs/SECURITY.md)
- [Roadmap & milestones](docs/ROADMAP.md) · [proposed LifeOS import](docs/lifeos/hcg-system-tester.backlog.json)

## Safety principles

- Discovery is **read-only**. No drivers are installed, no administrator privileges are requested, and no device is modified.
- Imported adapters are **declarative data**. They can only compose host-implemented operations, they start untrusted and
  disabled, and they never run until you approve them.
- Extended tests need confirmation. State-changing operations need explicit authorisation for each device and each operation.
  Every decision is written to an audit log.
- Serial numbers, user paths, network identifiers and credentials are redacted from reports and logs.
- No console, phone or appliance security control is ever bypassed.
- Publication to HCG Store, GitHub Releases or any other channel is a manual decision. This repository only builds.
