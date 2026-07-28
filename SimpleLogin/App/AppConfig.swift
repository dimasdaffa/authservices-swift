//
//  AppConfig.swift
//  SimpleLogin
//
//  Created by DIMAS DAFFA ERNANDA on 28/07/26.
//

import Foundation

enum AppConfig {
    private static func infoValue(forKey key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            fatalError("\(key) missing or empty in Info.plist / Config.xcconfig")
        }
        return value
    }

    static var passkeyRelyingPartyID: String {
        infoValue(forKey: "PASSKEY_RELYING_PARTY_ID")
    }

    static var githubClientID: String {
        infoValue(forKey: "GITHUB_CLIENT_ID")
    }

    static var oauthCallbackScheme: String {
        infoValue(forKey: "OAUTH_CALLBACK_SCHEME")
    }
}
