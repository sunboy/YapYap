import SwiftUI

struct AnalyticsTab: View {
    @State private var weeklyData: [(String, Double)] = [
        ("Mon", 0.35), ("Tue", 0.60), ("Wed", 0.45), ("Thu", 0.80),
        ("Fri", 0.95), ("Sat", 0.55), ("Sun", 0.25)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Yapping Stats")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)
            Text("All data stays on your Mac. Always.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 24)

            // Stats grid
            HStack(spacing: 12) {
                statCard(value: "1,247", label: "TRANSCRIPTIONS", color: .ypLavender)
                statCard(value: "38.2k", label: "WORDS", color: .ypWarm)
                statCard(value: "4.2 hrs", label: "TIME SAVED", color: .ypMint)
            }
            .padding(.bottom, 24)

            // Chart
            VStack(alignment: .leading, spacing: 12) {
                Text("Transcriptions This Week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ypText2)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(weeklyData.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.ypLavender)
                                .opacity(index == weeklyData.count - 1 ? 0.3 : 0.6)
                                .frame(height: max(4, item.1 * 100))

                            Text(item.0)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.ypText4)
                                .textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120)
            }
            .padding(16)
            .background(Color.ypCard)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ypBorderLight, lineWidth: 1))
            .cornerRadius(10)
        }
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.ypText3)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.ypCard)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ypBorderLight, lineWidth: 1))
        .cornerRadius(10)
    }
}
