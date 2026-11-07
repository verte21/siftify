import AppKit
import SwiftUI

struct GlassWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct BehindWindowBlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

struct LivingAuroraBackdrop: View {
    let stage: FlowStage
    var isDropTargeted: Bool = false

    private var isEnergetic: Bool {
        if case .scanning = stage { return true }
        return isDropTargeted
    }

    private var paletteColors: (Color, Color, Color, Color) {
        switch stage {
        case .setupModel:
            return (
                Color(red: 0.34, green: 0.42, blue: 0.96),
                Color(red: 0.14, green: 0.72, blue: 0.88),
                Color(red: 0.56, green: 0.34, blue: 0.92),
                Color(red: 0.16, green: 0.64, blue: 0.60)
            )
        case .pickFolder:
            if isDropTargeted {
                return (
                    Color(red: 0.16, green: 0.78, blue: 0.94),
                    Color(red: 0.38, green: 0.48, blue: 0.98),
                    Color(red: 0.18, green: 0.82, blue: 0.62),
                    Color(red: 0.62, green: 0.40, blue: 0.96)
                )
            }
            return (
                Color(red: 0.28, green: 0.38, blue: 0.92),
                Color(red: 0.12, green: 0.66, blue: 0.84),
                Color(red: 0.50, green: 0.30, blue: 0.86),
                Color(red: 0.12, green: 0.58, blue: 0.62)
            )
        case .scanning:
            return (
                Color(red: 0.14, green: 0.78, blue: 0.92),
                Color(red: 0.44, green: 0.40, blue: 0.98),
                Color(red: 0.16, green: 0.84, blue: 0.64),
                Color(red: 0.76, green: 0.34, blue: 0.88)
            )
        case .review:
            return (
                Color(red: 0.14, green: 0.70, blue: 0.56),
                Color(red: 0.28, green: 0.44, blue: 0.94),
                Color(red: 0.14, green: 0.68, blue: 0.86),
                Color(red: 0.48, green: 0.36, blue: 0.88)
            )
        case .completed:
            return (
                Color(red: 0.13, green: 0.78, blue: 0.54),
                Color(red: 0.16, green: 0.72, blue: 0.78),
                Color(red: 0.32, green: 0.52, blue: 0.95),
                Color(red: 0.24, green: 0.82, blue: 0.62)
            )
        }
    }

    var body: some View {
        ZStack {
            BehindWindowBlurView(material: .underWindowBackground)

            Color(red: 0.045, green: 0.06, blue: 0.115)
                .opacity(0.84)

            TimelineView(.animation(minimumInterval: isEnergetic ? (1.0 / 60.0) : (1.0 / 24.0))) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let speed = isEnergetic ? 0.85 : 0.28
                let (c1, c2, c3, c4) = paletteColors

                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let radius = max(w, h) * 0.56

                    let p1 = CGPoint(
                        x: w * (0.24 + 0.14 * sin(t * speed * 0.9)),
                        y: h * (0.26 + 0.12 * cos(t * speed * 0.7))
                    )
                    let p2 = CGPoint(
                        x: w * (0.78 + 0.13 * cos(t * speed * 0.8 + 1.1)),
                        y: h * (0.30 + 0.15 * sin(t * speed * 0.65 + 0.5))
                    )
                    let p3 = CGPoint(
                        x: w * (0.64 + 0.16 * sin(t * speed * 0.72 + 2.4)),
                        y: h * (0.78 + 0.12 * cos(t * speed * 0.85 + 1.7))
                    )
                    let p4 = CGPoint(
                        x: w * (0.22 + 0.12 * cos(t * speed * 0.6 + 3.1)),
                        y: h * (0.76 + 0.11 * sin(t * speed * 0.78 + 2.0))
                    )

                    let alphaBoost = isEnergetic ? 0.30 : 0.22
                    drawGlowOrb(in: &context, center: p1, radius: radius, color: c1, opacity: alphaBoost)
                    drawGlowOrb(in: &context, center: p2, radius: radius * 0.92, color: c2, opacity: alphaBoost * 0.92)
                    drawGlowOrb(in: &context, center: p3, radius: radius * 0.88, color: c3, opacity: alphaBoost * 0.84)
                    drawGlowOrb(in: &context, center: p4, radius: radius * 0.78, color: c4, opacity: alphaBoost * 0.76)
                }
            }
            .animation(.easeInOut(duration: 0.75), value: stage)
            .animation(.easeInOut(duration: 0.35), value: isDropTargeted)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.055),
                    Color.clear,
                    Color.black.opacity(0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func drawGlowOrb(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        opacity: Double
    ) {
        let gradient = Gradient(stops: [
            .init(color: color.opacity(opacity), location: 0.0),
            .init(color: color.opacity(opacity * 0.42), location: 0.45),
            .init(color: .clear, location: 1.0)
        ])
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
        )
    }
}

struct GlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color = .white
    var tintOpacity: Double = 0.03
    var borderOpacity: Double = 0.28
    var isHighlighted: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(isHighlighted ? 0.075 : 0.042))
                    shape.fill(tint.opacity(isHighlighted ? tintOpacity * 1.9 : tintOpacity))
                }
                .shadow(color: Color.black.opacity(0.26), radius: 20, x: 0, y: 10)
                .shadow(color: isHighlighted ? tint.opacity(0.22) : .clear, radius: 18, x: 0, y: 4)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHighlighted ? borderOpacity * 1.45 : borderOpacity),
                            Color.white.opacity(0.06),
                            tint.opacity(isHighlighted ? 0.42 : 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isHighlighted ? 1.35 : 1.0
                )
            }
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = 22,
        tint: Color = .white,
        tintOpacity: Double = 0.03,
        borderOpacity: Double = 0.28,
        isHighlighted: Bool = false
    ) -> some View {
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                tintOpacity: tintOpacity,
                borderOpacity: borderOpacity,
                isHighlighted: isHighlighted
            )
        )
    }
}

struct GlowActionButtonStyle: ButtonStyle {
    var accent: Color = Color(red: 0.24, green: 0.56, blue: 0.98)
    var secondaryAccent: Color = Color(red: 0.14, green: 0.78, blue: 0.72)

    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(.white)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, secondaryAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.28 : 0.18),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .shadow(color: accent.opacity(isHovered ? 0.50 : 0.34), radius: isHovered ? 20 : 13, x: 0, y: 6)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
            .scaleEffect(pressed ? 0.965 : (isHovered ? 1.022 : 1.0))
            .animation(.spring(response: 0.28, dampingFraction: 0.74), value: pressed)
            .animation(.spring(response: 0.30, dampingFraction: 0.76), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct TranslucentGlassButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 999
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(.white.opacity(0.92))
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(isHovered ? 0.12 : 0.065))
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovered ? 0.42 : 0.25),
                            Color.white.opacity(0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
            }
            .scaleEffect(pressed ? 0.97 : (isHovered ? 1.018 : 1.0))
            .animation(.spring(response: 0.26, dampingFraction: 0.76), value: pressed)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct ScanningLightSweep: View {
    var accent: Color = Color(red: 0.20, green: 0.82, blue: 0.96)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t * 0.72).truncatingRemainder(dividingBy: 1.0))
            GeometryReader { geo in
                let w = geo.size.width
                let offset = -w * 0.65 + phase * (w * 2.3)
                LinearGradient(
                    colors: [
                        .clear,
                        accent.opacity(0.18),
                        Color.white.opacity(0.22),
                        accent.opacity(0.14),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: w * 0.55)
                .rotationEffect(.degrees(14))
                .offset(x: offset)
            }
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

struct StackedFileIconsView: View {
    let paths: [String]
    var iconSize: CGFloat = 30

    var body: some View {
        let slice = Array(paths.prefix(4))
        HStack(spacing: -iconSize * 0.34) {
            ForEach(Array(slice.enumerated()), id: \.offset) { idx, path in
                let angle = Double(idx - (slice.count - 1) / 2) * 5.0
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                            )
                    )
                    .rotationEffect(.degrees(angle))
                    .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 2)
                    .zIndex(Double(slice.count - idx))
            }
        }
    }
}

struct CelebrationBurstView: View {
    @State private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate

    private struct Mote {
        let angle: Double
        let speed: Double
        let size: CGFloat
        let hueIndex: Int
    }

    private static let motes: [Mote] = (0..<28).map { i in
        let baseAngle = (Double(i) / 28.0) * (.pi * 2.0) + Double(i % 3) * 0.11
        let speed = 68.0 + Double((i * 37) % 95)
        let size = CGFloat(4 + (i % 4) * 2)
        return Mote(angle: baseAngle, speed: speed, size: size, hueIndex: i % 4)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - startTime)
            Canvas { context, size in
                guard elapsed < 2.6 else { return }
                let progress = elapsed / 2.6
                let fade = pow(max(0, 1.0 - progress), 1.6)
                let decel = 1.0 - pow(1.0 - min(1.0, elapsed / 1.8), 2.6)
                let center = CGPoint(x: size.width / 2, y: size.height * 0.34)

                let palette: [Color] = [
                    Color(red: 0.22, green: 0.92, blue: 0.66),
                    Color(red: 0.26, green: 0.80, blue: 0.98),
                    Color(red: 0.98, green: 0.84, blue: 0.38),
                    Color(red: 0.68, green: 0.56, blue: 0.98)
                ]

                for m in Self.motes {
                    let dist = m.speed * decel
                    let x = center.x + CGFloat(cos(m.angle) * dist)
                    let y = center.y + CGFloat(sin(m.angle) * dist - elapsed * 14.0)
                    let rect = CGRect(x: x - m.size / 2, y: y - m.size / 2, width: m.size, height: m.size)
                    let c = palette[m.hueIndex].opacity(fade * 0.85)
                    context.fill(Path(ellipseIn: rect), with: .color(c))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startTime = Date().timeIntervalSinceReferenceDate
        }
    }
}
