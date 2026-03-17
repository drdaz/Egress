//
//  VPNStatusChecker.swift
//  VPNChecker
//
//  Created by Darren Black on 14/03/2026.
//

import Foundation
internal import Combine

/// Service class for checking VPN status
@MainActor
class VPNStatusChecker: ObservableObject {
    @Published var currentStatus: VPNStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let provider: VPNProvider
    
    init(provider: VPNProvider = MullvadProvider()) {
        self.provider = provider
    }
    
    func checkStatus() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let status = try await provider.checkStatus()
            currentStatus = status
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Static method for use in widgets (which can't use @MainActor easily)
    static func checkStatus(using provider: VPNProvider = MullvadProvider()) async throws -> VPNStatus {
        return try await provider.checkStatus()
    }
}
