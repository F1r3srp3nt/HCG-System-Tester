import Foundation

/// Builds the five-layer connectivity assessment and derives the lifecycle status.
/// This is where "a connected cable does not mean communication" is enforced.
public enum ConnectivityAssessor {
    public static func assess(device: DiscoveredDevice, identification: IdentificationResult,
                              compatibility: [AdapterCompatibility], deviceAuthorized: Bool,
                              functionalEvidence: [String]) -> ConnectivityAssessment {
        var layers: [LayerAssessment] = []
        let synthetic = device.provenance.isSynthetic
        let tag = synthetic ? "SYNTHETIC: " : ""

        // 1. Physical
        if !device.isPresent {
            layers.append(LayerAssessment(layer: .physical, state: .unavailable, reason: "The device is no longer present on the bus."))
        } else {
            layers.append(LayerAssessment(layer: .physical, state: .verified,
                reason: tag + "Inferred from enumeration — the host could only read descriptors over a working data link.",
                evidence: [device.source]))
        }

        // 2. Enumeration
        if !device.isPresent {
            layers.append(LayerAssessment(layer: .enumeration, state: .unavailable, reason: "Not enumerated (disconnected)."))
        } else if let usb = device.usb, usb.vendorID != nil, usb.productID != nil {
            var ev = ["VID \(usb.vendorIDHex) PID \(usb.productIDHex)"]
            if let s = usb.speed { ev.append(s.displayName) }
            ev.append("\(usb.interfaces.count) interface(s)")
            layers.append(LayerAssessment(layer: .enumeration, state: .verified, reason: tag + "Descriptors read by the host.", evidence: ev))
        } else if device.thunderbolt != nil {
            layers.append(LayerAssessment(layer: .enumeration, state: .verified, reason: tag + "Thunderbolt switch registered by the host."))
        } else {
            layers.append(LayerAssessment(layer: .enumeration, state: .partial, reason: "The device appeared but its identifiers are incomplete."))
        }

        // 3. Protocol compatibility
        let usb = device.usb
        let osBound: [String] = {
            guard let usb = usb else { return [] }
            var out: [String] = []
            if !usb.bsdNames.isEmpty { out.append("Storage stack published \(usb.bsdNames.joined(separator: ", "))") }
            if !usb.serialDevicePaths.isEmpty { out.append("Serial driver published \(usb.serialDevicePaths.joined(separator: ", "))") }
            for i in usb.interfaces where i.hasDriver {
                out.append("Interface \(i.number) (\(i.functionDescription)) bound to \(i.attachedServices.joined(separator: ", "))")
            }
            return out
        }()
        let meaningfulProtocols = identification.exposedProtocols.filter { !["usb.descriptor", "usb.hub", "synthetic.fixture"].contains($0) }
        if !device.isPresent {
            layers.append(LayerAssessment(layer: .protocolCompatibility, state: .unavailable, reason: "Disconnected."))
        } else if !osBound.isEmpty {
            layers.append(LayerAssessment(layer: .protocolCompatibility, state: .verified,
                reason: tag + "macOS bound a driver to at least one of the device's functions.", evidence: osBound))
        } else if !meaningfulProtocols.isEmpty {
            let names = meaningfulProtocols.map { ProtocolCatalog.descriptor($0)?.name ?? $0 }
            layers.append(LayerAssessment(layer: .protocolCompatibility, state: .partial,
                reason: "Protocols identified (\(names.joined(separator: ", "))) but no driver or adapter currently speaks them.",
                evidence: names))
        } else if device.thunderbolt != nil {
            layers.append(LayerAssessment(layer: .protocolCompatibility, state: .partial, reason: "Switch-level registry only."))
        } else {
            layers.append(LayerAssessment(layer: .protocolCompatibility, state: .notVerified,
                reason: "No known protocol was identified on this device's interfaces."))
        }

        // 4. Authorization
        let needsAuth = compatibility.contains { c in c.availableOperations.contains { $0.impact == .stateChanging } }
        if deviceAuthorized {
            layers.append(LayerAssessment(layer: .authorization, state: .verified, reason: "You authorised this device for sessions."))
        } else if needsAuth {
            layers.append(LayerAssessment(layer: .authorization, state: .notVerified,
                reason: "Some available operations change device state and need your explicit authorisation."))
        } else {
            layers.append(LayerAssessment(layer: .authorization, state: .notApplicable,
                reason: "Read-only host-side diagnostics need no device authorisation."))
        }

        // 5. Functional communication
        if !device.isPresent {
            layers.append(LayerAssessment(layer: .functionalCommunication, state: .unavailable, reason: "Disconnected."))
        } else if !functionalEvidence.isEmpty {
            layers.append(LayerAssessment(layer: .functionalCommunication, state: .verified,
                reason: tag + "Data was exchanged through a supported protocol.", evidence: functionalEvidence))
        } else if !osBound.isEmpty {
            layers.append(LayerAssessment(layer: .functionalCommunication, state: .partial,
                reason: "macOS's own driver is communicating with the device, but System Tester has not exchanged data with it. 0.1.0 diagnostics are host-side and read-only.",
                evidence: osBound))
        } else {
            layers.append(LayerAssessment(layer: .functionalCommunication, state: .notVerified,
                reason: "No data has been exchanged with the device's functions."))
        }
        return ConnectivityAssessment(layers: layers)
    }

    /// Derives the lifecycle status. Recognising a name or ID never yields `.connected`.
    public static func status(device: DiscoveredDevice, identification: IdentificationResult,
                              compatibility: [AdapterCompatibility], assessment: ConnectivityAssessment) -> (DeviceStatus, String) {
        if !device.isPresent { return (.disconnected, "The device left the bus.") }
        if assessment.state(of: .functionalCommunication) == .verified {
            if assessment.state(of: .authorization) == .verified {
                return (.authenticated, "Functional communication verified within an authorised session.")
            }
            return (.connected, "Functional communication verified.")
        }
        let availableOps = compatibility.flatMap(\.availableOperations)
        let primary = identification.exposedProtocols.filter { !["usb.descriptor", "usb.hub", "thunderbolt.registry", "synthetic.fixture"].contains($0) }
        let levels = primary.compactMap { ProtocolCatalog.descriptor($0)?.support }
        if identification.isIdentified && !levels.isEmpty && levels.allSatisfy({ $0 == .requiresAdapter || $0 == .unavailable }) {
            if levels.contains(.requiresAdapter) {
                return (.adapterRequired, "Its functions (\(primary.joined(separator: ", "))) need an adapter that is not installed. Host-side diagnostics: \(availableOps.count).")
            }
            return (.unsupported, "Its functions (\(primary.joined(separator: ", "))) are not supported on this connection. Host-side diagnostics: \(availableOps.count).")
        }
        if !availableOps.isEmpty {
            return (.diagnosticsAvailable, "\(availableOps.count) read-only host-side diagnostic(s) available. Functional communication not verified.")
        }
        if compatibility.contains(where: { $0.status == .notExecutable }) {
            return (.adapterRequired, "A matching adapter exists but is not approved or enabled.")
        }
        if identification.isIdentified { return (.identified, "Identified; no diagnostics apply.") }
        if assessment.state(of: .enumeration) == .verified { return (.unsupported, "No profile or adapter supports this device.") }
        return (.detected, "Seen by the host; not yet identified.")
    }
}
