# Changelog

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
