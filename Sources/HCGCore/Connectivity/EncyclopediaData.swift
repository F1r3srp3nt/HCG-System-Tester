import Foundation

/// Built-in research profiles. These are research and development targets, not compatibility claims.
/// Manufacturer facts are general family-level facts; exact behaviour depends on model and firmware,
/// which each profile asks for. Reference URLs are top-level documentation entry points that HCG has
/// not fetched (`lastChecked == nil`) — verify them before relying on them.
public enum EncyclopediaData {
    typealias F = SourcedFact
    static let mfr = KnowledgeSource.manufacturerDocumented
    static let com = KnowledgeSource.communityReported
    static let res = KnowledgeSource.hcgResearchNote

    static func ref(_ id: String, _ title: String, _ publisher: String, _ url: String, _ source: KnowledgeSource = .manufacturerDocumented) -> DocumentationReference {
        DocumentationReference(id: id, title: title, publisher: publisher, url: url, source: source)
    }

    static let noControl = SafetyRestriction("no-control", "System Tester never sends control, actuation or firmware commands to this device.", .prohibitedControl, res)

    public static let all: [EncyclopediaProfile] = [ps5, samsungTV, audiR8, johnDeere, agriculture, industrialArm, ros2Robot, djiDrone,
                                                     raspberryPi, arduino, esp32, appleMobile, appleMac, windowsPC, linuxPC, bleSensor, smartHome]

    // MARK: Gaming

    public static let ps5 = EncyclopediaProfile(
        id: "sony.playstation5", category: .gamingConsole, manufacturer: "Sony Interactive Entertainment", productFamily: "PlayStation 5",
        operatingSystem: F("PS5 system software (proprietary)", mfr),
        physicalInterfaces: [F("HDMI output", mfr), F("USB-C and USB-A ports (USB host role)", mfr), F("Ethernet", mfr)],
        wirelessInterfaces: [F("Wi-Fi", mfr), F("Bluetooth (controllers and headsets)", mfr)],
        protocols: [F("HDMI-CEC (“HDMI Device Link” setting)", mfr), F("PS Remote Play over the network (proprietary, through Sony's app)", mfr),
                    F("Console USB ports are hosts: a Mac cannot enumerate the console over USB", res),
                    F("The console does not advertise documented DNS-SD services", com)],
        sdks: [F("Game development SDK only for licensed PlayStation Partners (not for third-party diagnostics)", mfr)],
        requiredCables: ["cable.usbc-data"], requiredSoftware: ["software.ps-remote-play"],
        authentication: [F("PlayStation Network account and console linking for Remote Play", mfr)],
        permissions: [F("Console owner must enable Remote Play", mfr)],
        safety: [noControl, SafetyRestriction("no-bypass", "No bypass of console authentication, DRM or firmware protection, ever.", .prohibitedControl, res)],
        connectionMethods: [
            ConnectionMethod(id: "dualsense-usb", title: "DualSense controller over USB-C (accessory diagnostics)", protocolID: "usb", driverID: "usb.enumeration",
                             requiredEquipment: ["cable.usbc-data"], steps: ["Connect the DualSense to the Mac with a USB-C data cable.", "Open Connected Systems: the controller is identified (HID + audio)."],
                             source: res, notes: "Diagnoses the controller, not the console."),
            ConnectionMethod(id: "remote-play", title: "PS Remote Play (Sony app, user-operated)", protocolID: "manufacturer.api",
                             requiredEquipment: ["interface.wifi-or-ethernet"], requiredSoftware: ["software.ps-remote-play"],
                             authentication: "PlayStation Network sign-in", steps: ["Enable Remote Play on the PS5 (Settings › System › Remote Play).", "Install PS Remote Play for Mac and sign in.", "Pair through Sony's app. System Tester records the result you report."],
                             source: mfr, notes: "Sony's protocol is proprietary; System Tester does not implement it."),
            ConnectionMethod(id: "hdmi-cec", title: "HDMI-CEC observation", protocolID: "hdmi.cec", requiredEquipment: ["adapter.hdmi-cec"], source: res)
        ],
        troubleshooting: [F("Mac ↔ console USB cable: nothing enumerates (host-to-host). Expected.", res)],
        references: [ref("ps-remote-play", "PS Remote Play", "Sony Interactive Entertainment", "https://www.playstation.com/remote-play/"),
                     ref("ps-support", "PlayStation Support", "Sony Interactive Entertainment", "https://www.playstation.com/support/")],
        informationRequests: ["Model (CFI-1xxx / CFI-2xxx, Digital or disc)", "System software version (Settings › System › System Software)"],
        match: EndpointMatchRule(transports: [.usb], usbVendorIDs: [0x054C]), priority: 4)

    // MARK: Television

    public static let samsungTV = EncyclopediaProfile(
        id: "samsung.smart-tv", category: .smartTelevision, manufacturer: "Samsung", productFamily: "Smart TV (Tizen)",
        operatingSystem: F("Tizen OS", mfr),
        physicalInterfaces: [F("HDMI inputs (HDMI-CEC branded “Anynet+”)", mfr), F("USB-A (media / accessories, host role)", mfr), F("Ethernet (most models)", mfr)],
        wirelessInterfaces: [F("Wi-Fi", mfr), F("Bluetooth", mfr)],
        protocols: [F("AirPlay 2 on supported 2018+ models", mfr), F("SmartThings cloud integration", mfr),
                    F("Matter support / SmartThings hub on selected 2022+ models", mfr),
                    F("SSDP/UPnP and DIAL discovery on the LAN", com),
                    F("Read-only device info at http://<tv>:8001/api/v2/ on many Tizen models", com)],
        sdks: [F("SmartThings API (cloud, owner-authorised)", mfr), F("Tizen TV SDK for app developers", mfr)],
        requiredSoftware: [],
        authentication: [F("SmartThings: Samsung account + owner authorisation", mfr), F("Remote-control channels require on-TV approval (not used)", com)],
        permissions: [F("macOS Local Network permission for discovery", res)],
        safety: [noControl],
        connectionMethods: [
            ConnectionMethod(id: "lan-discovery", title: "LAN discovery (Bonjour AirPlay / SSDP)", protocolID: "network.ssdp", driverID: "network.discovery",
                             requiredEquipment: ["interface.wifi-or-ethernet"], permissions: ["Local Network"],
                             steps: ["Turn the TV on and join the same network as the Mac.", "Run LAN discovery in the Live Connection Center.", "System Tester matches “Samsung” in UPnP/AirPlay records."],
                             source: com),
            ConnectionMethod(id: "local-info", title: "Read device info (port 8001, read-only)", protocolID: "samsung.tv-local", driverID: "samsung.tv-info",
                             requiredEquipment: ["interface.wifi-or-ethernet"], steps: ["Discover the TV first.", "Approve the read-only info request.", "Model, OS and capabilities are recorded with their source."],
                             source: com, notes: "Undocumented by Samsung for third parties; behaviour varies by model year."),
            ConnectionMethod(id: "smartthings", title: "SmartThings API (cloud)", protocolID: "manufacturer.api", authentication: "Samsung account (OAuth / token via HCG Connect governance)",
                             source: mfr, notes: "Adapter not implemented.")
        ],
        troubleshooting: [F("No SSDP responses: check the TV is on (not standby) and that the network allows multicast.", res)],
        references: [ref("smartthings-dev", "SmartThings Developers", "Samsung", "https://developer.smartthings.com/"),
                     ref("tizen-tv", "Samsung Smart TV developer documentation", "Samsung", "https://developer.samsung.com/smarttv")],
        informationRequests: ["Model code (e.g. QE65S95…, sticker on the back or Settings › Support › About This TV)", "Model year", "Software version"],
        match: EndpointMatchRule(transports: [.ssdp, .bonjour], attributeContains: ["manufacturer": "samsung"]), priority: 4)

    // MARK: Vehicles

    public static let audiR8 = EncyclopediaProfile(
        id: "audi.r8", category: .vehicle, manufacturer: "Audi", productFamily: "R8",
        physicalInterfaces: [F("OBD-II diagnostic connector (SAE J1962, 16-pin)", mfr)],
        protocols: [F("OBD-II emissions diagnostics (SAE J1979) — mandatory for road vehicles in the US (1996+) and EU (petrol 2001+)", mfr),
                    F("ISO 15765-4 CAN for OBD on modern model years", mfr),
                    F("Manufacturer-level diagnostics through VW Group ODIS (dealer/licensed tool)", mfr)],
        sdks: [F("No public Audi vehicle-diagnostics SDK for third parties", res)],
        requiredAdapters: ["interface.obd2"],
        authentication: [F("Manufacturer diagnostics require licensed access (e.g. ODIS, gateway authentication on newer platforms)", mfr)],
        permissions: [F("Vehicle owner's permission; vehicle stationary, ignition on, engine off for read-only sessions", res)],
        safety: [SafetyRestriction("obd-readonly", "Read-only OBD-II modes 01/03/09 only.", .readOnly, res),
                 SafetyRestriction("no-ecu", "No ECU coding, adaptation, flashing, clearing codes or actuator tests.", .prohibitedControl, res),
                 SafetyRestriction("not-driving", "Never run diagnostics while the vehicle is being driven.", .prohibitedControl, res)],
        connectionMethods: [
            ConnectionMethod(id: "obd2-readonly", title: "Read-only OBD-II via an ELM327/STN-class interface", protocolID: "obd2",
                             requiredEquipment: ["interface.obd2"], permissions: ["Owner authorisation"], steps: ["Vehicle parked, ignition on, engine off.", "Plug the interface into the OBD-II port.", "Connect the interface to the Mac (USB or BLE).", "Read supported PIDs, VIN and stored codes only."],
                             safety: .readOnly, source: res, notes: "Adapter not implemented yet.")
        ],
        troubleshooting: [F("Location of the OBD-II port and protocol depend on generation; confirm in the owner's manual.", res)],
        references: [ref("sae-j1979", "SAE J1979 — E/E Diagnostic Test Modes", "SAE International", "https://www.sae.org/standards/content/j1979_201702/")],
        informationRequests: ["Generation and model year (Type 42: 2007–2015, Type 4S: 2015–2024)", "Market (EU/US) and engine (V8/V10)"],
        match: EndpointMatchRule(nameContains: ["R8"], attributeContains: ["manufacturer": "audi"]), priority: 3)

    // MARK: Agriculture

    public static let johnDeere = EncyclopediaProfile(
        id: "johndeere.tractor", category: .agriculturalMachinery, manufacturer: "John Deere", productFamily: "Tractors",
        physicalInterfaces: [F("Diagnostic connector (9-pin Deutsch, J1939 CAN) on most modern tractors", mfr), F("ISOBUS implement connectors (ISO 11783)", mfr)],
        wirelessInterfaces: [F("JDLink telematics modem (cellular)", mfr)],
        protocols: [F("SAE J1939 vehicle network", mfr), F("ISOBUS (ISO 11783) tractor–implement communication", mfr),
                    F("John Deere Operations Center APIs (cloud, partner programme)", mfr)],
        sdks: [F("John Deere Developer APIs via developer.deere.com (OAuth, application approval)", mfr),
               F("Dealer diagnostics: Service ADVISOR; owner/operator tooling available in some markets", mfr)],
        requiredCables: ["cable.j1939-deutsch9", "cable.isobus"], requiredAdapters: ["interface.usb-can"],
        authentication: [F("Operations Center: John Deere account + organisation connection approval", mfr)],
        permissions: [F("Machine owner's authorisation; machine parked and secured", res)],
        safety: [SafetyRestriction("listen-only", "CAN/J1939/ISOBUS access is listen-only.", .readOnly, res),
                 SafetyRestriction("no-actuation", "No steering, hitch, PTO, hydraulic or implement commands.", .prohibitedControl, res), noControl],
        connectionMethods: [
            ConnectionMethod(id: "ops-center", title: "Operations Center API (read-only machine data)", protocolID: "manufacturer.api",
                             authentication: "John Deere OAuth (via HCG Connect governance)", steps: ["Register an application on developer.deere.com.", "Connect your organisation with read-only scopes.", "Read machine locations, hours and alerts."],
                             source: mfr, notes: "Adapter not implemented."),
            ConnectionMethod(id: "j1939-listen", title: "J1939 listen-only on the diagnostic connector", protocolID: "j1939",
                             requiredEquipment: ["interface.usb-can", "cable.j1939-deutsch9"], steps: ["Machine parked, key on.", "Connect the CAN interface in listen-only mode at 250 kbit/s (confirm for the model).", "Decode broadcast PGNs (engine speed, hours, temperatures)."],
                             safety: .readOnly, source: res, notes: "Adapter not implemented.")
        ],
        references: [ref("deere-dev", "John Deere Developer", "Deere & Company", "https://developer.deere.com/"),
                     ref("aef-isobus", "AEF ISOBUS database", "Agricultural Industry Electronics Foundation", "https://www.aef-online.org/")],
        informationRequests: ["Exact model and serial range (e.g. 6R 155, 8R 410)", "Model year", "Whether JDLink is active", "CommandCenter display generation"],
        match: EndpointMatchRule(attributeContains: ["manufacturer": "deere"]), priority: 3)

    public static let agriculture = EncyclopediaProfile(
        id: "agri.isobus-generic", category: .agriculturalMachinery, manufacturer: "Various (AEF-certified)", productFamily: "ISOBUS tractors and implements",
        physicalInterfaces: [F("ISOBUS breakaway and in-cab connectors (ISO 11783-2)", mfr), F("J1939 diagnostic connector", mfr)],
        protocols: [F("ISO 11783 (ISOBUS) incl. Virtual Terminal, Task Controller, TECU", mfr), F("SAE J1939", mfr)],
        requiredCables: ["cable.isobus"], requiredAdapters: ["interface.usb-can"],
        safety: [SafetyRestriction("isobus-passive", "Never claim an ISOBUS address or send messages; passive observation only.", .prohibitedControl, res), noControl],
        connectionMethods: [ConnectionMethod(id: "isobus-listen", title: "ISOBUS passive observation", protocolID: "isobus",
                                             requiredEquipment: ["interface.usb-can", "cable.isobus"], safety: .readOnly, source: res, notes: "Adapter not implemented.")],
        references: [ref("aef", "AEF — ISOBUS", "Agricultural Industry Electronics Foundation", "https://www.aef-online.org/")],
        informationRequests: ["Tractor and implement makes/models", "AEF certification of each (AEF database)"], priority: 2)

    // MARK: Robotics

    public static let industrialArm = EncyclopediaProfile(
        id: "robotics.industrial-arm", category: .roboticArm, manufacturer: "Various (e.g. Universal Robots, ABB, FANUC, KUKA)", productFamily: "Industrial robotic arms",
        physicalInterfaces: [F("Ethernet on the controller", mfr)],
        protocols: [F("Universal Robots: RTDE (real-time data exchange) and Modbus TCP; official ROS 2 driver", mfr),
                    F("ABB: Robot Web Services (REST) on supported controllers", mfr),
                    F("Many controllers expose OPC UA or Modbus TCP as options", com)],
        sdks: [F("Vendor SDKs and ROS 2 drivers per manufacturer", mfr)],
        authentication: [F("Controller credentials / network enablement by the integrator", mfr)],
        permissions: [F("Cell owner/integrator authorisation and safety sign-off", res)],
        safety: [SafetyRestriction("no-motion", "No motion, jogging, program start/stop or I/O writes. Read-only status only.", .prohibitedControl, res),
                 SafetyRestriction("iso10218", "Any future control requires separate risk assessment (ISO 10218 / ISO/TS 15066).", .prohibitedControl, res)],
        connectionMethods: [ConnectionMethod(id: "opcua-read", title: "OPC UA / RTDE read-only status", protocolID: "opcua", requiredEquipment: ["interface.wifi-or-ethernet"],
                                             safety: .readOnly, source: res, notes: "Adapter not implemented.")],
        references: [ref("ur-ros2", "Universal Robots ROS 2 Driver", "Universal Robots", "https://github.com/UniversalRobots/Universal_Robots_ROS2_Driver", .manufacturerDocumented)],
        informationRequests: ["Manufacturer and controller generation", "Enabled fieldbus/options", "Integrator contact for authorisation"], priority: 2)

    public static let ros2Robot = EncyclopediaProfile(
        id: "robotics.ros2", category: .robot, manufacturer: "Various", productFamily: "ROS 2 robots",
        operatingSystem: F("Typically Ubuntu Linux with a ROS 2 distribution (Humble, Jazzy)", com),
        physicalInterfaces: [F("Ethernet", com), F("USB (onboard computer)", com)], wirelessInterfaces: [F("Wi-Fi", com)],
        protocols: [F("ROS 2 over DDS (RTPS) with multicast discovery", mfr)],
        sdks: [F("ROS 2 client libraries (rclcpp, rclpy)", mfr)], requiredSoftware: ["software.ros2"],
        authentication: [F("Optional SROS2 security (certificates) on secured deployments", mfr)],
        permissions: [F("Robot owner authorisation; robot in a safe, supervised state", res)],
        safety: [SafetyRestriction("no-publish", "Observe topics only. Never publish to command topics (e.g. /cmd_vel) or call actions.", .prohibitedControl, res)],
        connectionMethods: [ConnectionMethod(id: "ros2-observe", title: "Observe nodes and topics (same ROS_DOMAIN_ID)", protocolID: "ros2",
                                             requiredEquipment: ["interface.wifi-or-ethernet"], requiredSoftware: ["software.ros2"],
                                             steps: ["Install the robot's ROS 2 distribution (Linux VM/container recommended on macOS).", "Match ROS_DOMAIN_ID and network.", "List nodes/topics; echo telemetry read-only."],
                                             safety: .readOnly, source: res, osRestriction: "ROS 2 on macOS is community-supported (Tier 3).", notes: "Adapter not implemented.")],
        references: [ref("ros2-docs", "ROS 2 Documentation", "Open Robotics", "https://docs.ros.org/")],
        informationRequests: ["Robot model", "ROS 2 distribution", "ROS_DOMAIN_ID and network setup", "SROS2 enabled?"], priority: 3)

    public static let djiDrone = EncyclopediaProfile(
        id: "dji.drone", category: .drone, manufacturer: "DJI", productFamily: "Drones",
        physicalInterfaces: [F("USB-C on aircraft and remote controller (firmware/data, via DJI Assistant)", mfr)],
        wirelessInterfaces: [F("Proprietary video/control link (OcuSync/O-series) between aircraft and controller", mfr)],
        protocols: [F("DJI Mobile SDK (MSDK v5), Onboard/Payload SDK, Cloud API for supported models", mfr)],
        sdks: [F("DJI Developer SDKs (registration and app key required)", mfr)],
        authentication: [F("DJI developer account and app key", mfr)],
        safety: [SafetyRestriction("no-flight", "No flight, gimbal or payload commands. Telemetry read-only only.", .prohibitedControl, res),
                 SafetyRestriction("no-firmware", "No firmware flashing or flight-limit modification.", .prohibitedControl, res),
                 SafetyRestriction("regulation", "Comply with aviation regulations (e.g. Remote ID) — out of scope for System Tester.", .prohibitedControl, res)],
        connectionMethods: [ConnectionMethod(id: "cloud-api", title: "DJI Cloud API telemetry (read-only)", protocolID: "manufacturer.api",
                                             authentication: "DJI developer app key", source: mfr, notes: "Adapter not implemented; model support varies.")],
        references: [ref("dji-dev", "DJI Developer", "DJI", "https://developer.dji.com/")],
        informationRequests: ["Exact aircraft model", "Remote controller model", "Firmware version"],
        match: EndpointMatchRule(transports: [.usb], usbVendorIDs: [0x2CA3]), priority: 2)

    // MARK: Boards

    public static let raspberryPi = EncyclopediaProfile(
        id: "raspberrypi.sbc", category: .singleBoardComputer, manufacturer: "Raspberry Pi", productFamily: "Raspberry Pi (4 / 5)",
        operatingSystem: F("Raspberry Pi OS (Debian-based) or other Linux", mfr),
        physicalInterfaces: [F("Ethernet, USB-A, USB-C (power; Pi 4 can act as a USB gadget)", mfr), F("40-pin GPIO with 3.3 V UART", mfr)],
        wirelessInterfaces: [F("Wi-Fi and Bluetooth (on wireless models)", mfr)],
        protocols: [F("SSH over the network", mfr), F("mDNS host name (raspberrypi.local) via Avahi", com), F("UART serial console on GPIO 14/15", mfr)],
        requiredAdapters: ["adapter.usb-ttl-3v3"],
        authentication: [F("SSH user credentials or keys configured by the owner", mfr)],
        safety: [SafetyRestriction("3v3", "GPIO is 3.3 V: never connect 5 V logic.", .readOnly, mfr)],
        connectionMethods: [
            ConnectionMethod(id: "mdns", title: "Discover on the LAN (DNS-SD)", protocolID: "network.mdns", driverID: "network.discovery",
                             requiredEquipment: ["interface.wifi-or-ethernet"], steps: ["Boot the Pi on the same network.", "Run LAN discovery: look for _ssh._tcp / _workstation._tcp records."], source: com),
            ConnectionMethod(id: "uart", title: "UART serial console (3.3 V)", protocolID: "uart", requiredEquipment: ["adapter.usb-ttl-3v3"],
                             steps: ["Enable the serial console in raspi-config.", "Wire GND, TX→RX, RX→TX at 3.3 V.", "Open the port read-only (planned)."], source: mfr)
        ],
        references: [ref("rpi-docs", "Raspberry Pi Documentation", "Raspberry Pi Ltd", "https://www.raspberrypi.com/documentation/")],
        informationRequests: ["Board model (Pi 4, Pi 5, Zero 2 W …)", "OS and version"],
        match: EndpointMatchRule(nameContains: ["raspberry", "raspberrypi"]), priority: 3)

    public static let arduino = EncyclopediaProfile(
        id: "arduino.board", category: .microcontroller, manufacturer: "Arduino", productFamily: "Arduino boards",
        physicalInterfaces: [F("USB (CDC ACM serial, via native USB or a USB-serial bridge depending on the board)", mfr)],
        protocols: [F("USB CDC serial", mfr)], sdks: [F("Arduino IDE / arduino-cli", mfr)], requiredSoftware: ["software.arduino-cli"],
        safety: [SafetyRestriction("no-flash", "System Tester never uploads sketches or flashes bootloaders.", .prohibitedControl, res)],
        connectionMethods: [ConnectionMethod(id: "usb-serial", title: "USB serial (detected over USB)", protocolID: "serial", driverID: "usb.enumeration",
                                             requiredEquipment: ["cable.usbc-data"], steps: ["Connect the board with a data cable.", "System Tester detects the board and its /dev/cu.* port."], source: mfr)],
        references: [ref("arduino-docs", "Arduino Documentation", "Arduino", "https://docs.arduino.cc/")],
        informationRequests: ["Board model (Uno R3/R4, Nano, Mega …)"],
        match: EndpointMatchRule(transports: [.usb], usbVendorIDs: [0x2341, 0x2A03]), researchStatus: .partiallyResearched, priority: 3)

    public static let esp32 = EncyclopediaProfile(
        id: "espressif.esp32", category: .microcontroller, manufacturer: "Espressif", productFamily: "ESP32",
        physicalInterfaces: [F("USB via CP210x/CH34x bridge, or native USB (ESP32-S2/S3/C3/C6)", mfr)],
        wirelessInterfaces: [F("Wi-Fi", mfr), F("Bluetooth LE (and Classic on the original ESP32)", mfr)],
        protocols: [F("UART serial console", mfr), F("BLE GATT when the firmware advertises it", mfr)],
        sdks: [F("ESP-IDF, Arduino-ESP32", mfr)],
        safety: [SafetyRestriction("no-flash", "System Tester never flashes firmware or erases flash.", .prohibitedControl, res)],
        connectionMethods: [ConnectionMethod(id: "usb-serial", title: "USB serial (native USB or bridge)", protocolID: "serial", driverID: "usb.enumeration",
                                             requiredEquipment: ["cable.usbc-data"], source: mfr),
                            ConnectionMethod(id: "ble", title: "BLE GATT (if the firmware advertises)", protocolID: "bluetooth.le", driverID: "ble.gatt-read",
                                             requiredEquipment: ["interface.bluetooth"], permissions: ["Bluetooth"], source: mfr)],
        references: [ref("esp-idf", "ESP-IDF Programming Guide", "Espressif", "https://docs.espressif.com/projects/esp-idf/")],
        informationRequests: ["Chip variant (ESP32, S3, C3, C6 …) and dev-board"],
        match: EndpointMatchRule(transports: [.usb], usbVendorIDs: [0x303A]), researchStatus: .partiallyResearched, priority: 3)

    // MARK: Apple and computers

    public static let appleMobile = EncyclopediaProfile(
        id: "apple.iphone-ipad", category: .smartphone, manufacturer: "Apple", productFamily: "iPhone and iPad",
        operatingSystem: F("iOS / iPadOS", mfr),
        physicalInterfaces: [F("USB-C (iPhone 15 and later, recent iPads) or Lightning", mfr)],
        wirelessInterfaces: [F("Wi-Fi, Bluetooth, NFC (payments, not accessible to Macs)", mfr)],
        protocols: [F("Apple usbmux / CoreDevice services after Trust", res), F("Xcode devicectl structured output", mfr)],
        sdks: [F("Xcode devicectl (developer tooling)", mfr)], requiredCables: ["cable.usbc-data"], requiredSoftware: ["software.xcode"],
        authentication: [F("“Trust This Computer” pairing with the device passcode", mfr)],
        permissions: [F("Developer Mode only for developer capabilities (not needed for read-only information)", mfr)],
        safety: [SafetyRestriction("no-bypass", "Never bypass passcodes, pairing, USB Restricted Mode or Activation Lock.", .prohibitedControl, res)],
        connectionMethods: [ConnectionMethod(id: "coredevice", title: "USB + Xcode CoreDevice (Apple Device Intelligence Adapter)", protocolID: "apple.coredevice",
                                             driverID: "apple.coredevice", requiredEquipment: ["cable.usbc-data"], requiredSoftware: ["software.xcode"],
                                             permissions: ["Device Trust"], authentication: "Trust This Computer",
                                             steps: ["Unlock the device and connect it with a data cable.", "Trust this Mac (Pair…).", "Live information and Apple diagnostics become available."],
                                             source: res)],
        references: [ref("apple-support", "Apple Support", "Apple", "https://support.apple.com/")],
        informationRequests: ["Model (Settings › General › About)", "iOS/iPadOS version"],
        match: EndpointMatchRule(transports: [.usb], usbVendorIDs: [0x05AC], nameContains: ["iPhone", "iPad"]), researchStatus: .implemented, priority: 5)

    public static let appleMac = EncyclopediaProfile(
        id: "apple.mac", category: .laptop, manufacturer: "Apple", productFamily: "Mac",
        operatingSystem: F("macOS", mfr),
        physicalInterfaces: [F("Thunderbolt / USB-C, HDMI on some models, Ethernet on some models", mfr)],
        wirelessInterfaces: [F("Wi-Fi, Bluetooth", mfr)],
        protocols: [F("Bonjour (DNS-SD); _device-info._tcp records commonly carry the model identifier", com), F("SSH / Screen Sharing when enabled by the owner", mfr)],
        permissions: [F("Remote Login / Screen Sharing must be enabled by the owner", mfr)],
        safety: [noControl],
        connectionMethods: [ConnectionMethod(id: "mdns", title: "Discover on the LAN (DNS-SD)", protocolID: "network.mdns", driverID: "network.discovery",
                                             requiredEquipment: ["interface.wifi-or-ethernet"], source: com)],
        references: [ref("apple-support", "Apple Support", "Apple", "https://support.apple.com/")],
        match: EndpointMatchRule(transports: [.host, .bonjour], attributeContains: ["model": "Mac"]), researchStatus: .partiallyResearched, priority: 4)

    public static let windowsPC = EncyclopediaProfile(
        id: "microsoft.windows-pc", category: .desktopComputer, manufacturer: "Various", productFamily: "Windows computers",
        operatingSystem: F("Windows 10/11", mfr),
        protocols: [F("SMB file sharing, RDP, OpenSSH server (optional feature)", mfr), F("WS-Discovery / NetBIOS rather than DNS-SD by default", com)],
        permissions: [F("Owner must enable sharing/remote access", mfr)], safety: [noControl],
        connectionMethods: [ConnectionMethod(id: "ssdp", title: "LAN discovery (SSDP/UPnP when enabled)", protocolID: "network.ssdp", driverID: "network.discovery",
                                             requiredEquipment: ["interface.wifi-or-ethernet"], source: com, notes: "Many Windows PCs do not answer discovery by default.")],
        references: [ref("ms-learn", "Microsoft Learn — Windows", "Microsoft", "https://learn.microsoft.com/windows/")],
        informationRequests: ["Windows edition and version", "Which remote services are enabled"],
        match: EndpointMatchRule(attributeContains: ["manufacturer": "microsoft"]), priority: 2)

    public static let linuxPC = EncyclopediaProfile(
        id: "linux.computer", category: .server, manufacturer: "Various", productFamily: "Linux computers",
        operatingSystem: F("Linux distributions", mfr),
        protocols: [F("SSH", mfr), F("Avahi DNS-SD (_workstation._tcp, _ssh._tcp when published)", com)], safety: [noControl],
        connectionMethods: [ConnectionMethod(id: "mdns", title: "Discover on the LAN (DNS-SD)", protocolID: "network.mdns", driverID: "network.discovery",
                                             requiredEquipment: ["interface.wifi-or-ethernet"], source: com)],
        references: [ref("avahi", "Avahi", "Avahi project", "https://avahi.org/", .communityReported)],
        match: EndpointMatchRule(transports: [.bonjour], serviceTypes: ["_workstation._tcp"]), priority: 2)

    // MARK: Sensors and smart home

    public static let bleSensor = EncyclopediaProfile(
        id: "ble.sensor-generic", category: .sensor, manufacturer: "Various", productFamily: "Bluetooth LE sensors",
        wirelessInterfaces: [F("Bluetooth LE", mfr)],
        protocols: [F("GATT standard services: Device Information (0x180A), Battery (0x180F), Heart Rate (0x180D), Environmental Sensing (0x181A)", mfr)],
        permissions: [F("macOS Bluetooth permission", mfr)],
        safety: [SafetyRestriction("no-write", "Characteristics are only read, never written.", .readOnly, res)],
        connectionMethods: [ConnectionMethod(id: "gatt-read", title: "Connect and read standard GATT characteristics", protocolID: "bluetooth.le", driverID: "ble.gatt-read",
                                             requiredEquipment: ["interface.bluetooth"], permissions: ["Bluetooth"],
                                             steps: ["Wake the sensor (many advertise only briefly).", "Scan in the Live Connection Center.", "Approve the connection: System Tester reads Device Information and Battery, then disconnects."],
                                             source: mfr)],
        references: [ref("bt-assigned", "Bluetooth Assigned Numbers", "Bluetooth SIG", "https://www.bluetooth.com/specifications/assigned-numbers/")],
        informationRequests: ["Sensor make and model"],
        match: EndpointMatchRule(transports: [.ble], bleServiceUUIDs: ["180A", "180F", "180D", "181A"]), researchStatus: .implemented, priority: 4)

    public static let smartHome = EncyclopediaProfile(
        id: "smarthome.matter-hap", category: .smartHome, manufacturer: "Various", productFamily: "Matter / HomeKit / Thread accessories",
        wirelessInterfaces: [F("Wi-Fi, Thread or Bluetooth LE depending on the accessory", mfr)],
        protocols: [F("Matter (commissionable _matterc._udp, operational _matter._tcp)", mfr), F("HomeKit Accessory Protocol over IP advertises _hap._tcp", mfr),
                    F("Thread border routers advertise _meshcop._udp", mfr)],
        authentication: [F("Matter/HomeKit setup code and an existing controller fabric", mfr)],
        permissions: [F("macOS Local Network permission", res)],
        safety: [SafetyRestriction("no-commission", "Discovery only: System Tester does not commission, pair or control accessories.", .prohibitedControl, res)],
        connectionMethods: [ConnectionMethod(id: "mdns", title: "Discover Matter / HomeKit / Thread records", protocolID: "matter", driverID: "network.discovery",
                                             requiredEquipment: ["interface.wifi-or-ethernet"], permissions: ["Local Network"], source: mfr)],
        references: [ref("csa-matter", "Matter", "Connectivity Standards Alliance", "https://csa-iot.org/all-solutions/matter/")],
        informationRequests: ["Accessory make/model", "Ecosystem (Apple Home, SmartThings, Google, Amazon)"],
        match: EndpointMatchRule(transports: [.bonjour], serviceTypes: ["_matter", "_matterc", "_hap", "_meshcop"]), researchStatus: .partiallyResearched, priority: 3)
}
