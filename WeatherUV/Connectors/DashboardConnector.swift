import Foundation

protocol DashboardConnector {
    var source: DataSource { get }

    func authorize() async throws
    func refresh() async throws -> [DashboardMetric]
    func disconnect() async
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
