import SwiftUI

struct LegalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 32) {
                Group {
                    Text("תנאי שימוש")
                        .font(.title2).bold()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("כאן יוצגו תנאי השימוש. עדכן טקסט זה בהתאם למדיניות שלך.")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Group {
                    Text("מדיניות פרטיות")
                        .font(.title2).bold()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("כאן תוצג מדיניות הפרטיות. עדכן טקסט זה בהתאם למדיניות שלך.")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Group {
                    Text("הסכם רישיון משתמש קצה (EULA)")
                        .font(.title2).bold()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("כאן יוצג הסכם הרישיון למשתמש הקצה. עדכן טקסט זה בהתאם למדיניות שלך.")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Group {
                    Text("הצהרת אחריות")
                        .font(.title2).bold()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("כאן תופיע הצהרת אחריות. עדכן טקסט זה בהתאם למדיניות שלך.")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding()
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle("תנאים והצהרות")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { LegalView() }
}
