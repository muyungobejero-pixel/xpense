import Foundation
import UserNotifications

/// Schedules and cancels local notifications for unpaid expenses based on
/// each item's due day and the user's configured notification settings.
enum NotificationScheduler {

    static let center = UNUserNotificationCenter.current()

    /// Requests notification authorization if not already determined.
    static func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            default:
                break
            }
        }
    }

    /// Rebuilds the full set of pending notifications from the given items and
    /// settings. Removes all existing Xpense notifications first, then (if
    /// enabled) schedules a reminder for each unpaid item with a due day.
    ///
    /// - Monthly recurring items are scheduled with a `repeats: true` trigger so
    ///   they fire every month indefinitely.
    /// - Non-monthly recurring items (every 2/3/6/12 months) are scheduled for
    ///   their next concrete occurrence (the resync-on-change re-arms them).
    /// - One-time items are scheduled for their single due date.
    ///
    /// - Parameters:
    ///   - items: The expense items to schedule reminders for.
    ///   - enabled: Whether notifications are enabled at all.
    ///   - leadDays: Days before the due date to fire (0 = same day).
    ///   - formatAmount: Closure that formats an amount into a display string.
    static func resync(items: [ExpenseItem],
                       enabled: Bool,
                       leadDays: Int,
                       formatAmount: @escaping (Double) -> String) {
        let ids = items.map { Self.identifier(for: $0.id) }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        guard enabled else { return }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }

            for item in items {
                guard !item.paid, let dueDay = item.dueDay else { continue }

                let content = UNMutableNotificationContent()
                content.title = item.name
                content.body = "Due \(ordinal(dueDay)) \u{00b7} \(formatAmount(item.amount)) \u{00b7} \(leadLabel(leadDays))"
                content.sound = .default

                guard let trigger = Self.trigger(for: item, dueDay: dueDay, leadDays: leadDays) else {
                    continue
                }

                let request = UNNotificationRequest(identifier: Self.identifier(for: item.id),
                                                    content: content,
                                                    trigger: trigger)
                center.add(request)
            }
        }
    }

    // MARK: - Helpers

    private static func identifier(for itemID: String) -> String {
        "xpense.reminder.\(itemID)"
    }

    /// Builds the appropriate trigger for an item.
    private static func trigger(for item: ExpenseItem, dueDay: Int, leadDays: Int) -> UNNotificationTrigger? {
        switch item.recurrence {
        case .monthly:
            // Fire every month on the (dueDay - leadDays) date. A day <= 0 is
            // not representable in a repeating calendar trigger, so fall back to
            // a concrete next occurrence.
            let fireDay = dueDay - leadDays
            if fireDay >= 1 {
                var comps = DateComponents()
                comps.day = fireDay
                comps.hour = 9
                comps.minute = 0
                return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            } else {
                return nextOccurrenceTrigger(for: item, dueDay: dueDay, leadDays: leadDays)
            }

        case .none, .bimonthly, .quarterly, .biannually, .annually:
            // One-time or interval-based: schedule the next concrete occurrence.
            return nextOccurrenceTrigger(for: item, dueDay: dueDay, leadDays: leadDays)
        }
    }

    /// Computes the next future fire date and returns a non-repeating trigger.
    private static func nextOccurrenceTrigger(for item: ExpenseItem, dueDay: Int, leadDays: Int) -> UNCalendarNotificationTrigger? {
        guard let fire = nextFireDate(for: item, dueDay: dueDay, leadDays: leadDays) else {
            return nil
        }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    /// Finds the next future due date (minus lead days) for an item.
    private static func nextFireDate(for item: ExpenseItem, dueDay: Int, leadDays: Int) -> Date? {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        var candidates: [Date] = []

        switch item.recurrence {
        case .none:
            // Just this month's due date.
            if let d = dueDate(monthOffset: 0, dueDay: dueDay, from: today, cal: cal) {
                candidates.append(d)
            }
        case .monthly:
            // This month and each subsequent month.
            for offset in 0..<13 {
                if let d = dueDate(monthOffset: offset, dueDay: dueDay, from: today, cal: cal) {
                    candidates.append(d)
                }
            }
        default:
            // Interval-based: scan future months and keep those matching anchor.
            guard let anchor = item.anchorMonth else {
                if let d = dueDate(monthOffset: 0, dueDay: dueDay, from: today, cal: cal) {
                    candidates.append(d)
                }
                break
            }
            for offset in 0..<24 {
                guard let d = dueDate(monthOffset: offset, dueDay: dueDay, from: today, cal: cal) else { continue }
                if monthMatches(month: cal.component(.month, from: d),
                                anchor: anchor,
                                interval: item.recurrence.interval) {
                    candidates.append(d)
                }
            }
        }

        candidates.sort()
        for due in candidates {
            let fire = cal.date(byAdding: .day, value: -leadDays, to: due) ?? due
            if fire > now {
                return fire
            }
        }
        return nil
    }

    private static func dueDate(monthOffset: Int, dueDay: Int, from start: Date, cal: Calendar) -> Date? {
        var comps = cal.dateComponents([.year, .month], from: start)
        comps.month = (comps.month ?? 1) + monthOffset
        guard let firstOfMonth = cal.date(from: comps) else { return nil }
        let range = cal.range(of: .day, in: .month, for: firstOfMonth)
        let clampedDay = min(dueDay, range?.count ?? dueDay)
        var dayComps = cal.dateComponents([.year, .month], from: firstOfMonth)
        dayComps.day = clampedDay
        dayComps.hour = 9
        dayComps.minute = 0
        return cal.date(from: dayComps)
    }

    private static func ordinal(_ n: Int) -> String {
        switch n % 100 {
        case 11, 12, 13: return "\(n)th"
        default:
            switch n % 10 {
            case 1: return "\(n)st"
            case 2: return "\(n)nd"
            case 3: return "\(n)rd"
            default: return "\(n)th"
            }
        }
    }

    private static func leadLabel(_ leadDays: Int) -> String {
        switch leadDays {
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "Due in \(leadDays) days"
        }
    }
}
