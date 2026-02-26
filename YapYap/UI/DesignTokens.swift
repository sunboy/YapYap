// DesignTokens.swift — All colors, fonts, and animation constants
// Matches the HTML mockup CSS variables exactly
import SwiftUI

extension Color {
    // Use hex init helper at bottom
    
    // Backgrounds
    static let ypBg = Color(hex: "2A2540")                     // --bg
    static let ypBg2 = Color.white.opacity(0.05)                // --card
    static let ypBg3 = Color(hex: "322D4A").opacity(0.97)       // --bg3 popover bg
    static let ypBg4 = Color(hex: "221E36").opacity(0.98)       // --bg4 sidebar bg
    static let ypCard = Color.white.opacity(0.10)               // --card
    static let ypCard2 = Color.white.opacity(0.14)              // --card2
    static let ypInput = Color.white.opacity(0.12)              // --inp

    // Creature & Accent
    static let ypLavender = Color(hex: "C4B8E8")               // --c primary
    static let ypWarm = Color(hex: "F4A261")                    // --w warm orange
    static let ypMint = Color(hex: "7EC8A0")                    // --m mint green
    static let ypZzz = Color(hex: "8B8FC7")                     // --z sleeping
    static let ypBlush = Color(hex: "E8A0B4")                   // --ch blush cheeks
    static let ypRed = Color(hex: "E85D5D")                     // --r errors

    // Text — fully opaque hex values for reliable contrast on dark bg
    static let ypText1 = Color(hex: "F2EEFF")                   // --t1 primary (near white, lavender tint)
    static let ypText2 = Color(hex: "C8BEE8")                   // --t2 secondary
    static let ypText3 = Color(hex: "9A90BC")                   // --t3 tertiary
    static let ypText4 = Color(hex: "5E5880")                   // --t4 disabled

    // Borders
    static let ypBorder = Color.white.opacity(0.12)             // --b
    static let ypBorderLight = Color.white.opacity(0.08)        // --bl
    static let ypBorderFocus = Color(hex: "C4B8E8").opacity(0.5) // --bf

    // Semantic pills
    static let ypPillLavender = Color(hex: "C4B8E8").opacity(0.15) // --cd
    static let ypPillWarm = Color(hex: "F4A261").opacity(0.12)     // --wd
    static let ypPillMint = Color(hex: "7EC8A0").opacity(0.10)     // --md
    static let ypPillRed = Color(hex: "E85D5D").opacity(0.10)      // --rd
    static let ypPillZzz = Color(hex: "8B8FC7").opacity(0.12)

    // Floating bar
    static let ypFloatingBg = Color(red: 20/255, green: 18/255, blue: 28/255).opacity(0.92)
    static let ypFloatingBorderActive = Color(hex: "F4A261").opacity(0.12)
    static let ypFloatingGlow = Color(hex: "F4A261").opacity(0.04)

    // Glass surfaces
    static let ypGlassFill     = Color.white.opacity(0.06)
    static let ypGlassBorder   = Color.white.opacity(0.14)
    static let ypGlassSpecular = Color.white.opacity(0.18)

    // Sidebar glass
    static let ypSidebarBg           = Color(hex: "0A0812").opacity(0.7)
    static let ypSidebarActive       = Color.ypLavender.opacity(0.15)
    static let ypSidebarActiveBorder = Color.ypLavender.opacity(0.35)

    // Creature internals
    static let ypEyeDark = Color(hex: "2A2040")
    static let ypEyeStroke = Color(hex: "6B5E8A")

    // Creature accessories (recording state)
    static let ypHeadphoneBand = Color(hex: "7B6FA0")
    static let ypHeadphoneCup = Color(hex: "F4A261")       // same as ypWarm
    static let ypHeadphoneCupInner = Color(hex: "E8914E")
    static let ypNotepadPaper = Color.white
    static let ypNotepadBinding = Color(hex: "E8914E")
    static let ypNotepadLines = Color(hex: "D0D0D0")
    static let ypPenBarrel = Color(hex: "F4A261")
    static let ypPenGrip = Color(hex: "E8914E")
    static let ypPenTip = Color(hex: "2A2040")

    // Creature accessories (processing state)
    static let ypThinkingDot = Color(hex: "C4B8E8")        // same as ypLavender
}

// MARK: - Hex Color Init
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
extension Font {
    static let ypTitle = Font.system(size: 28, weight: .bold)
    static let ypHeading = Font.system(size: 16, weight: .semibold)
    static let ypBody = Font.system(size: 13, weight: .regular)
    static let ypCaption = Font.system(size: 11, weight: .medium)
    static let ypMicro = Font.system(size: 10, weight: .semibold)
    static let ypMono = Font.system(size: 11, design: .monospaced)
    static let ypSmallMono = Font.system(size: 10, design: .monospaced)
    static let ypHandwritten = Font.custom("Caveat", size: 14)
    static let ypHandwrittenLarge = Font.custom("Caveat", size: 16)

    // Rounded heading variants (liquid glass redesign)
    static let ypDisplayRounded  = Font.system(size: 26, weight: .bold, design: .rounded)
    static let ypHeadingRounded  = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let ypSubheadRounded  = Font.system(size: 14, weight: .medium, design: .rounded)

    // Settings labels
    static let ypSectionLabel = Font.system(size: 9, weight: .semibold)
    static let ypFormLabel = Font.system(size: 11, weight: .semibold)
    static let ypFormDesc = Font.system(size: 12, weight: .regular)
    static let ypNavItem = Font.system(size: 12.5, weight: .regular)
}

// MARK: - Animation Constants
struct YPAnimation {
    static let breathe = Animation.easeInOut(duration: 3.5).repeatForever(autoreverses: true)
    static let headDrift = Animation.easeInOut(duration: 3.5).repeatForever(autoreverses: true)
    static let zFloat = Animation.easeInOut(duration: 2.8).repeatForever(autoreverses: true)
    static let pulseRing = Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false)
    static let spin = Animation.linear(duration: 0.8).repeatForever(autoreverses: false)
    static let barExpand = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let waveformUpdate: TimeInterval = 1.0 / 30.0 // 30fps
}

// MARK: - Custom Toggle Style (36x20 capsule)
struct YPToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color.ypMint : Color.white.opacity(0.12))
                    .frame(width: 36, height: 20)

                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}
