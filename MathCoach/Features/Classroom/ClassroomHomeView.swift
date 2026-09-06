import SwiftUI

struct ClassroomHomeView: View {
    let classroom: StudentClass
    let assignments: [StudentAssignment]
    let onOpenAssignment: (StudentAssignment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Heim bekkjar", systemImage: "books.vertical")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.primary)
                Text(classroom.name)
                    .font(.largeTitle.bold()).fontDesign(.serif)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                if let teacher = classroom.teacher_name, !teacher.isEmpty {
                    Label("Kennari: \(teacher)", systemImage: "person.crop.circle")
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                }
                Text("Hér eru verkefnasettin sem kennarinn hefur lagt fyrir bekkinn. Veldu sett og síðan dæmi til að vinna í stílabókinni.")
                    .foregroundStyle(AppTheme.Auth.textSecondary)
            }
            .classroomCard()

            Text("Verkefnasett")
                .font(.title2.bold()).fontDesign(.serif)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            if assignments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Engin verkefnasett enn").font(.headline)
                    Text("Verkefnasett birtast hér þegar kennarinn úthlutar þeim.")
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                }
                .classroomCard()
            } else {
                ForEach(assignments) { assignment in
                    Button { onOpenAssignment(assignment) } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "doc.on.doc")
                                .font(.title2).foregroundStyle(AppTheme.Auth.primary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(assignment.title)
                                    .font(.title3.bold()).fontDesign(.serif)
                                    .foregroundStyle(AppTheme.Auth.textPrimary)
                                Text("\(assignment.item_count) dæmi")
                                    .font(.subheadline).foregroundStyle(AppTheme.Auth.textSecondary)
                                Text("Opna verkefnasett")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.Auth.primary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppTheme.Auth.primary).accessibilityHidden(true)
                        }
                        .classroomCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Opna verkefnasett: \(assignment.title), \(assignment.item_count) dæmi")
                    .hoverEffect(.highlight)
                }
            }
        }
    }
}
