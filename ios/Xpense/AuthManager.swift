import SwiftUI
import GoogleSignIn

/// Manages Google Sign-In state for the app.
///
/// Sign-in is optional: the user may "Skip" and use the app locally without
/// an account. When signed in, `currentUser` exposes the account's name and
/// email so the UI can show who is logged in.
final class AuthManager: ObservableObject {

    /// True once a signed-in (or skipped) state has been resolved, so the app
    /// can show a brief loading state on first launch while we restore a
    /// previous Google session.
    @Published private(set) var isRestoring = true

    /// A lightweight, UI-friendly snapshot of the signed-in Google account.
    @Published private(set) var currentUser: GoogleUser?

    /// True when the user explicitly chose "Skip" for this session.
    @Published private(set) var didSkip = false

    /// Whether the app should gate content behind sign-in. Kept false because
    /// sign-in is optional; we simply expose who is signed in for now.
    var isSignedIn: Bool { currentUser != nil }

    /// Persist the "stay signed in" preference between launches.
    @AppStorage("xpense.auth.signedOut") private var signedOut = false

    init() {
        // Restore any previous Google session (unless the user signed out).
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRestoring = false
                if error == nil, let user {
                    self.setUser(user)
                } else {
                    // No previously signed-in account (or sign-in was cancelled).
                    self.currentUser = nil
                }
            }
        }

        // If no session exists, we're done restoring right away.
        // `restorePreviousSignIn` still runs, but this avoids a race where the
        // loading state sticks around if the callback never fires on a cold start.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isRestoring else { return }
            self.isRestoring = false
        }
    }

    /// Initiates the interactive Google sign-in flow.
    ///
    /// - Parameter presenting: The root view controller used to present Google's
    ///   sign-in UI. On iOS this is normally the window's root view controller.
    func signIn(presenting viewController: UIViewController? = nil) {
        guard let vc = viewController ?? Self.rootViewController() else {
            return
        }

        let config = GIDConfiguration(clientID: Self.clientID)
        GIDSignIn.sharedInstance.configuration = config

        GIDSignIn.sharedInstance.signIn(withPresenting: vc) { [weak self] signInResult, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    print("Google Sign-In failed: \(error.localizedDescription)")
                    return
                }
                guard let user = signInResult?.user else { return }
                self.signedOut = false
                self.setUser(user)
            }
        }
    }

    /// Signs the current user out and returns to the login screen.
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        signedOut = true
        currentUser = nil
        didSkip = false
    }

    /// Choose to continue without a Google account.
    func skip() {
        didSkip = true
        currentUser = nil
    }

    /// Clears any in-app session/skip state so the root view shows the login
    /// screen again. Used when a "skipped" user wants to sign in later.
    func showLogin() {
        didSkip = false
        currentUser = nil
    }

    private func setUser(_ user: GIDGoogleUser) {
        self.currentUser = GoogleUser(
            name: user.profile?.name ?? "",
            email: user.profile?.email ?? ""
        )
    }

    /// Your Google OAuth client ID from the Google Cloud Console
    /// (APIs & Services > Credentials > OAuth 2.0 Client ID, iOS type).
    private static let clientID = "1083755514063-g3bor3bpok2oh3hi9crg9q702i0a3iaf.apps.googleusercontent.com"

    private static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.compactMap { $0 as? UIWindowScene }.first
        return windowScene?.keyWindow?.rootViewController
    }
}

/// A UI-friendly snapshot of a signed-in Google user.
struct GoogleUser {
    let name: String
    let email: String
}
