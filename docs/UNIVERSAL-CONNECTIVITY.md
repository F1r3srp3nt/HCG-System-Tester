# Universal Connectivity — 0.3.0

System Tester 0.3.0 grows from "what is plugged into this Mac" into an engineering environment for **any** device:
what it is, how it can be reached, what is still missing, and what has actually been proven. The existing discovery,
device intelligence and diagnostics stay exactly as before; Universal Connectivity sits on top of them.

> **Nothing is claimed that has not been observed.** Research is labelled as research. Discovery is not communication.
> Compatibility is "validated" only after verified diagnostics *and* your recorded decision.

## Sections (sidebar → Universal Connectivity, menu **Connectivity**, ⌃⌘ + key)

| Section | Key | What it does |
|---|---|---|
| Universal Connectivity Center | ⌃⌘C | 25 connectivity categories, discovery controls (USB, Bluetooth LE, paired Bluetooth Classic, Bonjour, SSDP), totals |
| Device Encyclopedia | ⌃⌘E | Structured profiles; every fact shows its source; asks for your exact model, year, firmware, hardware revision |
| Connection Studio | ⌃⌘W | 14-step guided wizard; single-use approval; read-only attempt; explains exactly what must be developed when no adapter exists |
| Connected Devices | ⌃⌘K | Live Connection Center: live vs remembered devices, profile matches, explicit Connect / Disconnect (BLE) |
| Protocol Registry | ⌃⌘P | 27 protocols with separate discovery / communication support, dependencies, permissions, validation status |
| Hardware Requirements | ⌃⌘H | Cables, adapters, interfaces and software: detected on this Mac, or declared by you |
| Development Roadmap | ⌃⌘M | 17 states per device and protocol, automatic from evidence, manual decisions with notes, full history |
| Gap Analyzer | ⌃⌘G | Development requirements with dependencies, acceptance criteria, your priorities, LifeOS quest export |
| Compatibility Matrix | ⌃⌘X | Research vs real discovery vs real connection vs diagnostics vs your test report, per device |
| AI Connection Assistant | ⌃⌘A | Offline rule-based guidance (labelled *not AI*), HCG AI availability check, redacted research request |
| Connection History | ⌃⌘Y | Every discovery, attempt (failures too), diagnostic run and report; kept after devices disconnect |

Deep links: `hcgsystemtester://open/connectivity`, `encyclopedia`, `connection-studio`, `connected-devices`, `protocols`,
`hardware-requirements`, `roadmap`, `gaps`, `compatibility`, `assistant`, `history`.

All sections are created lazily: the connectivity model is built the first time a section opens or a device is observed,
and building it reads one local JSON file — it never scans, connects or sends anything.

## Knowledge sources

Every fact, method and reference carries one of:

| Source | Meaning |
|---|---|
| **Manufacturer** | Documented by the manufacturer or standards body |
| **Community** | Reported by the community (reverse engineering, forums, open-source projects) — not guaranteed |
| **AI suggestion** | Proposed by an AI — never treated as fact; never changes state |
| **HCG verified** | Physically verified by HCG with recorded evidence |
| **HCG note** | HCG research note / safety assessment |

User-supplied profiles (JSON files in `~/Library/Application Support/HCG System Tester/Encyclopedia/`) are accepted
with tolerant decoding but **cannot** claim *HCG verified*.

## Profiles shipped (all research unless stated)

PlayStation 5 · Samsung Smart TV (Tizen) · Audi R8 · John Deere tractors · ISOBUS agricultural equipment ·
industrial robot arms · ROS 2 robots · DJI drones · Raspberry Pi · Arduino · ESP32 · iPhone / iPad (*adapter
implemented*) · Mac · Windows PC · Linux computer · generic BLE sensors · Matter / HomeKit smart home.

Every profile lists what it needs from you (exact model, year, firmware, hardware revision) before anything specific is
claimed. Vehicle, agricultural, industrial-robot and drone profiles are **read-only research** with explicit prohibited
control actions.

## Protocol registry

Discovery and communication are declared separately. Validation status:

| Status | Protocols |
|---|---|
| Verified on hardware | USB (IOKit enumeration) |
| Implemented — awaiting physical verification | Thunderbolt (switch discovery), Apple CoreDevice, Bluetooth LE (scan + allow-listed GATT read), Bluetooth Classic (paired list), DNS-SD/Bonjour, SSDP/UPnP, Wi-Fi & Ethernet (interface state and LAN discovery), Serial (IOKit serial nodes), Matter & Thread (commissioning/border-router advertisements only), Samsung TV local info API |
| Planned | NFC, UART, CAN, OBD-II, SAE J1939, Modbus, OPC UA, MQTT, ROS 2, HDMI-CEC |
| Research only | ISOBUS, manufacturer cloud APIs |
| Delegated | Receive-only SDR → **HCG Signal Contractor** |
| Prohibited | Vehicle / machinery / robot / drone control |

## Drivers (all read-only, all user-started)

| Driver | What it does | Never does |
|---|---|---|
| `usb.enumeration` | Re-reads the IOKit registry entry of the matched device | Send USB control requests to unknown devices |
| `apple.coredevice` | Re-runs Apple Device Intelligence (`devicectl`) | Pair automatically, enable Developer Mode, modify the device |
| `ble.gatt-read` | Connects to one approved peripheral, reads Device Information (2A29, 2A24, 2A25, 2A27, 2A26, 2A28) and Battery Level (2A19), disconnects | Write, subscribe, pair or bond |
| `network.discovery` | One SSDP M-SEARCH and/or DNS-SD browse of documented service types; UPnP description GET from private LAN hosts | Port-scan, contact public hosts, log in |
| `samsung.tv-info` | `GET http://<private-ip>:8001/api/v2/` | Open the remote-control WebSocket, request a token, send keys |

Bluetooth and local-network access need the app bundle (Xcode or `scripts/build-app.sh`), whose Info.plist carries
`NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription` and the `NSBonjourServices` list. macOS asks for
permission the first time you start a scan.

## Evidence and the roadmap

Evidence kinds: **discovered**, **connection attempt** (success / partial / failure), **diagnostics** (passed of
applicable), **your report** (physical test you performed). Only real-hardware evidence and your reports change the
roadmap; synthetic fixtures are recorded and labelled but excluded.

Roadmap states: Research required → Documentation identified → Connection method identified → Hardware required /
Software required / Adapter development required → Adapter implemented → Ready for connection → Device discovered →
Connection attempted → Connection established → Diagnostics partially verified → Diagnostics fully verified →
Compatibility validated → Ecosystem integration available, plus Blocked and Unsupported.

- Automatic states are recomputed from the encyclopedia, detected/declared equipment, implemented drivers and evidence.
- *Compatibility validated* needs ≥ *Diagnostics fully verified*; *Ecosystem integration available* needs
  ≥ *Connection established*; evidence-based states cannot be set by hand. Refusals explain why.
- Manual decisions record state, note, actor and time; clearing one is recorded too.
- History is kept when a device disconnects. Live status is shown separately (Connected Devices).

## Gaps and LifeOS quests

Gap kinds: missing adapter, SDK, driver, diagnostic interface, protocol implementation, authentication; unsupported
firmware; missing hardware; operating-system restriction; safety review; missing information. IDs are stable
(`gap.protocol.can`, `gap.equipment.interface.obd2`, `gap.safety.automotive.obd2`, `gap.<profile>.info.<field>` …) and
dependencies are ordered topologically.

**Export proposed LifeOS quests** writes `hcg.lifeos.backlog` (schema 2): epic `hcg.systemtester.epic.platform`,
quest keys `hcg.systemtester.<gap-id>`, status *backlog*, realm *Sovereign Technology*, acceptance criteria, dependency
closure, **no XP**. System Tester never awards XP, never completes quests and never edits the LifeOS registry.

## AI

- The assistant shipped today is **rule-based and offline** and says so. Its statements carry sources.
- **HCG AI**: the public handoff document currently answers `404 not_published` (no native client issued) and central
  chat answers `501 chat_unavailable`. *Check availability* reads only that public document. No device data is sent.
- *Copy redacted research request* puts profile facts and gaps (no serials, addresses or identifiers) on the clipboard —
  that copy is the manual transfer step. Suggested actions are never executed.

## Ecosystem

Server (inventory export, Device Link report format), Sentinel (security findings), Signal Contractor (SDR is delegated,
not duplicated), Nexus (navigation routes), Terminal (navigation deep links only), Connect (no client issued), HCG AI
(above), Executable Maker (packaging), LifeOS (quest export). **HCG Vanguard:** no contract was found, so nothing is
integrated or assumed.

## Safety

Never performed, automatically or otherwise, by this version: vehicle ECU modification, safety-critical vehicle control,
robot movement, drone flight commands, industrial machinery control, firmware flashing, safety-interlock bypass,
unauthorised network access, radio jamming or transmission, device exploitation, pairing/passcode/lock bypass, enabling
developer settings. Any future control capability requires separate engineering, authorisation and safety validation.
Opening the application authorises nothing.

## Files

| Path (`~/Library/Application Support/HCG System Tester/`) | Contents |
|---|---|
| `connectivity.json` | Evidence, roadmap items and history, declared equipment, priorities, your profile details, remembered endpoints |
| `Encyclopedia/*.json` | Your own profiles |
| `audit.jsonl` | Approvals, attempts and manual decisions |

Remembered endpoints are only those matching a profile or that you connected to; other scan results stay in memory.
Sensitive attributes (serials, MAC addresses, BLE identifiers, addresses) are masked in the interface while
*Mask device identifiers* is on (default).
