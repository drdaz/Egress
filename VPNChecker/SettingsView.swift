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

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $choice) {
                    ForEach(choiceItems) { item in
                        Text(item.label).tag(item.choice)
                    }
                }
            }

            if mode != .hidden {
                CustomProviderEditorView(editor: editor) { draft in
                    guard (try? CustomProviderSaver.save(draft)) != nil else { return }
                    // Adopt the saved id so a subsequent Save updates this provider
                    // instead of creating a duplicate.
                    editor.startEditing(draft)
                    // Auto-select the just-saved provider: setting `choice` cascades
                    // through onChange to update the active selection and editor mode.
                    choice = .selection(.custom(draft.id))
                }
            }
        }
        .onAppear { syncEditor(to: choice) }
        .onChange(of: choice) { _, newChoice in
            if case .selection(let selection) = newChoice {
                providerSelection.select(selection)
            }
            syncEditor(to: newChoice)
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 380, height: 320)
        #endif
    }

    /// Configure the editor's contents to match the current choice (without
    /// mutating the active selection).
    private func syncEditor(to choice: ProviderChoice) {
        switch choice {
        case .selection(.custom(let id)):
            if let provider = ConfigStore.load().customProvider(withID: id) {
                editor.startEditing(provider)
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
