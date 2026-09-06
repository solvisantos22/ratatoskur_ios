import Foundation
import Observation

@MainActor
@Observable
final class StudentClassroomModel {
    private(set) var classes: [StudentClass] = []
    private(set) var assignments: [StudentAssignment] = []
    private(set) var isLoading = false
    private(set) var isJoining = false
    private(set) var openingItemID: String?
    var errorMessage: String?
    var joinCode = ""
    private(set) var selectedClassID: String?
    var navigationPath: [StudentClassroomRoute] = [] {
        didSet {
            if navigationPath != oldValue { invalidatePendingOpen() }
        }
    }
    private var navigationGeneration = 0

    var selectedClass: StudentClass? {
        classes.first { $0.id == selectedClassID }
    }

    var selectedAssignments: [StudentAssignment] {
        assignments.filter { $0.class_id == selectedClassID }
    }

    var selectedClassName: String {
        selectedClass?.name ?? "Verkefni bekkjarins"
    }

    func selectClass(_ id: String?) {
        selectedClassID = id
        navigationPath = []
        invalidatePendingOpen()
    }

    private func invalidatePendingOpen() {
        navigationGeneration += 1
        openingItemID = nil
        errorMessage = nil
    }

    func load(auth: AuthManager) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loadedClasses = try await auth.listStudentClasses()
            let loadedAssignments = try await auth.listStudentAssignments()
            classes = loadedClasses
            assignments = loadedAssignments
            if selectedClassID != nil && selectedClass == nil {
                selectClass(nil)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func join(auth: AuthManager) async -> Bool {
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, !isJoining else { return false }
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }
        do {
            let classroom = try await auth.joinStudentClass(code: code)
            joinCode = ""
            if !classes.contains(where: { $0.id == classroom.id }) {
                classes.append(classroom)
            }
            selectClass(classroom.id)
            await load(auth: auth)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func open(assignment: StudentAssignment, item: StudentAssignmentItem, auth: AuthManager) async -> StudentAssignmentStartResponse? {
        guard !Task.isCancelled,
              openingItemID == nil,
              selectedClass?.id == assignment.class_id,
              navigationPath.last == .assignment(assignment.id),
              selectedAssignments.contains(where: { current in
                  current.id == assignment.id && current.items.contains(where: { $0.id == item.id })
              }) else { return nil }
        let generation = navigationGeneration
        openingItemID = item.id
        errorMessage = nil
        defer {
            if navigationGeneration == generation { openingItemID = nil }
        }
        do {
            let opened = try await auth.startStudentAssignment(assignmentId: assignment.id, itemId: item.id)
            guard !Task.isCancelled, navigationGeneration == generation else { return nil }
            return opened
        } catch {
            guard !Task.isCancelled, navigationGeneration == generation else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
