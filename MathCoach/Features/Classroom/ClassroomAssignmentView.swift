import SwiftUI

struct ClassroomAssignmentView: View {
    let assignment: StudentAssignment
    let openingItemID: String?
    let onOpen: (StudentAssignmentItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Label(assignment.class_name, systemImage: "books.vertical")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.primary)
                Text(assignment.title)
                    .font(.largeTitle.bold()).fontDesign(.serif)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Text("Veldu dæmi til að opna stílabókina þína. Þú getur farið til baka og haldið áfram síðar.")
                    .foregroundStyle(AppTheme.Auth.textSecondary)
                if assignment.allow_reveal == false {
                    Label("Kennarinn hefur valið vísbendingar og yfirferð fyrir þetta sett.", systemImage: "lightbulb")
                        .font(.footnote).foregroundStyle(AppTheme.Auth.textSecondary)
                }
            }

            Text("Dæmi í verkefnasettinu")
                .font(.title2.bold()).fontDesign(.serif)
                .foregroundStyle(AppTheme.Auth.textPrimary)

            ForEach(assignment.items.sorted { $0.position < $1.position }) { item in
                Button { onOpen(item) } label: {
                    HStack(alignment: .center, spacing: 16) {
                        Text("\(item.position + 1)")
                            .font(.title2.bold()).monospacedDigit()
                            .foregroundStyle(AppTheme.Auth.primary)
                            .frame(minWidth: 40, minHeight: 44)
                            .background(AppTheme.Auth.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title.isEmpty ? "Dæmi \(item.position + 1)" : item.title)
                                .font(.headline).foregroundStyle(AppTheme.Auth.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.problem_id == nil ? "Opna vinnubók" : "Halda áfram í vinnubók")
                                .font(.subheadline).foregroundStyle(AppTheme.Auth.primary)
                            if item.last_submitted_at != nil {
                                Label("Skilað til kennara", systemImage: "checkmark.circle")
                                    .font(.caption).foregroundStyle(AppTheme.Auth.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if openingItemID == item.id {
                            ProgressView().accessibilityLabel("Opna vinnubók")
                        } else {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppTheme.Auth.primary).accessibilityHidden(true)
                        }
                    }
                    .classroomCard()
                }
                .buttonStyle(.plain)
                .disabled(openingItemID != nil)
                .accessibilityLabel("\(item.title.isEmpty ? "Dæmi \(item.position + 1)" : item.title), \(item.problem_id == nil ? "Opna vinnubók" : "Halda áfram")\(item.last_submitted_at == nil ? "" : ", skilað til kennara")")
                .hoverEffect(.highlight)
            }

            Label("Kennarinn sér handskrift eftir að þú skilar til kennara eða sendir AI-fyrirspurn. Skil merkja ekki að lausnin sé rétt.", systemImage: "person.crop.circle")
                .font(.footnote).foregroundStyle(AppTheme.Auth.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
