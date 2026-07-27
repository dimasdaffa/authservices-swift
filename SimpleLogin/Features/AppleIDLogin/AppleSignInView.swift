//
//  AppleSignInView.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import SwiftUI

struct AppleSignInView: View {
    @Bindable var viewModel: AppleSignInViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.authState.isAuthenticated {
                    authenticatedView
                } else {
                    unauthenticatedView
                }
            }
            .padding()
            .navigationTitle("Sign in with Apple")
        }
    }

    private var unauthenticatedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "apple.logo")
                .font(.system(size: 64))
                .foregroundStyle(.primary)

            Text("Authenticate using your Apple ID with end-to-end system-level security.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            SignInWithAppleButton(.signIn, onRequest: viewModel.configureRequest, onCompletion: viewModel.handleResult)
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .padding(.horizontal, 40)

            if let error = viewModel.authState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private var authenticatedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            LabeledContent("User ID", value: viewModel.authState.userIdentifier ?? "—")
            LabeledContent("Name", value: viewModel.authState.displayName ?? "—")
            LabeledContent("Email", value: viewModel.authState.email ?? "—")

            if let token = viewModel.authState.identityToken {
                DisclosureGroup("Identity Token (JWT)") {
                    Text(token)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Button("Sign Out", role: .destructive) {
                viewModel.authState.reset()
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppleSignInView(viewModel: AppleSignInViewModel(authState: AuthState()))
    }
}
