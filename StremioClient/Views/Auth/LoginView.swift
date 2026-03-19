import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo area
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Theme.accent)
                    Text("Stremio Client")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your personal streaming hub")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                        .padding()
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.textPrimary)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.textPrimary)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await signIn() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                }
                .padding(.horizontal, 32)

                Spacer()

                Text("Use your Stremio account credentials")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func signIn() async {
        isLoading = true
        errorMessage = nil
        do {
            try await appState.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
