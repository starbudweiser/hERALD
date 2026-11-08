// hERALD — exécution des agents : Claude Code (session « hERALD » unique), commande personnalisée, API compatible OpenAI.
// Rien n'est envoyé ailleurs qu'à l'agent choisi dans les Réglages ; hERALD ne publie jamais.
import Foundation

struct AgentFailure: Error { let message: String }

enum AgentRunner {
    struct Output { let out: String; let err: String; let code: Int32 }

    /// PATH élargi : une appli lancée depuis le Finder n'a pas celui du terminal.
    static var environment: [String: String] {
        var e = ProcessInfo.processInfo.environment
        let extra = ["\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        e["PATH"] = (extra + (e["PATH"]?.split(separator: ":").map(String.init) ?? [])).joined(separator: ":")
        return e
    }

    static func claudeURL(_ cfg: AgentConfig) -> URL? {
        let fm = FileManager.default
        var candidates = [(cfg.claudePath as NSString).expandingTildeInPath]
        candidates += ["\(NSHomeDirectory())/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for c in candidates where !c.isEmpty && fm.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        return nil
    }

    /// Avant de lancer l'agent, hERALD lit lui-même son dossier de travail : sur un disque externe, c'est lui (et non
    /// l'agent) qui déclenche la demande d'autorisation de macOS « volumes amovibles », et un refus devient un message clair.
    static func checkWorkFolder(_ cfg: AgentConfig) async throws {
        let url = cfg.workURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw AgentFailure(message: L.t("agent.err.nofolder", url.path))
        }
        let ok: Bool = await withCheckedContinuation { c in
            DispatchQueue.global().async { c.resume(returning: (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil) }
        }
        if !ok { throw AgentFailure(message: L.t("agent.err.volume", url.path)) }
    }

    private final class Box: @unchecked Sendable { var out = Data(); var err = Data() }

    /// Permet d'arrêter le processus quand la tâche qui l'attend est annulée.
    private final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false
        func set(_ p: Process) { lock.lock(); process = p; let c = cancelled; lock.unlock(); if c { p.terminate() } }
        func cancel() { lock.lock(); cancelled = true; let p = process; lock.unlock(); if p?.isRunning == true { p?.terminate() } }
    }

    /// Lance un processus, lui donne `stdin`, attend sa fin (ou `timeout` secondes) sans bloquer l'interface.
    /// `onLine` reçoit chaque ligne de sortie au fur et à mesure ; l'annulation de la tâche arrête le processus.
    static func run(_ exe: URL, _ args: [String], stdin: String, cwd: URL, timeout: TimeInterval = 900,
                    onLine: (@Sendable (String) -> Void)? = nil) async throws -> Output {
        let handle = Handle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Output, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = exe; p.arguments = args; p.environment = environment; p.currentDirectoryURL = cwd
                    let i = Pipe(), o = Pipe(), e = Pipe()
                    p.standardInput = i; p.standardOutput = o; p.standardError = e
                    do { try p.run() } catch { cont.resume(throwing: AgentFailure(message: error.localizedDescription)); return }
                    handle.set(p)
                    let box = Box(), group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        var pending = Data()
                        while true {
                            let d = o.fileHandleForReading.availableData
                            if d.isEmpty { break }
                            box.out.append(d); pending.append(d)
                            while let nl = pending.firstIndex(of: 10) {
                                let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                                pending.removeSubrange(pending.startIndex...nl)
                                onLine?(line)
                            }
                        }
                        if !pending.isEmpty { onLine?(String(decoding: pending, as: UTF8.self)) }
                        group.leave()
                    }
                    group.enter(); DispatchQueue.global().async { box.err = e.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                    i.fileHandleForWriting.write(Data(stdin.utf8)); try? i.fileHandleForWriting.close()
                    let kill = DispatchWorkItem { if p.isRunning { p.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)
                    p.waitUntilExit(); group.wait(); kill.cancel()
                    cont.resume(returning: Output(out: String(decoding: box.out, as: UTF8.self), err: String(decoding: box.err, as: UTF8.self), code: p.terminationStatus))
                }
            }
        } onCancel: { handle.cancel() }
    }

    /// Phrase d'avancement tirée d'un événement du flux de Claude Code (outil utilisé, rédaction…).
    static func status(fromStreamLine line: String) -> String? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], o["type"] as? String == "assistant",
              let content = (o["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return nil }
        for c in content.reversed() {
            if c["type"] as? String == "tool_use" {
                let input = c["input"] as? [String: Any] ?? [:]
                switch c["name"] as? String ?? "" {
                case "Read": return L.t("agent.status.read", ((input["file_path"] as? String) ?? "").split(separator: "/").last.map(String.init) ?? "…")
                case "Grep", "Glob": return L.t("agent.status.search", (input["pattern"] as? String) ?? "…")
                case "Bash": return L.t("agent.status.run")
                default: return L.t("agent.status.think")
                }
            }
            if c["type"] as? String == "text" { return L.t("agent.status.write") }
        }
        return nil
    }

    /// Vérifie l'agent sans rien lui demander : programme trouvé, dossier de travail accessible (c'est ici que macOS
    /// pose sa question d'autorisation pour un disque externe, au moment choisi par l'utilisateur).
    static func test(_ cfg: AgentConfig) async -> Result<String, AgentFailure> {
        do {
            var info = ""
            switch cfg.kind {
            case .claude:
                guard let exe = claudeURL(cfg) else { return .failure(AgentFailure(message: L.t("agent.err.noclaude"))) }
                let r = try await run(exe, ["--version"], stdin: "", cwd: URL(fileURLWithPath: NSHomeDirectory()), timeout: 30)
                info = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            case .command:
                guard !cfg.command.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(AgentFailure(message: L.t("agent.err.nocommand"))) }
                let first = cfg.command.split(separator: " ").first.map(String.init) ?? ""
                let r = try await run(URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v \(first)"], stdin: "", cwd: URL(fileURLWithPath: NSHomeDirectory()), timeout: 30)
                guard r.code == 0 else { return .failure(AgentFailure(message: L.t("agent.err.nocommandfound", first))) }
                info = first
            case .openai:
                guard !cfg.model.isEmpty, URL(string: cfg.apiURL) != nil else { return .failure(AgentFailure(message: L.t("agent.err.noapi"))) }
                info = cfg.model
            }
            if cfg.kind != .openai { try await checkWorkFolder(cfg) }
            return .success(L.t("agent.test.ok", info))
        } catch let e as AgentFailure { return .failure(e) }
        catch { return .failure(AgentFailure(message: error.localizedDescription)) }
    }

    // MARK: Claude Code

    /// Envoie un message dans la session « hERALD » (la crée si besoin). Renvoie la réponse et l'identifiant de la session.
    static func claude(_ cfg: AgentConfig, session: String, system: String, prompt: String,
                       progress: (@Sendable (String) -> Void)? = nil) async throws -> (text: String, session: String) {
        guard let exe = claudeURL(cfg) else { throw AgentFailure(message: L.t("agent.err.noclaude")) }
        try await checkWorkFolder(cfg)
        let id = session.isEmpty ? UUID().uuidString.lowercased() : session
        // lecture seule + la seule commande `claude` (pour ouvrir des sous-sessions) ; tout le reste est refusé sans question
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "dontAsk",
                    "--tools", "Read,Glob,Grep,Bash", "--allowedTools", "Read,Glob,Grep,Bash(claude *)"]
        if cfg.lightMode { args.append("--safe-mode") }
        args += session.isEmpty ? ["--session-id", id, "--name", cfg.sessionName.isEmpty ? "hERALD" : cfg.sessionName] : ["--resume", id]
        if !cfg.model.isEmpty { args += ["--model", cfg.model] }
        args += ["--append-system-prompt", system]
        let r = try await run(exe, args, stdin: prompt, cwd: cfg.workURL, onLine: { line in
            if let progress, let st = status(fromStreamLine: line) { progress(st) }
        })
        try Task.checkCancellation()
        // la réponse est l'événement « result » (dernier du flux)
        let resultLine = r.out.split(whereSeparator: \.isNewline).last { $0.contains("\"type\":\"result\"") }
        guard let resultLine, let obj = (try? JSONSerialization.jsonObject(with: Data(resultLine.utf8))) as? [String: Any] else {
            throw AgentFailure(message: shorten(r.err.isEmpty ? r.out : r.err))
        }
        if (obj["is_error"] as? Bool) == true || r.code != 0 {
            throw AgentFailure(message: shorten((obj["result"] as? String) ?? r.err))
        }
        return ((obj["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines), (obj["session_id"] as? String) ?? id)
    }

    // MARK: Commande personnalisée (Codex, etc.) : la question arrive sur l'entrée standard, la réponse sort sur la sortie standard

    static func command(_ cfg: AgentConfig, prompt: String) async throws -> String {
        guard !cfg.command.trimmingCharacters(in: .whitespaces).isEmpty else { throw AgentFailure(message: L.t("agent.err.nocommand")) }
        try await checkWorkFolder(cfg)
        let r = try await run(URL(fileURLWithPath: "/bin/zsh"), ["-lc", cfg.command], stdin: prompt, cwd: cfg.workURL)
        guard r.code == 0 else { throw AgentFailure(message: shorten(r.err.isEmpty ? r.out : r.err)) }
        return r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: API compatible OpenAI (ChatGPT, serveurs locaux…)

    static func openai(_ cfg: AgentConfig, system: String, history: [AgentMessage], user: String) async throws -> String {
        let key = Keychain.get("openai")
        guard !cfg.model.isEmpty, let url = URL(string: cfg.apiURL) else { throw AgentFailure(message: L.t("agent.err.noapi")) }
        var msgs: [[String: String]] = [["role": "system", "content": system]]
        for m in history.suffix(24) { msgs.append(["role": m.role == .user ? "user" : "assistant", "content": m.text]) }
        msgs.append(["role": "user", "content": user])
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": cfg.model, "messages": msgs])
        let (d, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        guard (200..<300).contains(code) else {
            let msg = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? L.t("watch.http", code)
            throw AgentFailure(message: shorten(msg))
        }
        guard let text = (((obj?["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any])?["content"] as? String else {
            throw AgentFailure(message: L.t("watch.parse"))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shorten(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 600 ? String(t.prefix(600)) + "…" : t.isEmpty ? L.t("agent.err.empty") : t
    }
}
