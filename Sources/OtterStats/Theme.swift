import SwiftUI
import OtterStatsCore

/// Otter Swarm palette (otter-swarm-website/css/styles.css).
enum Theme {
    static let bg = Color(hex: 0x070B14)
    static let surface = Color(hex: 0x0D1424)
    static let surfaceRaised = Color(hex: 0x121B2E)
    static let line = Color.white.opacity(0.08)
    static let glass = Color.white.opacity(0.04)
    static let cyan = Color(hex: 0x22D3EE)
    static let teal = Color(hex: 0x14B8A6)
    static let amber = Color(hex: 0xF59E0B)
    static let text = Color(hex: 0xE8EEF8)
    static let muted = Color(hex: 0x8B9BB4)
    static let ok = Color(hex: 0x34D399)
    static let fail = Color(hex: 0xF87171)
    static let warn = Color(hex: 0xFBBF24)
    static let violet = Color(hex: 0xA78BFA)
    static let pink = Color(hex: 0xF472B6)

    static let gradient = LinearGradient(colors: [cyan, teal], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func color(for bucket: AgentBucket) -> Color {
        switch bucket {
        case .lead: return cyan
        case .otter: return teal
        case .subagent: return violet
        case .housekeeping: return amber
        case .unknown: return fail
        }
    }

    static let seriesPalette: [Color] = [cyan, teal, violet, amber, pink, ok, warn, Color(hex: 0x60A5FA), Color(hex: 0xFB923C), Color(hex: 0xA3E635)]

    static func series(_ index: Int) -> Color { seriesPalette[index % seriesPalette.count] }

    static let display = Font.system(.title2, design: .rounded).weight(.bold)
    static let mono = Font.system(.caption, design: .monospaced)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct Panel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            content
        }
        .padding(16)
        .background(Theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }
}

struct KPI: View {
    let label: String
    let value: String
    var sub: String? = nil
    var accent: Color = Theme.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(accent)
            if let sub {
                Text(sub).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}

struct ShareBar: View {
    let segments: [(Color, Double)]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(seg.0)
                        .frame(width: max(0, geo.size.width * seg.1 - 1))
                }
            }
        }
        .frame(height: height)
        .background(Theme.line, in: RoundedRectangle(cornerRadius: 3))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct Chip: View {
    let text: String
    var color: Color = Theme.cyan
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.caption).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35)))
    }
}

struct PillToggle: View {
    @Binding var selection: String
    let options: [(String, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { opt in
                let on = opt.0 == selection
                Button { selection = opt.0 } label: {
                    Text(opt.1)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(on ? Theme.bg : Theme.muted)
                        .background(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.clear), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
    }
}

struct RowBar: View {
    let label: String
    let value: String
    let share: Double
    var color: Color = Theme.cyan
    var detail: String? = nil
    var selected = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label).font(.callout).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    if let detail { Text(detail).font(Theme.mono).foregroundStyle(Theme.muted) }
                    Text(value).font(.callout.monospacedDigit()).foregroundStyle(Theme.text)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.line)
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: max(2, geo.size.width * min(1, share)))
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
