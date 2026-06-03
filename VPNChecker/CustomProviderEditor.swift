//
//  CustomProviderEditor.swift
//  Egress
//
//  State and UI for creating/editing a custom IP-based provider, shown inside
//  the settings screen. Persistence of the saved provider is wired in a later task.
//

import SwiftUI
import Combine

// MARK: - Picker choice (built-in / custom / "Add Custom")

/// What the settings picker can point at: a real provider selection, or the
/// "Add Custom" action that reveals an empty editor.
nonisolated enum ProviderChoice: Hashable {
    case selection(SelectedProvider)
    case addCustom
}

/// A labelled entry in the settings picker.
nonisolated struct ProviderChoiceItem: Identifiable, Hashable {
    let choice: ProviderChoice
    let label: String
    var id: ProviderChoice { choice }
}

extension AppConfig {
    /// Picker contents for the settings screen: the provider items followed by
    /// the "Add Custom" action.
    var providerChoiceItems: [ProviderChoiceItem] {
        pickerItems.map { ProviderChoiceItem(choice: .selection($0.selection), label: $0.label) }
            + [ProviderChoiceItem(choice: .addCustom, label: "Add Custom…")]
    }
}

// MARK: - Editor visibility

/// Whether (and how) the custom-provider editor is shown for a given picker choice.
nonisolated enum ProviderEditorMode: Equatable {
    case hidden
    case creating
    case editing(UUID)

    init(choice: ProviderChoice) {
        switch choice {
        case .selection(.builtin):
            self = .hidden
        case .selection(.custom(let id)):
            self = .editing(id)
        case .addCustom:
            self = .creating
        }
    }
}

// MARK: - Editor model

/// Holds the in-progress custom provider: its name, the range being typed, and
/// the list of accepted ranges. Validation reuses `IPMatcher` so the editor and
/// the matcher agree on what a valid range is.
@MainActor
final class CustomProviderEditorModel: ObservableObject {
    @Published var name = ""
    @Published var rangeInput = ""
    @Published private(set) var ranges: [String] = []
    @Published private(set) var rangeInputError: String?

    /// The id of the provider being edited, or `nil` when creating a new one.
    private(set) var editingID: UUID?

    /// Reset the editor for creating a brand-new provider.
    func startNew() {
        editingID = nil
        name = ""
        ranges = []
        rangeInput = ""
        rangeInputError = nil
    }

    /// Load an existing provider's values for editing.
    func startEditing(_ provider: CustomProvider) {
        editingID = provider.id
        name = provider.name
        ranges = provider.ranges
        rangeInput = ""
        rangeInputError = nil
    }

    /// Validate `rangeInput` and, if it's a valid (non-duplicate) IP/CIDR, append it.
    func addRange() {
        let trimmed = rangeInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            rangeInputError = nil
            return
        }
        // Reuse the real matcher as the validator so editor and matching agree.
        do {
            _ = try IPMatcher(rules: [trimmed])
        } catch {
            rangeInputError = "Enter a valid IPv4 address or CIDR range (e.g. 203.0.113.0/24)."
            return
        }
        guard !ranges.contains(trimmed) else {
            rangeInputError = "That range is already in the list."
            return
        }
        ranges.append(trimmed)
        rangeInput = ""
        rangeInputError = nil
    }

    func removeRange(at offsets: IndexSet) {
        ranges.remove(atOffsets: offsets)
    }

    /// True when the provider has a non-empty name and at least one range.
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !ranges.isEmpty
    }

    /// Build the provider value to persist. Preserves the id when editing.
    func makeDraft() -> CustomProvider {
        CustomProvider(
            id: editingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            ranges: ranges
        )
    }
}

// MARK: - Editor view

/// Form section with the name field, range entry, the list of added ranges, and
/// a Save button. `onSave` is injected so persistence can be wired separately.
struct CustomProviderEditorView: View {
    @ObservedObject var editor: CustomProviderEditorModel
    var onSave: (CustomProvider) -> Void

    var body: some View {
        Section("Custom Provider") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $editor.name, prompt: Text("e.g. Home network"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                Spacer()
                Text("IPv4 address or CIDR range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Range", text: $editor.rangeInput, prompt: Text("e.g. 203.0.113.0/24"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit { editor.addRange() }
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #endif
                Spacer()
                HStack {
                    Spacer()
                    Button("Add") { editor.addRange() }
                        .disabled(editor.rangeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let error = editor.rangeInputError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // The ranges table and Save button appear once at least one valid
            // range has been added.
            if !editor.ranges.isEmpty {
                ForEach(editor.ranges, id: \.self) { range in
                    Text(range)
                }
                .onDelete { editor.removeRange(at: $0) }

                HStack {
                    Spacer()
                    Button("Save") { onSave(editor.makeDraft()) }
                        .disabled(!editor.canSave)
                }
            }
        }
    }
}

// MARK: - Previews

/// Wraps the editor section in a Form so previews render it the way the settings
/// screen does.
private struct EditorPreviewContainer: View {
    let model: CustomProviderEditorModel

    var body: some View {
        Form {
            CustomProviderEditorView(editor: model) { _ in }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 380)
        #endif
    }
}

#Preview("New") {
    EditorPreviewContainer(model: CustomProviderEditorModel())
}

#Preview("Editing") {
    let model: CustomProviderEditorModel = {
        let m = CustomProviderEditorModel()
        m.startEditing(CustomProvider(name: "Home network", ranges: ["192.168.1.0/24", "203.0.113.7"]))
        return m
    }()
    EditorPreviewContainer(model: model)
}

#Preview("Validation error") {
    let model: CustomProviderEditorModel = {
        let m = CustomProviderEditorModel()
        m.name = "Office"
        m.rangeInput = "not-an-ip"
        m.addRange()   // populates rangeInputError
        return m
    }()
    EditorPreviewContainer(model: model)
}
