//
//  PasskeyView.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import SwiftUI

struct PasskeyView: View {
    var viewModel: PasskeyViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.indigo)

                Text("FIDO2/WebAuthn passkey authentication. Zero shared secrets.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.signInWithPasskey()
                } label: {
                    Label("Authenticate with Passkey", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
                .padding(.horizontal, 40)

                Button {
                    let username = viewModel.authState?.email ?? viewModel.authState?.userIdentifier ?? "User"
                    viewModel.registerPasskey(username: username)
                } label: {
                    Label("Register New Passkey", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal, 40)

                if let assertion = viewModel.assertionResult {
                    GroupBox("Assertion Result") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Credential ID", value: assertion.credentialID.base64EncodedString().prefix(24) + "…")
                            LabeledContent("User Handle", value: assertion.userID.base64EncodedString())
                            Text("Signature & authenticatorData available for server verification.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()
            .navigationTitle("Passkey Auth")
        }
    }
}

#Preview {
    NavigationStack {
        PasskeyView(viewModel: PasskeyViewModel())
    }
}
