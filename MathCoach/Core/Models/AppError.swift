import Foundation

enum AppError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(statusCode: Int, message: String)
    case encodingFailed
    case decodingFailed
    case missingToken
    case missingProblemImage
    case emptyDrawing
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ógild bakenda-slóð."
        case .invalidResponse:
            return "Svar frá bakenda var ógilt."
        case .unauthorized:
            return "Innskráning rann út. Skráðu þig inn aftur."
        case let .server(statusCode, message):
            if statusCode == 409 {
                return "Þetta netfang er nú þegar skráð. Prófaðu að skrá þig inn."
            }
            if statusCode == 422 {
                return "Eitthvað í innsendingunni er ógilt. \(message)"
            }
            if statusCode == 413 {
                return "Innsendingin er of stór. Minnkaðu myndirnar eða skiptu vinnunni í fleiri innsendingar."
            }
            if statusCode == 502 {
                return "Kennsluþjónustan er tímabundið niðri. Reyndu aftur."
            }
            if statusCode >= 500 {
                return "Villa í netþjóni (\(statusCode)). Reyndu aftur eftir smá stund."
            }
            return "Beiðni mistókst (\(statusCode)): \(message)"
        case .encodingFailed:
            return "Mistókst að umbreyta beiðni."
        case .decodingFailed:
            return "Mistókst að lesa svar frá netþjóni."
        case .missingToken:
            return "Enginn aðgangslykill fannst."
        case .missingProblemImage:
            return "Settu inn mynd af dæminu áður en þú sendir."
        case .emptyDrawing:
            return "Skrifaðu að minnsta kosti eitt lausnarskref áður en þú sendir."
        case let .message(message):
            return message
        }
    }
}
