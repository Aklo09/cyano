import LibraryCore
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
            OutlineGroup(browser.folderTree.children ?? [], children: \.children) { node in
                Label(node.name, systemImage: "folder").tag(node.path)
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
                        Text(component.name).fontWeight(.semibold)
                    } else {
                        Button(component.name) { Task { await browser.navigate(to: component.target) } }
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
    @State private var sortOrder = [KeyPathComparator(\BrowserRow.name, comparator: .localizedStandard)]

    var body: some View {
        switch browser.content {
        case .loading:
            ProgressView("Loading library…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .libraryEmpty:
            ContentUnavailableView {
                Label("This library is empty", systemImage: "books.vertical")
            } description: {
                Text("Import a blueprint string from the clipboard or a TXT file.")
            }
        case .folderEmpty(let name):
            ContentUnavailableView {
                Label("“\(name)” is empty", systemImage: "folder")
            } description: {
                Text("Import here, or drag items onto this folder in the sidebar.")
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
                Label {
                    Text(row.name)
                } icon: {
                    Image(systemName: row.kind.symbol).accessibilityHidden(true)
                }
                .accessibilityLabel("\(row.name), \(row.kind.label.lowercased()), entry \(row.storedIndex ?? 0)")
            }
            .width(min: 160, ideal: 320)
            TableColumn("Kind") { row in Text(row.kind.label) }
                .width(min: 80, ideal: 160)
        }
        .scrollContentBackground(.hidden)
        .background(Color.contentBackground)
        .contextMenu(forSelectionType: String.self) { _ in
        } primaryAction: { ids in
            browser.selection = ids
            Task { await browser.openSelection() }
        }
        .accessibilityLabel("Book entries")
    }

    private func table(_ rows: [BrowserRow]) -> some View {
        Table(rows, selection: $browser.selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { row in
                Label {
                    Text(row.name)
                } icon: {
                    Image(systemName: row.kind.symbol).accessibilityHidden(true)
                }
                .accessibilityLabel(accessibilityLabel(row))
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
        }
        .scrollContentBackground(.hidden)
        .background(Color.contentBackground)
        .contextMenu(forSelectionType: String.self) { _ in
        } primaryAction: { ids in
            browser.selection = ids
            Task { await browser.openSelection() }
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
        .accessibilityLabel("Items")
    }

    private func accessibilityLabel(_ row: BrowserRow) -> String {
        var parts = [row.name, row.kind.label.lowercased()]
        if let updated = row.updated { parts.append("updated \(updated.formatted(date: .long, time: .omitted))") }
        if let size = row.sizeBytes { parts.append(LibraryFormat.size(size)) }
        return parts.joined(separator: ", ")
    }
}

extension BrowserRow {
    var sortableUpdated: Date { updated ?? .distantPast }
    var sortableSize: Int { sizeBytes ?? -1 }
}

/// Details of the selected item or the current folder. Preview, statistics, and comments come with A7–A13.
struct ItemInspector: View {
    @Bindable var browser: LibraryBrowserModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if browser.showsBook, let detail = browser.selectedDetail {
                    EntryDetailView(detail: detail, item: detail.location == nil ? browser.openBookItem : nil)
                } else if let item = browser.selectedItem {
                    let kind = ItemKind(stored: item.kind)
                    Text(item.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Label(kind.label, systemImage: kind.symbol)
                    if let version = browser.selectedDetail?.version {
                        Text("Factorio \(version)")
                    } else if browser.selectedDetail != nil {
                        Text("Version unknown")
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
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
                        GridRow {
                            Text("Folder").fontWeight(.medium)
                            Text(item.folder.isEmpty ? "Library" : item.folder)
                        }
                    }
                    if let detail = browser.selectedDetail { EntryDetailBody(detail: detail) }
                } else if let row = browser.selectedRows.first, browser.selectedRows.count == 1,
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
        .background(Color.contentBackground)
        .inspectorColumnWidth(min: 220, ideal: 260, max: 400)
        .task(id: browser.selectedItem.map { $0.id + $0.metadata.sourceSha256 }) {
            await browser.loadSelectedDetail()
        }
    }
}

/// An entry's (or open book's) header and details.
private struct EntryDetailView: View {
    let detail: EntryDetail
    /// The saved item when the detail is its root, for dates and size.
    let item: LibraryCore.LibraryItem?

    var body: some View {
        Text(detail.name).font(.title2.weight(.semibold)).textSelection(.enabled)
        Label(detail.kind.label, systemImage: detail.kind.symbol)
        Text(detail.version.map { "Factorio \($0)" } ?? "Version unknown")
        if let location = detail.location { Text(location) }
        if let item {
            Text("Size \(LibraryFormat.exactSize(item.sourceBytes))")
        }
        EntryDetailBody(detail: detail)
    }
}

/// Entry count, description with its line breaks (BOOK-5), and planner settings as text (BOOK-6).
private struct EntryDetailBody: View {
    let detail: EntryDetail

    var body: some View {
        if let count = detail.entryCount {
            Text(count == 1 ? "1 entry" : "\(count) entries")
        }
        if !detail.description.isEmpty {
            Text("Description").font(.headline).padding(.top, 6)
            Text(detail.description)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !detail.settings.isEmpty {
            Text("Settings").font(.headline).padding(.top, 6)
            Text(detail.settings.joined(separator: "\n"))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        if detail.kind == .upgradePlanner || detail.kind == .deconstructionPlanner {
            Text("Statistics don't apply to planners.")
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
