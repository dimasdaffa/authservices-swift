
---

# Apple's Authentication Services: Concepts, Analogies, and HIG Rules

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
│   └── AuthState.swift
└── Features/
    ├── AppleIDLogin/        (Sign in with Apple)
    ├── PasskeyAuth/         (FIDO2 / WebAuthn)
    ├── WebOAuth/            (ASWebAuthenticationSession)
    └── PasswordAutoFill/    (iCloud Keychain AutoFill)

```

---

### Shared State (`AuthState.swift`)

```swift
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
3. **`credential.identityToken` (Signed JWT):** A Base64 JSON Web Token signed by Apple. Your backend must verify this token against Apple's public key endpoint (`[https://appleid.apple.com/auth/keys](https://appleid.apple.com/auth/keys)`) before issuing an application session.

#### Required Setup & Configuration

1. **Xcode Capability:** Select App Target $\rightarrow$ **Signing & Capabilities** $\rightarrow$ **+ Capability** $\rightarrow$ **Sign In with Apple**.
2. **App ID Registration:** Ensure your Bundle Identifier has **Sign In with Apple** enabled in the [Apple Developer Portal](https://developer.apple.com).
3. **Server Validation:** Send `identityToken` to your API server to verify `iss` (issuer), `aud` (Bundle ID), and `sub` (User ID) claims against Apple's keys.

---

### 2.2 Passkeys (`ASAuthorizationPlatformPublicKeyCredentialProvider`)

#### Code Implementation

```swift
// MARK: - Features/PasskeyAuth/PasskeyViewModel.swift

@Observable
final class PasskeyViewModel: NSObject, 
    ASAuthorizationControllerDelegate, 
    ASAuthorizationControllerPresentationContextProviding 
{
    private let relyingPartyIdentifier = "yourdomain.com"
    var errorMessage: String?

    func signInWithPasskey() {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        // Challenge MUST be fetched from your server in production
        let challenge = fetchChallengeFromServer()
        let request = provider.createCredentialAssertionRequest(challenge: challenge)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(
        controller: ASAuthorizationController, 
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // Send assertion.signature and rawAuthenticatorData to backend for cryptographic verification
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue { return }
        errorMessage = error.localizedDescription
    }

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

```

#### Required Setup & Configuration

1. **Xcode Capability**: Select App Target $\rightarrow$ **Signing & Capabilities** $\rightarrow$ Add **Associated Domains**.
2. **Domain Entry**: Add an entry under Domains formatted as:
```text
webcredentials:yourdomain.com

```


3. **Server AASA File**: Host an `apple-app-site-association` file on your server over HTTPS at `[https://yourdomain.com/.well-known/apple-app-site-association](https://yourdomain.com/.well-known/apple-app-site-association)`:
```json
{
  "webcredentials": {
    "apps": [ "TEAMID.com.yourcompany.yourapp" ]
  }
}

```


4. **Relying Party ID**: Ensure `relyingPartyIdentifier` in your ViewModel matches `yourdomain.com` exactly.

---

### 2.3 Third-Party Web OAuth (`ASWebAuthenticationSession`)

#### Code Implementation

```swift
// MARK: - Features/WebOAuth/WebOAuthViewModel.swift

@Observable
final class WebOAuthViewModel: NSObject, ASWebAuthenticationPresentationContextProviding {
    var authorizationCode: String?
    var errorMessage: String?
    
    private let clientID = "YOUR_GITHUB_CLIENT_ID"
    private let callbackScheme = "myapp"

    func startOAuthFlow() {
        guard let authURL = URL(string: "https://github.com/login/oauth/authorize?client_id=\(clientID)&redirect_uri=\(callbackScheme)://oauth-callback&scope=user:email") else { return }

        let session = ASWebAuthenticationSession(
            url: authURL, 
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            if let error {
                let nsError = error as NSError
                if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                   nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return }
                self.errorMessage = error.localizedDescription
                return
            }

            if let callbackURL,
               let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                self.authorizationCode = code
                // Send code to backend to exchange for an access token
            }
        }
        
        session.presentationContextProvider = self
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first else { fatalError("No window scene available.") }
        return window
    }
}

```

#### Required Setup & Configuration

1. **OAuth Application**: Register an OAuth app in your provider's developer console (e.g., GitHub Developer Settings). Set the callback URL to `myapp://oauth-callback`.
2. **Info.plist Custom Scheme**: In Xcode $\rightarrow$ App Target $\rightarrow$ **Info** tab $\rightarrow$ Expand **URL Types** $\rightarrow$ Add a new item and set **URL Schemes** to `myapp`.
3. **Client ID**: Copy the generated Client ID from your OAuth provider into `clientID`. Never embed your `client_secret` in the mobile app binary; token exchange must happen server-side.

---

### 2.4 Saved Password AutoFill (`ASAuthorizationPasswordProvider`)

#### Code Implementation

```swift
// MARK: - Features/PasswordAutoFill/PasswordAutoFillViewModel.swift

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

## 3. Technical Concepts & Mental Models

### Biometrics vs. Account Relationship

Developers frequently conflate `LAContext` (LocalAuthentication) with `ASAuthorizationAppleIDCredential` (AuthenticationServices). They operate at different layers of the iOS security stack.

| Dimension | `LAContext` (LocalAuthentication) | `ASAuthorizationAppleIDCredential` (AuthenticationServices) |
| --- | --- | --- |
| **Mental Model** | 🔐 **Local Gatekeeper**: "Prove you hold this device right now" | 🛂 **Global Passport**: "Prove you own this Apple ID account" |
| **What It Verifies** | Local biometric or passcode ownership | Apple ID identity via iCloud |
| **Scope** | Current device only | All devices signed into the Apple ID |
| **Cryptographic Root** | Secure Enclave (device-bound key) | Apple Identity Service (iCloud-synced token) |
| **Credential Type** | Boolean (pass/fail) | `ASAuthorizationAppleIDCredential` with JWT, user ID, email |
| **Network Required** | No | Yes (initial authorization) |
| **Survives Device Wipe** | No: Secure Enclave keys are destroyed | Yes: credential is tied to Apple ID account |
| **Returns Identity** | No: confirms local presence only | Yes: returns stable `user` identifier, optional email/name |

**Key distinction**: `LAContext` answers *"Is an authorized user holding this phone right now?"*, while `ASAuthorizationAppleIDCredential` answers *"Which user is this across Apple's entire ecosystem?"*

### Authorizing Identity: OAuth vs. SSO

#### OAuth: "The Bar ID Analogy"

OAuth is a bouncer checking your ID at a bar entrance.

1. You approach the bar (the app).
2. The bouncer asks for your ID (redirects to identity provider).
3. You show your driver's license (authenticate with Google/GitHub).
4. The bouncer verifies your age and lets you in (receives an authorization code).
5. The bouncer **does not** keep a copy or make a new ID for you. The bar next door must check you independently.

#### SSO: "The Festival Wristband Analogy"

SSO is getting a wristband at a music festival entrance.

1. You show your ticket at the main gate (authenticate once with identity provider).
2. Staff gives you a wristband (the IdP issues a session token/assertion).
3. Every stage, food vendor, and VIP tent inspects your wristband and grants access without re-checking your ticket.

**Sign in with Apple operates as a hybrid OAuth-SSO.** It uses OAuth 2.0 protocol mechanics (authorization code grant, token exchange) while providing an SSO experience to the user: a single Apple ID login grants access across all their devices via iCloud.

---

## 4. HIG Rules & App Store Review Guidelines

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

1. Revoke the token via Apple's revocation endpoint (`POST [https://appleid.apple.com/auth/revoke](https://appleid.apple.com/auth/revoke)`).
2. Delete the user record on your server.

```swift
func revokeAppleIDToken(_ refreshToken: String) async throws {
    let url = URL(string: "https://appleid.apple.com/auth/revoke")!
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

**Part 2: Storage Architecture & ASProvider Execution Models** will explore the low-level systems beneath these APIs: how the Secure Enclave generates asymmetric key pairs for passkeys, AES-256-GCM encryption boundaries around Keychain items, sandbox isolation between `kSecAttrAccessGroup` domains, and the `authd` system daemon execution pipeline.

---

*Questions or feedback on implementing `AuthenticationServices`? Let's discuss in the responses below.*