// Provisoire (étape 1) : remplacé par les vraies vues aux étapes suivantes.
import SwiftUI

extension Store {
    var followUpsDue: Int { 0 }
    func addContact() -> UUID? { nil }
    var publishedCount: (Int, Int) { (campaign.posts.filter { $0.status == .published }.count, campaign.posts.count) }
}
struct ContactsView: View { var body: some View { EmptyState(text: "…").soclePanel() } }
struct BrowserView: View { var body: some View { EmptyState(text: "…") } }

extension Store { func contactTodos(now: Date) -> [TodoItem] { [] } }
struct ContactDetail: View { let id: UUID; var body: some View { EmptyState(text: "…") } }
