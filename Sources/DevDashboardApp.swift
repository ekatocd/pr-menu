import AppKit
import Combine
import SwiftUI

@main
struct DevDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prService = PRService()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var flashTimer: Timer?
    private var flashTick = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.contentViewController = NSHostingController(rootView: PRListView(service: prService))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }

        prService.$pullRequests
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
        } else {
            prService.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else {
            return
        }

        button.image = MenuBarIcon.createIcon(status: prService.aggregateStatus)
        button.title = MenuBarIcon.badgeText(for: prService.pullRequests.count) ?? ""
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
