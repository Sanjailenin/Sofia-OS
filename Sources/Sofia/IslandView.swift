import SwiftUI
import SofiaCore

struct IslandView: View {
    @ObservedObject var model: IslandModel
    var onTap: () -> Void

    private var active: Bool { model.phase.isActive }
    private var isError: Bool { if case .error = model.phase { return true } else { return false } }
    private var hasText: Bool { !lineText.isEmpty }
    private var reduce: Bool { model.reduceMotion }
    private var lamp: Color { Tok.lamp }
    private var glow: Color {
        switch model.phase { case .listening: return Tok.Ink.crimson.opacity(0.18); case .speaking: return lamp.opacity(0.16); default: return .clear }
    }

    private var size: CGSize {
        let top = model.notchHeight, f = Tok.Radius.shoulder * 2
        guard active else { return CGSize(width: (model.hasNotch ? model.notchWidth : Tok.Size.flatIdleWidth) + f, height: top) }
        return CGSize(width: max(model.notchWidth + Tok.Size.wingsExtra, Tok.Size.minWidth) + f, height: top + (hasText ? Tok.Size.textRow : Tok.Size.bareRow))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(flare: Tok.Radius.shoulder, radius: active ? Tok.Radius.open : Tok.Radius.rest).fill(Tok.Ink.surface)
                    .opacity(active || model.hasNotch ? 1 : 0)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        leftWing.frame(maxWidth: .infinity, alignment: .leading)
                        Spacer().frame(width: model.notchWidth)
                        rightWing.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: model.notchHeight)
                    .padding(.horizontal, Tok.Radius.shoulder + Tok.Space.m)
                    if hasText { line }
                }
                .opacity(active ? 1 : 0)
                .scaleEffect(reduce || active ? 1 : 0.88, anchor: .top)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .shadow(color: active ? glow : .clear, radius: 14, x: 0, y: 5)
            .contentShape(Rectangle())
            .onTapGesture { if active { onTap() } }
            .animation(Tok.Motion.pick(Tok.Motion.open, reduce: reduce), value: model.phase)
            .animation(Tok.Motion.pick(Tok.Motion.text, reduce: reduce), value: hasText)
            .animation(Tok.Motion.pick(Tok.Motion.open, reduce: reduce), value: model.hasNotch)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(model.name), \(model.phaseName)"))
            .accessibilityHint(Text("Activate to cancel"))
            .accessibilityAddTraits(.isButton)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var lineText: String {
        switch model.phase {
        case .error(let m): return m
        case .speaking: return shortLine(model.transcript, max: 60)
        default: return model.transcript
        }
    }
    private var line: some View {
        Text(lineText)
            .font(model.phase == .speaking ? Tok.Text_.serif : Tok.Text_.heard)
            .foregroundStyle(isError ? Tok.Ink.danger : (model.phase == .speaking ? Tok.Ink.paper : Tok.Ink.muted))
            .lineLimit(model.phase == .speaking ? 1 : 2).multilineTextAlignment(.center)
            .id(lineText)
            .transition(.opacity)
            .padding(.horizontal, Tok.Radius.shoulder + Tok.Space.l).padding(.bottom, Tok.Space.m)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var leftWing: some View {
        HStack(spacing: Tok.Space.s) {
            switch model.phase {
            case .listening: MicDot(reduce: reduce); Text("Listening").label()
            case .thinking: LampDot(color: lamp); Text("\(model.name) is working").label()
            case .speaking: LampDot(color: lamp); Text(model.name).label()
            case .error: Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(Tok.Ink.danger); Text("Failed").label()
            case .idle: EmptyView()
            }
            if model.demo && active {
                Text("DEMO").font(Tok.Text_.tag).foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 1.5).background(Capsule().fill(Tok.Ink.brass))
            }
        }
    }

    @ViewBuilder private var rightWing: some View {
        switch model.phase {
        case .listening: Waveform(level: model.level, colors: [Tok.Ink.crimson, Tok.Ink.crimson.opacity(0.7)], reduce: reduce)
        case .speaking: Waveform(level: model.level, colors: [lamp, lamp.opacity(0.7)], reduce: reduce)
        case .thinking: SlowLamp(color: lamp, reduce: reduce)
        case .error, .idle: EmptyView()
        }
    }
}

struct BootRing: View {
    var color: Color, reduce: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { ctx in
            let t = reduce ? 0 : ctx.date.timeIntervalSinceReferenceDate
            let d = Tok.Size.barMax
            ZStack {
                Circle().stroke(color.opacity(0.25), lineWidth: 1).frame(width: d, height: d)
                Circle().trim(from: 0, to: 0.3).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: d, height: d).rotationEffect(.degrees(t * 160))
                Circle().trim(from: 0, to: 0.45).stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).frame(width: d * 0.68, height: d * 0.68).rotationEffect(.degrees(-t * 110 + 90))
                Circle().trim(from: 0, to: 0.2).stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, lineCap: .round)).frame(width: d * 0.4, height: d * 0.4).rotationEffect(.degrees(t * 240 + 200))
                Circle().fill(color).frame(width: 4, height: 4).opacity(reduce ? 0.9 : 0.55 + 0.45 * sin(t * 4)).shadow(color: color.opacity(0.8), radius: 4)
            }
            .frame(width: d + 4, height: d + 4)
        }
    }
}

private extension Text {
    func label() -> some View { self.lineLimit(1).fixedSize(horizontal: true, vertical: false).font(Tok.Text_.label).foregroundStyle(Tok.Ink.paper) }
}

struct IslandShape: Shape {
    var flare: CGFloat
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        let f = flare, rad = max(0, min(radius, (r.height - f) / 2, (r.width - 2 * f) / 2))
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - f, y: r.minY + f), control: CGPoint(x: r.maxX - f, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - f, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - f - rad, y: r.maxY), control: CGPoint(x: r.maxX - f, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + f + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX + f, y: r.maxY - rad), control: CGPoint(x: r.minX + f, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + f, y: r.minY + f))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.minX + f, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct MicDot: View {
    var reduce: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { ctx in
            let t = reduce ? 0 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                if !reduce { Circle().stroke(Tok.Ink.crimson.opacity(1 - t), lineWidth: 1.5).frame(width: 8 + 12 * t, height: 8 + 12 * t) }
                Circle().fill(Tok.Ink.crimson).frame(width: 8, height: 8)
            }.frame(width: 20, height: 20)
        }
    }
}

struct LampDot: View {
    var color: Color
    var body: some View { Circle().fill(color).frame(width: 8, height: 8).frame(width: 20, height: 20) }
}

struct SlowLamp: View {
    var color: Color, reduce: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { ctx in
            let k = reduce ? 0.7 : 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 2 * .pi / Tok.Motion.slowPulse)
            Circle().fill(color).frame(width: 12, height: 12).scaleEffect(0.8 + 0.3 * k).opacity(0.45 + 0.55 * k)
                .shadow(color: color.opacity(0.5 * k), radius: 6)
        }
    }
}

struct Waveform: View {
    var level: Float, colors: [Color], reduce: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { ctx in
            let t = reduce ? 0 : ctx.date.timeIntervalSinceReferenceDate
            let n = Tok.Size.bars
            HStack(spacing: Tok.Size.barGap) {
                ForEach(0..<n, id: \.self) { i in
                    let shape = 1 - abs(Double(i) - Double(n - 1) / 2) / (Double(n) / 2 + 0.5)
                    let wobble = reduce ? 0.8 : 0.5 + 0.5 * abs(sin(t * 7 + Double(i) * 1.1))
                    let h = 3 + CGFloat(max(0.05, Double(level))) * Tok.Size.barMax * CGFloat(shape * wobble + 0.12)
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)).frame(width: Tok.Size.barWidth, height: h)
                }
            }
            .frame(height: Tok.Size.barMax + 4)
        }
    }
}

func shortLine(_ text: String, max: Int) -> String {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count > max else { return t }
    let cut = String(t.prefix(max))
    if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > max / 2 { return String(cut[..<space]) + "…" }
    return cut + "…"
}
