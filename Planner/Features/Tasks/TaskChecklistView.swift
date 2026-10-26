import SwiftUI

/// Подзадачи редактируются в документе и сохраняют свой порядок после выполнения.
struct TaskChecklistView: View {
    @Environment(\.translations) private var strings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: PlannerTask
    let service: TaskService
    let focusItemID: UUID?
    let addItem: (TaskChecklistItem?) -> Void
    @FocusState private var focusedItemID: UUID?

    private var items: [TaskChecklistItem] { task.orderedChecklistItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings["Подзадачи"]).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(strings.format("Выполнено: %d из %d", items.filter(\.isCompleted).count, items.count))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 4)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Button { service.toggleChecklistItem(item) } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .contentTransition(.opacity)
                                .font(.system(size: 17))
                                .foregroundStyle(item.isCompleted ? PlannerStyle.accent : .secondary)
                                .frame(width: 24, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(strings[item.isCompleted ? "Вернуть подзадачу в работу" : "Выполнить подзадачу"])
                        .accessibilityLabel(strings["Подзадача"] + ": " + service.checklistTitle(for: item))
                        .accessibilityValue(strings[item.isCompleted ? "Выполнено" : "Не выполнено"])
                        .accessibilityIdentifier("complete-checklist-item-\(item.id)")
                        TextField(strings["Название подзадачи"], text: Binding(
                            get: { service.checklistTitle(for: item) },
                            set: { service.renameChecklistItem(item, to: $0) }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted)
                        .focused($focusedItemID, equals: item.id)
                        .onSubmit { submit(item) }
                        .help(service.checklistTitle(for: item))
                        .accessibilityIdentifier("checklist-title-\(item.id)")
                        Button { remove(item) } label: {
                            Image(systemName: "xmark").font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(strings["Удалить подзадачу"])
                        .accessibilityLabel(strings["Удалить подзадачу"])
                    }
                    if service.checklistDrafts[item.id] != nil {
                        Button(strings["Повторить сохранение текста"]) {
                            service.renameChecklistItem(item, to: service.checklistTitle(for: item))
                        }.font(.caption)
                    }
                }
                .animation(PlannerMotion.animation(.feedback, reduceMotion: reduceMotion), value: item.isCompleted)
                .transition(.opacity)
                .id(item.id)
            }
            Button { addItem(nil) } label: {
                Label(strings["Добавить подзадачу"], systemImage: "plus")
                    .font(.system(size: 13)).padding(.vertical, 6)
            }
            .buttonStyle(.plain).foregroundStyle(PlannerStyle.accent)
        }
        .animation(PlannerMotion.animation(reduceMotion: reduceMotion), value: items.map(\.id))
        .task(id: focusItemID) {
            guard let focusItemID, items.contains(where: { $0.id == focusItemID }) else { return }
            // Сначала SwiftUI вставляет поле, затем можно передать ему клавиатурный фокус.
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedItemID = focusItemID
        }
    }

    private func submit(_ item: TaskChecklistItem) {
        let title = service.checklistTitle(for: item)
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Enter на пустом пункте завершает ввод списка, не оставляя пустую подзадачу.
            if service.deleteChecklistItem(item) { focusedItemID = nil }
        } else if service.renameChecklistItem(item, to: title) {
            addItem(item)
        }
    }

    private func remove(_ item: TaskChecklistItem) {
        let index = items.firstIndex { $0.id == item.id }
        let neighbor = index.flatMap { index in
            index + 1 < items.count ? items[index + 1].id : (index > 0 ? items[index - 1].id : nil)
        }
        let wasFocused = focusedItemID == item.id
        if service.deleteChecklistItem(item), wasFocused { focusedItemID = neighbor }
    }
}
