# Xpense — iOS (SwiftUI)

A native SwiftUI port of the Xpense monthly expense tracker. Feature-for-feature
parity with the web version: monthly navigation, add/edit/delete, paid toggle,
recurrence (monthly / every-other-month / quarterly / bi-annually / annually
with an explicit "recurs in" month), managed categories, recurring-bills view,
summary + progress, overdue/due-soon hints, and JSON backup export/import.

## Requirements

- macOS with Xcode 15+
- iOS 16.0+ deployment target
- (optional) [XcodeGen](https://github.com/yonaskolb/XcodeGen) for one-command
  project generation

## Quick start (XcodeGen — recommended)

1. Install XcodeGen: `brew install xcodegen`
2. From this `ios/` directory, run:
   ```sh
   xcodegen generate
   ```
3. Open the generated `Xpense.xcodeproj`, select a simulator, and run (⌘R).

The Swift sources already live in `ios/Xpense/`, which `project.yml` points at.
`PRODUCT_BUNDLE_IDENTIFIER` is already set to `io.muyungobejero.xpense`.

## Manual setup (no XcodeGen)

1. Open Xcode → **File → New → Project…** → **iOS → App**.
2. Product Name: `Xpense`, Interface: `SwiftUI`, Language: `Swift`.
3. Set the **Deployment Target** to `iOS 16.0`.
4. Delete the generated `ContentView.swift` (and the generated `XpenseApp.swift`).
5. Drag every `.swift` file from `ios/Xpense/` into the Xcode project navigator:
   - Check **"Copy items if needed"**.
   - Under **"Add to targets"**, make sure `Xpense` is checked.
6. Build & run (**⌘R**).

## Files

| File | Purpose |
|------|---------|
| `Xpense/XpenseApp.swift` | App entry point. |
| `Xpense/Models.swift` | Data model (`ExpenseItem`, `Recurrence`, `AppData`) + month helpers. |
| `Xpense/Store.swift` | Persistence + all business logic (`ObservableObject`). |
| `Xpense/HomeView.swift` | Monthly list, summary, progress, filter, item rows. |
| `Xpense/ExpenseEditorView.swift` | Add/edit sheet. |
| `Xpense/RecurringView.swift` | Recurring bills list. |
| `Xpense/SettingsView.swift` | Currency, categories, backup export/import, reset. |
| `Xpense/AuthManager.swift` | Google Sign-In state (optional sign-in). |
| `Xpense/LoginView.swift` | "Sign in with Google" / "Continue without signing in". |
| `project.yml` | XcodeGen project spec. |

## Notes

- Data is stored locally in `UserDefaults` under the key `xpense.data.v1`.
- This is a faithful port of the web app's data model and recurrence logic
  (anchor month + day-of-month + interval). Behavior matches, including
  "stop recurring" keeping past/current months and removing future ones.
- Minimum target is iOS 16 because of `NavigationStack`, `ShareLink`, and
  `.formatted(.currency(code:))` usage.

## Google Sign-In setup

Sign-in is **optional** — the launch screen offers "Sign in with Google" and a
"Continue without signing in" option. To make the Google button actually work,
you must supply your own OAuth credentials (you cannot use a placeholder).

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and
   create (or select) a project.
2. Enable the **Google Sign-In** API.
3. Under **APIs & Services > Credentials > Create Credentials > OAuth client ID**,
   choose **iOS**.
4. Set the **Bundle ID** to `io.muyungobejero.xpense` (or your actual bundle id).
5. After creating it, you'll get a **Client ID** (looks like
   `1234567890-xxxxxxxx.apps.googleusercontent.com`) and a **Reversed client ID**
   (the same, with components in reverse order).
6. Fill in your credentials in two places:
   - `project.yml` → `GIDClientID` and the `CFBundleURLSchemes` entry.
   - `Xpense/AuthManager.swift` → the `clientID` constant.

Then regenerate the project:

```sh
xcodegen generate
```

> **Note:** Older Google Sign-In setups used a `GoogleService-Info.plist`;
> recent versions take the client ID directly via code + `Info.plist` URL scheme.
