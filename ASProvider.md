
```markdown
# Apple's Authentication Services: Implementation & Setup Guide

**Part 1 of 2** · iOS 17+ · Swift 6 · Xcode 16

---

## 1. Framework Architecture Overview

`AuthenticationServices` is not an authentication engine. It is a **delegation surface**: a unified API through which your app hands identity verification to the iOS system layer, the Secure Enclave, and Apple's identity servers. Your app never touches raw credentials. It issues *requests*, the OS presents system-controlled UI, hardware performs cryptographic operations, and your app receives *attestations*.

This architecture enforces a hard security boundary: the app process cannot intercept, modify, or spoof the authentication dialog. The system owns the entire credential lifecycle.

### The Four Core Flows

| Flow | Protocol | Credential Type | Storage Domain |
| --- | --- | --- | --- |
| **Apple ID Native Auth** | Apple's proprietary OAuth 2.0 | `ASAuthorizationAppleIDCredential` (JWT identity token, relay email) | iCloud Keychain (synced) |
| **Passkeys (FIDO2/WebAuthn)** | CTAP2 / WebAuthn | `ASAuthorizationPlatformPublicKeyCredentialAssertion` (public-key pair) | iCloud Keychain (synced, E2E encrypted) |
| **Web OAuth Delegation** | OAuth 2.0 / OpenID Connect | Authorization code via callback URL | Ephemeral browser session (no persistence by default) |
| **Password AutoFill** | None (keychain query) | `ASPasswordCredential` (username + password) | iCloud Keychain / local Keychain |

Each flow converges on the same delegate pattern: construct an `ASAuthorizationController`, attach requests, and implement `ASAuthorizationControllerDelegate` to receive the result. The system decides which UI to present (biometric prompt, passkey sheet, Safari view controller, or keyboard AutoFill bar) based on the request type.

---

## 2. Implementation & Required Setup for Each ASProvider

Rather than dumping all logic into a single monolithic view, production iOS apps isolate each `ASProvider` flow into its own Feature directory (`Features/AppleIDLogin`, `Features/PasskeyAuth`, etc.) using Swift 6 `@Observable` ViewModels.

```text
SimpleLogin/
├── App/
│   ├── AppConfig.swift         (Type-safe environment wrapper)
│   ├── AuthState.swift         (Global authentication state)
│   └── SimpleLoginApp.swift
├── Features/
│   ├── AppleIDLogin/        (Sign in with Apple)
│   ├── PasskeyAuth/         (FIDO2 / WebAuthn)
│   ├── WebOAuth/            (ASWebAuthenticationSession)
│   └── PasswordAutoFill/    (iCloud Keychain AutoFill)
├── Config.example.xcconfig     (Template committed to source control)
└── Config.xcconfig             (Local secrets - added to .gitignore)

```

---

### Environment & Secret Management Setup

To avoid committing sensitive keys, credentials, or environment domains to source control, use Xcode Configuration files (`.xcconfig`) coupled with a type-safe `AppConfig` wrapper.

#### 1. Version-Controlled Template (`Config.example.xcconfig`)

Commit this file to your repository as a template for team members:

```text
// Config.example.xcconfig
// Copy this file to Config.xcconfig and supply your environment values.

PASSKEY_RELYING_PARTY_ID = your-domain.web.app
GITHUB_CLIENT_ID = YOUR_GITHUB_CLIENT_ID_HERE
OAUTH_CALLBACK_SCHEME = simplelogin

```

#### 2. Local Configuration File (`Config.xcconfig`)

Create `Config.xcconfig` locally and add `Config.xcconfig` to your `.gitignore`:

```text
// Config.xcconfig (Do NOT commit to git)

PASSKEY_RELYING_PARTY_ID = your-passkey-domain.web.app
GITHUB_CLIENT_ID = YOUR_ACTUAL_CLIENT_ID
OAUTH_CALLBACK_SCHEME = simplelogin

```

#### 3. Info.plist Evaluation

Map the build variables into your target's **Info** tab in Xcode so they can be read by `Bundle.main`:

| Key | Type | Value |
| --- | --- | --- |
| `PASSKEY_RELYING_PARTY_ID` | String | `$(PASSKEY_RELYING_PARTY_ID)` |
| `GITHUB_CLIENT_ID` | String | `$(GITHUB_CLIENT_ID)` |
| `OAUTH_CALLBACK_SCHEME` | String | `$(OAUTH_CALLBACK_SCHEME)` |

#### 4. Type-Safe Swift Wrapper (`AppConfig.swift`)

```swift
// MARK: - App/AppConfig.swift

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

```

---

### Shared State (`AuthState.swift`)

```swift
// MARK: - App/AuthState.swift

import AuthenticationServices
import SwiftUI

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

```

---

### 2.1 Native Sign in with Apple (`ASAuthorizationAppleIDProvider`)

#### Core Implementation

```swift
// MARK: - Features/AppleIDLogin/AppleSignInViewModel.swift

import AuthenticationServices
import SwiftUI

@MainActor
@Observable
final class AppleSignInViewModel: NSObject, 
    ASAuthorizationControllerDelegate, 
    ASAuthorizationControllerPresentationContextProviding 
{
    var authState: AuthState?

    func bindAuthState(_ authState: AuthState) {
        self.authState = authState
    }

    // Programmatic trigger for custom UI (e.g. custom icon/button)
    func startSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email] // Request user identity scopes

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests() // Launches system authorization sheet
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        handleResult(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        handleResult(.failure(error))
    }

    // Provides the window anchor for the system half-sheet UI
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first else { fatalError("No window scene available.") }
        return window
    }

    // MARK: - Credential Handling

    private func handleResult(_ result: Result<ASAuthorization, Error>) {
        guard let authState else { return }
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            
            // 1. Stable, team-scoped unique user identifier
            authState.userIdentifier = credential.user
            
            // 2. Full name (Delivered ONLY on first authorization!)
            if let nameComponents = credential.fullName {
                authState.displayName = PersonNameComponentsFormatter
                    .localizedString(from: nameComponents, style: .default)
            }
            
            // 3. Relay/Primary Email (Delivered ONLY on first authorization!)
            authState.email = credential.email
            
            // 4. Signed JWT identity token for backend server validation
            if let tokenData = credential.identityToken {
                authState.identityToken = String(data: tokenData, encoding: .utf8)
            }
            
            authState.isAuthenticated = true

        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue { return } // User dismissed sheet
            authState.errorMessage = error.localizedDescription
        }
    }
}

```

#### Triggering Authentication in SwiftUI

You can trigger this flow programmatically from custom UI or declaratively using Apple's native control:

```swift
// Approach 1: Programmatic Call (Used in UnifiedOnboardingView)
socialIconButton(systemImage: "apple.logo", label: "Apple") {
    appleSignInViewModel.startSignIn()
}

// Approach 2: Native System Button (Declarative Alternative)
SignInWithAppleButton(.signIn, onRequest: viewModel.configureRequest, onCompletion: viewModel.handlePublicResult)
    .signInWithAppleButtonStyle(.black)
    .frame(height: 50)

```

> **Note on App Store HIG Compliance:** While programmatic execution (`startSignIn()`) gives you full flexibility to trigger authentication from custom buttons, App Store Review Guideline 4.8 requires that any custom Sign in with Apple button maintains equal or greater visual prominence compared to other third-party login options. Alternatively, you can use Apple's pre-rendered `SignInWithAppleButton` control to guarantee HIG compliance out of the box.

#### Decoding the `ASAuthorizationAppleIDCredential` Payload

Upon successful authorization, the system delegate returns three key identity properties:

1. **`credential.user` (Persistent User ID):** A stable string (e.g., `001604.4e302e...`). This ID never changes across device restores or app reinstalls. Store this as the primary foreign key in your database.
2. **`credential.fullName` & `credential.email` (First-Time Only):** Delivered **only once** on initial registration. Subsequent logins return `nil` for both fields to protect user privacy. Your server must save them on first receipt.
3. **`credential.identityToken` (Signed JWT):** A Base64 JSON Web Token signed by Apple. Your backend must verify this token against Apple's public key endpoint (`https://appleid.apple.com/auth/keys`) before issuing an application session.

#### Required Setup & Configuration

1. **Xcode Capability:** Select App Target $\rightarrow$ **Signing & Capabilities** $\rightarrow$ **+ Capability** $\rightarrow$ **Sign In with Apple**.
2. **App ID Registration:** Ensure your Bundle Identifier has **Sign In with Apple** enabled in the Apple Developer Portal.
3. **Server Validation:** Send `identityToken` to your API server to verify `iss` (issuer), `aud` (Bundle ID), and `sub` (User ID) claims against Apple's keys.

---

### 2.2 Passkeys (`ASAuthorizationPlatformPublicKeyCredentialProvider`)

#### Code Implementation

```swift
// MARK: - Features/PasskeyAuth/PasskeyViewModel.swift

import AuthenticationServices
import SwiftUI
import UIKit

@MainActor
@Observable
final class PasskeyViewModel: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private let relyingPartyIdentifier = AppConfig.passkeyRelyingPartyID
    
    var authState: AuthState?
    var errorMessage: String?
    var assertionResult: ASAuthorizationPlatformPublicKeyCredentialAssertion?

    func bindAuthState(_ authState: AuthState) {
        self.authState = authState
    }

    // MARK: - Passkey Registration (Creation Request)

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

    // MARK: - Passkey Assertion (Sign-In Request)

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
            // New passkey created & saved to iCloud Keychain
            print("Passkey registered for ID: \(registration.credentialID)")
            authState?.errorMessage = nil
            
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // Passkey verified via Secure Enclave & Face ID / Touch ID
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
        // Challenge MUST be fetched from your server in production
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

```

---

#### Important Workflow Note: Registration Requirement

> **Critical Rule:** A user **MUST register a passkey first** (while authenticated via another method like Sign in with Apple or Email/Password) before they can use **Sign In with Passkey**.
> Passkeys rely on asymmetric public-private key pairs generated by the device's Secure Enclave and saved in **iCloud Keychain**. If a user attempts to sign in without an existing registered passkey for the domain:
> * iOS will find no matching credentials in iCloud Keychain.
> * iOS will fallback to displaying a QR code for cross-device (caBLE) authentication.
> * The request will fail with `ASCABLEClient.ClientError` if no secondary device has a key.
> 
> 

---

#### Required Setup & Configuration

1. **Xcode Capability**
* Select Target $\rightarrow$ **Signing & Capabilities** $\rightarrow$ **+ Capability** $\rightarrow$ **Associated Domains**.
* Add the following domain entry (append `?mode=developer` to bypass CDN caching during local development):
```text
webcredentials:YOUR_PASSKEY_DOMAIN.web.app?mode=developer

```




2. **Server AASA File Location & Format**
* File path on server: `https://YOUR_PASSKEY_DOMAIN/.well-known/apple-app-site-association` *(strictly NO file extension like `.json` or `.txt`)*.
* File content (matching App ID Prefix / Team ID from Apple Developer Portal):
```json
{
  "webcredentials": {
    "apps": [
      "YOUR_TEAM_ID.com.yourcompany.yourapp"
    ]
  }
}

```




3. **Firebase Hosting Configuration (`firebase.json`)**
* Ensure `firebase.json` allows hidden files in `ignore` and forces `Content-Type: application/json`:
```json
{
  "hosting": {
    "public": "public",
    "ignore": [
      "firebase.json",
      "**/node_modules/**"
    ],
    "headers": [
      {
        "source": "/.well-known/apple-app-site-association",
        "headers": [
          {
            "key": "Content-Type",
            "value": "application/json"
          }
        ]
      }
    ]
  }
}

```




4. **Relying Party ID**
* Ensure `PASSKEY_RELYING_PARTY_ID` in `Config.xcconfig` matches your domain name exactly.


5. **iOS Device Testing Requirements**
* On physical testing devices: Open **Settings** $\rightarrow$ **Developer** $\rightarrow$ Toggle **Associated Domains Development** to **ON**.



---

### 2.3 Third-Party Web OAuth (`ASWebAuthenticationSession`)

#### Code Implementation

```swift
// MARK: - Features/WebOAuth/WebOAuthViewModel.swift

import AuthenticationServices
import Foundation
import UIKit

@MainActor
@Observable
final class WebOAuthViewModel: NSObject, ASWebAuthenticationPresentationContextProviding {
    var authorizationCode: String?
    var errorMessage: String?
    var useEphemeralSession: Bool = false
    var authState: AuthState?

    // OAuth Credentials & Configuration from AppConfig
    private let clientID = AppConfig.githubClientID
    private let callbackScheme = AppConfig.oauthCallbackScheme

    func bindAuthState(_ authState: AuthState) {
        self.authState = authState
    }

    func startOAuthFlow() {
        errorMessage = nil
        
        // 1. Construct Authorization URL safely with URLComponents
        var components = URLComponents(string: "[https://github.com/login/oauth/authorize](https://github.com/login/oauth/authorize)")!
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

        // 2. Initialize Web Authentication Session
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            guard let self else { return }

            if let error {
                let nsError = error as NSError
                // Ignore user cancellation gracefully
                if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                   nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    return
                }
                self.errorMessage = error.localizedDescription
                return
            }

            // 3. Extract temporary authorization code from callback URL
            guard let callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                self.errorMessage = "No authorization code in callback."
                return
            }

            // 4. Update state & present authenticated view
            self.authorizationCode = code
            self.errorMessage = nil
            
            self.authState?.userIdentifier = "GitHub (\(code.prefix(8))...)"
            self.authState?.displayName = "GitHub User"
            self.authState?.isAuthenticated = true
        }

        session.prefersEphemeralWebBrowserSession = useEphemeralSession
        session.presentationContextProvider = self
        session.start()
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

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

```

---

#### Security & Architecture Notes

> **Production OAuth Flow:**
> 1. Mobile app receives temporary `authorization_code` from the redirect URL (`simplelogin://oauth-callback?code=...`).
> 2. Mobile app sends `authorization_code` to **your backend server**.
> 3. Your server securely exchanges `code` + `client_secret` with the provider (`https://github.com/login/oauth/access_token`).
> 4. **Never embed `client_secret` inside the iOS binary**, as it can be extracted via reverse engineering.
> 
> 

---

#### Required Setup & Configuration

1. **OAuth Application Setup (Provider Console)**
* Register an OAuth App in **GitHub Developer Settings** $\rightarrow$ **OAuth Apps**.
* **Homepage URL**: `https://YOUR_DOMAIN.web.app` (or your web application URL).
* **Authorization callback URL**: `simplelogin://oauth-callback` (matching your `OAUTH_CALLBACK_SCHEME`).


2. **Xcode Custom URL Scheme**
* Select Target $\rightarrow$ **Info** tab.
* Expand **URL Types** $\rightarrow$ Click **+**.
* Set **URL Schemes** to `simplelogin` *(matching `OAUTH_CALLBACK_SCHEME` without `://`)*.


3. **Session Privacy Modes**
* Default (`prefersEphemeralWebBrowserSession = false`): Shares cookies with Safari, allowing single sign-on if the user is already logged into the provider.
* Ephemeral (`prefersEphemeralWebBrowserSession = true`): Isolated private browser session with no shared cookies/cache.



---

### 2.4 Saved Password AutoFill (`ASAuthorizationPasswordProvider`)

#### Code Implementation

```swift
// MARK: - Features/PasswordAutoFill/PasswordAutoFillViewModel.swift

import AuthenticationServices
import SwiftUI

@Observable
final class PasswordAutoFillViewModel: NSObject, 
    ASAuthorizationControllerDelegate, 
    ASAuthorizationControllerPresentationContextProviding 
{
    var usernameText: String = ""
    var passwordText: String = ""

    func requestSavedCredentials() {
        let provider = ASAuthorizationPasswordProvider()
        let request = provider.createRequest()
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(
        controller: ASAuthorizationController, 
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let credential = authorization.credential as? ASPasswordCredential {
            usernameText = credential.user
            passwordText = credential.password
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {}

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first else { fatalError("No window scene available.") }
        return window
    }
}

```

#### Required Setup & Configuration

1. **Text Content Types**: In your SwiftUI view, explicitly mark input fields with `.textContentType(.username)` and `.textContentType(.password)` so the system keyboard knows to offer AutoFill suggestions from iCloud Keychain.
2. **Associated Domains**: Like Passkeys, this relies on the `webcredentials:yourdomain.com` entry under **Associated Domains** capability and the server's `apple-app-site-association` file.

---

## 3. HIG Rules & App Store Review Guidelines

These five rules represent the most common causes of App Store rejection for authentication implementations.

### Rule 1: Guideline 4.8 (Equivalence Rule)

> *"Apps that exclusively use a third-party or social login service (such as Facebook, Google, Twitter, LinkedIn, Amazon, or WeChat) to set up or authenticate the user's account must also offer Sign in with Apple as an equivalent option."*

* If your app includes **any** social login button, Sign in with Apple must be offered alongside it with equal visual prominence and functional parity.
* Standard email + password login does **not** trigger this rule. The moment you add a third-party social provider, the requirement activates.

### Rule 2: Native Button Integrity

`SignInWithAppleButton` is a system-rendered control and must be used as provided.

* ❌ **Prohibited**: Custom button shapes, overlaying text/icons, altering corner radii via hacks, or custom-drawn buttons mimicking Apple's style.
* ✅ **Allowed**: `.signInWithAppleButtonStyle(.black | .white | .whiteOutline)`, `.signInWithAppleButtonLabel(.signIn | .signUp | .continue)`, and height frame adjustments (minimum 30pt, recommended 44pt+).

### Rule 3: First-Time Payload Retention

`ASAuthorizationAppleIDCredential.fullName` and `.email` are delivered **only once** on the user's initial authorization. Every subsequent call returns `nil`.

Your backend must store these fields immediately alongside the stable `credential.user` identifier. If payload data is lost during development, revoke access via **Settings → Apple ID → Sign-In & Security → Sign in with Apple → [Your App] → Stop Using Apple ID** to trigger a fresh grant.

### Rule 4: Mandatory Account Deletion

Any app supporting account creation must provide an in-app account deletion flow. For Sign in with Apple, this requires two actions:

1. Revoke the token via Apple's revocation endpoint (`POST https://appleid.apple.com/auth/revoke`).
2. Delete the user record on your server.

```swift
func revokeAppleIDToken(_ refreshToken: String) async throws {
    let url = URL(string: "[https://appleid.apple.com/auth/revoke](https://appleid.apple.com/auth/revoke)")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let body = [
        "client_id": "com.yourcompany.yourapp",
        "client_secret": generateClientSecret(), // Server-generated JWT
        "token": refreshToken,
        "token_type_hint": "refresh_token"
    ]
    request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw RevocationError.serverRejected
    }
}

```

> **Security Warning**: `generateClientSecret()` must execute on your backend. Never embed your Sign in with Apple private key (`.p8`) in an app binary.

### Rule 5: System Terminology Compliance

Apple's Human Interface Guidelines require exact product terminology for biometric methods.

| ✅ Correct | ❌ Incorrect |
| --- | --- |
| Face ID | "facial recognition", "face scan", "biometrics" |
| Touch ID | "fingerprint", "biometric scan", "thumbprint" |
| Optic ID | "eye scan", "iris recognition" |

Query `LAContext().biometryType` at runtime to format UI strings dynamically:

```swift
func biometricDisplayName() -> String {
    let context = LAContext()
    var error: NSError?
    context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

    return switch context.biometryType {
    case .faceID: "Face ID"
    case .touchID: "Touch ID"
    case .opticID: "Optic ID"
    case .none: "Passcode"
    @unknown default: "Device Authentication"
    }
}

```

---

## What's Next

**Part 2: Deep-Dive Architecture, Mental Models & Storage** will explore the concepts behind these APIs:

* **Mental Models & Concepts**: Comparing `LAContext` vs `ASAuthorizationAppleIDCredential`, plus OAuth vs SSO analogies.
* **Low-Level Execution Pipeline**: How the `authd` system daemon and Secure Enclave coordinate during passkey generation.
* **Storage & Encryption Boundaries**: How iCloud Keychain handles AES-256-GCM encryption and sandbox isolation across `kSecAttrAccessGroup` domains.

```

```