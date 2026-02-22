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
    // Thinking dots (processing)
    @State private var dotScale1: CGFloat = 0.5
    @State private var dotScale2: CGFloat = 0.5
    @State private var dotScale3: CGFloat = 0.5
    @State private var dotOpacity1: Double = 0.3
    @State private var dotOpacity2: Double = 0.3
    @State private var dotOpacity3: Double = 0.3

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

            // Creature body (with recording accessories drawn in Canvas)
            Canvas { context, canvasSize in
                drawCreature(context: &context, size: canvasSize)
            }
            .frame(width: state == .recording ? size * 1.6 : size,
                   height: state == .recording ? size * 1.15 : size)
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

            // Thinking dots (processing) — SwiftUI overlays for animation
            if state == .processing {
                Circle()
                    .fill(Color.ypThinkingDot.opacity(dotOpacity1))
                    .frame(width: 3 * s, height: 3 * s)
                    .scaleEffect(dotScale1)
                    .offset(x: 8 * s, y: -10 * s)

                Circle()
                    .fill(Color.ypThinkingDot.opacity(dotOpacity2))
                    .frame(width: 4.4 * s, height: 4.4 * s)
                    .scaleEffect(dotScale2)
                    .offset(x: 12 * s, y: -15 * s)

                Circle()
                    .fill(Color.ypThinkingDot.opacity(dotOpacity3))
                    .frame(width: 6 * s, height: 6 * s)
                    .scaleEffect(dotScale3)
                    .offset(x: 17 * s, y: -20 * s)
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
        dotScale1 = 0.5
        dotScale2 = 0.5
        dotScale3 = 0.5
        dotOpacity1 = 0.3
        dotOpacity2 = 0.3
        dotOpacity3 = 0.3
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
            // Thinking dots cascade
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                dotScale1 = 1.0
                dotOpacity1 = 0.9
            }
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.3)) {
                dotScale2 = 1.0
                dotOpacity2 = 0.9
            }
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.6)) {
                dotScale3 = 1.0
                dotOpacity3 = 0.9
            }
        }
    }

    // MARK: - Drawing

    private func drawCreature(context: inout GraphicsContext, size: CGSize) {
        if state == .recording {
            // Recording state uses wider canvas to fit accessories
            // Scale factor: creature body occupies ~42 units in left portion
            let s = min(size.width / 67.0, size.height / 48.0)
            let offsetX: CGFloat = 2 * s // slight left margin

            drawCreatureBody(context: &context, s: s, offsetX: offsetX)
            drawHeadphones(context: &context, s: s, offsetX: offsetX)
            drawSmileMouth(context: &context, s: s, offsetX: offsetX)
            drawNotepadAndPen(context: &context, s: s, offsetX: offsetX)
        } else {
            let s = min(size.width, size.height) / 42.0
            drawCreatureBody(context: &context, s: s, offsetX: 0)

            // State-specific mouths
            if state == .sleeping {
                let mouthRect = CGRect(
                    x: (19 - 1.2) * s, y: (22 - 0.5) * s,
                    width: 2.4 * s, height: 1.0 * s
                )
                context.fill(Ellipse().path(in: mouthRect), with: .color(.ypEyeStroke.opacity(0.35)))
            }

            if state == .processing {
                drawHmmMouth(context: &context, s: s, offsetX: 0)
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
    }

    private func drawCreatureBody(context: inout GraphicsContext, s: CGFloat, offsetX: CGFloat) {
        // Body ellipse — cx=21 cy=30 rx=11 ry=7
        let bodyRect = CGRect(
            x: offsetX + (21 - 11) * s, y: (30 - 7) * s,
            width: 22 * s, height: 14 * s
        )
        context.fill(Ellipse().path(in: bodyRect), with: .color(.ypLavender))

        // Head circle — cx=19 cy=18 r=9 (offset left!)
        let headRect = CGRect(
            x: offsetX + (19 - 9) * s, y: (18 - 9) * s,
            width: 18 * s, height: 18 * s
        )
        context.fill(Circle().path(in: headRect), with: .color(.ypLavender))

        // Left ear — cx=13 cy=11 rx=2.2 ry=3
        let leftEar = CGRect(
            x: offsetX + (13 - 2.2) * s, y: (11 - 3) * s,
            width: 4.4 * s, height: 6 * s
        )
        context.fill(Ellipse().path(in: leftEar), with: .color(.ypLavender))

        // Right ear — cx=25 cy=11 rx=2.2 ry=3
        let rightEar = CGRect(
            x: offsetX + (25 - 2.2) * s, y: (11 - 3) * s,
            width: 4.4 * s, height: 6 * s
        )
        context.fill(Ellipse().path(in: rightEar), with: .color(.ypLavender))

        // Eyes
        if state == .sleeping {
            drawSleepingEyes(context: &context, s: s, offsetX: offsetX)
        } else {
            let eyeY: CGFloat = state == .processing ? 17.5 : 18.5
            let hlY: CGFloat = state == .processing ? 16.8 : 17.8
            drawOpenEyes(context: &context, s: s, eyeY: eyeY, highlightY: hlY, offsetX: offsetX)

            // Blush cheeks (recording & processing)
            if state == .recording {
                drawBlush(context: &context, s: s, opacity: 0.4, offsetX: offsetX)
            } else if state == .processing {
                drawBlush(context: &context, s: s, opacity: 0.3, offsetX: offsetX)
            }
        }
    }

    // MARK: - Recording Accessories

    private func drawHeadphones(context: inout GraphicsContext, s: CGFloat, offsetX: CGFloat) {
        // Headband — arc from left cup to right cup over the head
        var headband = Path()
        headband.move(to: CGPoint(x: offsetX + 11 * s, y: 13 * s))
        headband.addQuadCurve(
            to: CGPoint(x: offsetX + 27 * s, y: 13 * s),
            control: CGPoint(x: offsetX + 19 * s, y: 2 * s)
        )
        context.stroke(headband, with: .color(.ypHeadphoneBand), style: StrokeStyle(lineWidth: 2.5 * s, lineCap: .round))

        // Left ear cup — rounded rect
        let leftCupRect = CGRect(x: offsetX + 7 * s, y: 11 * s, width: 5 * s, height: 6.5 * s)
        let leftCupPath = RoundedRectangle(cornerRadius: 1.5 * s).path(in: leftCupRect)
        context.fill(leftCupPath, with: .color(.ypHeadphoneCup))

        // Left inner cup
        let leftInnerRect = CGRect(x: offsetX + 8 * s, y: 12 * s, width: 3 * s, height: 4.5 * s)
        let leftInnerPath = RoundedRectangle(cornerRadius: 1 * s).path(in: leftInnerRect)
        context.fill(leftInnerPath, with: .color(.ypHeadphoneCupInner))

        // Left grille lines
        for i in 0..<3 {
            let lineY = 12.8 * s + CGFloat(i) * 1.3 * s
            var grille = Path()
            grille.move(to: CGPoint(x: offsetX + 8.5 * s, y: lineY))
            grille.addLine(to: CGPoint(x: offsetX + 10.5 * s, y: lineY))
            context.stroke(grille, with: .color(.ypHeadphoneBand.opacity(0.5)), lineWidth: 0.4 * s)
        }

        // Right ear cup — rounded rect
        let rightCupRect = CGRect(x: offsetX + 26 * s, y: 11 * s, width: 5 * s, height: 6.5 * s)
        let rightCupPath = RoundedRectangle(cornerRadius: 1.5 * s).path(in: rightCupRect)
        context.fill(rightCupPath, with: .color(.ypHeadphoneCup))

        // Right inner cup
        let rightInnerRect = CGRect(x: offsetX + 27 * s, y: 12 * s, width: 3 * s, height: 4.5 * s)
        let rightInnerPath = RoundedRectangle(cornerRadius: 1 * s).path(in: rightInnerRect)
        context.fill(rightInnerPath, with: .color(.ypHeadphoneCupInner))

        // Right grille lines
        for i in 0..<3 {
            let lineY = 12.8 * s + CGFloat(i) * 1.3 * s
            var grille = Path()
            grille.move(to: CGPoint(x: offsetX + 27.5 * s, y: lineY))
            grille.addLine(to: CGPoint(x: offsetX + 29.5 * s, y: lineY))
            context.stroke(grille, with: .color(.ypHeadphoneBand.opacity(0.5)), lineWidth: 0.4 * s)
        }
    }

    private func drawSmileMouth(context: inout GraphicsContext, s: CGFloat, offsetX: CGFloat) {
        // Happy smile for recording: M17,22 Q19,24 21,22
        var smilePath = Path()
        smilePath.move(to: CGPoint(x: offsetX + 17 * s, y: 22 * s))
        smilePath.addQuadCurve(
            to: CGPoint(x: offsetX + 21 * s, y: 22 * s),
            control: CGPoint(x: offsetX + 19 * s, y: 24 * s)
        )
        context.stroke(smilePath, with: .color(.ypEyeStroke), lineWidth: 0.8 * s)
    }

    private func drawNotepadAndPen(context: inout GraphicsContext, s: CGFloat, offsetX: CGFloat) {
        // Notepad sits to the bottom-right of the creature body, rotated ~8°
        let noteX = offsetX + 35 * s
        let noteY = 26 * s

        // Apply rotation transform for notepad group
        var notepadContext = context
        let rotationCenter = CGPoint(x: noteX + 4 * s, y: noteY + 5 * s)
        notepadContext.translateBy(x: rotationCenter.x, y: rotationCenter.y)
        notepadContext.rotate(by: .degrees(8))
        notepadContext.translateBy(x: -rotationCenter.x, y: -rotationCenter.y)

        // Paper body
        let paperRect = CGRect(x: noteX, y: noteY, width: 9 * s, height: 10 * s)
        let paperPath = RoundedRectangle(cornerRadius: 0.8 * s).path(in: paperRect)
        notepadContext.fill(paperPath, with: .color(.ypNotepadPaper))

        // Binding strip (left edge)
        let bindingRect = CGRect(x: noteX, y: noteY, width: 2 * s, height: 10 * s)
        notepadContext.fill(Rectangle().path(in: bindingRect), with: .color(.ypNotepadBinding.opacity(0.3)))

        // Binding rings (3 small circles on left edge)
        for i in 0..<3 {
            let ringY = noteY + 2 * s + CGFloat(i) * 3 * s
            let ringRect = CGRect(x: noteX + 0.5 * s, y: ringY, width: 1 * s, height: 1 * s)
            notepadContext.fill(Circle().path(in: ringRect), with: .color(.ypNotepadBinding))
        }

        // Ruled lines
        for i in 0..<4 {
            let lineY = noteY + 2.5 * s + CGFloat(i) * 2 * s
            var linePath = Path()
            linePath.move(to: CGPoint(x: noteX + 2.5 * s, y: lineY))
            linePath.addLine(to: CGPoint(x: noteX + 8 * s, y: lineY))
            notepadContext.stroke(linePath, with: .color(.ypNotepadLines.opacity(0.4)), lineWidth: 0.3 * s)
        }

        // Scribble lines on notepad (wavy squiggles representing writing)
        for i in 0..<3 {
            let scribbleY = noteY + 2.5 * s + CGFloat(i) * 2 * s
            var scribble = Path()
            scribble.move(to: CGPoint(x: noteX + 3 * s, y: scribbleY))
            scribble.addQuadCurve(
                to: CGPoint(x: noteX + 5 * s, y: scribbleY),
                control: CGPoint(x: noteX + 4 * s, y: scribbleY - 0.5 * s)
            )
            scribble.addQuadCurve(
                to: CGPoint(x: noteX + 7.5 * s, y: scribbleY),
                control: CGPoint(x: noteX + 6.2 * s, y: scribbleY + 0.5 * s)
            )
            notepadContext.stroke(scribble, with: .color(.ypEyeStroke.opacity(0.5)), lineWidth: 0.35 * s)
        }

        // Arm stub extending from body toward notepad
        var armPath = Path()
        armPath.move(to: CGPoint(x: offsetX + 30 * s, y: 30 * s))
        armPath.addQuadCurve(
            to: CGPoint(x: noteX + 1 * s, y: noteY + 4 * s),
            control: CGPoint(x: offsetX + 33 * s, y: 28 * s)
        )
        context.stroke(armPath, with: .color(.ypLavender), style: StrokeStyle(lineWidth: 2.5 * s, lineCap: .round))

        // Tiny hand (ellipse at end of arm)
        let handRect = CGRect(x: noteX - 0.5 * s, y: noteY + 2.5 * s, width: 2.5 * s, height: 2 * s)
        context.fill(Ellipse().path(in: handRect), with: .color(.ypLavender))

        // Pen barrel
        var penPath = Path()
        penPath.move(to: CGPoint(x: noteX + 1 * s, y: noteY + 3 * s))
        penPath.addLine(to: CGPoint(x: noteX + 5 * s, y: noteY + 1 * s))
        context.stroke(penPath, with: .color(.ypPenBarrel), style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round))

        // Pen grip
        let gripRect = CGRect(x: noteX + 1.8 * s, y: noteY + 2 * s, width: 1.5 * s, height: 1.5 * s)
        context.fill(Ellipse().path(in: gripRect), with: .color(.ypPenGrip))

        // Pen tip
        let tipRect = CGRect(x: noteX + 4.5 * s, y: noteY + 0.5 * s, width: 1 * s, height: 1 * s)
        context.fill(Circle().path(in: tipRect), with: .color(.ypPenTip))
    }

    // MARK: - Processing Accessories

    private func drawHmmMouth(context: inout GraphicsContext, s: CGFloat, offsetX: CGFloat) {
        // Small "hmm" mouth: M17.5,21.5 Q19,22.5 20.5,21.5
        var hmmPath = Path()
        hmmPath.move(to: CGPoint(x: offsetX + 17.5 * s, y: 21.5 * s))
        hmmPath.addQuadCurve(
            to: CGPoint(x: offsetX + 20.5 * s, y: 21.5 * s),
            control: CGPoint(x: offsetX + 19 * s, y: 22.8 * s)
        )
        context.stroke(hmmPath, with: .color(.ypEyeStroke.opacity(0.5)), lineWidth: 0.7 * s)
    }

    // MARK: - Eyes

    private func drawSleepingEyes(context: inout GraphicsContext, s: CGFloat, offsetX: CGFloat = 0) {
        // Left eye — M14.5,18.5 Q16,20.2 17.5,18.5
        var leftEye = Path()
        leftEye.move(to: CGPoint(x: offsetX + 14.5 * s, y: 18.5 * s))
        leftEye.addQuadCurve(
            to: CGPoint(x: offsetX + 17.5 * s, y: 18.5 * s),
            control: CGPoint(x: offsetX + 16 * s, y: 20.2 * s)
        )
        context.stroke(leftEye, with: .color(.ypEyeStroke), lineWidth: 1.1 * s)

        // Right eye — M21,18.5 Q22.5,20.2 24,18.5
        var rightEye = Path()
        rightEye.move(to: CGPoint(x: offsetX + 21 * s, y: 18.5 * s))
        rightEye.addQuadCurve(
            to: CGPoint(x: offsetX + 24 * s, y: 18.5 * s),
            control: CGPoint(x: offsetX + 22.5 * s, y: 20.2 * s)
        )
        context.stroke(rightEye, with: .color(.ypEyeStroke), lineWidth: 1.1 * s)
    }

    private func drawOpenEyes(context: inout GraphicsContext, s: CGFloat, eyeY: CGFloat, highlightY: CGFloat, offsetX: CGFloat = 0) {
        // Left pupil — (16, eyeY) r=2
        let leftPupil = CGRect(
            x: offsetX + (16 - 2) * s, y: (eyeY - 2) * s,
            width: 4 * s, height: 4 * s
        )
        context.fill(Circle().path(in: leftPupil), with: .color(.ypEyeDark))

        // Right pupil — (22.5, eyeY) r=2
        let rightPupil = CGRect(
            x: offsetX + (22.5 - 2) * s, y: (eyeY - 2) * s,
            width: 4 * s, height: 4 * s
        )
        context.fill(Circle().path(in: rightPupil), with: .color(.ypEyeDark))

        // Left highlight — (16.5, highlightY) r=.7
        let leftHL = CGRect(
            x: offsetX + (16.5 - 0.7) * s, y: (highlightY - 0.7) * s,
            width: 1.4 * s, height: 1.4 * s
        )
        context.fill(Circle().path(in: leftHL), with: .color(.white))

        // Right highlight — (23, highlightY) r=.7
        let rightHL = CGRect(
            x: offsetX + (23 - 0.7) * s, y: (highlightY - 0.7) * s,
            width: 1.4 * s, height: 1.4 * s
        )
        context.fill(Circle().path(in: rightHL), with: .color(.white))
    }

    private func drawBlush(context: inout GraphicsContext, s: CGFloat, opacity: Double, offsetX: CGFloat = 0) {
        // Left blush — (12.5, 21) rx=2.2 ry=1
        let leftBlush = CGRect(
            x: offsetX + (12.5 - 2.2) * s, y: (21 - 1) * s,
            width: 4.4 * s, height: 2 * s
        )
        context.fill(Ellipse().path(in: leftBlush), with: .color(.ypBlush.opacity(opacity)))

        // Right blush — (26, 21) rx=2.2 ry=1
        let rightBlush = CGRect(
            x: offsetX + (26 - 2.2) * s, y: (21 - 1) * s,
            width: 4.4 * s, height: 2 * s
        )
        context.fill(Ellipse().path(in: rightBlush), with: .color(.ypBlush.opacity(opacity)))
    }
}
