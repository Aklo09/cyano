import SwiftUI

/// The library selection window (screen specs, "Library selection" and "Recovery required").
struct LibrarySelectionView: View {
    @Bindable var model: LibrarySelectionModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var listFocused: Bool
    @State private var selection: String?
    @State private var showSpinner = false

    var body: some View {
        VStack(spacing: 16) {
            header
            switch model.session.phase {
            case .openFailed(let url, let message):
                FailureView(url: url, message: message, model: model)
            case .recoveryRequired(let url, let operations, let message, let retried):
                RecoveryView(url: url, operations: operations, message: message, retried: retried, model: model)
            default:
                chooser
            }
        }
        .padding(24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(isOpening)
        .background(ListedInWindowMenu())
        .onChange(of: model.windowGoal, initial: true) { _, goal in
            guard goal == .library else { return }
            openWindow(id: LibraryAppIdentity.libraryWindow)
            dismissWindow(id: LibraryAppIdentity.selectionWindow)
        }
        .task(id: isOpening) {
            showSpinner = false
            guard isOpening else { return }
            try? await Task.sleep(for: .milliseconds(500))
            showSpinner = isOpening
        }
        .confirmationDialog(
            "Create a library in “\(model.pendingCreation?.lastPathComponent ?? "")”?",
            isPresented: Binding(
                get: { model.pendingCreation != nil }, set: { if !$0 { model.pendingCreation = nil } })
        ) {
            Button("Create Library") { Task { await model.confirmCreation() } }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { model.pendingCreation = nil }
        } message: {
            Text("The folder is empty. A new library will be created in it.")
        }
        .onAppear { model.refreshRecents() }
    }

    private var isOpening: Bool {
        if case .opening = model.session.phase { return true }
        return false
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40))
                .accessibilityHidden(true)
            Text(LibraryAppIdentity.name)
                .font(.title2.weight(.semibold))
        }
    }

    @ViewBuilder private var chooser: some View {
        if model.recents.isEmpty {
            Text("Open an existing library or create a new one in an empty folder.")
                .multilineTextAlignment(.center)
        } else {
            List(model.recents, selection: $selection) { row in
                RecentRowView(row: row, opening: openingPath == row.library.path && showSpinner)
                    .contextMenu {
                        Button("Remove from Recents") { model.removeRecent(row) }
                    }
            }
            .focused($listFocused)
            .frame(height: 220)
            .onKeyPress(.return) {
                openSelected()
                return .handled
            }
            .onDeleteCommand {
                if let row = selectedRow { model.removeRecent(row) }
            }
            .contextMenu(forSelectionType: String.self) { _ in
            } primaryAction: { _ in
                openSelected()
            }
            .accessibilityLabel("Recent libraries")
        }
        HStack {
            if showSpinner, openingPath == nil {
                ProgressView().controlSize(.small)
                Text("Opening…")
            }
            Spacer()
            Button("New Library…") { Task { await newLibrary() } }
            Button("Open Library…") { Task { await openLibrary() } }
                .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            listFocused = !model.recents.isEmpty
            selection = selection ?? model.recents.first?.id
        }
    }

    private var openingPath: String? {
        if case .opening(let url) = model.session.phase { return RecentLibraryStore.normalizedPath(url) }
        return nil
    }

    private var selectedRow: LibrarySelectionModel.RecentRow? {
        model.recents.first { $0.id == selection }
    }

    private func openSelected() {
        guard let row = selectedRow, row.available else { return }
        Task { await model.openRecent(row) }
    }

    private func openLibrary() async {
        guard let url = await LibraryPanels.chooseLibrary() else { return }
        await model.chooseFolderToOpen(url)
    }

    private func newLibrary() async {
        guard let url = await LibraryPanels.chooseEmptyFolder() else { return }
        await model.chooseFolderToCreate(url)
    }
}

private struct RecentRowView: View {
    let row: LibrarySelectionModel.RecentRow
    let opening: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.library.name).font(.body.weight(.medium))
                Text(row.library.path).font(.caption).truncationMode(.middle).lineLimit(1)
                Text("Last opened \(row.library.lastOpened.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
            }
            Spacer()
            if opening {
                ProgressView().controlSize(.small)
                Text("Opening…").font(.caption)
            } else if !row.available {
                Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct FailureView: View {
    let url: URL
    let message: LibraryMessage
    let model: LibrarySelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MessageView(message: message)
            HStack {
                Spacer()
                Button("Back") { model.back() }
                    .keyboardShortcut(.cancelAction)
                if message.code == "LIBRARY_IN_USE" || message.code == "FILESYSTEM_ERROR" {
                    Button("Try Again") { Task { await model.tryAgain() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

private struct RecoveryView: View {
    let url: URL
    let operations: [LibrarySession.PendingOperation]
    let message: LibraryMessage
    let retried: Bool
    let model: LibrarySelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("“\(url.lastPathComponent)” needs recovery")
                .font(.headline)
            Text(
                "An interrupted change couldn't be completed automatically. Recover tries again. If it still fails, "
                    + "set the change aside with the command below in Terminal, then choose Try Again."
            )
            .fixedSize(horizontal: false, vertical: true)
            if retried {
                Label(
                    "Recovery couldn't complete the change. Nothing was moved or deleted.",
                    systemImage: "xmark.octagon.fill"
                )
                .symbolRenderingMode(.multicolor)
            }
            ForEach(operations, id: \.id) { operation in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(LibrarySession.describeKind(operation.kind).capitalized) · \(operation.id)")
                        .font(.caption)
                    HStack(alignment: .top) {
                        Text(operation.quarantineCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Copy Command") { LibraryPanels.copy(operation.quarantineCommand) }
                    }
                }
            }
            DisclosureGroup("Details") {
                Text(([message.code].compactMap { $0 } + [message.technical]).joined(separator: "\n"))
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Back") { model.back() }
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { Task { await model.tryAgain() } }
                Button("Recover") { Task { await model.tryAgain() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// A message's title, guidance, and collapsed Details (screen specs, "Messages").
struct MessageView: View {
    let message: LibraryMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message.title, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.headline)
            Text(message.guidance)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Details") {
                Text(([message.code].compactMap { $0 } + [message.technical]).joined(separator: "\n"))
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
