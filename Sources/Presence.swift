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
        let menu = NSMenu()
        let open = NSMenuItem(title: L.t("menubar.open"), action: #selector(showMain), keyEquivalent: "")
        let refresh = NSMenuItem(title: L.t("menubar.refresh"), action: #selector(doRefresh), keyEquivalent: "")
        let quit = NSMenuItem(title: L.t("menubar.quit"), action: #selector(quitApp), keyEquivalent: "")
        [open, refresh, quit].forEach { $0.target = self }
        menu.addItem(open); menu.addItem(refresh); menu.addItem(.separator()); menu.addItem(quit)
        it.menu = menu
    }

    /// Le fanion et ses ondes du logo, sans le carré sombre : fanion ambre, hampe grise, ondes bleues.
    /// Dessin dans le repère 1024 du logo (origine en haut), recadré sur le motif.
    static func silhouette(height: CGFloat = 18) -> NSImage {
        let box = CGRect(x: 246, y: 186, width: 672, height: 672)
        let img = NSImage(size: NSSize(width: height, height: height), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: rect.width / box.width, y: rect.height / box.height)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            let amber = NSColor(red: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255, alpha: 1)
            let blue = NSColor(red: 0x0e / 255, green: 0xa5 / 255, blue: 0xe9 / 255, alpha: 1)
            // hampe
            NSColor(white: 0.62, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: 262, y: 204, width: 34, height: 600), xRadius: 17, yRadius: 17).fill()
            // fanion à queue fendue
            amber.setFill()
            let flag = NSBezierPath()
            flag.move(to: CGPoint(x: 296, y: 224)); flag.line(to: CGPoint(x: 640, y: 224)); flag.line(to: CGPoint(x: 560, y: 374))
            flag.line(to: CGPoint(x: 640, y: 524)); flag.line(to: CGPoint(x: 296, y: 524)); flag.close(); flag.fill()
            // « H » découpé dans le fanion
            ctx.setBlendMode(.clear)
            let h = NSAttributedString(string: "H", attributes: [.font: NSFont.systemFont(ofSize: 210, weight: .heavy), .foregroundColor: NSColor.black])
            let hs = h.size()
            h.draw(at: CGPoint(x: 420 - hs.width / 2, y: 368 - hs.height / 2))
            ctx.setBlendMode(.normal)
            // ondes d'annonce
            for (i, r) in [120.0, 200.0, 280.0].enumerated() {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: CGPoint(x: 600, y: 664), radius: r, startAngle: -40, endAngle: 40, clockwise: false)
                arc.lineWidth = 40 - CGFloat(i) * 6
                arc.lineCapStyle = .round
                blue.withAlphaComponent(1 - CGFloat(i) * 0.25).setStroke()
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
        if let w = mainWindow { w.makeKeyAndOrderFront(nil) } else { openMain?() }
    }

    /// Réduit dans la barre de menus : ferme la fenêtre, l'appli continue de tourner.
    func hideToMenuBar() { mainWindow?.close() }

    @objc private func doRefresh() { refreshStats?() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
