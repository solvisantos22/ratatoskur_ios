import SwiftUI
import UIKit
import Combine
import PencilKit
import Vision

private enum NotebookImagePickerSource: String, Identifiable {
    case photoLibrary
    case camera

    var id: String { rawValue }

    var sourceType: UIImagePickerController.SourceType {
        switch self {
        case .photoLibrary:
            return .photoLibrary
        case .camera:
            return .camera
        }
    }
}

struct NotebookView: View {
    let problem: ProblemSummary
    let showImageOnboardingOnOpen: Bool
    var assignedStart: StudentAssignmentStartResponse? = nil

    private var isAssigned: Bool { assignedStart != nil || problem.isAssigned }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel = NotebookViewModel()
    @AppStorage(PipelineMode.appStorageKey) private var selectedPipelineModeRawValue: String = PipelineMode.singlePass.rawValue

    @State private var activeImagePickerSource: NotebookImagePickerSource?
    @State private var showImageCropper = false
    @State private var pickedProblemImage: UIImage?
    @State private var selectedAttempt: ProblemAttempt?
    @State private var inlineCanvasZoomScale: CGFloat = 0
    @State private var fullscreenCanvasZoomScale: CGFloat = 0
    @State private var isWorkspaceFullscreen = false
    @State private var showImageOnboarding = false
    @State private var pendingSubmissionAction: SubmissionAction?
    @State private var submissionTask: Task<Void, Never>?
    @State private var actionInfoMode: QueryMode?
    @State private var sideBySideCardHeight: CGFloat = 0
    @StateObject private var canvasController = PencilCanvasController()
    @State private var selectedCanvasTool: CanvasToolKind = .pen
    @State private var selectedInkUIColor: UIColor = .label
    @State private var pencilWidth: CGFloat = 5
    @State private var penWidth: CGFloat = 5
    @State private var highlighterWidth: CGFloat = 18
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var isShowingColorPicker = false
    @State private var isRulerActive = false
    @State private var paperStyle: PaperStyle = .squared
    @State private var isDraftHydrated = false
    @State private var isAssignedImageReady = false
    @State private var isLoadingAssignedImage = false
    @State private var assignedImageError: String?
    @State private var suppressStartupEmptyDrawingUntil: Date = .distantPast
    @State private var problemImageHeightOverride: CGFloat?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    problemImageSection
                    if viewModel.hasUnscopedLegacyDraft {
                        Label("Eldri drög að þessu dæmi eru enn á tækinu. Þau eru ekki opnuð sjálfkrafa þar sem ekki er vitað hvaða aðgangi eða þjóni þau tilheyra.", systemImage: "doc.badge.ellipsis")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    canvasSection
                    actionsAndResponseSection
                        .disabled(!isDraftHydrated || (isAssigned && !isAssignedImageReady))
                    attemptsSection
                }
                .padding(16)
            }

            if showImageOnboarding {
                imageOnboardingOverlay
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            workspaceHeader(
                title: problem.title,
                backButtonTitle: "Til baka",
                onBack: {
                    persistAndSaveCanvasState()
                    dismiss()
                }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(AppTheme.Auth.background)
        .tint(AppTheme.Auth.primary)
        .sheet(item: $activeImagePickerSource) { activeSource in
            ImagePicker(sourceType: activeSource.sourceType) { image in
                pickedProblemImage = image
            }
        }
        .sheet(isPresented: $showImageCropper) {
            if let pickedProblemImage {
                ImageCropperSheet(
                    image: pickedProblemImage,
                    onCancel: {
                        self.pickedProblemImage = nil
                        showImageCropper = false
                    },
                    onConfirm: { croppedImage in
                        viewModel.setProblemImage(croppedImage)
                        self.pickedProblemImage = nil
                        showImageCropper = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true)
            }
        }
        .fullScreenCover(item: $selectedAttempt) { attempt in
            AttemptBrowserView(
                problemTitle: problem.title,
                attempts: viewModel.attempts,
                initialAttemptID: attempt.id,
                selectedRating: { attempt in
                    viewModel.feedbackRatingsByAttemptId[attempt.id]
                },
                selectedComment: { attempt in
                    viewModel.feedbackCommentsByAttemptId[attempt.id]
                },
                isSubmitting: { attempt in
                    viewModel.feedbackSubmittingAttemptId == attempt.id
                },
                feedbackErrorMessage: { attempt in
                    viewModel.feedbackErrorAttemptId == attempt.id ? viewModel.feedbackErrorMessage : nil
                },
                onSubmitFeedback: { attempt, rating, comment in
                    Task {
                        await viewModel.submitAttemptFeedback(
                            attemptId: attempt.id,
                            rating: rating,
                            comment: comment,
                            authManager: authManager
                        )
                    }
                }
            )
        }
        .sheet(item: $actionInfoMode) { mode in
            ActionInfoSheet(mode: mode)
        }
        .sheet(isPresented: $viewModel.isShowingReadingConfirmation) {
            ReadingConfirmationSheet(
                fields: $viewModel.readingConfirmationFields,
                message: viewModel.response?.message_is,
                confidence: viewModel.response?.reading_confidence,
                ambiguousRegions: viewModel.response?.ambiguous_regions,
                onSubmit: {
                    submissionTask = Task {
                        await viewModel.submitConfirmedReading(
                            authManager: authManager,
                            problemId: problem.id,
                            pipelineMode: selectedPipelineMode
                        )
                    }
                },
                onRewrite: {
                    viewModel.dismissReadingConfirmation()
                }
            )
        }
        .fullScreenCover(isPresented: $isWorkspaceFullscreen) {
            FullScreenWorkspaceView(
                problemTitle: problem.title,
                problemImage: viewModel.problemImage,
                pages: viewModel.pages,
                selectedPageIndex: viewModel.selectedPageIndex,
                onSelectPage: { index in viewModel.selectPage(index: index) },
                drawing: $viewModel.drawing,
                zoomScale: $fullscreenCanvasZoomScale,
                controller: canvasController,
                selectedTool: $selectedCanvasTool,
                selectedInkUIColor: $selectedInkUIColor,
                pencilWidth: $pencilWidth,
                penWidth: $penWidth,
                highlighterWidth: $highlighterWidth,
                eraserType: $eraserType,
                isRulerActive: $isRulerActive,
                paperStyle: $paperStyle
            )
        }
        .alert(item: $pendingSubmissionAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .default(Text("Staðfesta")) {
                    startSubmission(mode: action.mode)
                },
                secondaryButton: .cancel(Text("Hætta við"))
            )
        }
        .task {
            guard !isDraftHydrated else { return }
            suppressStartupEmptyDrawingUntil = Date().addingTimeInterval(1.0)
            loadPaperStylePreference()
            guard let userID = authManager.currentUser?.id, userID == problem.user_id else {
                viewModel.errorMessage = "Skráðu þig inn aftur til að opna stílabókina."
                return
            }
            viewModel.restoreNotebook(
                problemId: problem.id,
                backendURL: AppConfig.baseURL,
                userID: userID,
                assignmentAllowReveal: (assignedStart?.problem ?? problem).assignment_allow_reveal
            )
            showImageOnboarding = !isAssigned && showImageOnboardingOnOpen && viewModel.problemImage == nil
            try? await Task.sleep(for: .milliseconds(200))
            isDraftHydrated = true
            if isAssigned { await loadAssignedImage(initialStart: assignedStart) }
            await viewModel.loadAttempts(authManager: authManager, problemId: problem.id)
        }
        .onReceive(viewModel.$drawing.dropFirst()) { _ in
            guard isDraftHydrated else { return }
            viewModel.syncCurrentDrawingToPages()
            viewModel.flushAutosaveNow(problemId: problem.id)
        }
        .onReceive(viewModel.$problemImage.dropFirst()) { _ in
            guard isDraftHydrated else { return }
            viewModel.scheduleAutosave(problemId: problem.id)
        }
        .onChange(of: pickedProblemImage) { _, newValue in
            if newValue != nil {
                showImageCropper = true
            }
        }
        .onReceive(viewModel.$selectedMode.dropFirst()) { _ in
            guard isDraftHydrated else { return }
            viewModel.scheduleAutosave(problemId: problem.id)
        }
        .onReceive(viewModel.$selectedExpertMode.dropFirst()) { _ in
            guard isDraftHydrated else { return }
            viewModel.scheduleAutosave(problemId: problem.id)
        }
        .onReceive(viewModel.$selectedPageIndex.dropFirst()) { _ in
            guard isDraftHydrated else { return }
            viewModel.scheduleAutosave(problemId: problem.id)
        }
        .onChange(of: viewModel.problemImage) { _, newValue in
            if newValue != nil {
                showImageOnboarding = false
            }
        }
        .onChange(of: paperStyle) { _, newValue in
            savePaperStylePreference(newValue)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                persistAndSaveCanvasState()
            } else if isDraftHydrated && isAssigned {
                Task { await loadAssignedImage() }
            }
        }
        .onChange(of: problem.assignment_allow_reveal) { _, allowReveal in
            viewModel.applyAssignmentPolicy(allowReveal, problemId: problem.id)
        }
        .onDisappear {
            submissionTask?.cancel()
            persistAndSaveCanvasState()
        }
    }

    private func persistAndSaveCanvasState() {
        guard isDraftHydrated else { return }
        if let liveDrawing = canvasController.currentDrawing(),
           liveDrawing.dataRepresentation() != viewModel.drawing.dataRepresentation() {
            viewModel.drawing = liveDrawing
        }
        viewModel.syncCurrentDrawingToPages()
        viewModel.flushAutosaveNow(problemId: problem.id)
    }

    private func loadAssignedImage(initialStart: StudentAssignmentStartResponse? = nil) async {
        guard !isLoadingAssignedImage else { return }
        isLoadingAssignedImage = true
        isAssignedImageReady = false
        assignedImageError = nil
        defer { isLoadingAssignedImage = false }
        do {
            let start: StudentAssignmentStartResponse
            if let initialStart {
                start = initialStart
            } else if let assignmentID = problem.assignment_id, let itemID = problem.assignment_item_id {
                start = try await authManager.startStudentAssignment(assignmentId: assignmentID, itemId: itemID)
            } else {
                throw AppError.message("Ekki tókst að finna bekkjarverkefnið. Opnaðu það aftur úr Bekkurinn minn.")
            }
            guard start.problem.id == problem.id else {
                throw AppError.message("Dæmið hefur breyst. Opnaðu það aftur úr Bekkurinn minn.")
            }
            try Task.checkCancellation()
            viewModel.applyAssignmentPolicy(start.problem.assignment_allow_reveal, problemId: problem.id)
            let image = try await AssignmentImageLoader.load(url: start.image_url)
            try Task.checkCancellation()
            viewModel.setProblemImage(image)
            viewModel.flushAutosaveNow(problemId: problem.id)
            isAssignedImageReady = true
        } catch is CancellationError {
            return
        } catch {
            assignedImageError = error.localizedDescription
        }
    }

    private var paperStylePreferenceKey: String {
        let userId = authManager.currentUser?.id ?? "guest"
        return "notebook.paper_style.\(userId)"
    }

    private func loadPaperStylePreference() {
        let storedValue = UserDefaults.standard.string(forKey: paperStylePreferenceKey)
        paperStyle = storedValue.flatMap(PaperStyle.init(rawValue:)) ?? .squared
    }

    private func savePaperStylePreference(_ style: PaperStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: paperStylePreferenceKey)
    }

    private var selectedPipelineMode: PipelineMode {
        PipelineMode(rawValue: selectedPipelineModeRawValue) ?? .singlePass
    }

    private func startSubmission(mode: QueryMode) {
        submissionTask?.cancel()
        submissionTask = Task {
            viewModel.selectedMode = mode
            await viewModel.submitQuery(
                authManager: authManager,
                problemId: problem.id,
                pipelineMode: selectedPipelineMode
            )
        }
    }

    private func retrySubmission() {
        submissionTask?.cancel()
        submissionTask = Task {
            await viewModel.retryLastSubmission(authManager: authManager)
        }
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        viewModel.cancelSubmission()
    }

    private func handleCanvasDrawingChange(_ updatedDrawing: PKDrawing) {
        guard isDraftHydrated else { return }
        if Date() < suppressStartupEmptyDrawingUntil,
           updatedDrawing.bounds.isEmpty,
           !viewModel.drawing.bounds.isEmpty {
            return
        }
        if !updatedDrawing.bounds.isEmpty {
            suppressStartupEmptyDrawingUntil = .distantPast
        }
        if updatedDrawing.dataRepresentation() != viewModel.drawing.dataRepresentation() {
            viewModel.drawing = updatedDrawing
            viewModel.syncCurrentDrawingToPages()
            viewModel.flushAutosaveNow(problemId: problem.id)
        }
    }

    private var problemImageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mynd af dæmi")
                    .font(.headline)

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        adjustProblemImageHeight(by: -problemImageResizeStep)
                    } label: {
                        Image(systemName: "minus")
                            .font(.footnote.weight(.bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canDecreaseProblemImageHeight)
                    .opacity(canDecreaseProblemImageHeight ? 1 : 0.45)
                    .accessibilityLabel("Minnka mynd af dæmi")

                    Button {
                        adjustProblemImageHeight(by: problemImageResizeStep)
                    } label: {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canIncreaseProblemImageHeight)
                    .opacity(canIncreaseProblemImageHeight ? 1 : 0.45)
                    .accessibilityLabel("Stækka mynd af dæmi")
                }
            }

            if let image = viewModel.problemImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: currentProblemImageMaxHeight)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.Auth.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(isAssigned ? "Mynd kennarans birtist hér þegar tenging næst." : "Bættu við upprunalegu myndinni af dæminu áður en þú sendir fyrirspurn.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isAssigned {
                Label("Bekkjardæmi · Mynd kennarans", systemImage: "person.3.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Kennarinn sér handskriftina, tilraunirnar og vísbendingarnar sem þú sendir fyrir þetta dæmi. Persónulegar stílabækur eru ekki birtar kennara.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if isLoadingAssignedImage {
                    ProgressView("Sæki mynd kennarans...")
                }
                if let assignedImageError {
                    Text(assignedImageError).font(.footnote).foregroundStyle(.red)
                    Button("Sækja mynd aftur") {
                        Task { await loadAssignedImage() }
                    }
                    .disabled(isLoadingAssignedImage)
                }
            } else {
                Menu {
                    Button("Myndasafn") {
                        activeImagePickerSource = .photoLibrary
                    }

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Myndavél") {
                            activeImagePickerSource = .camera
                        }
                    }
                } label: {
                    imagePickerPrimaryLabel(
                        title: viewModel.problemImage == nil ? "Bæta við mynd af dæmi" : "Skipta út mynd af dæmi"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.problemImage == nil ? "Bæta við mynd af dæmi" : "Skipta út mynd af dæmi")
                .accessibilityHint("Veldu mynd úr myndasafni eða myndavél af upprunalega dæminu.")
            }
        }
        .padding(14)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()

                Button {
                    fullscreenCanvasZoomScale = 0
                    isWorkspaceFullscreen = true
                } label: {
                    Label("Heilskjár", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opnar stærra skrifsvæði.")
            }

            PencilCanvasView(
                drawing: $viewModel.drawing,
                zoomScale: $inlineCanvasZoomScale,
                selectedTool: $selectedCanvasTool,
                controller: canvasController,
                onDrawingChange: { updatedDrawing in
                    handleCanvasDrawingChange(updatedDrawing)
                },
                isCanvasActive: !isWorkspaceFullscreen,
                inkColor: selectedInkUIColor,
                pencilWidth: pencilWidth,
                penWidth: penWidth,
                highlighterWidth: highlighterWidth,
                eraserType: eraserType,
                isRulerActive: isRulerActive,
                paperStyle: paperStyle,
                viewportMode: .fitWidth
            )
                .frame(minHeight: 420)

            pageControls

            HStack {
                Spacer()

                Button("Hreinsa blað", role: .destructive) {
                    viewModel.clearCanvas()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(minHeight: 36)
            }
        }
        .padding(14)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var pageControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Blaðaskipan", systemImage: "square.on.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer()
                Text("\(viewModel.pageLabel(for: viewModel.selectedPageIndex)) / \(viewModel.pageCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { idx, _ in
                        Button(viewModel.pageLabel(for: idx)) {
                            viewModel.selectPage(index: idx)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(
                            viewModel.selectedPageIndex == idx ? Color.white : AppTheme.Auth.textPrimary
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.selectedPageIndex == idx ? AppTheme.Auth.primary : AppTheme.Auth.surface
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    viewModel.selectedPageIndex == idx ? AppTheme.Auth.primary : AppTheme.Auth.border,
                                    lineWidth: 1
                                )
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pageActionButton(
                        title: "Bæta við blaði",
                        systemImageName: "plus",
                        isEnabled: viewModel.canAddPage
                    ) {
                        viewModel.addPage()
                    }

                    pageActionButton(
                        title: "Afrita blað",
                        systemImageName: "doc.on.doc",
                        isEnabled: viewModel.canAddPage
                    ) {
                        viewModel.duplicateSelectedPage()
                    }

                    pageActionButton(
                        title: "Færa til vinstri",
                        systemImageName: "arrow.left",
                        isEnabled: viewModel.selectedPageIndex > 0
                    ) {
                        viewModel.moveSelectedPageLeft()
                    }

                    pageActionButton(
                        title: "Færa til hægri",
                        systemImageName: "arrow.right",
                        isEnabled: viewModel.selectedPageIndex < viewModel.pageCount - 1
                    ) {
                        viewModel.moveSelectedPageRight()
                    }

                    pageActionButton(
                        title: "Eyða blaði",
                        systemImageName: "trash",
                        isDestructive: true,
                        isEnabled: viewModel.pageCount > 1
                    ) {
                        viewModel.deleteSelectedPage()
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private func pageActionButton(
        title: String,
        systemImageName: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImageName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(
                    isEnabled
                        ? (isDestructive ? AppTheme.Auth.error : AppTheme.Auth.textPrimary)
                        : AppTheme.Auth.textSecondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isDestructive ? AppTheme.Auth.error.opacity(0.45) : AppTheme.Auth.border,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func imagePickerPrimaryLabel(title: String) -> some View {
        Label(title, systemImage: "photo.on.rectangle.angled")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AppTheme.Auth.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.Auth.primaryPressed.opacity(0.35), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var actionsAndResponseSection: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 12) {
                controlsSection
                    .reportSectionHeight()
                    .frame(minWidth: 300, maxWidth: 300, minHeight: sideBySideCardHeight, alignment: .topLeading)
                responseSection
                    .reportSectionHeight()
                    .frame(maxWidth: .infinity, minHeight: sideBySideCardHeight, alignment: .topLeading)
            }
            .onPreferenceChange(SectionHeightPreferenceKey.self) { sideBySideCardHeight = $0 }
        } else {
            controlsSection
            responseSection
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Veldu aðgerð")
                .font(.headline)

            expertModeSection

            VStack(spacing: 10) {
                actionRow(for: .hint, systemImage: "lightbulb.fill")
                actionRow(for: .check_solution, systemImage: "checkmark.seal.fill")
                if viewModel.availableModes.contains(.reveal) {
                    actionRow(for: .reveal, systemImage: "text.book.closed.fill")
                }
            }
            if let explanation = viewModel.assignmentPolicyExplanation {
                Label(explanation, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

#if DEBUG
            Button {
                viewModel.presentDebugReadingConfirmation()
            } label: {
                Label("Prófa óskýrt UX", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
#endif

            if let error = viewModel.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Villa: \(error)")
            }
        }
        .padding(14)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var expertModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {


            Toggle(isOn: clarityModeBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skýrleikahamur")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Auth.textPrimary)
                    Text(viewModel.selectedExpertMode == .clarity ? "Kveikt" : "Slökkt")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                }
            }
            .toggleStyle(.switch)

            Text(expertModeExplanation(viewModel.selectedExpertMode))
                .font(.footnote)
                .foregroundStyle(AppTheme.Auth.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Auth.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                )
                .accessibilityHint("Útskýrir áhrif valins sérfræðihams.")
        }
    }

    private func expertModeExplanation(_ mode: ExpertMode) -> String {
        switch mode {
        case .off:
            return "Hraðvirk og einföld svör. Hentar þegar þú vilt stuttar leiðbeiningar."
        case .clarity:
            return "Meiri áhersla á skýrar skref-fyrir-skref skýringar og betri framsetningu."
        }
    }

    private var clarityModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.selectedExpertMode == .clarity },
            set: { isEnabled in
                viewModel.selectedExpertMode = isEnabled ? .clarity : .off
            }
        )
    }

    private var imageOnboardingOverlay: some View {
        ZStack {
            AppTheme.Auth.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(AppTheme.Auth.primary)
                    Text("Byrjum á mynd af dæminu")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Settu inn mynd af verkefninu og haltu svo áfram í vinnusvæðið.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)

                Menu {
                    Button("Myndasafn") {
                        activeImagePickerSource = .photoLibrary
                    }

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Myndavél") {
                            activeImagePickerSource = .camera
                        }
                    }
                } label: {
                    imagePickerPrimaryLabel(title: "Bæta við mynd af dæmi")
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                Button("Sleppa í bili") {
                    showImageOnboarding = false
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

                Spacer()
            }
            .padding(24)
        }
    }

    private func actionRow(for mode: QueryMode, systemImage: String) -> some View {
        HStack(spacing: 8) {
            actionButton(for: mode, systemImage: systemImage)

            Button {
                actionInfoMode = mode
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Upplýsingar um \(mode.displayName)")
            .accessibilityHint("Sýnir stutta lýsingu á þessari aðgerð.")
        }
    }

    private func actionButton(for mode: QueryMode, systemImage: String) -> some View {
        Button {
            pendingSubmissionAction = SubmissionAction(mode: mode)
        } label: {
            Label(mode.displayName, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: 44)
        .disabled(!isActionEnabled(mode) || viewModel.isSubmitting)
        .accessibilityHint(actionAccessibilityHint(for: mode))
    }

    private func isActionEnabled(_ mode: QueryMode) -> Bool {
        switch mode {
        case .hint, .check_solution:
            return true
        case .reveal:
            return viewModel.canRevealSolution
        }
    }

    private func actionAccessibilityHint(for mode: QueryMode) -> String {
        switch mode {
        case .hint, .check_solution:
            return "Biður um staðfestingu áður en fyrirspurn er send."
        case .reveal:
            if let explanation = viewModel.assignmentPolicyExplanation {
                return explanation
            }
            if viewModel.canRevealSolution {
                return "Biður um staðfestingu áður en fyrirspurn er send."
            }
            return "Óvirkt þar til kennari hefur yfirfarið lausnina og metið hana rétta."
        }
    }

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Svar kennara")
                .font(.headline)

            if let response = viewModel.response {
                QueryResponseCard(
                    response: response,
                    displayedMessage: displayedResponseMessage,
                    isStreaming: viewModel.isStreamingResponse
                )
            } else if let stage = viewModel.submissionStage {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(stage.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .cancel) {
                        cancelSubmission()
                    } label: {
                        Label("Hætta við", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Auth.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(stage.label)
            } else {
                Text("Ekkert svar enn. Sendu fyrirspurn eftir að hafa hlaðið inn mynd af dæmi og skrifað skref.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Auth.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if viewModel.canRetryLastSubmission {
                Button {
                    retrySubmission()
                } label: {
                    Label("Reyna aftur", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var attemptsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tilraunir")
                .font(.headline)

            if viewModel.isLoadingAttempts && viewModel.attempts.isEmpty {
                ProgressView("Sæki tilraunir...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.attempts.isEmpty {
                Text("Engar tilraunir enn fyrir þetta dæmi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Auth.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ForEach(viewModel.attempts) { attempt in
                    Button {
                        selectedAttempt = attempt
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(localizedAttemptMode(attempt.mode))
                                    .font(.subheadline.weight(.semibold))
                                Text(attemptSummaryText(attempt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.Auth.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tilraun \(localizedAttemptMode(attempt.mode))")
                    .accessibilityHint("Opnar ítarlega endurgjöf kennara fyrir þessa tilraun.")
                }
            }
        }
        .padding(14)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var problemImageMaxHeight: CGFloat {
        horizontalSizeClass == .regular ? 320 : 220
    }

    private var problemImageHeightRange: ClosedRange<CGFloat> {
        if horizontalSizeClass == .regular {
            return 120...520
        }
        return 90...380
    }

    private var problemImageResizeStep: CGFloat {
        horizontalSizeClass == .regular ? 40 : 30
    }

    private var currentProblemImageMaxHeight: CGFloat {
        let baseHeight = problemImageHeightOverride ?? problemImageHeightRange.lowerBound
        return min(max(baseHeight, problemImageHeightRange.lowerBound), problemImageHeightRange.upperBound)
    }

    private var canDecreaseProblemImageHeight: Bool {
        currentProblemImageMaxHeight > problemImageHeightRange.lowerBound
    }

    private var canIncreaseProblemImageHeight: Bool {
        currentProblemImageMaxHeight < problemImageHeightRange.upperBound
    }

    private func adjustProblemImageHeight(by delta: CGFloat) {
        let nextHeight = currentProblemImageMaxHeight + delta
        problemImageHeightOverride = min(
            max(nextHeight, problemImageHeightRange.lowerBound),
            problemImageHeightRange.upperBound
        )
    }

    private var displayedResponseMessage: String {
        if viewModel.streamedResponseText.isEmpty {
            return viewModel.response?.message_is ?? ""
        }
        return viewModel.streamedResponseText
    }

    private func localizedAttemptMode(_ rawMode: String) -> String {
        switch rawMode.lowercased() {
        case QueryMode.hint.rawValue:
            return QueryMode.hint.displayName
        case QueryMode.check_solution.rawValue:
            return QueryMode.check_solution.displayName
        case QueryMode.reveal.rawValue:
            return QueryMode.reveal.displayName
        default:
            return rawMode.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func attemptSummaryText(_ attempt: ProblemAttempt) -> String {
        let verdict = localizedVerdict(attempt.verdict)
        let pageCount = attempt.page_count ?? 1
        let pageLabel = pageCount == 1 ? "blað" : "blöð"
        return "\(verdict) • \(pageCount) \(pageLabel)"
    }

    private func localizedVerdict(_ verdict: String?) -> String {
        guard let verdict = verdict?.trimmingCharacters(in: .whitespacesAndNewlines), !verdict.isEmpty else {
            return "Engin niðurstaða"
        }

        switch verdict.lowercased() {
        case "fully_solved", "fully_correct":
            return "Fullkomlega rétt"
        case "correct_so_far":
            return "Rétt hingað til"
        case "correct":
            return "Rétt"
        case "incorrect":
            return "Rangt"
        case "partial":
            return "Að hluta rétt"
        case "unclear":
            return "Óskýrt"
        default:
            return verdict
        }
    }

    @ViewBuilder
    private func workspaceHeader(
        title: String,
        backButtonTitle: String,
        onBack: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text(backButtonTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 8)

                if !showImageOnboarding {
                    HStack(spacing: 8) {
                        toolbarIconButton(
                            systemImageName: "arrow.uturn.backward",
                            isEnabled: canvasController.canUndo,
                            action: { canvasController.undo() },
                            accessibilityLabel: "Afturkalla"
                        )
                        toolbarIconButton(
                            systemImageName: "arrow.uturn.forward",
                            isEnabled: canvasController.canRedo,
                            action: { canvasController.redo() },
                            accessibilityLabel: "Endurtaka"
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(AppTheme.Auth.logo)

            if !showImageOnboarding {
                HStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(CanvasToolKind.notebookEnabledTools, id: \.rawValue) { tool in
                                toolSelectionButton(tool)
                            }

                            toggleIconButton(
                                systemImageName: "ruler",
                                isSelected: isRulerActive,
                                action: { isRulerActive.toggle() },
                                accessibilityLabel: "Reglustika"
                            )

                            toolAdjustmentsView
                        }
                        .padding(.vertical, 2)
                    }

                    Spacer(minLength: 0)

                    paperStyleControls

                    Button {
                        isShowingColorPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(uiColor: selectedInkUIColor))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 1))

                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.Auth.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.Auth.surface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isShowingColorPicker) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Veldu lit")
                                .font(.headline)
                            ColorPicker("Litur", selection: colorSelectionBinding, supportsOpacity: false)
                                .labelsHidden()
                            colorSwatches
                        }
                        .padding(16)
                        .presentationCompactAdaptation(.popover)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(AppTheme.Auth.surfaceMuted)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.Auth.border)
                .frame(height: 1)
        }
    }

    private func toolbarIconButton(
        systemImageName: String,
        isEnabled: Bool,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
            .padding(10)
            .background(Color.white.opacity(isEnabled ? 0.16 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
    }

    private func toolSelectionButton(_ tool: CanvasToolKind) -> some View {
        let isSelected = selectedCanvasTool == tool

        return Button {
            selectedCanvasTool = tool
        } label: {
            Image(systemName: tool.systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)
                .frame(width: 22, height: 22)
            .padding(10)
            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var toolAdjustmentsView: some View {
        switch selectedCanvasTool {
        case .pencil:
            widthSelector(widths: [3, 5, 8, 11], selectedWidth: $pencilWidth)
        case .pen:
            widthSelector(widths: [3, 5, 7, 10], selectedWidth: $penWidth)
        case .highlighter:
            widthSelector(widths: [10, 16, 22, 28], selectedWidth: $highlighterWidth)
        case .eraser:
            HStack(spacing: 8) {
                eraserTypeButton(title: "Strokur", type: .vector)
                eraserTypeButton(title: "Nákvæmt", type: .bitmap)
            }
        case .lasso:
            Text("Veldu strik til að færa eða breyta")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
                .padding(.horizontal, 10)
        }
    }

    private var paperStyleControls: some View {
        HStack(spacing: 8) {
            ForEach(PaperStyle.allCases, id: \.rawValue) { style in
                let isSelected = paperStyle == style

                Button {
                    paperStyle = style
                } label: {
                    Text(style.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 4)
    }

    private func widthSelector(widths: [CGFloat], selectedWidth: Binding<CGFloat>) -> some View {
        HStack(spacing: 8) {
            ForEach(widths, id: \.self) { width in
                let isSelected = abs(selectedWidth.wrappedValue - width) < 0.01

                Button {
                    selectedWidth.wrappedValue = width
                } label: {
                    ZStack {
                        Circle()
                            .fill(isSelected ? AppTheme.Auth.primary.opacity(0.14) : AppTheme.Auth.surface)
                            .frame(width: 34, height: 34)

                        Circle()
                            .fill(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.textPrimary)
                            .frame(width: width + 2, height: width + 2)
                    }
                    .overlay(
                        Circle()
                            .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Línuþykkt \(Int(width))")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.leading, 6)
    }

    private func eraserTypeButton(title: String, type: PKEraserTool.EraserType) -> some View {
        let isSelected = eraserType == type

        return Button {
            eraserType = type
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleIconButton(
        systemImageName: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)
                .frame(width: 22, height: 22)
            .padding(10)
            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var colorSelectionBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: selectedInkUIColor) },
            set: { selectedInkUIColor = UIColor($0) }
        )
    }

    private var colorSwatches: some View {
        let palette: [UIColor] = [
            .label,
            .systemBlue,
            .systemRed,
            .systemGreen,
            .systemOrange,
            .systemPurple
        ]

        return HStack(spacing: 10) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, color in
                Button {
                    selectedInkUIColor = color
                } label: {
                    Circle()
                        .fill(Color(uiColor: color))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(
                                    selectedInkUIColor.isEqual(color) ? AppTheme.Auth.primary : AppTheme.Auth.border,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

}

private struct SectionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func reportSectionHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: SectionHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }
}

private enum ReadingInputMode: String, CaseIterable {
    case text
    case draw
}

private struct ReadingConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fields: [QueryReadingField]
    let message: String?
    let confidence: Double?
    let ambiguousRegions: [QueryAmbiguousRegion]?
    let onSubmit: () -> Void
    let onRewrite: () -> Void

    @FocusState private var focusedFieldId: String?
    @State private var inputModeByFieldId: [String: ReadingInputMode] = [:]
    @State private var drawingByFieldId: [String: PKDrawing] = [:]
    @State private var zoomByFieldId: [String: CGFloat] = [:]
    @State private var controllerByFieldId: [String: PencilCanvasController] = [:]
    @State private var extractedTextByFieldId: [String: String] = [:]
    @State private var selectedTool: CanvasToolKind = .pen
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var isSubmitting = false
    @State private var localErrorMessage: String?

    private let mathSymbolChips = ["x²", "^", "√", "/", "(", ")", "=", "+", "-", "×"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Auth.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(messageText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Auth.textPrimary)

                        Text("Veldu Texti eða Teikna fyrir hvert svæði. Þú getur notað táknahjálp fyrir stærðfræði (t.d. 2^2).")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Auth.textSecondary)

                        if let confidence {
                            Text("Öryggi lesturs: \(Int((confidence * 100).rounded()))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Auth.textSecondary)
                        }

                        if let localErrorMessage, !localErrorMessage.isEmpty {
                            Label(localErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        symbolChipRow

                        ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(fieldLabel(field))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.Auth.textSecondary)

                                if let hintText = ambiguousHint(for: field, at: index) {
                                    Text("Óskýrt svæði: \(hintText)")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Auth.textSecondary)
                                }

                                inputModePicker(for: field.id)

                                if mode(for: field.id) == .draw {
                                    drawCorrectionView(for: field.id)
                                } else {
                                    TextField(
                                        "Leiðréttu lesturinn hér (t.d. 2^2)",
                                        text: Binding(
                                            get: { textForField(id: field.id) },
                                            set: { updateText($0, for: field.id) }
                                        ),
                                        axis: .vertical
                                    )
                                    .lineLimit(2...4)
                                    .focused($focusedFieldId, equals: field.id)
                                    .padding(10)
                                    .background(AppTheme.Auth.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(AppTheme.Auth.border, lineWidth: 1)
                                    )
                                }
                            }
                            .padding(10)
                            .background(AppTheme.Auth.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(spacing: 10) {
                            Button {
                                submitResolvedFields()
                            } label: {
                                if isSubmitting {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Les teikningu...")
                                    }
                                } else {
                                    Text("Samþykkja og meta")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(isSubmitting)

                            Button("Til baka og endurskrifa") {
                                onRewrite()
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Staðfesta lestur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Loka") {
                        onRewrite()
                        dismiss()
                    }
                }
            }
        }
        .tint(AppTheme.Auth.primary)
        .onAppear {
            initializeFieldState()
        }
        .onChange(of: fields.count) { _, _ in
            initializeFieldState()
        }
    }

    private var messageText: String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return "Kerfið er óöruggt um lestur á lausninni. Vinsamlegast leiðréttu textann áður en við metum skrefin."
    }

    private func fieldLabel(_ field: QueryReadingField) -> String {
        if let label = field.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let page = field.page {
            return "Bls. \(page)"
        }
        return "Skref"
    }

    @ViewBuilder
    private var symbolChipRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Táknahjálp")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(mathSymbolChips, id: \.self) { chip in
                        Button {
                            insertSymbol(chip)
                        } label: {
                            Text(chip)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.Auth.surface)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            Text("Dæmi: 2^2, x = 4, (3+1)/2")
                .font(.caption2)
                .foregroundStyle(AppTheme.Auth.textSecondary)
        }
    }

    @ViewBuilder
    private func inputModePicker(for fieldId: String) -> some View {
        HStack(spacing: 8) {
            modeButton(title: "Texti", mode: .text, fieldId: fieldId)
            modeButton(title: "Teikna", mode: .draw, fieldId: fieldId)
            Spacer(minLength: 0)
        }
    }

    private func modeButton(title: String, mode: ReadingInputMode, fieldId: String) -> some View {
        let isSelected = self.mode(for: fieldId) == mode
        return Button {
            inputModeByFieldId[fieldId] = mode
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.textPrimary)
                .background(AppTheme.Auth.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func drawCorrectionView(for fieldId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PencilCanvasView(
                drawing: Binding(
                    get: { drawingByFieldId[fieldId] ?? PKDrawing() },
                    set: { drawingByFieldId[fieldId] = $0 }
                ),
                zoomScale: Binding(
                    get: { zoomByFieldId[fieldId] ?? 0 },
                    set: { zoomByFieldId[fieldId] = $0 }
                ),
                selectedTool: $selectedTool,
                controller: canvasController(for: fieldId),
                isCanvasActive: false,
                inkColor: .label,
                pencilWidth: 5,
                penWidth: 5,
                highlighterWidth: 18,
                eraserType: eraserType,
                isRulerActive: false,
                paperStyle: .squared,
                viewportMode: .fitWidth
            )
            .frame(minHeight: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.Auth.border, lineWidth: 1)
            )

            HStack(spacing: 8) {
                modeToolButton(tool: .pen)
                modeToolButton(tool: .eraser)
                if selectedTool == .eraser {
                    eraserTypeButton(title: "Strokur", type: .vector)
                    eraserTypeButton(title: "Nákvæmt", type: .bitmap)
                }
                Spacer(minLength: 0)
                Button("Hreinsa") {
                    drawingByFieldId[fieldId] = PKDrawing()
                    extractedTextByFieldId[fieldId] = ""
                }
                .buttonStyle(.bordered)
            }

            if let extracted = normalizedText(extractedTextByFieldId[fieldId]), !extracted.isEmpty {
                Text("Lesið úr teikningu: \(extracted)")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
            } else {
                Text("Teiknaðu leiðréttingu hér, t.d. 2^2.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }
        }
    }

    private func modeToolButton(tool: CanvasToolKind) -> some View {
        let isSelected = selectedTool == tool
        return Button {
            selectedTool = tool
        } label: {
            Image(systemName: tool.systemImageName)
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)
                .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func eraserTypeButton(title: String, type: PKEraserTool.EraserType) -> some View {
        let isSelected = eraserType == type
        return Button {
            eraserType = type
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.textPrimary)
                .background(AppTheme.Auth.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func initializeFieldState() {
        for field in fields {
            if inputModeByFieldId[field.id] == nil {
                inputModeByFieldId[field.id] = .text
            }
            if drawingByFieldId[field.id] == nil {
                drawingByFieldId[field.id] = PKDrawing()
            }
            if zoomByFieldId[field.id] == nil {
                zoomByFieldId[field.id] = 1.0
            }
            if extractedTextByFieldId[field.id] == nil {
                extractedTextByFieldId[field.id] = ""
            }
            if controllerByFieldId[field.id] == nil {
                controllerByFieldId[field.id] = PencilCanvasController()
            }
        }
        if focusedFieldId == nil {
            focusedFieldId = fields.first?.id
        }
    }

    private func mode(for fieldId: String) -> ReadingInputMode {
        inputModeByFieldId[fieldId] ?? .text
    }

    private func textForField(id: String) -> String {
        fields.first(where: { $0.id == id })?.text ?? ""
    }

    private func updateText(_ text: String, for id: String) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        fields[index].text = text
    }

    private func canvasController(for fieldId: String) -> PencilCanvasController {
        controllerByFieldId[fieldId] ?? PencilCanvasController()
    }

    private func insertSymbol(_ symbol: String) {
        guard let fieldId = focusedFieldId ?? fields.first?.id else { return }
        guard let index = fields.firstIndex(where: { $0.id == fieldId }) else { return }
        fields[index].text += symbol == "x²" ? "^2" : (symbol == "×" ? "*" : symbol)
    }

    private func ambiguousHint(for field: QueryReadingField, at index: Int) -> String? {
        guard let ambiguousRegions else { return nil }
        if index < ambiguousRegions.count {
            let region = ambiguousRegions[index]
            let direct = region.snippet?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let direct, !direct.isEmpty {
                return direct
            }
            let reason = region.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let reason, !reason.isEmpty {
                return reason
            }
        }
        if let page = field.page {
            let pageRegion = ambiguousRegions.first { $0.page == page }
            if let snippet = pageRegion?.snippet?.trimmingCharacters(in: .whitespacesAndNewlines), !snippet.isEmpty {
                return snippet
            }
        }
        return nil
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        var normalized = trimmed
            .replacingOccurrences(of: "²", with: "^2")
            .replacingOccurrences(of: "³", with: "^3")
            .replacingOccurrences(of: "×", with: "*")
        normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        return normalized
    }

    private func submitResolvedFields() {
        isSubmitting = true
        localErrorMessage = nil
        defer { isSubmitting = false }

        var resolved = fields
        for index in resolved.indices {
            let fieldId = resolved[index].id
            if mode(for: fieldId) == .draw {
                let recognized = recognizeTextFromDrawing(drawingByFieldId[fieldId] ?? PKDrawing())
                if let recognized = normalizedText(recognized) {
                    resolved[index].text = recognized
                    extractedTextByFieldId[fieldId] = recognized
                }
            } else if let normalized = normalizedText(resolved[index].text) {
                resolved[index].text = normalized
            }
        }

        let cleaned = resolved
            .map { field in
                QueryReadingField(
                    id: field.id,
                    page: field.page,
                    label: field.label,
                    text: field.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty }

        guard !cleaned.isEmpty else {
            localErrorMessage = "Vantar leiðréttingu. Sláðu inn texta eða teiknaðu að minnsta kosti eitt svæði."
            return
        }

        fields = cleaned
        onSubmit()
        dismiss()
    }

    private func recognizeTextFromDrawing(_ drawing: PKDrawing) -> String? {
        guard !drawing.bounds.isEmpty else {
            return nil
        }

        let padded = drawing.bounds.insetBy(dx: -16, dy: -16)
        let image = drawing.image(from: padded, scale: 2.0)
        guard let cgImage = ReadingConfirmationSheet.makeWhiteBackgroundImage(image)?.cgImage else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["is-IS", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let candidates = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return candidates.joined(separator: " ")
        } catch {
            return nil
        }
    }

    private static func makeWhiteBackgroundImage(_ image: UIImage) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
private struct SubmissionAction: Identifiable {
    let mode: QueryMode

    var id: String { mode.rawValue }

    var title: String {
        switch mode {
        case .hint:
            return "Senda fyrirspurn um vísbendingu?"
        case .check_solution:
            return "Senda fyrirspurn um yfirferð?"
        case .reveal:
            return "Senda fyrirspurn um lausn?"
        }
    }

    var message: String {
        switch mode {
        case .hint:
            return "Þú ert að biðja um vísbendingu fyrir þetta dæmi."
        case .check_solution:
            return "Þú ert að biðja um yfirferð á skrefunum þínum."
        case .reveal:
            return "Þú ert að biðja um að sýna lausnina."
        }
    }
}

private struct ActionInfoSheet: View {
    let mode: QueryMode
    @Environment(\.dismiss) private var dismiss

    private var summaryText: String {
        switch mode {
        case .hint:
            return "Gefur þér vísbendingu án þess að sýna alla lausn."
        case .check_solution:
            return "Kennari yfirfer skrefin þín og bendir á hvað má bæta."
        case .reveal:
            return "Sýnir leið að lausn þegar kennari hefur yfirfarið lausnina þína og metið hana rétta."
        }
    }

    private var requirementsText: String {
        switch mode {
        case .hint, .check_solution:
            return "Krefst myndar af dæmi og vinnu á blaðinu."
        case .reveal:
            return "Virkar aðeins eftir að kennari hefur yfirfarið lausnina og dæmt hana fullkomlega rétta. Þá má biðja um að sjá lausnina."
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(summaryText)
                    .font(.subheadline)
                Text(requirementsText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(mode.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Loka") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(230), .medium])
        .tint(AppTheme.Auth.primary)
    }
}

private struct FullScreenWorkspaceView: View {
    let problemTitle: String
    let problemImage: UIImage?
    let pages: [NotebookPage]
    let selectedPageIndex: Int
    let onSelectPage: (Int) -> Void
    @Binding var drawing: PKDrawing
    @Binding var zoomScale: CGFloat
    let controller: PencilCanvasController
    @Binding var selectedTool: CanvasToolKind
    @Binding var selectedInkUIColor: UIColor
    @Binding var pencilWidth: CGFloat
    @Binding var penWidth: CGFloat
    @Binding var highlighterWidth: CGFloat
    @Binding var eraserType: PKEraserTool.EraserType
    @Binding var isRulerActive: Bool
    @Binding var paperStyle: PaperStyle

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingColorPicker = false

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                VStack(spacing: 0) {
                    PencilCanvasView(
                        drawing: $drawing,
                        zoomScale: $zoomScale,
                        selectedTool: $selectedTool,
                        controller: controller,
                        isCanvasActive: true,
                        inkColor: selectedInkUIColor,
                        pencilWidth: pencilWidth,
                        penWidth: penWidth,
                        highlighterWidth: highlighterWidth,
                        eraserType: eraserType,
                        isRulerActive: isRulerActive,
                        paperStyle: paperStyle,
                        viewportMode: .fitPage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(AppTheme.Auth.background)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Button("Lokið") {
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())

                        Spacer()

                        Text(problemTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        HStack(spacing: 8) {
                            workspaceActionButton(
                                systemImageName: "arrow.uturn.backward",
                                isEnabled: controller.canUndo,
                                action: { controller.undo() }
                            )
                            workspaceActionButton(
                                systemImageName: "arrow.uturn.forward",
                                isEnabled: controller.canRedo,
                                action: { controller.redo() }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(AppTheme.Auth.logo)

                    HStack(spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(CanvasToolKind.notebookEnabledTools, id: \.rawValue) { tool in
                                    toolButton(tool)
                                }

                                toggleButton(
                                    systemImageName: "ruler",
                                    isSelected: isRulerActive,
                                    action: { isRulerActive.toggle() }
                                )

                                toolAdjustmentsView
                            }
                            .padding(.vertical, 2)
                        }

                        Spacer(minLength: 0)

                        paperStyleControls

                        Button {
                            isShowingColorPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(uiColor: selectedInkUIColor))
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 1))

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.Auth.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AppTheme.Auth.surface)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isShowingColorPicker) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Veldu lit")
                                    .font(.headline)
                                ColorPicker("Litur", selection: colorSelectionBinding, supportsOpacity: false)
                                    .labelsHidden()
                                colorSwatches
                            }
                            .padding(16)
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(AppTheme.Auth.surfaceMuted)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(pages.enumerated()), id: \.element.id) { idx, _ in
                                Button("Blað \(idx + 1)") {
                                    onSelectPage(idx)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(selectedPageIndex == idx ? AppTheme.Auth.primary : AppTheme.Auth.surface)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Button("Hreinsa blað", role: .destructive) {
                        drawing = PKDrawing()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(AppTheme.Auth.surfaceMuted)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AppTheme.Auth.primary)
    }

    private func workspaceActionButton(
        systemImageName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
            .padding(10)
            .background(Color.white.opacity(isEnabled ? 0.16 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func toolButton(_ tool: CanvasToolKind) -> some View {
        let isSelected = selectedTool == tool

        return Button {
            selectedTool = tool
        } label: {
            Image(systemName: tool.systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)
                .frame(width: 22, height: 22)
            .padding(10)
            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleButton(
        systemImageName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)
                .frame(width: 22, height: 22)
            .padding(10)
            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var toolAdjustmentsView: some View {
        switch selectedTool {
        case .pencil:
            widthSelector(widths: [3, 5, 8, 11], selectedWidth: $pencilWidth)
        case .pen:
            widthSelector(widths: [3, 5, 7, 10], selectedWidth: $penWidth)
        case .highlighter:
            widthSelector(widths: [10, 16, 22, 28], selectedWidth: $highlighterWidth)
        case .eraser:
            HStack(spacing: 8) {
                eraserTypeButton(title: "Strokur", type: .vector)
                eraserTypeButton(title: "Nákvæmt", type: .bitmap)
            }
        case .lasso:
            Text("Veldu strik til að færa eða breyta")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
                .padding(.horizontal, 10)
        }
    }

    private func widthSelector(widths: [CGFloat], selectedWidth: Binding<CGFloat>) -> some View {
        HStack(spacing: 8) {
            ForEach(widths, id: \.self) { width in
                let isSelected = abs(selectedWidth.wrappedValue - width) < 0.01

                Button {
                    selectedWidth.wrappedValue = width
                } label: {
                    ZStack {
                        Circle()
                            .fill(isSelected ? AppTheme.Auth.primary.opacity(0.14) : AppTheme.Auth.surface)
                            .frame(width: 34, height: 34)

                        Circle()
                            .fill(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.textPrimary)
                            .frame(width: width + 2, height: width + 2)
                    }
                    .overlay(
                        Circle()
                            .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 6)
    }

    private func eraserTypeButton(title: String, type: PKEraserTool.EraserType) -> some View {
        let isSelected = eraserType == type

        return Button {
            eraserType = type
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var paperStyleControls: some View {
        HStack(spacing: 8) {
            ForEach(PaperStyle.allCases, id: \.rawValue) { style in
                let isSelected = paperStyle == style

                Button {
                    paperStyle = style
                } label: {
                    Text(style.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 4)
    }

    private var colorSelectionBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: selectedInkUIColor) },
            set: { selectedInkUIColor = UIColor($0) }
        )
    }

    private var colorSwatches: some View {
        let palette: [UIColor] = [
            .label,
            .systemBlue,
            .systemRed,
            .systemGreen,
            .systemOrange,
            .systemPurple
        ]

        return HStack(spacing: 10) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, color in
                Button {
                    selectedInkUIColor = color
                } label: {
                    Circle()
                        .fill(Color(uiColor: color))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(
                                    selectedInkUIColor.isEqual(color) ? AppTheme.Auth.primary : AppTheme.Auth.border,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension Color {
    var hexString: String {
        let uiColor = UIColor(self)
        guard let components = uiColor.cgColor.components else {
            return "#000000"
        }

        let resolved: (CGFloat, CGFloat, CGFloat)
        if components.count >= 3 {
            resolved = (components[0], components[1], components[2])
        } else if components.count == 2 {
            resolved = (components[0], components[0], components[0])
        } else {
            return "#000000"
        }

        return String(
            format: "#%02X%02X%02X",
            Int(resolved.0 * 255),
            Int(resolved.1 * 255),
            Int(resolved.2 * 255)
        )
    }
}

private struct AttemptBrowserView: View {
    let problemTitle: String
    let attempts: [ProblemAttempt]
    let initialAttemptID: String
    let selectedRating: (ProblemAttempt) -> AttemptFeedbackRating?
    let selectedComment: (ProblemAttempt) -> String?
    let isSubmitting: (ProblemAttempt) -> Bool
    let feedbackErrorMessage: (ProblemAttempt) -> String?
    let onSubmitFeedback: (ProblemAttempt, AttemptFeedbackRating, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAttemptID: String

    init(
        problemTitle: String,
        attempts: [ProblemAttempt],
        initialAttemptID: String,
        selectedRating: @escaping (ProblemAttempt) -> AttemptFeedbackRating?,
        selectedComment: @escaping (ProblemAttempt) -> String?,
        isSubmitting: @escaping (ProblemAttempt) -> Bool,
        feedbackErrorMessage: @escaping (ProblemAttempt) -> String?,
        onSubmitFeedback: @escaping (ProblemAttempt, AttemptFeedbackRating, String?) -> Void
    ) {
        self.problemTitle = problemTitle
        self.attempts = attempts
        self.initialAttemptID = initialAttemptID
        self.selectedRating = selectedRating
        self.selectedComment = selectedComment
        self.isSubmitting = isSubmitting
        self.feedbackErrorMessage = feedbackErrorMessage
        self.onSubmitFeedback = onSubmitFeedback
        _selectedAttemptID = State(initialValue: initialAttemptID)
    }

    var body: some View {
        ZStack {
            AppTheme.Auth.background
                .ignoresSafeArea()

            TabView(selection: $selectedAttemptID) {
                ForEach(attempts) { attempt in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Hamur: \(localizedAttemptMode(attempt.mode))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Auth.textSecondary)

                            Text("Niðurstaða: \(localizedVerdict(attempt.verdict))")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppTheme.Auth.textPrimary)

                            MathTextView(text: attempt.message_is ?? "Engin skilaboð frá kennara tiltæk.")
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.Auth.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Lausnarmynd")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.Auth.textPrimary)

                                if let urlString = attempt.solution_image_url, let url = URL(string: urlString) {
                                    ZoomableAttemptImageView(url: url)
                                        .frame(minHeight: 460)
                                        .background(AppTheme.Auth.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(AppTheme.Auth.border, lineWidth: 1)
                                        )
                                } else {
                                    Text("Engin slóð á lausnarmynd tiltæk fyrir þessa tilraun.")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Auth.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                        .background(AppTheme.Auth.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(AppTheme.Auth.border, lineWidth: 1)
                                        )
                                }
                            }

                            AttemptFeedbackSection(
                                attempt: attempt,
                                selectedRating: selectedRating(attempt),
                                selectedComment: selectedComment(attempt),
                                isSubmitting: isSubmitting(attempt),
                                feedbackErrorMessage: feedbackErrorMessage(attempt),
                                onSubmitFeedback: { rating, comment in
                                    onSubmitFeedback(attempt, rating, comment)
                                }
                            )
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                    .tag(attempt.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            attemptBrowserHeader
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            attemptPageIndicator
        }
        .tint(AppTheme.Auth.primary)
    }

    private var attemptBrowserHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Til baka")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text("Tilraunir - \(problemTitle)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            Color.clear
                .frame(width: 88, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(AppTheme.Auth.logo)
    }

    private var attemptPageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(attempts.enumerated()), id: \.element.id) { _, attempt in
                let isSelected = attempt.id == selectedAttemptID

                Circle()
                    .fill(isSelected ? Color.white : AppTheme.Auth.textSecondary.opacity(0.55))
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? AppTheme.Auth.logo : Color.clear)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.Auth.background.opacity(0.96))
    }

    private func localizedVerdict(_ verdict: String?) -> String {
        guard let verdict = verdict?.trimmingCharacters(in: .whitespacesAndNewlines), !verdict.isEmpty else {
            return "Á ekki við"
        }

        switch verdict.lowercased() {
        case "fully_solved", "fully_correct":
            return "Fullkomlega rétt"
        case "correct_so_far", "correct":
            return "Rétt"
        case "incorrect":
            return "Rangt"
        case "partial":
            return "Að hluta rétt"
        case "unclear":
            return "Óskýrt"
        default:
            return verdict
        }
    }

    private func localizedAttemptMode(_ rawMode: String) -> String {
        switch rawMode.lowercased() {
        case QueryMode.hint.rawValue:
            return QueryMode.hint.displayName
        case QueryMode.check_solution.rawValue:
            return QueryMode.check_solution.displayName
        case QueryMode.reveal.rawValue:
            return QueryMode.reveal.displayName
        default:
            return rawMode.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct AttemptFeedbackSection: View {
    let attempt: ProblemAttempt
    let selectedRating: AttemptFeedbackRating?
    let selectedComment: String?
    let isSubmitting: Bool
    let feedbackErrorMessage: String?
    let onSubmitFeedback: (AttemptFeedbackRating, String?) -> Void

    @State private var draftRating: AttemptFeedbackRating?
    @State private var commentText: String

    init(
        attempt: ProblemAttempt,
        selectedRating: AttemptFeedbackRating?,
        selectedComment: String?,
        isSubmitting: Bool,
        feedbackErrorMessage: String?,
        onSubmitFeedback: @escaping (AttemptFeedbackRating, String?) -> Void
    ) {
        self.attempt = attempt
        self.selectedRating = selectedRating
        self.selectedComment = selectedComment
        self.isSubmitting = isSubmitting
        self.feedbackErrorMessage = feedbackErrorMessage
        self.onSubmitFeedback = onSubmitFeedback
        _draftRating = State(initialValue: selectedRating)
        _commentText = State(initialValue: String((selectedComment ?? "").prefix(FeedbackConstraints.maxCommentLength)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Var þessi endurgjöf gagnleg?")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                feedbackButton(
                    label: "Gagnlegt",
                    systemImage: draftRating == .up ? "hand.thumbsup.fill" : "hand.thumbsup",
                    isSelected: draftRating == .up,
                    action: { draftRating = .up }
                )
                feedbackButton(
                    label: "Ekki gagnlegt",
                    systemImage: draftRating == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                    isSelected: draftRating == .down,
                    action: { draftRating = .down }
                )
            }

            Text("Athugasemd (valfrjálst)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $commentText)
                .frame(minHeight: 76, maxHeight: 120)
                .padding(6)
                .background(AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: commentText) { _, newValue in
                    if newValue.count > FeedbackConstraints.maxCommentLength {
                        commentText = String(newValue.prefix(FeedbackConstraints.maxCommentLength))
                    }
                }
                .onChange(of: selectedComment) { _, newValue in
                    let next = String((newValue ?? "").prefix(FeedbackConstraints.maxCommentLength))
                    if next != commentText {
                        commentText = next
                    }
                }
                .onChange(of: selectedRating) { _, newValue in
                    if newValue != draftRating {
                        draftRating = newValue
                    }
                }

            Text("\(commentText.count)/\(FeedbackConstraints.maxCommentLength)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    commentText.count >= FeedbackConstraints.warningThreshold ? .orange : .secondary
                )
                .frame(maxWidth: .infinity, alignment: .trailing)

            Button {
                guard let draftRating else { return }
                onSubmitFeedback(draftRating, normalizedCommentText)
            } label: {
                Label(
                    hasUnsavedChanges ? "Senda umsögn" : "Umsögn vistuð",
                    systemImage: hasUnsavedChanges ? "paperplane.fill" : "checkmark.circle.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draftRating == nil || isSubmitting || !hasUnsavedChanges)

            if isSubmitting {
                ProgressView("Vista umsögn...")
                    .font(.footnote)
            } else if !hasUnsavedChanges, let selectedRating {
                Text(selectedRating == .up ? "Vistað: Gagnlegt" : "Vistað: Ekki gagnlegt")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let feedbackErrorMessage, !feedbackErrorMessage.isEmpty {
                Text(feedbackErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private var normalizedCommentText: String? {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var hasUnsavedChanges: Bool {
        let currentComment = selectedComment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let draftComment = normalizedCommentText ?? ""
        return draftRating != selectedRating || currentComment != draftComment
    }

    @ViewBuilder
    private func feedbackButton(
        label: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? AppTheme.Auth.primary.opacity(0.18) : AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityHint("Sendir umsögn fyrir þetta svar kennara.")
    }
}

private struct ZoomableAttemptImageView: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 460)
            case let .success(image):
                ZoomableImageContent(image: image)
                    .frame(maxWidth: .infinity, minHeight: 460)
            case .failure:
                Text("Gat ekki hlaðið lausnarmynd.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            @unknown default:
                EmptyView()
            }
        }
    }
}

private struct ZoomableImageContent: View {
    let image: Image
    @State private var zoomScale: CGFloat = 1
    @State private var accumulatedZoomScale: CGFloat = 1
    private let minZoomScale: CGFloat = 0.45
    private let maxZoomScale: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                VStack {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * zoomScale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = min(max(accumulatedZoomScale * value, minZoomScale), maxZoomScale)
                                }
                                .onEnded { value in
                                    accumulatedZoomScale = min(max(accumulatedZoomScale * value, minZoomScale), maxZoomScale)
                                    zoomScale = accumulatedZoomScale
                                }
                        )
                        .onTapGesture(count: 2) {
                            if zoomScale > 1 {
                                zoomScale = 1
                                accumulatedZoomScale = 1
                            } else {
                                zoomScale = 2
                                accumulatedZoomScale = 2
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
