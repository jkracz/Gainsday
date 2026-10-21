import SwiftUI

/// The frame every setup step shares: a heading, the step's own sections, any error,
/// and the button that moves on, pinned to the bottom.
struct SetupStepLayout<Content: View>: View {
    @Environment(SetupModel.self) private var model
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    var buttonDisabled = false
    let action: () async -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title.bold())
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            content

            if let errorMessage = model.errorMessage {
                Section {
                    Text(verbatim: errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await action() }
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(buttonDisabled)
            .padding()
        }
    }
}

/// A point on a setup screen: an icon, a short heading and a sentence or two.
struct SetupPoint: View {
    let title: LocalizedStringKey
    let systemImage: String
    let detail: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
    }
}
