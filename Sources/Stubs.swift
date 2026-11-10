// Provisoire (étape 1) : remplacé par les vraies vues aux étapes suivantes.
import SwiftUI

extension Store {
    var todoCount: Int { 0 }
    var followUpsDue: Int { 0 }
    func addContact() -> UUID? { nil }
    var publishedCount: (Int, Int) { (campaign.posts.filter { $0.status == .published }.count, campaign.posts.count) }
}
struct TodayView: View { var body: some View { EmptyState(text: "…").soclePanel() } }
struct ContactsView: View { var body: some View { EmptyState(text: "…").soclePanel() } }
struct BrowserView: View { var body: some View { EmptyState(text: "…") } }
struct PostsView: View {
    @EnvironmentObject var ui: UIState
    var body: some View { TrackingView(selected: $ui.selectedPost) }
}
