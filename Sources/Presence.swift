// hERALD — présence de l'appli : Dock, barre de menus en haut de l'écran, ou les deux (préférence).
// Avec la barre de menus, fermer la fenêtre ne quitte plus l'appli : elle continue en arrière-plan
// (relevés de statistiques toutes les heures) et se rouvre d'un clic sur son icône en couleur.
import AppKit
import SwiftUI

enum IconMode: String, CaseIterable, Identifiable {
    case dock, menubar, both
    var id: String { rawValue }
    var label: String { L.t("settings.icon.\(rawValue)") }
    var showsDock: Bool { self != .menubar }
    var showsMenuBar: Bool { self != .dock }

    static let key = "iconMode"
    static var current: IconMode {
        get { IconMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .dock }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

@MainActor
final class Presence: NSObject {
    static let shared = Presence()

    /// Ouvre la fenêtre principale (fournie par SwiftUI, car une fenêtre fermée doit être rouverte par lui).
    var openMain: (() -> Void)?
    var refreshStats: (() -> Void)?
    private var item: NSStatusItem?

    var mode: IconMode { IconMode.current }

    /// Applique la préférence : politique d'activation (Dock) et icône de la barre de menus.
    func apply() {
        let m = mode
        let wanted: NSApplication.ActivationPolicy = m.showsDock ? .regular : .accessory
        if NSApp.activationPolicy() != wanted { NSApp.setActivationPolicy(wanted) }
        if m.showsMenuBar { installItem() } else { removeItem() }
    }

    private func installItem() {
        if item == nil {
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item = it
        }
        guard let it = item else { return }
        // silhouette en couleur, sans fond (pas une image « modèle » monochrome)
        it.button?.image = Self.silhouette()
        it.button?.imagePosition = .imageOnly
        it.button?.toolTip = "hERALD"
        // pas de it.menu : sur certaines configurations (plusieurs écrans) macOS ouvre ce menu loin de l'icône ;
        // hERALD le fait apparaître lui-même, juste sous l'icône
        it.menu = nil
        it.button?.target = self
        it.button?.action = #selector(statusClicked)
        it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: L.t("menubar.open"), action: #selector(showMain), keyEquivalent: "")
        let refresh = NSMenuItem(title: L.t("menubar.refresh"), action: #selector(doRefresh), keyEquivalent: "")
        let quit = NSMenuItem(title: L.t("menubar.quit"), action: #selector(quitApp), keyEquivalent: "")
        let about = NSMenuItem(title: L.t("side.about", "hERALD"), action: #selector(showAbout), keyEquivalent: "")
        let closeMem = NSMenuItem(title: L.t("window.close.remember"), action: #selector(closeRemembering), keyEquivalent: "")
        [open, refresh, about, quit, closeMem].forEach { $0.target = self }
        menu.addItem(open); menu.addItem(refresh); menu.addItem(closeMem); menu.addItem(.separator())
        let icon = NSMenuItem(title: L.t("settings.icon"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for m in IconMode.allCases {
            let it = NSMenuItem(title: m.label, action: #selector(chooseMode(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = m.rawValue
            it.state = m == mode ? .on : .off
            sub.addItem(it)
        }
        icon.submenu = sub
        menu.addItem(icon); menu.addItem(.separator()); menu.addItem(about); menu.addItem(quit)
        return menu
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = IconMode(rawValue: raw) else { return }
        IconMode.current = m
        apply()
        if m == .dock { showMain() }  // plus d'icône ici : la fenêtre reste accessible par le Dock
    }

    /// Clic gauche : ouvre ou ferme la fenêtre. Clic droit (ou Ctrl-clic) : menu, juste sous l'icône.
    @objc private func statusClicked() {
        guard let button = item?.button else { return }
        let ev = NSApp.currentEvent
        let wantsMenu = ev?.type == .rightMouseUp || ev?.modifierFlags.contains(.control) == true
        if wantsMenu {
            // position calculée en coordonnées d'écran, à partir de la fenêtre de l'icône (celle de son écran, pas de l'écran actif)
            if let w = button.window {
                let r = w.convertToScreen(button.convert(button.bounds, to: nil))
                var x = r.minX
                if let sc = w.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(r) }) {
                    let menu = makeMenu()
                    x = min(max(x, sc.frame.minX), sc.frame.maxX - menu.size.width - 4)
                    menu.popUp(positioning: nil, at: NSPoint(x: x, y: r.minY - 4), in: nil)
                    return
                }
                makeMenu().popUp(positioning: nil, at: NSPoint(x: x, y: r.minY - 4), in: nil)
            } else {
                let y = button.isFlipped ? button.bounds.maxY + 4 : -4
                makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: button)
            }
        } else if let w = mainWindow, NSApp.isActive, !w.isMiniaturized {
            hideToMenuBar()      // fenêtre au premier plan : on la ferme (l'appli reste dans la barre de menus)
        } else {
            showMain()           // fermée, cachée derrière d'autres applis ou réduite : on l'amène devant
        }
    }

    /// Le fanion du logo en grand, sans le carré sombre ni la hampe, avec les ondes bleues en bas à droite, par-dessus.
    /// Dessin dans un repère 640 × 640 (origine en haut).
    static func silhouette(height: CGFloat = 20) -> NSImage {
        let box = CGRect(x: 0, y: 0, width: 640, height: 640)
        let img = NSImage(size: NSSize(width: height, height: height), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: rect.width / box.width, y: rect.height / box.height)
            let amber = NSColor(red: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255, alpha: 1)
            let blue = NSColor(red: 0x0e / 255, green: 0xa5 / 255, blue: 0xe9 / 255, alpha: 1)
            // fanion à queue fendue (coordonnées du logo × 1,7)
            func f(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 296) * 1.8 + 10, y: (y - 224) * 1.8 + 10) }
            amber.setFill()
            let flag = NSBezierPath()
            flag.move(to: f(296, 224)); flag.line(to: f(640, 224)); flag.line(to: f(560, 374))
            flag.line(to: f(640, 524)); flag.line(to: f(296, 524)); flag.close(); flag.fill()
            // « H » découpé dans le fanion
            ctx.setBlendMode(.clear)
            let h = NSAttributedString(string: "H", attributes: [.font: NSFont.systemFont(ofSize: 380, weight: .heavy), .foregroundColor: NSColor.black])
            let hs = h.size(); let hc = f(420, 368)
            h.draw(at: CGPoint(x: hc.x - hs.width / 2, y: hc.y - hs.height / 2))
            // liseré dégagé autour des ondes, pour qu'elles se détachent du fanion
            let radii: [CGFloat] = [105, 175, 245]
            let center = CGPoint(x: 330, y: 470)
            func arcs(_ extra: CGFloat) {
                for (i, r) in radii.enumerated() {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: r, startAngle: -40, endAngle: 40, clockwise: false)
                    arc.lineWidth = 52 - CGFloat(i) * 6 + extra
                    arc.lineCapStyle = .round
                    arc.stroke()
                }
            }
            NSColor.black.setStroke(); arcs(34)
            ctx.setBlendMode(.normal)
            // ondes d'annonce, au premier plan
            for (i, r) in radii.enumerated() {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: r, startAngle: -40, endAngle: 40, clockwise: false)
                arc.lineWidth = 52 - CGFloat(i) * 6
                arc.lineCapStyle = .round
                blue.setStroke()
                arc.stroke()
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private func removeItem() {
        if let it = item { NSStatusBar.system.removeStatusItem(it) }
        item = nil
    }

    /// Fenêtre principale visible ?
    private var mainWindow: NSWindow? { NSApp.windows.first { $0.canBecomeMain && $0.isVisible } }

    @objc func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindow { w.makeKeyAndOrderFront(nil) }
        else if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isMiniaturized }) { w.deminiaturize(nil) }
        else { openMain?() }
    }

    /// Réduit dans la barre de menus : ferme la fenêtre, l'appli continue de tourner.
    func hideToMenuBar() { mainWindow?.close() }

    @objc private func closeRemembering() { WindowMemory.closeRemembering() }
    @objc private func showAbout() { About.show() }
    @objc private func doRefresh() { refreshStats?() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
