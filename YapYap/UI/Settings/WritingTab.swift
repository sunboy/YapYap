import SwiftUI

/// Combined writing settings tab — merges language/formality/cleanup settings
/// with per-app style customization into a single cohesive view.
struct WritingTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Language, Formality, Cleanup Level
            WritingStyleTab()

            settingsSectionDivider

            // Section 2: Per-App Output Styles
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.ypWarm)
                    Text("App-Specific Styles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.ypText1)
                }
                .padding(.bottom, 4)

                Text("Customize output formatting for different app categories.")
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
                    .padding(.bottom, 20)

                StyleTab()
            }
        }
    }

    private var settingsSectionDivider: some View {
        Rectangle()
            .fill(Color.ypBorderLight)
            .frame(height: 1)
            .padding(.vertical, 28)
    }
}
