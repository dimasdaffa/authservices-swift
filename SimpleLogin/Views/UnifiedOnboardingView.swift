//
//  UnifiedOnboardingView.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import SwiftUI

struct UnifiedOnboardingView: View {
    @State private var authState = AuthState()
    @State private var passkeyViewModel = PasskeyViewModel()
    @State private var webOAuthViewModel = WebOAuthViewModel()
    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 60)
                    .padding(.bottom, 32)

                if authState.isAuthenticated {
                    authenticatedSection
                } else {
                    loginFormSection
                        .padding(.horizontal, 16)

                    dividerLine
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)

                    socialButtonsSection
                        .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Welcome Back")
                .font(.largeTitle.bold())

            Text("Sign in to continue")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Authenticated State

    private var authenticatedSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            LabeledContent("User ID", value: authState.userIdentifier ?? "—")
            LabeledContent("Name", value: authState.displayName ?? "—")
            LabeledContent("Email", value: authState.email ?? "—")

            if let token = authState.identityToken {
                DisclosureGroup("Identity Token (JWT)") {
                    Text(token)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Button("Sign Out", role: .destructive) {
                authState.reset()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }

    // MARK: - Login Form

    private var loginFormSection: some View {
        VStack(spacing: 12) {
            TextField("Username or Email", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)

            Button {
                // Submit credentials
            } label: {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }

    // MARK: - Divider

    private var dividerLine: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
            Text("or")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Social Buttons

    private var socialButtonsSection: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn, onRequest: { _ in }, onCompletion: { _ in })
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)

            Button {
                passkeyViewModel.signInWithPasskey()
            } label: {
                HStack {
                    Image(systemName: "key.fill")
                    Text("Continue with Passkey")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.bordered)

            Button {
                webOAuthViewModel.startOAuthFlow()
            } label: {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("Continue with GitHub")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.bordered)

            if let error = passkeyViewModel.errorMessage ?? webOAuthViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    UnifiedOnboardingView()
}
