import SwiftUI

/// Settings content shared between the macOS Settings scene and the iOS settings
/// sheet. Hosts the provider picker and, when "Add Custom" or an existing custom
/// provider is selected, the custom-provider editor.
struct SettingsView: View {
    @ObservedObject private var providerSelection = ProviderSelection.shared
    @StateObject private var editor = CustomProviderEditorModel()

    @State private var choice: ProviderChoice = .selection(ProviderSelection.shared.selection)
    @State private var mode: ProviderEditorMode = .hidden

    private var choiceItems: [ProviderChoiceItem] {
        ConfigStore.load().providerChoiceItems
    }

    #if os(macOS)
    private let maxHeight: CGFloat = 800
    @State private var contentHeight: CGFloat = 320
    #endif

    var body: some View {
        #if os(macOS)
        // Hug content vertically (so the window resizes with the editor) but cap at
        // maxHeight; beyond that the outer ScrollView scrolls instead of clipping.
        ScrollView {
            settingsForm
                .formStyle(.grouped)
                .frame(width: 380)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        .frame(width: 380, height: min(contentHeight, maxHeight))
        #else
        settingsForm
        #endif
    }

    private var settingsForm: some View {
        Form {
            Section() {
                Picker("Location", selection: $choice) {
                    ForEach(choiceItems) { item in
                        Text(item.label).tag(item.choice)
                    }
                }
            } header: {
                Text("Egress via")
                    .font(.title2)
                    .textCase(nil)
            }

            if mode != .hidden {
                CustomProviderEditorView(
                    editor: editor,
                    onSave: { draft in
                        guard (try? CustomProviderSaver.save(draft)) != nil else { return }
                        // Adopt the saved id so a subsequent Save updates this provider
                        // instead of creating a duplicate.
                        editor.populate(with: draft)
                        // Auto-select the just-saved provider: setting `choice` cascades
                        // through onChange to update the active selection and editor mode.
                        choice = .selection(.custom(draft.id))
                        // Mirror the change to iCloud (covers same-id edits, where the
                        // choice doesn't change and onChange wouldn't fire).
                        CloudConfigSync.shared.push()
                    },
                    onRemove: {
                        guard let id = editor.editingID else { return }
                        CustomProviderSaver.remove(id: id)
                        CloudConfigSync.shared.push()
                        // Pick up the post-removal selection (reset to default if it
                        // was the removed provider) and reflect it in the picker, which
                        // hides the editor.
                        providerSelection.reload()
                        choice = .selection(providerSelection.selection)
                    }
                )
            }
        }
        .onAppear { syncEditor(to: choice) }
        .onChange(of: choice) { _, newChoice in
            if case .selection(let selection) = newChoice {
                providerSelection.select(selection)
            }
            syncEditor(to: newChoice)
            // Note: selection is per-device and intentionally not pushed to iCloud.
        }
    }

    /// Configure the editor's contents to match the current choice (without
    /// mutating the active selection).
    private func syncEditor(to choice: ProviderChoice) {
        switch choice {
        case .selection(.custom(let id)):
            if let provider = ConfigStore.load().customProvider(withID: id) {
                editor.populate(with: provider)
            }
        case .addCustom:
            editor.startNew()
        case .selection(.builtin):
            break
        }
        mode = ProviderEditorMode(choice: choice)
    }
}

#Preview {
    SettingsView()
}
