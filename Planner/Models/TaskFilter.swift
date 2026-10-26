import Foundation
import PlannerLocalization

/// Период планирования хранится отдельно от отметки «На сегодня» и статуса выполнения.
enum PlanningPeriod: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    func title(using strings: Translations) -> String { strings[self == .week ? "На неделе" : "В этом месяце"] }
    var component: Calendar.Component { self == .week ? .weekOfYear : .month }
}

/// Системные разделы — фильтры над одной библиотекой; копии задач для них не создаются.
enum TaskFilter: Hashable, Identifiable {
    case inbox, today, week, month, all
    case folder(UUID)

    static let smartFilters: [TaskFilter] = [.inbox, .today, .week, .month, .all]
    var id: String {
        switch self {
        case .inbox: "inbox"
        case .today: "today"
        case .week: "week"
        case .month: "month"
        case .all: "all"
        case .folder(let id): "folder-\(id.uuidString)"
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "star"
        case .week: "calendar"
        case .month: "calendar.badge.clock"
        case .all: "square.stack"
        case .folder: "folder"
        }
    }

    func title(in folders: [TaskFolder], using strings: Translations) -> String {
        switch self {
        case .inbox: strings["Входящие"]
        case .today: strings["Сегодня"]
        case .week: strings["На неделе"]
        case .month: strings["Месяц"]
        case .all: strings["Все задачи"]
        case .folder(let id): folders.first { $0.id == id }?.name ?? strings["Папка"]
        }
    }

    func matches(_ task: PlannerTask, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .inbox: return task.folder == nil
        case .today: return task.isFocused(on: now, calendar: calendar)
        case .all: return true
        case .folder(let id): return task.folder?.id == id
        case .week, .month:
            if task.isFocused(on: now, calendar: calendar) { return true }
            guard let kind = task.planningKind.flatMap(PlanningPeriod.init(rawValue:)),
                  let anchor = task.planningAnchor,
                  let planned = calendar.dateInterval(of: kind.component, for: anchor) else { return false }
            if self == .week && kind != .week { return false }
            let component: Calendar.Component = self == .week ? .weekOfYear : .month
            guard let current = calendar.dateInterval(of: component, for: now) else { return false }
            // Правая граница не включается: соседние недели и месяцы не пересекаются.
            return planned.start < current.end && current.start < planned.end
        }
    }
}

enum LocalDay {
    // Формат ключа всегда григорианский, часовой пояс берём из пользовательского календаря.
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension PlannerTask {
    func isFocused(on date: Date, calendar: Calendar = .current) -> Bool {
        focusDay == LocalDay.key(for: date, calendar: calendar)
    }
}
