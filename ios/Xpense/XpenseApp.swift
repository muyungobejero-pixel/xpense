import SwiftUI
import GoogleSignIn

@main
struct XpenseApp: App {
    @StateObject private var store = Store()
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(store)
                .environmentObject(auth)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if auth.isRestoring {
            // Brief loading state while we restore a previous Google session.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else if auth.isSignedIn || auth.didSkip {
            HomeView()
        } else {
            LoginView()
        }
    }
}
