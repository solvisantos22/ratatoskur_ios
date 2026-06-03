import Foundation
import Combine
import UIKit
import PencilKit
import WebKit

struct SubmissionExportResult {
    let fileURL: URL
    let exportedCount: Int
    let skippedProblems: [String]
}

enum SubmissionExportError: LocalizedError {
    case missingTitle
    case missingStudentName
    case noProblemsSelected
    case noExportableProblems
    case invalidImageURL(problemTitle: String)
    case failedImageDownload(problemTitle: String)
    case failedFileWrite

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Vinsamlegast settu inn titil á skilum."
        case .missingStudentName:
            return "Vinsamlegast bættu við fullu nafni í prófíl áður en þú flytur út."
        case .noProblemsSelected:
            return "Veldu að minnsta kosti eitt dæmi til útflutnings."
        case .noExportableProblems:
            return "Engin valin dæmi voru með útflutningshæfar síður."
        case let .invalidImageURL(problemTitle):
            return "Ógild myndaslóð fyrir dæmi: \(problemTitle)."
        case let .failedImageDownload(problemTitle):
            return "Mistókst að sækja myndir fyrir dæmi: \(problemTitle)."
        case .failedFileWrite:
            return "Mistókst að skrifa PDF skrá."
        }
    }
}

@MainActor
final class ProblemsOverviewViewModel: ObservableObject {
    static let maxFolderNameLength: Int = 60

    struct ComparativeStat {
        let currentValue: String
        let previousValue: String
        let deltaValue: String
        let trend: Trend

        enum Trend {
            case up
            case down
            case flat
        }
    }

    private struct SubmissionProblemAssets {
        let title: String
        let problemImage: UIImage
        let solutionPages: [UIImage]
    }

    @Published var problems: [ProblemSummary] = []
    @Published var folders: [FolderSummary] = []
    @Published var selectedFolderId: String?
    @Published var isLoading: Bool = false
    @Published var isCreating: Bool = false
    @Published var isCreatingFolder: Bool = false
    @Published var isArchivingFolder: Bool = false
    @Published var isMovingProblem: Bool = false
    @Published var isDeletingProblem: Bool = false
    @Published var errorMessage: String?
    @Published var userStats: UserStatsSummary?
    @Published var errorEventTypeSummary: ErrorEventTypeSummaryResponse?

    private let draftStore = ProblemDraftStore()

    func loadProblems(authManager: AuthManager) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedProblems = authManager.listProblems()
            async let loadedFolders = authManager.listFolders()
            async let loadedStats: UserStatsSummary? = try? authManager.getAnalyticsSummary()
            async let loadedErrorEventTypes: ErrorEventTypeSummaryResponse? = try? authManager.getErrorEventTypeSummary(folderId: nil)
            problems = try await loadedProblems
            folders = sortFolders(try await loadedFolders)
            userStats = await loadedStats
            errorEventTypeSummary = await loadedErrorEventTypes
            if let selectedFolderId, !folders.contains(where: { $0.id == selectedFolderId }) {
                self.selectedFolderId = nil
            }
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að hlaða dæmum."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProblem(title: String, folderId: String?, authManager: AuthManager) async -> ProblemSummary? {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            let created = try await authManager.createProblem(title: title, folderId: folderId)
            problems.insert(created, at: 0)
            return created
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að búa til dæmi."
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createFolder(
        name: String,
        parentFolderId: String? = nil,
        authManager: AuthManager
    ) async -> FolderSummary? {
        isCreatingFolder = true
        errorMessage = nil
        defer { isCreatingFolder = false }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            errorMessage = "Nafn möppu má ekki vera tómt."
            return nil
        }
        guard normalizedName.count <= Self.maxFolderNameLength else {
            errorMessage = "Nafn möppu má vera að hámarki \(Self.maxFolderNameLength) stafir."
            return nil
        }

        do {
            let created = try await authManager.createFolder(
                name: normalizedName,
                parentFolderId: parentFolderId
            )
            folders = sortFolders(folders + [created])
            return created
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að búa til möppu."
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func archiveFolder(folderId: String, authManager: AuthManager) async -> Bool {
        isArchivingFolder = true
        errorMessage = nil
        defer { isArchivingFolder = false }

        do {
            _ = try await authManager.archiveFolder(folderId: folderId)
            await loadProblems(authManager: authManager)
            if selectedFolderId == folderId {
                selectedFolderId = nil
            }
            return true
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að eyða möppu."
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func moveProblem(problemId: String, folderId: String, authManager: AuthManager) async {
        isMovingProblem = true
        errorMessage = nil
        defer { isMovingProblem = false }

        do {
            let updated = try await authManager.moveProblem(problemId: problemId, folderId: folderId)
            if let index = problems.firstIndex(where: { $0.id == updated.id }) {
                problems[index] = updated
            }
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að færa dæmi."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProblem(problemId: String, authManager: AuthManager) async -> Bool {
        isDeletingProblem = true
        errorMessage = nil
        defer { isDeletingProblem = false }

        do {
            _ = try await authManager.deleteProblem(problemId: problemId)
            draftStore.delete(problemId: problemId)
            await loadProblems(authManager: authManager)
            return true
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að eyða dæmi."
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var filteredProblems: [ProblemSummary] {
        guard let selectedFolderId else {
            return problems
        }
        return problems.filter { $0.folder_id == selectedFolderId }
    }

    func problemCount(folderId: String?) -> Int {
        guard let folderId else { return problems.count }
        return problems.filter { $0.folder_id == folderId }.count
    }

    var rootFolders: [FolderSummary] {
        sortFolders(folders.filter { $0.parent_folder_id == nil })
    }

    func childFolders(parentFolderId: String) -> [FolderSummary] {
        sortFolders(folders.filter { $0.parent_folder_id == parentFolderId })
    }

    func parentFolder(for folder: FolderSummary) -> FolderSummary? {
        guard let parentFolderId = folder.parent_folder_id else { return nil }
        return folders.first(where: { $0.id == parentFolderId })
    }

    func folderPathTitle(folder: FolderSummary) -> String {
        if let parent = parentFolder(for: folder) {
            return "\(localizedFolderName(parent.name)) / \(localizedFolderName(folder.name))"
        }
        return localizedFolderName(folder.name)
    }

    func localizedFolderName(_ value: String) -> String {
        value == "Unsorted" ? "Óflokkað" : value
    }

    func isDefaultFolder(_ folder: FolderSummary) -> Bool {
        folder.name == "Unsorted"
    }

    private func sortFolders(_ value: [FolderSummary]) -> [FolderSummary] {
        value.sorted { lhs, rhs in
            if lhs.name == "Unsorted" { return true }
            if rhs.name == "Unsorted" { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var solvedProblemsText: String {
        guard let userStats else { return "--" }
        return "\(userStats.solved_problems_count_current)"
    }

    var solvedProblemsComparison: ComparativeStat {
        guard let userStats else {
            return ComparativeStat(currentValue: "--", previousValue: "--", deltaValue: "--", trend: .flat)
        }
        return ComparativeStat(
            currentValue: "\(userStats.solved_problems_count_current)",
            previousValue: "\(userStats.solved_problems_count_pre)",
            deltaValue: "\(abs(userStats.solved_problems_count_current - userStats.solved_problems_count_pre))",
            trend: trend(current: Double(userStats.solved_problems_count_current), previous: Double(userStats.solved_problems_count_pre))
        )
    }

    var averageErrorComparison: ComparativeStat {
        guard let userStats else {
            return ComparativeStat(currentValue: "--", previousValue: "--", deltaValue: "--", trend: .flat)
        }
        return ComparativeStat(
            currentValue: formattedDecimal(userStats.average_error_current),
            previousValue: formattedDecimal(userStats.average_error_pre),
            deltaValue: formattedDecimal(abs(userStats.average_error_current - userStats.average_error_pre)),
            trend: trend(current: userStats.average_error_current, previous: userStats.average_error_pre)
        )
    }

    var averageAttemptsComparison: ComparativeStat {
        guard let userStats else {
            return ComparativeStat(currentValue: "--", previousValue: "--", deltaValue: "--", trend: .flat)
        }
        return ComparativeStat(
            currentValue: formattedDecimal(userStats.average_attempts_current),
            previousValue: formattedDecimal(userStats.average_attempts_pre),
            deltaValue: formattedDecimal(abs(userStats.average_attempts_current - userStats.average_attempts_pre)),
            trend: trend(current: userStats.average_attempts_current, previous: userStats.average_attempts_pre)
        )
    }

    var mostCommonModeText: String {
        guard let mode = userStats?.most_common_mode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mode.isEmpty
        else {
            return "--"
        }

        switch mode {
        case "hint":
            return "Vísbending"
        case "check_solution":
            return "Fara yfir lausn"
        case "reveal":
            return "Sýna lausn"
        default:
            return mode
        }
    }

    var activeStreakText: String {
        guard let userStats else { return "--" }
        return "\(userStats.active_streak)"
    }

    var errorBankDistinctCountText: String {
        guard let errorEventTypeSummary else { return "--" }
        return "\(errorEventTypeSummary.total_distinct_error_types)"
    }

    private func trend(current: Double, previous: Double) -> ComparativeStat.Trend {
        if current > previous {
            return .up
        }
        if current < previous {
            return .down
        }
        return .flat
    }

    private func formattedDecimal(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    func buildSubmissionPDF(
        selectedProblems: [ProblemSummary],
        submissionTitle: String,
        studentName: String,
        authManager: AuthManager
    ) async throws -> SubmissionExportResult {
        let normalizedTitle = submissionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw SubmissionExportError.missingTitle
        }

        let normalizedStudentName = studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStudentName.isEmpty else {
            throw SubmissionExportError.missingStudentName
        }

        guard !selectedProblems.isEmpty else {
            throw SubmissionExportError.noProblemsSelected
        }

        var assets: [SubmissionProblemAssets] = []
        var skippedProblems: [String] = []

        for problem in selectedProblems {
            let attempts = try await authManager.listAttempts(problemId: problem.id)
            let draft = draftStore.load(problemId: problem.id)

            let problemImage = try await resolveProblemImage(
                problem: problem,
                draft: draft,
                attempts: attempts
            )
            let solutionPages = try await resolveSolutionPages(
                problem: problem,
                draft: draft,
                attempts: attempts
            )

            guard let problemImage, !solutionPages.isEmpty else {
                skippedProblems.append(problem.title)
                continue
            }

            assets.append(
                SubmissionProblemAssets(
                    title: problem.title,
                    problemImage: problemImage,
                    solutionPages: solutionPages
                )
            )
        }

        guard !assets.isEmpty else {
            throw SubmissionExportError.noExportableProblems
        }

        let logoImage = await loadPDFLogoImage()
        let pdfData = renderPDFData(
            submissionTitle: normalizedTitle,
            studentName: normalizedStudentName,
            assets: assets,
            logoImage: logoImage
        )
        let fileURL = try writePDFToTemporaryFile(
            data: pdfData,
            submissionTitle: normalizedTitle,
            studentName: normalizedStudentName
        )

        return SubmissionExportResult(
            fileURL: fileURL,
            exportedCount: assets.count,
            skippedProblems: skippedProblems
        )
    }

    private func resolveProblemImage(
        problem: ProblemSummary,
        draft: ProblemDraft?,
        attempts: [ProblemAttempt]
    ) async throws -> UIImage? {
        if let imageData = draft?.problemImageData, let draftImage = UIImage(data: imageData) {
            return draftImage
        }

        guard
            let imageURLString = attempts.first(where: { $0.problem_image_url?.isEmpty == false })?.problem_image_url,
            let url = URL(string: imageURLString)
        else {
            return nil
        }
        return try await downloadImage(from: url, problemTitle: problem.title)
    }

    private func resolveSolutionPages(
        problem: ProblemSummary,
        draft: ProblemDraft?,
        attempts: [ProblemAttempt]
    ) async throws -> [UIImage] {
        if let draft, !draft.pages.isEmpty {
            let renderedPages = draft.pages
                .sorted { lhs, rhs in lhs.order < rhs.order }
                .compactMap { renderDraftPageImage(from: $0.drawingData) }
            if !renderedPages.isEmpty {
                return renderedPages
            }
        }

        guard
            let imageURLString = attempts.first(where: { $0.solution_image_url?.isEmpty == false })?.solution_image_url,
            let url = URL(string: imageURLString)
        else {
            return []
        }
        return [try await downloadImage(from: url, problemTitle: problem.title)]
    }

    private func downloadImage(from url: URL, problemTitle: String) async throws -> UIImage {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw SubmissionExportError.failedImageDownload(problemTitle: problemTitle)
        }

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            let image = UIImage(data: data)
        else {
            throw SubmissionExportError.failedImageDownload(problemTitle: problemTitle)
        }
        return image
    }

    private func renderDraftPageImage(from drawingData: Data) -> UIImage? {
        guard let drawing = try? PKDrawing(data: drawingData) else {
            return nil
        }
        if drawing.bounds.isEmpty {
            return blankSolutionPage()
        }

        let bounds = drawing.bounds.insetBy(dx: -16, dy: -16)
        let image = drawing.image(from: bounds, scale: 2.0)
        return imageOnWhiteBackground(image)
    }

    private func blankSolutionPage() -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func imageOnWhiteBackground(_ image: UIImage) -> UIImage {
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func renderPDFData(
        submissionTitle: String,
        studentName: String,
        assets: [SubmissionProblemAssets],
        logoImage: UIImage?
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 at 72 DPI
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let headerColor = UIColor(red: 108 / 255, green: 63 / 255, blue: 34 / 255, alpha: 1)
        let accentColor = UIColor(red: 169 / 255, green: 104 / 255, blue: 53 / 255, alpha: 1)
        let pageBackgroundColor = UIColor(red: 249 / 255, green: 245 / 255, blue: 239 / 255, alpha: 1)
        let cardBackgroundColor = UIColor.white

        return renderer.pdfData { context in
            context.beginPage()
            pageBackgroundColor.setFill()
            UIBezierPath(rect: pageRect).fill()

            drawPDFCard(
                rect: CGRect(x: 36, y: 84, width: 523, height: 210),
                fillColor: cardBackgroundColor,
                borderColor: accentColor.withAlphaComponent(0.22)
            )
            drawText(
                submissionTitle,
                in: CGRect(x: 56, y: 110, width: 483, height: 56),
                font: .systemFont(ofSize: 30, weight: .bold),
                color: headerColor
            )
            drawText(
                "Nafn: \(studentName)",
                in: CGRect(x: 56, y: 174, width: 483, height: 24),
                font: .systemFont(ofSize: 16, weight: .semibold),
                color: .darkGray
            )
            drawText(
                "Dagsetning: \(formattedDate())",
                in: CGRect(x: 56, y: 200, width: 483, height: 24),
                font: .systemFont(ofSize: 15, weight: .regular),
                color: .darkGray
            )
            drawText(
                "Dæmi: \(assets.count)",
                in: CGRect(x: 56, y: 226, width: 483, height: 24),
                font: .systemFont(ofSize: 15, weight: .regular),
                color: .darkGray
            )

            if let logoImage {
                drawImage(
                    logoImage,
                    inside: CGRect(x: (pageRect.width - 180) / 2, y: 336, width: 180, height: 180),
                    backgroundColor: .clear,
                    padding: 0
                )
            }

            drawPDFFooter(
                in: pageRect,
                text: "Ratatoskur | Persónulegi einkakennarinn þinn",
                lineColor: accentColor.withAlphaComponent(0.35),
                textColor: .darkGray
            )

            for asset in assets {
                // Dedicated page for the original problem image.
                context.beginPage()
                pageBackgroundColor.setFill()
                UIBezierPath(rect: pageRect).fill()
                drawPDFHeaderBand(in: pageRect, color: headerColor)

                drawText(
                    asset.title,
                    in: CGRect(x: 110, y: 36, width: 400, height: 22),
                    font: .systemFont(ofSize: 16, weight: .bold),
                    color: .white
                )
                drawText(
                    "Upprunalegt dæmi",
                    in: CGRect(x: 110, y: 58, width: 400, height: 16),
                    font: .systemFont(ofSize: 12, weight: .semibold),
                    color: UIColor.white.withAlphaComponent(0.9)
                )

                if let logoImage {
                    drawImage(
                        logoImage,
                        inside: CGRect(x: 40, y: 24, width: 56, height: 56),
                        backgroundColor: .clear,
                        padding: 0
                    )
                }

                let margin: CGFloat = 36
                let contentWidth = pageRect.width - (margin * 2)
                let bodyStartY: CGFloat = 118

                drawImage(
                    asset.problemImage,
                    inside: CGRect(x: margin, y: bodyStartY + 24, width: contentWidth, height: 648),
                    backgroundColor: cardBackgroundColor
                )

                drawPDFFooter(
                    in: pageRect,
                    text: "Ratatoskur | \(asset.title)",
                    lineColor: accentColor.withAlphaComponent(0.35),
                    textColor: .darkGray
                )

                for (pageIndex, solutionPage) in asset.solutionPages.enumerated() {
                    context.beginPage()
                    pageBackgroundColor.setFill()
                    UIBezierPath(rect: pageRect).fill()
                    drawPDFHeaderBand(in: pageRect, color: headerColor)

                    drawText(
                        asset.title,
                        in: CGRect(x: 110, y: 36, width: 400, height: 22),
                        font: .systemFont(ofSize: 16, weight: .bold),
                        color: .white
                    )
                    drawText(
                        "Lausn nemanda - Síða \(pageIndex + 1) af \(asset.solutionPages.count)",
                        in: CGRect(x: 110, y: 58, width: 400, height: 16),
                        font: .systemFont(ofSize: 12, weight: .semibold),
                        color: UIColor.white.withAlphaComponent(0.9)
                    )

                    if let logoImage {
                        drawImage(
                            logoImage,
                            inside: CGRect(x: 40, y: 24, width: 56, height: 56),
                            backgroundColor: .clear,
                            padding: 0
                        )
                    }

                    drawText(
                        "Lausn nemanda",
                        in: CGRect(x: margin, y: bodyStartY, width: contentWidth, height: 22),
                        font: .systemFont(ofSize: 13, weight: .semibold),
                        color: .darkGray
                    )
                    drawImage(
                        solutionPage,
                        inside: CGRect(x: margin, y: bodyStartY + 24, width: contentWidth, height: 648),
                        backgroundColor: cardBackgroundColor
                    )

                    drawPDFFooter(
                        in: pageRect,
                        text: "Ratatoskur | \(asset.title)",
                        lineColor: accentColor.withAlphaComponent(0.35),
                        textColor: .darkGray
                    )
                }
            }
        }
    }

    private func drawPDFHeaderBand(in pageRect: CGRect, color: UIColor) {
        let headerRect = CGRect(x: 24, y: 20, width: pageRect.width - 48, height: 62)
        color.setFill()
        UIBezierPath(roundedRect: headerRect, cornerRadius: 14).fill()
    }

    private func drawPDFCard(rect: CGRect, fillColor: UIColor, borderColor: UIColor) {
        fillColor.setFill()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawPDFFooter(in pageRect: CGRect, text: String, lineColor: UIColor, textColor: UIColor) {
        lineColor.setStroke()
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: 36, y: pageRect.height - 40))
        linePath.addLine(to: CGPoint(x: pageRect.width - 36, y: pageRect.height - 40))
        linePath.lineWidth = 1
        linePath.stroke()
        drawText(
            text,
            in: CGRect(x: 36, y: pageRect.height - 34, width: pageRect.width - 72, height: 20),
            font: .systemFont(ofSize: 11, weight: .regular),
            color: textColor
        )
    }

    private func drawImage(
        _ image: UIImage,
        inside box: CGRect,
        backgroundColor: UIColor = UIColor(white: 0.96, alpha: 1.0),
        padding: CGFloat = 10
    ) {
        backgroundColor.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 10).fill()

        let fittedRect = aspectFitRect(for: image.size, in: box.insetBy(dx: padding, dy: padding))
        image.draw(in: fittedRect)
    }

    private func loadPDFLogoImage() async -> UIImage? {
        if let bundleLogo = UIImage(named: "ratatoskur_logo") {
            return bundleLogo
        }

        guard
            let svgURL = Bundle.main.url(forResource: "ratatoskur_logo", withExtension: "svg"),
            let rawSVG = try? String(contentsOf: svgURL, encoding: .utf8)
        else {
            return nil
        }

        let preparedSVG = rawSVG.replacingOccurrences(
            of: #"preserveAspectRatio=\"none\""#,
            with: #"preserveAspectRatio=\"xMidYMid meet\""#
        )

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0\">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: transparent;
            }
            svg {
              width: 100%;
              height: 100%;
              display: block;
            }
          </style>
        </head>
        <body>\(preparedSVG)</body>
        </html>
        """

        let size = CGSize(width: 220, height: 220)
        return await renderHTMLSnapshot(html: html, size: size)
    }

    private func renderHTMLSnapshot(html: String, size: CGSize) async -> UIImage? {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        webView.loadHTMLString(html, baseURL: nil)

        let waitDurations: [UInt64] = [250_000_000, 350_000_000, 600_000_000]
        for waitDuration in waitDurations {
            try? await Task.sleep(nanoseconds: waitDuration)
            if let image = await takeWebViewSnapshot(webView, size: size) {
                return image
            }
        }

        return nil
    }

    private func takeWebViewSnapshot(_ webView: WKWebView, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let snapshotConfig = WKSnapshotConfiguration()
            snapshotConfig.rect = CGRect(origin: .zero, size: size)
            webView.takeSnapshot(with: snapshotConfig) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor
    ) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func aspectFitRect(for imageSize: CGSize, in box: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return box
        }

        let widthScale = box.width / imageSize.width
        let heightScale = box.height / imageSize.height
        let scale = min(widthScale, heightScale)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: box.midX - (fittedSize.width / 2),
            y: box.midY - (fittedSize.height / 2)
        )
        return CGRect(origin: origin, size: fittedSize)
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "is_IS")
        return formatter.string(from: Date())
    }

    private func writePDFToTemporaryFile(
        data: Data,
        submissionTitle: String,
        studentName: String
    ) throws -> URL {
        let baseName = sanitizeFilename("\(submissionTitle)_\(studentName)")
        let fileName = "\(baseName)_\(UUID().uuidString.prefix(8)).pdf"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw SubmissionExportError.failedFileWrite
        }
    }

    private func sanitizeFilename(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = input.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }
        let collapsed = String(mapped).replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "skil" : trimmed
    }
}
