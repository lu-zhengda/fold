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
    var title: String {
        switch self {
        case .files: "Files"
        default: rawValue.capitalized
        }
    }
}

extension Clip {
    var listTitle: String {
        if kind == .link && !detail.isEmpty { return detail }
        return preview.split(whereSeparator: \.isNewline).first.map { String($0.prefix(160)) } ?? kind.title
    }

    var swatch: Color {
        var hex = String(preview.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        let rgb = UInt32(hex, radix: 16) ?? 0
        return Color(red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
