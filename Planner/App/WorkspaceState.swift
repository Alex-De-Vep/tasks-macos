import SwiftUI
import Observation

/// Навигация обновляется атомарно. Локальные переходы строк задаются их представлениями.
@MainActor
func withImmediateNavigationUpdate(_ update: () -> Void) {
    withTransaction(Transaction(animation: nil), update)
}

/// Состояние принадлежит окну; методы меняют связанные значения одновременно.
@MainActor @Observable
final class WorkspaceState {
    private(set) var filter: TaskFilter? = .inbox
    private(set) var selectedTaskID: UUID?
    private(set) var search = ""
    private(set) var createdTaskID: UUID?

    func selectFilter(_ filter: TaskFilter, visibleIDs: [UUID]) {
        guard self.filter != filter else { return }
        withImmediateNavigationUpdate {
            self.filter = filter
            search = ""
            createdTaskID = nil
            selectedTaskID = visibleIDs.first
        }
    }

    func updateSearch(_ search: String, visibleIDs: [UUID]) {
        withImmediateNavigationUpdate {
            self.search = search
            if !visibleIDs.contains(where: { $0 == selectedTaskID }) {
                selectedTaskID = visibleIDs.first
                createdTaskID = nil
            }
        }
    }

    func selectTask(_ id: UUID?) {
        guard selectedTaskID != id else { return }
        withImmediateNavigationUpdate {
            selectedTaskID = id
            createdTaskID = nil
        }
    }

    func selectCreatedTask(_ id: UUID) {
        withImmediateNavigationUpdate {
            search = ""
            createdTaskID = id
            selectedTaskID = id
        }
    }

    func openLinkedTask(_ task: PlannerTask, visibleIDs: [UUID]) {
        withImmediateNavigationUpdate {
            if !visibleIDs.contains(task.id) { filter = task.folder.map { .folder($0.id) } ?? .inbox }
            search = ""
            createdTaskID = nil
            selectedTaskID = task.id
        }
    }

    /// Удаление не переводит выбор между активными и выполненными задачами и не раскрывает другой список.
    func selectAfterDeletingTask(_ deletedID: UUID, previousActiveIDs: [UUID], previousCompletedIDs: [UUID]) {
        guard selectedTaskID == deletedID else { return }
        let previousIDs = previousActiveIDs.contains(deletedID) ? previousActiveIDs : previousCompletedIDs
        reconcileSelection(previousIDs: previousIDs, visibleIDs: previousIDs.filter { $0 != deletedID })
    }

    /// Если строка исчезла, ищем соседей в прежнем визуальном порядке: сначала ниже, затем выше.
    func reconcileSelection(previousIDs: [UUID], visibleIDs: [UUID]) {
        guard let selected = selectedTaskID, !visibleIDs.contains(selected) else { return }
        let remaining = Set(visibleIDs)
        let replacement: UUID?
        if let index = previousIDs.firstIndex(of: selected) {
            replacement = previousIDs.dropFirst(index + 1).first(where: remaining.contains)
                ?? previousIDs.prefix(index).reversed().first(where: remaining.contains)
                ?? visibleIDs.first
        } else {
            replacement = visibleIDs.first
        }
        selectTask(replacement)
    }
}
