import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ClipPreview: View {
    let clip: Clip
    let load: () -> Payload?
    @State private var text = ""
    @State private var image: NSImage?
    @State private var files: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .accessibilityLabel(clip.listTitle)
                } else if !files.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(files.enumerated()), id: \.offset) { _, url in
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable().frame(width: 40, height: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(url.lastPathComponent).fontWeight(.medium)
                                        Text(url.deletingLastPathComponent().path)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if clip.kind == .color {
                    RoundedRectangle(cornerRadius: 10).fill(clip.swatch)
                } else {
                    ScrollView {
                        Text(text.isEmpty ? clip.preview : text)
                            .font(clip.kind == .code ? .body.monospaced() : .body)
                            .lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(clip.listTitle).font(.title3.weight(.semibold)).lineLimit(1)
            HStack(spacing: 5) {
                Text(clip.source)
                Text("·")
                Text(clip.detail)
                Text("·")
                Text(clip.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
            }.font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
        .task(id: clip.id) {
            guard let payload = load(), let first = payload.items.first else { return }
            switch clip.kind {
            case .image:
                let data = first["public.png"] ?? first["public.jpeg"] ?? first["public.tiff"] ?? clip.thumbnail
                image = data.flatMap(NSImage.init(data:))
            case .files:
                files = payload.items.compactMap { $0["public.file-url"].flatMap { URL(dataRepresentation: $0, relativeTo: nil) } }
                guard files.count == 1, let url = files.first, !url.hasDirectoryPath,
                      let type = UTType(filenameExtension: url.pathExtension),
                      type.conforms(to: .image) || type.conforms(to: .pdf) else { return }
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 640, height: 400),
                                                           scale: 2, representationTypes: .thumbnail)
                let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                if !Task.isCancelled { image = thumbnail?.nsImage }
            default:
                if let data = first[NSPasteboard.PasteboardType.string.rawValue],
                   let decoded = String(data: data, encoding: .utf8) {
                    text = decoded
                }
            }
        }
    }
}
