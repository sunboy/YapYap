import SwiftUI

/// Combined activity tab — shows analytics dashboard and transcription history
/// in a single scrollable view.
struct ActivityTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Stats Dashboard
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.ypMint)
                    Text("This Week")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.ypText1)
                }
                .padding(.bottom, 16)

                AnalyticsTab()
            }

            settingsSectionDivider

            // Section 2: History
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.ypLavender)
                    Text("Recent Transcriptions")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.ypText1)
                }
                .padding(.bottom, 16)

                HistoryTab()
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
