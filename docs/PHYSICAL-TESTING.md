# Physical-device test checklist (0.1.0)

Goal of the first acceptance milestone: **connect a real USB device to the MacBook and immediately see System Tester detect it.**
Record every result, **including failures**. An unsuccessful connection is compatibility evidence, not something to hide.

## Before you start

1. Build and launch: `open App/HCGSystemTester.xcodeproj` → ⌘R, or `scripts/build-app.sh --open`.
2. Settings: leave **Synthetic fixtures OFF**, so every device you see is real hardware labelled **REAL HARDWARE**.
3. In a terminal, keep `swift run hcg-probe --watch` running as an independent cross-check.
4. Optional ground truth: `system_profiler SPUSBDataType` (USB) and `system_profiler SPThunderboltDataType`.

For each device, on its page in **Connected Systems**:

- note the status badge and the **limiting layer**;
- run **Run read-only diagnostics** (⇧⌘D);
- click **Record compatibility evidence**, adding the cable, port and adapter used in the notes;
- unplug it and confirm the **Disconnected** event in the Command Center's event stream;
- re-plug it and confirm it continues the same Laboratory profile (event *Re-attached*).

At the end: **Reports → Generate from this session's runs → Export (Markdown and hcg.diagnostic-report/1)**.

## Test matrix

| # | Device | Connect via | Expected in 0.1.0 | Pass criteria |
|---|---|---|---|---|
| 1 | **USB storage** (flash drive / SSD) | USB-C directly, then through a hub | Identified as *USB mass-storage device*; status **Diagnostics available**; BSD disk (e.g. `disk4`) and size; Protocol layer *Verified*; Functional *Partial* (macOS's driver talks to it, System Tester does not) | Appears within ~1 s; BSD disk shown; **Negotiated link speed** passes on a USB 3 cable and warns on a USB 2 cable/hub |
| 2 | **Smartphone – iPhone** | USB-C cable | *Apple iPhone*, status **Adapter required** (usbmux/PTP need device trust + Apple tooling) | Shown as Adapter required, **never** Connected; result stays the same whether the phone is locked or unlocked |
| 3 | **Smartphone – Android** | USB-C cable, try *File transfer* and *USB debugging* | MTP: *Phone or tablet (MTP/PTP)*. ADB on: *Android device (USB debugging enabled)*. Status **Adapter required** | ADB interface `FF.42.01` listed when debugging is on; *Charging only* mode may enumerate with fewer interfaces or not at all (record it) |
| 4 | **USB hub** (powered or unpowered) | USB-C | Hub row with role *USB hub*; the devices behind it are drawn as its children in the **Connection Visualizer** | The topology follows the port path (locationID); unplugging the hub detaches every child |
| 5 | **USB serial device** (Arduino, ESP32, Pico, FTDI/CH340/CP210x board) | USB-C/USB-A adapter | Identified board or bridge; `/dev/cu.*` path shown; **Protocol validation** passes | Serial node listed. If missing, record it: the bridge may need a vendor driver, which System Tester never installs |
| 6 | **Gaming controller** (DualSense, DualShock 4, Xbox, Switch Pro) | USB-C cable | DualSense/DS4: *controller*, HID interface; status **Diagnostics available**. Xbox (GIP): status **Unsupported** for its vendor protocol, but descriptors are still shown | Identified as a **controller**, not a console. The PlayStation/Xbox Research module explains what is exposed |
| 7 | **PlayStation or Xbox console** | Mac USB-C ↔ console USB-A/C port | **Expected: nothing appears.** Both sides are USB hosts; consoles expose no USB device-mode diagnostic interface | Record "no enumeration (host-to-host)" as compatibility evidence. Do **not** use converters that claim to bypass this |
| 8 | Thunderbolt dock/display (optional) | Thunderbolt 4/5 | Thunderbolt switch node with vendor/model; USB devices inside the dock appear as USB devices | Switch appears under *Thunderbolt / USB4* in the Visualizer |
| 9 | Charge-only cable (optional, negative test) | any | Nothing appears | Confirms that a connected cable does not mean communication |

## Synthetic cross-check (optional)

Enable **Settings → Synthetic fixtures**. Six labelled fixtures appear on a separate **SYNTHETIC fixture bus**, including a USB 3
SSD on a USB 2 link (link-speed warning) and an unknown vendor device. In **Diagnostics**, select a fixture, toggle
**Synthetic disconnect injection**, confirm the authorisation prompt, and run it. The fixture reaches **Connected** (SYNTHETIC)
only after that exchange, which shows the full state machine. Turn fixtures off again before real testing.

## What to send back

- The exported Markdown report, plus the `hcg.diagnostic-report/1` JSON.
- The `hcg-probe --json` output (redacted).
- Notes on anything that appeared in `system_profiler` but **not** in System Tester. That would be a discovery bug.
