// hERALD — canaux par défaut et campagne d'exemple facultative (lancement fictif d'un mod), proposée au premier
// lancement et supprimable comme toute campagne. Titres et notes suivent la langue de l'interface (clés « sample.* ») ;
// les brouillons existent dans les 4 langues, avec des repères [Nom du mod] et [lien] à remplacer.
import Foundation

enum Sample {
    /// Canaux proposés d'office : les grandes plateformes, sans compte ni page particulière.
    static func channels() -> [Channel] {
        [
            Channel(name: "Nexus Mods", kind: .nexus, url: "https://www.nexusmods.com", notes: L.t("sample.ch.nexus")),
            Channel(name: "Reddit", kind: .reddit, url: "https://www.reddit.com", notes: L.t("sample.ch.reddit")),
            Channel(name: "Discord", kind: .discord, url: "https://discord.com", notes: L.t("sample.ch.discord")),
            Channel(name: "YouTube", kind: .youtube, url: "https://studio.youtube.com", notes: L.t("sample.ch.youtube")),
            Channel(name: "GitHub Releases", kind: .github, url: "https://github.com", notes: ""),
            Channel(name: "Bluesky / X", kind: .bluesky, url: "https://bsky.app", notes: ""),
            Channel(name: "Instagram", kind: .instagram, url: "https://www.instagram.com", notes: L.t("sample.ch.instagram")),
        ]
    }

    /// Campagne d'exemple : sortie dans 21 jours, jalons et publications placés autour de cette date.
    /// Utilise les canaux existants (par type) ; `channels` reçoit ceux qu'il faut ajouter.
    static func campaign(using channels: inout [Channel], now: Date = Date()) -> Campaign {
        let cal = Calendar.current
        let launch = cal.date(byAdding: .day, value: 21, to: cal.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now) ?? now
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: launch) ?? launch }
        func ch(_ kind: ChannelKind) -> Channel {
            if let c = channels.first(where: { $0.kind == kind }) { return c }
            let c = Sample.channels().first { $0.kind == kind } ?? Channel(name: kind.label, kind: kind)
            channels.append(c)
            return c
        }

        let prep = Milestone(title: L.t("sample.ms.prep"), date: day(-14), kind: .other)
        let teaser = Milestone(title: L.t("sample.ms.teaser"), date: day(-7), kind: .teaser)
        let preview = Milestone(title: L.t("sample.ms.preview"), date: day(-3), kind: .teaser)
        let launchMs = Milestone(title: L.t("sample.ms.launch"), date: launch, kind: .announce)
        let follow = Milestone(title: L.t("sample.ms.followup"), date: day(3), kind: .followup)
        let review = Milestone(title: L.t("sample.ms.review"), date: day(30), kind: .followup)

        func post(_ key: String, _ date: Date, _ kind: ChannelKind, _ ms: Milestone, _ status: PostStatus = .idea,
                  drafts: [String: String] = [:]) -> Post {
            Post(title: L.t(key), date: date, channelID: ch(kind).id, milestoneID: ms.id, status: status, drafts: drafts)
        }

        var c = Campaign(name: L.t("sample.campaign"), eventDate: launch, notes: L.t("sample.campaign.notes"))
        c.milestones = [prep, teaser, preview, launchMs, follow, review]
        c.posts = [
            post("sample.post.files", day(-12), .nexus, prep, .draft),
            post("sample.post.visuals", day(-10), .instagram, prep),
            post("sample.post.teaser", day(-7), .bluesky, teaser, .draft, drafts: teaserDrafts),
            post("sample.post.teaser.ig", day(-7), .instagram, teaser),
            post("sample.post.preview", day(-3), .discord, preview),
            post("sample.post.short", day(-2), .youtube, preview),
            post("sample.post.reddit", launch, .reddit, launchMs, .draft, drafts: launchDrafts),
            post("sample.post.nexus", launch, .nexus, launchMs, .draft, drafts: nexusDrafts),
            post("sample.post.video", launch, .youtube, launchMs),
            post("sample.post.discord", launch, .discord, launchMs, .draft, drafts: discordDrafts),
            post("sample.post.community", day(7), .reddit, follow),
            post("sample.post.review", day(30), .github, review),
        ]
        return c
    }

    /// Plan complet d'exemple (canaux par défaut + campagne), pour les tests et l'aperçu.
    static func make(now: Date = Date()) -> AppData {
        var chans = channels()
        let c = campaign(using: &chans, now: now)
        return AppData(campaigns: [c], selected: c.id, channels: chans)
    }

    private static let teaserDrafts = [
        "fr": "Quelque chose arrive dans 7 jours… 👀\n[Nom du mod] : [ce qu'il apporte, en une phrase].\nRendez-vous le [date] !",
        "en": "Something is coming in 7 days… 👀\n[Mod name]: [what it brings, in one sentence].\nSee you on [date]!",
        "es": "Algo llega dentro de 7 días… 👀\n[Nombre del mod]: [lo que aporta, en una frase].\n¡Nos vemos el [fecha]!",
        "it": "Qualcosa arriva tra 7 giorni… 👀\n[Nome della mod]: [cosa porta, in una frase].\nAppuntamento al [data]!",
    ]

    private static let launchDrafts = [
        "fr": """
        [Nom du mod] est disponible : [ce qu'il apporte]

        Bonjour à tous,

        Je viens de publier [Nom du mod], un projet fait sur mon temps libre :

        - [Fonction 1]
        - [Fonction 2]
        - [Fonction 3]

        Téléchargement : [lien]

        Vos retours, bugs et idées sont les bienvenus. Merci d'avance !
        """,
        "en": """
        [Mod name] is out: [what it brings]

        Hi everyone,

        I've just released [Mod name], a project I build in my spare time:

        - [Feature 1]
        - [Feature 2]
        - [Feature 3]

        Download: [link]

        Feedback, bug reports and ideas are very welcome. Thanks in advance!
        """,
        "es": """
        [Nombre del mod] ya está disponible: [lo que aporta]

        Hola a todos:

        Acabo de publicar [Nombre del mod], un proyecto que desarrollo en mi tiempo libre:

        - [Función 1]
        - [Función 2]
        - [Función 3]

        Descarga: [enlace]

        Vuestros comentarios, bugs e ideas son bienvenidos. ¡Gracias de antemano!
        """,
        "it": """
        [Nome della mod] è disponibile: [cosa porta]

        Ciao a tutti,

        Ho appena pubblicato [Nome della mod], un progetto che sviluppo nel tempo libero:

        - [Funzione 1]
        - [Funzione 2]
        - [Funzione 3]

        Download: [link]

        Commenti, bug e idee sono benvenuti. Grazie in anticipo!
        """,
    ]

    private static let nexusDrafts = [
        "fr": "[Nom du mod] — [accroche]\n\n[Description courte : ce que fait le mod, prérequis, installation.]\nVos retours sont les bienvenus dans les commentaires.",
        "en": "[Mod name] — [tagline]\n\n[Short description: what the mod does, requirements, installation.]\nFeedback is welcome in the comments.",
        "es": "[Nombre del mod] — [eslogan]\n\n[Descripción breve: qué hace el mod, requisitos, instalación.]\nVuestros comentarios son bienvenidos.",
        "it": "[Nome della mod] — [slogan]\n\n[Descrizione breve: cosa fa la mod, requisiti, installazione.]\nI vostri commenti sono benvenuti.",
    ]

    private static let discordDrafts = [
        "fr": "Bonjour ! Je viens de publier [Nom du mod] : [ce qu'il apporte]. Gratuit, retours bienvenus. Lien : [lien]\nSi ce n'est pas le bon salon, dites-le-moi et je retire le message.",
        "en": "Hi! I've just released [Mod name]: [what it brings]. Free, feedback welcome. Link: [link]\nIf this isn't the right channel, let me know and I'll remove the message.",
        "es": "¡Hola! Acabo de publicar [Nombre del mod]: [lo que aporta]. Gratis, comentarios bienvenidos. Enlace: [enlace]\nSi este no es el canal adecuado, decídmelo y retiro el mensaje.",
        "it": "Ciao! Ho appena pubblicato [Nome della mod]: [cosa porta]. Gratuita, commenti benvenuti. Link: [link]\nSe non è il canale giusto, ditemelo e rimuovo il messaggio.",
    ]
}
