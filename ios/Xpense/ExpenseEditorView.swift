import SwiftUI

struct ExpenseEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss

    let item: ExpenseItem?

    @State private var name: String
    @State private var amount: String
    @State private var dueDay: String
    @State private var category: String
    @State private var newCategory: String = ""
    @State private var recurrence: Recurrence
    @State private var anchorMonth: Int

    init(item: ExpenseItem?) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _amount = State(initialValue: item.map { formatAmountForInput($0.amount) } ?? "")
        _dueDay = State(initialValue: item?.dueDay.map(String.init) ?? "")
        _category = State(initialValue: item?.category ?? "")
        _recurrence = State(initialValue: item?.recurrence ?? .none)
        _anchorMonth = State(initialValue: item?.anchorMonth ?? currentMonthNumber())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Due day (1-31)", text: $dueDay)
                        .keyboardType(.numberPad)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("None").tag("")
                        ForEach(store.data.categories, id: \.self) { c in
                            Text(c).tag(c)
                        }
                        Text("＋ Add new category…").tag("__add__")
                    }
                    if category == "__add__" {
                        TextField("New category name", text: $newCategory)
                    }
                }

                Section("Repeats") {
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    if recurrence.needsMonth {
                        Picker("Recurs in (month)", selection: $anchorMonth) {
                            ForEach(1...12, id: \.self) { m in
                                Text(monthName(m)).tag(m)
                            }
                        }
                    }
                }

                if let item = item {
                    Section {
                        if item.isRecurring {
                            Button("Stop recurring", role: .destructive) {
                                if let sid = item.seriesId { store.stopSeries(sid) }
                                dismiss()
                            }
                        }
                        Button(item.isRecurring ? "Delete this month" : "Delete", role: .destructive) {
                            store.delete(id: item.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")),
              amountValue >= 0 else { return }

        let due = Int(dueDay)

        let finalCategory: String
        if category == "__add__" {
            finalCategory = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalCategory.isEmpty { store.addCategory(finalCategory) }
        } else {
            finalCategory = category
        }

        let anchor = recurrence.needsMonth ? anchorMonth : nil

        if let item = item {
            store.update(id: item.id, name: trimmedName, amount: amountValue, dueDay: due,
                         category: finalCategory, recurrence: recurrence, anchorMonth: anchor)
        } else {
            store.add(name: trimmedName, amount: amountValue, dueDay: due,
                      category: finalCategory, recurrence: recurrence, anchorMonth: anchor)
        }
        dismiss()
    }
}
