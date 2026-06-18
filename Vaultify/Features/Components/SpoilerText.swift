import SwiftUI
import UIKit

/// Concealed secret display: the value is covered by a shimmering dust cloud
/// (Telegram-style). Reveal/conceal is controlled by the parent (the detail
/// row's "•••" menu) — this view just renders the hidden state.
struct SpoilerText: View {
    let text: String
    var font: Font = .vaultCode()

    var body: some View {
        Text(text)
            .font(font)
            .opacity(0.0001) // keep layout; dust covers it
            .overlay { DustView().padding(.horizontal, -3) }
            .accessibilityLabel("Hidden value")
    }
}

private struct DustView: UIViewRepresentable {
    func makeUIView(context: Context) -> DustParticleView { DustParticleView() }
    func updateUIView(_ uiView: DustParticleView, context: Context) {}
}

/// Continuously redrawn field of smoothly-twinkling, drifting dots, driven by a
/// `CADisplayLink` so it animates in any container (incl. `List`/`Form` rows).
final class DustParticleView: UIView {
    private struct Dot { let x: Double; let y: Double; let phase: Double; let speed: Double; let radius: Double }

    private var dots: [Dot] = []
    private var displayLink: CADisplayLink?
    private let start = CACurrentMediaTime()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    @objc private func step() { setNeedsDisplay() }

    override func layoutSubviews() {
        super.layoutSubviews()
        regenerate()
    }

    private func regenerate() {
        let area = Double(bounds.width * bounds.height)
        let count = min(Int(area * 0.35), 900)
        guard count > 0 else { dots = []; return }
        var rng = SplitMix64(seed: 0xA17F2C)
        dots = (0..<count).map { _ in
            Dot(x: rng.unit() * Double(bounds.width),
                y: rng.unit() * Double(bounds.height),
                phase: rng.unit() * 2 * .pi,
                speed: 3.0 + rng.unit() * 5.0,
                radius: 0.5 + rng.unit() * 0.7)
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let time = CACurrentMediaTime() - start
        let base = UIColor.label
        for dot in dots {
            let wave = 0.5 + 0.5 * sin(time * dot.speed + dot.phase)
            let twinkle = 0.15 + 0.85 * wave
            let driftX = sin(time * 1.4 + dot.phase) * 0.7
            let driftY = cos(time * 1.7 + dot.phase) * 0.7
            context.setFillColor(base.withAlphaComponent(twinkle).cgColor)
            context.fillEllipse(in: CGRect(x: dot.x + driftX - dot.radius,
                                           y: dot.y + driftY - dot.radius,
                                           width: dot.radius * 2, height: dot.radius * 2))
        }
    }
}

/// SplitMix64 PRNG — deterministic so the dust layout is stable across frames.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}
