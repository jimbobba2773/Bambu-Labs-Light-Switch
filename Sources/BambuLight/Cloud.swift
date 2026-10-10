import Foundation

enum CloudError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

enum LoginResult {
    case token(String)
    case needsCode
    case needsTFA(String)
}

struct CloudDevice: Identifiable, Hashable {
    let id: String   // serial number
    let name: String
}

enum CloudRegion: String, CaseIterable, Identifiable {
    case global, china
    var id: String { rawValue }
    var label: String { self == .global ? "Global" : "China" }
    var mqttHost: String { self == .global ? "us.mqtt.bambulab.com" : "cn.mqtt.bambulab.com" }
    fileprivate var api: String { self == .global ? "https://api.bambulab.com" : "https://api.bambulab.cn" }
    fileprivate var web: String { self == .global ? "https://bambulab.com" : "https://bambulab.cn" }
}

/// Unofficial Bambu Cloud API.
struct CloudAPI {
    let region: CloudRegion
    private var api: String { region.api }
    var mqttHost: String { region.mqttHost }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    private func request(_ url: String, method: String = "GET", body: [String: Any]? = nil,
                                token: String? = nil) async throws -> (json: [String: Any], http: HTTPURLResponse) {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = method
        req.setValue("bambu_network_agent/01.09.05.01", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await Self.session.data(for: req)
        let http = resp as! HTTPURLResponse
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if http.statusCode == 403 || (http.statusCode >= 400 && json.isEmpty) {
            throw CloudError.message("Bambu Cloud refused the request (HTTP \(http.statusCode)). It may be blocking this client; try again later.")
        }
        return (json, http)
    }

    private func fail(_ json: [String: Any], _ fallback: String) -> CloudError {
        .message((json["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback)
    }

    func login(email: String, password: String) async throws -> LoginResult {
        let (json, _) = try await request("\(api)/v1/user-service/user/login", method: "POST",
                                          body: ["account": email, "password": password])
        if let t = json["accessToken"] as? String, !t.isEmpty { return .token(t) }
        switch json["loginType"] as? String {
        case "verifyCode": return .needsCode
        case "tfa": return .needsTFA(json["tfaKey"] as? String ?? "")
        default: throw fail(json, "Sign-in failed. Check your email and password.")
        }
    }

    func sendCode(email: String) async throws {
        let (json, http) = try await request("\(api)/v1/user-service/user/sendemail/code", method: "POST",
                                             body: ["email": email, "type": "codeLogin"])
        if http.statusCode >= 400 { throw fail(json, "Couldn't send the verification code.") }
    }

    func login(email: String, code: String) async throws -> String {
        let (json, _) = try await request("\(api)/v1/user-service/user/login", method: "POST",
                                          body: ["account": email, "code": code])
        guard let t = json["accessToken"] as? String, !t.isEmpty else { throw fail(json, "Invalid verification code.") }
        return t
    }

    func tfa(key: String, code: String) async throws -> String {
        let (json, http) = try await request("\(region.web)/api/sign-in/tfa", method: "POST",
                                             body: ["tfaKey": key, "tfaCode": code])
        if let t = json["accessToken"] as? String, !t.isEmpty { return t }
        let cookies = (http.allHeaderFields["Set-Cookie"] as? String) ?? ""
        if let r = cookies.range(of: "token=") {
            let t = cookies[r.upperBound...].prefix { $0 != ";" && $0 != "," }
            if !t.isEmpty { return String(t) }
        }
        throw fail(json, "Invalid two-factor code.")
    }

    func userId(token: String) async throws -> String {
        let (json, _) = try await request("\(api)/v1/design-user-service/my/preference", token: token)
        guard let uid = json["uid"] as? NSNumber ?? (json["uid"] as? String).flatMap({ NSNumber(value: Int64($0) ?? 0) }),
              uid != 0 else { throw fail(json, "Couldn't read your account ID. Sign in again.") }
        return uid.stringValue
    }

    func devices(token: String) async throws -> [CloudDevice] {
        let (json, _) = try await request("\(api)/v1/iot-service/api/user/bind", token: token)
        guard let list = json["devices"] as? [[String: Any]] else { throw fail(json, "Couldn't load your printers.") }
        return list.compactMap { d in
            guard let id = d["dev_id"] as? String else { return nil }
            return CloudDevice(id: id, name: (d["name"] as? String) ?? id)
        }
    }
}
