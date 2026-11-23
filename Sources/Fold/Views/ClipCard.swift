import SwiftUI

struct ClipCard: View {
    let clip: Clip
    let selected: Bool
    let fileURL: () -> URL?
    @State private var representedURL: URL?
    @State private var fileIcon: NSImage?
    @State private var appIcon: NSImage?
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    private var title: String {
        if clip.kind == .files && clip.detail == "1 file" {
            return representedURL?.hasDirectoryPath == true ? "Folder" : "File"
        }
        return clip.kind.title
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(clip.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.system(size: 11, weight: .medium)).opacity(0.9)
                }
                Spacer(minLength: 0)
                if !clip.boards.isEmpty { Image(systemName: "pin.fill").font(.caption) }
                if let appIcon {
                    Image(nsImage: appIcon).resizable().interpolation(.high).frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-7)).offset(x: 3)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: clip.kind.symbol).font(.system(size: 31, weight: .semibold))
                        .opacity(0.65).padding(.trailing, 9)
                }
            }
            .padding(.leading, 13).frame(height: 49).clipped()
            .foregroundStyle(.white).background(clip.kind.headerColor.gradient)

            preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            if clip.kind != .image && clip.kind != .color && clip.kind != .link {
                Text(title == "Folder" ? "1 folder" : clip.detail).lineLimit(1).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 9)
            }
        }
        .background(scheme == .dark ? Color(white: 0.085) : Color(white: 0.995))
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(hovering ? 0.2 : 0.08)))
        .overlay { if selected { shape.inset(by: -2).strokeBorder(Color.accentColor, lineWidth: 3) } }
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .contentShape(shape).onHover { hovering = $0 }
        .task(id: clip.id) {
            representedURL = fileURL()
            fileIcon = representedURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            let workspace = NSWorkspace.shared
            if let id = clip.sourceBundleID, let url = workspace.urlForApplication(withBundleIdentifier: id) {
                appIcon = workspace.icon(forFile: url.path)
            } else {
                appIcon = workspace.runningApplications.first { $0.localizedName == clip.source }?.icon
            }
        }
        .help("\(title) from \(clip.source) · Space to preview")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clip.kind.title), \(clip.preview.prefix(120)), from \(clip.source)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var preview: some View {
        switch clip.kind {
        case .files:
            VStack(spacing: 8) {
                if let fileIcon { Image(nsImage: fileIcon).resizable().scaledToFit().frame(maxHeight: 85) }
                else { Image(systemName: "doc.on.doc").font(.largeTitle).foregroundStyle(.secondary) }
                Text(clip.preview.split(separator: "\n").first.map(String.init) ?? title)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(2).truncationMode(.middle)
            }.multilineTextAlignment(.center).padding(12)
        case .image:
            if let data = clip.thumbnail, let image = NSImage(data: data) {
                GeometryReader { geo in
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
            } else { Image(systemName: "photo").font(.largeTitle) }
        case .color:
            ZStack {
                clip.swatch
                Text(clip.preview).font(.system(.title3, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 5).background(.regularMaterial, in: Capsule())
            }
        case .link:
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "arrow.up.right.circle.fill").font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(clip.kind.headerColor)
                Text(clip.detail).font(.system(size: 18, weight: .semibold)).lineLimit(2)
                Text(clip.preview).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
        case .text, .code:
            Text(String(clip.preview.prefix(900)))
                .font(clip.kind == .code ? .system(size: 13, design: .monospaced) : .system(size: 15))
                .lineSpacing(2).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12).clipped()
        }
    }
}
