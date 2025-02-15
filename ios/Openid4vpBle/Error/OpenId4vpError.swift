import Foundation

enum OpenId4vpError: Error {
    case invalidMTUSizeError(mtu: Int)
    case responseTransferFailure
}

extension OpenId4vpError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidMTUSizeError(let mtu):
            return "Negotiated MTU: \(mtu) is too low."
        case .responseTransferFailure:
            return "failed to write response"
        }
    }
}
