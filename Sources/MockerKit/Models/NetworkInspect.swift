import Foundation

/// Docker-compatible `network inspect` output (mirrors `docker network inspect`).
/// Serializes with Docker PascalCase JSON keys per the moby v29.6.1 network.Inspect shape.
/// Containers is always `{}` in v0.6.0 — Apple-runtime enrichment is deferred to a follow-up PR.
public struct NetworkInspect: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case Name, Id, Created, Scope, Driver, EnableIPv4, EnableIPv6
        case IPAM, Internal, Attachable, Ingress, ConfigFrom, ConfigOnly
        case Containers, Options, Labels
    }

    public let Name: String
    public let Id: String
    public let Created: String
    public let Scope: String
    public let Driver: String
    public let EnableIPv4: Bool
    public let EnableIPv6: Bool
    public let IPAM: NetworkIPAM
    public let Internal: Bool
    public let Attachable: Bool
    public let Ingress: Bool
    public let ConfigFrom: NetworkConfigReference
    public let ConfigOnly: Bool
    public var Containers: [String: NetworkEndpointResource]
    public let Options: [String: String]
    public let Labels: [String: String]

    public init(
        Name: String, Id: String, Created: String, Scope: String, Driver: String,
        EnableIPv4: Bool, EnableIPv6: Bool, IPAM: NetworkIPAM,
        Internal: Bool, Attachable: Bool, Ingress: Bool,
        ConfigFrom: NetworkConfigReference, ConfigOnly: Bool,
        Containers: [String: NetworkEndpointResource],
        Options: [String: String], Labels: [String: String]
    ) {
        self.Name = Name; self.Id = Id; self.Created = Created
        self.Scope = Scope; self.Driver = Driver
        self.EnableIPv4 = EnableIPv4; self.EnableIPv6 = EnableIPv6
        self.IPAM = IPAM; self.Internal = Internal
        self.Attachable = Attachable; self.Ingress = Ingress
        self.ConfigFrom = ConfigFrom; self.ConfigOnly = ConfigOnly
        self.Containers = Containers; self.Options = Options; self.Labels = Labels
    }
}

/// Docker-compatible IPAM sub-object. `Encodable` only — inspect output is write-only.
/// Custom `encode(to:)` guarantees `"Options": null` when Options is nil (Docker parity).
public struct NetworkIPAM: Encodable, Sendable {
    enum CodingKeys: String, CodingKey { case Driver, Options, Config }

    public let Driver: String
    public let Options: [String: String]?
    public let Config: [NetworkIPAMConfig]

    public init(Driver: String, Options: [String: String]?, Config: [NetworkIPAMConfig]) {
        self.Driver = Driver; self.Options = Options; self.Config = Config
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Driver, forKey: .Driver)
        if let opts = Options { try c.encode(opts, forKey: .Options) }
        else { try c.encodeNil(forKey: .Options) }
        try c.encode(Config, forKey: .Config)
    }
}

/// One IPAM config entry. `IPRange` and `AuxiliaryAddresses` are omitted (moby omitempty).
public struct NetworkIPAMConfig: Codable, Sendable {
    enum CodingKeys: String, CodingKey { case Subnet, Gateway }

    public let Subnet: String
    public let Gateway: String?

    public init(Subnet: String, Gateway: String? = nil) {
        self.Subnet = Subnet; self.Gateway = Gateway
    }
}

/// `ConfigFrom` sub-object. Always present with `Network: ""` when no config network is set.
public struct NetworkConfigReference: Codable, Sendable {
    enum CodingKeys: String, CodingKey { case Network }

    public let Network: String

    public init(Network: String = "") { self.Network = Network }
}

/// Endpoint resource entry in the `Containers` map.
/// Defined now so the map type is stable for the Apple-runtime enrichment follow-up.
public struct NetworkEndpointResource: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case Name, EndpointID, MacAddress, IPv4Address, IPv6Address
    }

    public let Name: String
    public let EndpointID: String
    public let MacAddress: String
    public let IPv4Address: String
    public let IPv6Address: String

    public init(Name: String, EndpointID: String, MacAddress: String, IPv4Address: String, IPv6Address: String) {
        self.Name = Name; self.EndpointID = EndpointID; self.MacAddress = MacAddress
        self.IPv4Address = IPv4Address; self.IPv6Address = IPv6Address
    }
}

/// Maps mocker's internal `NetworkInfo` to a Docker-compatible `NetworkInspect`. Pure, no I/O.
public func mapToNetworkInspect(_ info: NetworkInfo) -> NetworkInspect {
    let ipamConfig: [NetworkIPAMConfig]
    if let subnet = info.subnet, !subnet.isEmpty {
        ipamConfig = [NetworkIPAMConfig(
            Subnet: subnet,
            Gateway: info.gateway.flatMap { $0.isEmpty ? nil : $0 }
        )]
    } else {
        ipamConfig = []
    }
    return NetworkInspect(
        Name: info.name, Id: info.id,
        Created: rfc3339String(info.created),
        Scope: "local", Driver: info.driver,
        EnableIPv4: true, EnableIPv6: false,
        IPAM: NetworkIPAM(Driver: "default", Options: nil, Config: ipamConfig),
        Internal: false, Attachable: false, Ingress: false,
        ConfigFrom: NetworkConfigReference(), ConfigOnly: false,
        Containers: [:], Options: [:], Labels: info.labels
    )
}

private func rfc3339String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
