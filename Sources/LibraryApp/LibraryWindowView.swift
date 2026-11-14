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
            ItemInspector(browser: browser)
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
