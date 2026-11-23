import SwiftUI

struct ClipPreview: View {
    let clip: Clip
    let load: () -> Payload?
    let close: () -> Void
    @State private var text = ""
    @State private var image: NSImage?
    @State private var files: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: clip.kind.symbol).foregroundStyle(clip.kind.headerColor)
                Text(clip.source).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close preview")
            }.padding(13)
            Divider()
            ScrollView {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else if !files.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(files.enumerated()), id: \.offset) { _, url in
                                HStack {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 36, height: 36)
                                    VStack(alignment: .leading) {
                                        Text(url.lastPathComponent).fontWeight(.medium)
                                        Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else if clip.kind == .color {
                        RoundedRectangle(cornerRadius: 9).fill(clip.swatch).frame(height: 125)
                        Text(clip.preview).font(.body.monospaced())
                    } else {
                        Text(text.isEmpty ? clip.preview : text)
                            .font(clip.kind == .code ? .body.monospaced() : .body).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }.frame(maxHeight: 290)
            Divider()
            Text(clip.detail).font(.caption).foregroundStyle(.secondary).padding(8)
        }.frame(width: 410)
        .onExitCommand(perform: close)
        .task(id: clip.id) {
            guard let payload = load(), let first = payload.items.first else { return }
            switch clip.kind {
            case .image:
                let data = first["public.png"] ?? first["public.jpeg"] ?? first["public.tiff"] ?? clip.thumbnail
                image = data.flatMap(NSImage.init(data:))
            case .files:
                files = payload.items.compactMap { $0["public.file-url"].flatMap { URL(dataRepresentation: $0, relativeTo: nil) } }
            default:
                if let data = first[NSPasteboard.PasteboardType.string.rawValue] {
                    text = String(decoding: data, as: UTF8.self)
                }
            }
        }
    }
}
