// hERALD — sauvegarde des plans dans iCloud Drive : un instantané par jour (30 gardés) et « plan-latest.herald ».
// Aucun droit spécial : on écrit dans le dossier iCloud Drive de l'utilisateur, iCloud se charge de la synchronisation.
// Un plan sans campagne n'est jamais sauvegardé (il écraserait une bonne copie).
import Foundation

enum PlanBackup {
    static let keep = 30
    static let latestName = "plan-latest.herald"

    /// iCloud Drive du Mac (absent si iCloud Drive est désactivé).
    static var iCloudRoot: URL? {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    static var defaultDir: URL? { iCloudRoot?.appendingPathComponent("hERALD/Sauvegardes", isDirectory: true) }

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "icloudBackup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "icloudBackup") }
    }
    static var lastDate: Date? { UserDefaults.standard.object(forKey: "icloudBackupLast") as? Date }

    private static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// Écrit « plan-latest » et l'instantané du jour dans `dir`, puis ne garde que les `keep` derniers instantanés.
    @discardableResult
    static func write(_ plan: AppData, to dir: URL, now: Date = Date()) -> Result<URL, Error> {
        guard !plan.campaigns.isEmpty else { return .failure(NSError(domain: "hERALD", code: 1)) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Storage.encode(plan)
            let latest = dir.appendingPathComponent(latestName)
            try data.write(to: latest, options: .atomic)
            try data.write(to: dir.appendingPathComponent("plan-\(stamp(now)).herald"), options: .atomic)
            let dated = snapshots(in: dir)
            for old in dated.dropFirst(keep) { try? FileManager.default.removeItem(at: old.url) }
            return .success(latest)
        } catch { return .failure(error) }
    }

    /// Instantanés datés, du plus récent au plus ancien.
    static func snapshots(in dir: URL) -> [(url: URL, date: Date)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return urls.compactMap { u -> (URL, Date)? in
            let n = u.lastPathComponent
            guard n.hasPrefix("plan-2"), u.pathExtension == "herald", let d = f.date(from: String(n.dropFirst(5).prefix(10))) else { return nil }
            return (u, d)
        }.sorted { $0.1 > $1.1 }
    }

    /// Sauvegarde dans iCloud Drive si l'option est active. Renvoie un message d'erreur ou nil.
    @discardableResult
    static func run(_ plan: AppData) -> String? {
        guard enabled else { return nil }
        guard let dir = defaultDir else { return L.t("backup.unavailable") }
        switch write(plan, to: dir) {
        case .success: UserDefaults.standard.set(Date(), forKey: "icloudBackupLast"); return nil
        case .failure(let e): return (e as NSError).code == 1 ? nil : e.localizedDescription
        }
    }
}
