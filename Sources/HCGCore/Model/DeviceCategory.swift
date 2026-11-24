import Foundation

public enum DeviceCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case playStation
    case xbox
    case nintendo
    case smartphone
    case tablet
    case computer
    case server
    case smartRefrigerator
    case smartTelevision
    case smartHome
    case networkEquipment
    case microcontroller
    case robotics
    case storage
    case camera
    case audio
    case industrial
    case gamingAccessory
    case inputDevice
    case usbInfrastructure
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .playStation: return "PlayStation"
        case .xbox: return "Xbox"
        case .nintendo: return "Nintendo"
        case .smartphone: return "Smartphone"
        case .tablet: return "Tablet"
        case .computer: return "Computer"
        case .server: return "Server"
        case .smartRefrigerator: return "Smart refrigerator"
        case .smartTelevision: return "Smart television"
        case .smartHome: return "Smart home"
        case .networkEquipment: return "Network equipment"
        case .microcontroller: return "Microcontroller"
        case .robotics: return "Robotics"
        case .storage: return "Storage"
        case .camera: return "Camera"
        case .audio: return "Audio equipment"
        case .industrial: return "Industrial equipment"
        case .gamingAccessory: return "Gaming accessory"
        case .inputDevice: return "Input device"
        case .usbInfrastructure: return "USB hub / dock"
        case .unknown: return "Unknown electronic system"
        }
    }

    public var symbolName: String {
        switch self {
        case .playStation, .xbox, .nintendo: return "gamecontroller"
        case .smartphone: return "iphone"
        case .tablet: return "ipad"
        case .computer: return "desktopcomputer"
        case .server: return "server.rack"
        case .smartRefrigerator: return "refrigerator"
        case .smartTelevision: return "tv"
        case .smartHome: return "homekit"
        case .networkEquipment: return "network"
        case .microcontroller: return "cpu"
        case .robotics: return "gearshape.2"
        case .storage: return "externaldrive"
        case .camera: return "camera"
        case .audio: return "hifispeaker"
        case .industrial: return "gauge.with.dots.needle.bottom.50percent"
        case .gamingAccessory: return "gamecontroller.fill"
        case .inputDevice: return "keyboard"
        case .usbInfrastructure: return "point.3.filled.connected.trianglepath.dotted"
        case .unknown: return "questionmark.square.dashed"
        }
    }
}
