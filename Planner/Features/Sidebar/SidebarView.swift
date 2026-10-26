import SwiftUI

/// Системные разделы и пользовательские папки используют одинаковые строки и счётчики.
struct SidebarView: View {
    @Environment(\.translations) private var strings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: TaskFilter?
    let folders: [TaskFolder]
    let tasks: [PlannerTask]
    let now: Date
    let renameFolder: (TaskFolder) -> Void
    let deleteFolder: (TaskFolder) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section(strings["Задачи"]) {
                    ForEach(TaskFilter.smartFilters) { filter in
                        row(filter).tag(filter)
                            .accessibilityIdentifier("sidebar-\(filter.id)")
                    }
                }
                Section(strings["Мои папки"]) {
                    if folders.isEmpty {
                        Text(strings["Создайте свою первую папку"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                    ForEach(folders) { folder in
                        row(.folder(folder.id)).tag(TaskFilter.folder(folder.id))
                            .accessibilityIdentifier("folder-row-\(folder.name)")
                            .contextMenu {
                                Button(strings["Переименовать"]) { renameFolder(folder) }
                                Button(strings["Удалить папку…"], role: .destructive) { deleteFolder(folder) }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            // Стекло рисует полноразмерный NSSplitViewItem, а не отдельная область внутри списка.
            .scrollContentBackground(.hidden)
            .listItemTint(.monochrome)
            .animation(PlannerMotion.animation(reduceMotion: reduceMotion), value: folders.map(\.id))
            .accessibilityIdentifier("sidebar-list")
            HStack {
                SettingsLink { Label(strings["Настройки"], systemImage: "gearshape") }
                    .labelStyle(SidebarRowLabelStyle())
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(strings["Настройки"])
                    .accessibilityLabel(strings["Настройки"])
                    .accessibilityIdentifier("settings-button")
                Spacer()
            }
            .padding(16)
        }
    }

    private func row(_ filter: TaskFilter) -> some View {
        let count = tasks.filter { !$0.isCompleted && filter.matches($0, now: now) }.count
        // Семантический цвет становится белым вместе с системным выделением строки.
        return HStack(spacing: 6) {
            Label(filter.title(in: folders, using: strings), systemImage: filter.symbol)
                .labelStyle(SidebarRowLabelStyle())
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text(count.formatted()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(count)))
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 3)
        .foregroundStyle(.primary)
        .animation(PlannerMotion.animation(.feedback, reduceMotion: reduceMotion), value: count)
    }
}

/// Одинаковый размер значков и компактный отступ до текста во всех строках левой панели.
private struct SidebarRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 17, weight: .regular))
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
                .frame(width: 20)
            configuration.title
        }
    }
}
