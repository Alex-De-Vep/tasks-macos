import SwiftUI

/// Меню открытой задачи в панели инструментов: перенос, планирование и удаление с подтверждением.
struct TaskActionsMenu: View {
    @Environment(\.translations) private var strings
    let task: PlannerTask
    let folders: [TaskFolder]
    let service: TaskService
    let delete: () -> Void

    var body: some View {
        Menu {
            Menu(strings["Переместить в папку"]) {
                Button(strings["Входящие"]) { service.move(task, to: nil) }
                ForEach(folders) { folder in
                    Button(folder.name) { service.move(task, to: folder) }
                }
            }
            Menu(strings["Запланировать"]) {
                ForEach(PlanningPeriod.allCases) { period in
                    Button(period.title(using: strings)) { service.plan(task, for: period) }
                }
                Divider()
                Button(strings["Убрать период"]) { service.plan(task, for: nil) }
            }
            Divider()
            Button(strings["Удалить задачу…"], role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17))
                .frame(width: WorkspaceToolbarButtonSurface.diameter, height: WorkspaceToolbarButtonSurface.diameter)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .buttonBorderShape(.circle)
        .frame(width: WorkspaceToolbarButtonSurface.diameter, height: WorkspaceToolbarButtonSurface.diameter)
        .contentShape(Circle())
        .help(strings["Действия с задачей"])
        .accessibilityLabel(strings["Действия с задачей"])
        .accessibilityIdentifier("task-actions-menu")
    }
}
