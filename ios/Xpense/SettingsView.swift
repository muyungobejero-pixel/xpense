import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    @State private var showImporter = false
    @State private var importError: String?

    @State private var renameTarget: String?
    @State private var renameText = ""

    private let currencies = ["PHP", "USD", "EUR", "GBP", "CAD", "AUD", "JPY", "INR"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = auth.currentUser {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name.isEmpty ? user.email : user.name)
                                        .font(.body)
                                    if !user.email.isEmpty {
                                        Text(user.email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "person.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        Button("Sign out", role: .destructive) {
                            auth.signOut()
                        }
                    } else {
                        Button("Sign in with Google") {
                            dismiss()
                            auth.showLogin()
                        }
                    }
                }

                Section("Currency") {
                    Picker("Currency", selection: $store.data.currency) {
                        ForEach(currencies, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                }
                .onChange(of: store.data.currency) { _ in store.save() }

                Section("Notifications") {
                    Toggle("Enable reminders", isOn: notificationsEnabledBinding)
                    if store.data.notificationsEnabled {
                        Picker("Notify", selection: leadDaysBinding) {
                            ForEach([0, 1, 2, 3, 5, 7], id: \.self) { d in
                                Text(d == 0 ? "On the due date" : "\(d) day\(d == 1 ? "" : "s") before").tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Categories") {
                    ForEach(store.data.categories, id: \.self) { cat in
                        HStack {
                            Text(cat)
                            Spacer()
                            Button {
                                renameTarget = cat
                                renameText = cat
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                store.deleteCategory(cat)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("Data") {
                    ShareLink(item: store.exportJSON()) {
                        Label("Export backup (JSON)", systemImage: "square.and.arrow.up")
                    }
                    Button("Import backup") { showImporter = true }
                    Button("Reset all data", role: .destructive) { store.resetAll() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let data = try Data(contentsOf: url)
                        try store.importData(data)
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Rename category", isPresented: renameBinding) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let old = renameTarget { store.renameCategory(from: old, to: renameText) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .alert("Import failed", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    // MARK: - Notification bindings

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.data.notificationsEnabled },
            set: { newValue in
                if newValue {
                    NotificationScheduler.requestAuthorizationIfNeeded()
                }
                store.setNotifications(enabled: newValue)
            }
        )
    }

    private var leadDaysBinding: Binding<Int> {
        Binding(
            get: { store.data.notificationLeadDays },
            set: { newValue in
                store.setNotifications(leadDays: newValue)
            }
        )
    }
}
