import Foundation

/// Modular device classification. Profiles come from built-ins plus any
/// registered adapters; the engine never invents support.
public final class IdentificationEngine {
    public private(set) var profiles: [DeviceProfile]

    public init(profiles: [DeviceProfile] = BuiltInProfiles.all) {
        self.profiles = profiles
    }

    public func register(_ profile: DeviceProfile) {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
    }

    public func register(contentsOf newProfiles: [DeviceProfile]) {
        newProfiles.forEach(register)
    }

    public func identify(_ device: DiscoveredDevice) -> IdentificationResult {
        struct Candidate { let profile: DeviceProfile; let score: Double; let evidence: [String] }

        let candidates: [Candidate] = profiles.compactMap { profile in
            guard let r = profile.match.evaluate(device) else { return nil }
            return Candidate(profile: profile, score: r.score, evidence: r.evidence)
        }.sorted { a, b in
            if a.profile.priority != b.profile.priority { return a.profile.priority > b.profile.priority }
            if a.score != b.score { return a.score > b.score }
            return a.profile.id < b.profile.id
        }

        guard let best = candidates.first else {
            var reasons: [String] = []
            if let usb = device.usb {
                reasons.append("VID \(usb.vendorIDHex) PID \(usb.productIDHex), class \(usb.usbClass.name)")
                if let vendor = USBVendorDatabase.name(for: usb.vendorID) { reasons.append("Vendor: \(vendor)") }
                reasons.append("Interfaces: " + (usb.interfaces.isEmpty ? "none reported" : usb.interfaces.map(\.functionDescription).joined(separator: ", ")))
            }
            var result = IdentificationResult.unidentified(reason: "No device profile matched.")
            result.evidence += reasons
            if device.usb?.vendorID != nil { result.confidence = .none }
            return result
        }

        var protocols = best.profile.exposedProtocols
        // Add protocols evidenced by interfaces even if the profile does not list them.
        for p in ProtocolCatalog.protocols(evidencedBy: device) where !protocols.contains(p) {
            protocols.append(p)
        }

        return IdentificationResult(
            category: best.profile.category,
            profileID: best.profile.id,
            profileName: best.profile.name,
            family: best.profile.family,
            role: device.usb?.isHub == true ? .usbHub : best.profile.role,
            score: best.score,
            confidence: IdentificationConfidence(score: best.score),
            evidence: best.evidence,
            exposedProtocols: protocols,
            recommendedAdapters: best.profile.recommendedAdapters,
            knownLimitations: best.profile.knownLimitations,
            alternatives: candidates.dropFirst().prefix(4).map { "\($0.profile.name) (\($0.profile.id))" }
        )
    }
}
