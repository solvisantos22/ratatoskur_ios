import Foundation

enum Endpoint {
    case register
    case login
    case refresh
    case me
    case updateMe
    case logout
    case query
    case problem
    case problems
    case folders
    case foldersCreate
    case folder(folderId: String)
    case problemDelete(problemId: String)
    case problemMove(problemId: String)
    case problemsMoveBatch
    case problemAttempts(problemId: String)
    case attemptFeedback(attemptId: String)
    case analyticsSummary
    case analyticsErrorEventTypes
    case analyticsErrorEvents
    case examPacksList
    case examPacksCreate
    case examPack(packId: String)
    case examPackStart(packId: String)
    case examSessionAnswer(sessionId: String, itemId: String)
    case examSessionSubmit(sessionId: String)
    case examSessionResults(sessionId: String)

    var path: String {
        switch self {
        case .register:
            return "/auth/register"
        case .login:
            return "/auth/login"
        case .refresh:
            return "/auth/refresh"
        case .me:
            return "/auth/me"
        case .updateMe:
            return "/auth/me"
        case .logout:
            return "/auth/logout"
        case .query:
            return "/query"
        case .problem:
            return "/problem"
        case .problems:
            return "/problems"
        case .folders, .foldersCreate:
            return "/folders"
        case let .folder(folderId):
            return "/folders/\(folderId)"
        case let .problemDelete(problemId):
            return "/problems/\(problemId)"
        case let .problemMove(problemId):
            return "/problems/\(problemId)/move"
        case .problemsMoveBatch:
            return "/problems/move-batch"
        case let .problemAttempts(problemId):
            return "/problems/\(problemId)/attempts"
        case let .attemptFeedback(attemptId):
            return "/attempts/\(attemptId)/feedback"
        case .analyticsSummary:
            return "/analytics/summary"
        case .analyticsErrorEventTypes:
            return "/analytics/error-events/types"
        case .analyticsErrorEvents:
            return "/analytics/error-events"
        case .examPacksList, .examPacksCreate:
            return "/exam-packs"
        case let .examPack(packId):
            return "/exam-packs/\(packId)"
        case let .examPackStart(packId):
            return "/exam-packs/\(packId)/start"
        case let .examSessionAnswer(sessionId, itemId):
            return "/exam-sessions/\(sessionId)/answers/\(itemId)"
        case let .examSessionSubmit(sessionId):
            return "/exam-sessions/\(sessionId)/submit"
        case let .examSessionResults(sessionId):
            return "/exam-sessions/\(sessionId)/results"
        }
    }

    var method: String {
        switch self {
        case .me, .problems, .folders, .problemAttempts, .analyticsSummary, .analyticsErrorEventTypes, .analyticsErrorEvents, .examPacksList, .examPack, .examSessionResults:
            return "GET"
        case .updateMe, .folder, .problemMove, .problemsMoveBatch, .examSessionAnswer:
            return "PATCH"
        case .problemDelete:
            return "DELETE"
        case .problem, .query, .register, .login, .refresh, .logout, .attemptFeedback, .foldersCreate, .examPacksCreate, .examPackStart, .examSessionSubmit:
            return "POST"
        }
    }

}
