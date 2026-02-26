// GlassComponents.swift — Liquid glass design primitives
import SwiftUI

// MARK: - AmbientGlowBackground

struct AmbientGlowBackground: View {
    struct GlowLayer {
        let color: Color
        let x: CGFloat  // 0-1 relative
        let y: CGFloat
        let radius: CGFloat
    }
    let layers: [GlowLayer]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "2A2540")
                ForEach(layers.indices, id: \.self) { i in
                    RadialGradient(
                        colors: [layers[i].color.opacity(0.55), .clear],
                        center: .init(x: layers[i].x, y: layers[i].y),
                        startRadius: 0,
                        endRadius: layers[i].radius
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Presets

    static let onboardingWelcome: [GlowLayer] = [
        GlowLayer(color: .ypLavender, x: 0.5, y: 0.3, radius: 280),
        GlowLayer(color: .ypZzz, x: 0.8, y: 0.8, radius: 200)
    ]
    static let onboardingMic: [GlowLayer] = [
        GlowLayer(color: .ypWarm, x: 0.3, y: 0.4, radius: 260),
        GlowLayer(color: .ypLavender, x: 0.7, y: 0.7, radius: 180)
    ]
    static let onboardingAccess: [GlowLayer] = [
        GlowLayer(color: .ypLavender, x: 0.6, y: 0.35, radius: 270),
        GlowLayer(color: .ypMint, x: 0.2, y: 0.75, radius: 190)
    ]
    static let onboardingModels: [GlowLayer] = [
        GlowLayer(color: .ypZzz, x: 0.5, y: 0.5, radius: 300)
    ]
    static let onboardingLoading: [GlowLayer] = [
        GlowLayer(color: .ypLavender, x: 0.5, y: 0.4, radius: 320)
    ]
    static let onboardingDone: [GlowLayer] = [
        GlowLayer(color: .ypMint, x: 0.5, y: 0.3, radius: 250),
        GlowLayer(color: .ypLavender, x: 0.3, y: 0.7, radius: 200)
    ]
    static let settings: [GlowLayer] = [
        GlowLayer(color: .ypLavender, x: 0.15, y: 0.5, radius: 350),
        GlowLayer(color: .ypZzz, x: 0.85, y: 0.3, radius: 250)
    ]
}

// MARK: - GlassPanel ViewModifier

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tint: Color = .white
    var tintOpacity: Double = 0.10

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(hex: "352F50"))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(tint.opacity(tintOpacity))
                    // Specular highlight — thin white line at top
                    VStack {
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        Spacer()
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 16, tint: Color = .white, tintOpacity: Double = 0.10) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint, tintOpacity: tintOpacity))
    }
}

// MARK: - GlassPillButton

struct GlassPillButton: View {
    let label: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(isDisabled ? .white.opacity(0.4) : .white.opacity(0.95))
                .padding(.horizontal, 28)
                .padding(.vertical, 11)
                .background {
                    if isDisabled {
                        Capsule().fill(Color.white.opacity(0.08))
                    } else {
                        ZStack {
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color(hex: "C4B8E8"), Color(hex: "8B7CC8")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                            // Specular
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .top, endPoint: .center
                                ))
                        }
                    }
                }
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - GlassSecondaryButton

struct GlassSecondaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - OnboardingProgressBar

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var progress: Double { Double(current + 1) / Double(total) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1)).frame(height: 3)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(hex: "C4B8E8"), Color(hex: "7EC8A0")],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * progress, height: 3)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - GlassRowStyle ViewModifier

struct GlassRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "352F50")))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

extension View {
    func glassRow() -> some View { modifier(GlassRowStyle()) }
}
