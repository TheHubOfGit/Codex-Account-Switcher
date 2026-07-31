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
                .frame(width: 480, height: 640)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var statusItemObservation: AnyCancellable?
    private var appearanceObservation: AnyCancellable?
    private var paceObservation: AnyCancellable?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var popoverPreviewWindow: NSWindow?
    private var pendingPopoverPreviewHeight: CGFloat?

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
        sendRequestedTestNotifications()
        showRequestedPopoverPreview()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(
            width: PopoverSizing.width,
            height: PopoverSizing.minimumHeight
        )
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(
                onPreferredHeightChange: { [weak self] preferredHeight in
                    self?.updatePopoverHeight(preferredHeight)
                },
                onAccountSwitchRequested: { [weak self] account in
                    self?.beginAccountSwitch(account)
                }
            )
                .environmentObject(appState)
                .frame(width: PopoverSizing.width)
        )
    }

    private func updatePopoverHeight(_ preferredHeight: CGFloat) {
        guard !appState.isSwitching else { return }

        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let availableHeight = screen?.visibleFrame.height ?? 620
        let nextHeight = PopoverSizing.height(
            contentHeight: preferredHeight,
            availableScreenHeight: availableHeight
        )
        guard abs(popover.contentSize.height - nextHeight) >= 1 else { return }
        popover.contentSize = NSSize(width: PopoverSizing.width, height: nextHeight)
    }

    private func beginAccountSwitch(_ account: AccountSnapshot) {
        // The active account changes the list ordering and preferred popover
        // height. Close the transient AppKit surface before that SwiftUI state
        // mutation so AppKit never tries to animate a moving, resizing popover
        // while Codex is also being relaunched.
        popover.performClose(nil)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            await appState.switchToAccount(account)
        }
    }

    private func configureStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: 22)
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

        appearanceObservation = NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }

        paceObservation = Timer.publish(every: 15 * 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let meterState = MenuBarQuotaMeterState(
            activeAccount: appState.activeAccount,
            accounts: appState.accounts
        )
        var image: NSImage?
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            image = MenuBarIcon.paceRing(state: meterState)
        }
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Codex Account Switcher - \(meterState.accessibilityDescription)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            appState.popoverDidOpen()
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
                    .frame(width: 480, height: 640)
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

    private func showRequestedPopoverPreview() {
        guard CommandLine.arguments.contains("--show-popover-preview") else {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            let hostingController = NSHostingController(
                rootView: MenuContentView(
                    onPreferredHeightChange: { [weak self] preferredHeight in
                        self?.updatePopoverPreviewHeight(preferredHeight)
                    }
                )
                .environmentObject(appState)
                .frame(width: PopoverSizing.width)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Codex Account Switcher"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(
                NSSize(width: PopoverSizing.width, height: PopoverSizing.minimumHeight)
            )
            window.center()
            popoverPreviewWindow = window
            updatePopoverPreviewHeight(
                pendingPopoverPreviewHeight ?? PopoverSizing.minimumHeight
            )
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func updatePopoverPreviewHeight(_ preferredHeight: CGFloat) {
        guard let window = popoverPreviewWindow else {
            pendingPopoverPreviewHeight = preferredHeight
            return
        }
        let height = PopoverSizing.height(
            contentHeight: preferredHeight,
            availableScreenHeight: 2_000
        )
        window.setContentSize(NSSize(width: PopoverSizing.width, height: height))
        window.center()
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
