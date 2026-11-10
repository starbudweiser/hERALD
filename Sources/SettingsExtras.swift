// hERALD — Réglages : mise à jour automatique et sauvegarde iCloud.
import SwiftUI

struct UpdateSection: View {
    @ObservedObject var updater = Updater.shared
    @AppStorage("autoUpdate") private var auto = true

    private var status: String {
        switch updater.state {
        case .idle: L.t("upd.version", updater.currentVersion)
        case .checking: L.t("upd.checking")
        case .upToDate: L.t("upd.uptodate", updater.currentVersion)
        case .available(let v): L.t("upd.available", v)
        case .downloading: L.t("upd.downloading")
        case .failed(let e): L.t("upd.failed", e)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            Toggle(L.t("upd.auto"), isOn: $auto)
            HStack(spacing: Socle.M.space2) {
                Button(L.t("upd.check")) { Task { await updater.check() } }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(updater.state == .checking || updater.state == .downloading)
                if case .available(let v) = updater.state {
                    Button(L.t("upd.install", v)) { Task { await updater.install() } }
                        .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            Text(status).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(2)
        }
    }
}

struct BackupSection: View {
    @EnvironmentObject var store: Store
    @State private var on = PlanBackup.enabled
    @State private var message: String?

    private var status: String {
        if PlanBackup.defaultDir == nil { return L.t("backup.unavailable") }
        if let e = store.backupError { return L.t("backup.err", e) }
        return PlanBackup.lastDate.map { L.t("backup.last", L.date($0)) } ?? L.t("backup.never")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            Toggle(L.t("backup.enable"), isOn: Binding(get: { on }, set: { on = $0; PlanBackup.enabled = $0 }))
            HStack(spacing: Socle.M.space2) {
                Button(L.t("backup.now")) { store.backupNow() }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(PlanBackup.defaultDir == nil)
                Button(L.t("backup.restore")) { restore() }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(PlanBackup.defaultDir == nil)
                Button(L.t("settings.reveal")) { if let d = PlanBackup.defaultDir { NSWorkspace.shared.activateFileViewerSelecting([d]) } }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(PlanBackup.defaultDir == nil)
            }
            Text(message ?? status).socle(Socle.T.meta).foregroundStyle(store.backupError == nil ? Socle.C.textSubtle : Socle.C.danger).lineLimit(2)
            Text(L.t("backup.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.directoryURL = PlanBackup.defaultDir
        panel.allowedContentTypes = [Store.planType, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        message = store.restoreBackup(from: url) ?? L.t("backup.restored")
    }
}
