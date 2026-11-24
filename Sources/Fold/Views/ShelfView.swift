import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    let use: (Clip) -> Void
    let copy: (Clip) -> Void
    let dismiss: () -> Void
    let openSettings: () -> Void
    let enablePaste: () -> Void
    let canPaste: () -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var creatingBoard = false
    @State private var page: Int? = 0
    @State private var boardName = ""
    @State private var confirmClear = false
    @State private var confirmRemoveBoard = false

    private var currentBoard: Board? { store.history.boards.first { $0.id == store.boardID } }
    private var newName: String { boardName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GeometryReader { geometry in
            let clips = store.visible
            let columns = ShelfLayout.columns(geometry.size.width)
            let pages = max(1, (clips.count + columns - 1) / columns)
            let current = min(page ?? 0, pages - 1)
            VStack(spacing: 0) {
                toolbar(clips: clips, current: current, columns: columns, pages: pages)
                    .padding(.horizontal, 20).frame(height: 58)
                if clips.isEmpty {
                    EmptyShelf(searching: !store.query.isEmpty, board: currentBoard != nil, paused: store.paused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    cards(clips, columns: columns, pages: pages, width: geometry.size.width)
                        .padding(.top, 3).padding(.bottom, 17)
                }
                if let notice = store.notice {
                    Text(notice).font(.caption).lineLimit(1).padding(.vertical, 3)
                }
            }
        }
        .background(ShelfMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.15)))
        .onChange(of: store.openCount) { _, _ in page = 0 }
        .onChange(of: store.boardID) { _, _ in store.query = ""; store.selection = nil; page = 0 }
        .onChange(of: store.query) { _, _ in store.selection = nil; page = 0 }
        .alert("Clear unpinned history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear history", role: .destructive) { store.change { $0.clips.removeAll { $0.boards.isEmpty } } }
        } message: { Text("Clips saved to a pinboard will stay in your library.") }
        .alert("Remove this pinboard?", isPresented: $confirmRemoveBoard) {
            Button("Cancel", role: .cancel) {}
            Button("Remove pinboard", role: .destructive) {
                guard let id = store.boardID else { return }
                store.change {
                    $0.boards.removeAll { $0.id == id }
                    for i in $0.clips.indices { $0.clips[i].boards.remove(id) }
                }
                store.boardID = nil
            }
        } message: { Text("Its clips will still be available in History, subject to your history limit.") }
    }

    private func toolbar(clips: [Clip], current: Int, columns: Int, pages: Int) -> some View {
        ZStack {
            HStack(spacing: 7) {
                if pages > 1 {
                    pageButton("Previous page", symbol: "chevron.left", disabled: current == 0) { page = current - 1 }
                }
                Text(clips.isEmpty ? "0 clips" : pages == 1 ? "\(clips.count) \(clips.count == 1 ? "clip" : "clips")" :
                     "\(current * columns + 1)–\(min((current + 1) * columns, clips.count)) of \(clips.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if pages > 1 {
                    pageButton("Next page", symbol: "chevron.right", disabled: current == pages - 1) { page = current + 1 }
                }
                Spacer()
                if store.paused || store.captureDenied || !store.shortcutAvailable {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        .help(store.captureDenied ? "Pasteboard access denied" : store.paused ? "Capture paused" : "Shortcut unavailable")
                }
                Button {
                    if let clip = store.selected { store.delete(clip) }
                } label: {
                    Image(systemName: "trash").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).disabled(clips.isEmpty)
                .accessibilityLabel("Delete selected clip").help("Delete selected clip (⌫)")
                options
            }
            HStack(spacing: 7) {
                if store.searching {
                    ShelfSearchField(query: $store.query, focusRequest: store.searchFocusRequest) {
                        if let clip = store.selected { use(clip) }
                    }.frame(maxWidth: 290).frame(height: 30)
                } else {
                    Button { store.searching = true } label: { Image(systemName: "magnifyingglass").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).help("Search clips (⌘F)").accessibilityLabel("Search clips")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) {
                        boardTab(nil, index: 0)
                        ForEach(Array(store.history.boards.enumerated()), id: \.element.id) { index, board in
                            boardTab(board, index: index)
                        }
                    }.fixedSize()
                    Menu(currentBoard?.name ?? "Clipboard") {
                        Button("Clipboard") { store.boardID = nil }
                        ForEach(store.history.boards) { board in
                            Button(board.name) { store.boardID = board.id }
                        }
                    }.fixedSize()
                }
                Button { boardName = ""; creatingBoard = true } label: { Image(systemName: "plus").frame(width: 26, height: 26) }
                    .buttonStyle(.plain).help("New pinboard").accessibilityLabel("New pinboard")
            }.padding(.horizontal, 120)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: store.searching)
        .popover(isPresented: $creatingBoard, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New pinboard").font(.headline)
                TextField("Board name", text: $boardName).onSubmit(createBoard)
                HStack {
                    Spacer()
                    Button("Cancel") { creatingBoard = false }
                    Button("Create", action: createBoard).disabled(!canCreate).keyboardShortcut(.defaultAction)
                }
            }.padding(16).frame(width: 254)
        }
    }

    private func pageButton(_ label: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 24) }
            .buttonStyle(.plain).disabled(disabled).help(label).accessibilityLabel(label)
    }

    private func boardTab(_ board: Board?, index: Int) -> some View {
        let selected = store.boardID == board?.id
        let colors: [Color] = [.pink, .orange, .purple, .cyan, .green]
        return Button { store.boardID = board?.id } label: {
            HStack(spacing: 6) {
                if board == nil { Image(systemName: "clock.arrow.circlepath") }
                else { Circle().fill(colors[index % colors.count]).frame(width: 10, height: 10) }
                Text(board?.name ?? "Clipboard").lineLimit(1)
            }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 10).frame(height: 28)
                .background(selected ? Color.primary.opacity(0.13) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var options: some View {
            Menu {
                Button("Settings…", action: openSettings).keyboardShortcut(",")
                Divider()
                Button("New Pinboard…") { boardName = ""; creatingBoard = true }
                Divider()
                Button(store.paused ? "Resume Capture" : "Pause Capture") { store.paused.toggle() }
                Button("Enable Automatic Insertion…", action: enablePaste)
                Divider()
                if let currentBoard, currentBoard.id != Board.favorites.id {
                    Button("Remove Pinboard…") { confirmRemoveBoard = true }
                }
                Button("Clear Unpinned History…") { confirmClear = true }
                Divider()
                Button("Hide Fold", action: dismiss)
                Button("Quit Fold") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 18)).frame(width: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Fold options")
                .accessibilityLabel("Fold options")
    }

    private var canCreate: Bool {
        !newName.isEmpty && !store.history.boards.contains { $0.name.localizedCaseInsensitiveCompare(newName) == .orderedSame }
    }
    private func createBoard() {
        guard canCreate else { return }
        let board = Board(id: UUID(), name: newName)
        store.change { $0.boards.append(board) }
        store.boardID = board.id
        creatingBoard = false
    }

    private func cards(_ clips: [Clip], columns: Int, pages: Int, width: CGFloat) -> some View {
        let selectedID = store.selected?.id
        let cardWidth = ShelfLayout.cardSize(width)
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<pages, id: \.self) { index in
                    let start = index * columns
                    HStack(spacing: ShelfLayout.gap) {
                        ForEach(clips[start..<min(start + columns, clips.count)]) { clip in
                            ClipCard(clip: clip, selected: selectedID == clip.id, fileURL: { store.firstFileURL(for: clip) })
                                .frame(width: cardWidth)
                                .onTapGesture(count: 2) { use(clip) }
                                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil); store.selection = clip.id }
                                .accessibilityAction { use(clip) }
                                .popover(isPresented: Binding(get: { store.previewID == clip.id }, set: { showing in
                                    if !showing && store.previewID == clip.id { store.previewID = nil }
                                }), arrowEdge: .top) {
                                    ClipPreview(clip: clip, load: { store.previewPayload(clip) }, close: { store.previewID = nil })
                                }
                                .contextMenu {
                                    Button("Preview") { store.selection = clip.id; store.previewID = clip.id }
                                    Button("Copy Clip") { copy(clip) }
                                    if canPaste() { Button("Paste into Previous App") { use(clip) } }
                                    Menu("Pinboards") {
                                        ForEach(store.history.boards) { board in
                                            Button { store.toggle(clip, on: board) } label: {
                                                if clip.boards.contains(board.id) { Label(board.name, systemImage: "checkmark") }
                                                else { Text(board.name) }
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("Delete Clip", role: .destructive) { store.delete(clip) }
                                }
                        }
                    }.padding(.horizontal, ShelfLayout.margin).frame(width: width, alignment: .leading).id(index)
                }
            }.scrollTargetLayout()
        }.scrollClipDisabled().scrollIndicators(.hidden).scrollTargetBehavior(.paging).scrollPosition(id: $page, anchor: .leading)
        .onChange(of: store.selection) { _, id in
            guard let id, let index = clips.firstIndex(where: { $0.id == id }) else { return }
            if page != index / columns { page = index / columns }
        }
        .onChange(of: page) { _, new in
            guard let new, clips.indices.contains(new * columns) else { return }
            let selected = clips.firstIndex { $0.id == selectedID } ?? 0
            if selected / columns != new { store.selection = clips[new * columns].id }
        }
    }

}
