import SwiftUI
import UIKit
import XCTest

enum HostedViewRenderer {
    @MainActor
    static func image<Content: View>(
        for content: Content,
        width: CGFloat,
        height: CGFloat,
        colorScheme: ColorScheme,
        settlingTime: TimeInterval = 0.05,
        renderScale: CGFloat = 2
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let frame = CGRect(origin: .zero, size: size)
        let interfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let hostingController = UIHostingController(
            rootView: content.preferredColorScheme(colorScheme)
        )
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true }

        window.overrideUserInterfaceStyle = interfaceStyle
        hostingController.overrideUserInterfaceStyle = interfaceStyle
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: settlingTime))
        hostingController.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = renderScale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            XCTAssertTrue(
                hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                ),
                "Failed to draw hosted SwiftUI hierarchy"
            )
        }
    }
}
