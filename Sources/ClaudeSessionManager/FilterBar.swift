import SwiftUI
import AppKit
import ClaudeSessionCore

/// Folder, status and search-scope filters above the sessions table. They combine with each other
/// and with the search field.
struct FilterBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            FolderChooser()

            Picker("Status:", selection: $model.filter.status) {
                ForEach(StatusFilter.allCases, id: \.self) { status in
                    Text(status.label).tag(status)
                    if status == .all { Divider() }
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Picker("Search in:", selection: $model.filter.scope) {
                ForEach(SearchScope.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            SearchField(text: $model.filter.query, prompt: model.filter.scope.prompt)
                .frame(minWidth: 180, maxWidth: 320)

            Button("Clear Preferences", action: model.clearFilters)
                .disabled(!model.filter.isActive)

            Spacer()

            Button(action: model.reload) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh (⌘R)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A button summarising the chosen folders, opening a checklist that stays open while several are ticked.
private struct FolderChooser: View {
    @EnvironmentObject private var model: AppModel
    @State private var isOpen = false
    @State private var search = ""

    private var summary: String {
        let chosen = model.filter.folders
        switch chosen.count {
        case 0: return "All folders"
        case 1: return model.folderOptions.first { $0.folder == chosen.first }?.display ?? "1 folder"
        default: return "\(chosen.count) folders"
        }
    }

    private var visibleOptions: [(folder: String, display: String, count: Int)] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.folderOptions : model.folderOptions.filter { $0.display.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Folders:")
            Button { isOpen.toggle() } label: {
                HStack(spacing: 4) {
                    Text(summary).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
            .help(model.filter.folders.sorted().joined(separator: "\n"))
            .popover(isPresented: $isOpen, arrowEdge: .bottom) { checklist }
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Filter folders", text: $search)
                .textFieldStyle(.roundedBorder)
            List(visibleOptions, id: \.folder) { option in
                Toggle(isOn: binding(for: option.folder)) {
                    HStack {
                        Text(option.display).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(option.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.plain)
            HStack {
                Text(model.filter.folders.isEmpty ? "Showing all folders" : "\(model.filter.folders.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show All Folders") { model.filter.folders = [] }
                    .disabled(model.filter.folders.isEmpty)
            }
            .font(.callout)
        }
        .padding(12)
        .frame(width: 440, height: 380)
    }

    private func binding(for folder: String) -> Binding<Bool> {
        Binding(
            get: { model.filter.folders.contains(folder) },
            set: { on in
                if on { model.filter.folders.insert(folder) } else { model.filter.folders.remove(folder) }
            }
        )
    }
}

/// AppKit's own search field, so its height, bezel and colours match the other controls in the bar.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        // The clear (×) button sends the action rather than a text-change notification.
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func searchChanged(_ field: NSSearchField) {
            if text.wrappedValue != field.stringValue { text.wrappedValue = field.stringValue }
        }
    }
}
