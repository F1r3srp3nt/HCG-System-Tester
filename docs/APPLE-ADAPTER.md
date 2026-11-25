# Apple Device Intelligence Adapter — reference implementation

`com.hakmicapitalgroup.adapter.apple-device-intelligence` · v0.2.0 · first device-family adapter of the
Universal Device Intelligence Engine.

## What it uses, and why

The installed Xcode is inspected at runtime before any method is chosen (`AppleToolchainInspector`):

| Probe | Purpose |
|---|---|
| `xcode-select -p` + `<Xcode>/Contents/version.plist` | Xcode version/build (structured plist); detects Command-Line-Tools-only setups |
| `xcrun --find devicectl`, `xcrun devicectl --version` | Is CoreDevice tooling present |
| `xcrun devicectl device info --help`, `xcrun devicectl manage --help` | Which subcommands this Xcode offers (`details`, `lockState`, `apps`, `pair`) — capability probe only |
| `/opt/homebrew/bin`, `/usr/local/bin` | Optional, user-installed libimobiledevice (`ideviceinfo`, `idevicepair`) |

Information sources, all read-only:

| Source | Command (argument vector, never a shell) | Provides |
|---|---|---|
| IOKit `IOUSBHostDevice` | — | VID/PID, USB strings, speed, interfaces (usbmux FF.FE.02, PTP, NCM), topology, USB serial (sensitive) |
| CoreDevice | `xcrun devicectl list devices --timeout 5 --json-output <tmp>` | name, model (marketingName), productType, hardwareModel, platform, OS version/build, UDID/serial/ECID (sensitive), storage capacity, pairing state, transport, tunnel state, Developer Mode, DDI services, capabilities |
| CoreDevice (paired) | `xcrun devicectl device info details --device <id> --json-output <tmp>` | live properties answered by the device → **communication established**; also timed for latency |
| CoreDevice (paired, if offered) | `xcrun devicectl device info lockState …` | lock state keys as reported |
| CoreDevice (paired, on your request) | `xcrun devicectl device info apps …` | installed applications |
| CoreDevice (on your click) | `xcrun devicectl manage pair --device <id> …` | starts Apple's pairing flow; you tap **Trust** on the device |
| libimobiledevice (optional) | `ideviceinfo -u <udid> -x [-q com.apple.mobile.battery \| com.apple.disk_usage]` | battery level/charging, free space (XML plist) |

JSON output is parsed tolerantly (`DevicectlOutput`): every field is optional, unknown fields are ignored, and
devicectl error documents (`error.userInfo.NSLocalizedDescription`) are surfaced as the reason a field is missing.

## Correlation

A USB device is matched to its CoreDevice record by **UDID**: Apple devices report their UDID (without the hyphen) as the
USB serial number. If no serial is available and exactly one wired device is listed, the match is made by elimination and
labelled as such. Ambiguous cases are not matched.

## Connection ladder (13 states)

1 Waiting for device · 2 Physical device detected · 3 USB enumeration successful · 4 Device family identified ·
5 Supported protocol discovered · 6 Locked / authorization required · 7 Pairing available · 8 Pairing established ·
9 Authorized communication established · 10 Diagnostics available · 11 Connection limited · 12 Unsupported · 13 Disconnected

Each step is marked reached only with evidence (shown in the UI and reports). States 6, 7, 11 block progress and come
with a **next action** (unlock, trust/pair, select Xcode, …). Enumeration never implies communication: state 9 requires a
live answer from the device.

## Security boundaries

- Never bypasses passcodes, pairing/Trust, USB Restricted Mode, device locks or Activation Lock.
- Never enables Developer Mode or changes device settings. Pairing happens only after you click **Pair…** and confirm, and
  is completed by you on the device.
- Command allow-list (`AppleToolCommand`): fixed executables, validated identifiers (alphanumerics and `-`, no leading `-`),
  allow-listed libimobiledevice paths and domains. Nothing from devices, manifests or URLs can add commands.
- UDID, ECID, serial numbers and CoreDevice identifiers are flagged sensitive: masked in the UI (toggle) and redacted from
  every export unless you explicitly include them.

## Diagnostics (read-only)

`apple.usb-enumeration`, `apple.identification`, `apple.pairing-status`, `apple.service-availability`,
`apple.query-latency` (3 uncached live queries; end-to-end incl. devicectl start-up — an upper bound),
`apple.connection-stability` (10 s IOKit presence + CoreDevice re-check), `apple.device-information`,
`apple.reconnect-handling` (evaluates real disconnect/reconnect events; never simulated on hardware),
`apple.authorization-requirements`, `apple.compatibility` (Xcode/devicectl, cable speed vs model's USB capability,
transport), `apple.battery-storage`.

## Using it as a template

Adapter Developer Studio › **Load reference: Apple Device Intelligence** creates an editable, declarative copy
(`com.example.adapter.apple-reference`). Imported/declarative adapters can reuse the `apple.*` host operations but can
never run their own code.

## Known limitations

- Battery level and free space are not exposed by devicectl; they need optional libimobiledevice and pairing.
  Battery health/cycle count are not exposed by supported interfaces.
- `lockState` and `pair` availability depends on the Xcode version (detected at runtime).
- Latency includes tool start-up; it is an upper bound on device response time.
- Older devices/iOS versions not supported by your Xcode's CoreDevice remain at USB-level identification.
