//
//  PasskeyViewModel.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import SwiftUI
import UIKit

@MainActor
@Observable
final class PasskeyViewModel: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private let relyingPartyIdentifier = "simplelogin-passkeys-dev.web.app"
    
    var authState: AuthState?
    var errorMessage: String?
    
    // 1. ADD THIS PROPERTY
    var assertionResult: ASAuthorizationPlatformPublicKeyCredentialAssertion?

    func bindAuthState(_ authState: AuthState) {
        self.authState = authState
    }

    // MARK: - Passkey Registration

    func registerPasskey(username: String) {
        errorMessage = nil
        assertionResult = nil
        
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let challenge = fetchChallengeFromServer()
        let userID = username.data(using: .utf8) ?? Data()

        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: username,
            userID: userID
        )

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Passkey Assertion

    func signInWithPasskey() {
        errorMessage = nil
        assertionResult = nil
        
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let challenge = fetchChallengeFromServer()
        let request = provider.createCredentialAssertionRequest(challenge: challenge)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            print("Passkey registered for ID: \(registration.credentialID)")
            authState?.errorMessage = nil
            
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // 2. STORE ASSERTION FOR THE VIEW
            self.assertionResult = assertion
            
            let userString = String(data: assertion.userID, encoding: .utf8) ?? "Passkey User"
            
            authState?.userIdentifier = userString
            authState?.displayName = userString
            authState?.isAuthenticated = true
            authState?.errorMessage = nil
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue { return }
        errorMessage = error.localizedDescription
    }

    // MARK: - Presentation Anchor

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first else { fatalError("No window scene available.") }
        return window
    }

    private func fetchChallengeFromServer() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
