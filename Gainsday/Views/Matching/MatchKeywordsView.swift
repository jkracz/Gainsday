import SwiftUI
import SyncCore

/// The workout types, each with the keywords that match a plan to it. [v1.1]
struct MatchKeywordsView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        List {
            Section {
                ForEach(types, id: \.self) { type in
                    NavigationLink {
                        TypeKeywordsView(type: type)
                    } label: {
                        LabeledContent(type.displayName, value: summary(for: type))
                    }
                }
            } footer: {
                Text("A plan whose title contains a keyword for the workout's type is matched to it.")
            }
        }
        .navigationTitle("Keywords")
    }

    /// The types that have keywords, sorted by name.
    private var types: [WorkoutActivityType] {
        WorkoutActivityType.known.filter { MatchKeywords.builtIn[$0] != nil }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func summary(for type: WorkoutActivityType) -> String {
        let count = coordinator.settings.matchKeywords[type]?.count ?? 0
        return count == 0 ? "" : String(localized: "\(count) added")
    }
}

/// One type's keywords: the user's own, which they can add and delete, and the built-in ones.
struct TypeKeywordsView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    let type: WorkoutActivityType
    @State private var newKeyword = ""

    var body: some View {
        List {
            Section {
                ForEach(userKeywords, id: \.self) { keyword in
                    Text(verbatim: keyword)
                }
                .onDelete { offsets in
                    let removed = offsets.map { userKeywords[$0] }
                    coordinator.updateSettings { settings in
                        for keyword in removed {
                            settings.removeMatchKeyword(keyword, for: type)
                        }
                    }
                }
                HStack {
                    TextField("Add Keyword", text: $newKeyword)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Your Keywords")
            } footer: {
                Text("For example, the name of your club or a weekly event. Case and accents don't matter.")
            }
            Section("Built In") {
                Text(verbatim: (MatchKeywords.builtIn[type] ?? []).joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(type.displayName)
    }

    private var userKeywords: [String] {
        coordinator.settings.matchKeywords[type] ?? []
    }

    private func add() {
        var preview = coordinator.settings
        guard preview.addMatchKeyword(newKeyword, for: type) else { return }
        let keyword = newKeyword
        coordinator.updateSettings { _ = $0.addMatchKeyword(keyword, for: type) }
        newKeyword = ""
    }
}

/// A row that opens the keyword list.
struct MatchKeywordsLink: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationLink {
            MatchKeywordsView()
        } label: {
            LabeledContent("Keywords", value: summary)
        }
    }

    private var summary: String {
        let count = coordinator.settings.matchKeywords.values.reduce(0) { $0 + $1.count }
        return count == 0 ? String(localized: "Built In") : String(localized: "\(count) added")
    }
}
