import SwiftUI
import PencilKit
import UIKit

private struct ActiveExamSession: Identifiable {
    let sessionId: String
    let pack: ExamPackDetail

    var id: String { sessionId }
}

struct ExamPrepSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var packSize: ExamPackSize = .ten
    @State private var buildMode: ExamBuildMode = .auto
    @State private var feedbackMode: ExamFeedbackMode = .end_exam
    @State private var selectedTopics: Set<ExamTopic> = Set(ExamTopic.allCases)
    @State private var selectedManualTargets: Set<ExamErrorTarget> = []
    @State private var recentPacks: [ExamPackSummary] = []

    @State private var isLoadingPacks = false
    @State private var isGenerating = false
    @State private var startingPackId: String?
    @State private var loadedDefaults = false
    @State private var errorMessage: String?
    @State private var activeSession: ActiveExamSession?

    var body: some View {
        NavigationStack {
            Form {
                createSection
                if !recentPacks.isEmpty {
                    recentPacksSection
                }
                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Prófaundirbúningur")
            .scrollContentBackground(.hidden)
            .background(AppTheme.Auth.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Loka") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Endurhlaða") {
                        Task { await loadRecentPacks() }
                    }
                    .disabled(isLoadingPacks || isGenerating || startingPackId != nil)
                }
            }
        }
        .task {
            guard !loadedDefaults else { return }
            title = defaultPackTitle()
            loadedDefaults = true
            await loadRecentPacks()
        }
        .fullScreenCover(item: $activeSession) { session in
            ExamSessionView(sessionId: session.sessionId, pack: session.pack)
                .environmentObject(authManager)
        }
        .tint(AppTheme.Auth.primary)
    }

    private var createSection: some View {
        Section("Búa til nýtt æfingarpróf") {
            TextField("Titill prófs", text: $title)

            selectionChips(
                title: "Fjöldi spurninga",
                values: ExamPackSize.allCases,
                selected: $packSize
            ) { size in
                "\(size.rawValue)"
            }

            selectionChips(
                title: "Valmát",
                values: ExamBuildMode.allCases,
                selected: $buildMode
            ) { mode in
                mode.displayName
            }

            selectionChips(
                title: "Endurgjöf",
                values: ExamFeedbackMode.allCases,
                selected: $feedbackMode
            ) { mode in
                mode.displayName
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Efnisflokkar")
                    .font(.subheadline.weight(.semibold))
                ForEach(ExamTopic.allCases) { topic in
                    toggleRow(
                        title: topic.displayName,
                        isSelected: selectedTopics.contains(topic)
                    ) {
                        if selectedTopics.contains(topic) {
                            selectedTopics.remove(topic)
                        } else {
                            selectedTopics.insert(topic)
                        }
                    }
                }
            }

            if buildMode == .manual {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Markvissar villugerðir")
                        .font(.subheadline.weight(.semibold))
                    ForEach(ExamErrorTarget.allCases) { target in
                        toggleRow(
                            title: target.displayName,
                            isSelected: selectedManualTargets.contains(target)
                        ) {
                            if selectedManualTargets.contains(target) {
                                selectedManualTargets.remove(target)
                            } else {
                                selectedManualTargets.insert(target)
                            }
                        }
                    }
                }
            }

            Button {
                Task { await createAndStartExamPack() }
            } label: {
                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Bý til...")
                    }
                } else {
                    Text("Búa til og hefja")
                }
            }
            .disabled(isGenerating || isLoadingPacks || startingPackId != nil)
        }
        .listRowBackground(AppTheme.Auth.surfaceMuted)
    }

    private var recentPacksSection: some View {
        Section("Nýleg próf") {
            ForEach(recentPacks) { pack in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pack.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Auth.textPrimary)
                        Text(packMetaLine(pack))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatIcelandicDateOnly(pack.created_at))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await startPack(pack) }
                    } label: {
                        if startingPackId == pack.id {
                            ProgressView()
                        } else {
                            Text("Hefja")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(startingPackId != nil || isGenerating)
                }
            }
        }
        .listRowBackground(AppTheme.Auth.surfaceMuted)
    }

    @ViewBuilder
    private func toggleRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.Auth.primary : .secondary)
                Text(title)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectionChips<Value: Hashable>(
        title: String,
        values: [Value],
        selected: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)

            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    let isSelected = selected.wrappedValue == value
                    Button {
                        selected.wrappedValue = value
                    } label: {
                        Text(label(value))
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)
                            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(AppTheme.Auth.border, lineWidth: isSelected ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func createAndStartExamPack() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            errorMessage = "Titill prófs vantar."
            return
        }
        guard !selectedTopics.isEmpty else {
            errorMessage = "Veldu að minnsta kosti einn efnisflokk."
            return
        }
        if buildMode == .manual && selectedManualTargets.isEmpty {
            errorMessage = "Veldu að minnsta kosti eina villugerð fyrir handvirkan ham."
            return
        }

        let payload = ExamPackCreateRequest(
            title: normalizedTitle,
            pack_size: packSize.rawValue,
            build_mode: buildMode.rawValue,
            feedback_mode: feedbackMode.rawValue,
            topics: selectedTopics.map(\.rawValue).sorted(),
            manual_error_targets: buildMode == .manual ? selectedManualTargets.map(\.rawValue).sorted() : nil
        )

        do {
            let created = try await authManager.createExamPack(payload: payload)
            let started = try await authManager.startExamPack(packId: created.id)
            activeSession = ActiveExamSession(sessionId: started.session_id, pack: started.pack)
            await loadRecentPacks()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að búa til próf."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPack(_ pack: ExamPackSummary) async {
        errorMessage = nil
        startingPackId = pack.id
        defer { startingPackId = nil }

        do {
            let started = try await authManager.startExamPack(packId: pack.id)
            activeSession = ActiveExamSession(sessionId: started.session_id, pack: started.pack)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að hefja próf."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRecentPacks() async {
        isLoadingPacks = true
        errorMessage = nil
        defer { isLoadingPacks = false }

        do {
            recentPacks = try await authManager.listExamPacks()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að sækja próf."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func packMetaLine(_ pack: ExamPackSummary) -> String {
        let modeLabel = pack.build_mode == ExamBuildMode.manual.rawValue ? "handvirkt" : "sjálfvirkt"
        let feedbackLabel = pack.feedback_mode == ExamFeedbackMode.per_question.rawValue ? "eftir hverja spurningu" : "í lok prófs"
        return "\(pack.pack_size) sp. | \(modeLabel) | \(feedbackLabel)"
    }

    private func defaultPackTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Æfingarpróf \(formatter.string(from: Date()))"
    }

}

private struct ExamSessionView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    let sessionId: String
    let pack: ExamPackDetail

    @State private var currentIndex: Int = 0
    @State private var extractedAnswers: [String: String] = [:]
    @State private var perQuestionFeedback: [String: ExamAnswerUpdateResponse] = [:]
    @State private var submitSummary: ExamSessionSubmitResponse?
    @State private var results: ExamSessionResultsResponse?
    @State private var isSaving: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var savedDrawingHashesByItemId: [String: Int] = [:]
    @State private var hasLoadedSessionState = false
    @State private var showSubmitConfirmation = false
    @State private var answerDrawingsByItemId: [String: PKDrawing] = [:]
    @State private var answerDrawing: PKDrawing = .init()
    @State private var answerCanvasZoomScale: CGFloat = 0
    @StateObject private var answerCanvasController = PencilCanvasController()
    @State private var answerSelectedTool: CanvasToolKind = .pen
    @State private var answerInkUIColor: UIColor = .label
    @State private var answerPencilWidth: CGFloat = 5
    @State private var answerPenWidth: CGFloat = 5
    @State private var answerHighlighterWidth: CGFloat = 18
    @State private var answerEraserType: PKEraserTool.EraserType = .vector
    @State private var answerRulerActive = false

    private var orderedItems: [ExamPackItemSummary] {
        pack.items.sorted { lhs, rhs in lhs.position < rhs.position }
    }

    private var hasItems: Bool {
        !orderedItems.isEmpty
    }

    private var currentItem: ExamPackItemSummary? {
        guard hasItems, orderedItems.indices.contains(currentIndex) else { return nil }
        return orderedItems[currentIndex]
    }

    private var feedbackIsPerQuestion: Bool {
        pack.feedback_mode == ExamFeedbackMode.per_question.rawValue
    }

    private var unansweredCount: Int {
        orderedItems.reduce(into: 0) { count, item in
            if !hasAnswered(itemId: item.id) {
                count += 1
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let results {
                    resultsView(results: results)
                } else {
                    questionFlowView
                }
            }
            .navigationTitle(pack.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(results == nil ? "Hætta" : "Loka") { dismiss() }
                }
            }
            .alert("Villa", isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        errorMessage = nil
                    }
                }
            )) {
                Button("Í lagi", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Skila prófi?", isPresented: $showSubmitConfirmation) {
                Button("Hætta við", role: .cancel) {}
                Button("Skila samt", role: .destructive) {
                    Task { await submitExam() }
                }
            } message: {
                Text("Það eru \(unansweredCount) ósvöruð dæmi. Viltu skila samt?")
            }
        }
        .task {
            await hydrateSessionStateIfNeeded()
        }
        .tint(AppTheme.Auth.primary)
    }

    private var questionFlowView: some View {
        VStack(spacing: 12) {
            if let currentItem {
                headerView(item: currentItem)
                questionNavigator

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        questionCard(item: currentItem)
                        answerEditor(item: currentItem)
                        if feedbackIsPerQuestion {
                            feedbackCard(itemId: currentItem.id)
                        }
                        if let savedMessage, !savedMessage.isEmpty {
                            Text(savedMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                actionBar(item: currentItem)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                ContentUnavailableView(
                    "Engar spurningar",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Engar spurningar voru búnar til í þessu prófi.")
                )
            }
        }
        .background(AppTheme.Auth.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func headerView(item: ExamPackItemSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spurning \(currentIndex + 1) af \(orderedItems.count)")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer()
                if unansweredCount > 0 {
                    Text("Ósvöruð: \(unansweredCount)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.Auth.surfaceMuted)
                        .clipShape(Capsule())
                }
                Text(localizedTopic(item.topic))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.Auth.surface)
                    .clipShape(Capsule())
            }

            ProgressView(value: Double(currentIndex + 1), total: Double(max(orderedItems.count, 1)))
                .tint(AppTheme.Auth.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var questionNavigator: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        Task { await moveToQuestion(index: index) }
                    } label: {
                        Text("\(item.position)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(
                                currentIndex == index
                                    ? Color.white
                                    : (hasAnswered(itemId: item.id) ? AppTheme.Auth.textPrimary : AppTheme.Auth.textSecondary)
                            )
                            .background(
                                currentIndex == index
                                    ? AppTheme.Auth.primary
                                    : (hasAnswered(itemId: item.id) ? AppTheme.Auth.surface : AppTheme.Auth.surfaceMuted)
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(AppTheme.Auth.border, lineWidth: currentIndex == index ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || isSubmitting)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func questionCard(item: ExamPackItemSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dæmi")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
            Text(item.question_text)
                .font(.body)
                .foregroundStyle(AppTheme.Auth.textPrimary)

        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func answerEditor(item: ExamPackItemSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Þitt svar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)

            PencilCanvasView(
                drawing: $answerDrawing,
                zoomScale: $answerCanvasZoomScale,
                selectedTool: $answerSelectedTool,
                controller: answerCanvasController,
                inkColor: answerInkUIColor,
                pencilWidth: answerPencilWidth,
                penWidth: answerPenWidth,
                highlighterWidth: answerHighlighterWidth,
                eraserType: answerEraserType,
                isRulerActive: answerRulerActive,
                paperStyle: .squared,
                viewportMode: .fitWidth
            )
            .frame(minHeight: 260)

            HStack(spacing: 8) {
                ForEach(CanvasToolKind.examEnabledTools, id: \.rawValue) { tool in
                    examToolButton(tool)
                }
                Spacer(minLength: 0)
                Button {
                    answerCanvasController.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!answerCanvasController.canUndo)

                Button {
                    answerCanvasController.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!answerCanvasController.canRedo)
            }

            if answerSelectedTool == .eraser {
                HStack(spacing: 8) {
                    examEraserTypeButton(title: "Strokur", type: .vector)
                    examEraserTypeButton(title: "Nákvæmt", type: .bitmap)
                    Spacer(minLength: 0)
                }
            }

            Text("Skrifaðu lokasvarið skýrt neðst í teiknigluggann og veldu svo Vista.")
                .font(.footnote)
                .foregroundStyle(AppTheme.Auth.textSecondary)

            if let extractedAnswer = normalizedAnswer(extractedAnswers[item.id]) {
                Text("Lesið lokasvar: \(extractedAnswer)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private func examToolButton(_ tool: CanvasToolKind) -> some View {
        let isSelected = answerSelectedTool == tool
        return Button {
            answerSelectedTool = tool
        } label: {
            Image(systemName: tool.systemImageName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)
                .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func examEraserTypeButton(title: String, type: PKEraserTool.EraserType) -> some View {
        let isSelected = answerEraserType == type
        return Button {
            answerEraserType = type
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.textPrimary)
                .background(AppTheme.Auth.surfaceMuted)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func feedbackCard(itemId: String) -> some View {
        if let feedback = perQuestionFeedback[itemId], feedback.graded {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: feedback.is_correct == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(feedback.is_correct == true ? .green : .red)
                    Text(feedback.is_correct == true ? "Rétt" : "Þarf að bæta")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Auth.textPrimary)
                    Spacer(minLength: 0)
                }
                if let feedbackText = feedback.feedback_text, !feedbackText.isEmpty {
                    Text(feedbackText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.Auth.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func actionBar(item: ExamPackItemSummary) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Til baka") {
                    Task { await moveToQuestion(index: currentIndex - 1) }
                }
                .buttonStyle(.bordered)
                .disabled(currentIndex == 0 || isSaving || isSubmitting)

                Button("Næsta") {
                    Task { await moveToQuestion(index: currentIndex + 1) }
                }
                .buttonStyle(.bordered)
                .disabled(currentIndex >= orderedItems.count - 1 || isSaving || isSubmitting)

                Spacer(minLength: 0)

                Button {
                    Task { await saveAnswer(for: item) }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(feedbackIsPerQuestion ? "Vista + athuga" : "Vista")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || isSubmitting)
            }

            Button {
                if unansweredCount > 0 {
                    showSubmitConfirmation = true
                } else {
                    Task { await submitExam() }
                }
            } label: {
                if isSubmitting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Sendi...")
                    }
                } else {
                    Text("Skila prófi")
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(isSubmitting || isSaving)
        }
    }

    private func saveAnswer(for item: ExamPackItemSummary, showSavedMessage: Bool = true) async {
        isSaving = true
        errorMessage = nil
        if showSavedMessage {
            savedMessage = nil
        }
        defer { isSaving = false }

        do {
            if currentItem?.id == item.id {
                persistDrawing(for: item.id)
            }
            let answerImageBase64 = makeAnswerImageBase64(for: item.id)
            let response = try await authManager.saveExamAnswer(
                sessionId: sessionId,
                itemId: item.id,
                answerText: nil,
                answerImageBase64: answerImageBase64
            )
            if response.graded {
                perQuestionFeedback[item.id] = response
            }
            if let answer = normalizedAnswer(response.answer_text) {
                extractedAnswers[item.id] = answer
            } else {
                extractedAnswers.removeValue(forKey: item.id)
            }
            savedDrawingHashesByItemId[item.id] = drawingHashForItem(itemId: item.id)
            if showSavedMessage {
                savedMessage = "Vistað."
            }
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að vista svar."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitExam() async {
        isSubmitting = true
        errorMessage = nil
        savedMessage = nil
        defer { isSubmitting = false }

        do {
            if let item = currentItem {
                persistDrawing(for: item.id)
            }
            for item in orderedItems {
                let answerImageBase64 = makeAnswerImageBase64(for: item.id)
                let response = try await authManager.saveExamAnswer(
                    sessionId: sessionId,
                    itemId: item.id,
                    answerText: nil,
                    answerImageBase64: answerImageBase64
                )
                if response.graded {
                    perQuestionFeedback[item.id] = response
                }
                if let answer = normalizedAnswer(response.answer_text) {
                    extractedAnswers[item.id] = answer
                } else {
                    extractedAnswers.removeValue(forKey: item.id)
                }
                savedDrawingHashesByItemId[item.id] = drawingHashForItem(itemId: item.id)
            }

            submitSummary = try await authManager.submitExamSession(sessionId: sessionId)
            results = try await authManager.getExamSessionResults(sessionId: sessionId)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að skila prófi."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToQuestion(index: Int) async {
        guard orderedItems.indices.contains(index), index != currentIndex else { return }
        if let item = currentItem {
            persistDrawing(for: item.id)
        }
        if let item = currentItem, isCurrentAnswerDirty(itemId: item.id) {
            await saveAnswer(for: item, showSavedMessage: false)
            if errorMessage != nil {
                return
            }
        }
        savedMessage = nil
        currentIndex = index
        if let newItem = currentItem {
            loadDrawing(for: newItem.id)
        }
    }

    private func isCurrentAnswerDirty(itemId: String) -> Bool {
        drawingHashForItem(itemId: itemId) != savedDrawingHashesByItemId[itemId]
    }

    private func persistDrawing(for itemId: String) {
        answerDrawingsByItemId[itemId] = answerDrawing
    }

    private func loadDrawing(for itemId: String) {
        answerDrawing = answerDrawingsByItemId[itemId] ?? PKDrawing()
    }

    private func hasAnswered(itemId: String) -> Bool {
        if let extracted = normalizedAnswer(extractedAnswers[itemId]), !extracted.isEmpty {
            return true
        }
        return !drawingForItem(itemId: itemId).bounds.isEmpty
    }

    private func drawingForItem(itemId: String) -> PKDrawing {
        if currentItem?.id == itemId {
            return answerDrawing
        }
        return answerDrawingsByItemId[itemId] ?? PKDrawing()
    }

    private func drawingHashForItem(itemId: String) -> Int {
        drawingForItem(itemId: itemId).dataRepresentation().hashValue
    }

    private func makeAnswerImageBase64(for itemId: String) -> String? {
        let drawing = drawingForItem(itemId: itemId)
        guard !drawing.bounds.isEmpty else { return nil }

        let paddedBounds = drawing.bounds.insetBy(dx: -16, dy: -16)
        let rawImage = drawing.image(from: paddedBounds, scale: 2.0)
        let normalized = flattenAnswerImageOnWhite(rawImage)
        let optimized = optimizeAnswerImageForUpload(normalized)
        guard let jpegData = optimized.jpegData(compressionQuality: 0.82) else { return nil }
        return jpegData.base64EncodedString()
    }

    private func flattenAnswerImageOnWhite(_ image: UIImage) -> UIImage {
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func optimizeAnswerImageForUpload(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1200
        let currentSize = image.size
        let largestDimension = max(currentSize.width, currentSize.height)
        guard largestDimension > maxDimension, largestDimension > 0 else {
            return image
        }

        let ratio = maxDimension / largestDimension
        let targetSize = CGSize(
            width: max(1, floor(currentSize.width * ratio)),
            height: max(1, floor(currentSize.height * ratio))
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func hydrateSessionStateIfNeeded() async {
        guard !hasLoadedSessionState else { return }
        hasLoadedSessionState = true

        do {
            let state = try await authManager.getExamSessionResults(sessionId: sessionId)
            if state.status == "graded" {
                results = state
                return
            }

            var hydratedAnswers: [String: String] = [:]
            var feedbackByItem: [String: ExamAnswerUpdateResponse] = [:]

            for item in state.items {
                if let answer = item.answer_text {
                    hydratedAnswers[item.item_id] = answer
                }
                if feedbackIsPerQuestion, let isCorrect = item.is_correct {
                    feedbackByItem[item.item_id] = ExamAnswerUpdateResponse(
                        session_id: state.session_id,
                        item_id: item.item_id,
                        answer_text: item.answer_text,
                        is_correct: isCorrect,
                        score: item.score,
                        feedback_text: item.feedback_text,
                        graded: true
                    )
                }
            }

            extractedAnswers = hydratedAnswers
            perQuestionFeedback = feedbackByItem

            if let firstUnanswered = orderedItems.firstIndex(where: { normalizedAnswer(hydratedAnswers[$0.id]) == nil }) {
                currentIndex = firstUnanswered
            } else {
                currentIndex = 0
            }
            if let current = currentItem {
                loadDrawing(for: current.id)
            }
            for item in orderedItems {
                savedDrawingHashesByItemId[item.id] = drawingHashForItem(itemId: item.id)
            }
        } catch {
            // Keep resume hydration best-effort and non-blocking for exam start.
        }
    }

    @ViewBuilder
    private func resultsView(results: ExamSessionResultsResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summaryCard(results: results)
                ForEach(results.items.sorted { lhs, rhs in lhs.position < rhs.position }) { item in
                    resultRow(item: item)
                }
            }
            .padding(16)
        }
        .background(AppTheme.Auth.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func summaryCard(results: ExamSessionResultsResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lokaeinkunn")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            let scoreCorrect = results.score_correct ?? submitSummary?.score_correct ?? 0
            let scoreTotal = results.score_total ?? submitSummary?.score_total ?? orderedItems.count
            let scorePercent = results.score_percent ?? submitSummary?.score_percent ?? 0

            Text("\(scoreCorrect) / \(max(scoreTotal, 1))")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppTheme.Auth.textPrimary)
            Text("\(Int(scorePercent.rounded()))%")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func resultRow(item: ExamSessionResultItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("Sp.\(item.position)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer(minLength: 0)
                if let isCorrect = item.is_correct {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isCorrect ? .green : .red)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.question_text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            if let answer = item.answer_text, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Þitt svar: \(answer)")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            } else {
                Text("Þitt svar: (tómt)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let feedback = item.feedback_text, !feedback.isEmpty {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private func normalizedAnswer(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localizedTopic(_ value: String) -> String {
        if let topic = ExamTopic(rawValue: value.lowercased()) {
            return topic.displayName
        }
        return humanize(value)
    }

    private func localizedErrorType(_ value: String) -> String {
        if let errorType = ExamErrorTarget(rawValue: value.lowercased()) {
            return errorType.displayName
        }

        switch value.lowercased() {
        case "conceptual":
            return "Hugtakavilla"
        case "calculation":
            return "Reiknivilla"
        case "logic":
            return "Rökvilla"
        default:
            return humanize(value)
        }
    }

    private func humanize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }
}

private func formatIcelandicDateOnly(_ isoDate: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fallbackParser = ISO8601DateFormatter()
    fallbackParser.formatOptions = [.withInternetDateTime]
    let date = parser.date(from: isoDate) ?? fallbackParser.date(from: isoDate)
    guard let date else { return isoDate }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "is_IS")
    formatter.setLocalizedDateFormatFromTemplate("d MMMM y")
    formatter.monthSymbols = formatter.monthSymbols.map { $0.lowercased(with: formatter.locale) }
    return formatter.string(from: date)
}

private extension ExamBuildMode {
    var displayName: String {
        switch self {
        case .auto:
            return "Sjálfvirkt"
        case .manual:
            return "Handvirkt"
        }
    }
}

private extension ExamFeedbackMode {
    var displayName: String {
        switch self {
        case .per_question:
            return "Eftir hverja spurningu"
        case .end_exam:
            return "Í lok prófs"
        }
    }
}

private extension ExamTopic {
    var displayName: String {
        switch self {
        case .algebra:
            return "Algebra"
        case .fractions:
            return "Brot"
        }
    }
}
