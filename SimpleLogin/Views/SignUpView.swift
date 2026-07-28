//
//  SignUpView.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 28/07/26.
//

import SwiftUI

struct SignUpView: View {
    @Bindable var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                        .padding(.top, 20)
                    
                    formSection
                    
                    if let error = authState.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 24)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.badge.plus.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            
            Text("Create Account")
                .font(.largeTitle.bold())
            
            Text("Sign up to test AutoFill & Keychain saving")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Sign Up Form

    private var formSection: some View {
        VStack(spacing: 12) {
            TextField("Email or Username", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
            
            // Eye icon toggle for New Password
            CustomSecureField(
                placeholder: "New Password",
                text: $password,
                contentType: .newPassword
            )
            
            // Eye icon toggle for Confirm Password
            CustomSecureField(
                placeholder: "Confirm Password",
                text: $confirmPassword,
                contentType: .newPassword
            )
            
            Button {
                handleSignUp()
            } label: {
                Text("Create Account")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(username.isEmpty || password.isEmpty)
        }
    }
    
    private func handleSignUp() {
        guard !username.isEmpty, !password.isEmpty else { return }
        
        if password != confirmPassword {
            authState.errorMessage = "Passwords do not match."
            return
        }
        
        // Register user state
        authState.userIdentifier = username
        authState.displayName = username
        authState.email = username.contains("@") ? username : nil
        authState.isAuthenticated = true
        authState.errorMessage = nil
        
        dismiss()
    }
}

#Preview {
    SignUpView(authState: AuthState())
}
