import AppKit
import Testing
@testable import Planner

/// Повторное подключение документа не меняет ввод, Undo и обработчики действующей карточки.
@MainActor
struct TaskEditorAttachmentTests {
    @Test func cachedEditorMovesToOneHostAndOldTeardownCannotDisconnectIt() {
        let store = TaskEditorStore(), taskID = UUID()
        let editor = store.view(taskID: taskID, title: false)
        let first = TaskEditorHost(editor: editor)
        editor.string = "Сохранённое описание"
        editor.setSelectedRange(NSRange(location: 4, length: 5))
        editor.focusRequested = true
        var oldSubmits = 0, newSubmits = 0
        editor.submit = { oldSubmits += 1 }
        let firstCoordinator = PlainTextTaskEditor.Coordinator()
        firstCoordinator.host = first
        editor.delegate = firstCoordinator

        let second = TaskEditorHost(editor: store.view(taskID: taskID, title: false))
        let secondCoordinator = PlainTextTaskEditor.Coordinator()
        secondCoordinator.host = second
        editor.delegate = secondCoordinator
        editor.submit = { newSubmits += 1 }
        // SwiftUI может вызвать dismantle старой карточки уже после подключения новой.
        PlainTextTaskEditor.dismantleNSView(first, coordinator: firstCoordinator)
        #expect(!first.ownsEditor && first.subviews.isEmpty && second.ownsEditor)
        #expect(editor.superview === second && editor.delegate === secondCoordinator)
        #expect(editor.isEditable && editor.isSelectable && !editor.focusRequested)
        #expect(editor.string == "Сохранённое описание" && editor.selectedRange() == NSRange(location: 4, length: 5))
        editor.submit()
        #expect(oldSubmits == 0 && newSubmits == 1)
        PlainTextTaskEditor.dismantleNSView(second, coordinator: secondCoordinator)
        #expect(editor.superview == nil && editor.delegate == nil && editor.editorHost == nil)
    }

    @Test func onlyCurrentCoordinatorSavesEditsToItsTask() {
        let store = TaskEditorStore(), firstID = UUID(), secondID = UUID()
        let first = TaskEditorHost(editor: store.view(taskID: firstID, title: true))
        let other = TaskEditorHost(editor: store.view(taskID: secondID, title: true))
        let oldCoordinator = PlainTextTaskEditor.Coordinator()
        oldCoordinator.host = first
        var oldChanges: [String] = [], currentChanges: [String] = []
        oldCoordinator.changed = { oldChanges.append($0) }
        let current = TaskEditorHost(editor: store.view(taskID: firstID, title: true))
        let coordinator = PlainTextTaskEditor.Coordinator()
        coordinator.host = current
        coordinator.changed = { currentChanges.append($0) }
        current.editor.string = "Новое название"
        let notification = Notification(name: NSText.didChangeNotification, object: current.editor)
        oldCoordinator.textDidChange(notification)
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: other.editor))
        coordinator.textDidChange(notification)
        #expect(oldChanges.isEmpty && currentChanges == ["Новое название"])
    }

    @Test func undoSelectionAndPlainTextSurviveDetachingAndReopening() {
        let store = TaskEditorStore(), taskID = UUID()
        let editor = store.view(taskID: taskID, title: false)
        let first = TaskEditorHost(editor: editor)
        editor.undoManager?.groupsByEvent = false
        editor.undoManager?.beginUndoGrouping()
        editor.insertText("Первая\nВторая", replacementRange: NSRange(location: 0, length: 0))
        editor.undoManager?.endUndoGrouping()
        let undo = editor.undoManager
        first.detachEditor()
        let second = TaskEditorHost(editor: store.view(taskID: taskID, title: false))
        #expect(second.ownsEditor && editor.undoManager === undo && editor.isEditable && !editor.isRichText)
        #expect(editor.acceptsFirstMouse(for: nil))
        editor.undoManager?.undo()
        #expect(editor.string.isEmpty)
        editor.undoManager?.redo()
        #expect(editor.string == "Первая\nВторая")
    }

    @Test func hostFillsTheVisibleEditorAndIncludesItsWholeSurfaceInHitTesting() {
        let editor = TaskEditorStore().view(taskID: UUID(), title: false)
        let host = TaskEditorHost(editor: editor)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        host.layoutSubtreeIfNeeded()
        #expect(editor.frame == host.bounds)
        // Проверяем и текстовую область, и пустую часть описания справа и снизу.
        for point in [NSPoint(x: 4, y: 4), NSPoint(x: 210, y: 40), NSPoint(x: 414, y: 174)] {
            #expect(host.hitTest(point) === editor)
        }
    }
}
