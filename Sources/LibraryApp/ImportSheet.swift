import AppKit
import SwiftUI

/// The Import sheet (screen specs, "Import"; spec IMP-1 to IMP-12).
struct ImportSheet: View {
    @Bindable var model: ImportModel
    let folders: [String]
    let onImport: () -> Void
    let onCancel: () -> Void
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import").font(.title2.weight(.semibold))
            Picker("Source", selection: $model.source) {
                Text("Paste").tag(ImportModel.Source.paste)
                Text("Files").tag(ImportModel.Source.files)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            switch model.source {
            case .paste: pasteSource
            case .files: fileSource
            }

            Form {
                if model.acceptsName {
                    TextField("Name (optional)", text: $model.name)
                }
                Picker("Save in", selection: $model.destination) {
                    Text("Library").tag("")
                    ForEach(folders, id: \.self) { folder in Text(folder).tag(folder) }
                }
                Picker("Books", selection: $model.mode) {
                    Text("Save as one book").tag(ImportModel.Mode.oneBook)
                    Text("Unpack book into folders").tag(ImportModel.Mode.unpack)
                }
                .pickerStyle(.radioGroup)
                if model.mode == .unpack {
                    Text(
                        "Each blueprint is saved as a new string; the book's original string isn't kept unless you "
                            + "also save it as one book."
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.columns)

            if let failure = model.failure {
                MessageView(message: failure)
            }

            HStack {
                if model.importing {
                    ProgressView().controlSize(.small)
                    Text("Importing…")
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(model.importTitle, action: onImport)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.blocker != nil)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Color.contentBackground)
        .disabled(model.importing)
        .task(id: model.text) {
            try? await Task.sleep(for: .milliseconds(200))
            await model.analyze()
        }
        .onAppear { textFocused = model.source == .paste }
    }

    private var pasteSource: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Blueprint string").font(.headline)
            TextEditor(text: $model.text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 140)
                .focused($textFocused)
                .accessibilityLabel("Blueprint string")
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            status
        }
    }

    @ViewBuilder private var status: some View {
        switch model.analysis {
        case .empty:
            Text("Paste a blueprint string or choose TXT files.")
        case .checking:
            Text("Checking…")
        case .valid(let kind, let entries, _):
            if model.mode == .unpack && kind != .book {
                Label("Only books can be unpacked.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            } else {
                Label(
                    entries.map { "\(kind.label) · \($0) \($0 == 1 ? "entry" : "entries")" } ?? kind.label,
                    systemImage: kind.symbol)
            }
        case .invalid(let message):
            Label(message.title, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
        }
    }

    private var fileSource: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.files.isEmpty {
                Text("Choose TXT files, or drag them onto the library window.")
            } else {
                ForEach(model.files, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "doc.text")
                }
            }
            Button("Choose Files…") {
                Task { if let urls = await Self.chooseFiles() { model.setFiles(urls) } }
            }
        }
    }

    static func chooseFiles() async -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "Import Blueprint Files"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.urls : nil) }
        }
    }
}

/// "Imported 4 of 5 files" with each failure (IMP-3).
struct ImportSummarySheet: View {
    let imported: Int
    let total: Int
    let failures: [(name: String, reason: String)]
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Imported \(imported) of \(total) files").font(.headline)
            ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                Label("\(failure.name): \(failure.reason)", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
            HStack {
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
