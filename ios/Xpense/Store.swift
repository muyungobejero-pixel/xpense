import Foundation
import SwiftUI

enum Filter: String, CaseIterable, Identifiable {
    case all, unpaid, paid
    var id: String { rawValue }
}

final class Store: ObservableObject {
    @Published var data: AppData
    @Published var currentMonth: String
    @Published var filter: Filter = .all

    private static let storageKeyPrefix = "xpense.data.v1"

    /// The active data owner. Set by `setNamespace(_:)` when the user signs in
    /// or skips. Each namespace gets its own `UserDefaults` key so identities
    /// don't share data.
    private(set) var namespace: String = ""

    /// The fully-qualified storage key for the current namespace.
    private var storageKey: String {
        Self.storageKeyPrefix + (namespace.isEmpty ? "" : ".\(namespace)")
    }

    private static let defaultItems: [(name: String, amount: Double, dueDay: Int, category: String)] = [
        ("Rent / Mortgage", 1200, 1, "Housing"),
        ("Electricity", 90, 10, "Utilities"),
        ("Water", 40, 10, "Utilities"),
        ("Internet", 60, 15, "Utilities"),
        ("Phone", 45, 20, "Utilities"),
        ("Netflix", 15.49, 5, "Subscriptions"),
        ("Spotify", 11.99, 8, "Subscriptions"),
        ("Gym", 35, 3, "Subscriptions"),
        ("Car insurance", 120, 12, "Insurance"),
    ]

    init() {
        self.data = AppData()
        self.currentMonth = currentMonthKey()
        loadForNamespace()
    }

    /// Switches the store to the given data owner. Reloads that user's data
    /// (freshly seeded if none exists yet) and resets the view to this month.
    /// Called whenever the auth identity changes.
    func setNamespace(_ newNamespace: String) {
        guard newNamespace != namespace else { return }
        namespace = newNamespace
        data = AppData()
        currentMonth = currentMonthKey()
        filter = .all
        loadForNamespace()
    }

    private func loadForNamespace() {
        self.data = Store.load(storageKey: storageKey)
        seedIfEmpty()
        ensureCategoriesCoverItems()
        materialize(currentMonth)
        resyncNotifications()
    }

    // MARK: - Persistence

    private static func load(storageKey: String) -> AppData {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AppData.self, from: data) else {
            return AppData()
        }
        return decoded
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func seedIfEmpty() {
        guard data.state.isEmpty else { return }
        let month = currentMonth
        let items = Self.defaultItems.map { t in
            ExpenseItem(id: UUID().uuidString,
                        seriesId: UUID().uuidString,
                        name: t.name,
                        amount: t.amount,
                        dueDay: t.dueDay,
                        category: t.category,
                        recurrence: .monthly,
                        paid: false,
                        isAuto: false)
        }
        data.state[month] = items
        save()
    }

    private func ensureCategoriesCoverItems() {
        var used = Set<String>()
        for (_, arr) in data.state {
            for item in arr where !item.category.isEmpty {
                used.insert(item.category)
            }
        }
        var changed = false
        for c in used where !data.categories.contains(c) {
            data.categories.append(c)
            changed = true
        }
        if changed {
            data.categories.sort()
            save()
        }
    }

    // MARK: - Materialization

    /// Rolls recurring items forward into `key`, reconciling auto-generated
    /// copies. Must be called outside of view body evaluation (e.g. on
    /// navigation or on appear), since it mutates published state.
    func materialize(_ key: String) {
        let existing = data.state[key] ?? []

        var expected: [String: ExpenseItem] = [:]
        let prior = data.state.keys.filter { $0 < key }.sorted(by: >)
        var resolved = Set<String>()

        for k in prior {
            for src in data.state[k] ?? [] {
                guard let sid = src.seriesId else { continue }
                if data.stoppedSeries.contains(sid) { continue }
                if resolved.contains(sid) { continue }
                resolved.insert(sid)

                switch src.recurrence {
                case .monthly:
                    expected[sid] = src
                case .none:
                    break
                default:
                    if let anchor = src.anchorMonth,
                       monthMatches(month: monthNumber(key), anchor: anchor, interval: src.recurrence.interval) {
                        expected[sid] = src
                    }
                }
            }
        }

        var kept = existing.filter { item in
            guard let sid = item.seriesId else { return true }
            if !item.isAuto { return true }
            if data.stoppedSeries.contains(sid) { return false }
            return expected[sid] != nil
        }

        for (sid, src) in expected {
            if !kept.contains(where: { $0.seriesId == sid }) {
                kept.append(copyRecurring(src))
            }
        }

        if kept != existing {
            data.state[key] = kept
            save()
        }
    }

    private func copyRecurring(_ src: ExpenseItem) -> ExpenseItem {
        ExpenseItem(id: UUID().uuidString,
                    seriesId: src.seriesId,
                    name: src.name,
                    amount: src.amount,
                    dueDay: src.dueDay,
                    category: src.category,
                    recurrence: src.recurrence,
                    anchorMonth: src.anchorMonth,
                    paid: false,
                    isAuto: true)
    }

    /// Pure read: the already-materialized items for a month.
    func items(for key: String) -> [ExpenseItem] {
        data.state[key] ?? []
    }

    func sortedItems(_ items: [ExpenseItem]) -> [ExpenseItem] {
        items.sorted {
            if $0.paid != $1.paid { return !$0.paid }
            return ($0.dueDay ?? 99) < ($1.dueDay ?? 99)
        }
    }

    // MARK: - Navigation

    func goTo(_ month: String) {
        currentMonth = month
        materialize(month)
    }

    func goToPreviousMonth() { goTo(shiftMonth(currentMonth, by: -1)) }
    func goToNextMonth() { goTo(shiftMonth(currentMonth, by: 1)) }
    func goToCurrentMonth() { goTo(currentMonthKey()) }

    // MARK: - CRUD

    func add(name: String, amount: Double, dueDay: Int?, category: String, recurrence: Recurrence, anchorMonth: Int?) {
        let key = currentMonth
        var month = items(for: key)
        month.append(ExpenseItem(
            id: UUID().uuidString,
            seriesId: recurrence != .none ? UUID().uuidString : nil,
            name: name, amount: amount, dueDay: dueDay, category: category,
            recurrence: recurrence,
            anchorMonth: recurrence.needsMonth ? anchorMonth : nil,
            paid: false, isAuto: false))
        data.state[key] = month
        save()
        resyncNotifications()
    }

    func update(id: String, name: String, amount: Double, dueDay: Int?, category: String, recurrence: Recurrence, anchorMonth: Int?) {
        let key = currentMonth
        var month = items(for: key)
        if let idx = month.firstIndex(where: { $0.id == id }) {
            month[idx].name = name
            month[idx].amount = amount
            month[idx].dueDay = dueDay
            month[idx].category = category
            month[idx].recurrence = recurrence
            month[idx].anchorMonth = recurrence.needsMonth ? anchorMonth : nil

            if recurrence != .none {
                if month[idx].seriesId == nil { month[idx].seriesId = UUID().uuidString }
                if let sid = month[idx].seriesId { data.stoppedSeries.remove(sid) }
            } else {
                month[idx].seriesId = nil
            }
        }
        data.state[key] = month
        save()
        resyncNotifications()
    }

    func delete(id: String) {
        let key = currentMonth
        var month = items(for: key)
        month.removeAll { $0.id == id }
        data.state[key] = month
        save()
        resyncNotifications()
    }

    func togglePaid(id: String) {
        let key = currentMonth
        var month = items(for: key)
        if let idx = month.firstIndex(where: { $0.id == id }) {
            month[idx].paid.toggle()
        }
        data.state[key] = month
        save()
        resyncNotifications()
    }

    func stopSeries(_ sid: String) {
        guard !data.stoppedSeries.contains(sid) else { return }
        data.stoppedSeries.insert(sid)
        for key in data.state.keys {
            guard let arr = data.state[key] else { continue }
            var kept: [ExpenseItem] = []
            for var item in arr {
                if item.seriesId != sid {
                    kept.append(item)
                } else if key <= currentMonth {
                    // Keep as a one-time historical record.
                    item.recurrence = .none
                    item.anchorMonth = nil
                    item.isAuto = false
                    kept.append(item)
                }
            }
            data.state[key] = kept
        }
        save()
        resyncNotifications()
    }

    func recurringRules() -> [ExpenseItem] {
        var map: [String: ExpenseItem] = [:]
        for key in data.state.keys.sorted() {
            for item in data.state[key] ?? [] {
                guard item.isRecurring, let sid = item.seriesId else { continue }
                if data.stoppedSeries.contains(sid) { continue }
                map[sid] = item
            }
        }
        return map.values.sorted { ($0.dueDay ?? 99) < ($1.dueDay ?? 99) }
    }

    // MARK: - Categories

    func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !data.categories.contains(trimmed) else { return }
        data.categories.append(trimmed)
        data.categories.sort()
        save()
    }

    func renameCategory(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old, !data.categories.contains(trimmed) else { return }
        if let idx = data.categories.firstIndex(of: old) {
            data.categories[idx] = trimmed
            data.categories.sort()
        }
        for key in data.state.keys {
            if var arr = data.state[key] {
                for i in arr.indices where arr[i].category == old {
                    arr[i].category = trimmed
                }
                data.state[key] = arr
            }
        }
        save()
    }

    func deleteCategory(_ name: String) {
        data.categories.removeAll { $0 == name }
        for key in data.state.keys {
            if var arr = data.state[key] {
                for i in arr.indices where arr[i].category == name {
                    arr[i].category = ""
                }
                data.state[key] = arr
            }
        }
        save()
    }

    func resetAll() {
        data = AppData()
        currentMonth = currentMonthKey()
        seedIfEmpty()
        save()
        resyncNotifications()
    }

    // MARK: - Backup

    func exportJSON() -> String {
        guard let d = try? JSONEncoder().encode(data),
              let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }

    func importData(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(AppData.self, from: data)
        self.data = decoded
        currentMonth = currentMonthKey()
        ensureCategoriesCoverItems()
        save()
        resyncNotifications()
    }

    // MARK: - Formatting / presentation helpers

    var monthTitle: String { monthLabel(currentMonth) }

    func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: data.currency))
    }

    func recurrenceText(_ item: ExpenseItem) -> String {
        guard item.recurrence != .none else { return "" }
        var text = item.recurrence.label
        if item.recurrence.needsMonth, let m = item.anchorMonth {
            text += " (\(monthName(m)))"
        }
        return text
    }

    func dueStatus(_ item: ExpenseItem) -> (label: String, kind: String)? {
        guard !item.paid, let dueDay = item.dueDay else { return nil }
        guard currentMonth == currentMonthKey() else { return nil }
        let today = Calendar.current.component(.day, from: Date())
        if dueDay < today { return ("Overdue", "overdue") }
        if dueDay == today { return ("Due today", "due-today") }
        if dueDay - today <= 3 { return ("Due soon", "due-soon") }
        return nil
    }

    // MARK: - Summary

    func total(_ items: [ExpenseItem]) -> Double { items.reduce(0) { $0 + $1.amount } }
    func paidAmount(_ items: [ExpenseItem]) -> Double { items.filter { $0.paid }.reduce(0) { $0 + $1.amount } }

    // MARK: - Notifications

    /// Rebuilds pending local notifications to match the current data and
    /// notification settings. Uses the current month's items; recurring items
    /// resolve their next occurrence inside the scheduler.
    func resyncNotifications() {
        let all = data.state.values.flatMap { $0 }
        NotificationScheduler.resync(
            items: all,
            enabled: data.notificationsEnabled,
            leadDays: data.notificationLeadDays,
            formatAmount: { [weak self] amount in self?.money(amount) ?? "" }
        )
    }

    func setNotifications(enabled: Bool? = nil, leadDays: Int? = nil) {
        if let enabled { data.notificationsEnabled = enabled }
        if let leadDays { data.notificationLeadDays = max(0, leadDays) }
        save()
        resyncNotifications()
    }
}
