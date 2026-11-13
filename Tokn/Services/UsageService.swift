import Foundation

enum AppError: LocalizedError {
    case authenticationFailed
    case organizationNotFound
    case usageAccessDenied
    case networkError(NetworkError)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:  return "Session key invalid or expired. Please re-enter."
        case .organizationNotFound:  return "Could not find your Claude organization."
        case .usageAccessDenied:     return "Usage data unavailable. Your account may not support the usage API (Pro subscription required)."
        case .networkError(let e):   return e.localizedDescription
        case .unknown(let e):        return e.localizedDescription
        }
    }
}

struct Organization: Decodable, Sendable {
    let uuid: String
    let name: String?
}

final class UsageService {
    private let network = NetworkService()
    private let baseURL = "https://claude.ai/api"

    /// Returns the first organization whose usage endpoint this key can read.
    func validateKey(_ key: SessionKey) async throws -> Organization {
        let orgs: [Organization] = try await network.get(
            "\(baseURL)/organizations",
            sessionKey: key.value
        )
        guard !orgs.isEmpty else {
            throw AppError.organizationNotFound
        }
        // Accounts can belong to multiple orgs (personal + team memberships).
        // Try each org's usage endpoint and return the first one that succeeds,
        // so we don't accidentally cache a team org where the user lacks access.
        for org in orgs {
            do {
                let _: UsageAPIResponse = try await network.get(
                    "\(baseURL)/organizations/\(org.uuid)/usage",
                    sessionKey: key.value
                )
                return org
            } catch let err as NetworkError {
                switch err {
                case .sessionExpired:
                    throw AppError.authenticationFailed
                case .accessBlocked, .permissionDenied, .httpError:
                    continue  // This org denied access; try the next one.
                default:
                    throw AppError.networkError(err)
                }
            }
        }
        throw AppError.usageAccessDenied
    }

    func fetchUsage(sessionKey: String, organizationId: String) async throws -> UsageData {
        do {
            let response: UsageAPIResponse = try await network.get(
                "\(baseURL)/organizations/\(organizationId)/usage",
                sessionKey: sessionKey
            )
            return try response.toUsageData()
        } catch let error as NetworkError {
            if case .sessionExpired = error { throw AppError.authenticationFailed }
            // 403 "Invalid authorization for organization" means the cached org ID doesn't
            // belong to this session key (stale cache from a different account).
            // Throw organizationNotFound so AppModel re-validates and gets the correct org.
            if case .accessBlocked(let detail) = error, detail.contains("permission_error") {
                throw AppError.organizationNotFound
            }
            throw AppError.networkError(error)
        } catch {
            throw AppError.unknown(error)
        }
    }
}
