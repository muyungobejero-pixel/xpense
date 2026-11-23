# Xpense — iOS (SwiftUI)

A native SwiftUI port of the Xpense monthly expense tracker. Feature-for-feature
parity with the web version: monthly navigation, add/edit/delete, paid toggle,
recurrence (monthly / every-other-month / quarterly / bi-annually / annually
with an explicit "recurs in" month), managed categories, recurring-bills view,
summary + progress, overdue/due-soon hints, and JSON backup export/import.

## Requirements

- macOS with Xcode 15+ (recommended)
- iOS 16.0+ deployment target

## Setup

1. Open Xcode → **File → New → Project…** → **iOS → App**.
2. Product Name: `Xpense`, Interface: `SwiftUI`, Language: `Swift`.
3. Set the **Deployment Target** to `iOS 16.0` (or later).
4. Delete the generated `ContentView.swift` (and the generated `XpenseApp.swift`
   if it was auto-created, since we provide our own).
5. Drag every `.swift` file from this `Xpense/` folder into the Xcode project
   navigator (under the `Xpense` group):
   - Check **"Copy items if needed"**.
   - Under **"Add to targets"**, make sure `Xpense` is checked.
6. Build & run (**⌘R**).

## Files

| File | Purpose |
|------|---------|
| `XpenseApp.swift` | App entry point. |
| `Models.swift` | Data model (`ExpenseItem`, `Recurrence`, `AppData`) + month helpers. |
| `Store.swift` | Persistence + all business logic (`ObservableObject`). |
| `HomeView.swift` | Monthly list, summary, progress, filter, item rows. |
| `ExpenseEditorView.swift` | Add/edit sheet. |
| `RecurringView.swift` | Recurring bills list. |
| `SettingsView.swift` | Currency, categories, backup export/import, reset. |

## Notes

- Data is stored locally in `UserDefaults` under the key `xpense.data.v1`.
- This is a faithful port of the web app's data model and recurrence logic
  (anchor month + day-of-month + interval). Behavior matches, including
  "stop recurring" keeping past/current months and removing future ones.
