import SwiftUI
import SyncCore

/// Edits the title and notes templates, with placeholder chips, starters and a
/// live preview rendered exactly as sync will write it.
struct TemplateEditorView: View {
    private enum Field {
        case title
        case notes
    }

    @Environment(SyncCoordinator.self) private var coordinator
    @State private var title = EventTemplate.default.title
    @State private var notes = EventTemplate.default.notes
    @State private var titleSelection: TextSelection?
    @State private var notesSelection: TextSelection?
    @FocusState private var focusedField: Field?
    /// Chips insert into the field the user was last in, even after it loses focus.
    @State private var lastField = Field.title
    @State private var hasLoaded = false

    private var template: EventTemplate {
        EventTemplate(title: title, notes: notes)
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $title, selection: $titleSelection)
                    .focused($focusedField, equals: .title)
            }

            Section("Notes") {
                TextEditor(text: $notes, selection: $notesSelection)
                    .focused($focusedField, equals: .notes)
                    .frame(minHeight: 130)
                    .font(.body.monospaced())
            }

            Section {
                PlaceholderChips(insert: insert)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Placeholders")
            } footer: {
                Text("Tap a placeholder to add it at the cursor. A notes line, or a title part between ` · `, is left out when one of its values is missing.")
            }

            TemplatePreviewSection(template: template)

            Section {
                ForEach(StarterTemplate.allCases, id: \.self) { starter in
                    Button(starter.displayName) { apply(starter.template) }
                }
                Button("Reset to Default", role: .destructive) { apply(.default) }
            } header: {
                Text("Start From")
            }
        }
        .navigationTitle("Event Template")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: focusedField) { _, field in
            if let field { lastField = field }
        }
        // Saves a second after the last change, so iCloud isn't written on every keystroke.
        .task(id: template) {
            guard hasLoaded, template != coordinator.settings.template else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await save()
        }
        .onDisappear {
            Task { await save() }
        }
    }

    private func load() {
        guard !hasLoaded else { return }
        title = coordinator.settings.template.title
        notes = coordinator.settings.template.notes
        hasLoaded = true
    }

    private func save() async {
        let template = template
        guard hasLoaded, template != coordinator.settings.template else { return }
        await coordinator.updateSettings { $0.template = template }
    }

    private func apply(_ template: EventTemplate) {
        title = template.title
        notes = template.notes
        titleSelection = nil
        notesSelection = nil
    }

    private func insert(_ placeholder: TemplatePlaceholder) {
        switch lastField {
        case .title: insert(placeholder.token, into: $title, selection: $titleSelection)
        case .notes: insert(placeholder.token, into: $notes, selection: $notesSelection)
        }
    }

    private func insert(_ token: String, into text: Binding<String>, selection: Binding<TextSelection?>) {
        var range: Range<String.Index>?
        if case .selection(let selected) = selection.wrappedValue?.indices {
            range = selected
        }
        var updated = text.wrappedValue
        let caret = PlaceholderInsertion.insert(token, into: &updated, replacing: range)
        text.wrappedValue = updated
        selection.wrappedValue = TextSelection(insertionPoint: caret)
    }
}

/// A scrolling row of tappable placeholders.
private struct PlaceholderChips: View {
    var insert: (TemplatePlaceholder) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(TemplatePlaceholder.allCases, id: \.self) { placeholder in
                    Button {
                        insert(placeholder)
                    } label: {
                        Text(verbatim: placeholder.token)
                            .font(.callout.monospaced())
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }
}

extension StarterTemplate {
    var displayName: LocalizedStringKey {
        switch self {
        case .minimal: "Minimal"
        case .detailed: "Detailed"
        case .runner: "Runner"
        }
    }
}
