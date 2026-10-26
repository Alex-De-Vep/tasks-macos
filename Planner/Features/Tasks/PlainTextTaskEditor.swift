import AppKit
import SwiftUI

/// Правило Enter отделено от NSTextView, чтобы проверить списки без окна и личных данных.
enum PlainTextLists {
    static func newline(in text: String, selection: NSRange, shift: Bool) -> (range: NSRange, text: String) {
        guard !shift else { return (selection, "\n") }
        let source = text as NSString
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let value = source.substring(with: line).trimmingCharacters(in: .newlines)
        let pattern = #"^([\t ]*)([-*•] |([0-9]+)\. )"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)),
              selection.location >= line.location + match.range.length else { return (selection, "\n") }
        let rest = (value as NSString).substring(from: match.range.length)
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            return (NSRange(location: line.location, length: (value as NSString).length), "")
        }
        let indent = (value as NSString).substring(with: match.range(at: 1))
        if match.range(at: 3).location != NSNotFound,
           let number = Int((value as NSString).substring(with: match.range(at: 3))), number < Int.max {
            return (selection, "\n\(indent)\(number + 1). ")
        }
        return (selection, "\n" + (value as NSString).substring(with: match.range))
    }
}

/// Каждый документ имеет собственные текстовые представления и UndoManager. Переключение задач их не очищает.
@MainActor
final class TaskEditorStore {
    private var views: [String: TaskTextView] = [:]
    func view(taskID: UUID, title: Bool) -> TaskTextView {
        let key = taskID.uuidString + (title ? ".title" : ".description")
        if let view = views[key] { return view }
        let view = TaskTextView(frame: .zero)
        view.isTitle = title
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticTextReplacementEnabled = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false
        // Размером управляет SwiftUI: NSTextView не должен сам вырастать поверх следующего блока.
        view.isVerticallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.containerSize.height = .greatestFiniteMagnitude
        view.font = .systemFont(ofSize: title ? 22 : 14, weight: title ? .semibold : .regular)
        view.textColor = .labelColor
        view.setAccessibilityIdentifier(title ? "task-title-field" : "task-description-field")
        views[key] = view
        return view
    }
    func remove(taskID: UUID) {
        views[taskID.uuidString + ".title"] = nil
        views[taskID.uuidString + ".description"] = nil
    }
}

struct PlainTextTaskEditor: NSViewRepresentable {
    let taskID: UUID
    let isTitle: Bool
    let store: TaskEditorStore
    @Binding var text: String
    @Binding var requestFocus: Bool
    let placeholder: String
    var submit: () -> Void = {}
    let toggleCompleted: () -> Void
    var minimumHeight: CGFloat? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> TaskTextView { store.view(taskID: taskID, title: isTitle) }
    func updateNSView(_ view: TaskTextView, context: Context) {
        context.coordinator.changed = { text = $0 }
        view.delegate = context.coordinator
        view.submit = submit
        view.toggleCompleted = toggleCompleted
        view.placeholder = placeholder
        view.setAccessibilityLabel(placeholder)
        // Не присваиваем строку при каждом рендере: это сохраняет выделение, IME и историю отмены.
        if view.string != text, !view.hasMarkedText() {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            view.invalidateIntrinsicContentSize()
        }
        view.needsDisplay = true
        view.focusRequested = requestFocus
        view.focusConsumed = { requestFocus = false }
        if requestFocus { view.applyRequestedFocus() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: TaskTextView, context: Context) -> CGSize? {
        view.fittingSize(width: max(1, proposal.width ?? 300),
                         minimumHeight: minimumHeight ?? (isTitle ? 30 : 160))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var changed: ((String) -> Void)?
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? TaskTextView else { return }
            view.needsDisplay = true; view.invalidateIntrinsicContentSize()
            changed?(view.string)
        }
    }
}

final class TaskTextView: NSTextView {
    var isTitle = false
    var placeholder = ""
    var submit: () -> Void = {}
    var toggleCompleted: () -> Void = {}
    var focusRequested = false
    var focusConsumed: () -> Void = {}
    private let documentUndo = UndoManager()
    override var undoManager: UndoManager? { documentUndo }

    /// Пробные ширины SwiftUI измеряем отдельно, не меняя контейнер живого редактора.
    /// Иначе widthTracksTextView может вернуть прежнюю ширину во время ensureLayout,
    /// и описание получит высоту от другого количества строк.
    func fittingSize(width: CGFloat, minimumHeight: CGFloat) -> CGSize {
        let storage = NSTextStorage(attributedString: textStorage ?? NSAttributedString(string: string))
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(
            width: max(1, width - textContainerInset.width * 2), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        // Последний пустой абзац тоже занимает строку и должен оставлять место для курсора.
        let bottom = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        return CGSize(width: width, height: max(minimumHeight, ceil(bottom + textContainerInset.height * 2) + 6))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusRequested { applyRequestedFocus() }
    }
    func applyRequestedFocus() {
        // Новый NSTextView может получить запрос ещё до присоединения к окну.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.focusRequested, let window = self.window else { return }
            if window.makeFirstResponder(self) { self.focusRequested = false; self.focusConsumed() }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(at: .zero, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor])
        }
    }
    override func insertNewline(_ sender: Any?) {
        if isTitle { submit(); return }
        let change = PlainTextLists.newline(in: string, selection: selectedRange(), shift: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
        // insertText использует штатный механизм выделения, уведомлений и отмены NSTextView.
        insertText(change.text, replacementRange: change.range)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            toggleCompleted(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) {
            insertText(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"), replacementRange: selectedRange())
        } else { pasteAsPlainText(sender) }
    }
}
