import SwiftUI

/// Shared setup content, progress and bottom action.
struct SetupScreen<Content: View>: View {
    @Environment(SetupModel.self) private var model
    let step: SetupStep
    let title: LocalizedStringKey
    let subtitle: Text
    let buttonTitle: LocalizedStringKey
    var buttonDisabled = false
    let action: () async -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color(.ink))
                    subtitle
                        .font(.body)
                        .foregroundStyle(Color(.inkSecondary))
                }
                content
                if let errorMessage = model.errorMessage {
                    Text(verbatim: errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color(.danger))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.canvas))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                StepDashes(current: step.index, count: SetupStep.allCases.count)
            }
        }
        .safeAreaBar(edge: .bottom) {
            Button {
                Task { await action() }
            } label: {
                Text(buttonTitle)
            }
            .buttonStyle(.primary)
            .disabled(buttonDisabled)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

/// Setup progress dashes.
private struct StepDashes: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color(.ink) : Color(.hairline))
                    .frame(width: 28, height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(current + 1) of \(count)"))
    }
}

/// Wraps views into rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
