//
//  VPNStatusChecker.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import Foundation
internal import Combine

/// Service class for checking VPN status
class VPNStatusChecker: ObservableObject {
    @Published var currentStatus: VPNStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let provider: VPNProvider
    
    init(provider: VPNProvider = MullvadProvider()) {
        self.provider = provider
    }
    
    func checkStatus() async {
        await MainActor.run { isLoading = true }
        await MainActor.run { errorMessage = nil }
        
        do {
            let status = try await provider.checkStatus()
            await MainActor.run { currentStatus = status }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        
        await MainActor.run { isLoading = false }
    }
    
    /// Static method for use in widgets (which can't use @MainActor easily)
    static func checkStatus(using provider: VPNProvider? = nil) async throws -> VPNStatus {
        let actualProvider = provider ?? MullvadProvider()
        return try await actualProvider.checkStatus()
    }
}
