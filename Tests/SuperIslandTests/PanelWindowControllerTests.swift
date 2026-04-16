import AppKit
import XCTest
@testable import SuperIsland

final class PanelWindowControllerTests: XCTestCase {
    func testPanelGeometryCentersFrameWhenHorizontalDragDisabled() {
        let frame = PanelGeometry.panelFrame(
            panelSize: NSSize(width: 420, height: 180),
            screenFrame: CGRect(x: 100, y: 50, width: 1440, height: 900),
            allowHorizontalDrag: false,
            storedHorizontalOffset: 120
        )

        XCTAssertEqual(frame.origin.x, 610, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 770, accuracy: 0.001)
    }

    func testPanelGeometryClampsDraggedPanelInsideScreenBounds() {
        let origin = PanelGeometry.draggedFrameOrigin(
            startPanelX: 300,
            mouseDeltaX: 2000,
            panelSize: NSSize(width: 420, height: 180),
            screenFrame: CGRect(x: 100, y: 50, width: 1440, height: 900)
        )

        XCTAssertEqual(origin.x, 1120, accuracy: 0.001)
        XCTAssertEqual(origin.y, 770, accuracy: 0.001)
    }

    func testPanelGeometryPersistsOffsetRelativeToCenteredPosition() {
        let offset = PanelGeometry.persistedHorizontalOffset(
            panelOriginX: 700,
            panelWidth: 420,
            screenFrame: CGRect(x: 100, y: 50, width: 1440, height: 900)
        )

        XCTAssertEqual(offset, 90, accuracy: 0.001)
    }

    func testPanelGeometryDragThresholdRequiresIntentionalMovement() {
        XCTAssertFalse(PanelGeometry.shouldStartDrag(deltaX: 5))
        XCTAssertTrue(PanelGeometry.shouldStartDrag(deltaX: 5.1))
        XCTAssertTrue(PanelGeometry.shouldStartDrag(deltaX: -8))
    }

    func testPanelEnvironmentMonitorRefreshesWhenSelectionPreferenceChanges() {
        XCTAssertTrue(
            PanelEnvironmentMonitor.needsScreenRefresh(
                previousPreferenceSignature: "automatic",
                newPreferenceSignature: "specificScreen|1|Studio Display",
                previousNotchWidthOverride: 0,
                newNotchWidthOverride: 0
            )
        )
    }

    func testPanelEnvironmentMonitorRefreshesWhenNotchOverrideChanges() {
        XCTAssertTrue(
            PanelEnvironmentMonitor.needsScreenRefresh(
                previousPreferenceSignature: "automatic",
                newPreferenceSignature: "automatic",
                previousNotchWidthOverride: 0,
                newNotchWidthOverride: 188
            )
        )
    }

    func testPanelEnvironmentMonitorSkipsRefreshWhenSelectionInputsMatch() {
        XCTAssertFalse(
            PanelEnvironmentMonitor.needsScreenRefresh(
                previousPreferenceSignature: "automatic",
                newPreferenceSignature: "automatic",
                previousNotchWidthOverride: 0,
                newNotchWidthOverride: 0
            )
        )
    }

    func testPanelSpaceTransitionEntersFullscreenImmediately() {
        XCTAssertEqual(
            PanelEnvironmentMonitor.spaceTransition(
                isFullscreen: true,
                fullscreenLatch: false
            ),
            .enterFullscreen
        )
    }

    func testPanelSpaceTransitionWaitsForExitWhenLatched() {
        XCTAssertEqual(
            PanelEnvironmentMonitor.spaceTransition(
                isFullscreen: false,
                fullscreenLatch: true
            ),
            .waitForFullscreenExit
        )
    }

    func testPanelSpaceTransitionUpdatesVisibilityWhenNotFullscreenAndNotLatched() {
        XCTAssertEqual(
            PanelEnvironmentMonitor.spaceTransition(
                isFullscreen: false,
                fullscreenLatch: false
            ),
            .updateVisible
        )
    }

    func testResolvedPresentationModeUsesMenuBarForExplicitMenuBarOnSingleScreen() {
        XCTAssertEqual(
            PanelWindowController.resolvedPresentationMode(
                displayMode: .menuBar,
                hasPhysicalNotch: true,
                screenCount: 1
            ),
            .menuBar
        )
    }

    func testResolvedPresentationModeUsesMenuBarForAutoOnSingleScreenWithoutNotch() {
        XCTAssertEqual(
            PanelWindowController.resolvedPresentationMode(
                displayMode: .auto,
                hasPhysicalNotch: false,
                screenCount: 1
            ),
            .menuBar
        )
    }

    func testExpandedPanelHeightUsesDynamicSessionDetailEstimate() {
        let height = PanelWindowController.expandedPanelHeight(
            surface: .sessionDetail(sessionId: "done"),
            collapsedHeight: 46,
            maxPanelHeight: 560,
            screenHeight: 900,
            maxVisibleSessions: 5,
            detailEstimatedHeight: 480
        )

        XCTAssertEqual(height, 480, accuracy: 0.001)
    }

    func testExpandedPanelHeightTreatsCompletionCardLikeDetailSurface() {
        let height = PanelWindowController.expandedPanelHeight(
            surface: .completionCard(sessionId: "done"),
            collapsedHeight: 46,
            maxPanelHeight: 560,
            screenHeight: 900,
            maxVisibleSessions: 5,
            detailEstimatedHeight: 430
        )

        XCTAssertEqual(height, 430, accuracy: 0.001)
    }

    func testExpandedPanelHeightStillUsesConfiguredMaximumAsClamp() {
        let height = PanelWindowController.expandedPanelHeight(
            surface: .sessionDetail(sessionId: "done"),
            collapsedHeight: 46,
            maxPanelHeight: 420,
            screenHeight: 900,
            maxVisibleSessions: 5,
            detailEstimatedHeight: 480
        )

        XCTAssertEqual(height, 420, accuracy: 0.001)
    }

    func testExpandedPanelHeightCapsSessionDetailAtConfiguredScreenRatio() {
        let height = PanelWindowController.expandedPanelHeight(
            surface: .sessionDetail(sessionId: "done"),
            collapsedHeight: 46,
            maxPanelHeight: 560,
            screenHeight: 600,
            maxVisibleSessions: 5,
            detailEstimatedHeight: 480
        )

        XCTAssertEqual(height, 384, accuracy: 0.001)
    }

    func testExpandedPanelHeightLeavesExtraBreathingRoomForSessionList() {
        let height = PanelWindowController.expandedPanelHeight(
            surface: .sessionList,
            collapsedHeight: 46,
            maxPanelHeight: 600,
            screenHeight: 900,
            maxVisibleSessions: 5
        )

        XCTAssertEqual(height, 526, accuracy: 0.001)
    }

    func testAutomaticPresentationActivationModeStaysPassiveWhenAppIsBackgrounded() {
        // Background completion cards must not reactivate the app.
        XCTAssertFalse(
            PanelWindowController.automaticPresentationActivationMode(appIsActive: false)
        )
    }

    func testAutomaticPresentationActivationModeStaysInteractiveWhenAppIsForeground() {
        // Foreground refreshes can keep the panel interactive for normal use.
        XCTAssertTrue(
            PanelWindowController.automaticPresentationActivationMode(appIsActive: true)
        )
    }

    func testDirectPanelClickOnlyPromotesPanelWindow() {
        // Panel clicks should not raise unrelated windows like Settings.
        XCTAssertEqual(
            KeyablePanel.directClickActivationPolicy(),
            .panelOnly
        )
    }

    func testScreenHopMotionUsesMoreVisibleTiming() {
        let motion = PanelWindowController.screenHopMotion()

        XCTAssertEqual(motion.outgoingOffset, 18)
        XCTAssertEqual(motion.incomingOffset, 30)
        XCTAssertEqual(motion.fadeOutDuration, 0.14, accuracy: 0.001)
        XCTAssertEqual(motion.incomingPauseDuration, 0.06, accuracy: 0.001)
        XCTAssertEqual(motion.fadeInDuration, 0.34, accuracy: 0.001)
    }

    func testScreenHopFramesRetractOldFrameAndDropIntoNewFrame() {
        let oldFrame = NSRect(x: 100, y: 820, width: 420, height: 180)
        let newFrame = NSRect(x: 1800, y: 900, width: 420, height: 180)

        let frames = PanelWindowController.screenHopFrames(
            oldFrame: oldFrame,
            newFrame: newFrame
        )

        XCTAssertEqual(frames.outgoing.origin.x, oldFrame.origin.x)
        XCTAssertEqual(frames.outgoing.origin.y, oldFrame.origin.y + 18)
        XCTAssertEqual(frames.outgoing.size, oldFrame.size)

        XCTAssertEqual(frames.incoming.origin.x, newFrame.origin.x)
        XCTAssertEqual(frames.incoming.origin.y, newFrame.origin.y + 30)
        XCTAssertEqual(frames.incoming.size, newFrame.size)
    }

    func testReplaceMonitorRemovesExistingMonitorBeforeAssigningNewOne() {
        final class MonitorBox {}

        let oldMonitor = MonitorBox()
        let newMonitor = MonitorBox()
        var currentMonitor: Any? = oldMonitor
        var removedMonitors: [ObjectIdentifier] = []

        PanelWindowController.replaceMonitor(
            currentMonitor: &currentMonitor,
            newMonitor: newMonitor,
            removeMonitor: { monitor in
                removedMonitors.append(ObjectIdentifier(monitor as AnyObject))
            }
        )

        XCTAssertEqual(removedMonitors, [ObjectIdentifier(oldMonitor)])
        XCTAssertTrue((currentMonitor as AnyObject?) === newMonitor)
    }
}
