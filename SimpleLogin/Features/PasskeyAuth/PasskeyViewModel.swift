//
//  PasskeyViewModel.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import Foundation
import UIKit

@MainActor
@Observable
final class PasskeyViewModel: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let relyingPartyIdentifier = "simplelogin-passkeys-dev.web.app"

    var assertionResult: PasskeyAssertionResult?
    var errorMessage: String?

    struct PasskeyAssertionResult {
        let credentialID: Data
        let userHandle: Data
        let signature: Data
        let authenticatorData: Data
        let clientDataJSON: Data
    }

    func signInWithPasskey() {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        let request = provider.createCredentialAssertionRequest(challenge: fetchChallengeFromServer())
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func registerPasskey() {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        let request = provider.createCredentialRegistrationRequest(
            challenge: fetchChallengeFromServer(),
            name: "user@example.com",
            userID: Data("user-unique-id".utf8)
        )
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {
        case let assertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            assertionResult = PasskeyAssertionResult(
                credentialID: assertion.credentialID,
                userHandle: assertion.userID,
                signature: assertion.signature,
                authenticatorData: assertion.rawAuthenticatorData,
                clientDataJSON: assertion.rawClientDataJSON
            )
            errorMessage = nil
        case let registration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            errorMessage = nil
            _ = registration
        default:
            errorMessage = "Unhandled credential type."
        }
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

    private func fetchChallengeFromServer() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
