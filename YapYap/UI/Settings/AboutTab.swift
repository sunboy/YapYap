import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)

            // Creature with smile
            CreatureView(state: .recording, size: 72, showSmile: true)
                .frame(width: 72, height: 72)
                .padding(.bottom, 14)

            Text("yapyap")
                .font(.system(size: 20, weight: .bold))
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
                .font(.system(size: 12))
                .foregroundColor(.ypText2)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(Color.ypCard)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ypBorder, lineWidth: 1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
