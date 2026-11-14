import SwiftUI

/// The main library window: folder sidebar, path bar, item list, and inspector (screen specs, "Main window").
struct LibraryWindowView: View {
    @Bindable var model: LibrarySelectionModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var launched = false
    @State private var showInspector = true
    @FocusState private var searchFocused: Bool

    private var browser: LibraryBrowserModel { model.browser }

    var body: some View {
        NavigationSplitView {
            FolderSidebar(browser: browser)
        } detail: {
            VStack(spacing: 0) {
                banners
                PathBar(browser: browser)
                Divider()
                ItemList(browser: browser)
            }
            .background(Color.contentBackground)
        }
        .inspector(isPresented: $showInspector) {
            ItemInspector(browser: browser, previews: model.previews, assetsRevision: model.assets.revision)
        }
        .searchable(text: Bindable(browser).filterText, placement: .toolbar, prompt: "Search item names")
        .searchFocused($searchFocused)
        .onChange(of: browser.searchFocusRequested) { _, requested in
            guard requested else { return }
            searchFocused = true
            browser.searchFocusRequested = false
        }
        .onChange(of: model.session.revision, initial: true) { browser.listingChanged() }
        .onChange(of: model.session.libraryURL) { browser.listingChanged() }
        .sheet(isPresented: Bindable(browser).showingIssues) { ListingIssuesSheet(browser: browser) }
        .sheet(
            isPresented: Binding(get: { browser.importSheet != nil }, set: { if !$0 { browser.importSheet = nil } })
        ) {
            if let sheet = browser.importSheet {
                ImportSheet(
                    model: sheet,
                    folders: browser.listing?.folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                        ?? [],
                    onImport: { Task { await browser.runImport() } }, onCancel: { browser.importSheet = nil })
            }
        }
        .sheet(
            isPresented: Binding(get: { browser.importSummary != nil }, set: { if !$0 { browser.importSummary = nil } })
        ) {
            if let summary = browser.importSummary {
                ImportSummarySheet(
                    imported: summary.imported, total: summary.total, failures: summary.failures,
                    onDone: { browser.importSummary = nil })
            }
        }
        .overlay(alignment: .bottom) {
            if let confirmation = browser.confirmation {
                Text(confirmation)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)
            }
        }
        .alert(
            browser.exportFailure?.title ?? "",
            isPresented: Binding(
                get: { browser.exportFailure != nil }, set: { if !$0 { browser.exportFailure = nil } }),
            presenting: browser.exportFailure
        ) { _ in
            Button("OK") { browser.exportFailure = nil }
        } message: { message in
            Text(message.guidance)
        }
        .sheet(
            isPresented: Binding(get: { browser.moveSheetRows != nil }, set: { if !$0 { browser.moveSheetRows = nil } })
        ) {
            if let rows = browser.moveSheetRows { MoveToSheet(browser: browser, rows: rows) }
        }
        .sheet(
            isPresented: Binding(get: { browser.replaceSheet != nil }, set: { if !$0 { browser.replaceSheet = nil } })
        ) {
            if let sheet = browser.replaceSheet {
                ReplaceSheet(
                    model: sheet, onReplace: { Task { await browser.runReplace() } },
                    onCancel: { browser.replaceSheet = nil })
            }
        }
        .alert(
            browser.pendingDeletion?.title ?? "",
            isPresented: Binding(
                get: { browser.pendingDeletion != nil }, set: { if !$0 { browser.pendingDeletion = nil } }),
            presenting: browser.pendingDeletion
        ) { pending in
            Button(pending.actionTitle, role: .destructive) { Task { await browser.confirmDelete(pending) } }
            Button("Cancel", role: .cancel) { browser.pendingDeletion = nil }
                .keyboardShortcut(.defaultAction)
        } message: { pending in
            Text(pending.message)
        }
        .alert(
            browser.organizeFailure?.title ?? "",
            isPresented: Binding(
                get: { browser.organizeFailure != nil }, set: { if !$0 { browser.organizeFailure = nil } }),
            presenting: browser.organizeFailure
        ) { _ in
            Button("OK") { browser.organizeFailure = nil }
        } message: { message in
            Text(message.guidance)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    browser.beginImport()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import a blueprint string or TXT files (⇧⌘I)")
                .disabled(model.session.libraryURL == nil || model.session.requiresRecovery)
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .navigationTitle(model.session.libraryURL?.lastPathComponent ?? LibraryAppIdentity.name)
        .task {
            guard !launched else { return }
            launched = true
            if model.session.libraryURL == nil, case .closed = model.session.phase { await model.launch() }
        }
        .onChange(of: model.windowGoal, initial: true) { _, goal in
            guard goal == .selection else { return }
            model.willDismissLibraryWindow()
            openWindow(id: LibraryAppIdentity.selectionWindow)
            dismissWindow(id: LibraryAppIdentity.libraryWindow)
        }
        .onDisappear {
            let openSelection = openWindow
            Task {
                if await model.libraryWindowDisappeared() {
                    openSelection(id: LibraryAppIdentity.selectionWindow)
                }
                model.didDismissLibraryWindow()
            }
        }
    }
}

extension LibraryWindowView {
    @ViewBuilder fileprivate var banners: some View {
        if let notice = model.session.completedNotice {
            Banner(text: notice, symbol: "info.circle", action: "Dismiss") {
                model.session.dismissCompletedNotice()
            }
        }
        if model.session.requiresRecovery {
            Banner(
                text: model.session.recoveryFailure == nil
                    ? "A change failed and the library needs recovery. Recover to continue."
                    : "Recovery couldn't complete the change.",
                symbol: "xmark.octagon.fill",
                action: model.session.recoveryFailure == nil ? "Recover" : "Close Library"
            ) {
                Task {
                    if model.session.recoveryFailure == nil {
                        await model.session.recover()
                    } else {
                        await model.closeLibrary()
                    }
                }
            }
        }
        if let failure = model.session.listingFailure, model.session.listing != nil {
            Banner(text: "\(failure.title). \(failure.guidance)", symbol: "exclamationmark.triangle.fill", action: nil)
            {}
        }
    }
}

/// A one-line notice across the top of the item list.
private struct Banner: View {
    let text: String
    let symbol: String
    let action: String?
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(text, systemImage: symbol).symbolRenderingMode(.multicolor)
            Spacer()
            if let action { Button(action, action: perform) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
    }
}
