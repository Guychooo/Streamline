import Foundation

/// Minimal HTTP abstraction so the add-on client can be tested without a network.
public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 20) {
        self.session = session
        self.timeout = timeout
    }

    public func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw AddonError.resourceNotFound(url.path) }
            guard (200..<300).contains(http.statusCode) else { throw AddonError.httpStatus(http.statusCode) }
        }
        return data
    }
}

/// Something that can answer add-on resource requests.
public protocol AddonTransport: Sendable {
    var transportURL: String { get }
    func fetchManifest() async throws -> Manifest
    func fetch(_ request: ResourceRequest) async throws -> Data
}

public struct HTTPAddonTransport: AddonTransport {
    public let transportURL: String
    private let client: HTTPClient

    public init(transportURL: String, client: HTTPClient) {
        self.transportURL = transportURL
        self.client = client
    }

    public func fetchManifest() async throws -> Manifest {
        guard let url = URL(string: transportURL) else { throw AddonError.invalidURL(transportURL) }
        let data = try await client.get(url)
        return try AddonDecoding.decode(Manifest.self, from: data)
    }

    public func fetch(_ request: ResourceRequest) async throws -> Data {
        let base = TransportURL.baseURLString(forManifest: transportURL)
        guard let url = URL(string: base + "/" + request.path) else {
            throw AddonError.invalidURL(base + "/" + request.path)
        }
        return try await client.get(url)
    }
}

enum AddonDecoding {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw AddonError.invalidResponse(describe(error))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "Missing field \"\(key.stringValue)\"."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.debugDescription
        @unknown default: return "Unknown decoding error."
        }
    }
}
