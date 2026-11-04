import SwiftUI
import SyncCore

extension WorkoutActivityType {
    var tint: Color {
        switch self {
        case .running, .hiking: Color(.workoutRun)
        case .traditionalStrengthTraining, .functionalStrengthTraining, .highIntensityIntervalTraining: Color(.workoutStrength)
        case .cycling, .elliptical, .rowing: Color(.workoutCycle)
        case .swimming: Color(.workoutSwim)
        case .yoga: Color(.workoutYoga)
        case .walking: Color(.workoutWalk)
        default: Color(.workoutOther)
        }
    }
}

/// A full-width capsule button for primary actions.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Color(.buttonLabel))
            .background(Color(.buttonFill), in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

/// An outlined capsule button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .foregroundStyle(Color(.ink))
            .overlay(Capsule().strokeBorder(Color(.hairline), lineWidth: 1.5))
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.card), in: .rect(cornerRadius: 20))
    }

    func canvasBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color(.canvas))
    }
}

/// A tinted status pill.
struct Badge: View {
    let text: Text
    let color: Color

    init(_ text: Text, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        text
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: .capsule)
    }
}

/// An uppercase section heading.
struct SectionLabel: View {
    let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color(.inkSecondary))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A white glyph on a coloured tile.
struct IconTile: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: .rect(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}
