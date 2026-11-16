import AppKit
import FactorioData
import PreviewRenderer
import SwiftUI

/// The inspector's Statistics tab (screen specs, "Statistics tab"; STA-1 to STA-6).
struct StatisticsTab: View {
    let browser: LibraryBrowserModel
    let model: StatisticsModel
    let assetsRevision: Int
    @Environment(\.openSettings) private var openSettings

    private struct Key: Equatable {
        let target: StatisticsTarget?
        let revision: Int
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: Key(target: browser.statisticsTarget, revision: assetsRevision)) {
                await model.show(browser.statisticsTarget)
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .none:
            Color.clear
        case .notApplicable(let kind):
            message(
                kind == .book
                    ? "Statistics don't apply to books. Open the book to see its blueprints."
                    : "Statistics don't apply to planners.")
        case .noAssets:
            message("Statistics need the game data from an asset release.", settings: true)
        case .assetsUnusable(let problem):
            message("The asset release can't be used: \(problem.title). \(problem.guidance)", settings: true)
        case .mapUnsuitable:
            message("The selected asset release can't provide statistics.", settings: true)
        case .calculating:
            CalculatingView()
        case .failed(let failure):
            message("\(failure.title). \(failure.guidance)")
        case .ready(let statistics, let inventory):
            StatisticsList(presentation: StatisticsPresentation(statistics, inventory: inventory))
        }
    }

    /// A message in a scroll view, like the Details tab: a fixed-size message here made the inspector ask for more
    /// height than the window had, which pushed the whole window's content up.
    private func message(_ text: String, settings: Bool = false) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                if settings { Button("Open Settings…") { openSettings() } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

/// An item or quality icon at text height in a Statistics row, or nothing when the release has none (ICN-9).
private struct StatisticsIcon: View {
    let reference: IconReference?
    @Environment(\.iconCatalog) private var catalog
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16

    var body: some View {
        if let reference, let image = catalog?.image(for: reference) {
            Image(decorative: image, scale: 1).resizable().interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// A quality other than normal: its icon alone, named for VoiceOver and in a tooltip, or its name when the release
/// has no icon for it (ICN-9).
private struct StatisticsQuality: View {
    let quality: String
    @Environment(\.iconCatalog) private var catalog
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16

    var body: some View {
        if let reference = IconReference(tagKind: "quality", name: quality),
            let image = catalog?.image(for: reference)
        {
            Image(decorative: image, scale: 1).resizable().interpolation(.high)
                .frame(width: size, height: size)
                .help(quality)
                .accessibilityLabel(quality)
        } else {
            // Hierarchy by size, not lighter text (screen specs, "Color and contrast").
            Text(quality).font(.callout)
        }
    }
}

/// "Calculating…" with a spinner, shown only after 0.5 s so quick results never flash it.
private struct CalculatingView: View {
    @State private var visible = false

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Calculating…")
        }
        .padding(16)
        .opacity(visible ? 1 : 0)
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            visible = true
        }
    }
}

/// Counts, footprint, items by inventory tab, and warnings; rows can be selected and copied as text.
private struct StatisticsList: View {
    let presentation: StatisticsPresentation
    @State private var selection: Set<String> = []

    var body: some View {
        List(selection: $selection) {
            Section {
                if presentation.isEmpty {
                    Text("This blueprint has no entities or tiles.")
                }
                Text(counts)
                Text(footprint)
                if !presentation.requirementsComplete {
                    Label(
                        "Requirements incomplete: some items are missing from these totals.",
                        systemImage: "exclamationmark.triangle")
                }
            }
            .selectionDisabled()
            ForEach(presentation.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        HStack(alignment: .center, spacing: 4) {
                            // Icons from the release before the item and its quality; names stay text (ICN-9).
                            StatisticsIcon(reference: IconReference(signalType: nil, name: row.name))
                            Text(row.name)
                            if let quality = row.quality { StatisticsQuality(quality: quality) }
                            Spacer()
                            Text(row.count, format: .number).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .tag(row.id)
                    }
                } header: {
                    if let note = group.note {
                        Text("\(group.title) (\(note))")
                    } else {
                        Text(group.title)
                    }
                }
            }
            if !presentation.warnings.isEmpty {
                Section("Warnings") {
                    ForEach(presentation.warnings) { warning in
                        Text("\(warning.count.formatted()) × \(warning.text)")
                            .fixedSize(horizontal: false, vertical: true)
                            .tag(warning.id)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onCopyCommand {
            let text = presentation.copyText(rows: selection)
            return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
        }
        .accessibilityLabel("Statistics")
    }

    private var counts: String {
        let entities = presentation.entities.formatted()
        let tiles = presentation.tiles.formatted()
        return "\(entities) \(presentation.entities == 1 ? "entity" : "entities"), "
            + "\(tiles) \(presentation.tiles == 1 ? "tile" : "tiles")"
    }

    private var footprint: String {
        func size(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
        switch presentation.footprint {
        case .complete(let width, let height): return "Footprint \(size(width)) × \(size(height)) tiles"
        case .incomplete(let width, let height):
            return "Footprint incomplete, at least \(size(width)) × \(size(height)) tiles"
        case .unknown: return "Footprint incomplete"
        }
    }
}
