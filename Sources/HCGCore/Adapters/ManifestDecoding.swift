import Foundation

/// Accepts identifiers written as JSON numbers or as hexadecimal strings ("0x054C").
struct FlexibleHexInteger<T: FixedWidthInteger & Codable>: Codable {
    var value: T

    init(_ value: T) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(T.self) {
            value = n
            return
        }
        let s = try c.decode(String.self).trimmingCharacters(in: .whitespaces).lowercased()
        let digits = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
        guard let n = T(digits, radix: 16) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "\"\(s)\" is not a hexadecimal identifier")
        }
        value = n
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode("0x" + Hex.pad(UInt64(value), digits: T.bitWidth / 4))
    }
}

extension DeviceMatchRules {
    enum CodingKeys: String, CodingKey {
        case vendorIDs, productIDs, deviceClasses, interfaceClasses, interfaceTriples, nameContains, connectionTypes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            vendorIDs: (try c.decodeIfPresent([FlexibleHexInteger<UInt16>].self, forKey: .vendorIDs) ?? []).map(\.value),
            productIDs: (try c.decodeIfPresent([FlexibleHexInteger<UInt16>].self, forKey: .productIDs) ?? []).map(\.value),
            deviceClasses: (try c.decodeIfPresent([FlexibleHexInteger<UInt8>].self, forKey: .deviceClasses) ?? []).map(\.value),
            interfaceClasses: (try c.decodeIfPresent([FlexibleHexInteger<UInt8>].self, forKey: .interfaceClasses) ?? []).map(\.value),
            interfaceTriples: try c.decodeIfPresent([String].self, forKey: .interfaceTriples) ?? [],
            nameContains: try c.decodeIfPresent([String].self, forKey: .nameContains) ?? [],
            connectionTypes: try c.decodeIfPresent([ConnectionType].self, forKey: .connectionTypes) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !vendorIDs.isEmpty { try c.encode(vendorIDs.map(FlexibleHexInteger.init), forKey: .vendorIDs) }
        if !productIDs.isEmpty { try c.encode(productIDs.map(FlexibleHexInteger.init), forKey: .productIDs) }
        if !deviceClasses.isEmpty { try c.encode(deviceClasses.map(FlexibleHexInteger.init), forKey: .deviceClasses) }
        if !interfaceClasses.isEmpty { try c.encode(interfaceClasses.map(FlexibleHexInteger.init), forKey: .interfaceClasses) }
        if !interfaceTriples.isEmpty { try c.encode(interfaceTriples, forKey: .interfaceTriples) }
        if !nameContains.isEmpty { try c.encode(nameContains, forKey: .nameContains) }
        if !connectionTypes.isEmpty { try c.encode(connectionTypes, forKey: .connectionTypes) }
    }
}

extension AdapterManifest {
    enum CodingKeys: String, CodingKey {
        case schema, id, name, version, publisher, summary, execution, deviceFamilies, connectionTypes, protocols, match
        case hardwareRequirements, driverRequirements, permissions, operations, configuration, compatibility, lifecycle
        case errors, healthChecks, profiles, experimental
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schema: try c.decode(String.self, forKey: .schema),
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            version: try c.decode(SemanticVersion.self, forKey: .version),
            publisher: try c.decode(String.self, forKey: .publisher),
            summary: try c.decodeIfPresent(String.self, forKey: .summary) ?? "",
            execution: try c.decodeIfPresent(AdapterExecutionModel.self, forKey: .execution) ?? .declarative,
            deviceFamilies: try c.decodeIfPresent([DeviceCategory].self, forKey: .deviceFamilies) ?? [],
            connectionTypes: try c.decodeIfPresent([ConnectionType].self, forKey: .connectionTypes) ?? [],
            protocols: try c.decodeIfPresent([String].self, forKey: .protocols) ?? [],
            match: try c.decodeIfPresent(DeviceMatchRules.self, forKey: .match) ?? DeviceMatchRules(),
            hardwareRequirements: try c.decodeIfPresent([String].self, forKey: .hardwareRequirements) ?? [],
            driverRequirements: try c.decodeIfPresent([DriverRequirement].self, forKey: .driverRequirements) ?? [],
            permissions: try c.decodeIfPresent([AdapterPermission].self, forKey: .permissions) ?? [],
            operations: try c.decodeIfPresent([DiagnosticOperationDescriptor].self, forKey: .operations) ?? [],
            configuration: try c.decodeIfPresent(ConfigurationSchema.self, forKey: .configuration) ?? ConfigurationSchema(),
            compatibility: try c.decodeIfPresent(CompatibilityRequirements.self, forKey: .compatibility) ?? CompatibilityRequirements(),
            lifecycle: try c.decodeIfPresent(ConnectionLifecycle.self, forKey: .lifecycle) ?? ConnectionLifecycle(),
            errors: try c.decodeIfPresent([AdapterErrorDescriptor].self, forKey: .errors) ?? [],
            healthChecks: try c.decodeIfPresent([HealthCheckDescriptor].self, forKey: .healthChecks) ?? [],
            profiles: try c.decodeIfPresent([DeviceProfile].self, forKey: .profiles) ?? [],
            experimental: try c.decodeIfPresent(Bool.self, forKey: .experimental) ?? false
        )
    }
}
