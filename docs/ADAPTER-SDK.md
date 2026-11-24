# Hardware Adapter SDK — `hcg.adapter-manifest/1`

Adapters make System Tester interchangeable. An adapter teaches the host about a device family: how to recognise it, which
protocols it exposes, what it needs, and which diagnostics apply. You add one without changing the application.

## Execution models

| Model | Who | What it may do |
|---|---|---|
| `builtIn` | Hakmi Capital Group, compiled into the app | Use host operations; future first-party adapters may add new host operations through code review |
| `declarative` | Everyone else (imported, or created in the Studio) | **Only** compose host-implemented operations (`HostOperationCatalog`). No code is loaded, interpreted or executed |

Imported adapters are stored as **untrusted and disabled**. After you review them in the Adapter Library you can approve them.
Approved adapters still run only host operations, gated by their declared permissions and impact levels.

## Manifest fields

| Field | Required | Notes |
|---|---|---|
| `schema` | ✅ | `hcg.adapter-manifest/1` |
| `id` | ✅ | Lowercase reverse-DNS, e.g. `com.example.adapter.widget`. `com.hakmicapitalgroup.*` is reserved |
| `name`, `publisher`, `version` | ✅ | `version` is semantic (`1.2.3`). Downgrades are refused |
| `summary` | — | Shown in the Library |
| `execution` | — | Default `declarative` |
| `deviceFamilies` | ✅ | `playStation`, `xbox`, `nintendo`, `smartphone`, `tablet`, `computer`, `server`, `smartRefrigerator`, `smartTelevision`, `smartHome`, `networkEquipment`, `microcontroller`, `robotics`, `storage`, `camera`, `audio`, `industrial`, `gamingAccessory`, `inputDevice`, `usbInfrastructure`, `unknown` |
| `connectionTypes` | ✅ | `usb`, `usbSerial`, `hid`, `thunderbolt`, `ethernet`, `bluetooth`, `localNetwork`, `remoteAuthenticated`, `manufacturerAPI`, `synthetic` |
| `protocols` | — | Must be IDs from the protocol catalogue (`usb.descriptor`, `usb.msc`, `usb.cdc-acm`, `usb.hid`, `android.adb`, `matter`, `mqtt`, …) |
| `match` | ✅ for imports | `vendorIDs`, `productIDs` (numbers or `"0x054C"` strings), `deviceClasses`, `interfaceClasses`, `interfaceTriples` (`"FF.42.01"`), `nameContains`, `connectionTypes`. All specified criteria must match |
| `hardwareRequirements`, `driverRequirements` | — | `{name, providedByMacOS, notes}`. System Tester never installs drivers |
| `permissions` | — | See below. Request only what you use |
| `operations` | — | `{id, name, hostOperation, category, impact, requiredCapabilities, summary, effects?, timeoutSeconds}` |
| `configuration` | — | `{fields: [{key, label, type: string/integer/boolean/choice, required, defaultValue?, choices?, minimum?, maximum?, secret}]}` |
| `compatibility` | — | `{platforms: ["macOS"], minimumHostVersion, minimumOSVersion}` |
| `lifecycle` | — | `{stages: [discover, identify, authorize, open, diagnose, close], requiresExplicitAuthorization, closeOnDisconnect}` |
| `errors` | — | `{code, meaning, recovery}`, shown to users when an operation fails |
| `healthChecks` | — | `{id, hostOperation, intervalSeconds ≥ 5}`, read-only only |
| `profiles` | — | Device profiles contributed to the identification engine once approved |
| `experimental` | — | Shown with an EXPERIMENTAL marker |

## Permissions

| Permission | Privileged | Meaning |
|---|---|---|
| `readDeviceDescriptors` | | Read descriptors |
| `readStorageMetadata` | | BSD name and medium size (never file contents) |
| `readSerialPortList` | | List `/dev/cu.*` nodes |
| `readHIDDescriptors` | | HID descriptors (never input) |
| `readThunderboltRegistry` | | Thunderbolt switch properties |
| `localNetworkDiscovery`, `bluetoothScan` | | Discovery only |
| `openSerialPort` | ⚠︎ | Per-device grant **and** device authorisation required |
| `networkConnect` | ⚠︎ | Requires a network connection type |
| `useStoredCredential` | ⚠︎ | Required for `secret` configuration fields (Keychain; never in manifests or logs) |
| `changeDeviceConfiguration` | ⚠︎ | Required for any `stateChanging` operation; adapters must include an `authorize` lifecycle stage |

## Host operations (0.1.0)

| ID | Category | Impact |
|---|---|---|
| `host.presence` | Connection health | read-only |
| `host.identification` | Device identification | read-only |
| `host.interfaces` | Interface availability | read-only |
| `host.protocol-validation` | Protocol validation | read-only |
| `host.link-speed` | Data-transfer performance | read-only |
| `host.firmware-info` | Firmware information | read-only |
| `host.storage-info` | Storage information | read-only |
| `host.thunderbolt-switch` | Interface availability | read-only |
| `host.enumeration-errors` | Error reporting | read-only |
| `host.registry-latency` | Communication latency (host-side) | read-only |
| `host.presence-stability` | Connection stability (5 s) | read-only |
| `host.presence-stability-extended` | Connection stability (60 s) | extended |
| `research.console-interfaces` | Device-specific (console families) | read-only |
| `synthetic.fault-injection` | Connection stability (synthetic only) | state-changing |

The validator rejects an operation whose declared impact is lower than its host operation's impact.

Every result carries: test ID, target device, type, start and finish time, outcome, measurements with units, evidence,
limitations, errors, recommended next action and provenance.

## Workflow

1. **Adapter Developer Studio → Create**. You start from a declarative template.
2. Edit the manifest (form or JSON), add device profiles, and bump the version.
3. **Test & validate**: see the match rules against synthetic fixtures and connected devices (metadata only), and run the operations on matching
   synthetic fixtures.
4. **Export** the JSON, or **Send to Adapter Library** (it is registered as untrusted and disabled).
5. **Adapter Library → Review & approve**.

Example: [`Examples/Adapters/example-serial-widget.json`](../Examples/Adapters/example-serial-widget.json). A unit test
keeps it valid.

## Programmatic use

```swift
import HCGCore

let registry = AdapterRegistry()                       // first-party adapters pre-registered
let entry = try registry.importManifest(data: json)    // validated; untrusted + disabled
try registry.approve(entry.id)                          // explicit user decision
let compat = registry.compatibility(for: device, identification: IdentificationEngine().identify(device))
```

## Shared specification

This manifest is proposed as the shared hardware adapter specification with **HCG Signal Contractor**, so the two products
do not maintain separate discovery stacks (see [ECOSYSTEM.md](ECOSYSTEM.md)).
