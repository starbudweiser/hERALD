// Provisoire (étape 1) : remplacé par les vraies vues aux étapes suivantes.
import SwiftUI

extension Store {
    var followUpsDue: Int { 0 }
    func addContact() -> UUID? { nil }
    var publishedCount: (Int, Int) { (campaign.posts.filter { $0.status == .published }.count, campaign.posts.count) }
}
struct ContactsView: View { var body: some View { EmptyState(text: "…").soclePanel() } }
struct BrowserView: View { var body: some View { EmptyState(text: "…") } }
struct PostsView: View {
    @EnvironmentObject var ui: UIState
    var body: some View { TrackingView(selected: $ui.selectedPost) }
}

extension Store { func contactTodos(now: Date) -> [TodoItem] { [] } }
struct ContactDetail: View { let id: UUID; var body: some View { EmptyState(text: "…") } }
struct PostInspector: View {
    let id: UUID
    @Binding var selected: UUID?
    var body: some View { PostEditor(id: id, selected: $selected) }
}
