import SwiftUI

struct StudentClassroomView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = StudentClassroomModel()
    @State private var showJoin = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var compactColumn: NavigationSplitViewColumn = .detail

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            sidebar
                .navigationTitle("Mínir bekkir")
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Heim", systemImage: "house") { dismiss() }
                    }
                }
                .toolbarBackground(AppTheme.Auth.surface, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
        } detail: {
            NavigationStack(path: $model.navigationPath) {
                classroomPage {
                    if let classroom = model.selectedClass {
                        ClassroomHomeView(classroom: classroom, assignments: model.selectedAssignments) { assignment in
                            model.navigationPath.append(.assignment(assignment.id))
                        }
                    } else {
                        ClassroomOverviewView(classes: model.classes, assignments: model.assignments, isLoading: model.isLoading, onSelect: selectClass) {
                            showJoin = true
                        }
                    }
                }
                .navigationTitle(model.selectedClass?.name ?? "Mínir bekkir")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.selectedClassID != nil {
                            Button("Allir bekkir", systemImage: "square.grid.2x2") { selectClass(nil) }
                        } else {
                            Button("Heim", systemImage: "house") { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Ganga í bekk", systemImage: "person.badge.plus") { showJoin = true }
                            Button("Endurhlaða", systemImage: "arrow.clockwise") { Task { await model.load(auth: authManager) } }
                                .disabled(model.isLoading)
                            Button("Heimaskjár", systemImage: "house") { dismiss() }
                        } label: {
                            Label("Aðgerðir bekkja", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .navigationDestination(for: StudentClassroomRoute.self) { route in
                    switch route {
                    case .assignment(let id):
                        if let assignment = model.selectedAssignments.first(where: { $0.id == id }) {
                            classroomPage {
                                ClassroomAssignmentView(assignment: assignment, openingItemID: model.openingItemID) { item in
                                    Task {
                                        if let opened = await model.open(assignment: assignment, item: item, auth: authManager) {
                                            model.navigationPath.append(.exercise(opened))
                                        }
                                    }
                                }
                            }
                            .navigationTitle("Verkefnasett")
                            .navigationBarTitleDisplayMode(.inline)
                        } else {
                            classroomPage {
                                Text("Verkefnasettið er ekki lengur tiltækt. Farðu til baka í bekkinn.")
                                    .classroomCard()
                            }
                        }
                    case .exercise(let opened):
                        NotebookView(
                            problem: opened.problem,
                            showImageOnboardingOnOpen: false,
                            assignedStart: opened,
                            onShowClassroom: showClassroom,
                            classroomContext: notebookContext(for: opened),
                            backButtonTitle: "Verkefnasett"
                        )
                    }
                }
                .toolbarBackground(AppTheme.Auth.surface, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
            }
        }
        .tint(AppTheme.Auth.primary)
        .foregroundStyle(AppTheme.Auth.textPrimary)
        .task { await model.load(auth: authManager) }
        .onChange(of: model.navigationPath) { oldPath, newPath in
            if case .exercise? = oldPath.last, oldPath.count > newPath.count {
                Task { await model.load(auth: authManager) }
            }
        }
        .sheet(isPresented: $showJoin) { joinSheet }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    SVGLogoView(resourceName: "ratatoskur_logo")
                        .frame(width: 40, height: 40).accessibilityHidden(true)
                    Text("Ratatoskur").font(.title2.bold()).fontDesign(.serif)
                }
                Button { selectClass(nil) } label: {
                    Label("Allir bekkir", systemImage: "square.grid.2x2")
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                ForEach(model.classes) { classroom in
                    Button { selectClass(classroom.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(classroom.name, systemImage: "books.vertical")
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            if let teacher = classroom.teacher_name, !teacher.isEmpty {
                                Text(teacher).font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .foregroundStyle(model.selectedClassID == classroom.id ? Color.white : AppTheme.Auth.textPrimary)
                        .background(model.selectedClassID == classroom.id ? AppTheme.Auth.primary : AppTheme.Auth.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Opna bekk: \(classroom.name)")
                    .accessibilityAddTraits(model.selectedClassID == classroom.id ? .isSelected : [])
                    .hoverEffect(.highlight)
                }
                Button("Ganga í bekk", systemImage: "person.badge.plus") { showJoin = true }
                    .buttonStyle(.bordered).controlSize(.large)
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Text("Veldu bekk til að fara á heimasíðu hans. Skrifuð vinna í dæmum varðveitist þegar þú skiptir um bekk.")
                    .font(.footnote).foregroundStyle(AppTheme.Auth.textSecondary)
            }
            .padding(16)
        }
        .background(AppTheme.Auth.surfaceMuted)
    }

    private func classroomPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = model.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).foregroundStyle(AppTheme.Auth.error)
                        Button("Endurhlaða") { Task { await model.load(auth: authManager) } }
                    }
                    .classroomCard()
                }
                content()
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.Auth.background)
        .refreshable { await model.load(auth: authManager) }
    }

    private var joinSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bekkjarkóði", text: $model.joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit(join)
                } footer: {
                    Text("Sláðu inn kóðann frá kennaranum. Bekkurinn birtist svo undir Mínir bekkir.")
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                }
                .listRowBackground(AppTheme.Auth.surface)
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(AppTheme.Auth.error)
                        .listRowBackground(AppTheme.Auth.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Auth.background)
            .foregroundStyle(AppTheme.Auth.textPrimary)
            .navigationTitle("Ganga í bekk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hætta við") { showJoin = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isJoining ? "Tengist…" : "Ganga í bekk", action: join)
                        .disabled(model.isJoining || model.joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .toolbarBackground(AppTheme.Auth.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .tint(AppTheme.Auth.primary)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.isJoining)
    }

    private func selectClass(_ id: String?) {
        model.selectClass(id)
        compactColumn = .detail
    }

    private func showClassroom() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            columnVisibility = .all
            compactColumn = .sidebar
        }
    }

    private func notebookContext(for opened: StudentAssignmentStartResponse) -> String? {
        guard let classroom = model.selectedClass else { return nil }
        let assignment = model.selectedAssignments.first { $0.id == opened.problem.assignment_id }
        return [classroom.name, assignment?.title].compactMap { $0 }.joined(separator: " › ")
    }

    private func join() {
        Task {
            if await model.join(auth: authManager) {
                showJoin = false
                compactColumn = .detail
            }
        }
    }
}
