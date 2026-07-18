import SwiftUI

/// UV index risk levels per WHO, with a label and a color used across all widget sizes.
enum UVLevel: String {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case veryHigh = "Very High"
    case extreme = "Extreme"

    init(index: Double) {
        switch index {
        case ..<3: self = .low
        case ..<6: self = .moderate
        case ..<8: self = .high
        case ..<11: self = .veryHigh
        default: self = .extreme
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .extreme: return .purple
        }
    }

    /// Short label suitable for very small widgets.
    var shortLabel: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Mod"
        case .high: return "High"
        case .veryHigh: return "V.High"
        case .extreme: return "Extr"
        }
    }
}
