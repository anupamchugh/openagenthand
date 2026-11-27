import Foundation
import OpenAgentHandCore

struct EventFeed: Sendable {
    enum Failure: LocalizedError {
        case address, token, response, size, invalid

        var errorDescription: String? {
            switch self {
            case .address: "Use a local address (localhost or .local) or an HTTPS address."
            case .token: "Enter the feed's session token."
            case .response: "The feed declined the request or is unavailable."
            case .size: "The feed exceeded the response size limit."
            case .invalid: "The feed returned invalid events."
            }
        }
    }

    private let request: URLRequest
    private static let session = URLSession(
        configuration: .ephemeral, delegate: RejectRedirects(), delegateQueue: nil
    )

    init(address: String, token: String) throws {
        guard var url = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http"
                  && (host == "127.0.0.1" || host == "localhost" || host.hasSuffix(".local"))) else {
            throw Failure.address
        }
        guard token.count >= 24, token.utf8.count <= 512,
              !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw Failure.token }
        url.path = "/v1/events"
        guard let endpoint = url.url else { throw Failure.address }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        self.request = request
    }

    func snapshot() async throws -> AgentSnapshot {
        let (stream, response) = try await Self.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw Failure.response }
        var data = Data()
        for try await byte in stream {
            guard data.count < 256_000 else { throw Failure.size }
            data.append(byte)
        }
        guard let snapshot = try? JSONDecoder().decode(AgentSnapshot.self, from: data), snapshot.isValid else {
            throw Failure.invalid
        }
        return snapshot
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
