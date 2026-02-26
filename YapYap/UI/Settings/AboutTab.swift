import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)

            // Creature with glow halo
            ZStack {
                RadialGradient(
                    colors: [.ypLavender.opacity(0.3), .clear],
                    center: .center, startRadius: 0, endRadius: 60
                )
                .frame(width: 120, height: 120)
                .blur(radius: 20)
                CreatureView(state: .recording, size: 80, showSmile: true)
                    .frame(width: 80, height: 80)
            }
            .padding(.bottom, 14)

            Text("yapyap")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.ypText1)

            Text("Version 0.1.0 (Build 42)")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.top, 2)

            Text("you yap. it writes.")
                .font(.custom("Caveat", size: 16))
                .foregroundColor(.ypZzz)
                .padding(.top, 4)
                .padding(.bottom, 20)

            Text("An open-source voice-to-text companion that lives in your menu bar. Completely offline, completely free, completely yours.")
                .font(.system(size: 13))
                .foregroundColor(.ypText3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 340)
                .padding(.bottom, 20)

            // Buttons
            HStack(spacing: 10) {
                linkButton("GitHub")
                linkButton("Website")
                linkButton("License")
            }
            .padding(.bottom, 20)

            Text("MIT Licensed · Made with 💜 and too much coffee")
                .font(.system(size: 11))
                .foregroundColor(.ypText4)
        }
        .frame(maxWidth: .infinity)
    }

    private func linkButton(_ title: String) -> some View {
        Button(action: {}) {
            Text(title)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.ypText2)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
