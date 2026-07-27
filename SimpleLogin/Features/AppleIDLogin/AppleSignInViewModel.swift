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
    var authState: AuthState?

    override init() {
        super.init()
    }

    func bindAuthState(_ authState: AuthState) {
        self.authState = authState
    }

    func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handlePublicResult(_ result: Result<ASAuthorization, Error>) {
        handleResult(result)
    }

    func startSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
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

    private func handleResult(_ result: Result<ASAuthorization, Error>) {
        guard let authState else { return }
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
}
