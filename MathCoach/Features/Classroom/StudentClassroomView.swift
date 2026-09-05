import SwiftUI

struct StudentClassroomView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var model = StudentClassroomModel()
    @State private var showJoin = false
    @State private var openedExercise: StudentAssignmentStartResponse?

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedClassID) {
                Section("Bekkir") {
                    ForEach(model.classes) { classroom in
                        NavigationLink(value: classroom.id) {
                            Label(classroom.name, systemImage: "person.3")
                        }
                    }
                }
                Section {
                    Button("Ganga í bekk", systemImage: "person.badge.plus") {
                        showJoin = true
                    }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                }
                Section {
                    Text("Kennarinn sér handskriftina, tilraunirnar og vísbendingarnar sem þú sendir í bekkjarverkefnum. Persónulegar stílabækur eru ekki birtar kennara.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bekkurinn minn")
            .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Loka") { dismiss() }
                }
            }
        } detail: {
            NavigationStack {
                assignmentsList
                    .navigationTitle(model.selectedClassName)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(item: $openedExercise) { opened in
                        NotebookView(problem: opened.problem, showImageOnboardingOnOpen: false, assignedStart: opened)
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Ganga í bekk", systemImage: "person.badge.plus") { showJoin = true }
                        }
                        ToolbarItem(placement: .secondaryAction) {
                            Button("Endurhlaða", systemImage: "arrow.clockwise") {
                                Task { await model.load(auth: authManager) }
                            }
                            .disabled(model.isLoading)
                            .keyboardShortcut("r", modifiers: .command)
                        }
                    }
            }
        }
        .task { await model.load(auth: authManager) }
        .onChange(of: openedExercise) { _, newValue in
            if newValue == nil { Task { await model.load(auth: authManager) } }
        }
        .sheet(isPresented: $showJoin) { joinSheet }
    }

    private var assignmentsList: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Reyna aftur") { Task { await model.load(auth: authManager) } }
                }
            }
            if model.isLoading && model.assignments.isEmpty {
                ProgressView("Sæki verkefni...")
            } else if model.classes.isEmpty {
                ContentUnavailableView("Gakktu í bekk", systemImage: "person.3", description: Text("Fáðu bekkjarkóða hjá kennaranum og veldu Ganga í bekk."))
            } else if model.selectedAssignments.isEmpty {
                ContentUnavailableView("Engin verkefni enn", systemImage: "doc.text", description: Text("Hér birtast verkefni sem kennarinn úthlutar bekknum."))
            }
            ForEach(model.selectedAssignments) { assignment in
                Section(assignment.title) {
                    ForEach(assignment.items.sorted { $0.position < $1.position }) { item in
                        Button {
                            Task {
                                openedExercise = await model.open(assignment: assignment, item: item, auth: authManager)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.image")
                                    .foregroundStyle(AppTheme.Auth.primary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title.isEmpty ? "Dæmi \(item.position + 1)" : item.title)
                                        .foregroundStyle(.primary)
                                    Text(item.problem_id == nil ? "Opna dæmi" : "Halda áfram")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.openingItemID == item.id {
                                    ProgressView().accessibilityLabel("Opna dæmi")
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .disabled(model.openingItemID != nil)
                    }
                }
            }
        }
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
                    Text("Sláðu inn kóðann sem kennarinn gaf þér.")
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Ganga í bekk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hætta við") { showJoin = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isJoining ? "Tengist..." : "Ganga í bekk", action: join)
                        .disabled(model.isJoining || model.joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.isJoining)
    }

    private func join() {
        Task {
            if await model.join(auth: authManager) { showJoin = false }
        }
    }
}
