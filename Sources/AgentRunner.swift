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

    private final class Box { var out = Data(); var err = Data() }

    /// Lance un processus, lui donne `stdin`, attend sa fin (ou `timeout` secondes) sans bloquer l'interface.
    static func run(_ exe: URL, _ args: [String], stdin: String, cwd: URL, timeout: TimeInterval = 600) async throws -> Output {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Output, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = exe; p.arguments = args; p.environment = environment; p.currentDirectoryURL = cwd
                let i = Pipe(), o = Pipe(), e = Pipe()
                p.standardInput = i; p.standardOutput = o; p.standardError = e
                do { try p.run() } catch { cont.resume(throwing: AgentFailure(message: error.localizedDescription)); return }
                let box = Box(), group = DispatchGroup()
                group.enter(); DispatchQueue.global().async { box.out = o.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter(); DispatchQueue.global().async { box.err = e.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                i.fileHandleForWriting.write(Data(stdin.utf8)); try? i.fileHandleForWriting.close()
                let kill = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)
                p.waitUntilExit(); group.wait(); kill.cancel()
                cont.resume(returning: Output(out: String(decoding: box.out, as: UTF8.self), err: String(decoding: box.err, as: UTF8.self), code: p.terminationStatus))
            }
        }
    }

    // MARK: Claude Code

    /// Envoie un message dans la session « hERALD » (la crée si besoin). Renvoie la réponse et l'identifiant de la session.
    static func claude(_ cfg: AgentConfig, session: String, system: String, prompt: String) async throws -> (text: String, session: String) {
        guard let exe = claudeURL(cfg) else { throw AgentFailure(message: L.t("agent.err.noclaude")) }
        let id = session.isEmpty ? UUID().uuidString.lowercased() : session
        // lecture seule + la seule commande `claude` (pour ouvrir des sous-sessions) ; tout le reste est refusé sans question
        var args = ["-p", "--output-format", "json", "--permission-mode", "dontAsk",
                    "--tools", "Read,Glob,Grep,Bash", "--allowedTools", "Read,Glob,Grep,Bash(claude *)"]
        if cfg.lightMode { args.append("--safe-mode") }
        args += session.isEmpty ? ["--session-id", id, "--name", cfg.sessionName.isEmpty ? "hERALD" : cfg.sessionName] : ["--resume", id]
        if !cfg.model.isEmpty { args += ["--model", cfg.model] }
        args += ["--append-system-prompt", system]
        let r = try await run(exe, args, stdin: prompt, cwd: cfg.workURL)
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(r.out.utf8))) as? [String: Any] else {
            throw AgentFailure(message: shorten(r.err.isEmpty ? r.out : r.err) )
        }
        if (obj["is_error"] as? Bool) == true || r.code != 0 {
            throw AgentFailure(message: shorten((obj["result"] as? String) ?? r.err))
        }
        return ((obj["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines), (obj["session_id"] as? String) ?? id)
    }

    // MARK: Commande personnalisée (Codex, etc.) : la question arrive sur l'entrée standard, la réponse sort sur la sortie standard

    static func command(_ cfg: AgentConfig, prompt: String) async throws -> String {
        guard !cfg.command.trimmingCharacters(in: .whitespaces).isEmpty else { throw AgentFailure(message: L.t("agent.err.nocommand")) }
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
