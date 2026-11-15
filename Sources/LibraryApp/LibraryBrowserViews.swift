import AppKit
import LibraryCore
import PreviewRenderer
import SwiftUI

/// The folder sidebar with its listing-issues footer (BRW-1, BRW-8).
struct FolderSidebar: View {
    @Bindable var browser: LibraryBrowserModel

    var body: some View {
        List(
            selection: Binding(
                get: { browser.isFiltering ? nil : browser.folder },
                set: { if let path = $0 { browser.show(folder: path) } })
        ) {
            Label("Library", systemImage: "books.vertical").tag("")
                .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { browser.drop($0, into: "") }
                .contextMenu {
                    Button("New Folder") {
                        Task {
                            browser.show(folder: "")
                            await browser.newFolder()
                        }
                    }
                }
            OutlineGroup(browser.folderTree.children ?? [], children: \.children) { node in
                Label {
                    RichNameText(name: node.name)
                } icon: {
                    Image(systemName: "folder")
                }
                .tag(node.path)
                .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { browser.drop($0, into: node.path) }
                .contextMenu {
                    Button("New Folder") {
                        Task {
                            browser.show(folder: node.path)
                            await browser.newFolder()
                        }
                    }
                    Button("Rename") {
                        browser.show(folder: LibraryBrowserModel.parent(node.path))
                        browser.selection = ["folder:" + node.path]
                        browser.beginRename()
                    }
                    Button("Move To…") {
                        browser.show(folder: LibraryBrowserModel.parent(node.path))
                        browser.selection = ["folder:" + node.path]
                        browser.moveSheetRows = browser.organizableSelection
                    }
                    Button("Delete Folder") {
                        browser.show(folder: LibraryBrowserModel.parent(node.path))
                        browser.selection = ["folder:" + node.path]
                        browser.requestDelete()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if !browser.issues.isEmpty {
                Button {
                    browser.showingIssues = true
                } label: {
                    Label(
                        browser.issues.count == 1
                            ? "1 item can't be used" : "\(browser.issues.count) items can't be used",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .symbolRenderingMode(.multicolor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

/// Links to the current folder and each ancestor (BRW-4), or the search scope while filtering.
struct PathBar: View {
    @Bindable var browser: LibraryBrowserModel

    var body: some View {
        HStack(spacing: 4) {
            if browser.isFiltering {
                Text("Search results in Library")
            } else {
                let components = browser.pathComponents
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                    }
                    if index == components.count - 1 {
                        RichNameText(name: component.name).fontWeight(.semibold)
                    } else {
                        Button {
                            Task { await browser.navigate(to: component.target) }
                        } label: {
                            RichNameText(name: component.name)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            Spacer()
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path")
    }
}

/// The item list and its empty states (BRW-1 to BRW-6, BRW-10).
struct ItemList: View {
    @Bindable var browser: LibraryBrowserModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.iconCatalog) private var iconCatalog
    /// Entry and tag icons in rows. Every name cell is at least this tall plus 12 points, the height of a name line
    /// holding a centred icon, so rows keep one height with icons or without.
    @ScaledMetric(relativeTo: .body) private var rowIconSize: CGFloat = 24
    @State private var sortOrder = [KeyPathComparator(\BrowserRow.name, comparator: .localizedStandard)]
    @FocusState private var listFocused: Bool
    @State private var refocusList = false

    var body: some View {
        listArea
            .onChange(of: browser.listFocusRequested) { _, requested in
                guard requested else { return }
                browser.listFocusRequested = false
                listFocused = true
                selectFirstRowForKeyboard()
            }
            .onChange(of: browser.locationKey) {
                guard listFocused else { return }
                // Opening or leaving a book replaces the table (after a loading state) and would leave focus nowhere;
                // the next table to appear takes it back.
                refocusList = true
                // A folder opens in the same table, which keeps focus but loses its selection.
                selectFirstRowForKeyboard()
            }
    }

    /// Selects the first row for a list focused from the keyboard (`itemListFocusedByKeyboard`), on the next turn,
    /// after the table has pushed its own selection back.
    private func selectFirstRowForKeyboard() {
        Task { @MainActor in browser.itemListFocusedByKeyboard() }
    }

    private static func isMouse(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        let mouse: [NSEvent.EventType] = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
        ]
        return mouse.contains(event.type)
    }

    /// Gives keyboard focus back to a table that replaced a focused one, with a visible selected row.
    private func restoreListFocus() {
        guard refocusList else { return }
        refocusList = false
        Task { @MainActor in
            // Only when focus went nowhere: never take it from a field the user has moved to since.
            guard let window = NSApp.keyWindow, window.firstResponder === window else { return }
            listFocused = true
            selectFirstRowForKeyboard()
        }
    }

    @ViewBuilder private var listArea: some View {
        switch browser.content {
        case .loading:
            ProgressView("Loading library…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .libraryEmpty:
            ContentUnavailableView {
                Label("This library is empty", systemImage: "books.vertical")
            } description: {
                Text("Import a blueprint string from the clipboard or a TXT file.")
            } actions: {
                Button("Import…") { browser.beginImport() }
                Button("Import from Clipboard") { browser.beginImport(text: LibraryPasteboard.text) }
            }
            .dropDestination(for: URL.self) { urls, _ in
                browser.beginImport(files: urls)
                return !urls.isEmpty
            }
        case .folderEmpty(let name):
            ContentUnavailableView {
                Label("“\(name)” is empty", systemImage: "folder")
            } description: {
                Text("Import here, or drag items onto this folder in the sidebar.")
            } actions: {
                Button("Import…") { browser.beginImport() }
            }
            .dropDestination(for: URL.self) { urls, _ in
                browser.beginImport(files: urls)
                return !urls.isEmpty
            }
        case .noMatches(let text):
            ContentUnavailableView {
                Label("No items named “\(text)”", systemImage: "magnifyingglass")
            } description: {
                Text("Check the spelling or clear the search.")
            } actions: {
                Button("Clear Search") { browser.filterText = "" }
            }
        case .tooLarge(let message):
            ContentUnavailableView {
                Label(message.title, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                Text(message.guidance)
            }
        case .bookEmpty:
            ContentUnavailableView("This book has no entries.", systemImage: "books.vertical")
        case .bookFailed(let message):
            ContentUnavailableView {
                Label(message.title, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                Text(message.guidance)
            }
        case .rows(let rows):
            if browser.showsBook { bookTable(rows) } else { table(rows) }
        }
    }

    /// A book's entries in stored order with their stored indices (BOOK-1, BOOK-2); not sortable.
    private func bookTable(_ rows: [BrowserRow]) -> some View {
        Table(rows, selection: $browser.selection) {
            TableColumn("#") { row in Text(row.storedIndex.map(String.init) ?? "").monospacedDigit() }
                .width(min: 32, ideal: 44, max: 64)
            TableColumn("Name") { row in
                HStack(spacing: 6) {
                    EntryIconStrip(kind: row.kind, icons: row.icons, size: rowIconSize)
                    RichNameText(name: row.name, pointSize: rowIconSize)
                }
                .frame(minHeight: rowIconSize + 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Self.withIcons(
                        "\(spokenName(row)), \(row.kind.label.lowercased()), entry \(row.storedIndex ?? 0)", row))
            }
            .width(min: 160, ideal: 320)
            TableColumn("Kind") { row in Text(row.kind.label) }
                .width(min: 80, ideal: 160)
        }
        .scrollContentBackground(.hidden)
        .background(Color.contentBackground)
        .contextMenu(forSelectionType: String.self) { ids in
            RowMenu(browser: browser, ids: ids)
        } primaryAction: { ids in
            browser.selection = ids
            Task { await browser.openSelection() }
        }
        .onCopyCommand {
            Task { await browser.copySelectedString() }
            return []
        }
        .onKeyPress(.space) { openPreviewWindow() }
        .focused($listFocused)
        .onChange(of: listFocused) { _, focused in
            // Not a click, which selects (or clears) rows itself. Anything else counts as the keyboard: by the time
            // focus changes, the current event can already be the Tab's key-up.
            guard focused, !Self.isMouse(NSApp.currentEvent) else { return }
            selectFirstRowForKeyboard()
        }
        .onAppear(perform: restoreListFocus)
        .accessibilityLabel("Book entries")
    }

    private func table(_ rows: [BrowserRow]) -> some View {
        Table(of: BrowserRow.self, selection: $browser.selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { row in
                if browser.renamingRow == row.id {
                    RenameField(browser: browser, row: row)
                } else {
                    HStack(spacing: 6) {
                        EntryIconStrip(kind: row.kind, icons: row.icons, size: rowIconSize)
                        RichNameText(name: row.name, pointSize: rowIconSize)
                    }
                    .frame(minHeight: rowIconSize + 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(row))
                }
            }
            .width(min: 160, ideal: 280)
            if browser.isFiltering {
                TableColumn("Folder") { row in Text(row.folder.isEmpty ? "Library" : row.folder) }
            }
            TableColumn("Kind", value: \.kind.label) { row in Text(row.kind.label) }
                .width(min: 80, ideal: 120)
            TableColumn("Updated", value: \.sortableUpdated) { row in
                Text(row.updated.map(LibraryFormat.display) ?? "")
            }
            .width(min: 120, ideal: 160)
            TableColumn("Size", value: \.sortableSize) { row in
                Text(row.sizeBytes.map(LibraryFormat.size) ?? "")
            }
            .width(min: 60, ideal: 80)
        } rows: {
            ForEach(rows) { row in
                TableRow(row).draggable(browser.dragPayload(for: row))
            }
        }
        .onKeyPress(.return) {
            guard browser.renamingRow == nil, browser.canRenameSelection else { return .ignored }
            browser.beginRename()
            return .handled
        }

        .scrollContentBackground(.hidden)
        .background(Color.contentBackground)
        .contextMenu(forSelectionType: String.self) { ids in
            RowMenu(browser: browser, ids: ids)
        } primaryAction: { ids in
            browser.selection = ids
            Task { await browser.openSelection() }
        }
        .onCopyCommand {
            Task { await browser.copySelectedString() }
            return []
        }
        .onKeyPress(.space) { openPreviewWindow() }
        .onChange(of: [browser.sortKey.rawValue, String(browser.ascending)]) {
            // View ▸ Sort By changed the order; move the header's sort indicator to match.
            let order: SortOrder = browser.ascending ? .forward : .reverse
            let wanted =
                switch browser.sortKey {
                case .name: KeyPathComparator(\BrowserRow.name, comparator: .localizedStandard, order: order)
                case .kind: KeyPathComparator(\BrowserRow.kind.label, order: order)
                case .updated: KeyPathComparator(\BrowserRow.sortableUpdated, order: order)
                case .size: KeyPathComparator(\BrowserRow.sortableSize, order: order)
                }
            if sortOrder.first != wanted { sortOrder = [wanted] }
        }
        .onChange(of: sortOrder, initial: true) { _, order in
            guard let first = order.first else { return }
            browser.ascending = first.order == .forward
            browser.sortKey =
                switch first.keyPath {
                case \BrowserRow.kind.label: .kind
                case \BrowserRow.sortableUpdated: .updated
                case \BrowserRow.sortableSize: .size
                default: .name
                }
        }
        .onPasteCommand(of: [.plainText]) { _ in browser.beginImport(text: LibraryPasteboard.text) }
        .dropDestination(for: URL.self) { urls, _ in
            browser.beginImport(files: urls)
            return !urls.isEmpty
        }
        .focused($listFocused)
        .onChange(of: listFocused) { _, focused in
            // Not a click, which selects (or clears) rows itself. Anything else counts as the keyboard: by the time
            // focus changes, the current event can already be the Tab's key-up.
            guard focused, !Self.isMouse(NSApp.currentEvent) else { return }
            selectFirstRowForKeyboard()
        }
        .onAppear(perform: restoreListFocus)
        .accessibilityLabel("Items")
    }

    /// Space opens the selected blueprint, planner, or entry in a preview window (screen specs, "Menus").
    private func openPreviewWindow() -> KeyPress.Result {
        guard browser.renamingRow == nil, let target = browser.previewTarget else { return .ignored }
        openWindow(id: LibraryAppIdentity.previewWindow, value: target.subject)
        return .handled
    }

    private func accessibilityLabel(_ row: BrowserRow) -> String {
        var parts = [spokenName(row), row.kind.label.lowercased()]
        if let updated = row.updated { parts.append("updated \(updated.formatted(date: .long, time: .omitted))") }
        if let size = row.sizeBytes { parts.append(LibraryFormat.size(size)) }
        return Self.withIcons(parts.joined(separator: ", "), row)
    }

    /// The row's name as VoiceOver reads it, with icons named in place (ICN-7).
    private func spokenName(_ row: BrowserRow) -> String { RichTextName(row.name).spoken(showing: iconCatalog) }

    /// Entry icons are read after the rest of the row: "…, icons: iron plate, rare; copper cable".
    private static func withIcons(_ label: String, _ row: BrowserRow) -> String {
        let names = EntryIconLayout.spokenNames(row.icons)
        return names.isEmpty ? label : label + ", icons: " + names
    }
}

extension BrowserRow {
    var sortableUpdated: Date { updated ?? .distantPast }
    var sortableSize: Int { sizeBytes ?? -1 }
}

/// The inspector: a header for the selected item or entry, then Statistics, Details, and Comments tabs (screen specs,
/// "Inspector"); folders and multiple selections show a summary.
struct ItemInspector: View {
    @Bindable var browser: LibraryBrowserModel
    let previews: PreviewCenter
    let statistics: StatisticsModel
    let assetsRevision: Int

    /// The inspector's height, so the header and the preview leave room for the tabs in short windows.
    @State private var height: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if browser.commentScope != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        InspectorHeader(browser: browser)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                // The header shows all of itself at ordinary window heights and scrolls only in short windows, where the
                // preview and the tabs need the room.
                .frame(maxHeight: min(420, max(120, height * 0.45)))
                .fixedSize(horizontal: false, vertical: true)
                if browser.previewTarget != nil {
                    InspectorPreview(
                        browser: browser, center: previews, assetsRevision: assetsRevision,
                        height: min(200, max(100, height * 0.25))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else if let count = bookEntryCount {
                    BookPreviewNote(browser: browser, entryCount: count)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                Picker("Inspector", selection: $browser.inspectorTab) {
                    ForEach(InspectorTab.allCases, id: \.self) { tab in Text(tab.title).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                Divider()
                switch browser.inspectorTab {
                case .statistics:
                    StatisticsTab(browser: browser, model: statistics, assetsRevision: assetsRevision)
                case .details: DetailsTab(browser: browser)
                case .comments: CommentsTab(browser: browser)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let row = browser.selectedRows.first, browser.selectedRows.count == 1,
                            let path = row.folderPath
                        {
                            FolderSummary(browser: browser, path: path)
                        } else if browser.selectedRows.count > 1 {
                            Text("\(browser.selectedRows.count) items selected")
                        } else if !browser.folder.isEmpty {
                            FolderSummary(browser: browser, path: browser.folder)
                        } else {
                            Text("Select an item to see its details.")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            height = $0
        }
        .background(Color.contentBackground)
        .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
        .task(id: browser.selectedItem.map { $0.id + $0.metadata.sourceSha256 }) {
            await browser.loadSelectedDetail()
        }
    }

    /// The entry count when the inspector shows a book, which has no rendered preview (PRV-1).
    private var bookEntryCount: Int? {
        if let detail = browser.selectedDetail, detail.kind == .book { return detail.entryCount ?? 0 }
        if browser.selectedDetail == nil, let item = browser.selectedItem, ItemKind(stored: item.kind) == .book {
            return 0
        }
        return nil
    }
}

/// "Books have no preview", with the entry count and Open Book (screen specs, "Inspector").
private struct BookPreviewNote: View {
    let browser: LibraryBrowserModel
    let entryCount: Int

    var body: some View {
        VStack(spacing: 8) {
            Text("Books have no preview").font(.headline)
            if browser.selectedDetail != nil {
                // Primary text: secondary fails 4.5:1 on this panel (A16 contrast check).
                Text(entryCount == 1 ? "1 entry" : "\(entryCount) entries")
            }
            if browser.canOpenSelection {
                Button("Open Book") { Task { await browser.openSelection() } }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Name, kind, version, position or dates and size, and the export buttons.
private struct InspectorHeader: View {
    let browser: LibraryBrowserModel

    var body: some View {
        let detail = browser.selectedDetail
        let item = browser.showsBook ? (detail?.location == nil ? browser.openBookItem : nil) : browser.selectedItem
        let name = detail?.name ?? item?.name ?? ""
        let kind = detail?.kind ?? item.map { ItemKind(stored: $0.kind) } ?? .blueprint
        HStack(alignment: .top, spacing: 10) {
            EntryIconTile(kind: kind, icons: detail?.icons ?? item?.entryIcons ?? [], side: 64)
            VStack(alignment: .leading, spacing: 4) {
                RichNameText(name: name, pointSize: 28, textStyle: .title2).font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Label(kind.label, systemImage: kind.symbol)
            }
        }
        if let detail { Text(detail.version.map { "Factorio \($0)" } ?? "Version unknown") }
        if let location = detail?.location { Text(location) }
        if let item {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                if let updated = LibraryFormat.date(item.metadata.updatedAt) {
                    GridRow {
                        Text("Updated").fontWeight(.medium)
                        Text(LibraryFormat.display(updated))
                    }
                }
                if let created = LibraryFormat.date(item.metadata.createdAt) {
                    GridRow {
                        Text("Created").fontWeight(.medium)
                        Text(LibraryFormat.display(created))
                    }
                }
                GridRow {
                    Text("Size").fontWeight(.medium)
                    Text(LibraryFormat.exactSize(item.sourceBytes))
                }
                if !browser.showsBook {
                    GridRow {
                        Text("Folder").fontWeight(.medium)
                        Text(item.folder.isEmpty ? "Library" : item.folder)
                    }
                }
            }
        }
        ExportButtons(browser: browser).padding(.top, 4)
    }
}

/// Entry count, description with its line breaks (BOOK-5), and planner settings as text (BOOK-6).
private struct DetailsTab: View {
    let browser: LibraryBrowserModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let detail = browser.selectedDetail {
                    if let count = detail.entryCount {
                        Text(count == 1 ? "1 entry" : "\(count) entries")
                    }
                    if !detail.description.isEmpty {
                        Text("Description").font(.headline)
                        Text(detail.description)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !detail.settings.isEmpty {
                        Text("Settings").font(.headline)
                        Text(detail.settings.joined(separator: "\n"))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if detail.entryCount == nil && detail.description.isEmpty && detail.settings.isEmpty {
                        Text("No description.")
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

/// The scope's comments with an Add field (COM-1 to COM-7).
private struct CommentsTab: View {
    @Bindable var browser: LibraryBrowserModel
    @State private var selected: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if browser.comments.isEmpty {
                Text("No comments yet.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            } else {
                List(browser.comments, id: \.id, selection: $selected) { comment in
                    let date = LibraryFormat.date(comment.createdAt).map(LibraryFormat.display) ?? comment.createdAt
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date)
                            .font(.caption.weight(.medium))
                        Text(comment.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Delete Comment") { browser.commentPendingDeletion = comment }
                    }
                    // Combining children keeps only the date: selectable text is not merged.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(comment.text), \(date)")
                }
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Comments")
                .onDeleteCommand {
                    browser.commentPendingDeletion = browser.comments.first { $0.id == selected }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("New comment").font(.headline)
                TextEditor(text: $browser.commentDraft)
                    .frame(height: 70)
                    .focused($fieldFocused)
                    .accessibilityLabel("New comment")
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
                    // A comment rarely needs a tab character; Tab and Shift-Tab move focus like a text field's,
                    // and Escape returns it to the item list.
                    .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: .down) { press in
                        // Shift-Tab arrives as the back-tab character.
                        if press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}") {
                            NSApp.keyWindow?.selectPreviousKeyView(nil)
                        } else {
                            NSApp.keyWindow?.selectNextKeyView(nil)
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        browser.requestListFocus()
                        return .handled
                    }
                if browser.commentTooLong {
                    Text("Comments can be up to 64 KB.")
                }
                if let failure = browser.commentFailure {
                    Label("\(failure.title). \(failure.guidance)", systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Add Comment") { Task { await browser.addComment() } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!browser.canAddComment)
                }
            }
            .padding(16)
        }
        .onChange(of: browser.commentFocusRequested, initial: true) { _, requested in
            guard requested else { return }
            fieldFocused = true
            browser.commentFocusRequested = false
        }
        .alert(
            "Delete this comment?",
            isPresented: Binding(
                get: { browser.commentPendingDeletion != nil },
                set: { if !$0 { browser.commentPendingDeletion = nil } }),
            presenting: browser.commentPendingDeletion
        ) { comment in
            Button("Delete Comment", role: .destructive) { Task { await browser.deleteComment(comment) } }
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: { _ in
            Text("This can't be undone.")
        }
    }
}

private struct FolderSummary: View {
    let browser: LibraryBrowserModel
    let path: String

    var body: some View {
        let listing = browser.listing
        let items = listing?.items.filter { $0.folder == path }.count ?? 0
        let folders = listing?.folders.filter { LibraryBrowserModel.parent($0) == path }.count ?? 0
        Text(LibraryBrowserModel.lastComponent(path)).font(.title2.weight(.semibold))
        Label("Folder", systemImage: "folder")
        Text("\(items) \(items == 1 ? "item" : "items"), \(folders) \(folders == 1 ? "folder" : "folders")")
        if let description = listing?.folderComments[path] {
            Text(description)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Unusable stored items and why (BRW-8).
struct ListingIssuesSheet: View {
    @Bindable var browser: LibraryBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(browser.issues.count == 1 ? "1 item can't be used" : "\(browser.issues.count) items can't be used")
                .font(.headline)
            Text(
                "They are left out of the library until fixed. Close the library before changing files in Finder.")
            Table(
                browser.issues.enumerated().map {
                    IssueRow(id: $0.offset, path: $0.element.path, message: $0.element.message)
                }
            ) {
                TableColumn("Path") { Text($0.path).textSelection(.enabled) }
                    .width(min: 160, ideal: 220)
                TableColumn("Problem") { Text($0.message) }
            }
            .frame(minHeight: 180)
            HStack {
                Spacer()
                Button("Done") { browser.showingIssues = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 320)
    }
}

private struct IssueRow: Identifiable {
    let id: Int
    let path: String
    let message: String
}

/// The general pasteboard's text, exactly as copied.
enum LibraryPasteboard {
    @MainActor static var text: String { NSPasteboard.general.string(forType: .string) ?? "" }

    @MainActor static func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Context menu for item and entry rows.
private struct RowMenu: View {
    let browser: LibraryBrowserModel
    let ids: Set<String>

    var body: some View {
        if browser.canOpenSelection && ids == browser.selection {
            Button("Open") { Task { await browser.openSelection() } }
        }
        if ids.count == 1, ids == browser.selection, browser.exportTarget != nil {
            Button("Copy String") { Task { await browser.copySelectedString() } }
            Button("Save As TXT…") { Task { await ExportFlow.saveSelection(browser) } }
        }
        if ids == browser.selection, !browser.organizableSelection.isEmpty {
            Divider()
            if browser.canRenameSelection { Button("Rename") { browser.beginRename() } }
            Button("Move To…") { browser.moveSheetRows = browser.organizableSelection }
            if browser.canReplaceSelection { Button("Replace Source…") { browser.beginReplace() } }
            let folder = browser.organizableSelection.first?.folderPath != nil
            Button(folder && browser.organizableSelection.count == 1 ? "Delete Folder" : "Move to Trash") {
                browser.requestDelete()
            }
        }
    }
}

/// The in-place name editor: Return commits, Esc cancels, a refused name keeps the text and explains why (ORG-5).
private struct RenameField: View {
    let browser: LibraryBrowserModel
    let row: BrowserRow
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .labelsHidden()
            .focused($focused)
            .onAppear { text = row.name }
            .task {
                // The table keeps focus while it finishes handling Return; claim it on the next turn.
                try? await Task.sleep(for: .milliseconds(80))
                focused = true
            }
            .onSubmit {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task { await browser.rename(row, to: text) }
            }
            .onExitCommand { browser.cancelRename() }
            .popover(
                isPresented: Binding(
                    get: { browser.renameFailure != nil }, set: { if !$0 { browser.renameFailure = nil } }),
                arrowEdge: .bottom
            ) {
                if let failure = browser.renameFailure {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure.title).font(.headline)
                        Text(failure.guidance)
                    }
                    .padding(12)
                    .frame(maxWidth: 280)
                }
            }
            .accessibilityLabel("New name for \(row.name)")
    }
}

/// The Move To sheet: a folder tree with invalid targets disabled (ORG-6, ORG-7).
struct MoveToSheet: View {
    let browser: LibraryBrowserModel
    let rows: [BrowserRow]
    @State private var target: String?

    var body: some View {
        let allowed = Set(browser.moveTargets(for: rows))
        VStack(alignment: .leading, spacing: 12) {
            Text(rows.count == 1 ? "Move “\(rows[0].name)” to:" : "Move \(rows.count) items to:").font(.headline)
            List(selection: $target) {
                Label("Library", systemImage: "books.vertical").tag("")
                    .foregroundStyle(allowed.contains("") ? Color.primary : Color.secondary)
                    .selectionDisabled(!allowed.contains(""))
                OutlineGroup(browser.folderTree.children ?? [], children: \.children) { node in
                    Label(node.name, systemImage: "folder").tag(node.path)
                        .foregroundStyle(allowed.contains(node.path) ? Color.primary : Color.secondary)
                        .selectionDisabled(!allowed.contains(node.path))
                }
            }
            .frame(minHeight: 260)
            .accessibilityLabel("Folders")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { browser.moveSheetRows = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Move") {
                    guard let target else { return }
                    browser.moveSheetRows = nil
                    Task { await browser.move(rows, to: target, reveal: true) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(target == nil || !allowed.contains(target ?? "\u{0}"))
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// The Replace Source sheet (ORG-11 to ORG-13).
struct ReplaceSheet: View {
    @Bindable var model: ReplaceModel
    let onReplace: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace “\(model.itemName)”").font(.title2.weight(.semibold))
            Text("The current string goes to the Trash. Comments on entries that no longer exist move to the item.")
                .fixedSize(horizontal: false, vertical: true)
            if let file = model.file {
                HStack {
                    Label(file.lastPathComponent, systemImage: "doc.text")
                    Spacer()
                    Button("Use Pasted Text") { model.setFile(nil) }
                }
            } else {
                Text("Blueprint string").font(.headline)
                TextEditor(text: $model.text)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
                    .accessibilityLabel("Blueprint string")
                switch model.analysis {
                case .valid(let kind, _, _): Label(kind.label, systemImage: kind.symbol)
                case .invalid(let message):
                    Label(message.title, systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                default: EmptyView()
                }
                Button("Choose File…") {
                    Task { if let url = await ImportSheet.chooseFiles()?.first { model.setFile(url) } }
                }
            }
            if let failure = model.failure { MessageView(message: failure) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Replace", action: onReplace)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.blocker != nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task(id: model.text) {
            try? await Task.sleep(for: .milliseconds(200))
            await model.analyze()
        }
    }
}

/// Copy String and Save As TXT for the inspector's item or entry.
struct ExportButtons: View {
    let browser: LibraryBrowserModel

    var body: some View {
        if browser.exportTarget != nil {
            HStack {
                Button("Copy String") { Task { await browser.copySelectedString() } }
                Button("Save As TXT…") { Task { await ExportFlow.saveSelection(browser) } }
            }
            .controlSize(.small)
        }
    }
}
