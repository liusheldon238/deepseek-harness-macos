import Foundation

public struct DSHHealthReport: Sendable, Equatable {
    public let methods: [String]

    public init(methods: [String]) {
        self.methods = methods
    }
}

public struct DSHHealthChecker: @unchecked Sendable {
    public typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport

    public init(transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RuntimeError.domainHealthFailed("transport", "非 HTTP 响应")
        }
        return (data, http)
    }) {
        self.transport = transport
    }

    public func check(baseURL: URL) async throws -> DSHHealthReport {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if components?.path.isEmpty == true { components?.path = "/" }
        var rootRequest = URLRequest(url: components?.url ?? baseURL)
        rootRequest.timeoutInterval = 4
        let (rootData, rootResponse) = try await transport(rootRequest)
        guard rootResponse.statusCode == 200 else {
            throw RuntimeError.domainHealthFailed("root", "HTTP \(rootResponse.statusCode)")
        }
        let rootBody = String(data: rootData, encoding: .utf8) ?? ""
        if let failure = ClientPluginFailureParser.failure(from: rootBody) {
            throw RuntimeError.pluginConflict(failure.pluginID)
        }

        let methods = ["agentPreset.list", "settings.describe"]
        for method in methods {
            try Task.checkCancellation()
            try await check(method: method, baseURL: baseURL)
        }
        return DSHHealthReport(methods: methods)
    }

    private func check(method: String, baseURL: URL) async throws {
        let rpcID = UUID().uuidString
        let url = baseURL.appendingPathComponent("api/\(method)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-request",
            "rpcId": rpcID,
            "method": method,
            "payload": [:]
        ])
        let (data, response) = try await transport(request)
        guard response.statusCode == 200 else {
            throw RuntimeError.domainHealthFailed(method, "HTTP \(response.statusCode)")
        }
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["type"] as? String == "server-response",
              envelope["rpcId"] as? String == rpcID,
              let result = envelope["result"] as? [String: Any] else {
            throw RuntimeError.domainHealthFailed(method, "RPC 响应标识无效")
        }
        guard result["ok"] as? Bool == true else {
            let error = result["error"] as? [String: Any]
            throw RuntimeError.domainHealthFailed(method, error?["message"] as? String ?? "RPC 返回失败")
        }
    }
}

public enum WebRecoveryRequest {
    public static func make(url: URL, recovering: Bool) -> URLRequest {
        URLRequest(url: url, cachePolicy: recovering ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy, timeoutInterval: 30)
    }
}
