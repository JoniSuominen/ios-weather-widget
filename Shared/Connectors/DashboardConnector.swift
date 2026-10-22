import Foundation

@MainActor
protocol DashboardConnector {
    var source: DataSource { get }

    func authorize() async throws
    func refresh() async throws -> [DashboardMetric]
    func disconnect() async -> DisconnectResult
}

enum OuraConnectionMethod: String, CaseIterable, Identifiable {
    case appleHealth
    case direct
    var id: String { rawValue }
    var displayName: String { self == .direct ? "Oura account" : "Apple Health" }

    static let preferenceKey = "oura.connectionMethod"

    /// The saved choice, shared with the widget so it knows whether Oura data
    /// can be read from Apple Health outside the app.
    static var stored: OuraConnectionMethod {
        let defaults = UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
        return OuraConnectionMethod(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .appleHealth
    }
}

struct DisconnectResult: Codable, Equatable, Sendable {
    enum RemoteAuthorization: String, Codable, Equatable, Sendable {
        case notApplicable
        case revoked
        case unconfirmed
        case noStoredCredentials
    }

    let localCredentialsCleared: Bool
    let remoteAuthorization: RemoteAuthorization

    /// System permission grants are managed by iOS even after local disconnection.
    static let localOnly = DisconnectResult(localCredentialsCleared: true, remoteAuthorization: .notApplicable)
    static let revoked = DisconnectResult(localCredentialsCleared: true, remoteAuthorization: .revoked)
    static let noStoredCredentials = DisconnectResult(localCredentialsCleared: true, remoteAuthorization: .noStoredCredentials)

    var requiresAttention: Bool {
        !localCredentialsCleared || remoteAuthorization == .unconfirmed
    }

    var warningMessage: String? { requiresAttention ? statusMessage : nil }

    var statusMessage: String {
        if !localCredentialsCleared {
            switch remoteAuthorization {
            case .revoked:
                return "Oura account access was revoked, but saved credentials could not be removed from this device. The connection is no longer used. Try disconnecting again."
            case .unconfirmed:
                return "Oura is no longer used, but removal of saved credentials and revocation of Oura account access could not be confirmed. Try disconnecting again and review access in your Oura account."
            case .noStoredCredentials:
                return "Oura is no longer used, but removal of saved credentials from this device could not be confirmed. Try disconnecting again."
            case .notApplicable:
                return "This source is no longer used, but removal of local credentials could not be confirmed. Permissions remain in iOS Settings."
            }
        }
        switch remoteAuthorization {
        case .notApplicable:
            return "Disconnected. Permissions granted in iOS Settings remain unchanged."
        case .revoked:
            return "Disconnected from Oura. Saved credentials were removed and Oura account access was revoked."
        case .unconfirmed:
            return "Disconnected and removed saved Oura credentials. Revoking access in your Oura account could not be confirmed. Review account access in Oura."
        case .noStoredCredentials:
            return "Disconnected. No saved Oura credentials were found. You can review previous app access in your Oura account."
        }
    }
}

enum ConnectorError: LocalizedError {
    case unavailable(String)
    case authorizationDenied(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .authorizationDenied(let message):
            return message
        }
    }
}
