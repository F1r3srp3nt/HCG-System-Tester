# iPhone 16 Pro Max acceptance test (v0.2.0)

Everything below is implemented and CI-verified against synthetic fixtures and fake devicectl output. **It has not yet run
against a physical iPhone** — this procedure is that verification. Record results (pass/fail + screenshots) and export the
reports at the end.

## 0. Prepare (once)

```bash
cd HCG-System-Tester && git pull
```

```bash
swift run hcg-probe --toolchain
```

Expected: `Xcode 27.2 (…)`, a devicectl path and version, and detected commands including `details` (ideally also `pair`,
`lockState`, `apps`). If it says “Command Line Tools only”, run `sudo xcode-select -s /Applications/Xcode.app`.

Optional (battery / free space): `brew install libimobiledevice`. Not required for the test.

Open and run the app: `open App/HCGSystemTester.xcodeproj` → ⌘R (or `scripts/build-app.sh --open`).
Settings: synthetic fixtures **off**.

## 1–14. Steps

| # | Do | Expected in HCG System Tester | Where |
|---|---|---|---|
| 1 | Unlock the iPhone, connect it with the USB-C cable | — | — |
| 2 | — | “ATTACHED iPhone” appears in the Command Center event stream within ~1 s | Command Center |
| 3 | — | Real USB device: VID `0x05AC`, PID `0x12A8`, “iPhone”, REAL HARDWARE badge | Connected Systems › iPhone › Hardware |
| 4 | — | Family identified: “Apple iPhone” profile, ladder step 4 ✓ | Overview |
| 5 | — | Interfaces include **Apple usbmux (FF.FE.02)** and PTP; link speed shown (USB 2.0 with a USB 2 cable — flagged as limiting on a 16 Pro Max; USB 3.x with a 10 Gbit/s cable) | Hardware, USB Connection Inspector |
| 6 | — | Ladder step 5 ✓ (usbmux, CoreDevice lists the device) and services list | Overview / Authorization |
| 7 | If not yet trusted: state **7 Pairing available** → click **Pair…**, confirm, tap **Trust** on the iPhone, enter passcode. If the iPhone is locked: state **6** with “Unlock the device” | Next action panel guides you; after Trust the ladder reaches **8 Pairing established** | Overview / Authorization |
| 8 | — | **9 Authorized communication established**, then **10 Diagnostics available**. Fields with sources: name, model “iPhone 16 Pro Max”, product type `iPhone17,2`, hardware model, iOS version + build, storage capacity, pairing status, Developer Mode status, DDI services, capabilities. Battery/free space: values with libimobiledevice, otherwise “Unavailable — …” with the reason | Overview / Software / Authorization |
| 9 | Diagnostics tab → **Run Apple device diagnostics** | Results for 11 Apple tests with evidence, sources and limitations; latency in ms; *Disconnect & reconnect handling* = “Not exercised yet” | Diagnostics |
| 10 | — | iPhone node under its USB bus, interface satellites, state text “10/13 · Diagnostics available”; double-click opens the workspace | Connection Visualizer |
| 11 | Reports tab → **Export JSON…** and **Export summary…** (Device information + Diagnostic results) | Files saved; UDID/ECID/serial redacted unless you opted in | Device workspace › Reports |
| 12 | Unplug the iPhone | Within ~1 s: “DETACHED”, status **Disconnected**, ladder **13 Disconnected**, Live Monitor drop-out +1 | Command Center / Live Monitor |
| 13 | — | Visualizer removes the node; workspace shows “Reconnect the device” | Visualizer |
| 14 | Plug it back in (unlocked) | “Re-attached; continuing previous record”, timeline shows Reconnect, state returns to 10 without new Trust prompt. Re-run **Disconnect & reconnect handling** → Passed | Activity / Diagnostics |

## Cross-check from the terminal

```bash
swift run hcg-probe --apple
```

Prints the 13-state ladder, every field with its source, services and limitations. `--show-serials` reveals identifiers
locally (never use it for shared output).

## Also try

- iPad Pro M4 (USB-C, Thunderbolt): same steps; USB capability field shows “Thunderbolt / USB 4”.
- An older Lightning device: expect USB identification and CoreDevice data if your Xcode still supports its iOS version;
  otherwise the ladder stops with a reason.
- A charge-only cable: nothing appears (explained in the USB Connection Inspector).

## What to send back

The exported device information + diagnostic reports, `hcg-probe --toolchain` and `hcg-probe --apple` output, and a note
of any step whose result differed from the table.
