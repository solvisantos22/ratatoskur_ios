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
    var selectedClassID: String?

    var selectedAssignments: [StudentAssignment] {
        assignments.filter { $0.class_id == selectedClassID }
    }

    var selectedClassName: String {
        classes.first { $0.id == selectedClassID }?.name ?? "Verkefni bekkjarins"
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
            if !classes.contains(where: { $0.id == selectedClassID }) {
                selectedClassID = classes.first?.id
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
            await load(auth: auth)
            selectedClassID = classroom.id
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func open(assignment: StudentAssignment, item: StudentAssignmentItem, auth: AuthManager) async -> StudentAssignmentStartResponse? {
        guard openingItemID == nil else { return nil }
        openingItemID = item.id
        errorMessage = nil
        defer { openingItemID = nil }
        do {
            return try await auth.startStudentAssignment(assignmentId: assignment.id, itemId: item.id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
