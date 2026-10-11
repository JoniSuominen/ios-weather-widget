import Foundation

@MainActor
protocol DashboardConnector {
    var source: DataSource { get }

    func authorize() async throws
    func refresh() async throws -> [DashboardMetric]
    func disconnect() async -> DisconnectResult
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
                return "Oura account access was revoked, but saved credentials could not be removed from this device. Pulseboard has stopped using the connection. Try disconnecting again."
            case .unconfirmed:
                return "Pulseboard stopped using Oura, but could not confirm removal of saved credentials or revocation of Oura account access. Try disconnecting again and review access in your Oura account."
            case .noStoredCredentials:
                return "Pulseboard stopped using Oura, but could not confirm removal of saved credentials from this device. Try disconnecting again."
            case .notApplicable:
                return "Pulseboard stopped using this source, but could not confirm removal of local credentials. Permissions remain in iOS Settings."
            }
        }
        switch remoteAuthorization {
        case .notApplicable:
            return "Disconnected in Pulseboard. Permissions granted in iOS Settings remain unchanged."
        case .revoked:
            return "Disconnected from Oura. Saved credentials were removed and Oura account access was revoked."
        case .unconfirmed:
            return "Disconnected in Pulseboard and removed saved Oura credentials. Revoking access in your Oura account could not be confirmed. Review account access in Oura."
        case .noStoredCredentials:
            return "Disconnected in Pulseboard. No saved Oura credentials were found. You can review previous app access in your Oura account."
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
