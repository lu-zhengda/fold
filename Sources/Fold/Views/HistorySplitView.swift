import SwiftUI

struct HistorySplitView: View {
    @ObservedObject var store: ShelfStore
    let use: (Clip) -> Void
    let copy: (Clip) -> Void
    let dismiss: () -> Void
    let openSettings: () -> Void
    let enablePaste: () -> Void
    let canPaste: () -> Bool
    @State private var creatingBoard = false
    @State private var boardName = ""
    @State private var clipToRename: Clip?
    @State private var clipName = ""
    @State private var confirmClear = false
    @State private var confirmRemoveBoard = false

    private var currentBoard: Board? { store.history.boards.first { $0.id == store.boardID } }
    private var newName: String { boardName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GeometryReader { geometry in
            let clips = store.visible
            let selected = clips.first { $0.id == store.selection } ?? clips.first
            VStack(spacing: 0) {
                toolbar.padding(.horizontal, 18).frame(height: 54)
                Divider()
                if let selected {
                    HStack(spacing: 0) {
                        historyList(clips, selected: selected.id)
                            .frame(width: geometry.size.width * 0.40)
                        Divider()
                        ClipPreview(clip: selected, load: { store.previewPayload(selected) })
                            .id(selected.storageID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .popover(isPresented: Binding(get: { store.previewID == selected.id }, set: {
                                if !$0 { store.previewID = nil }
                            })) {
                                ClipPreview(clip: selected, load: { store.previewPayload(selected) })
                                    .frame(width: 530, height: 390)
                                    .onExitCommand { store.previewID = nil }
                            }
                    }
                } else {
                    EmptyShelf(searching: !store.query.isEmpty, board: currentBoard != nil, paused: store.paused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                HStack(spacing: 16) {
                    Button {
                        if let selected { store.delete(selected) }
                    } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete selected clip").help("Delete selected clip (⌫)")
                    .disabled(selected == nil)
                    if let selected {
                        let favorite = selected.boards.contains(Board.favorites.id)
                        Button { store.toggle(selected, on: .favorites) } label: {
                            Image(systemName: favorite ? "star.fill" : "star")
                        }
                        .accessibilityLabel(favorite ? "Remove from Favorites" : "Add to Favorites")
                        .help(favorite ? "Remove from Favorites (⌘D)" : "Add to Favorites (⌘D)")
                    }
                    if let notice = store.notice { Text(notice).lineLimit(1) }
                    Spacer()
                    Text("↑ ↓  Navigate")
                    Button {
                        if let selected { use(selected) }
                    } label: { Text(canPaste() ? "↩  Paste" : "↩  Copy") }
                    .disabled(selected == nil)
                }
                .font(.callout).foregroundStyle(.secondary).buttonStyle(.plain)
                .padding(.horizontal, 18).frame(height: 38)
            }
        }
        .background(ShelfMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.primary.opacity(0.15)).allowsHitTesting(false))
        .onChange(of: store.boardID) { store.query = ""; store.selection = nil }
        .onChange(of: store.query) { store.selection = nil }
        .sheet(item: $clipToRename) { clip in
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Clip").font(.headline)
                TextField("Clip name", text: $clipName)
                Text("Leave the name blank to use the original title.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { clipToRename = nil }.keyboardShortcut(.cancelAction)
                    Button("Save") {
                        store.change { history in
                            guard let index = history.clips.firstIndex(where: { $0.id == clip.id }) else { return }
                            history.clips[index].rename(to: clipName)
                        }
                        clipToRename = nil
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 320)
        }
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

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("Fold", systemImage: "square.on.square")
                .font(.system(size: 18, weight: .semibold))
            Menu(currentBoard?.name ?? "History") {
                Button("History") { store.boardID = nil }
                ForEach(store.history.boards) { board in
                    Button(board.name) { store.boardID = board.id }
                }
                Divider()
                Button("New Pinboard…") { boardName = ""; creatingBoard = true }
            }.fixedSize()
            Spacer(minLength: 0)
            if store.paused || store.captureDenied || !store.shortcutAvailable {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    .help(store.captureDenied ? "Clipboard access denied" : store.paused ? "Capture paused" : "Shortcut unavailable")
            }
            ShelfSearchField(query: $store.query, focusRequest: store.searchFocusRequest) {
                if let clip = store.selected { use(clip) }
            }.frame(maxWidth: 240).frame(height: 30)
            options
        }
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

    private func historyList(_ clips: [Clip], selected: UUID) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(clips) { clip in
                        let active = clip.id == selected
                        HStack(spacing: 9) {
                            Image(systemName: clip.kind.symbol)
                                .frame(width: 28, height: 28)
                                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                            Text(clip.listTitle).lineLimit(1)
                            Spacer(minLength: 0)
                            if !clip.boards.isEmpty { Image(systemName: "pin.fill").font(.caption2) }
                            Text(clip.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                                .font(.caption).opacity(0.8)
                        }
                        .padding(.horizontal, 9).frame(height: 43)
                        .foregroundStyle(active ? Color.white : Color.primary)
                        .background(active ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { use(clip) }
                        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil); store.selection = clip.id }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(clip.listTitle), \(clip.kind.title), from \(clip.source)")
                        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { store.selection = clip.id }
                        .contextMenu { clipActions(clip) }
                        .id(clip.id)
                    }
                }.padding(8)
            }
            .onChange(of: selected, initial: true) { scroll.scrollTo(selected) }
            .onChange(of: store.openCount) { scroll.scrollTo(selected, anchor: .top) }
        }
    }

    @ViewBuilder private func clipActions(_ clip: Clip) -> some View {
        Button("Preview") { store.selection = clip.id; store.previewID = clip.id }
        Button("Copy Clip") { copy(clip) }
        Button("Rename Clip…") {
            clipName = clip.listTitle
            clipToRename = clip
        }
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
