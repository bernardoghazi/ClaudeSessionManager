import SwiftUI
import ClaudeSessionCore

/// Folder, status and search-scope filters above the sessions table. They combine with each other
/// and with the search field.
struct FilterBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Picker("Folder:", selection: $model.filter.folder) {
                Text("All folders").tag(String?.none)
                Divider()
                ForEach(model.folderOptions, id: \.folder) { option in
                    Text("\(option.display)  (\(option.count))").tag(Optional(option.folder))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 420)

            Picker("Status:", selection: $model.filter.status) {
                ForEach(StatusFilter.allCases, id: \.self) { status in
                    Text("\(status.label)  (\(model.count(of: status)))").tag(status)
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

            Spacer()

            Button("Clear Filters", action: model.clearFilters)
                .disabled(!model.filter.isActive)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
