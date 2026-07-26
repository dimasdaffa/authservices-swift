//
//  PasswordAutoFillViewModel.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import Foundation
import UIKit

@MainActor
@Observable
final class PasswordAutoFillViewModel: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let authState: AuthState

    var retrievedCredential: ASPasswordCredential?
    var errorMessage: String?

    init(authState: AuthState) {
        self.authState = authState
        super.init()
    }

    func requestSavedCredentials() {
        let passwordProvider = ASAuthorizationPasswordProvider()
        let request = passwordProvider.createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASPasswordCredential else {
            errorMessage = "Unexpected credential type."
            return
        }
        retrievedCredential = credential
        errorMessage = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return
        }
        errorMessage = error.localizedDescription
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
