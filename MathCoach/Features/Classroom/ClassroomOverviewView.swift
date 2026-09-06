import SwiftUI

struct ClassroomOverviewView: View {
    let classes: [StudentClass]
    let assignments: [StudentAssignment]
    let isLoading: Bool
    let onSelect: (String) -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                SVGLogoView(resourceName: "ratatoskur_logo")
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mínir bekkir")
                        .font(.largeTitle.bold()).fontDesign(.serif)
                        .foregroundStyle(AppTheme.Auth.textPrimary)
                    Text("Veldu bekk til að sjá verkefnin frá kennaranum þínum.")
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                }
            }

            if isLoading && classes.isEmpty {
                ProgressView("Sæki bekki…").frame(maxWidth: .infinity).padding(32)
            } else if classes.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Velkomin í bekkinn", systemImage: "person.3")
                        .font(.title2.bold()).fontDesign(.serif)
                    Text("Fáðu bekkjarkóða hjá kennaranum þínum. Þú notar kóðann einu sinni; eftir það birtist bekkurinn hér.")
                        .foregroundStyle(AppTheme.Auth.textSecondary)
                    Button("Ganga í bekk", systemImage: "person.badge.plus", action: onJoin)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .classroomCard()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], spacing: 16) {
                    ForEach(classes) { classroom in
                        Button { onSelect(classroom.id) } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: "books.vertical")
                                    .font(.title).foregroundStyle(AppTheme.Auth.primary)
                                    .accessibilityHidden(true)
                                Text(classroom.name)
                                    .font(.title2.bold()).fontDesign(.serif)
                                    .foregroundStyle(AppTheme.Auth.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let teacher = classroom.teacher_name, !teacher.isEmpty {
                                    Label(teacher, systemImage: "person.crop.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Auth.textSecondary)
                                }
                                Text("\(assignments.filter { $0.class_id == classroom.id }.count) verkefnasett")
                                    .font(.subheadline).foregroundStyle(AppTheme.Auth.textSecondary)
                                HStack {
                                    Text("Opna bekk").font(.headline)
                                    Spacer()
                                    Image(systemName: "arrow.right").accessibilityHidden(true)
                                }
                                .foregroundStyle(AppTheme.Auth.primary)
                            }
                            .classroomCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Opna bekk: \(classroom.name)")
                        .hoverEffect(.highlight)
                    }
                }
            }

            Label("Persónulegu stílabækurnar þínar eru áfram á heimaskjánum. Kennari sér aðeins vinnu sem þú sendir í bekkjarverkefnum.", systemImage: "book.closed")
                .font(.footnote).foregroundStyle(AppTheme.Auth.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
