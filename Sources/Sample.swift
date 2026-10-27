// hERALD — plan d'exemple chargé au premier lancement : la campagne des 15 ans de Skyrim (11 novembre 2026).
// Les titres suivent la langue de l'interface (clés « sample.* ») ; les brouillons existent dans les 4 langues.
// Aucune donnée personnelle : canaux et produits surveillés sont des pages publiques.
import Foundation

enum Sample {
    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date()
    }

    static func make() -> AppData {
        let nexus = Channel(name: "Nexus Mods", kind: .nexus, url: "https://www.nexusmods.com", notes: L.t("sample.ch.nexus"))
        let reddit = Channel(name: "r/skyrimmods", kind: .reddit, url: "https://www.reddit.com/r/skyrimmods/", notes: L.t("sample.ch.reddit"))
        let macgaming = Channel(name: "r/macgaming", kind: .reddit, url: "https://www.reddit.com/r/macgaming/", notes: L.t("sample.ch.reddit"))
        let discord = Channel(name: "Discord", kind: .discord, url: "https://discord.com", notes: L.t("sample.ch.discord"))
        let youtube = Channel(name: "YouTube", kind: .youtube, url: "https://studio.youtube.com", notes: L.t("sample.ch.youtube"))
        let github = Channel(name: "GitHub Releases", kind: .github, url: "https://github.com", notes: "")
        let bluesky = Channel(name: "Bluesky / X", kind: .bluesky, url: "https://bsky.app", notes: "#Skyrim15")
        let instagram = Channel(name: "Instagram", kind: .instagram, url: "https://www.instagram.com", notes: L.t("sample.ch.instagram"))

        let prep = Milestone(title: L.t("sample.ms.prep"), date: day(2026, 10, 27), kind: .other)
        let teaser = Milestone(title: L.t("sample.ms.teaser"), date: day(2026, 11, 4), kind: .teaser)
        let series = Milestone(title: L.t("sample.ms.series"), date: day(2026, 11, 6), kind: .teaser)
        let dday = Milestone(title: L.t("sample.ms.dday"), date: day(2026, 11, 11), kind: .announce)
        let follow = Milestone(title: L.t("sample.ms.followup"), date: day(2026, 11, 12), kind: .followup)
        let review = Milestone(title: L.t("sample.ms.review"), date: day(2026, 12, 1), kind: .followup)

        func post(_ key: String, _ date: Date, _ ch: Channel, _ ms: Milestone, _ status: PostStatus = .idea,
                  drafts: [String: String] = [:]) -> Post {
            Post(title: L.t(key), date: date, channelID: ch.id, milestoneID: ms.id, status: status, drafts: drafts)
        }

        var c = Campaign(name: L.t("sample.campaign"), eventDate: day(2026, 11, 11), notes: L.t("sample.campaign.notes"))
        c.milestones = [prep, teaser, series, dday, follow, review]
        c.posts = [
            post("sample.post.releases", day(2026, 10, 29), github, prep, .draft),
            post("sample.post.visuals", day(2026, 11, 2), instagram, prep),
            post("sample.post.teaser", day(2026, 11, 4), bluesky, teaser, .draft, drafts: teaserDrafts),
            post("sample.post.teaser.ig", day(2026, 11, 4), instagram, teaser),
            post("sample.post.skycrash", day(2026, 11, 6), macgaming, series),
            post("sample.post.ig.carousel", day(2026, 11, 6), instagram, series),
            post("sample.post.nexuswatch", day(2026, 11, 7), discord, series),
            post("sample.post.short.mabbajack", day(2026, 11, 8), youtube, series),
            post("sample.post.short.mortex", day(2026, 11, 9), youtube, series),
            post("sample.post.ig.reel", day(2026, 11, 10), instagram, series),
            post("sample.post.reddit", day(2026, 11, 11), reddit, dday, .draft, drafts: redditDrafts),
            post("sample.post.nexus", day(2026, 11, 11), nexus, dday, .draft, drafts: nexusDrafts),
            post("sample.post.video", day(2026, 11, 11), youtube, dday),
            post("sample.post.discord", day(2026, 11, 11), discord, dday, .draft, drafts: discordDrafts),
            post("sample.post.community", day(2026, 11, 18), reddit, follow),
            post("sample.post.review", day(2026, 12, 1), github, review),
        ]

        let watch = [
            WatchItem(name: "Vortex", kind: .github, ref: "Nexus-Mods/Vortex"),
            WatchItem(name: "Mod Organizer 2", kind: .github, ref: "ModOrganizer2/modorganizer"),
            WatchItem(name: "Wabbajack", kind: .github, ref: "wabbajack-tools/wabbajack"),
            WatchItem(name: "Whisky", kind: .github, ref: "Whisky-App/Whisky"),
            WatchItem(name: "SkyUI", kind: .nexus, ref: "skyrimspecialedition/12604"),
        ]

        return AppData(campaigns: [c], selected: c.id,
                       channels: [nexus, reddit, macgaming, discord, youtube, github, bluesky, instagram], watch: watch)
    }

    private static let teaserDrafts = [
        "fr": "Skyrim a 15 ans le 11 novembre. 🎂\nPour fêter ça, je prépare quelque chose pour les moddeurs sur Mac : des outils natifs, faits maison, pensés pour Apple Silicon.\nRendez-vous le 11/11. #Skyrim15",
        "en": "Skyrim turns 15 on November 11. 🎂\nTo celebrate, I'm preparing something for Mac modders: native, homemade tools built for Apple Silicon.\nSee you on 11/11. #Skyrim15",
        "es": "Skyrim cumple 15 años el 11 de noviembre. 🎂\nPara celebrarlo, preparo algo para quienes modean en Mac: herramientas nativas, hechas en casa, pensadas para Apple Silicon.\nNos vemos el 11/11. #Skyrim15",
        "it": "Skyrim compie 15 anni l'11 novembre. 🎂\nPer festeggiare preparo qualcosa per chi fa modding su Mac: strumenti nativi, fatti in casa, pensati per Apple Silicon.\nAppuntamento all'11/11. #Skyrim15",
    ]

    private static let redditDrafts = [
        "fr": """
        [Mac] Skyrim a 15 ans : le Mac a enfin ses propres outils de modding

        Bonjour à tous,

        Je modde Skyrim sur Mac depuis longtemps et, pour les 15 ans du jeu, je partage le kit d'applis macOS natives que je construis seul, sur mon temps libre :

        - mORTEX : Vortex sur Mac Apple Silicon (Nexus, FOMOD, Skyrim sous CrossOver)
        - mABBAJACK : les listes Wabbajack sur Mac, sans Windows
        - sKYCRASH : comprendre un crash Skyrim en un clic
        - nEXUSWATCH : suivre commentaires, bugs et téléchargements de ses mods

        Tout est en 4 langues (fr, en, es, it). Téléchargement sur GitHub ; les pages Nexus arrivent bientôt.

        C'est fait maison : vos retours, bugs et idées sont les bienvenus. Merci d'avoir fait vivre ce jeu pendant 15 ans !
        """,
        "en": """
        [Mac] Skyrim turns 15: the Mac finally has its own modding tools

        Hi everyone,

        I've been modding Skyrim on a Mac for a long time, and for the game's 15th anniversary I'm sharing the native macOS apps I build on my own, in my spare time:

        - mORTEX: Vortex on Apple Silicon Macs (Nexus, FOMOD, Skyrim under CrossOver)
        - mABBAJACK: Wabbajack lists on a Mac, no Windows needed
        - sKYCRASH: understand a Skyrim crash in one click
        - nEXUSWATCH: keep track of comments, bugs and downloads on your mods

        Everything is available in 4 languages (en, fr, es, it). Downloads are on GitHub; the Nexus pages are coming soon.

        It's a homemade project: feedback, bug reports and ideas are very welcome. Thanks for keeping this game alive for 15 years!
        """,
        "es": """
        [Mac] Skyrim cumple 15 años: el Mac por fin tiene sus propias herramientas de modding

        Hola a todos:

        Hace mucho que modeo Skyrim en Mac y, por el 15.º aniversario del juego, comparto las apps nativas de macOS que desarrollo solo, en mi tiempo libre:

        - mORTEX: Vortex en Mac con Apple Silicon (Nexus, FOMOD, Skyrim con CrossOver)
        - mABBAJACK: las listas de Wabbajack en Mac, sin Windows
        - sKYCRASH: entender un cierre de Skyrim con un clic
        - nEXUSWATCH: seguir comentarios, bugs y descargas de tus mods

        Todo está en 4 idiomas (es, en, fr, it). Descarga en GitHub; las páginas de Nexus llegarán pronto.

        Es un proyecto casero: vuestros comentarios, bugs e ideas son bienvenidos. ¡Gracias por mantener vivo este juego durante 15 años!
        """,
        "it": """
        [Mac] Skyrim compie 15 anni: il Mac ha finalmente i suoi strumenti di modding

        Ciao a tutti,

        Faccio modding di Skyrim su Mac da tanto tempo e, per i 15 anni del gioco, condivido le app native per macOS che sviluppo da solo, nel tempo libero:

        - mORTEX: Vortex su Mac Apple Silicon (Nexus, FOMOD, Skyrim con CrossOver)
        - mABBAJACK: le liste Wabbajack su Mac, senza Windows
        - sKYCRASH: capire un crash di Skyrim con un clic
        - nEXUSWATCH: seguire commenti, bug e download delle proprie mod

        Tutto è disponibile in 4 lingue (it, en, fr, es). Download su GitHub; le pagine Nexus arriveranno presto.

        È un progetto fatto in casa: commenti, bug e idee sono benvenuti. Grazie per aver tenuto vivo questo gioco per 15 anni!
        """,
    ]

    private static let nexusDrafts = [
        "fr": "Skyrim a 15 ans — un kit de modding natif pour Mac\n\nPour l'anniversaire, le kit est disponible sur GitHub en attendant la mise en ligne des fichiers ici (bientôt). mORTEX, mABBAJACK, sKYCRASH, nEXUSWATCH et une série d'outils d'atelier, en 4 langues.\nVos retours sont les bienvenus dans les commentaires.",
        "en": "Skyrim turns 15 — a native modding kit for the Mac\n\nFor the anniversary, the kit is available on GitHub until the files go live here (coming soon). mORTEX, mABBAJACK, sKYCRASH, nEXUSWATCH and a series of workshop tools, in 4 languages.\nFeedback is welcome in the comments.",
        "es": "Skyrim cumple 15 años — un kit de modding nativo para Mac\n\nPor el aniversario, el kit está disponible en GitHub hasta que los archivos se publiquen aquí (pronto). mORTEX, mABBAJACK, sKYCRASH, nEXUSWATCH y una serie de herramientas de taller, en 4 idiomas.\nVuestros comentarios son bienvenidos.",
        "it": "Skyrim compie 15 anni — un kit di modding nativo per Mac\n\nPer l'anniversario il kit è disponibile su GitHub in attesa che i file vengano pubblicati qui (presto). mORTEX, mABBAJACK, sKYCRASH, nEXUSWATCH e una serie di strumenti da laboratorio, in 4 lingue.\nI vostri commenti sono benvenuti.",
    ]

    private static let discordDrafts = [
        "fr": "Bonjour ! Pour les 15 ans de Skyrim, je partage des outils de modding natifs pour Mac (Apple Silicon) : mORTEX, mABBAJACK, sKYCRASH, nEXUSWATCH. Faits maison, gratuits, en 4 langues. Lien GitHub : <lien>\nSi ce n'est pas le bon salon, dites-le-moi et je retire le message.",
        "en": "Hi! For Skyrim's 15th anniversary I'm sharing native modding tools for the Mac (Apple Silicon): mORTEX, mABBAJACK, sKYCRASH, nEXUSWATCH. Homemade, free, in 4 languages. GitHub link: <link>\nIf this isn't the right channel, let me know and I'll remove the message.",
        "es": "¡Hola! Por los 15 años de Skyrim comparto herramientas de modding nativas para Mac (Apple Silicon): mORTEX, mABBAJACK, sKYCRASH, nEXUSWATCH. Hechas en casa, gratuitas, en 4 idiomas. Enlace de GitHub: <enlace>\nSi este no es el canal adecuado, decídmelo y retiro el mensaje.",
        "it": "Ciao! Per i 15 anni di Skyrim condivido strumenti di modding nativi per Mac (Apple Silicon): mORTEX, mABBAJACK, sKYCRASH, nEXUSWATCH. Fatti in casa, gratuiti, in 4 lingue. Link GitHub: <link>\nSe non è il canale giusto, ditemelo e rimuovo il messaggio.",
    ]
}
