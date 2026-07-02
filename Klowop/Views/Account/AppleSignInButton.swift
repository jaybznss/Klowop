import SwiftUI
import AuthenticationServices

/// Sign in with Apple button that completes the backend handshake.
struct AppleSignInButton: View {
    var onSignedIn: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 8) {
            if isWorking {
                // Swap the button out entirely — a spinner floating over the
                // Apple wordmark reads as broken.
                ProgressView("Signing in…")
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Couldn't read the Apple credential. Please try again."
                return
            }
            let email = credential.email
            isWorking = true
            errorMessage = nil
            Task { @MainActor in
                defer { isWorking = false }
                do {
                    try await BackendService.shared.signInWithApple(identityToken: token, email: email)
                    onSignedIn()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            // Cancellation is expected and not an error worth surfacing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }
}
