# Architecture

```
            ┌──────────────────────────── HCGSystemTesterUI (SwiftUI, @MainActor AppModel) ─────────────────────────────┐
            │ Command Center · Connected Systems · Visualizer · Diagnostics · Laboratory · Adapter Library · Studio ·   │
            │ Ecosystem · Reports · Settings                                                                             │
            └──────────────▲─────────────────────────────────────────────▲─────────────────────────────────────────────┘
                           │ DiscoveryEvent (hopped to main actor)          │ DiagnosticRun / reports / lab
┌──────────────────────────┴───────────┐            ┌─────────────────────────┴──────────────────────────────────────┐
│ HCGHardware                          │            │ HCGCore (platform-neutral, unit-tested)                         │
│  IOKitRegistryMonitor                │  attached/ │  DeviceInventory ─ IdentificationEngine ─ BuiltInProfiles       │
│   ├ IOKitUSBDiscovery (IOUSBHost…)   │──detached──▶   │                AdapterRegistry ─ ManifestValidator          │
│   └ IOKitThunderboltDiscovery        │            │   ├ ConnectivityAssessor (5 layers) → DeviceStateMachine        │
│  HostDiscovery, HostInfo             │◀──refresh──│  DiagnosticEngine ─ HostOperationCatalog (14 host tests)        │
└──────────────────────────────────────┘ (DeviceProbe)  AuthorizationStore · AuditLog · Redactor                       │
┌──────────────────────────────────────┐            │  DeviceLaboratory · ReportGenerator · TopologyBuilder           │
│ SyntheticDiscoveryBackend (opt-in)   │────────────▶  ProtocolCatalog · ConnectionCapabilityRegistry · HCGEcosystem  │
└──────────────────────────────────────┘            └────────────────────────────────────────────────────────────────┘
```

## Key decisions

1. **One codebase, two front doors.** All code lives in the Swift package. The Xcode project (`App/`) is a thin app target
   (entry point, Info.plist, entitlements, icon) linking `HCGSystemTesterUI`. `swift run HCGSystemTester`,
   `scripts/build-app.sh` and HCG Executable Maker build the same code.
2. **Core is platform-neutral.** `HCGCore` uses only Foundation. IOKit property dictionaries are parsed by
   `USBRegistryParser`, so parsing, identification, assessment, diagnostics and reports are all unit-tested without hardware.
3. **Discovery backends are interchangeable.** `DeviceDiscoveryBackend` (start/stop/snapshot/refresh) is implemented by the IOKit
   USB, IOKit Thunderbolt and synthetic backends. Network, Bluetooth and remote backends plug in the same way.
4. **Live, read-only IOKit.** `IOServiceAddMatchingNotification` (first-match and terminated) is armed on a private dispatch queue.
   Every new device is re-read at 0.75 s, 2.5 s and 6 s, because drivers, disks and serial nodes are published asynchronously.
   Nothing is opened, claimed or written.
5. **Honest status.** `ConnectivityAssessor` evaluates five layers. `DeviceStateMachine` enforces legal transitions (for example,
   *detected → authenticated* is impossible). *Connected* requires evidence of functional communication, which only an adapter
   that exchanged data can record.
6. **Provenance everywhere.** Devices, measurements, results, runs and reports carry `DataProvenance` (`hardware`, `synthetic`,
   `imported`). Synthetic devices have `synthetic:` IDs, a `[SYNTHETIC]` name prefix, their own topology bus, and labels in
   charts, reports and audit entries.
7. **Adapters are data.** See [ADAPTER-SDK.md](ADAPTER-SDK.md). First-party adapters may be `builtIn`. Imported adapters must be
   `declarative` and can only reference host operations.

## Device lifecycle

```
detected ──▶ identified ──▶ diagnosticsAvailable ──▶ connected ──▶ authenticated
   │             │  ▲               │  ▲                 │               │
   │             ▼  │               ▼  │                 ▼               ▼
   └──────▶ adapterRequired ◀──▶ unsupported        (any state) ──▶ disconnected ──▶ detected (re-attach continues the record)
```

## Concurrency

- IOKit callbacks run on each backend's serial queue. `AppModel` hops every event onto the main actor before it touches
  `DeviceInventory`, which is single-threaded by design.
- `DeviceProbe.refresh` (used by diagnostics) looks a device up by registry entry ID with
  `IOServiceGetMatchingService(IORegistryEntryIDMatching)`. It is thread-safe and needs no shared state.
- Diagnostics run as `async` tasks. A device that disappears mid-test throws `DiagnosticError.deviceDisconnected`. The engine
  records that test as **aborted** and aborts the remaining tests in the run.

## Persistence

- `DeviceLaboratory` stores JSON (`laboratory.json`), keyed by `DiscoveredDevice.stableKey`:
  `VID:PID:sn-<salted FNV fingerprint>`, or the port location when there is no serial number. Raw serial numbers are never keys.
- `AuditLog` is append-only JSON Lines.
- Imported manifests are stored under `Adapters/` and reloaded as untrusted on launch.
