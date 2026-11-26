# Changelog

## 0.3.0 — Universal Device Connectivity and Engineering Roadmap

- Universal Connectivity Center (25 categories), Device Connectivity Encyclopedia (17 sourced profiles, information
  requests, tolerant user-profile JSON that cannot claim HCG verification), Universal Protocol Registry (27 protocols with
  separate discovery/communication support, dependencies, permissions and validation status), equipment catalogue and
  Hardware Requirements Center (detected vs declared).
- macOS connectivity layer, all user-started and read-only: Core Bluetooth scan and allow-listed GATT read
  (Device Information, Battery) with automatic disconnect; paired Bluetooth Classic list; DNS-SD browse of declared
  service types; one-shot SSDP M-SEARCH and UPnP description (private LAN hosts only); Samsung TV `:8001/api/v2/`;
  host interfaces; HCG AI public handoff check. Info.plist usage descriptions and `NSBonjourServices`.
- Evidence model (discovered / connection attempt / diagnostics / your report) fed automatically by IOKit discovery,
  Apple device intelligence and diagnostic runs; synthetic evidence recorded but excluded.
- Living Development Roadmap (17 states, manual decisions with refusal rules, full history kept across disconnects),
  Development Gap Analyzer (11 gap kinds, stable IDs, dependencies, priorities), proposed LifeOS quests
  (`hcg.lifeos.backlog` schema 2, no XP), 14-step Guided Connection Studio with single-use approval, Live Connection
  Center, Compatibility Matrix, Connection History, rule-based Connection Assistant with redacted research requests.
- Ecosystem: HCG AI, HCG LifeOS and HCG Vanguard (no contract found) entries; 11 new navigation routes.
- `hcg-probe --connectivity [--ssdp]`; CI renders all new sections.

## 0.2.0 — Device Intelligence Update

- Universal Device Intelligence Engine: provider protocol, sourced fields (every value names its tool and key; every gap
  its reason), 13-state connection ladder with evidence and next actions, timeline, generic USB provider, planned
  families listed without claiming support.
- Apple Device Intelligence Adapter (reference implementation): runtime Xcode/devicectl capability inspection,
  `devicectl list devices` / `device info details` / `lockState` / `apps` / `manage pair` via allow-listed argument
  vectors and JSON output, UDID↔USB-serial correlation, model facts (USB capability), optional libimobiledevice battery and
  disk usage, user-confirmed pairing, 11 read-only Apple diagnostics.
- Device Intelligence workspace (7 tabs) with device illustration; Live Device Monitor; USB Connection Inspector
  (endpoints, drivers, connection classes); Connection Visualizer 2.0 (interface satellites, authorization badges,
  double-click to workspace).
- Device-side authorization evidence (pairing) feeds the connectivity layers: a paired, answering iPhone reaches
  *Authenticated*; an enumerated one stays *Diagnostics available*.
- Reports: device information / compatibility / diagnostic reports (`hcg.systemtester.device-report/1`), identifiers
  redacted by default; inventory snapshot (`hcg.systemtester.inventory/1`) and Sentinel connection-security findings.
- Adapter Developer Studio: Apple reference project, synthetic fixture editor.
- `hcg-probe --toolchain`, `--apple [--pair]`; icon script accepts a supplied PNG; CI verifies the icon is bundled.

## 0.1.0 — first working MVP

- Native macOS SwiftUI workstation with 10 sections: Command Center, Connected Systems, Connection Visualizer, Diagnostics,
  Device Laboratory, Adapter Library, Adapter Developer Studio, HCG Ecosystem, Reports and Settings.
- Real hardware discovery through IOKit: `IOUSBHostDevice` and `IOThunderboltSwitch`, with live attach/detach notifications
  and settle re-reads for drivers, disks and serial nodes.
- Universal Device Identification Engine with 40+ profiles, confidence scores, evidence and known limitations.
- Five-layer connectivity assessment and an enforced lifecycle state machine.
- Hardware Adapter SDK `hcg.adapter-manifest/1`: validator, registry, trust model (untrusted until approved), 11 first-party
  adapters and an example manifest.
- Diagnostic Engine: 14 host operations, impact levels (read-only / extended / state-changing), authorisation gate, audit log,
  and handling of disconnection during tests.
- Device Laboratory: saved profiles (fingerprint keys), connection history, sessions, measurement timelines, comparison and
  compatibility evidence.
- Reports: Markdown, `hcg.systemtester.report/1` JSON and HCG Device Link `hcg.diagnostic-report/1`, all redacted.
- Labelled synthetic fixtures, an opt-in synthetic bus and a synthetic fault-injection operation.
- `hcg-probe` CLI, Xcode project, `scripts/build-app.sh`, Executable Maker `AppPackaging.json`, and GitHub Actions macOS CI
  (build, tests, real-IORegistry probe, app bundle, Xcode build, UI snapshots).
