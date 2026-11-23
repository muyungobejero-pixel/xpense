import SwiftUI
import GoogleSignIn

/// Shown on launch. Offers "Sign in with Google" and a "Skip" option so the
/// user can either authenticate or continue using the app locally.
struct LoginView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App branding
            VStack(spacing: 12) {
                Text("X")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 88, height: 88)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.31, green: 0.55, blue: 1.0), Color(red: 0.48, green: 0.36, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text("Xpense")
                    .font(.largeTitle.bold())

                Text("Track your monthly expenses.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                GoogleSignInButton {
                    auth.signIn()
                }

                Button {
                    auth.skip()
                } label: {
                    Text("Continue without signing in")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
                .frame(height: 24)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// A self-contained "Sign in with Google" button using the official branding
/// guideline (white background, Google logo + "Sign in with Google" text).
struct GoogleSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Google "G" logo
                GoogleLogo()
                    .frame(width: 18, height: 18)

                Text("Sign in with Google")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.23, green: 0.23, blue: 0.23))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

/// Renders the Google "G" mark as a Shape so it needs no bundled assets.
private struct GoogleLogo: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // Simple four-color "G" approximation.
                Circle()
                    .stroke(Color(red: 0.26, green: 0.52, blue: 0.96), lineWidth: s * 0.18)
                // Horizontal bar of the "G"
                Rectangle()
                    .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .frame(width: s * 0.34, height: s * 0.16)
                    .offset(x: s * 0.05, y: s * 0.12)
            }
        }
    }
}
