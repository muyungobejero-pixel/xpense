import SwiftUI
import GoogleSignIn
import UserNotifications
import FirebaseCore

@main
struct XpenseApp: App {
    @StateObject private var store = Store()
    @StateObject private var auth = AuthManager()
    @StateObject private var cloud = CloudSyncManager()

    init() {
        // Configure Firebase for cloud sync (no-op if config plist is missing).
        FirebaseApp.configure()
        cloud.configure()

        // Request notification permission on first launch.
        NotificationScheduler.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(cloud)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: auth.storageNamespace) { newNamespace in
                    store.setNamespace(newNamespace, cloud: cloud)
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        Group {
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
        .onAppear {
            // Sync the store to the initial auth identity (e.g. a restored
            // session from a previous launch) once we know it.
            store.setNamespace(auth.storageNamespace, cloud: cloud)
        }
    }
}
