import SwiftUI

/// Settings content shared between the macOS Settings scene and the iOS settings
/// sheet. Currently hosts the provider picker; the custom-provider editor is
/// added here in a later task.
struct SettingsView: View {
    @ObservedObject private var providerSelection = ProviderSelection.shared

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $providerSelection.selection) {
                    ForEach(providerSelection.pickerItems) { item in
                        Text(item.label).tag(item.selection)
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 380, height: 160)
        #endif
    }
}

#Preview {
    SettingsView()
}
