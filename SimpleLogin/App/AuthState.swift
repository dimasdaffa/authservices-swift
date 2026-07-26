//
//  AuthState.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 26/07/26.
//

import Foundation

@Observable
final class AuthState {
    var userIdentifier: String?
    var displayName: String?
    var email: String?
    var identityToken: String?
    var isAuthenticated: Bool = false
    var errorMessage: String?

    func reset() {
        userIdentifier = nil
        displayName = nil
        email = nil
        identityToken = nil
        isAuthenticated = false
        errorMessage = nil
    }
}
