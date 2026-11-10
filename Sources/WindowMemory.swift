// hERALD — taille de la fenêtre : taille par défaut fixe, mémorisation à la demande (⇧ + croix rouge, ou menu « Fermer en mémorisant la taille »).
import AppKit
import Darwin

@MainActor
enum WindowMemory {
    /// Taille par défaut du cadre de la fenêtre (titre compris).
    static let defaultSize = NSSize(width: 1724, height: 981)
    private static let key = "windowSize"
    private static var monitor: Any?

    static var saved: NSSize? {
        guard let s = UserDefaults.standard.string(forKey: key) else { return nil }
        let p = s.split(separator: " ").compactMap { Double($0) }
        return p.count == 2 ? NSSize(width: p[0], height: p[1]) : nil
    }

    static func remember(_ w: NSWindow?) {
        guard let w else { return }
        UserDefaults.standard.set("\(Int(w.frame.width)) \(Int(w.frame.height))", forKey: key)
    }

    /// Oublie la taille mémorisée et remet la fenêtre à la taille par défaut.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible && $0.styleMask.contains(.titled) && $0.title == "hERALD" }) { applySize(w) }
    }

    /// Ferme la fenêtre principale en mémorisant sa taille.
    static func closeRemembering() {
        let w = NSApp.windows.first { $0.canBecomeMain && $0.isVisible }
        remember(w); w?.close()
    }

    /// À l'ouverture : taille mémorisée sinon taille par défaut, toujours centrée sur l'écran (la position n'est jamais mémorisée).
    static func applySize(_ w: NSWindow) {
        let want = saved ?? defaultSize
        let screen = w.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = NSSize(width: min(want.width, screen.width), height: min(want.height, screen.height))
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        w.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Libère les caches et rend les pages inutilisées (appelé quand plus aucune fenêtre n'est visible).
    static func trimMemory() {
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        URLCache.shared.removeAllCachedResponses()
        malloc_zone_pressure_relief(nil, 0)
    }

    static func install() {
        // ⇧ + clic sur la croix rouge : mémorise la taille, puis la fermeture se fait normalement.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            guard e.modifierFlags.contains(.shift), let w = e.window,
                  let b = w.standardWindowButton(.closeButton), b.superview != nil else { return e }
            let p = b.convert(e.locationInWindow, from: nil)
            if b.bounds.contains(p) { remember(w) }
            return e
        }
        // Fenêtre fermée (appli réduite en arrière-plan) : on rend au système la mémoire libérable.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, w.title == "hERALD" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { trimMemory() }
        }
        // Première apparition de la fenêtre principale : taille par défaut ou mémorisée.
        var done = Set<ObjectIdentifier>()
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, w.canBecomeMain, w.styleMask.contains(.titled) else { return }
            MainActor.assumeIsolated {
                if done.insert(ObjectIdentifier(w)).inserted, w.frameAutosaveName == "main" || w.title == "hERALD" { applySize(w) }
            }
        }
    }
}
