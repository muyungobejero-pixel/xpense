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
| `Xpense/NotificationScheduler.swift` | Local notification scheduling (due-date reminders). |
| `Xpense/CloudSyncManager.swift` | Firestore cloud sync (whole-document per user). |
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

## Cloud sync (Firebase) setup

Signing in with Google also enables **cloud sync**: your whole dataset is saved
to Firestore under `users/{googleUserID}/xpense/data` and pulled back on sign-in.
"Skip" (anonymous) users remain local-only. The app falls back to local
`UserDefaults` silently if Firestore isn't configured or is unreachable.

To enable cloud sync:

1. Create a Firebase project at https://console.firebase.google.com.
2. Add an **iOS app** with bundle ID `io.muyungobejero.xpense`.
3. Download **`GoogleService-Info.plist`** and place it in `ios/Xpense/`.
4. In the console, create a **Cloud Firestore** database (test mode is fine to
   start). Lock it down with security rules keyed on the signed-in user:

   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{uid}/{document=**} {
         allow read, write: if request.auth != null && request.auth.uid == uid;
       }
     }
   }
   ```

   > These rules assume you are also using **Firebase Authentication** with the
   > same user ID (see below). If you are not using Firebase Auth, you'll need a
   > different access-control strategy.

Then regenerate and rebuild:

```sh
xcodegen generate
```

### Note on Firebase Auth

Currently the app uses the **Google Sign-In SDK directly** (`userID` = Google
`sub` claim) and stores data under that ID. The Firestore security rules above
require `request.auth.uid` to match — which only works if you also enable
**Firebase Authentication** and sign in with Google *through Firebase*. Two
options:

- **Simplest for now:** use Firestore in "test mode" (open rules) without Firebase
  Auth while developing locally, then lock it down before shipping.
- **Properly:** add Firebase Auth and exchange the Google credential for a
  Firebase session so `request.auth.uid` matches `userID`. This is a small
  additional step I can implement.

For a personal tracker in development, "test mode" is sufficient to validate
sync end-to-end.
