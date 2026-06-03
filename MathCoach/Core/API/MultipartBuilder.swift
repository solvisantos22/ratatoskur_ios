import Foundation

struct MultipartPart {
    let name: String
    let filename: String?
    let contentType: String?
    let data: Data
}

struct MultipartBuilder {
    let boundary: String = "Boundary-\(UUID().uuidString)"

    func build(parts: [MultipartPart]) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        for part in parts {
            body.append("--\(boundary)\(lineBreak)")

            if let filename = part.filename {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\(lineBreak)")
            } else {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"\(lineBreak)")
            }

            if let contentType = part.contentType {
                body.append("Content-Type: \(contentType)\(lineBreak)")
            }

            body.append(lineBreak)
            body.append(part.data)
            body.append(lineBreak)
        }

        body.append("--\(boundary)--\(lineBreak)")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
