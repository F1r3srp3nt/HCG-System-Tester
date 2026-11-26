# Universal Connectivity acceptance test — 0.3.0

Twelve steps. Each says whether it is a **physical** test (real hardware, run by you) or a **research** check
(profile content, no hardware claimed). CI on a GitHub macOS runner can only cover what that runner physically has
(virtual USB devices, no Bluetooth radio, no LAN devices); those results are recorded in
[TEST-RESULTS.md](TEST-RESULTS.md). Nothing below is marked passed on your hardware until you run it.

Run the app from Xcode (⌘R) or `scripts/build-app.sh` — Bluetooth and local-network discovery need the app bundle.

| # | Step | Type | How | Expected | Status |
|---|---|---|---|---|---|
| 1 | Local hardware discovery | Physical | Plug any USB device into the MacBook. Open **Connected Devices** (⌃⌘K). | The device appears as LIVE with transport USB; unplug → it moves to HISTORY with a last-seen time and stays in Connection History. | CI: virtual USB devices discovered. **Your Mac: pending** |
| 2 | Apple USB device | Physical | Connect the iPhone 16 Pro Max with a data cable; unlock; tap **Trust** when asked (or use Pair in the device workspace). Open **Connection Studio**, profile *Apple iPhone / iPad*, approve once, **Attempt**. | Step 1 *Identify* shows the observed iPhone; attempt result *success* with CoreDevice evidence; History shows *connectionAttempt success · REAL HARDWARE*; roadmap reaches at least *Connection established*. | **Pending (needs your iPhone)** |
| 3 | Authorised Bluetooth LE connection | Physical | **Universal Connectivity Center › Bluetooth LE › Scan** (allow Bluetooth when macOS asks). In **Connected Devices** choose a BLE device you own (e.g. a heart-rate strap, sensor or your iPad), **Connect (read-only)…**, confirm. | Connects, reads only Device Information / Battery characteristics, disconnects; values shown (serial masked); evidence recorded; a device advertising 180A/180F/180D/181A matches *Generic BLE sensor*. | **Pending** |
| 4 | Authorised Wi-Fi discovery | Physical | **Local network › Bonjour** and **SSDP once** (allow Local Network when asked). | Your own LAN devices (Apple TV/HomePod, printers, Samsung TV, Matter/HomeKit hubs) appear with service type and manufacturer/model where advertised; only private addresses are contacted; nothing is logged into. | CI: no LAN devices on runner. **Your network: pending** |
| 5 | PlayStation 5 guided profile | Research | **Device Encyclopedia › Sony PlayStation 5**. Enter your exact model (e.g. CFI-2016) and system software version. | Facts labelled Manufacturer / Community; methods: DualSense over USB-C (accessory diagnostics), PS Remote Play (Sony's app, operated by you), HDMI-CEC observation; no console control is offered; information requests listed; gaps generated. | Profile-completeness tests; CI snapshot (assistant). Research only |
| 6 | Samsung Smart TV guided profile | Research → Physical (optional) | **Encyclopedia › Samsung Smart TV**, then **Studio**: discover via SSDP or enter its LAN address, approve once, **Attempt**. | Without a TV: research profile with LAN discovery, the read-only `:8001/api/v2/` method and the SmartThings cloud API (not implemented); remote control is not offered. With a TV: model, firmware and token-auth support are read (Wi-Fi MAC and ID masked). | Research: CI snapshot. **Physical: pending** |
| 7 | Audi R8 research profile | Research | **Encyclopedia › Audi R8**. Enter model year. | Read-only OBD-II (SAE J1979 modes 01/03/09) via an ELM327/STN-class interface; ECU coding, adaptation, flashing, clearing codes and actuator tests prohibited; required OBD-II interface shown in **Hardware Requirements**; roadmap *Adapter development required*; gaps for the OBD-II interface, the OBD-II protocol and a vehicle safety review. | Unit tests (state and gaps); CI snapshot |
| 8 | Agricultural research profiles | Research | **Encyclopedia › John Deere tractor** and **ISOBUS agricultural equipment**. | Operations Center API (read-only), J1939 and ISOBUS listen-only methods with sources, Deutsch-9 / ISOBUS cabling, machine control prohibited, information requests; one shared USB-CAN interface gap. | Unit tests (shared gap); CI snapshot (Deere studio) |
| 9 | Robotics research profiles | Research | **Encyclopedia › Industrial robot arm** and **ROS 2 robot**. | Read-only methods only (industrial arm: OPC UA / RTDE status; ROS 2: observe nodes and topics on the same ROS_DOMAIN_ID); motion commands prohibited; ROS 2 software requirement shown; gaps generated. | Profile-completeness tests |
| 10 | Roadmap updates automatically from evidence | Physical | After step 2 (or 1/3), open **Development Roadmap**. | The device item's history shows an AUTOMATIC transition citing the recorded evidence. Synthetic fixtures never move it. Setting *Compatibility validated* by hand is refused until diagnostics are fully verified. | Logic verified by unit tests. **Physical: pending** |
| 11 | Gap generation | Research | **Gap Analyzer** (⌃⌘G). Change a priority. | Requirements with stable IDs, kinds, dependencies (e.g. `gap.protocol.obd2` depends on `gap.equipment.interface.obd2` and a safety review), acceptance criteria; the priority persists. | Verified by unit tests |
| 12 | Proposed LifeOS quest | Research | Select gaps, **Export proposed LifeOS quests…**, import the file into LifeOS. | `hcg.lifeos.backlog` schema 2, quest keys `hcg.systemtester.<gap-id>`, dependencies included, status backlog, **no XP**; exporting again produces the same keys (no duplicates); nothing is completed automatically. | Verified by unit tests. **LifeOS import: pending** |

## Recording your results

For each physical step, use **Development Roadmap › Report a physical test you performed** to add a
*physically tested (your report)* entry, or send the Connection History and the diagnostic report (identifiers redacted
by default) back for review.

## What must never happen during these steps

No pairing without your tap on the device, no writes to BLE devices, no login to any network device, no vehicle,
machine, robot or drone control, no firmware changes, no data sent to HCG AI or any server.
