//
//  AppleSignInViewModel.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppleSignInViewModel: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let authState: AuthState

    init(authState: AuthState) {
        self.authState = authState
        super.init()
    }

    func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authState.errorMessage = "Unexpected credential type."
                return
            }
            authState.userIdentifier = credential.user
            if let nameComponents = credential.fullName {
                authState.displayName = PersonNameComponentsFormatter.localizedString(from: nameComponents, style: .default)
            }
            authState.email = credential.email
            if let tokenData = credential.identityToken,
               let tokenString = String(data: tokenData, encoding: .utf8) {
                authState.identityToken = tokenString
            }
            authState.isAuthenticated = true
            authState.errorMessage = nil
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            authState.errorMessage = error.localizedDescription
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        handleResult(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        handleResult(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let window = scene.windows.first
        else {
            fatalError("No window scene available.")
        }
        return window
    }
}
