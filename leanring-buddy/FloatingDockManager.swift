//
//  FloatingDockManager.swift
//  leanring-buddy
//
//  Manages an always-visible, draggable floating dock that hosts the full
//  CompanionPanelView. Unlike the menu bar drop-down (MenuBarPanelManager),
//  this panel stays on screen persistently so the companion controls are always
//  one glance away. The user can drag it anywhere by its background, and its
//  position is remembered across launches.
//
//  The dock is a non-activating panel (it never steals focus from the user's
//  current app) that can still become key, so the email text field inside the
//  panel can receive keyboard focus. App-owned windows like this one are
//  automatically excluded from the screenshots sent to Claude (see
//  CompanionScreenCaptureUtility), so the dock never pollutes what the AI sees.
//

import AppKit
import SwiftUI

/// NSPanel subclass that can become key even though it is a non-activating
/// panel, so text fields inside CompanionPanelView can receive focus without
/// the whole app activating and stealing focus from the user's current window.
private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class FloatingDockManager: NSObject {
    private var panel: NSPanel?
    private let companionManager: CompanionManager
    private let dockWidth: CGFloat = 320

    /// Gap between the top of the dock and the top of the screen's visible area
    /// (just below the menu bar) when the dock sits at its default location.
    private let topGapBelowMenuBar: CGFloat = 8

    /// UserDefaults key for the remembered dock position. We store the TOP-left
    /// corner (not AppKit's bottom-left origin) so the dock keeps its top edge
    /// anchored in place even as its content height changes.
    private let savedTopLeftDefaultsKey = "ClickyFloatingDockTopLeft"

    /// Guards the move/resize observers against frame changes that we make
    /// ourselves, so our own repositioning is never mistaken for a user drag.
    private var isProgrammaticallyAdjustingFrame = false

    private var didMoveObserver: NSObjectProtocol?
    private var didResizeObserver: NSObjectProtocol?

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        super.init()
    }

    deinit {
        if let didMoveObserver {
            NotificationCenter.default.removeObserver(didMoveObserver)
        }
        if let didResizeObserver {
            NotificationCenter.default.removeObserver(didResizeObserver)
        }
    }

    /// Creates (if needed) and shows the always-visible floating dock.
    func show() {
        if panel == nil {
            createPanel()
        }
        panel?.orderFrontRegardless()
    }

    // MARK: - Panel Construction

    private func createPanel() {
        // The dock hosts the full companion panel but hides the close (X) button,
        // because the dock is meant to stay on screen persistently. The menu bar
        // icon remains available as the dismissible secondary entry point.
        let dockContent = CompanionPanelView(
            companionManager: companionManager,
            showsDismissButton: false
        )

        // NSHostingController keeps the panel sized to the SwiftUI content's ideal
        // size and updates it as the content height changes (e.g. when permissions
        // are granted or onboarding advances).
        let hostingController = NSHostingController(rootView: dockContent)
        hostingController.sizingOptions = [.preferredContentSize]

        let measuredHeight = hostingController.view.fittingSize.height
        let initialContentHeight = measuredHeight > 1 ? measuredHeight : 400

        let dockPanel = DockPanel(
            contentRect: NSRect(x: 0, y: 0, width: dockWidth, height: initialContentHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dockPanel.contentViewController = hostingController

        dockPanel.isFloatingPanel = true
        dockPanel.level = .floating
        dockPanel.isOpaque = false
        dockPanel.backgroundColor = .clear
        // CompanionPanelView draws its own rounded card and shadow, so the window
        // must not add a second (square) shadow of its own.
        dockPanel.hasShadow = false
        dockPanel.hidesOnDeactivate = false
        dockPanel.isExcludedFromWindowsMenu = true
        dockPanel.isReleasedWhenClosed = false
        dockPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Let the user drag the dock anywhere by clicking and dragging its
        // background. Interactive controls (buttons, text field) still work; only
        // drags that start on empty background move the window.
        dockPanel.isMovableByWindowBackground = true
        dockPanel.titleVisibility = .hidden
        dockPanel.titlebarAppearsTransparent = true

        panel = dockPanel

        positionAtSavedOrDefaultLocation()
        installFrameObservers()
    }

    // MARK: - Positioning

    private func positionAtSavedOrDefaultLocation() {
        guard let panel else { return }
        let panelHeight = panel.frame.height
        let desiredTopLeft = savedTopLeft() ?? defaultTopLeft()
        setPanelTopLeft(desiredTopLeft, panelHeight: panelHeight)
    }

    /// Default dock location: horizontally centered, near the top of the main
    /// screen just below the menu bar.
    private func defaultTopLeft() -> CGPoint {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let topLeftX = visibleFrame.midX - (dockWidth / 2)
        let topLeftY = visibleFrame.maxY - topGapBelowMenuBar
        return CGPoint(x: topLeftX, y: topLeftY)
    }

    /// Positions the panel so its TOP-left corner sits at `topLeft`, clamped to
    /// stay on screen. AppKit windows use a bottom-left origin, so we convert the
    /// top-left point to a bottom-left origin here.
    private func setPanelTopLeft(_ topLeft: CGPoint, panelHeight: CGFloat) {
        guard let panel else { return }
        let clampedTopLeft = clampTopLeftToScreen(topLeft, panelHeight: panelHeight)
        let bottomLeftOrigin = CGPoint(x: clampedTopLeft.x, y: clampedTopLeft.y - panelHeight)
        let newFrame = NSRect(origin: bottomLeftOrigin, size: CGSize(width: dockWidth, height: panelHeight))

        // The move/resize observers run synchronously while we change the frame,
        // so flip the guard around the call to ignore our own adjustment.
        isProgrammaticallyAdjustingFrame = true
        panel.setFrame(newFrame, display: true)
        isProgrammaticallyAdjustingFrame = false
    }

    /// Keeps the dock fully within the visible area of whichever screen it sits on.
    private func clampTopLeftToScreen(_ topLeft: CGPoint, panelHeight: CGFloat) -> CGPoint {
        let visibleFrame = screen(forTopLeft: topLeft).visibleFrame

        let clampedX = max(visibleFrame.minX, min(topLeft.x, visibleFrame.maxX - dockWidth))
        let minTopY = visibleFrame.minY + panelHeight
        let maxTopY = visibleFrame.maxY
        let clampedTopY = max(minTopY, min(topLeft.y, maxTopY))

        return CGPoint(x: clampedX, y: clampedTopY)
    }

    /// Finds the screen that contains the dock's top-left corner, falling back to
    /// the main screen (then any screen) when the point is off all screens.
    private func screen(forTopLeft topLeft: CGPoint) -> NSScreen {
        let samplePoint = CGPoint(x: topLeft.x + dockWidth / 2, y: topLeft.y - 1)
        return NSScreen.screens.first { $0.frame.contains(samplePoint) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - Dragging + Dynamic Resize

    private func installFrameObservers() {
        guard let panel else { return }

        // Remember where the user drags the dock so it returns there next launch.
        // queue: nil delivers the notification synchronously on the main thread,
        // which keeps the isProgrammaticallyAdjustingFrame guard deterministic.
        didMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isProgrammaticallyAdjustingFrame else { return }
                self.saveCurrentTopLeft()
            }
        }

        // When the SwiftUI content changes height, AppKit resizes the window. Keep
        // the dock's TOP edge anchored where the user left it instead of letting it
        // drift, then re-clamp it to stay on screen.
        didResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isProgrammaticallyAdjustingFrame else { return }
                self.reanchorTopAfterContentResize()
            }
        }
    }

    private func reanchorTopAfterContentResize() {
        guard let panel else { return }
        let desiredTopLeft = savedTopLeft() ?? defaultTopLeft()
        setPanelTopLeft(desiredTopLeft, panelHeight: panel.frame.height)
    }

    // MARK: - Position Persistence

    private func saveCurrentTopLeft() {
        guard let panel else { return }
        let frame = panel.frame
        let topLeft = CGPoint(x: frame.minX, y: frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: savedTopLeftDefaultsKey)
    }

    private func savedTopLeft() -> CGPoint? {
        guard let storedValue = UserDefaults.standard.string(forKey: savedTopLeftDefaultsKey) else {
            return nil
        }
        return NSPointFromString(storedValue)
    }
}
