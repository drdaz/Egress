//
//  ProviderTestSupport.swift
//  EgressTests
//
//  Shared test doubles and factories for the config/provider tests. Egress info
//  is supplied by a StubResolver so behaviour is fully determined by inputs we
//  control — no real networking.
//

import Foundation
import Combine
@testable import Egress

// MARK: - Resolver double

/// Test double that returns a fixed egress result instead of hitting the network.
struct StubResolver: CurrentIPResolver {
    let result: Result<EgressInfo, Error>
    func resolve() async throws -> EgressInfo { try result.get() }

    /// A resolver that always reports egress at `ip`.
    static func resolving(to ip: String) -> StubResolver {
        StubResolver(result: .success(info(ip)))
    }
}

func info(
    _ ip: String,
    country: String? = "Testland",
    city: String? = "Testville",
    organization: String? = "TestOrg"
) -> EgressInfo {
    EgressInfo(ipAddress: ip, country: country, city: city, organization: organization)
}

// MARK: - Filesystem

/// Creates a fresh temporary directory and removes it when `body` returns.
func withTempDirectory(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

// MARK: - iCloud key-value store double

/// In-memory `KeyValueSyncing` for CloudConfigSync tests, with a hook to
/// simulate an external (other-device) change.
final class FakeKVStore: KeyValueSyncing, @unchecked Sendable {
    var storage: [String: Data] = [:]
    private let subject = PassthroughSubject<Void, Never>()
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data?, forKey key: String) { storage[key] = data }
    @discardableResult func synchronize() -> Bool { true }
    var externalChanges: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    func fireExternalChange() { subject.send() }
}

// MARK: - Config factories

extension AppConfig {
    /// A config containing `provider` with it selected — the common test setup.
    static func selecting(_ provider: CustomProvider, modifiedAt: Date = .distantPast) -> AppConfig {
        AppConfig(customProviders: [provider], selection: .custom(provider.id), providersModifiedAt: modifiedAt)
    }
}
