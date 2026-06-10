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

    /// The provider's name as last loaded/saved — used to detect an unsaved rename
    /// and to title the editor section. Published so the section header updates
    /// when a provider is loaded or first saved.
    @Published private(set) var savedName = ""

    /// Reset the editor for creating a brand-new provider.
    func startNew() {
        editingID = nil
        name = ""
        savedName = ""
        ranges = []
        rangeInput = ""
        rangeInputError = nil
    }

    /// Load an existing provider's values for editing.
    func populate(with provider: CustomProvider) {
        editingID = provider.id
        name = provider.name
        savedName = provider.name
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

    /// Remove a specific range value (used by the per-row delete button, which
    /// works on macOS where swipe-to-delete isn't available).
    func removeRange(_ range: String) {
        ranges.removeAll { $0 == range }
    }

    /// True when the provider has a non-empty name and at least one range.
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !ranges.isEmpty
    }

    /// True when editing an existing provider whose (non-empty) name has changed
    /// from the saved one — i.e. there's a rename worth saving explicitly.
    var canSaveNameChange: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return editingID != nil
            && !trimmed.isEmpty
            && trimmed != savedName.trimmingCharacters(in: .whitespaces)
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
    var onRemove: () -> Void = {}

    @State private var showingRemoveConfirmation = false

    private var removeConfirmationTitle: String {
        let name = editor.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Remove this egress point?" : "Remove “\(name)”?"
    }

    /// "Custom Egress" while creating a not-yet-saved entry; "Custom Egress: Work"
    /// once a named provider is loaded or first saved.
    private var sectionTitle: String {
        editor.savedName.isEmpty ? "Custom Egress" : "Custom Egress: \(editor.savedName)"
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text("Define your own egress point — a VPN, a home or office network, a specific location. Add the public IPs it uses and Egress confirms when your traffic is exiting there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.title3)
                        .foregroundStyle(.primary)
                    TextField("Name", text: $editor.name, prompt: Text("e.g. Home network"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit {
                            // Save a rename on Return (ranges auto-save separately).
                            if editor.canSaveNameChange { onSave(editor.makeDraft()) }
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("IPv4 address or CIDR range")
                        .font(.title3)
                        .foregroundStyle(.primary)
                    TextField("Range", text: $editor.rangeInput, prompt: Text("e.g. 203.0.113.0/24"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit {
                            editor.addRange()
                            if editor.canSave { onSave(editor.makeDraft()) }
                        }
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                    if let error = editor.rangeInputError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Press Return to add it to the list and save this egress point.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Kept inside this VStack (not its own Form row) so there's no
                // separator above it — macOS doesn't honor .listRowSeparator here.
                if !editor.ranges.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allowed IPs and ranges")
                            .font(.title3)
                            .foregroundStyle(.primary)
                        Text("If your public IP matches any of these, the app will show you as 'Connected'")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)

            // The ranges table appears once at least one valid range is added.
            // Removal: right-click (macOS) / long-press (iOS) → Remove; iOS also
            // keeps swipe-to-delete via onDelete.
            if !editor.ranges.isEmpty {
                ForEach(editor.ranges, id: \.self) { range in
                    Text(range)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                editor.removeRange(range)
                                persistRangeChange()
                            }
                        }
                }
                .onDelete { offsets in
                    editor.removeRange(at: offsets)
                    persistRangeChange()
                }
            }

            // Remove is available whenever editing an existing provider.
            if editor.editingID != nil {
                HStack {
                    Button("Remove", role: .destructive) { showingRemoveConfirmation = true }
                        .buttonStyle(.borderless)
                        .confirmationDialog(
                            removeConfirmationTitle,
                            isPresented: $showingRemoveConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Remove", role: .destructive) { onRemove() }
                            Button("Cancel", role: .cancel) {}
                        }
                    Spacer()
                }
            }
        } header: {
            Text(sectionTitle)
                .font(.title2)
                .textCase(nil)
                .foregroundStyle(.primary)
        }
    }

    /// Persist a range add/remove while editing an existing provider. Ranges
    /// auto-save (only the name needs an explicit Save); skips when there's no
    /// valid provider to save — e.g. the last range was just removed.
    private func persistRangeChange() {
        guard editor.editingID != nil, editor.canSave else { return }
        onSave(editor.makeDraft())
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
        m.populate(with: CustomProvider(name: "Home network", ranges: ["192.168.1.0/24", "203.0.113.7"]))
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
