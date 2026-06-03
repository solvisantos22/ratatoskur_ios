import SwiftUI
import UIKit
import PDFKit

struct ProblemsOverviewView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel = ProblemsOverviewViewModel()
    @AppStorage("profile.avatar.id") private var selectedAvatarID: String = ProfileAvatarOption.defaultID

    @State private var navigationPath: [ProblemNavigationRoute] = []
    @State private var showCreateSheet = false
    @State private var showCreateFolderSheet = false
    @State private var showProfileSheet = false
    @State private var showSubmissionExportSheet = false
    @State private var newProblemTitle = ""
    @State private var newFolderName = ""
    @State private var newFolderParentId: String?
    @State private var selectedRootFolderId: String?
    @State private var selectedSubfolderId: String?
    @State private var showExamPrepSheet = false
    @State private var showErrorBankSheet = false
    @State private var showStreakInfoAlert = false
    @State private var greetingPrefix = ["Hæ", "Góðan dag"].randomElement() ?? "Hæ"
    @State private var pendingFolderDeletion: FolderSummary?
    @State private var pendingProblemDeletion: ProblemSummary?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AppTheme.Auth.background
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.problems.isEmpty {
                    ProgressView("Sæki heimaskjá...")
                        .tint(AppTheme.Auth.primary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            brandHeader
                            greetingSection
                            statsSection
                            comingSoonSection
                            workspaceSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProblemNavigationRoute.self) { route in
                NotebookView(
                    problem: route.problem,
                    showImageOnboardingOnOpen: route.showImageOnboardingOnOpen
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreateSheet) {
                createProblemSheet
            }
            .sheet(isPresented: $showCreateFolderSheet) {
                createFolderSheet
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileSheet()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showSubmissionExportSheet) {
                SubmissionExportSheet(
                    problems: viewModel.problems,
                    folders: viewModel.folders,
                    exportAction: { selectedProblems, title, studentName in
                        try await viewModel.buildSubmissionPDF(
                            selectedProblems: selectedProblems,
                            submissionTitle: title,
                            studentName: studentName,
                            authManager: authManager
                        )
                    }
                )
                .environmentObject(authManager)
            }
            .sheet(isPresented: $showExamPrepSheet) {
                ExamPrepSheet()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showErrorBankSheet) {
                ErrorBankSheet(
                    folders: viewModel.folders,
                    initialSummary: viewModel.errorEventTypeSummary,
                    initialSelectedFolderId: effectiveSelectedFolderId
                )
                    .environmentObject(authManager)
            }
            .task {
                await viewModel.loadProblems(authManager: authManager)
                synchronizeFolderSelection()
            }
            .onChange(of: viewModel.folders) { _, _ in
                synchronizeFolderSelection()
            }
            .alert("Villa", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.errorMessage = nil
                    }
                }
            )) {
                Button("Í lagi", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Eyða möppu?", isPresented: Binding(
                get: { pendingFolderDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingFolderDeletion = nil
                    }
                }
            )) {
                Button("Hætta við", role: .cancel) {
                    pendingFolderDeletion = nil
                }
                Button("Eyða", role: .destructive) {
                    guard let folder = pendingFolderDeletion else { return }
                    Task {
                        let success = await viewModel.archiveFolder(
                            folderId: folder.id,
                            authManager: authManager
                        )
                        if success {
                            pendingFolderDeletion = nil
                        }
                    }
                }
                .disabled(viewModel.isArchivingFolder)
            } message: {
                if let folder = pendingFolderDeletion {
                    Text("Mappan „\(viewModel.folderPathTitle(folder: folder))“ verður fjarlægð. Dæmi flytjast í Óflokkað.")
                } else {
                    Text("")
                }
            }
            .alert("Eyða dæmi?", isPresented: Binding(
                get: { pendingProblemDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingProblemDeletion = nil
                    }
                }
            )) {
                Button("Hætta við", role: .cancel) {
                    pendingProblemDeletion = nil
                }
                Button("Eyða", role: .destructive) {
                    guard let problem = pendingProblemDeletion else { return }
                    Task {
                        let success = await viewModel.deleteProblem(
                            problemId: problem.id,
                            authManager: authManager
                        )
                        if success {
                            pendingProblemDeletion = nil
                        }
                    }
                }
                .disabled(viewModel.isDeletingProblem)
            } message: {
                if let problem = pendingProblemDeletion {
                    Text("Dæminu „\(problem.title)” verður eytt varanlega.")
                } else {
                    Text("")
                }
            }
            .alert("Streak", isPresented: $showStreakInfoAlert) {
                Button("Fara að reikna", role: .cancel) {}
            } message: {
                Text("Þú hefur reiknað a.m.k. eitt stærðfræðidæmi \(viewModel.activeStreakText) daga í röð\n\nReiknaðu eitt dæmi í dag til þess að framlengja \"streakið\".")
            }
        }
        .tint(AppTheme.Auth.primary)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            SVGLogoView(resourceName: "ratatoskur_logo")
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ratatoskur")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Text("Persónulegi einkakennarinn þinn")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    showStreakInfoAlert = true
                } label: {
                    ZStack {
                        SVGLogoView(resourceName: "shield")
                            .frame(width: 42, height: 42)
                            .accessibilityHidden(true)

                        Text(viewModel.activeStreakText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .offset(y: -1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skoða upplýsingar um streak")

                Button {
                    showProfileSheet = true
                } label: {
                    AvatarImageView(resourceName: dashboardAvatarResourceName)
                        .frame(width: 66, height: 66)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Opna prófíl")
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tölfræði síðustu viku")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            LazyVGrid(columns: statColumns, spacing: 10) {
                statCard(title: "Leyst dæmi", comparison: viewModel.solvedProblemsComparison)
                statCard(title: "Meðalfjöldi villa á dæmi", comparison: viewModel.averageErrorComparison)
                statCard(title: "Meðalfjöldi fyrirspurna á dæmi", comparison: viewModel.averageAttemptsComparison)
                statCard(title: "Algengasti hamur", value: viewModel.mostCommonModeText)
            }
        }
        .padding(12)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private var greetingSection: some View {
        Text(greetingText)
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.Auth.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var greetingText: String {
        let firstName = authManager.currentUser?.full_name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""

        let namePart = firstName.isEmpty ? "" : " \(firstName)"
        return "\(greetingPrefix)\(namePart). Gaman að sjá þig aftur."
    }

    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Næst á dagskrá")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            LazyVGrid(columns: featureColumns, spacing: 10) {
                examPrepCard
                errorBankCard
            }
        }
        .padding(12)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var workspaceSection: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 12) {
                foldersSection
                    .frame(minWidth: 280, maxWidth: 320, alignment: .topLeading)
                recentProblemsSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                foldersSection
                recentProblemsSection
            }
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Möppur")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer()
                Button("Ný mappa") {
                    newFolderName = ""
                    newFolderParentId = nil
                    showCreateFolderSheet = true
                }
                .font(.subheadline.weight(.semibold))
            }

            if horizontalSizeClass == .regular {
                ScrollView(.vertical, showsIndicators: true) {
                    folderTreeContent
                }
                .frame(maxHeight: 560)
            } else {
                folderTreeContent
            }
        }
        .padding(12)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private var folderTreeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            folderTreeRow(
                title: "Allt",
                count: viewModel.problemCount(folderId: nil),
                isSelected: selectedRootFolderId == nil,
                level: 0,
                systemImage: "tray.full"
            ) {
                selectedRootFolderId = nil
                selectedSubfolderId = nil
            }

            ForEach(viewModel.rootFolders) { folder in
                folderTreeRow(
                    title: viewModel.localizedFolderName(folder.name),
                    count: rootFolderCount(folder),
                    isSelected: selectedRootFolderId == folder.id,
                    level: 0,
                    systemImage: "folder"
                ) {
                    selectedRootFolderId = folder.id
                    selectedSubfolderId = nil
                }

                if selectedRootFolderId == folder.id {
                    let childFolders = viewModel.childFolders(parentFolderId: folder.id)
                    if !childFolders.isEmpty {
                        folderTreeRow(
                            title: "Allt í \(viewModel.localizedFolderName(folder.name))",
                            count: rootFolderCount(folder),
                            isSelected: selectedSubfolderId == nil,
                            level: 1,
                            systemImage: "tray.full"
                        ) {
                            selectedSubfolderId = nil
                        }

                        ForEach(childFolders) { child in
                            folderTreeRow(
                                title: viewModel.localizedFolderName(child.name),
                                count: viewModel.problemCount(folderId: child.id),
                                isSelected: selectedSubfolderId == child.id,
                                level: 1,
                                systemImage: "folder.badge.plus"
                            ) {
                                selectedSubfolderId = (selectedSubfolderId == child.id) ? nil : child.id
                            }
                        }
                    }
                }
            }

            if let selectedFolderForActions, !viewModel.isDefaultFolder(selectedFolderForActions) {
                Divider()
                    .padding(.vertical, 4)

                Menu {
                    if selectedSubfolderId == nil {
                        Button("Ný undirmappa") {
                            newFolderName = ""
                            newFolderParentId = selectedFolderForActions.id
                            showCreateFolderSheet = true
                        }
                    }
                    Button("Eyða möppu", role: .destructive) {
                        pendingFolderDeletion = selectedFolderForActions
                    }
                } label: {
                    Label(
                        "Aðgerðir fyrir \(viewModel.localizedFolderName(selectedFolderForActions.name))",
                        systemImage: "ellipsis.circle"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                }
            }
        }
    }

    private func folderTreeRow(
        title: String,
        count: Int,
        isSelected: Bool,
        level: Int,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)

                Spacer(minLength: 8)

                folderCountBadge(count)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
            .padding(.leading, CGFloat(level) * 18)
        }
        .buttonStyle(.plain)
    }

    private var recentProblemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dæmi")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer()
                NavigationLink {
                    AllProblemsView(
                        problems: viewModel.problems,
                        folders: viewModel.folders,
                        selectedFolderId: $viewModel.selectedFolderId,
                        onMove: { problem, folderId in
                            await viewModel.moveProblem(
                                problemId: problem.id,
                                folderId: folderId,
                                authManager: authManager
                            )
                        },
                        onDelete: { problem in
                            await viewModel.deleteProblem(
                                problemId: problem.id,
                                authManager: authManager
                            )
                        },
                        onSelect: { problem in
                            navigationPath.append(
                                ProblemNavigationRoute(problem: problem, showImageOnboardingOnOpen: false)
                            )
                        }
                    )
                } label: {
                    Text("Sjá allt")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(dashboardFilteredProblems.isEmpty)
                .opacity(dashboardFilteredProblems.isEmpty ? 0.45 : 1.0)
            }

            folderBreadcrumb

            if horizontalSizeClass == .regular {
                ScrollView(.vertical, showsIndicators: true) {
                    recentProblemsListContent
                }
                .frame(maxHeight: 560)
            } else {
                recentProblemsListContent
            }

            HStack(spacing: 10) {
                PrimaryButton(title: "Nýtt dæmi", isLoading: viewModel.isCreating) {
                    newProblemTitle = ""
                    showCreateSheet = true
                }
                .frame(maxWidth: .infinity)

                PrimaryButton(title: "Búa til skil", isLoading: false) {
                    showSubmissionExportSheet = true
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 6)
        }
        .padding(12)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var recentProblemsListContent: some View {
        if dashboardFilteredProblems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Engin dæmi í þessari möppu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Text("Búðu til nýtt dæmi eða veldu aðra möppu.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Auth.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ForEach(recentProblems) { problem in
                Button {
                    navigationPath.append(
                        ProblemNavigationRoute(problem: problem, showImageOnboardingOnOpen: false)
                    )
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(problem.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Auth.textPrimary)
                            Text(formatIcelandicDateOnly(problem.created_at))
                                .font(.caption)
                                .foregroundStyle(AppTheme.Auth.textSecondary)
                            if let folderName = problem.folder_name {
                                Text(localizedFolderName(folderName))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Menu {
                            if !viewModel.folders.isEmpty {
                                ForEach(viewModel.folders) { folder in
                                    Button(viewModel.folderPathTitle(folder: folder)) {
                                        Task {
                                            await viewModel.moveProblem(
                                                problemId: problem.id,
                                                folderId: folder.id,
                                                authManager: authManager
                                            )
                                        }
                                    }
                                }
                                Divider()
                            }
                            Button("Eyða dæmi", role: .destructive) {
                                pendingProblemDeletion = problem
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Auth.textSecondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Auth.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Auth.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                )
            }
        }
    }

    private var createProblemSheet: some View {
        NavigationStack {
            Form {
                Section("Titill dæmis") {
                    TextField("t.d. STÆ103 heimadæmi 3", text: $newProblemTitle)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Auth.background)
            .navigationTitle("Nýtt dæmi")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hætta við") {
                        showCreateSheet = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Búa til") {
                        let title = newProblemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }

                        Task {
                            if let created = await viewModel.createProblem(
                                title: title,
                                folderId: effectiveSelectedFolderId,
                                authManager: authManager
                            ) {
                                showCreateSheet = false
                                navigationPath.append(
                                    ProblemNavigationRoute(problem: created, showImageOnboardingOnOpen: true)
                                )
                            }
                        }
                    }
                    .disabled(newProblemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCreating)
                }
            }
        }
        .tint(AppTheme.Auth.primary)
    }

    private var createFolderSheet: some View {
        NavigationStack {
            Form {
                Section("Nafn möppu") {
                    TextField("t.d. STÆ103", text: $newFolderName)
                        .onChange(of: newFolderName) { _, value in
                            if value.count > ProblemsOverviewViewModel.maxFolderNameLength {
                                newFolderName = String(value.prefix(ProblemsOverviewViewModel.maxFolderNameLength))
                            }
                        }
                }
                Section("Staðsetning") {
                    Picker("Yfirmappa", selection: $newFolderParentId) {
                        Text("Rótarmappa").tag(Optional<String>.none)
                        ForEach(viewModel.rootFolders.filter { !viewModel.isDefaultFolder($0) }) { folder in
                            Text(viewModel.localizedFolderName(folder.name)).tag(Optional<String>.some(folder.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Auth.background)
            .navigationTitle("Ný mappa")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hætta við") {
                        newFolderParentId = nil
                        showCreateFolderSheet = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Búa til") {
                        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }

                        Task {
                            if await viewModel.createFolder(
                                name: name,
                                parentFolderId: newFolderParentId,
                                authManager: authManager
                            ) != nil {
                                newFolderParentId = nil
                                showCreateFolderSheet = false
                            }
                        }
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCreatingFolder)
                }
            }
        }
        .tint(AppTheme.Auth.primary)
    }

    @ViewBuilder
    private var folderBreadcrumb: some View {
        HStack(spacing: 6) {
            Image(systemName: "location")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.Auth.textSecondary)

            Button("Allt") {
                selectedRootFolderId = nil
                selectedSubfolderId = nil
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selectedRootFolderId == nil ? AppTheme.Auth.primary : AppTheme.Auth.textSecondary)

            if let selectedRootFolder {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                Button(viewModel.localizedFolderName(selectedRootFolder.name)) {
                    selectedRootFolderId = selectedRootFolder.id
                    selectedSubfolderId = nil
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedSubfolderId == nil ? AppTheme.Auth.primary : AppTheme.Auth.textSecondary)
            }

            if let selectedSubfolderId,
               let selectedSubfolder = viewModel.folders.first(where: { $0.id == selectedSubfolderId }) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                Text(viewModel.localizedFolderName(selectedSubfolder.name))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func folderCountBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.Auth.surfaceMuted)
            .clipShape(Capsule())
            .foregroundStyle(AppTheme.Auth.textPrimary)
    }

    @ViewBuilder
    private func folderFilterChip(
        title: String,
        count: Int,
        isSelected: Bool,
        leadingSystemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let leadingSystemImage {
                    Image(systemName: leadingSystemImage)
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                folderCountBadge(count)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)
            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var selectedRootFolder: FolderSummary? {
        guard let selectedRootFolderId else { return nil }
        return viewModel.folders.first(where: { $0.id == selectedRootFolderId })
    }

    private var selectedFolderForActions: FolderSummary? {
        if let selectedSubfolderId {
            return viewModel.folders.first(where: { $0.id == selectedSubfolderId })
        }
        if let selectedRootFolderId {
            return viewModel.folders.first(where: { $0.id == selectedRootFolderId })
        }
        return nil
    }

    private var effectiveSelectedFolderId: String? {
        selectedSubfolderId ?? selectedRootFolderId
    }

    private var dashboardFilteredProblems: [ProblemSummary] {
        guard let selectedRootFolderId else {
            return viewModel.problems
        }
        if let selectedSubfolderId {
            return viewModel.problems.filter { $0.folder_id == selectedSubfolderId }
        }

        let childIds = Set(viewModel.childFolders(parentFolderId: selectedRootFolderId).map(\.id))
        return viewModel.problems.filter { problem in
            guard let folderId = problem.folder_id else { return false }
            return folderId == selectedRootFolderId || childIds.contains(folderId)
        }
    }

    private func rootFolderCount(_ rootFolder: FolderSummary) -> Int {
        let childIds = Set(viewModel.childFolders(parentFolderId: rootFolder.id).map(\.id))
        return viewModel.problems.filter { problem in
            guard let folderId = problem.folder_id else { return false }
            return folderId == rootFolder.id || childIds.contains(folderId)
        }.count
    }

    private func synchronizeFolderSelection() {
        if let selectedRootFolderId,
           !viewModel.folders.contains(where: { $0.id == selectedRootFolderId && $0.parent_folder_id == nil }) {
            self.selectedRootFolderId = nil
            self.selectedSubfolderId = nil
        }

        if let selectedSubfolderId {
            guard let selectedSubfolder = viewModel.folders.first(where: { $0.id == selectedSubfolderId }),
                  let parentId = selectedSubfolder.parent_folder_id else {
                self.selectedSubfolderId = nil
                return
            }
            if self.selectedRootFolderId != parentId {
                self.selectedRootFolderId = parentId
            }
        }
    }

    private var recentProblems: [ProblemSummary] {
        Array(dashboardFilteredProblems.prefix(5))
    }

    private var dashboardAvatarResourceName: String {
        resolvedProfileAvatarOption(from: selectedAvatarID).resourceName
    }

    private func localizedFolderName(_ value: String) -> String {
        viewModel.localizedFolderName(value)
    }

    private var statColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: horizontalSizeClass == .regular ? 4 : 2)
    }

    private var featureColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: horizontalSizeClass == .regular ? 2 : 1)
    }

    @ViewBuilder
    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.Auth.textPrimary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statCard(title: String, comparison: ProblemsOverviewViewModel.ComparativeStat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(comparison.currentValue)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Image(systemName: trendSystemImage(comparison.trend))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                Text("\(comparison.deltaValue) frá vikunni á undan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private func trendSystemImage(_ trend: ProblemsOverviewViewModel.ComparativeStat.Trend) -> String {
        switch trend {
        case .up:
            return "arrow.up.right"
        case .down:
            return "arrow.down.right"
        case .flat:
            return "arrow.right"
        }
    }

    private var examPrepCard: some View {
        Button {
            showExamPrepSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "target")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                }
                .foregroundStyle(Color.white)

                Text("Prófaundirbúningur")
                    .font(.headline)
                    .foregroundStyle(Color.white)

                Text("Búðu til 10/20/30 spurninga æfingarpróf út frá veikleikum þínum.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.9))

                HStack(spacing: 6) {
                    Text("Opna prófaundirbúning")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Auth.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.Auth.primaryPressed.opacity(0.8), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var errorBankCard: some View {
        Button {
            showErrorBankSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text("\(viewModel.errorBankDistinctCountText) gerðir")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }
                .foregroundStyle(Color.white)

                Text("Mínar villur")
                    .font(.headline)
                    .foregroundStyle(Color.white)

                Text("Skoðaðu hvað þú klikkar oftast á og hvað hefur batnað.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.9))

                HStack(spacing: 6) {
                    Text("Opna villubanka")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Auth.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.Auth.primaryPressed.opacity(0.8), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

}

private struct AllProblemsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let problems: [ProblemSummary]
    let folders: [FolderSummary]
    @Binding var selectedFolderId: String?
    let onMove: (ProblemSummary, String) async -> Void
    let onDelete: (ProblemSummary) async -> Bool
    let onSelect: (ProblemSummary) -> Void

    @State private var pendingProblemDeletion: ProblemSummary?
    @State private var selectedRootFolderId: String?
    @State private var selectedSubfolderId: String?

    private var filteredProblems: [ProblemSummary] {
        guard let selectedRootFolderId else {
            return problems
        }

        if let selectedSubfolderId {
            return problems.filter { $0.folder_id == selectedSubfolderId }
        }

        let childIds = Set(childFolders(parentFolderId: selectedRootFolderId).map(\.id))
        return problems.filter { problem in
            guard let folderId = problem.folder_id else { return false }
            return folderId == selectedRootFolderId || childIds.contains(folderId)
        }
    }

    private func count(for folderId: String?) -> Int {
        guard let folderId else { return problems.count }
        return problems.filter { $0.folder_id == folderId }.count
    }

    private var rootFolders: [FolderSummary] {
        folders
            .filter { $0.parent_folder_id == nil }
            .sorted { folderSort(lhs: $0, rhs: $1) }
    }

    private func childFolders(parentFolderId: String) -> [FolderSummary] {
        folders
            .filter { $0.parent_folder_id == parentFolderId }
            .sorted { folderSort(lhs: $0, rhs: $1) }
    }

    private func folderSort(lhs: FolderSummary, rhs: FolderSummary) -> Bool {
        if lhs.name == "Unsorted" { return true }
        if rhs.name == "Unsorted" { return false }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func localizedFolderName(_ value: String) -> String {
        value == "Unsorted" ? "Óflokkað" : value
    }

    private func rootFolderCount(_ rootFolder: FolderSummary) -> Int {
        let childIds = Set(childFolders(parentFolderId: rootFolder.id).map(\.id))
        return problems.filter { problem in
            guard let folderId = problem.folder_id else { return false }
            return folderId == rootFolder.id || childIds.contains(folderId)
        }.count
    }

    private func folderPathTitle(_ folder: FolderSummary) -> String {
        guard let parentId = folder.parent_folder_id,
              let parentFolder = folders.first(where: { $0.id == parentId }) else {
            return localizedFolderName(folder.name)
        }
        return "\(localizedFolderName(parentFolder.name)) / \(localizedFolderName(folder.name))"
    }

    private var selectedRootFolder: FolderSummary? {
        guard let selectedRootFolderId else { return nil }
        return folders.first(where: { $0.id == selectedRootFolderId })
    }

    private var effectiveSelectedFolderId: String? {
        selectedSubfolderId ?? selectedRootFolderId
    }

    var body: some View {
        ZStack {
            AppTheme.Auth.background
                .ignoresSafeArea()

            if problems.isEmpty {
                ContentUnavailableView(
                    "Engin dæmi enn",
                    systemImage: "square.and.pencil",
                    description: Text("Búðu til dæmi til að byrja.")
                )
            } else {
                if horizontalSizeClass == .regular {
                    GeometryReader { geometry in
                        HStack(alignment: .top, spacing: 12) {
                            folderTreePanel
                                .frame(minWidth: 280, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
                            problemsPanel
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(16)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            folderTreePanel
                            problemsPanel
                        }
                        .padding(16)
                    }
                }
            }
        }
        .navigationTitle("Öll dæmi")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.Auth.primary)
        .alert("Eyða dæmi?", isPresented: Binding(
            get: { pendingProblemDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingProblemDeletion = nil
                }
            }
        )) {
            Button("Hætta við", role: .cancel) {
                pendingProblemDeletion = nil
            }
            Button("Eyða", role: .destructive) {
                guard let problem = pendingProblemDeletion else { return }
                Task {
                    let success = await onDelete(problem)
                    if success {
                        pendingProblemDeletion = nil
                    }
                }
            }
        } message: {
            if let problem = pendingProblemDeletion {
                Text("Dæminu „\(problem.title)” verður eytt varanlega.")
            } else {
                Text("")
            }
        }
        .onAppear {
            synchronizeSelectionFromBinding()
        }
        .onChange(of: selectedFolderId) { _, _ in
            synchronizeSelectionFromBinding()
        }
        .onChange(of: folders) { _, _ in
            synchronizeSelectionFromBinding()
        }
        .onChange(of: selectedRootFolderId) { _, _ in
            pushSelectionToBinding()
        }
        .onChange(of: selectedSubfolderId) { _, _ in
            pushSelectionToBinding()
        }
    }

    private var folderTreePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Möppur")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            if horizontalSizeClass == .regular {
                ScrollView(.vertical, showsIndicators: true) {
                    folderTreeContent
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                folderTreeContent
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private var folderTreeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            folderTreeRow(
                title: "Allt",
                count: count(for: nil),
                isSelected: selectedRootFolderId == nil,
                level: 0,
                systemImage: "tray.full"
            ) {
                selectedRootFolderId = nil
                selectedSubfolderId = nil
            }

            ForEach(rootFolders) { folder in
                folderTreeRow(
                    title: localizedFolderName(folder.name),
                    count: rootFolderCount(folder),
                    isSelected: selectedRootFolderId == folder.id,
                    level: 0,
                    systemImage: "folder"
                ) {
                    selectedRootFolderId = folder.id
                    selectedSubfolderId = nil
                }

                if selectedRootFolderId == folder.id {
                    let children = childFolders(parentFolderId: folder.id)
                    if !children.isEmpty {
                        folderTreeRow(
                            title: "Allt í \(localizedFolderName(folder.name))",
                            count: rootFolderCount(folder),
                            isSelected: selectedSubfolderId == nil,
                            level: 1,
                            systemImage: "tray.full"
                        ) {
                            selectedSubfolderId = nil
                        }

                        ForEach(children) { child in
                            folderTreeRow(
                                title: localizedFolderName(child.name),
                                count: count(for: child.id),
                                isSelected: selectedSubfolderId == child.id,
                                level: 1,
                                systemImage: "folder.badge.plus"
                            ) {
                                selectedSubfolderId = child.id
                            }
                        }
                    }
                }
            }
        }
    }

    private var problemsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dæmi")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer()
                Text("\(filteredProblems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }

            folderBreadcrumb

            if horizontalSizeClass == .regular {
                ScrollView(.vertical, showsIndicators: true) {
                    problemsPanelListContent
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                problemsPanelListContent
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var problemsPanelListContent: some View {
        if filteredProblems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Engin dæmi í þessari möppu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Text("Veldu aðra möppu eða búðu til nýtt dæmi.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.Auth.border, lineWidth: 1)
            )
        } else {
            ForEach(filteredProblems) { problem in
                problemRow(problem)
            }
        }
    }

    private func problemRow(_ problem: ProblemSummary) -> some View {
        Button {
            onSelect(problem)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(problem.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Auth.textPrimary)
                    Text(formatIcelandicDateOnly(problem.created_at))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                    if let folderName = problem.folder_name {
                        Text(localizedFolderName(folderName))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    if !folders.isEmpty {
                        ForEach(folders) { folder in
                            Button(folderPathTitle(folder)) {
                                Task { await onMove(problem, folder.id) }
                            }
                        }
                        Divider()
                    }
                    Button("Eyða dæmi", role: .destructive) {
                        pendingProblemDeletion = problem
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private func folderTreeRow(
        title: String,
        count: Int,
        isSelected: Bool,
        level: Int,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)

                Spacer(minLength: 8)

                folderCountBadge(count, isSelected: isSelected)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
            .padding(.leading, CGFloat(level) * 18)
        }
        .buttonStyle(.plain)
    }

    private func folderCountBadge(_ count: Int, isSelected: Bool) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isSelected ? Color.white.opacity(0.2) : Color.black.opacity(0.08))
            .clipShape(Capsule())
            .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)
    }

    private var folderBreadcrumb: some View {
        HStack(spacing: 6) {
            Image(systemName: "location")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.Auth.textSecondary)

            Button("Allt") {
                selectedRootFolderId = nil
                selectedSubfolderId = nil
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selectedRootFolderId == nil ? AppTheme.Auth.primary : AppTheme.Auth.textSecondary)

            if let selectedRootFolder {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                Button(localizedFolderName(selectedRootFolder.name)) {
                    selectedRootFolderId = selectedRootFolder.id
                    selectedSubfolderId = nil
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedSubfolderId == nil ? AppTheme.Auth.primary : AppTheme.Auth.textSecondary)
            }

            if let selectedSubfolderId,
               let selectedSubfolder = folders.first(where: { $0.id == selectedSubfolderId }) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                Text(localizedFolderName(selectedSubfolder.name))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private func synchronizeSelectionFromBinding() {
        guard let selectedFolderId else {
            selectedRootFolderId = nil
            selectedSubfolderId = nil
            return
        }

        guard let selectedFolder = folders.first(where: { $0.id == selectedFolderId }) else {
            selectedRootFolderId = nil
            selectedSubfolderId = nil
            return
        }

        if let parentId = selectedFolder.parent_folder_id {
            selectedRootFolderId = parentId
            selectedSubfolderId = selectedFolder.id
        } else {
            selectedRootFolderId = selectedFolder.id
            selectedSubfolderId = nil
        }
    }

    private func pushSelectionToBinding() {
        let next = effectiveSelectedFolderId
        if selectedFolderId != next {
            selectedFolderId = next
        }
    }
}

private struct ProfileSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("profile.avatar.id") private var selectedAvatarID: String = ProfileAvatarOption.defaultID
    @AppStorage(PipelineMode.appStorageKey) private var selectedPipelineModeRawValue: String = PipelineMode.singlePass.rawValue
    @State private var fullName: String = ""
    @State private var initialFullName: String = ""
    @State private var isSaving: Bool = false
    @State private var isEditingName: Bool = false
    @State private var errorMessage: String?
    @State private var loadedInitialState = false
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Auth.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        avatarSection
                        identitySection
                        pipelineModeSection

                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AppTheme.Auth.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                                )
                        }

                        if isSaving {
                            ProgressView("Vista prófíl...")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AppTheme.Auth.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Prófíll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Loka") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skrá út") {
                        Task {
                            await authManager.logout()
                            dismiss()
                        }
                    }
                }
            }
        }
        .task {
            guard !loadedInitialState else { return }
            fullName = authManager.currentUser?.full_name ?? ""
            initialFullName = fullName
            loadedInitialState = true
        }
        .onDisappear {
            Task { await saveProfileIfNeeded() }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            AvatarImageView(resourceName: selectedAvatarResourceName)
                .frame(width: 168, height: 168)

            Text("Veldu táknmynd")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)

            ProfileAvatarPicker(
                selectedAvatarID: $selectedAvatarID,
                columns: 3,
                iconSize: 62,
                iconPadding: 0,
                labelSize: 14
            )
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aðgangsupplýsingar")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Nafn")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)

                HStack(spacing: 8) {
                    if isEditingName {
                        TextField("Sláðu inn fullt nafn", text: $fullName)
                            .textInputAutocapitalization(.words)
                            .focused($isNameFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isEditingName = false
                                Task { await saveProfileIfNeeded() }
                            }
                    } else {
                        Text(displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Auth.textPrimary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        if isEditingName {
                            isEditingName = false
                            isNameFieldFocused = false
                            Task { await saveProfileIfNeeded() }
                        } else {
                            isEditingName = true
                            isNameFieldFocused = true
                        }
                    } label: {
                        Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.Auth.primary)
                    }
                    .accessibilityLabel(isEditingName ? "Ljúka nafnbreytingu" : "Breyta nafni")
                }
                .padding(12)
                .background(AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Netfang")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)

                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(AppTheme.Auth.primary)
                    Text(authManager.currentUser?.email ?? "Óskráð netfang")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Auth.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pipelineModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Svörunarhamur")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            HStack(spacing: 8) {
                ForEach(PipelineMode.allCases) { mode in
                    let isSelected = selectedPipelineMode == mode
                    Button {
                        selectedPipelineModeRawValue = mode.rawValue
                    } label: {
                        Text(mode.displayName)
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
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }

            Text(selectedPipelineMode.explanation)
                .font(.footnote)
                .foregroundStyle(AppTheme.Auth.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.Auth.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var displayName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Óskráð nafn" : trimmed
    }

    private var hasNameChanges: Bool {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            != initialFullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedAvatarResourceName: String {
        resolvedProfileAvatarOption(from: selectedAvatarID).resourceName
    }

    private var selectedPipelineMode: PipelineMode {
        PipelineMode(rawValue: selectedPipelineModeRawValue) ?? .singlePass
    }

    private func saveProfileIfNeeded() async {
        guard hasNameChanges, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await authManager.updateProfile(fullName: fullName)
            initialFullName = fullName
            isEditingName = false
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Gat ekki vistað prófíl."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileAvatarPicker: View {
    @Binding var selectedAvatarID: String
    var columns: Int = 3
    var iconSize: CGFloat = 26
    var iconPadding: CGFloat = 8
    var labelSize: CGFloat = 12

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: max(1, columns))
    }

    private var normalizedSelectionID: String {
        resolvedProfileAvatarOption(from: selectedAvatarID).id
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(ProfileAvatarOption.all) { option in
                let selected = isSelected(option)
                Button {
                    selectedAvatarID = option.id
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            AvatarImageView(resourceName: option.resourceName)
                                .frame(width: iconSize, height: iconSize)
                                .padding(iconPadding)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(AppTheme.Auth.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: selected ? 2.5 : 1)
                                )
                                .scaleEffect(selected ? 1.14 : 1.0)

                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: max(14, labelSize + 3), weight: .semibold))
                                    .foregroundStyle(AppTheme.Auth.primary)
                                    .background(
                                        Circle()
                                            .fill(AppTheme.Auth.surface)
                                    )
                                    .offset(x: 6, y: -6)
                            }
                        }
                        Text(option.label)
                            .font(.system(size: labelSize, weight: .semibold))
                            .foregroundStyle(selected ? AppTheme.Auth.textPrimary : AppTheme.Auth.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? AppTheme.Auth.primary.opacity(0.14) : AppTheme.Auth.surfaceMuted.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: selected ? 2 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func isSelected(_ option: ProfileAvatarOption) -> Bool {
        normalizedSelectionID == option.id
    }
}

struct ProfileAvatarOption: Identifiable {
    let id: String
    let resourceName: String
    let label: String

    static let defaultID = "odin"

    static let all: [ProfileAvatarOption] = [
        .init(id: "odin", resourceName: "profile_avatars/avatar_odin", label: "Óðinn"),
        .init(id: "thor", resourceName: "profile_avatars/avatar_thor", label: "Þór"),
        .init(id: "loki", resourceName: "profile_avatars/avatar_loki", label: "Loki"),
        .init(id: "freya", resourceName: "profile_avatars/avatar_freya", label: "Freyja"),
        .init(id: "garmur", resourceName: "profile_avatars/avatar_garmur", label: "Garmur"),
        .init(id: "idun", resourceName: "profile_avatars/avatar_idun", label: "Iðunn"),
    ]
}

func resolvedProfileAvatarOption(from storedValue: String) -> ProfileAvatarOption {
    let normalized = storedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ProfileAvatarOption.all.first(where: { $0.id == normalized }) ?? ProfileAvatarOption.all[0]
}

private struct SubmissionExportSheet: View {
    let problems: [ProblemSummary]
    let folders: [FolderSummary]
    let exportAction: ([ProblemSummary], String, String) async throws -> SubmissionExportResult

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var submissionTitle: String = ""
    @State private var selectedProblemIds: Set<String> = []
    @State private var isExporting: Bool = false
    @State private var loadedDefaults = false
    @State private var errorMessage: String?
    @State private var exportResult: SubmissionExportResult?
    @State private var showPreviewSheet: Bool = false
    @State private var selectedRootFolderId: String?
    @State private var selectedSubfolderId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Auth.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Skilaupplýsingar")
                                .font(.headline)
                                .foregroundStyle(AppTheme.Auth.textPrimary)

                            TextField("Titill á skilum", text: $submissionTitle)
                                .padding(12)
                                .background(AppTheme.Auth.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                                )

                            infoRow(
                                title: "Nafn nemanda",
                                value: authManager.currentUser?.full_name ?? "Vantar nafn í prófíl",
                                systemImage: "person.fill"
                            )
                            infoRow(
                                title: "Valin dæmi",
                                value: "\(selectedProblemIds.count)",
                                systemImage: "checkmark.circle.fill"
                            )
                        }
                        .padding(14)
                        .background(AppTheme.Auth.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Veldu dæmi")
                                .font(.headline)
                                .foregroundStyle(AppTheme.Auth.textPrimary)

                            if horizontalSizeClass == .regular {
                                HStack(alignment: .top, spacing: 10) {
                                    folderTreePanel
                                        .frame(minWidth: 260, maxWidth: 300, alignment: .topLeading)
                                    problemSelectionPanel
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            } else {
                                folderTreePanel
                                problemSelectionPanel
                            }
                        }
                        .padding(14)
                        .background(AppTheme.Auth.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(spacing: 10) {
                            Button {
                                Task { await generatePDF() }
                            } label: {
                                if isExporting {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Bý til skilaskjal...")
                                    }
                                } else {
                                    Text("Búa til skil")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(isExporting || selectedProblemIds.isEmpty)

                            if let exportResult {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Tilbúið skjal")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.Auth.textPrimary)

                                    Text("Flutt út: \(exportResult.exportedCount) dæmi.")
                                        .foregroundStyle(.secondary)

                                    if !exportResult.skippedProblems.isEmpty {
                                        Text("Sleppt: \(exportResult.skippedProblems.joined(separator: ", "))")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    Button("Forskoða skjal") {
                                        showPreviewSheet = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AppTheme.Auth.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .padding(14)
                        .background(AppTheme.Auth.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AppTheme.Auth.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                                )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Búa til skil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Loka") { dismiss() }
                }
            }
        }
        .task {
            guard !loadedDefaults else { return }
            selectedProblemIds = []
            submissionTitle = defaultSubmissionTitle()
            loadedDefaults = true
        }
        .sheet(isPresented: $showPreviewSheet) {
            if let fileURL = exportResult?.fileURL {
                PDFPreviewSheet(fileURL: fileURL)
            }
        }
    }

    private var folderTreePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Möppur")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            if horizontalSizeClass == .regular {
                ScrollView(.vertical, showsIndicators: true) {
                    folderTreeContent
                }
                .frame(maxHeight: 460)
            } else {
                folderTreeContent
            }
        }
        .padding(10)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var folderTreeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            folderTreeRow(
                title: "Allt",
                count: problems.count,
                isSelected: selectedRootFolderId == nil,
                level: 0,
                systemImage: "tray.full"
            ) {
                selectedRootFolderId = nil
                selectedSubfolderId = nil
            }

            ForEach(rootFolders) { folder in
                folderTreeRow(
                    title: localizedFolderName(folder.name),
                    count: rootFolderCount(folder),
                    isSelected: selectedRootFolderId == folder.id,
                    level: 0,
                    systemImage: "folder"
                ) {
                    selectedRootFolderId = folder.id
                    selectedSubfolderId = nil
                }

                if selectedRootFolderId == folder.id {
                    let childItems = childFolders(parentFolderId: folder.id)
                    if !childItems.isEmpty {
                        folderTreeRow(
                            title: "Allt í \(localizedFolderName(folder.name))",
                            count: rootFolderCount(folder),
                            isSelected: selectedSubfolderId == nil,
                            level: 1,
                            systemImage: "tray.full"
                        ) {
                            selectedSubfolderId = nil
                        }

                        ForEach(childItems) { child in
                            folderTreeRow(
                                title: localizedFolderName(child.name),
                                count: problemCount(for: child.id),
                                isSelected: selectedSubfolderId == child.id,
                                level: 1,
                                systemImage: "folder.badge.plus"
                            ) {
                                selectedSubfolderId = (selectedSubfolderId == child.id) ? nil : child.id
                            }
                        }
                    }
                }
            }
        }
    }

    private var problemSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            folderBreadcrumb

            if horizontalSizeClass == .regular {
                ScrollView(.vertical, showsIndicators: true) {
                    problemSelectionListContent
                }
                .frame(maxHeight: 460)
            } else {
                problemSelectionListContent
            }
        }
    }

    @ViewBuilder
    private var problemSelectionListContent: some View {
        if filteredProblems.isEmpty {
            Text("Engin dæmi tiltæk.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            ForEach(filteredProblems) { problem in
                Button {
                    toggleProblemSelection(problem.id)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.title)
                                .foregroundStyle(AppTheme.Auth.textPrimary)
                            Text(formatIcelandicDateOnly(problem.created_at))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedProblemIds.contains(problem.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedProblemIds.contains(problem.id) ? AppTheme.Auth.primary : .secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Auth.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.Auth.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredProblems: [ProblemSummary] {
        guard let selectedRootFolderId else {
            return problems
        }
        if let selectedSubfolderId {
            return problems.filter { $0.folder_id == selectedSubfolderId }
        }
        let childIds = Set(childFolders(parentFolderId: selectedRootFolderId).map(\.id))
        return problems.filter { problem in
            guard let folderId = problem.folder_id else { return false }
            return folderId == selectedRootFolderId || childIds.contains(folderId)
        }
    }

    private var rootFolders: [FolderSummary] {
        folders
            .filter { $0.parent_folder_id == nil }
            .sorted { folderSort(lhs: $0, rhs: $1) }
    }

    private func childFolders(parentFolderId: String) -> [FolderSummary] {
        folders
            .filter { $0.parent_folder_id == parentFolderId }
            .sorted { folderSort(lhs: $0, rhs: $1) }
    }

    private func folderSort(lhs: FolderSummary, rhs: FolderSummary) -> Bool {
        if lhs.name == "Unsorted" { return true }
        if rhs.name == "Unsorted" { return false }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func localizedFolderName(_ value: String) -> String {
        value == "Unsorted" ? "Óflokkað" : value
    }

    private func problemCount(for folderId: String?) -> Int {
        guard let folderId else { return problems.count }
        return problems.filter { $0.folder_id == folderId }.count
    }

    private func rootFolderCount(_ rootFolder: FolderSummary) -> Int {
        let childIds = Set(childFolders(parentFolderId: rootFolder.id).map(\.id))
        return problems.filter { problem in
            guard let folderId = problem.folder_id else { return false }
            return folderId == rootFolder.id || childIds.contains(folderId)
        }.count
    }

    private var selectedRootFolder: FolderSummary? {
        guard let selectedRootFolderId else { return nil }
        return folders.first(where: { $0.id == selectedRootFolderId })
    }

    private func folderTreeRow(
        title: String,
        count: Int,
        isSelected: Bool,
        level: Int,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textSecondary)

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.black.opacity(0.08))
                    .clipShape(Capsule())
                    .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)

                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.white : AppTheme.Auth.textPrimary)
            .background(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AppTheme.Auth.primary : AppTheme.Auth.border, lineWidth: 1)
            )
            .padding(.leading, CGFloat(level) * 18)
        }
        .buttonStyle(.plain)
    }

    private var folderBreadcrumb: some View {
        HStack(spacing: 6) {
            Image(systemName: "location")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.Auth.textSecondary)

            Button("Allt") {
                selectedRootFolderId = nil
                selectedSubfolderId = nil
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selectedRootFolderId == nil ? AppTheme.Auth.primary : AppTheme.Auth.textSecondary)

            if let selectedRootFolder {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                Button(localizedFolderName(selectedRootFolder.name)) {
                    selectedRootFolderId = selectedRootFolder.id
                    selectedSubfolderId = nil
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedSubfolderId == nil ? AppTheme.Auth.primary : AppTheme.Auth.textSecondary)
            }

            if let selectedSubfolderId,
               let selectedSubfolder = folders.first(where: { $0.id == selectedSubfolderId }) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                Text(localizedFolderName(selectedSubfolder.name))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func infoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.Auth.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                Text(value)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private func toggleProblemSelection(_ problemId: String) {
        if selectedProblemIds.contains(problemId) {
            selectedProblemIds.remove(problemId)
        } else {
            selectedProblemIds.insert(problemId)
        }
    }

    private func generatePDF() async {
        isExporting = true
        errorMessage = nil
        exportResult = nil
        defer { isExporting = false }

        let selectedProblems = problems.filter { selectedProblemIds.contains($0.id) }
        let studentName = authManager.currentUser?.full_name ?? ""

        do {
            exportResult = try await exportAction(selectedProblems, submissionTitle, studentName)
            showPreviewSheet = exportResult != nil
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Gat ekki búið til PDF skjal."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultSubmissionTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Heimadæmi \(formatter.string(from: Date()))"
    }
}


private struct PDFPreviewSheet: View {
    let fileURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            PDFDocumentView(fileURL: fileURL)
                .background(AppTheme.Auth.background)
                .navigationTitle("Forskoðun PDF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Loka") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Deila") { showShareSheet = true }
                    }
                }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(items: [fileURL])
        }
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let fileURL: URL

    func makeUIView(context _: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = UIColor(AppTheme.Auth.background)
        pdfView.document = PDFDocument(url: fileURL)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context _: Context) {
        if uiView.document?.documentURL != fileURL {
            uiView.document = PDFDocument(url: fileURL)
        }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

private struct ErrorBankSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var summary: ErrorEventTypeSummaryResponse?
    @State private var selectedRootFolderId: String?
    @State private var selectedSubfolderId: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    let folders: [FolderSummary]
    let initialSummary: ErrorEventTypeSummaryResponse?
    let initialSelectedFolderId: String?

    init(
        folders: [FolderSummary],
        initialSummary: ErrorEventTypeSummaryResponse?,
        initialSelectedFolderId: String?
    ) {
        self.folders = folders
        self.initialSummary = initialSummary
        self.initialSelectedFolderId = initialSelectedFolderId
        _summary = State(initialValue: initialSummary)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Auth.background
                    .ignoresSafeArea()

                if isLoading && summary == nil {
                    ProgressView("Sæki villubanka...")
                        .tint(AppTheme.Auth.primary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            summaryHeader
                            folderFilterCard

                            errorMessageCard

                            if let summary, !summary.entries.isEmpty {
                                ForEach(summary.entries, id: \.self) { entry in
                                    NavigationLink {
                                        ErrorEventTypeDetailView(
                                            errorType: entry.error_type,
                                            folderId: effectiveSelectedFolderId,
                                            folderName: selectedFolderName,
                                            titlePrefix: selectedFolderName ?? "Allar möppur",
                                            folders: folders,
                                            selectedRootFolderId: selectedRootFolderId,
                                            selectedSubfolderId: selectedSubfolderId
                                        )
                                        .environmentObject(authManager)
                                    } label: {
                                        errorRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Text("Engar skráðar villur enn. Haltu áfram að leysa dæmi og villubankinn byggist upp.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppTheme.Auth.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Mínar villur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Loka") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Endurhlaða") {
                        Task { await loadErrorTypes() }
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            synchronizeFolderSelectionFromInitialValue()
            await loadErrorTypes()
        }
        .onChange(of: effectiveSelectedFolderId) { _, _ in
            Task { await loadErrorTypes() }
        }
        .tint(AppTheme.Auth.primary)
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Yfirlit")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)
            HStack(spacing: 10) {
                metricPill(title: "Heildarvillur", value: "\(summary?.total_occurrences ?? 0)")
                metricPill(title: "Mismunandi gerðir", value: "\(summary?.total_distinct_error_types ?? 0)")
            }
        }
    }

    private var folderFilterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sía eftir möppu")
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            Menu {
                Button("Allar möppur") {
                    selectedRootFolderId = nil
                    selectedSubfolderId = nil
                }

                if !rootFolders.isEmpty {
                    Divider()
                }

                ForEach(rootFolders) { folder in
                    Button(localizedFolderName(folder.name)) {
                        selectedRootFolderId = folder.id
                        selectedSubfolderId = nil
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.subheadline.weight(.semibold))
                    Text(selectedRootFolderName ?? "Allar möppur")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.Auth.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                )
            }

            if let selectedRootFolder, !childFolders(parentFolderId: selectedRootFolder.id).isEmpty {
                Menu {
                    Button("Allt í \(localizedFolderName(selectedRootFolder.name))") {
                        selectedSubfolderId = nil
                    }

                    Divider()

                    ForEach(childFolders(parentFolderId: selectedRootFolder.id)) { folder in
                        Button(localizedFolderName(folder.name)) {
                            selectedSubfolderId = folder.id
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.subheadline.weight(.semibold))
                        Text(selectedSubfolderName ?? "Allt í \(localizedFolderName(selectedRootFolder.name))")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Auth.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.Auth.border, lineWidth: 1)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var errorMessageCard: some View {
        if let errorMessage, !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Auth.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.Auth.textPrimary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
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

    @ViewBuilder
    private func errorRow(entry: ErrorEventTypeCount) -> some View {
        HStack(spacing: 12) {
            HStack(alignment: .top) {
                Text(prettyErrorTypeName(entry.error_type))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer()
            }

            Text("x\(entry.count)")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.Auth.primary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)
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

    private var rootFolders: [FolderSummary] {
        folders
            .filter { $0.parent_folder_id == nil }
            .sorted { localizedFolderName($0.name) < localizedFolderName($1.name) }
    }

    private var selectedFolderName: String? {
        if let selectedSubfolderName {
            return selectedSubfolderName
        }
        guard let selectedRootFolder else { return nil }
        return localizedFolderName(selectedRootFolder.name)
    }

    private var selectedRootFolderName: String? {
        guard let selectedRootFolder else { return nil }
        return localizedFolderName(selectedRootFolder.name)
    }

    private var selectedRootFolder: FolderSummary? {
        guard let selectedRootFolderId else { return nil }
        return folders.first(where: { $0.id == selectedRootFolderId })
    }

    private var selectedSubfolderName: String? {
        guard let selectedSubfolderId,
              let folder = folders.first(where: { $0.id == selectedSubfolderId }) else { return nil }
        return localizedFolderName(folder.name)
    }

    private var effectiveSelectedFolderId: String? {
        selectedSubfolderId ?? selectedRootFolderId
    }

    private func childFolders(parentFolderId: String) -> [FolderSummary] {
        folders
            .filter { $0.parent_folder_id == parentFolderId }
            .sorted { localizedFolderName($0.name) < localizedFolderName($1.name) }
    }

    private func folderPathTitle(_ folder: FolderSummary) -> String {
        if let parentId = folder.parent_folder_id,
           let parent = folders.first(where: { $0.id == parentId }) {
            return "\(localizedFolderName(parent.name)) / \(localizedFolderName(folder.name))"
        }
        return localizedFolderName(folder.name)
    }

    private func localizedFolderName(_ value: String) -> String {
        value.caseInsensitiveCompare("default") == .orderedSame ? "Óflokkað" : value
    }

    private func loadErrorTypes() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            summary = try await authManager.getErrorEventTypeSummary(folderId: effectiveSelectedFolderId)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Gat ekki sótt villubanka."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func synchronizeFolderSelectionFromInitialValue() {
        guard let initialSelectedFolderId else {
            selectedRootFolderId = nil
            selectedSubfolderId = nil
            return
        }

        guard let selectedFolder = folders.first(where: { $0.id == initialSelectedFolderId }) else {
            selectedRootFolderId = nil
            selectedSubfolderId = nil
            return
        }

        if let parentId = selectedFolder.parent_folder_id {
            selectedRootFolderId = parentId
            selectedSubfolderId = selectedFolder.id
        } else {
            selectedRootFolderId = selectedFolder.id
            selectedSubfolderId = nil
        }
    }

}

private struct ErrorEventTypeDetailView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var items: [ErrorEventRecord] = []
    @State private var nextCursor: String?
    @State private var selectedAttemptBrowser: ErrorEventAttemptBrowserContext?
    @State private var loadingAttemptId: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    let errorType: String
    let folderId: String?
    let folderName: String?
    let titlePrefix: String
    let folders: [FolderSummary]
    let selectedRootFolderId: String?
    let selectedSubfolderId: String?

    var body: some View {
        ZStack {
            AppTheme.Auth.background
                .ignoresSafeArea()

            if isLoading && items.isEmpty {
                ProgressView("Sæki villur...")
                    .tint(AppTheme.Auth.primary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        headerCard

                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.Auth.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if items.isEmpty {
                            Text("Engar villur fundust fyrir þessa síu.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.Auth.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            ForEach(items) { item in
                                errorEventCard(item)
                            }

                            if nextCursor != nil {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if isLoadingMore {
                                            ProgressView()
                                                .tint(AppTheme.Auth.primary)
                                        } else {
                                            Text("Sækja fleiri")
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(AppTheme.Auth.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(AppTheme.Auth.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoadingMore)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(prettyErrorTypeName(errorType))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedAttemptBrowser) { context in
            ErrorEventAttemptBrowserView(
                entries: context.entries,
                initialEntryID: context.initialEntryID,
                title: "\(titlePrefix) - \(prettyErrorTypeName(errorType))"
            )
            .environmentObject(authManager)
        }
        .task {
            await reload()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prettyErrorTypeName(errorType))
                .font(.headline)
                .foregroundStyle(AppTheme.Auth.textPrimary)
            Text(folderName ?? "Allar möppur")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Auth.textSecondary)
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

    @ViewBuilder
    private func errorEventCard(_ item: ErrorEventRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let problemTitle = item.problem_title, !problemTitle.isEmpty {
                        Text(problemTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Auth.textPrimary)
                    }

                    let topicLine = [item.topic, item.subtopic]
                        .compactMap { value in
                            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                return nil
                            }
                            return value
                        }
                        .joined(separator: " · ")

                    if !topicLine.isEmpty {
                        Text(topicLine)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Auth.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatIcelandicDateOnly(item.created_at))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                    if let confidence = item.confidence {
                        Text("Öryggi \(formattedConfidence(confidence))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let wrongStep = item.wrong_step, !wrongStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rangt skref")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                    MathTextView(text: wrongStep)
                }
            }

            if let correctStep = item.correct_step, !correctStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rétt skref")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                    MathTextView(text: correctStep)
                }
            }

            Button {
                Task { await openAttempt(for: item) }
            } label: {
                HStack(spacing: 8) {
                    if loadingAttemptId == item.id {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Sjá dæmi")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AppTheme.Auth.logo)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(loadingAttemptId == item.id)
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

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await loadFilteredErrorEventPage(cursor: nil)
            items = result.items
            nextCursor = result.nextCursor
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Gat ekki sótt villur."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, let nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await loadFilteredErrorEventPage(cursor: nextCursor)
            items.append(contentsOf: result.items)
            self.nextCursor = result.nextCursor
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Gat ekki sótt fleiri villur."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedConfidence(_ value: Double) -> String {
        if value > 1 {
            return String(format: "%.0f%%", value.rounded())
        }
        return String(format: "%.0f%%", (value * 100).rounded())
    }

    private func openAttempt(for item: ErrorEventRecord) async {
        guard loadingAttemptId == nil else { return }
        loadingAttemptId = item.id
        defer { loadingAttemptId = nil }
        selectedAttemptBrowser = ErrorEventAttemptBrowserContext(
            entries: items,
            initialEntryID: item.id
        )
    }

    private var subtreeFolderIDs: Set<String>? {
        guard let selectedRootFolderId, selectedSubfolderId == nil else { return nil }
        let childIDs = folders
            .filter { $0.parent_folder_id == selectedRootFolderId }
            .map(\.id)
        return Set([selectedRootFolderId] + childIDs)
    }

    private var backendFolderId: String? {
        subtreeFolderIDs == nil ? folderId : nil
    }

    private func loadFilteredErrorEventPage(cursor: String?) async throws -> (items: [ErrorEventRecord], nextCursor: String?) {
        var currentCursor = cursor
        var filteredItems: [ErrorEventRecord] = []

        while filteredItems.isEmpty {
            let page = try await authManager.getErrorEvents(
                errorType: errorType,
                folderId: backendFolderId,
                cursor: currentCursor
            )

            filteredItems = filterItemsForSelectedFolder(page.items)
            currentCursor = page.next_cursor

            if page.next_cursor == nil || subtreeFolderIDs == nil {
                return (filteredItems, page.next_cursor)
            }
        }

        return (filteredItems, currentCursor)
    }

    private func filterItemsForSelectedFolder(_ source: [ErrorEventRecord]) -> [ErrorEventRecord] {
        guard let subtreeFolderIDs else { return source }
        return source.filter { item in
            guard let folderId = item.folder_id else { return false }
            return subtreeFolderIDs.contains(folderId)
        }
    }
}

private struct ErrorEventAttemptBrowserContext: Identifiable {
    let entries: [ErrorEventRecord]
    let initialEntryID: String

    var id: String { initialEntryID }
}

private struct ErrorEventAttemptBrowserView: View {
    @EnvironmentObject private var authManager: AuthManager

    let entries: [ErrorEventRecord]
    let initialEntryID: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedEntryID: String
    @State private var attemptsByEntryID: [String: ProblemAttempt] = [:]
    @State private var loadingEntryID: String?
    @State private var errorMessage: String?

    init(entries: [ErrorEventRecord], initialEntryID: String, title: String) {
        self.entries = entries
        self.initialEntryID = initialEntryID
        self.title = title
        _selectedEntryID = State(initialValue: initialEntryID)
    }

    var body: some View {
        ZStack {
            AppTheme.Auth.background
                .ignoresSafeArea()

            TabView(selection: $selectedEntryID) {
                ForEach(entries) { entry in
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if let errorMessage, entry.id == selectedEntryID, attemptsByEntryID[entry.id] == nil {
                                    Text(errorMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(AppTheme.Auth.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                if let attempt = attemptsByEntryID[entry.id] {
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
                                            ErrorEventZoomableAttemptImageView(url: url)
                                                .frame(minHeight: 460, maxHeight: max(460, geometry.size.height - 250))
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
                                } else {
                                    ProgressView("Sæki tilraun...")
                                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                                        .padding(14)
                                        .background(AppTheme.Auth.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                            .frame(minHeight: geometry.size.height - 24, alignment: .top)
                            .padding(16)
                            .padding(.bottom, 24)
                        }
                    }
                    .tag(entry.id)
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
        .task {
            await loadAttemptIfNeeded(for: selectedEntryID)
        }
        .onChange(of: selectedEntryID) { _, newValue in
            Task { await loadAttemptIfNeeded(for: newValue) }
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

            Text(title)
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
            ForEach(Array(entries.enumerated()), id: \.element.id) { _, entry in
                let isSelected = entry.id == selectedEntryID

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

    private func loadAttemptIfNeeded(for entryID: String) async {
        guard attemptsByEntryID[entryID] == nil, loadingEntryID != entryID else { return }
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }

        loadingEntryID = entryID
        defer { loadingEntryID = nil }

        do {
            let attempts = try await authManager.listAttempts(problemId: entry.problem_id)
            guard let attempt = attempts.first(where: { $0.id == entry.attempt_id }) else {
                errorMessage = "Gat ekki fundið tilraunina fyrir þessa villu."
                return
            }
            attemptsByEntryID[entryID] = attempt
            if selectedEntryID == entryID {
                errorMessage = nil
            }
        } catch let error as LocalizedError {
            if selectedEntryID == entryID {
                errorMessage = error.errorDescription ?? "Gat ekki sótt tilraun."
            }
        } catch {
            if selectedEntryID == entryID {
                errorMessage = error.localizedDescription
            }
        }
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

private struct ErrorEventZoomableAttemptImageView: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 460)
            case let .success(image):
                ErrorEventZoomableImageContent(image: image)
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

private struct ErrorEventZoomableImageContent: View {
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

private struct ProblemNavigationRoute: Hashable {
    let problem: ProblemSummary
    let showImageOnboardingOnOpen: Bool
}

private func prettyErrorTypeName(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    if let target = ExamErrorTarget(rawValue: normalized) {
        return target.displayName
    }

    switch normalized {
    case "conceptual_error":
        return "Hugtaksvilla"
    case "rule_application_error":
        return "Villa í beitingu reglu eða formúlu"
    case "procedural_error":
        return "Aðferðavilla"
    case "arithmetic_error":
        return "Reikningsvilla"
    case "sign_notation_copying_error":
        return "Formerkja- eða táknvilla / afritunarvilla"
    case "interpretation_error":
        return "Túlkunarvilla"
    case "incomplete_reasoning":
        return "Ófullnægjandi rökstuðningur"
    case "ambiguous_error":
        return "Óljós villa"
    case "conceptual":
        return "Hugtakavilla"
    case "calculation":
        return "Reiknivilla"
    case "logic":
        return "Rökvilla"
    default:
        return normalized
            .replacingOccurrences(of: "_", with: " ")
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
