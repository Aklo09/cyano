import AppKit
import SwiftUI

/// Settings › Assets (screen specs, "Settings"; spec SET-1 to SET-6).
struct SettingsView: View {
    @Bindable var model: LibrarySelectionModel
    @FocusState private var chooseFocused: Bool

    private var assets: AssetSettings { model.assets }

    var body: some View {
        Form {
            Section {
                LabeledContent("Asset release") {
                    Text(path ?? "None")
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                status
                if let failure = assets.choiceFailure {
                    MessageView(message: failure)
                }
                HStack {
                    if assets.candidate != nil {
                        ProgressView().controlSize(.small)
                        Text("Verifying…")
                        Button("Cancel") { assets.cancelChoice() }
                    }
                    Spacer()
                    Button("Clear") { assets.clear() }
                        .disabled(assets.state == .none || assets.candidate != nil)
                    Button("Choose…") { Task { await choose() } }
                        .keyboardShortcut(.defaultAction)
                        .focused($chooseFocused)
                        .disabled(assets.candidate != nil)
                }
            } footer: {
                Text("Previews and statistics need a verified asset release. Everything else works without one.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 520)
        .padding(.vertical, 8)
        .onAppear { chooseFocused = true }
    }

    private var path: String? {
        switch assets.state {
        case .none: nil
        case .checking(let url), .verified(let url, _, _, _), .problem(let url, _): url.path
        }
    }

    @ViewBuilder private var status: some View {
        switch assets.state {
        case .none:
            Text("No asset release is configured. Previews and statistics are unavailable; everything else works.")
                .fixedSize(horizontal: false, vertical: true)
        case .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking…")
            }
        case .verified(_, let name, let gameVersion, _):
            Label("Verified: \(name), Factorio \(gameVersion)", systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
        case .problem(_, let message):
            Label("\(message.title). \(message.guidance)", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choose() async {
        let panel = NSOpenPanel()
        panel.title = "Choose an Asset Release"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let url: URL? = await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
        guard let url else { return }
        await assets.choose(url, library: model.session.libraryURL)
    }
}
