import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Bindable var auth: SessionStore
    var client: AuthClient
    @State private var email = ""
    @State private var token = ""
    @State private var message = "登录后才能阅读。未登录不会读取任何站点。"
    @State private var busy = false

    init(auth: SessionStore, client: AuthClient = AuthClient(
        baseURL: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
        transport: URLSessionTransport()
    )) {
        self.auth = auth
        self.client = client
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("晨读")
                .font(Font.custom("MaShanZheng-Regular", size: 56))
                .accessibilityIdentifier("wordmark")
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color(Ink.muted))
            TextField("邮箱", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(Ink.card))
                .accessibilityIdentifier("loginEmail")
            Button(busy ? "发送中" : "发送登录链接") { Task { await send() } }
                .buttonStyle(.borderedProminent)
                .disabled(busy || email.isEmpty)
                .accessibilityIdentifier("sendMagicLink")
            TextField("邮件里的验证码", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(Ink.card))
                .accessibilityIdentifier("magicToken")
            Button("验证并进入") { Task { await verify() } }
                .buttonStyle(.bordered)
                .disabled(busy || token.isEmpty)
                .accessibilityIdentifier("verifyMagicLink")
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await finishApple(result) }
            }
            .frame(height: 44)
            .accessibilityIdentifier("appleSignIn")
            Spacer()
        }
        .padding(24)
        .background(Color(Ink.paper))
    }

    private func send() async {
        busy = true
        defer { busy = false }
        do {
            try await client.sendMagicLink(email: email)
            message = "链接已发出。本地 Supabase 的验证码在 Inbucket（127.0.0.1:54324）。"
        } catch {
            message = "发送失败"
        }
    }

    private func verify() async {
        busy = true
        defer { busy = false }
        do {
            let session = try await client.verifyMagicLink(email: email, token: token)
            try auth.save(session)
        } catch {
            message = "验证失败"
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else {
            message = "Apple 登录还没配好。见 docs/USER_SETUP.md。"
            return
        }
        do {
            let session = try await client.signInWithApple(idToken: idToken, nonce: credential.user)
            try auth.save(session)
        } catch {
            message = "Apple 登录失败"
        }
    }
}
