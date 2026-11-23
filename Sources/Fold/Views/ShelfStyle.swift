import SwiftUI

struct ShelfMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension ClipKind {
    var headerColor: Color {
        switch self {
        case .text: Color(red: 0.08, green: 0.51, blue: 0.52)
        case .link: Color(red: 0.24, green: 0.36, blue: 0.77)
        case .image: Color(red: 0.72, green: 0.27, blue: 0.42)
        case .files: Color(red: 0.08, green: 0.47, blue: 0.76)
        case .color: Color(red: 0.72, green: 0.36, blue: 0.12)
        case .code: Color(red: 0.47, green: 0.31, blue: 0.72)
        }
    }
    var title: String {
        switch self {
        case .files: "Files"
        default: rawValue.capitalized
        }
    }
}

extension Clip {
    var swatch: Color {
        var hex = String(preview.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        let rgb = UInt32(hex, radix: 16) ?? 0
        return Color(red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

enum ShelfLayout {
    static let margin: CGFloat = 20
    static let gap: CGFloat = 15
    static func columns(_ width: CGFloat) -> Int {
        max(1, Int((width - 2 * margin + gap) / 232))
    }
    static func cardSize(_ width: CGFloat) -> CGFloat {
        (width - 2 * margin - CGFloat(columns(width) - 1) * gap) / CGFloat(columns(width))
    }
}
