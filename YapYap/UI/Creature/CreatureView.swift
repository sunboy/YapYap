import SwiftUI

struct CreatureView: View {
    let state: CreatureState
    let size: CGFloat
    var showSmile: Bool = false

    @State private var breatheScale: CGFloat = 1.0
    @State private var headRotation: Double = 0
    @State private var zOpacity1: Double = 0.2
    @State private var zOpacity2: Double = 0.2
    @State private var zOffset1: CGFloat = 0
    @State private var zOffset2: CGFloat = 0
    @State private var pulseScale1: CGFloat = 1.0
    @State private var pulseOpacity1: Double = 0.5
    @State private var pulseScale2: CGFloat = 1.0
    @State private var pulseOpacity2: Double = 0.5
    @State private var spinRotation: Double = 0

    // Normalized to 42pt base
    private var s: CGFloat { size / 42.0 }

    var body: some View {
        ZStack {
            // Pulse rings (recording)
            if state == .recording {
                RoundedRectangle(cornerRadius: size * 0.43)
                    .stroke(Color.ypWarm, lineWidth: 1.5 * s)
                    .frame(width: size + 8 * s, height: size + 8 * s)
                    .scaleEffect(pulseScale1)
                    .opacity(pulseOpacity1)

                RoundedRectangle(cornerRadius: size * 0.43)
                    .stroke(Color.ypWarm, lineWidth: 1.5 * s)
                    .frame(width: size + 8 * s, height: size + 8 * s)
                    .scaleEffect(pulseScale2)
                    .opacity(pulseOpacity2)
            }

            // Spinner ring (processing)
            if state == .processing {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.ypLavender, lineWidth: 1.5 * s)
                    .frame(width: size + 6 * s, height: size + 6 * s)
                    .rotationEffect(.degrees(spinRotation))
            }

            // Creature body
            Canvas { context, canvasSize in
                drawCreature(context: &context, size: canvasSize)
            }
            .frame(width: size, height: size)
            .scaleEffect(y: state == .sleeping ? breatheScale : 1.0)
            .rotationEffect(.degrees(state == .sleeping ? headRotation : 0))

            // Floating z's (sleeping)
            if state == .sleeping {
                Text("z")
                    .font(.custom("Caveat", size: 6 * s))
                    .foregroundColor(.ypZzz)
                    .opacity(zOpacity1)
                    .offset(x: 7 * s, y: -7 * s)
                    .offset(y: zOffset1)

                Text("z")
                    .font(.custom("Caveat", size: 8 * s))
                    .foregroundColor(.ypZzz)
                    .opacity(zOpacity2)
                    .offset(x: 11 * s, y: -12 * s)
                    .offset(y: zOffset2)
            }
        }
        .frame(width: size + 16 * s, height: size + 16 * s)
        .onAppear { startAnimations() }
        .onChange(of: state) { _, _ in resetAndStartAnimations() }
    }

    private func resetAndStartAnimations() {
        breatheScale = 1.0
        headRotation = 0
        zOpacity1 = 0.2
        zOpacity2 = 0.2
        zOffset1 = 0
        zOffset2 = 0
        pulseScale1 = 1.0
        pulseOpacity1 = 0.5
        pulseScale2 = 1.0
        pulseOpacity2 = 0.5
        spinRotation = 0
        startAnimations()
    }

    private func startAnimations() {
        switch state {
        case .sleeping:
            withAnimation(YPAnimation.breathe) {
                breatheScale = 1.04
            }
            withAnimation(YPAnimation.headDrift) {
                headRotation = 3
            }
            withAnimation(YPAnimation.zFloat) {
                zOpacity1 = 0.75
                zOffset1 = -3
            }
            withAnimation(YPAnimation.zFloat.delay(0.6)) {
                zOpacity2 = 0.75
                zOffset2 = -3
            }

        case .recording:
            withAnimation(YPAnimation.pulseRing) {
                pulseScale1 = 1.3
                pulseOpacity1 = 0
            }
            withAnimation(YPAnimation.pulseRing.delay(0.75)) {
                pulseScale2 = 1.3
                pulseOpacity2 = 0
            }

        case .processing:
            withAnimation(YPAnimation.spin) {
                spinRotation = 360
            }
        }
    }

    // MARK: - Drawing

    private func drawCreature(context: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height) / 42.0

        // Body ellipse — cx=21 cy=30 rx=11 ry=7
        let bodyRect = CGRect(
            x: (21 - 11) * s, y: (30 - 7) * s,
            width: 22 * s, height: 14 * s
        )
        context.fill(Ellipse().path(in: bodyRect), with: .color(.ypLavender))

        // Head circle — cx=19 cy=18 r=9 (offset left!)
        let headRect = CGRect(
            x: (19 - 9) * s, y: (18 - 9) * s,
            width: 18 * s, height: 18 * s
        )
        context.fill(Circle().path(in: headRect), with: .color(.ypLavender))

        // Left ear — cx=13 cy=11 rx=2.2 ry=3
        let leftEar = CGRect(
            x: (13 - 2.2) * s, y: (11 - 3) * s,
            width: 4.4 * s, height: 6 * s
        )
        context.fill(Ellipse().path(in: leftEar), with: .color(.ypLavender))

        // Right ear — cx=25 cy=11 rx=2.2 ry=3
        let rightEar = CGRect(
            x: (25 - 2.2) * s, y: (11 - 3) * s,
            width: 4.4 * s, height: 6 * s
        )
        context.fill(Ellipse().path(in: rightEar), with: .color(.ypLavender))

        // Eyes
        if state == .sleeping {
            drawSleepingEyes(context: &context, s: s)
        } else {
            let eyeY: CGFloat = state == .processing ? 17.5 : 18.5
            let hlY: CGFloat = state == .processing ? 16.8 : 17.8
            drawOpenEyes(context: &context, s: s, eyeY: eyeY, highlightY: hlY)

            // Blush cheeks (recording & processing)
            if state == .recording {
                drawBlush(context: &context, s: s, opacity: 0.4)
            } else if state == .processing {
                drawBlush(context: &context, s: s, opacity: 0.3)
            }
        }

        // Sleeping mouth
        if state == .sleeping {
            let mouthRect = CGRect(
                x: (19 - 1.2) * s, y: (22 - 0.5) * s,
                width: 2.4 * s, height: 1.0 * s
            )
            context.fill(Ellipse().path(in: mouthRect), with: .color(.ypEyeStroke.opacity(0.35)))
        }

        // Processing mouth
        if state == .processing {
            let mouthRect = CGRect(
                x: (19 - 1) * s, y: (22 - 0.6) * s,
                width: 2.0 * s, height: 1.2 * s
            )
            context.fill(Ellipse().path(in: mouthRect), with: .color(.ypEyeStroke.opacity(0.3)))
        }

        // Happy smile (for About tab)
        if showSmile {
            var smilePath = Path()
            smilePath.move(to: CGPoint(x: 17 * s, y: 22.5 * s))
            smilePath.addQuadCurve(
                to: CGPoint(x: 21 * s, y: 22.5 * s),
                control: CGPoint(x: 19 * s, y: 24.5 * s)
            )
            context.stroke(smilePath, with: .color(.ypEyeStroke), lineWidth: 0.8 * s)
        }
    }

    private func drawSleepingEyes(context: inout GraphicsContext, s: CGFloat) {
        // Left eye — M14.5,18.5 Q16,20.2 17.5,18.5
        var leftEye = Path()
        leftEye.move(to: CGPoint(x: 14.5 * s, y: 18.5 * s))
        leftEye.addQuadCurve(
            to: CGPoint(x: 17.5 * s, y: 18.5 * s),
            control: CGPoint(x: 16 * s, y: 20.2 * s)
        )
        context.stroke(leftEye, with: .color(.ypEyeStroke), lineWidth: 1.1 * s)

        // Right eye — M21,18.5 Q22.5,20.2 24,18.5
        var rightEye = Path()
        rightEye.move(to: CGPoint(x: 21 * s, y: 18.5 * s))
        rightEye.addQuadCurve(
            to: CGPoint(x: 24 * s, y: 18.5 * s),
            control: CGPoint(x: 22.5 * s, y: 20.2 * s)
        )
        context.stroke(rightEye, with: .color(.ypEyeStroke), lineWidth: 1.1 * s)
    }

    private func drawOpenEyes(context: inout GraphicsContext, s: CGFloat, eyeY: CGFloat, highlightY: CGFloat) {
        // Left pupil — (16, eyeY) r=2
        let leftPupil = CGRect(
            x: (16 - 2) * s, y: (eyeY - 2) * s,
            width: 4 * s, height: 4 * s
        )
        context.fill(Circle().path(in: leftPupil), with: .color(.ypEyeDark))

        // Right pupil — (22.5, eyeY) r=2
        let rightPupil = CGRect(
            x: (22.5 - 2) * s, y: (eyeY - 2) * s,
            width: 4 * s, height: 4 * s
        )
        context.fill(Circle().path(in: rightPupil), with: .color(.ypEyeDark))

        // Left highlight — (16.5, highlightY) r=.7
        let leftHL = CGRect(
            x: (16.5 - 0.7) * s, y: (highlightY - 0.7) * s,
            width: 1.4 * s, height: 1.4 * s
        )
        context.fill(Circle().path(in: leftHL), with: .color(.white))

        // Right highlight — (23, highlightY) r=.7
        let rightHL = CGRect(
            x: (23 - 0.7) * s, y: (highlightY - 0.7) * s,
            width: 1.4 * s, height: 1.4 * s
        )
        context.fill(Circle().path(in: rightHL), with: .color(.white))
    }

    private func drawBlush(context: inout GraphicsContext, s: CGFloat, opacity: Double) {
        // Left blush — (12.5, 21) rx=2.2 ry=1
        let leftBlush = CGRect(
            x: (12.5 - 2.2) * s, y: (21 - 1) * s,
            width: 4.4 * s, height: 2 * s
        )
        context.fill(Ellipse().path(in: leftBlush), with: .color(.ypBlush.opacity(opacity)))

        // Right blush — (26, 21) rx=2.2 ry=1
        let rightBlush = CGRect(
            x: (26 - 2.2) * s, y: (21 - 1) * s,
            width: 4.4 * s, height: 2 * s
        )
        context.fill(Ellipse().path(in: rightBlush), with: .color(.ypBlush.opacity(opacity)))
    }
}
