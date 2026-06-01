#if os(macOS)
import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Egress Settings")
                .font(.title)

            Text("Status bar icon shows your VPN connection status")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
#endif
