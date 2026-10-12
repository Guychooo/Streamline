import Foundation

public enum AddonError: Error, Equatable, Sendable, LocalizedError {
    case invalidURL(String)
    case unsupportedScheme(String)
    case httpStatus(Int)
    case invalidResponse(String)
    case resourceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let input):
            return "\"\(input)\" isn't a valid add-on address."
        case .unsupportedScheme(let scheme):
            return "Add-ons served over \(scheme) aren't supported. Use an http or https manifest URL."
        case .httpStatus(let code):
            return "The add-on server answered with HTTP \(code)."
        case .invalidResponse(let detail):
            return "The add-on sent a response this app couldn't read. \(detail)"
        case .resourceNotFound(let path):
            return "The add-on has nothing at \(path)."
        }
    }
}
