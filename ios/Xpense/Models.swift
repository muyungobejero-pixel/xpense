import Foundation

// MARK: - Recurrence

enum Recurrence: String, Codable, CaseIterable, Identifiable, Hashable {
    case none, monthly, bimonthly, quarterly, biannually, annually

    var id: String { rawValue }

    var interval: Int {
        switch self {
        case .none: return 0
        case .monthly: return 1
        case .bimonthly: return 2
        case .quarterly: return 3
        case .biannually: return 6
        case .annually: return 12
        }
    }

    var label: String {
        switch self {
        case .none: return "This month only"
        case .monthly: return "Every month"
        case .bimonthly: return "Every other month"
        case .quarterly: return "Every 3 months"
        case .biannually: return "Every 6 months"
        case .annually: return "Every year"
        }
    }

    /// True when the recurrence needs an explicit "recurs in" month.
    var needsMonth: Bool { self != .none && self != .monthly }
}

// MARK: - Expense item

struct ExpenseItem: Codable, Identifiable, Hashable {
    var id: String
    var seriesId: String?
    var name: String
    var amount: Double
    var dueDay: Int?
    var category: String
    var recurrence: Recurrence
    var anchorMonth: Int?
    var paid: Bool
    var isAuto: Bool

    init(id: String = UUID().uuidString,
         seriesId: String? = nil,
         name: String,
         amount: Double,
         dueDay: Int? = nil,
         category: String = "",
         recurrence: Recurrence = .none,
         anchorMonth: Int? = nil,
         paid: Bool = false,
         isAuto: Bool = false) {
        self.id = id
        self.seriesId = seriesId
        self.name = name
        self.amount = amount
        self.dueDay = dueDay
        self.category = category
        self.recurrence = recurrence
        self.anchorMonth = anchorMonth
        self.paid = paid
        self.isAuto = isAuto
    }

    var isRecurring: Bool { seriesId != nil && recurrence != .none }
}

// MARK: - App data

struct AppData: Codable {
    var state: [String: [ExpenseItem]] = [:]
    var categories: [String] = AppData.defaultCategories
    var stoppedSeries: Set<String> = []
    var currency: String = "PHP"
    var notificationsEnabled: Bool = true
    /// How many days before a due date to notify. Default 1.
    var notificationLeadDays: Int = 1

    static let defaultCategories = [
        "Housing", "Utilities", "Subscriptions", "Insurance",
        "Food", "Transport", "Health", "Entertainment", "Debt", "Other"
    ]
}

// MARK: - Month helpers

let MONTH_NAMES = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
]

func monthName(_ n: Int) -> String {
    (1...12).contains(n) ? MONTH_NAMES[n - 1] : ""
}

func currentMonthKey() -> String {
    let c = Calendar.current.dateComponents([.year, .month], from: Date())
    return String(format: "%04d-%02d", c.year ?? 2000, c.month ?? 1)
}

func currentMonthNumber() -> Int {
    Calendar.current.component(.month, from: Date())
}

func monthNumber(_ key: String) -> Int {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    return parts.count >= 2 ? parts[1] : 1
}

func shiftMonth(_ key: String, by delta: Int) -> String {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count >= 2 else { return key }
    var comps = DateComponents()
    comps.year = parts[0]
    comps.month = parts[1] + delta
    guard let date = Calendar.current.date(from: comps) else { return key }
    let c = Calendar.current.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
}

func monthLabel(_ key: String) -> String {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count >= 2 else { return key }
    var comps = DateComponents()
    comps.year = parts[0]
    comps.month = parts[1]
    guard let date = Calendar.current.date(from: comps) else { return key }
    return date.formatted(.dateTime.month(.wide).year())
}

/// Returns true when `month` (1-12) belongs to a schedule that starts at
/// `anchor` (1-12) and repeats every `interval` months. Works for intervals
/// that divide 12 (2, 3, 6, 12) because the year cancels out.
func monthMatches(month: Int, anchor: Int, interval: Int) -> Bool {
    (month - anchor) % interval == 0
}

func formatAmountForInput(_ v: Double) -> String {
    if v.truncatingRemainder(dividingBy: 1) == 0 {
        return String(Int(v))
    }
    return String(v)
}
