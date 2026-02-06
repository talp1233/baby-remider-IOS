import SwiftUI

struct LegalView: View {
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        ScrollView {
            VStack(alignment: loc.alignment, spacing: 28) {
                legalSection(
                    icon: "doc.text.fill",
                    title: loc.s("termsOfUse"),
                    content: loc.s("termsOfUseContent")
                )
                legalSection(
                    icon: "lock.shield.fill",
                    title: loc.s("privacyPolicy"),
                    content: loc.s("privacyPolicyContent")
                )
                legalSection(
                    icon: "signature",
                    title: loc.s("eula"),
                    content: loc.s("eulaContent")
                )
                legalSection(
                    icon: "exclamationmark.shield.fill",
                    title: loc.s("disclaimer"),
                    content: loc.s("disclaimerContent")
                )
            }
            .padding(20)
        }
        .background(Color.screenBackground)
        .environment(\.layoutDirection, loc.layoutDirection)
        .navigationTitle(loc.s("legalNavTitle"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func legalSection(icon: String, title: String, content: String) -> some View {
        VStack(alignment: loc.alignment, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.babyOrange)

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }

            Text(content)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(loc.textAlignment)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: loc.frameAlignment)
        .background(Color.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }
}

#Preview {
    NavigationStack {
        LegalView()
            .environmentObject(LocalizationManager.shared)
    }
}
