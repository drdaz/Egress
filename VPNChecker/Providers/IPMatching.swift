//
//  IPMatching.swift
//  Egress
//
//  Pure, network-free IPv4 parsing and allowlist matching used by IPCheckProvider.
//

import Foundation

/// Errors thrown while parsing IPv4 addresses or matcher rules.
nonisolated enum IPMatchingError: LocalizedError {
    case invalidAddress(String)
    case invalidRule(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let s): return "Invalid IPv4 address: \(s)"
        case .invalidRule(let s): return "Invalid IP rule: \(s)"
        }
    }
}

/// A parsed IPv4 address, stored as its 32-bit value for cheap comparison/masking.
nonisolated struct IPv4Address: Equatable {
    let value: UInt32

    /// Parses a canonical dotted-quad string ("a.b.c.d"). Throws on anything else.
    init(_ string: String) throws {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { throw IPMatchingError.invalidAddress(string) }

        var result: UInt32 = 0
        for part in parts {
            // UInt8(_:) rejects empty, non-digits, surrounding whitespace, signs, and > 255.
            guard let octet = UInt8(part) else { throw IPMatchingError.invalidAddress(string) }
            result = (result << 8) | UInt32(octet)
        }
        self.value = result
    }
}

/// A single allowlist rule: either an exact host or a CIDR network.
private nonisolated enum IPRule {
    case host(IPv4Address)
    case cidr(network: UInt32, mask: UInt32)

    func contains(_ address: IPv4Address) -> Bool {
        switch self {
        case .host(let host):
            return address == host
        case .cidr(let network, let mask):
            return (address.value & mask) == network
        }
    }

    init(_ string: String) throws {
        let parts = string.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            self = .host(try IPv4Address(string))
        case 2:
            guard let prefix = Int(parts[1]), (0...32).contains(prefix) else {
                throw IPMatchingError.invalidRule(string)
            }
            let address = try IPv4Address(String(parts[0]))
            // `<<` is a smart shift: a shift of 32 yields 0, giving /0 a match-all mask.
            let mask: UInt32 = prefix == 0 ? 0 : (0xFFFF_FFFF << (32 - prefix))
            self = .cidr(network: address.value & mask, mask: mask)
        default:
            throw IPMatchingError.invalidRule(string)
        }
    }
}

/// An allowlist of IPv4 hosts and CIDR ranges. `contains` is true if any rule matches.
nonisolated struct IPMatcher {
    private let rules: [IPRule]

    init(rules ruleStrings: [String]) throws {
        self.rules = try ruleStrings.map { try IPRule($0) }
    }

    func contains(_ address: IPv4Address) -> Bool {
        rules.contains { $0.contains(address) }
    }
}
