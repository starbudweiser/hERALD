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
        // icône de l'appli en couleur (pas une image « modèle » monochrome)
        let img = (NSApp.applicationIconImage.copy() as? NSImage) ?? NSImage()
        img.size = NSSize(width: 20, height: 20)
        img.isTemplate = false
        it.button?.image = img
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
