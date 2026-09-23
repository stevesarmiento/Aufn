import SwiftUI

/// Card fills for the projects grid. Graphite is the neutral default; the rest
/// are the system palette so they sit naturally next to the accent. Purely
/// cosmetic — nothing in the audio chain reads it.
enum ProjectTint: String, CaseIterable, Codable, Hashable {
    case graphite, red, orange, yellow, green, teal, blue, indigo, purple, pink

    var color: Color {
        switch self {
        case .graphite: Color(white: 0.13)
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }

    var displayName: String { rawValue.capitalized }

    /// Tint for the Nth project created, so fresh cards vary out of the box.
    static func rotating(index: Int) -> ProjectTint {
        allCases[((index % allCases.count) + allCases.count) % allCases.count]
    }
}
