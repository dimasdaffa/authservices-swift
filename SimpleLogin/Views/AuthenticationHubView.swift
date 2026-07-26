//
//  AuthenticationHubView.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import SwiftUI

struct AuthenticationHubView: View {
    @State private var authState = AuthState()

    var body: some View {
        TabView {
            Tab("Apple ID", systemImage: "apple.logo") {
                AppleSignInView(viewModel: AppleSignInViewModel(authState: authState))
            }
            Tab("Passkey", systemImage: "person.badge.key.fill") {
                PasskeyView(viewModel: PasskeyViewModel())
            }
            Tab("OAuth", systemImage: "globe") {
                WebOAuthView(viewModel: WebOAuthViewModel())
            }
            Tab("Password", systemImage: "key.fill") {
                PasswordAutoFillView(viewModel: PasswordAutoFillViewModel(authState: authState))
            }
        }
    }
}
