import AppKit
import Combine
import Darwin
import SwiftUI

@main
struct CodexAccountSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
                .frame(width: 420)
                .padding(20)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var statusItemObservation: AnyCancellable?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isPrimaryAppInstance else {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        appState.setSettingsOpener { [weak self] in
            self?.showSettingsWindow()
        }
        configurePopover()
        configureStatusItem()
        appState.requestNotificationAuthorization()
        sendRequestedTestNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView()
                .environmentObject(appState)
                .frame(width: 360)
        )
    }

    private func configureStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: 34)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
        updateStatusItem()
        observeStatusItemState()
    }

    private func observeStatusItemState() {
        statusItemObservation = appState.$accounts
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let meterState = MenuBarQuotaMeterState(activeAccount: appState.activeAccount)
        var image: NSImage?
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            image = MenuBarIcon.multiAuthWithFiveHourMeter(state: meterState)
        }
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Codex Account Switcher - \(meterState.accessibilityDescription)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showSettingsWindow() {
        let window: NSWindow

        if let settingsWindow {
            window = settingsWindow
        } else {
            let hostingController = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(appState)
                    .frame(width: 420)
                    .padding(20)
            )

            window = NSWindow(contentViewController: hostingController)
            window.title = "Codex Account Switcher Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func sendRequestedTestNotifications() {
        guard CommandLine.arguments.contains("--test-auto-switch-notification") else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            appState.sendTestAutoSwitchNotification()
        }
    }

    private var isPrimaryAppInstance: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentProcessID = getpid()
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .allSatisfy { $0.processIdentifier == currentProcessID }
    }
}
