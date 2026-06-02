//
//  IPMatchingTests.swift
//  EgressTests
//
//  Pure, network-free tests for IPv4 parsing and allowlist matching.
//

import Testing
@testable import Egress

struct IPv4AddressTests {

    @Test(arguments: [
        "1.2.3.4", "0.0.0.0", "255.255.255.255", "192.168.0.1"
    ])
    func parsesValidAddresses(_ s: String) throws {
        #expect(throws: Never.self) {
            _ = try IPv4Address(s)
        }
    }

    @Test(arguments: [
        "256.1.1.1", "1.2.3", "1.2.3.4.5", "abc", "", "1.2.3.-1", " 1.2.3.4 "
    ])
    func rejectsInvalidAddresses(_ s: String) {
        #expect(throws: (any Error).self) {
            _ = try IPv4Address(s)
        }
    }

    @Test func equalStringsParseEqual() throws {
        #expect(try IPv4Address("192.168.1.1") == IPv4Address("192.168.1.1"))
        #expect(try IPv4Address("192.168.1.1") != IPv4Address("192.168.1.2"))
    }
}

struct IPMatcherTests {

    // (candidate IP, single rule, expected membership)
    @Test(arguments: [
        // single host
        (ip: "192.168.1.5", rule: "192.168.1.5",   expected: true),
        (ip: "192.168.1.6", rule: "192.168.1.5",   expected: false),
        // /24 range
        (ip: "192.168.1.5",   rule: "192.168.1.0/24", expected: true),
        (ip: "192.168.1.255", rule: "192.168.1.0/24", expected: true),  // broadcast still in range
        (ip: "192.168.1.0",   rule: "192.168.1.0/24", expected: true),  // network address in range
        (ip: "192.168.2.5",   rule: "192.168.1.0/24", expected: false),
        // boundaries
        (ip: "10.0.0.1", rule: "10.0.0.1/32", expected: true),          // /32 == single host
        (ip: "10.0.0.2", rule: "10.0.0.1/32", expected: false),
        (ip: "8.8.8.8",  rule: "0.0.0.0/0",   expected: true),          // /0 matches everything
        // a rule written with host bits set should still match on its network
        (ip: "192.168.1.42", rule: "192.168.1.99/24", expected: true),
    ])
    func matches(_ c: (ip: String, rule: String, expected: Bool)) throws {
        let matcher = try IPMatcher(rules: [c.rule])
        #expect(try matcher.contains(IPv4Address(c.ip)) == c.expected)
    }

    @Test func anyOfMultipleRulesMatches() throws {
        let matcher = try IPMatcher(rules: ["10.0.0.0/8", "192.168.1.5"])
        #expect(try matcher.contains(IPv4Address("10.5.5.5")) == true)
        #expect(try matcher.contains(IPv4Address("192.168.1.5")) == true)
        #expect(try matcher.contains(IPv4Address("172.16.0.1")) == false)
    }

    @Test func emptyMatcherMatchesNothing() throws {
        let matcher = try IPMatcher(rules: [])
        #expect(try matcher.contains(IPv4Address("1.2.3.4")) == false)
    }

    @Test(arguments: [
        "192.168.1.0/33", "192.168.1.0/-1", "192.168.1.0/abc", "/24", "192.168.1.0/", "999.0.0.0/8"
    ])
    func rejectsMalformedRule(_ s: String) {
        #expect(throws: (any Error).self) {
            _ = try IPMatcher(rules: [s])
        }
    }
}
