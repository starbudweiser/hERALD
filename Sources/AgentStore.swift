// hERALD — dialogue avec l'agent IA : envoi des demandes, historique par tâche, propositions appliquées d'un clic.
import Foundation

extension Store {
    func agentThread(_ t: AgentTarget) -> AgentThread {
        switch t {
        case .campaign: return campaign.agent ?? AgentThread()
        case .post(let id): return post(id)?.agent ?? AgentThread()
        }
    }

    private func mutateThread(_ t: AgentTarget, _ ci: Int, _ f: (inout AgentThread) -> Void) {
        switch t {
        case .campaign:
            var th = data.campaigns[ci].agent ?? AgentThread(); f(&th); data.campaigns[ci].agent = th
        case .post(let id):
            guard let pi = data.campaigns[ci].posts.firstIndex(where: { $0.id == id }) else { return }
            var th = data.campaigns[ci].posts[pi].agent ?? AgentThread(); f(&th); data.campaigns[ci].posts[pi].agent = th
        }
    }

    /// Titre de la discussion.
    func agentTitle(_ t: AgentTarget) -> String {
        switch t {
        case .campaign: return campaign.name
        case .post(let id): return post(id)?.title ?? "—"
        }
    }

    /// Lance une demande en arrière-plan (interruptible avec `cancelAgent`).
    func startAgent(_ t: AgentTarget, _ question: String) {
        guard !agentBusy.contains(t) else { return }
        agentTasks[t] = Task {
            var actions = await self.askAgent(t, question)
            var rounds = 0
            // mode assistance : on exécute les actions de l'agent, puis on lui renvoie les résultats, jusqu'à la fin du travail
            while self.assistOn, !actions.isEmpty, rounds < AssistMode.maxRounds, !Task.isCancelled, let run = self.assistExecutor {
                rounds += 1
                var results: [String] = []
                for a in actions.prefix(AssistMode.maxPerRound) {
                    if Task.isCancelled { break }
                    results.append("\(a.kind): " + (await run(a)))
                }
                guard !Task.isCancelled else { break }
                actions = await self.askAgent(t, "[hERALD action results]\n" + results.joined(separator: "\n"), auto: true)
            }
            if !AssistMode.persistent { self.assistOn = false }
            self.agentTasks[t] = nil
        }
    }

    /// Reprend la main : arrête l'agent, refuse la confirmation en attente et coupe le mode assistance.
    func assistStop() {
        assistOn = false
        assistConfirm?.resolve(false); assistConfirm = nil
        for t in agentTasks.values { t.cancel() }
    }

    func cancelAgent(_ t: AgentTarget) { agentTasks[t]?.cancel() }

    /// Envoie une demande. Toutes les demandes partent dans la même session de l'agent ; le contexte (campagne, tâche)
    /// accompagne le message quand il est nouveau ou modifié, pour que l'agent retrouve la tâche concernée.
    @discardableResult
    func askAgent(_ t: AgentTarget, _ question: String, auto: Bool = false) async -> [AssistAction] {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !agentBusy.contains(t), let ci = data.campaigns.firstIndex(where: { $0.id == campaign.id }) else { return [] }
        var found: [AssistAction] = []
        let cfg = AgentConfig.current
        agentBusy.insert(t); agentError[t] = nil; agentStart[t] = Date(); agentStatus[t] = L.t("agent.status.think")
        defer { agentBusy.remove(t); agentStatus[t] = nil; agentStart[t] = nil }
        let progress: @Sendable (String) -> Void = { [weak self] s in Task { @MainActor in self?.agentStatus[t] = s } }
        let before = agentThread(t)
        mutateThread(t, ci) { $0.messages.append(AgentMessage(role: .user, text: q, auto: auto ? true : nil)) }

        let camp = data.campaigns[ci]
        let chan: (UUID?) -> String = { [unowned self] in channel($0)?.name ?? "—" }
        let campBlock = AgentContext.campaignBlock(camp, config: cfg, channel: chan) + (assistOn ? AssistPrompt.contactsBlock(camp) : "")
        var postBlock = ""
        if case .post(let id) = t, let p = camp.posts.first(where: { $0.id == id }) {
            postBlock = AgentContext.postBlock(p, in: camp, config: cfg, channel: chan)
        }
        let campHash = AgentContext.hash(campBlock), postHash = postBlock.isEmpty ? nil : AgentContext.hash(postBlock)
        let system = AgentContext.system(config: cfg, campaign: camp, assist: assistOn)
        do {
            var reply: String
            var usage: AgentUsage?
            switch cfg.kind {
            case .claude:
                var parts: [String] = []
                if camp.agent?.contextHash != campHash { parts.append(campBlock) }
                if let postHash, before.contextHash != postHash { parts.append(postBlock) }
                let r = try await AgentRunner.claude(cfg, session: cfg.sessionID, system: system,
                                                     prompt: AgentContext.message(question: q, context: parts.isEmpty ? nil : parts.joined(separator: "\n")),
                                                     progress: progress)
                reply = r.text; usage = r.usage
                if cfg.sessionID != r.session { var c = AgentConfig.current; c.sessionID = r.session; AgentConfig.current = c }
            case .command:
                reply = try await AgentRunner.command(cfg, prompt: AgentContext.transcript(system: system, context: campBlock + "\n" + postBlock,
                                                                                            history: before.messages, question: q))
            case .openai:
                let r = try await AgentRunner.openai(cfg, system: system, history: before.messages,
                                                     user: AgentContext.message(question: q, context: campBlock + "\n" + postBlock))
                reply = r.text; usage = r.usage
            }
            let acts = AssistParse.extract(reply)
            reply = acts.clean
            if assistOn { found = acts.actions }
            let parsed = AgentParse.sessions(reply)
            reply = parsed.clean
            mutateThread(t, ci) { th in
                th.messages.append(AgentMessage(role: .assistant, text: reply, usage: usage))
                if let postHash { th.contextHash = postHash }
            }
            // contexte de campagne envoyé : mémorisé sur la discussion de campagne
            var c = data.campaigns[ci].agent ?? AgentThread(); c.contextHash = campHash; data.campaigns[ci].agent = c
            for s in parsed.items { attachSubSession(s, ci: ci, current: t) }
        } catch let e as AgentFailure {
            agentError[t] = Task.isCancelled ? L.t("agent.cancelled") : e.message
        } catch {
            agentError[t] = Task.isCancelled ? L.t("agent.cancelled") : error.localizedDescription
        }
        return found
    }

    /// Rattache une sous-session annoncée par l'agent à la tâche qu'elle traite (sinon à la discussion en cours).
    private func attachSubSession(_ s: (id: String, name: String, task: String?), ci: Int, current: AgentTarget) {
        var target = current
        if let ref = s.task, let pi = AgentParse.find(ref, in: data.campaigns[ci], current: nil) { target = .post(data.campaigns[ci].posts[pi].id) }
        mutateThread(target, ci) { th in
            if !th.subSessions.contains(where: { $0.id == s.id }) { th.subSessions.append(AgentSubSession(id: s.id, name: s.name)) }
        }
    }

    // MARK: Propositions de modifications

    private func messageIndex(_ t: AgentTarget, _ id: UUID) -> Int? { agentThread(t).messages.firstIndex { $0.id == id } }

    func applyProposal(_ t: AgentTarget, message id: UUID, only: Set<String>? = nil) {
        guard let ci = data.campaigns.firstIndex(where: { $0.id == campaign.id }), let mi = messageIndex(t, id),
              let proposal = AgentParse.split(agentThread(t).messages[mi].text).proposal else { return }
        var c = data.campaigns[ci]
        var current: UUID?; if case .post(let p) = t { current = p }
        let r = AgentParse.apply(proposal, to: &c, current: current, only: only)
        // la discussion vit dans la campagne : on ne la remplace pas par la copie modifiée
        let thread = data.campaigns[ci].agent
        c.agent = thread
        data.campaigns[ci] = c
        mutateThread(t, ci) { th in
            th.messages[mi].applied = Date(); th.messages[mi].undo = r.undo
        }
    }

    func undoProposal(_ t: AgentTarget, message id: UUID) {
        guard let ci = data.campaigns.firstIndex(where: { $0.id == campaign.id }), let mi = messageIndex(t, id),
              let undo = agentThread(t).messages[mi].undo else { return }
        var c = data.campaigns[ci]
        AgentParse.revert(undo, in: &c)
        data.campaigns[ci] = c
        mutateThread(t, ci) { th in th.messages[mi].applied = nil; th.messages[mi].undo = nil }
    }

    func dismissProposal(_ t: AgentTarget, message id: UUID) {
        guard let ci = data.campaigns.firstIndex(where: { $0.id == campaign.id }), let mi = messageIndex(t, id) else { return }
        mutateThread(t, ci) { $0.messages[mi].dismissed = true }
    }

    func clearThread(_ t: AgentTarget) {
        guard let ci = data.campaigns.firstIndex(where: { $0.id == campaign.id }) else { return }
        mutateThread(t, ci) { th in th.messages = []; th.contextHash = nil }
    }
}
