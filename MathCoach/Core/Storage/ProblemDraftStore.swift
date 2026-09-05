import Foundation
import CryptoKit
import PencilKit
import UIKit

struct ProblemDraftPage {
    let id: String
    let drawingData: Data
    let order: Int
    let createdAt: Date
    let updatedAt: Date
}

struct ProblemDraft {
    let pages: [ProblemDraftPage]
    let problemImageData: Data?
    let selectedMode: QueryMode
    let selectedExpertMode: ExpertMode
    let selectedPageId: String?
}

final class ProblemDraftStore {
    private struct PageMetadata: Codable {
        let id: String
        let order: Int
        let createdAt: Date
        let updatedAt: Date
    }

    private struct Metadata: Codable {
        let selectedMode: QueryMode
        let selectedExpertMode: ExpertMode?
        let selectedPageId: String?
        let pages: [PageMetadata]
        let updatedAt: Date
    }

    private struct LegacyMetadata: Codable {
        let selectedMode: QueryMode
        let updatedAt: Date
    }

    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let scopedDirectory: URL

    init(backendURL: URL, userID: String, baseDirectory: URL? = nil) {
        let root = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProblemDrafts", isDirectory: true)
        self.baseDirectory = root
        // Keep API prefixes in the identity: one host can serve multiple independent backends.
        var components = URLComponents(url: backendURL, resolvingAgainstBaseURL: false)
        let normalizedScheme = components?.scheme?.lowercased()
        let normalizedHost = components?.host?.lowercased()
        components?.scheme = normalizedScheme
        components?.host = normalizedHost
        if (components?.scheme == "https" && components?.port == 443) ||
            (components?.scheme == "http" && components?.port == 80) {
            components?.port = nil
        }
        if let path = components?.path, !path.hasSuffix("/") { components?.path += "/" }
        let backendKey = Self.storageKey(components?.url?.absoluteString ?? backendURL.absoluteString)
        self.scopedDirectory = root
            .appendingPathComponent("Scoped", isDirectory: true)
            .appendingPathComponent(backendKey, isDirectory: true)
            .appendingPathComponent(Self.storageKey(userID), isDirectory: true)
    }

    func hasUnscopedLegacyDraft(problemId: String) -> Bool {
        let legacy = baseDirectory.appendingPathComponent(problemId, isDirectory: true)
        return fileManager.fileExists(atPath: legacy.appendingPathComponent("metadata.json").path)
    }

    private static func storageKey(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func load(problemId: String) -> ProblemDraft? {
        let folder = folderURL(problemId: problemId)
        let metadataURL = folder.appendingPathComponent("metadata.json")
        let imageURL = folder.appendingPathComponent("problem-image.jpg")

        if
            let metadataData = try? Data(contentsOf: metadataURL),
            let metadata = try? JSONDecoder().decode(Metadata.self, from: metadataData)
        {
            let pages = metadata.pages
                .sorted { lhs, rhs in lhs.order < rhs.order }
                .compactMap { pageMeta -> ProblemDraftPage? in
                    let pageURL = pageURL(folder: folder, pageId: pageMeta.id)
                    guard let drawingData = try? Data(contentsOf: pageURL) else {
                        return nil
                    }
                    return ProblemDraftPage(
                        id: pageMeta.id,
                        drawingData: drawingData,
                        order: pageMeta.order,
                        createdAt: pageMeta.createdAt,
                        updatedAt: pageMeta.updatedAt
                    )
                }

            if !pages.isEmpty {
                let problemImageData = try? Data(contentsOf: imageURL)
                return ProblemDraft(
                    pages: pages,
                    problemImageData: problemImageData,
                    selectedMode: metadata.selectedMode,
                    selectedExpertMode: metadata.selectedExpertMode ?? .off,
                    selectedPageId: metadata.selectedPageId
                )
            }
        }

        // Backward compatibility: legacy single-page draft format.
        let legacyDrawingURL = folder.appendingPathComponent("drawing.data")
        guard
            let drawingData = try? Data(contentsOf: legacyDrawingURL),
            let metadataData = try? Data(contentsOf: metadataURL),
            let metadata = try? JSONDecoder().decode(LegacyMetadata.self, from: metadataData)
        else {
            return nil
        }

        let migratedPage = ProblemDraftPage(
            id: UUID().uuidString,
            drawingData: drawingData,
            order: 0,
            createdAt: metadata.updatedAt,
            updatedAt: metadata.updatedAt
        )
        let problemImageData = try? Data(contentsOf: imageURL)
        let migratedDraft = ProblemDraft(
            pages: [migratedPage],
            problemImageData: problemImageData,
            selectedMode: metadata.selectedMode,
            selectedExpertMode: .off,
            selectedPageId: migratedPage.id
        )
        try? save(problemId: problemId, draft: migratedDraft)
        return migratedDraft
    }

    func save(problemId: String, draft: ProblemDraft) throws {
        let folder = folderURL(problemId: problemId)
        let pagesFolder = pagesFolderURL(folder: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pagesFolder, withIntermediateDirectories: true)

        let metadataURL = folder.appendingPathComponent("metadata.json")
        let imageURL = folder.appendingPathComponent("problem-image.jpg")
        let legacyDrawingURL = folder.appendingPathComponent("drawing.data")

        // Remove stale page files that are no longer present in the latest draft.
        let currentIds = Set(draft.pages.map(\.id))
        if let existingFiles = try? fileManager.contentsOfDirectory(
            at: pagesFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in existingFiles where fileURL.pathExtension == "drawing" {
                let pageId = fileURL.deletingPathExtension().lastPathComponent
                if !currentIds.contains(pageId) {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }

        for page in draft.pages {
            let drawingURL = pageURL(folder: folder, pageId: page.id)
            try page.drawingData.write(to: drawingURL, options: .atomic)
        }

        let pageMetadata = draft.pages
            .sorted { lhs, rhs in lhs.order < rhs.order }
            .map {
                PageMetadata(
                    id: $0.id,
                    order: $0.order,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        let fullMetadata = Metadata(
            selectedMode: draft.selectedMode,
            selectedExpertMode: draft.selectedExpertMode,
            selectedPageId: draft.selectedPageId,
            pages: pageMetadata,
            updatedAt: Date()
        )
        let metadataData = try JSONEncoder().encode(fullMetadata)
        try metadataData.write(to: metadataURL, options: .atomic)

        if let imageData = draft.problemImageData {
            try imageData.write(to: imageURL, options: .atomic)
        } else if fileManager.fileExists(atPath: imageURL.path) {
            try fileManager.removeItem(at: imageURL)
        }

        if fileManager.fileExists(atPath: legacyDrawingURL.path) {
            try? fileManager.removeItem(at: legacyDrawingURL)
        }
    }

    func delete(problemId: String) {
        let folder = folderURL(problemId: problemId)
        if fileManager.fileExists(atPath: folder.path) {
            try? fileManager.removeItem(at: folder)
        }
    }

    private func folderURL(problemId: String) -> URL {
        scopedDirectory.appendingPathComponent(problemId, isDirectory: true)
    }

    private func pagesFolderURL(folder: URL) -> URL {
        folder.appendingPathComponent("pages", isDirectory: true)
    }

    private func pageURL(folder: URL, pageId: String) -> URL {
        pagesFolderURL(folder: folder).appendingPathComponent("\(pageId).drawing")
    }
}
