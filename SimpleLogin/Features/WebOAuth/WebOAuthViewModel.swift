//
//  WebOAuthViewModel.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import AuthenticationServices
import Foundation
import UIKit

@MainActor
@Observable
final class WebOAuthViewModel: NSObject, ASWebAuthenticationPresentationContextProviding {
    var authorizationCode: String?
    var errorMessage: String?
    var useEphemeralSession: Bool = false

    private let clientID = "YOUR_GITHUB_CLIENT_ID"
    private let callbackScheme = "myapp"

    func startOAuthFlow() {
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://oauth-callback"),
            URLQueryItem(name: "scope", value: "user:email"),
            URLQueryItem(name: "state", value: UUID().uuidString),
        ]

        guard let authURL = components.url else {
            errorMessage = "Failed to construct authorization URL."
            return
        }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self else { return }

            if let error {
                let nsError = error as NSError
                if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                   nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    return
                }
                self.errorMessage = error.localizedDescription
                return
            }

            guard let callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                self.errorMessage = "No authorization code in callback."
                return
            }

            self.authorizationCode = code
            self.errorMessage = nil
        }

        session.prefersEphemeralWebBrowserSession = useEphemeralSession
        session.presentationContextProvider = self
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
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
