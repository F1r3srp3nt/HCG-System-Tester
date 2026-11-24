# Actual hardware compatibility limitations (0.1.0)

These are physical and platform facts, not missing polish. System Tester reports them instead of hiding them.

## USB-C and cables

- **USB-C is a connector, not a protocol.** A device is only visible if a USB data link is negotiated. Power Delivery-only
  negotiation (charge-only cables, chargers, many power banks) produces **no discovery event**, and macOS gives apps no
  supported, non-privileged way to observe it.
- **Host-to-host links do not enumerate.** Two USB hosts (Mac ↔ PC, Mac ↔ game console, Mac ↔ most smart TVs) cannot talk over a
  plain USB cable. Special "bridge" cables appear as a separate device; they connect to that device, not to the other host.
- Link speed is the **negotiated signalling rate** reported by the host controller, not measured throughput. A USB 3 device
  on a USB 2 cable or hub is reported at High Speed (480 Mbit/s), and System Tester flags that.
- Alternate modes (DisplayPort, Thunderbolt) are negotiated below USB. A device that offered an alternate mode it could not
  enter may show only a **USB-C Billboard** interface.

## What 0.1.0 verifies

| Layer | 0.1.0 capability |
|---|---|
| Physical | Inferred from enumeration (descriptors can only be read over a working data link) |
| Enumeration | ✅ IOKit registry |
| Protocol compatibility | ✅ when macOS bound a driver, published a disk or a serial node |
| Authorization | ✅ recorded per device (no device-side pairing yet) |
| Functional communication | ❌ on real hardware: diagnostics are host-side and read-only. First real verification is the serial adapter (milestone 2) |

**No real device reaches *Connected* in 0.1.0.** This is intentional. *Connected* means data was exchanged.

## Device families

| Family | What is exposed over USB to a Mac | What System Tester does | Not possible / not done |
|---|---|---|---|
| **PlayStation 4/5 console** | Nothing. The console is a USB host. | Records "no enumeration" evidence | No USB diagnostic interface; console services need documented, authorised network APIs (planned research). No bypass of authentication, DRM or firmware protection, ever |
| **Xbox One/Series console** | Nothing (USB host) | Same as above | Same. Developer Mode / Device Portal is a documented network interface for owners and may be investigated later |
| **PlayStation controllers** | HID (+ audio on DualSense) | Identification, interfaces, HID driver binding | Input reports are never captured |
| **Xbox controllers** | Vendor GIP protocol (or XInput on older pads) | Identification, descriptors; status *Unsupported* for the vendor protocol | macOS handles them through the Game Controller framework; System Tester does not speak GIP |
| **Nintendo Switch Pro / Joy-Con grip** | HID | Identification | — |
| **iPhone / iPad** | PTP + Apple usbmux (vendor interface) | Identification; status *Adapter required* | Anything beyond descriptors needs "Trust This Computer" and Apple's supported tooling. No pairing, unlocking or backup access |
| **Android phones** | MTP/PTP, optional ADB (`FF.42.01`), optional RNDIS/NCM tethering | Identification by interface; status *Adapter required* | macOS has no MTP client; ADB needs platform-tools and on-device RSA approval (planned optional adapter) |
| **USB storage** | Mass Storage (BOT/UAS) | BSD disk, medium size, link speed, interface validation | SMART is usually not passed through USB bridges; file systems are never read |
| **USB serial / microcontrollers** | CDC ACM or vendor bridge | Serial node detection, identification | Opening ports is planned (milestone 2) behind a per-device authorisation |
| **Hubs** | Hub class | Topology (port path) | Hubs that macOS models internally without an `IOUSBHostDevice` are not drawn; their children attach to the bus |
| **Thunderbolt / USB4** | Switch registry | Vendor, model, route, depth | PCIe/DisplayPort tunnels are not inspected |
| **Smart TVs, refrigerators, appliances** | Usually nothing useful over USB (service/USB-media ports only) | — | Planned via documented network interfaces (Matter, manufacturer APIs, MQTT) with explicit authorisation; never safety-critical functions |
| **HomeKit accessories** | — | — | The HomeKit framework is not available to native macOS apps (Mac Catalyst only) |
| **Bluetooth, Ethernet, local network** | — | Shown as *Planned* in the Connection Engine | Not implemented in 0.1.0 |

## Platform notes

- Built-in Apple silicon peripherals (keyboard, trackpad, camera) are mostly not USB devices and do not appear.
- Some vendor serial bridges (older CH34x/PL2303) need vendor drivers. System Tester never installs drivers.
- Unknown devices are shown with their raw descriptors. A vendor-specific interface (`0xFF`) is never assumed to mean anything.
