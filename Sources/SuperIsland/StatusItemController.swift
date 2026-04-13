import AppKit
import SwiftUI
import SuperIslandCore

enum StatusItemPresentation: Equatable {
    case hidden
    case menu
    case popover
    case listPopover
}

struct MenuBarStatusSummary: Equatable {
    enum Tone: Equatable {
        case idle
        case active
        case waiting
        case complete
    }

    let text: String
    let sessionCount: Int
    let tone: Tone
    let tooltip: String
    let source: String?
}

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var popoverHostingController: NSHostingController<MenuBarPopoverView>?
    private var popoverAppStateID: ObjectIdentifier?
    private var popoverMode: MenuBarPopoverView.Mode?
    private var eventMonitor: Any?
    private weak var appState: AppState?
    private var presentation: StatusItemPresentation = .hidden
    private var refreshTimer: Timer?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 430, height: 560)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItemAppearance()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func bind(appState: AppState) {
        self.appState = appState
        ensurePopoverContent()
        refreshStatusItemAppearance()
    }

    func syncVisibility(resolvedDisplayMode: DisplayMode) {
        let targetPresentation = Self.resolvedPresentation(resolvedDisplayMode: resolvedDisplayMode)
        applyPresentation(targetPresentation)
    }

    func showPopover() {
        guard presentation == .popover || presentation == .listPopover else { return }
        ensureStatusItem()
        ensurePopoverContent()
        refreshStatusItemAppearance()
        guard let button = statusItem?.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    nonisolated static func summary(
        sessions: [String: SessionSnapshot],
        activeSessionId: String?,
        surface: IslandSurface,
        showDetail: Bool
    ) -> MenuBarStatusSummary? {
        guard !sessions.isEmpty else {
            return showDetail ? nil : MenuBarStatusSummary(
                text: "",
                sessionCount: 0,
                tone: .idle,
                tooltip: "SuperIsland",
                source: nil
            )
        }

        let sessionCount = sessions.count

        let pendingEntry = sessions.first { _, session in
            session.status == .waitingApproval || session.status == .waitingQuestion
        }

        let activeSession = activeSessionId.flatMap { sessions[$0] }
            ?? pendingEntry?.value
            ?? sessions.values
                .sorted {
                    if $0.lastActivity != $1.lastActivity {
                        return $0.lastActivity > $1.lastActivity
                    }
                    return $0.projectDisplayName < $1.projectDisplayName
                }
                .first

        guard let activeSession else {
            return MenuBarStatusSummary(
                text: showDetail ? "\(sessionCount)" : "",
                sessionCount: sessionCount,
                tone: .idle,
                tooltip: "SuperIsland",
                source: nil
            )
        }

        let tone: MenuBarStatusSummary.Tone
        let prefix: String

        if case .completionCard = surface {
            tone = .complete
            prefix = "DONE"
        } else if activeSession.status == .waitingApproval || activeSession.status == .waitingQuestion {
            tone = .waiting
            prefix = activeSession.status == .waitingApproval ? "WAIT" : "ASK"
        } else if activeSession.status == .processing || activeSession.status == .running {
            tone = .active
            prefix = "RUN"
        } else {
            tone = .idle
            prefix = "IDLE"
        }

        let title = activeSession.displayTitle(sessionId: activeSession.providerSessionId ?? activeSessionId ?? "")
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryLabel: String

        switch tone {
        case .waiting, .active:
            let detail = activeSession.currentTool ?? activeSession.toolDescription ?? trimmedTitle
            primaryLabel = detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? activeSession.sourceLabel
                : detail
        case .complete, .idle:
            primaryLabel = trimmedTitle.isEmpty ? activeSession.sourceLabel : trimmedTitle
        }

        let truncatedPrimary = Self.truncate(primaryLabel, limit: 26)
        let project = Self.truncate(activeSession.projectDisplayName, limit: 18)
        let text = showDetail
            ? [prefix, project, truncatedPrimary].filter { !$0.isEmpty }.joined(separator: " · ")
            : ""

        let tooltip = [prefix, activeSession.projectDisplayName, primaryLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return MenuBarStatusSummary(
            text: text,
            sessionCount: sessionCount,
            tone: tone,
            tooltip: tooltip,
            source: activeSession.source
        )
    }

    nonisolated static func resolvedPresentation(
        resolvedDisplayMode: DisplayMode
    ) -> StatusItemPresentation {
        if resolvedDisplayMode == .menuBar {
            return .popover
        }
        return .listPopover
    }

    private func applyPresentation(_ targetPresentation: StatusItemPresentation) {
        guard targetPresentation != presentation else {
            if targetPresentation != .hidden {
                ensureStatusItem()
                configureButton()
                refreshStatusItemAppearance()
            }
            return
        }

        presentation = targetPresentation

        switch targetPresentation {
        case .hidden:
            closePopover()
            stopEventMonitor()
            removeStatusItem()
        case .menu, .popover, .listPopover:
            ensureStatusItem()
            configureButton()
            refreshStatusItemAppearance()
            if targetPresentation == .popover || targetPresentation == .listPopover {
                startEventMonitor()
            } else {
                stopEventMonitor()
                closePopover()
            }
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let length = usesDetailText ? NSStatusItem.variableLength : NSStatusItem.squareLength
        statusItem = NSStatusBar.system.statusItem(withLength: length)
    }

    private func recreateStatusItemIfNeeded() {
        guard let statusItem else { return }
        let desiredLength = usesDetailText ? NSStatusItem.variableLength : NSStatusItem.squareLength
        guard statusItem.length != desiredLength else { return }

        removeStatusItem()
        ensureStatusItem()
        configureButton()
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private var usesDetailText: Bool {
        presentation == .popover && SettingsManager.shared.menuBarShowDetail
    }

    private func configureButton() {
        recreateStatusItemIfNeeded()
        guard let button = statusItem?.button else { return }

        button.image = renderStatusIcon(
            source: currentSummary?.source,
            tone: currentSummary?.tone ?? .idle
        )
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = currentSummary?.tooltip ?? "SuperIsland"
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = usesDetailText ? .imageTrailing : .imageOnly

        switch presentation {
        case .popover:
            button.target = self
            button.action = #selector(togglePopoverFromStatusItem(_:))
            statusItem?.menu = nil
        case .listPopover:
            button.target = self
            button.action = #selector(togglePopoverFromStatusItem(_:))
            statusItem?.menu = nil
        case .menu:
            button.target = nil
            button.action = nil
            statusItem?.menu = makeMenu()
        case .hidden:
            break
        }
    }

    private func refreshStatusItemAppearance() {
        guard presentation != .hidden else { return }
        guard let button = statusItem?.button else { return }

        ensurePopoverContent()
        let summary = currentSummary
        configureButton()

        guard usesDetailText, let summary else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            return
        }

        let result = NSMutableAttributedString(string: " ")
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.72),
        ]
        result.append(NSAttributedString(string: summary.text, attributes: textAttributes))

        if summary.sessionCount > 1 {
            let countAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.45),
            ]
            result.append(NSAttributedString(string: " (\(summary.sessionCount))", attributes: countAttributes))
        }

        result.append(NSAttributedString(string: " "))
        button.attributedTitle = result
    }

    private var currentSummary: MenuBarStatusSummary? {
        guard let appState else { return nil }
        return Self.summary(
            sessions: appState.sessions,
            activeSessionId: appState.activeSessionId,
            surface: appState.surface,
            showDetail: SettingsManager.shared.menuBarShowDetail
        )
    }

    private func ensurePopoverContent() {
        guard let appState else { return }
        let appStateID = ObjectIdentifier(appState)
        let mode = desiredPopoverMode

        if let hostingController = popoverHostingController,
           !Self.needsPopoverContentRebuild(
                existingAppStateID: popoverAppStateID,
                newAppStateID: appStateID,
                existingMode: popoverMode,
                newMode: mode
           ) {
            if popover.contentViewController !== hostingController {
                popover.contentViewController = hostingController
            }
            return
        }

        let hostingController = NSHostingController(rootView: MenuBarPopoverView(appState: appState, mode: mode))
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 430, height: 560)
        popover.contentViewController = hostingController
        popoverHostingController = hostingController
        popoverAppStateID = appStateID
        popoverMode = mode
    }

    nonisolated static func needsPopoverContentRebuild(
        existingAppStateID: ObjectIdentifier?,
        newAppStateID: ObjectIdentifier,
        existingMode: MenuBarPopoverView.Mode?,
        newMode: MenuBarPopoverView.Mode
    ) -> Bool {
        existingAppStateID != newAppStateID || existingMode != newMode
    }

    private var desiredPopoverMode: MenuBarPopoverView.Mode {
        switch presentation {
        case .listPopover:
            return .sessionListOnly
        case .hidden, .menu, .popover:
            return .contextual
        }
    }

    private func startEventMonitor() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: L10n.shared["settings_ellipsis"],
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.shared["quit"],
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func togglePopoverFromStatusItem(_ sender: Any?) {
        togglePopover()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    nonisolated private static func truncate(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(0, limit - 1))) + "…"
    }

    private func renderStatusIcon(source: String?, tone: MenuBarStatusSummary.Tone) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let icon = source.flatMap { cliIcon(source: $0, size: 18) } ?? SettingsWindowController.bundleAppIcon()
        icon.size = size

        let image = NSImage(size: size)
        image.lockFocus()

        icon.draw(in: NSRect(origin: .zero, size: size))

        let badgeColor: NSColor? = {
            switch tone {
            case .idle:
                return nil
            case .active:
                return NSColor.systemGreen
            case .waiting:
                return NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.22, alpha: 1)
            case .complete:
                return NSColor.systemBlue
            }
        }()

        if let badgeColor {
            let badgeRect = NSRect(x: 11, y: 0.5, width: 6.5, height: 6.5)
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1)).fill()
            badgeColor.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
        }

        image.unlockFocus()
        return image
    }
}
