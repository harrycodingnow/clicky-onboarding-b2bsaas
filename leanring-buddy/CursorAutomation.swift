//
//  CursorAutomation.swift
//  leanring-buddy
//
//  Controls the REAL macOS pointer: glides it to a target location and clicks.
//  Used by the onboarding "Show me" action so Clicky actually performs the
//  step for the new employee, instead of only pointing at it visually.
//
//  Posting synthetic mouse events requires Accessibility permission, which the
//  app already requests for its global push-to-talk shortcut. Without that
//  permission macOS silently drops the events.
//

import AppKit
import CoreGraphics

@MainActor
enum CursorAutomation {

  /// Smoothly glides the real cursor from its current position to the target
  /// (an AppKit global point, bottom-left origin) and performs a left click.
  /// The glide is purely cosmetic so the user can see what Clicky is doing.
  static func glideAndClick(toAppKitGlobalPoint appKitGlobalPoint: CGPoint) async {
    let targetCoreGraphicsPoint = convertAppKitGlobalToCoreGraphicsGlobal(appKitGlobalPoint)
    let startingCoreGraphicsPoint = convertAppKitGlobalToCoreGraphicsGlobal(NSEvent.mouseLocation)

    // Glide the cursor along an eased path so the motion looks deliberate
    // rather than teleporting straight to the target.
    let totalGlideSteps = 60
    for currentStep in 1...totalGlideSteps {
      let linearProgress = CGFloat(currentStep) / CGFloat(totalGlideSteps)
      let easedProgress = easeInOutProgress(linearProgress)
      let interpolatedPoint = CGPoint(
        x: startingCoreGraphicsPoint.x + (targetCoreGraphicsPoint.x - startingCoreGraphicsPoint.x)
          * easedProgress,
        y: startingCoreGraphicsPoint.y + (targetCoreGraphicsPoint.y - startingCoreGraphicsPoint.y)
          * easedProgress
      )
      moveCursor(toCoreGraphicsPoint: interpolatedPoint)
      try? await Task.sleep(nanoseconds: 8_000_000)  // ~8ms per step → ~0.5s glide
    }

    // Land exactly on target, pause briefly so the destination is obvious,
    // then click.
    moveCursor(toCoreGraphicsPoint: targetCoreGraphicsPoint)
    try? await Task.sleep(nanoseconds: 150_000_000)
    leftClick(atCoreGraphicsPoint: targetCoreGraphicsPoint)
  }

  /// Converts an AppKit global point (bottom-left origin, primary screen at
  /// the bottom-left) to a Core Graphics global point (top-left origin) used
  /// by CGEvent. The y-flip is anchored at the primary display's height,
  /// which holds across multi-monitor arrangements.
  private static func convertAppKitGlobalToCoreGraphicsGlobal(_ appKitGlobalPoint: CGPoint)
    -> CGPoint
  {
    let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    let primaryDisplayHeight = primaryScreen?.frame.height ?? 0
    return CGPoint(x: appKitGlobalPoint.x, y: primaryDisplayHeight - appKitGlobalPoint.y)
  }

  /// Moves the system cursor to an absolute Core Graphics global point by
  /// posting a `.mouseMoved` event. Posting an absolute-position event both
  /// relocates the visible cursor and lets apps update their hover state.
  private static func moveCursor(toCoreGraphicsPoint coreGraphicsPoint: CGPoint) {
    guard
      let moveEvent = CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: coreGraphicsPoint,
        mouseButton: .left
      )
    else {
      return
    }
    moveEvent.post(tap: .cghidEventTap)
  }

  /// Posts a left mouse down + up at the given Core Graphics global point.
  private static func leftClick(atCoreGraphicsPoint coreGraphicsPoint: CGPoint) {
    guard
      let mouseDownEvent = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseDown,
        mouseCursorPosition: coreGraphicsPoint,
        mouseButton: .left
      ),
      let mouseUpEvent = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseUp,
        mouseCursorPosition: coreGraphicsPoint,
        mouseButton: .left
      )
    else {
      return
    }
    mouseDownEvent.post(tap: .cghidEventTap)
    mouseUpEvent.post(tap: .cghidEventTap)
    print(
      "🖱️ CursorAutomation: clicked at (\(Int(coreGraphicsPoint.x)), \(Int(coreGraphicsPoint.y)))")
  }

  /// Standard ease-in-out curve so the glide accelerates then decelerates.
  private static func easeInOutProgress(_ progress: CGFloat) -> CGFloat {
    if progress < 0.5 {
      return 2 * progress * progress
    } else {
      return 1 - pow(-2 * progress + 2, 2) / 2
    }
  }
}
