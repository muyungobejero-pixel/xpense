import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store

    @State private var showAdd = false
    @State private var editingItem: ExpenseItem?
    @State private var showRecurring = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summary
                    progress
                    filterPicker
                    list
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.monthTitle)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { store.goToPreviousMonth() } label: { Image(systemName: "chevron.left") }
                    Button("Today") { store.goToCurrentMonth() }
                    Button { store.goToNextMonth() } label: { Image(systemName: "chevron.right") }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showRecurring = true } label: { Image(systemName: "arrow.clockwise") }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { showAdd = true } label: {
                        Label("Add expense", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                ExpenseEditorView(item: nil)
                    .environmentObject(store)
            }
            .sheet(item: $editingItem) { item in
                ExpenseEditorView(item: item)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showRecurring) {
                RecurringView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(store)
            }
        }
    }

    // MARK: - Sections

    private var summary: some View {
        let items = store.items(for: store.currentMonth)
        let total = store.total(items)
        let paid = store.paidAmount(items)
        let unpaid = total - paid
        return HStack(spacing: 12) {
            SummaryCard(title: "Total", value: store.money(total), color: .primary)
            SummaryCard(title: "Unpaid", value: store.money(unpaid), color: .red)
            SummaryCard(title: "Paid", value: store.money(paid), color: .green)
        }
    }

    private var progress: some View {
        let items = store.items(for: store.currentMonth)
        let total = store.total(items)
        let fraction = total > 0 ? store.paidAmount(items) / total : 0
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: fraction)
            Text("\(Int(fraction * 100))% paid")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $store.filter) {
            ForEach(Filter.allCases) { f in
                Text(f.rawValue.capitalized).tag(f)
            }
        }
        .pickerStyle(.segmented)
    }

    private var list: some View {
        let items = store.sortedItems(displayedItems)
        if items.isEmpty {
            return AnyView(
                VStack(spacing: 12) {
                    Text("No expenses here.")
                        .foregroundColor(.secondary)
                    Button("Add your first expense") { showAdd = true }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            )
        }
        return AnyView(
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    ExpenseRow(item: item) {
                        editingItem = item
                    }
                }
            }
        )
    }

    private var displayedItems: [ExpenseItem] {
        let all = store.items(for: store.currentMonth)
        switch store.filter {
        case .all: return all
        case .unpaid: return all.filter { !$0.paid }
        case .paid: return all.filter { $0.paid }
        }
    }
}

// MARK: - Summary card

private struct SummaryCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Expense row

private struct ExpenseRow: View {
    @EnvironmentObject var store: Store
    let item: ExpenseItem
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.togglePaid(id: item.id)
            } label: {
                Image(systemName: item.paid ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(item.paid ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .strikethrough(item.paid)
                    .foregroundColor(item.paid ? .secondary : .primary)
                if !metaText.isEmpty {
                    Text(metaText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(store.money(item.amount))
                .fontWeight(.semibold)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }

    private var metaText: String {
        var parts: [String] = []
        if !item.category.isEmpty { parts.append(item.category) }
        if let dueDay = item.dueDay { parts.append("Due \(ordinal(dueDay))") }
        let rec = store.recurrenceText(item)
        if !rec.isEmpty { parts.append(rec) }
        if let status = store.dueStatus(item) { parts.append(status.label) }
        return parts.joined(separator: " · ")
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
