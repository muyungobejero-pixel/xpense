import SwiftUI

struct RecurringView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss

    @State private var editingItem: ExpenseItem?

    var body: some View {
        NavigationStack {
            List {
                let rules = store.recurringRules()
                if rules.isEmpty {
                    Text("No recurring bills yet. Set any expense's \"Repeats\" to start one.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(rules) { rule in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.name)
                                Text(store.recurrenceText(rule))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !rule.category.isEmpty {
                                    Text(rule.category)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Text(store.money(rule.amount))
                                .fontWeight(.semibold)
                            Button("Edit") { editingItem = rule }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            Button("Stop", role: .destructive) {
                                if let sid = rule.seriesId { store.stopSeries(sid) }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Recurring bills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingItem) { item in
                ExpenseEditorView(item: item)
                    .environmentObject(store)
            }
        }
    }
}
