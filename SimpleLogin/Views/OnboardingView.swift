//
//  OnboardingView.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import SwiftUI

struct OnboardingView: View {
    @State private var authState = AuthState()
    @State private var passkeyViewModel = PasskeyViewModel()
    @State private var webOAuthViewModel = WebOAuthViewModel()
    @State private var appleSignInViewModel = AppleSignInViewModel()
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showSignUpSheet: Bool = false
    
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
                    
                    signUpLink
                        .padding(.top, 16)
                    
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
        .sheet(isPresented: $showSignUpSheet) {
            SignUpView(authState: authState)
        }
        .onAppear {
            appleSignInViewModel.bindAuthState(authState)
            passkeyViewModel.bindAuthState(authState)
            webOAuthViewModel.bindAuthState(authState)
        }
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
            
            Button {
                let user = authState.email ?? authState.displayName ?? authState.userIdentifier ?? "User"
                passkeyViewModel.registerPasskey(username: user)
            } label: {
                Label("Register Passkey for this Account", systemImage: "key.badge.plus")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            
            Button("Sign Out", role: .destructive) {
                authState.reset()
                username = ""
                password = ""
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
                guard !username.isEmpty, !password.isEmpty else { return }
                authState.userIdentifier = username
                authState.displayName = username
                authState.email = username.contains("@") ? username : nil
                authState.isAuthenticated = true
            } label: {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(username.isEmpty || password.isEmpty)
        }
    }
    
    // MARK: - Sign Up Trigger
    
    private var signUpLink: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .foregroundStyle(.secondary)
            Button("Sign Up") {
                showSignUpSheet = true
            }
            .fontWeight(.semibold)
        }
        .font(.subheadline)
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
            HStack(spacing: 20) {
                socialIconButton(systemImage: "apple.logo", label: "Apple") {
                    appleSignInViewModel.startSignIn()
                }
                
                socialIconButton(assetImage: "github-logo", label: "GitHub") {
                    webOAuthViewModel.startOAuthFlow()
                }
                .foregroundStyle(.black)
                
                socialIconButton(systemImage: "key.fill", label: "Passkey") {
                    passkeyViewModel.signInWithPasskey()
                }
            }
            .padding(.top, 4)
            
            if let error = passkeyViewModel.errorMessage ?? webOAuthViewModel.errorMessage ?? authState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func socialIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(.thickMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
        .accessibilityLabel("Continue with \(label)")
    }
    
    private func socialIconButton(assetImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(assetImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .background(.thickMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
        .accessibilityLabel("Continue with \(label)")
    }
}

#Preview {
    OnboardingView()
}
