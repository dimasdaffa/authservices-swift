//
//  PasswordAutoFillView.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import SwiftUI

struct PasswordAutoFillView: View {
    @Bindable var viewModel: PasswordAutoFillViewModel
    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "key.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.teal)

                Text("Query iCloud Keychain for saved credentials via system AutoFill.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    TextField("Username or Email", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 40)

                Button {
                    viewModel.requestSavedCredentials()
                } label: {
                    Label("Use Saved Password", systemImage: "rectangle.and.pencil.and.ellipsis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .controlSize(.large)
                .padding(.horizontal, 40)

                if let credential = viewModel.retrievedCredential {
                    GroupBox("Retrieved Credential") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("User", value: credential.user)
                            LabeledContent("Password", value: "••••••••")
                        }
                    }
                    .onAppear {
                        username = credential.user
                        password = credential.password
                    }
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()
            .navigationTitle("Password AutoFill")
        }
    }
}
