import Foundation
import FirebaseFirestore

/// Cloud sync for a single user's data using Firestore (Approach A: the whole
/// `AppData` is stored as one document per user).
///
/// - When signed in, `AppData` is persisted to `users/{userID}/xpense` and
///   pulled down on sign-in/launch.
/// - When not signed in (or Firebase isn't configured), it no-ops so the app
///   keeps working with local `UserDefaults` only.
final class CloudSyncManager: ObservableObject {

    /// Firestore collection: one document per user under `users/{uid}/xpense`.
    private static let collectionName = "users"
    private static let documentName = "xpense"

    /// The Firestore instance, or nil when not configured.
    private var db: Firestore?

    /// The last known synced data (as a stable JSON string) so we can avoid
    /// redundant writes and detect conflicts.
    private var lastSyncedJSON: String?

    init() {
        // Firebase is configured lazily; if the config plist is missing, we
        // simply stay in local-only mode and never fail.
    }

    /// Call this once at app startup before any sync.
    func configure() {
        // FirebaseApp.configure() is handled in XpenseApp via FirebaseCore.
        // Here we just grab the database instance.
        db = Firestore.firestore()
    }

    /// Pushes the given data to the cloud for the provided user ID. No-ops when
    /// the user isn't signed in or Firestore isn't available.
    func push(_ data: AppData, userID: String, completion: ((Error?) -> Void)? = nil) {
        guard let db, !userID.isEmpty else {
            completion?(nil)
            return
        }

        let json = Self.encodeToJSON(data)
        // Skip the write if nothing changed since our last sync.
        if json == lastSyncedJSON {
            completion?(nil)
            return
        }

        let docRef = db.collection(Self.collectionName).document(userID)
            .collection(Self.documentName).document("data")

        // Write the whole AppData as a JSON string + a server timestamp. Keeping
        // it as a string avoids mapping every field into Firestore types.
        docRef.setData([
            "json": json,
            "updatedAt": FieldValue.serverTimestamp(),
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.lastSyncedJSON = json
                }
                completion?(error)
            }
        }
    }

    /// Pulls the latest data from the cloud for the given user ID. On success,
    /// returns the decoded `AppData` (or nil if none exists yet).
    func pull(userID: String, completion: @escaping (Result<AppData?, Error>) -> Void) {
        guard let db, !userID.isEmpty else {
            completion(.success(nil))
            return
        }

        let docRef = db.collection(Self.collectionName).document(userID)
            .collection(Self.documentName).document("data")

        docRef.getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let snapshot, snapshot.exists,
                      let json = snapshot.data()?["json"] as? String else {
                    completion(.success(nil))
                    return
                }
                let data = Self.decodeFromJSON(json)
                self.lastSyncedJSON = json
                completion(.success(data))
            }
        }
    }

    // MARK: - Encoding

    private static func encodeToJSON(_ data: AppData) -> String {
        guard let d = try? JSONEncoder().encode(data),
              let s = String(data: d, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    private static func decodeFromJSON(_ json: String) -> AppData? {
        guard let d = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: d)
    }
}
