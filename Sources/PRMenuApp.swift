import AppKit
import Combine
import SwiftUI

@main
struct PRMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var prService: PRService = {
        let (org, teams) = Self.resolveConfig()
        return PRService(orgFilter: org, teamFilters: teams)
    }()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var flashTimer: Timer?
    private var flashTick = 0
    private var eventMonitor: Any?

    /// Reads config from ~/.config/pr-menu/config.json, then lets CLI args override.
    private static func resolveConfig() -> (org: String?, teams: [String]) {
        // 1. Load config file defaults
        var org: String?
        var teams: [String] = []

        let configPath = NSString("~/.config/pr-menu/config.json").expandingTildeInPath
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            org = json["org"] as? String
            teams = json["teams"] as? [String] ?? []
        }

        // 2. CLI args override config file
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--org"), idx + 1 < args.count {
            org = args[idx + 1]
        }

        var cliTeams: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == "--team", i + 1 < args.count {
                cliTeams.append(args[i + 1])
                i += 2
            } else {
                i += 1
            }
        }
        if !cliTeams.isEmpty {
            teams = cliTeams
        }

        return (org, teams)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 480)
        popover.contentViewController = NSHostingController(rootView: PRListView(service: prService))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }

        prService.$myPRs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateIcon()
                }
            }
            .store(in: &cancellables)

        prService.$teamPRs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateIcon()
                }
            }
            .store(in: &cancellables)

        prService.$statusChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changed in
                guard changed else { return }

                Task { @MainActor [weak self] in
                    self?.flashIcon()
                }
            }
            .store(in: &cancellables)

        updateIcon()
        prService.startAutoRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        flashTimer?.invalidate()
        prService.stopAutoRefresh()
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        } else {
            prService.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)

            eventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.popover.performClose(nil)
                if let monitor = self?.eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    self?.eventMonitor = nil
                }
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else {
            return
        }

        button.image = MenuBarIcon.createIcon(status: prService.aggregateStatus)
        button.title = MenuBarIcon.badgeText(mine: prService.myPRs.count, team: prService.teamPRs.count) ?? ""
    }

    private func flashIcon() {
        flashTimer?.invalidate()
        flashTick = 0
        updateIcon()

        flashTimer = Timer.scheduledTimer(
            timeInterval: 0.3,
            target: self,
            selector: #selector(handleFlashTick),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func handleFlashTick() {
        guard let button = statusItem?.button else {
            flashTimer?.invalidate()
            flashTimer = nil
            return
        }

        if flashTick >= 8 {
            flashTimer?.invalidate()
            flashTimer = nil
            updateIcon()
            return
        }

        button.image = flashTick.isMultiple(of: 2)
            ? MenuBarIcon.createIcon(status: prService.aggregateStatus)
            : nil
        flashTick += 1
    }
}
