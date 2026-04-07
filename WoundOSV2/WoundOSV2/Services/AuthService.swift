import Foundation
import KeychainAccess

final class AuthService: ObservableObject {
    static let shared = AuthService()

    private let keychain = Keychain(service: "com.careplix.woundos-v2")
    private let tokenKey = "auth_token"
    private let refreshTokenKey = "refresh_token"

    @Published var isAuthenticated: Bool = false

    var currentToken: String? {
        try? keychain.get(tokenKey)
    }

    private init() {
        isAuthenticated = currentToken != nil
    }

    func storeToken(_ token: String, refreshToken: String? = nil) {
        try? keychain.set(token, key: tokenKey)
        if let refreshToken = refreshToken {
            try? keychain.set(refreshToken, key: refreshTokenKey)
        }
        isAuthenticated = true
    }

    func clearToken() {
        try? keychain.remove(tokenKey)
        try? keychain.remove(refreshTokenKey)
        isAuthenticated = false
    }

    func refreshTokenIfNeeded() async throws {
        guard let refreshToken = try? keychain.get(refreshTokenKey) else {
            throw AuthError.noRefreshToken
        }
        // Placeholder for real token refresh
        _ = refreshToken
    }

    enum AuthError: Error, LocalizedError {
        case noRefreshToken
        case refreshFailed

        var errorDescription: String? {
            switch self {
            case .noRefreshToken: return "No refresh token available"
            case .refreshFailed: return "Token refresh failed"
            }
        }
    }
}
