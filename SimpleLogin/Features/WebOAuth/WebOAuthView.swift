//
//  WebOAuthView.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import SwiftUI

struct WebOAuthView: View {
    @Bindable var viewModel: WebOAuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("Delegate authentication to a third-party identity provider via system browser.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Toggle("Ephemeral Session (Private)", isOn: $viewModel.useEphemeralSession)
                    .padding(.horizontal, 40)

                Button {
                    viewModel.startOAuthFlow()
                } label: {
                    Label("Sign in with GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .padding(.horizontal, 40)

                if let code = viewModel.authorizationCode {
                    GroupBox("Authorization Code") {
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()
            .navigationTitle("Web OAuth")
        }
    }
}

#Preview {
    NavigationStack {
        WebOAuthView(viewModel: WebOAuthViewModel())
    }
}
