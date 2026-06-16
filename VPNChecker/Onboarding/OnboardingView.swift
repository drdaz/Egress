import SwiftUI

/// First-launch screen shown over the main view: a short introduction to what
/// the app does, followed by the live `SettingsView` so a new user can pick
/// their egress provider before they start. Dismissed via "Get started", which
/// marks onboarding complete (see `OnboardingGate`).
///
/// The embedded `SettingsView` is the same view used by the real Settings
/// screen, so any selection made here persists through the normal config path —
/// there is no separate onboarding-only settings copy.
struct OnboardingView: View {
    /// Invoked when the user taps "Get started". The caller marks onboarding
    /// complete and dismisses.
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The intro rides along as the Form's first section (see SettingsView's
            // `header`), so it shares the grouped background, insets and scrolling.
            SettingsView(header: AnyView(intro))

            Divider()

            Button(action: onGetStarted) {
                Text("Get started")
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        #if os(macOS)
        .frame(width: 380)
        #endif
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Egress")
                .font(.title2)
                .fontWeight(.bold)
            Text("Know where you're surfacing from — at a glance. Egress confirms you're exiting through the VPN or network you expect, right from a widget.")
                .foregroundStyle(.secondary)
            Text("Pick a VPN provider below, or add a custom egress check for anything that's not listed. Change it any time in Settings.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

#Preview {
    OnboardingView(onGetStarted: {})
}
