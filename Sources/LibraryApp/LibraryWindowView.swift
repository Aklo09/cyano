import SwiftUI

/// The main library window. Browsing arrives with A6; this shows the open library and its notices.
struct LibraryWindowView: View {
    @Bindable var model: LibrarySelectionModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var launched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let notice = model.session.completedNotice {
                HStack(alignment: .firstTextBaseline) {
                    Label(notice, systemImage: "info.circle")
                    Spacer()
                    Button("Dismiss") { model.session.dismissCompletedNotice() }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            switch model.session.phase {
            case .open(let url):
                Text(url.lastPathComponent).font(.title2.weight(.semibold))
                if let listing = model.session.listing {
                    Text(
                        "\(listing.items.count) items in \(listing.folders.count) folders. Browsing comes in a later "
                            + "build.")
                }
            default:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Opening library…")
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420, alignment: .topLeading)
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
