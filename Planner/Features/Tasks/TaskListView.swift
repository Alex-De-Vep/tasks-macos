import SwiftUI
import PlannerLocalization

struct TaskListView: View {
    @Environment(\.translations) private var strings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedID: UUID?
    let search: String
    let filter: TaskFilter
    let snapshot: TaskListSnapshot
    let now: Date
    let create: () -> Void
    let toggleToday: (PlannerTask) -> Void
    let toggleCompleted: (PlannerTask) -> Void
    let delete: (PlannerTask) -> Void
    let deleteImmediately: (PlannerTask) -> Void

    @State private var isCompletedExpanded = false
    @State private var displayedScope: Scope?
    @FocusState private var focusedList: ListArea?

    private enum ListArea: Hashable { case active, completed }
    private struct Scope: Equatable {
        let filter: TaskFilter
        let search: String
    }
    private struct Rows: Equatable {
        let active: [UUID]
        let completed: [UUID]
    }
    private var scope: Scope { Scope(filter: filter, search: search) }
    private var rowIDs: Rows {
        Rows(active: snapshot.activeTasks.map(\.id), completed: snapshot.completedTasks.map(\.id))
    }
    private var rowAnimation: Animation? {
        // Поиск и переход между папками не должны анимировать каждую строку как удалённую задачу.
        displayedScope == scope ? PlannerMotion.animation(reduceMotion: reduceMotion) : nil
    }
    private var tasks: [PlannerTask] { snapshot.tasks }
    private var selectedActiveID: UUID? {
        snapshot.activeTasks.first { $0.id == selectedID }?.id
    }
    private var selectedCompletedID: UUID? {
        snapshot.completedTasks.first { $0.id == selectedID }?.id
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    // List сохраняет свою идентичность и анимирует даже удаление последней строки.
                    activeList.frame(maxHeight: .infinity)
                    if !snapshot.completedTasks.isEmpty {
                        completedPanel(availableHeight: geometry.size.height)
                            .transition(.opacity)
                    }
                }
                if tasks.isEmpty { emptyState.transition(.opacity) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PlannerStyle.listBackground)
        .animation(rowAnimation, value: rowIDs)
        .onChange(of: scope, initial: true) { _, value in displayedScope = value }
        // Открытая задача остаётся видимой после выполнения или перехода в другую папку.
        .task(id: selectedCompletedID) {
            guard let id = selectedCompletedID else { return }
            // SwiftData может временно выбрать выполненную строку во время сохранения удаления.
            // Раскрываем панель только после согласования окончательного выбора, без задержки данных.
            await Task.yield()
            guard !Task.isCancelled, selectedID == id else { return }
            isCompletedExpanded = true
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(search.isEmpty ? strings["Пока нет задач"] : strings["Ничего не найдено"], systemImage: search.isEmpty ? filter.symbol : "magnifyingglass")
        } description: {
            Text(!search.isEmpty ? strings["Попробуйте другое название."] : filter == .today ? strings["Добавляйте задачи на сегодня с помощью звёздочки."] : strings["Создайте первую задачу в этом разделе."])
        } actions: {
            if search.isEmpty { Button(strings["Создать задачу"], action: create).accessibilityIdentifier("empty-create-task-button") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeList: some View {
        ScrollViewReader { proxy in
            List(selection: selection(in: snapshot.activeTasks, area: .active)) {
                ForEach(snapshot.activeSections) { section in
                    if let title = section.title(using: strings) {
                        Section {
                            rows(section.tasks)
                        } header: {
                            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    } else {
                        rows(section.tasks)
                    }
                }
            }
            .modifier(TaskListAppearance())
            .focused($focusedList, equals: .active)
            // Delete и Forward Delete действуют только в списке с фокусом, а не в редакторе задачи.
            .onDeleteCommand(perform: deleteSelection(in: snapshot.activeTasks))
            .accessibilityIdentifier("task-list")
            .onChange(of: selectedActiveID, initial: true) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            // Стрелки продолжают навигацию через границу двух областей списка.
            .onKeyPress(.downArrow) {
                guard selectedID == snapshot.activeTasks.last?.id,
                      let first = snapshot.completedTasks.first else { return .ignored }
                withImmediateNavigationUpdate {
                    isCompletedExpanded = true
                    selectedID = first.id
                    focusedList = .completed
                }
                return .handled
            }
        }
    }

    private func completedPanel(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                // Сворачивание не закрывает задачу, уже открытую в правой колонке.
                isCompletedExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).frame(width: 12)
                        .rotationEffect(.degrees(isCompletedExpanded ? 90 : 0))
                    Text(strings["Выполнено"]).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(snapshot.completedTasks.count.formatted()).font(.system(size: 11)).monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18).frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings[isCompletedExpanded ? "Свернуть выполненные задачи" : "Показать выполненные задачи"])
            .accessibilityValue(strings[isCompletedExpanded ? "Развернуто" : "Свернуто"])
            .accessibilityIdentifier("completed-disclosure-button")

            if isCompletedExpanded {
                completedList.frame(height: completedListHeight(availableHeight: availableHeight))
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(PlannerMotion.animation(reduceMotion: reduceMotion), value: isCompletedExpanded)
        .accessibilityIdentifier("completed-tasks-panel")
    }

    private var completedList: some View {
        ScrollViewReader { proxy in
            // В список передаются все выполненные задачи текущего фильтра и поиска, без ограничения количества.
            List(selection: selection(in: snapshot.completedTasks, area: .completed)) {
                rows(snapshot.completedTasks)
            }
            .modifier(TaskListAppearance())
            .focused($focusedList, equals: .completed)
            .onDeleteCommand(perform: deleteSelection(in: snapshot.completedTasks))
            .accessibilityIdentifier("completed-task-list")
            .onChange(of: selectedCompletedID, initial: true) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .onKeyPress(.upArrow) {
                guard selectedID == snapshot.completedTasks.first?.id,
                      let last = snapshot.activeTasks.last else { return .ignored }
                selectedID = last.id
                focusedList = .active
                return .handled
            }
        }
    }

    @ViewBuilder
    private func rows(_ tasks: [PlannerTask]) -> some View {
        ForEach(tasks) { task in
            TaskRow(task: TaskRowContent(task, now: now, strings: strings), now: now, toggleToday: { toggleToday(task) },
                    toggleCompleted: { toggleCompleted(task) })
                .tag(task.id)
                .id(task.id)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.visible, edges: .bottom)
                .contextMenu {
                    Button(task.isFocused(on: now) ? strings["Убрать из «Сегодня»"] : strings["На сегодня"]) { toggleToday(task) }
                    Button(strings["Удалить задачу…"], role: .destructive) { delete(task) }
                }
        }
    }

    private func deleteSelection(in tasks: [PlannerTask]) -> (() -> Void)? {
        // Без выделения команда отключена. Клавиша удаляет сразу; меню запрашивает подтверждение отдельно.
        guard let task = tasks.first(where: { $0.id == selectedID }) else { return nil }
        return { deleteImmediately(task) }
    }

    private func selection(in tasks: [PlannerTask], area: ListArea) -> Binding<UUID?> {
        let ids = Set(tasks.map(\.id))
        return Binding(get: {
            selectedID.flatMap { ids.contains($0) ? $0 : nil }
        }, set: { id in
            // Две области используют один выбор. Снятие выделения старым List не сбрасывает новый выбор.
            // Исчезающий при сворачивании список также не должен повторно выбирать свою строку.
            guard area != .completed || isCompletedExpanded else { return }
            if let id, ids.contains(id) { selectedID = id }
        })
    }

    private func completedListHeight(availableHeight: CGFloat) -> CGFloat {
        // Короткий список прилегает к низу; длинный прокручивается, оставляя место активным задачам.
        let available = max(0, availableHeight - 39)
        let limit = snapshot.activeTasks.isEmpty ? available : available * 0.45
        let rowsHeight = snapshot.completedTasks.reduce(CGFloat(0)) { $0 + ($1.deadline == nil ? 76 : 100) }
        return min(rowsHeight + 12, limit)
    }
}

/// Нативный inset-список даёт отступы и скруглённое выделение без дополнительной заливки строк.
private struct TaskListAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
    }
}

/// Уходящая строка может оставаться на экране до конца перехода после удаления SwiftData-модели.
/// Для её отрисовки нужны только значения, а не доступ к уже удалённым связям модели.
struct TaskRowContent {
    let id: UUID
    let title: String
    let createdAt: Date
    let folderName: String
    let isCompleted: Bool
    let isFocused: Bool
    let deadline: TaskDeadline?

    init(_ task: PlannerTask, now: Date, strings: Translations) {
        id = task.id
        title = task.displayTitle(using: strings)
        createdAt = task.createdAt
        folderName = task.folder?.name ?? strings["Входящие"]
        isCompleted = task.isCompleted
        isFocused = task.isFocused(on: now)
        deadline = task.deadline
    }
}

private struct TaskRow: View {
    @Environment(\.translations) private var strings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: TaskRowContent
    let now: Date
    let toggleToday: () -> Void
    let toggleCompleted: () -> Void

    private var completionTitle: String {
        strings[task.isCompleted ? "Вернуть в работу" : "Отметить выполненной"]
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                HStack(spacing: 5) {
                    if task.isCompleted { Label(strings["Выполнено"], systemImage: "checkmark") }
                    else {
                        Text(task.createdAt, format: .dateTime.day().month(.twoDigits))
                        Text(task.folderName).lineLimit(1)
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                if let deadline = task.deadline {
                    TaskDeadlineTag(deadline: deadline, now: now, isCompleted: task.isCompleted)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggleCompleted) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    .contentTransition(.opacity)
                    .font(.system(size: 15))
                    .foregroundStyle(task.isCompleted ? Color.green : Color.primary)
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(completionTitle)
            .accessibilityLabel(completionTitle + ": " + task.title)
            .accessibilityValue(strings[task.isCompleted ? "Выполнено" : "Не выполнено"])
            .accessibilityIdentifier("task-complete-\(task.id)")
            Button(action: toggleToday) {
                Image(systemName: task.isFocused ? "star.fill" : "star")
                    .contentTransition(.opacity)
                    .font(.system(size: 15))
                    // Цвет звезды отражает отметку «Сегодня» и не зависит от выделения строки.
                    .foregroundStyle(task.isFocused ? Color.yellow : Color.white)
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(task.isFocused ? strings["Убрать из «Сегодня»"] : strings["На сегодня"])
            .accessibilityLabel(strings["На сегодня"] + ": " + task.title)
            .accessibilityValue(strings[task.isFocused ? "Включено" : "Выключено"])
            .accessibilityIdentifier("task-star-\(task.id)")
        }
        .frame(minHeight: 54)
        .padding(.vertical, 4)
        .animation(PlannerMotion.animation(.feedback, reduceMotion: reduceMotion), value: task.isFocused)
        .animation(PlannerMotion.animation(.feedback, reduceMotion: reduceMotion), value: task.isCompleted)
        .animation(PlannerMotion.animation(reduceMotion: reduceMotion), value: task.deadline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row-\(task.id)")
    }
}
