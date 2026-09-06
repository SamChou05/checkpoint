import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class CheckpointDialogueRenderingTests: XCTestCase {
    @MainActor
    func testAllCharacterPosesAreBundledAndVisuallyDistinct() throws {
        let poses = try CheckpointMascotPose.allCases.map { pose in
            try XCTUnwrap(UIImage(named: pose.assetName, in: .main, compatibleWith: nil), pose.assetName)
        }
        for first in poses.indices {
            for second in poses.indices where second > first {
                XCTAssertGreaterThan(pixelDifference(poses[first], poses[second]), 0.01)
            }
        }
    }

    func testDialogueMotionKeepsAssistivePresentationsStill() {
        let standard = CheckpointDialogueMotionPolicy(reduceMotion: false, voiceOverEnabled: false)
        XCTAssertTrue(standard.permitsSpatialMotion)
        XCTAssertNotEqual(standard.entranceOffset, 0)
        XCTAssertNotEqual(standard.reactionLift, 0)
        XCTAssertNotNil(standard.entranceAnimation)

        for preferences in [(true, false), (false, true), (true, true)] {
            let policy = CheckpointDialogueMotionPolicy(
                reduceMotion: preferences.0,
                voiceOverEnabled: preferences.1
            )
            XCTAssertFalse(policy.permitsSpatialMotion)
            XCTAssertEqual(policy.entranceOffset, 0)
            XCTAssertEqual(policy.entranceRotation, 0)
            XCTAssertEqual(policy.entranceScale, 1)
            XCTAssertEqual(policy.reactionLift, 0)
            XCTAssertEqual(policy.reactionRotation, 0)
            XCTAssertNil(policy.entranceAnimation)
        }
    }

    @MainActor
    func testMountedDialogueEntersOnceReactsToANewLineThenRemainsStill() {
        let driver = DialogueTestDriver()
        let mount = mountDialogue(driver: driver)
        defer { mount.window.isHidden = true }

        settle(for: 0.06)
        XCTAssertEqual(driver.phases, [.entering])
        let entranceImage = image(of: mount.host.view)
        settle(for: 0.55)
        XCTAssertEqual(driver.phases, [.entering, .settled])
        let restingImage = image(of: mount.host.view)
        XCTAssertGreaterThan(
            pixelDifference(entranceImage, restingImage), 0.0001,
            "The mounted mascot must visibly move during its entrance."
        )

        let settledCount = driver.phases.count
        driver.title = "Oh, hello!"
        driver.message = "I'm Checkpoint. What would you like to learn?"
        driver.pose = .wave
        driver.unrelatedRevision += 1
        settle(for: 0.1)
        XCTAssertEqual(driver.phases.count, settledCount, "An unchanged line must not replay for ordinary updates.")

        driver.title = "I can help with that."
        driver.message = "Let's make a place to start."
        driver.pose = .think
        settle(for: 0.06)
        XCTAssertEqual(driver.phases.last, .reacting)
        let reactingImage = image(of: mount.host.view)
        settle(for: 0.5)
        XCTAssertEqual(Array(driver.phases.suffix(2)), [.reacting, .settled])
        let newRestingImage = image(of: mount.host.view)
        XCTAssertGreaterThan(
            pixelDifference(reactingImage, newRestingImage), 0.0001,
            "Changing the spoken line must produce a short visible character reaction."
        )
        let completedCount = driver.phases.count
        settle(for: 0.6)
        XCTAssertEqual(driver.phases.count, completedCount, "The character must not loop after settling.")
        XCTAssertLessThan(pixelDifference(newRestingImage, image(of: mount.host.view)), 0.0001)
    }

    @MainActor
    func testReduceMotionInterruptsMountedEntranceAndDoesNotReplayWhenDisabled() {
        let driver = DialogueTestDriver()
        let mount = mountDialogue(driver: driver)
        defer { mount.window.isHidden = true }
        settle(for: 0.06)
        XCTAssertEqual(driver.phases.last, .entering)

        driver.reduceMotion = true
        settle(for: 0.05)
        XCTAssertEqual(driver.phases.last, .settled)
        let suppressedImage = image(of: mount.host.view)
        let settledCount = driver.phases.count
        settle(for: 0.6)
        XCTAssertEqual(driver.phases.count, settledCount, "Cancelled entrance work must stay cancelled.")
        XCTAssertLessThan(pixelDifference(suppressedImage, image(of: mount.host.view)), 0.0001)

        driver.reduceMotion = false
        settle(for: 0.1)
        XCTAssertEqual(driver.phases.count, settledCount, "A preference change must not replay the same dialogue.")
        XCTAssertLessThan(pixelDifference(suppressedImage, image(of: mount.host.view)), 0.0001)
    }

    @MainActor
    func testDismissalCancelsMountedReactionAndReducedMotionNeverBeginsOne() {
        let driver = DialogueTestDriver()
        driver.reduceMotion = true
        let mount = mountDialogue(driver: driver)
        defer { mount.window.isHidden = true }
        settle(for: 0.05)
        XCTAssertEqual(driver.phases, [.settled])

        driver.pose = .think
        driver.title = "Let's find a starting point."
        settle(for: 0.05)
        XCTAssertFalse(driver.phases.contains(.entering))
        XCTAssertFalse(driver.phases.contains(.reacting))

        driver.reduceMotion = false
        settle(for: 0.05)
        driver.title = "Your map is ready!"
        driver.pose = .celebrate
        settle(for: 0.05)
        XCTAssertEqual(driver.phases.last, .reacting)
        driver.isVisible = false
        settle(for: 0.05)
        XCTAssertEqual(driver.phases.last, .settled)
        let dismissedCount = driver.phases.count
        settle(for: 0.6)
        XCTAssertEqual(driver.phases.count, dismissedCount, "A removed guide must not finish an old beat later.")
    }

    @MainActor
    private func mountDialogue(driver: DialogueTestDriver) -> (window: UIWindow, host: UIHostingController<DialogueTestHarness>) {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 260)
        let host = UIHostingController(rootView: DialogueTestHarness(driver: driver))
        let window = UIWindow(frame: frame)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = frame
        host.view.layoutIfNeeded()
        return (window, host)
    }

    @MainActor
    private func settle(for duration: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }

    @MainActor
    private func image(of view: UIView) -> UIImage {
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
        }
    }

    private func pixelDifference(_ first: UIImage, _ second: UIImage) -> Double {
        guard let firstImage = first.cgImage,
              let secondImage = second.cgImage,
              firstImage.width == secondImage.width,
              firstImage.height == secondImage.height else {
            XCTFail("Dialogue captures must have matching dimensions.")
            return 0
        }
        let byteCount = firstImage.width * firstImage.height * 4
        var firstPixels = [UInt8](repeating: 0, count: byteCount)
        var secondPixels = firstPixels
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(x: 0, y: 0, width: firstImage.width, height: firstImage.height)
        func draw(_ image: CGImage, into pixels: inout [UInt8]) {
            pixels.withUnsafeMutableBytes { buffer in
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                context.draw(image, in: bounds)
            }
        }
        draw(firstImage, into: &firstPixels)
        draw(secondImage, into: &secondPixels)
        let difference = zip(firstPixels, secondPixels).reduce(0.0) { total, bytes in
            total + Double(abs(Int(bytes.0) - Int(bytes.1)))
        }
        return difference / Double(byteCount * 255)
    }
}

@MainActor
@Observable
private final class DialogueTestDriver {
    var title = "Oh, hello!"
    var message = "I'm Checkpoint. What would you like to learn?"
    var pose = CheckpointMascotPose.wave
    var reduceMotion = false
    var unrelatedRevision = 0
    var isVisible = true
    @ObservationIgnored var phases: [CheckpointDialogueMotionPhase] = []
}

private struct DialogueTestHarness: View {
    let driver: DialogueTestDriver

    var body: some View {
        VStack {
            if driver.isVisible {
                CheckpointSetupGuide(
                    step: .goal,
                    title: driver.title,
                    message: driver.message,
                    reduceMotionOverride: driver.reduceMotion,
                    pose: driver.pose,
                    motionObserver: { driver.phases.append($0) }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(CheckpointTheme.paper)
        .accessibilityValue("\(driver.unrelatedRevision)")
    }
}
