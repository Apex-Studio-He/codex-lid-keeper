#!/usr/bin/env swift

import AppKit
import Foundation

private enum AssetError: Error, LocalizedError {
    case missingImage(String)
    case cannotCreateBitmap
    case cannotEncode(String)

    var errorDescription: String? {
        switch self {
        case .missingImage(let path):
            return "Could not load image at \(path)"
        case .cannotCreateBitmap:
            return "Could not create an image canvas."
        case .cannotEncode(let path):
            return "Could not encode \(path)"
        }
    }
}

private let project = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath,
    isDirectory: true
)
private let imageDirectory = project.appendingPathComponent(
    "docs/images",
    isDirectory: true
)

private func image(_ relativePath: String) throws -> NSImage {
    let url = project.appendingPathComponent(relativePath)
    guard let image = NSImage(contentsOf: url) else {
        throw AssetError.missingImage(url.path)
    }
    return image
}

private func canvas(
    width: Int,
    height: Int,
    draw: (NSRect) throws -> Void
) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw AssetError.cannotCreateBitmap
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    try draw(NSRect(x: 0, y: 0, width: width, height: height))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

private func drawCover(_ image: NSImage, in rect: NSRect) {
    let scale = max(
        rect.width / image.size.width,
        rect.height / image.size.height
    )
    let size = NSSize(
        width: image.size.width * scale,
        height: image.size.height * scale
    )
    let target = NSRect(
        x: rect.midX - size.width / 2,
        y: rect.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
    image.draw(
        in: target,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func drawRoundedImage(
    _ image: NSImage,
    in rect: NSRect,
    radius: CGFloat,
    borderColor: NSColor = NSColor.white.withAlphaComponent(0.14)
) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.withAlphaComponent(0.6).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    drawCover(image, in: rect)
    NSGraphicsContext.restoreGraphicsState()

    borderColor.setStroke()
    let border = NSBezierPath(
        roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
        xRadius: radius,
        yRadius: radius
    )
    border.lineWidth = 1
    border.stroke()
}

private func drawText(
    _ value: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    lineHeight: CGFloat? = nil
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    (value as NSString).draw(
        in: rect,
        withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    )
}

private func drawPill(
    _ value: String,
    rect: NSRect,
    color: NSColor
) {
    color.withAlphaComponent(0.16).setFill()
    NSBezierPath(
        roundedRect: rect,
        xRadius: rect.height / 2,
        yRadius: rect.height / 2
    ).fill()
    color.withAlphaComponent(0.5).setStroke()
    let border = NSBezierPath(
        roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
        xRadius: rect.height / 2,
        yRadius: rect.height / 2
    )
    border.lineWidth = 1
    border.stroke()
    drawText(
        value,
        in: rect.insetBy(dx: 16, dy: 8),
        size: 14,
        weight: .semibold,
        color: color
    )
}

private func writeJPEG(
    _ bitmap: NSBitmapImageRep,
    to relativePath: String,
    quality: CGFloat
) throws {
    let url = project.appendingPathComponent(relativePath)
    guard let data = bitmap.representation(
        using: .jpeg,
        properties: [.compressionFactor: quality]
    ) else {
        throw AssetError.cannotEncode(url.path)
    }
    try data.write(to: url, options: .atomic)
}

private func writePNG(
    _ bitmap: NSBitmapImageRep,
    to relativePath: String
) throws {
    let url = project.appendingPathComponent(relativePath)
    guard let data = bitmap.representation(
        using: .png,
        properties: [:]
    ) else {
        throw AssetError.cannotEncode(url.path)
    }
    try data.write(to: url, options: .atomic)
}

private func backgroundOverlay(in rect: NSRect) {
    let gradient = NSGradient(
        colorsAndLocations:
            (NSColor(calibratedWhite: 0.02, alpha: 0.82), 0),
            (NSColor(calibratedWhite: 0.02, alpha: 0.48), 0.48),
            (NSColor(calibratedWhite: 0.02, alpha: 0.10), 1)
    )
    gradient?.draw(in: rect, angle: 0)
}

private func buildSocialPreview(
    background: NSImage,
    icon: NSImage,
    dashboard: NSImage
) throws {
    let bitmap = try canvas(width: 1280, height: 640) { bounds in
        drawCover(background, in: bounds)
        backgroundOverlay(in: bounds)

        drawRoundedImage(
            icon,
            in: NSRect(x: 64, y: 488, width: 88, height: 88),
            radius: 20,
            borderColor: NSColor.white.withAlphaComponent(0.08)
        )
        drawText(
            "Codex Lid Keeper",
            in: NSRect(x: 64, y: 394, width: 565, height: 70),
            size: 48,
            weight: .bold,
            color: .white
        )
        drawText(
            "A guard that follows the task.",
            in: NSRect(x: 64, y: 334, width: 540, height: 50),
            size: 29,
            weight: .semibold,
            color: NSColor(
                calibratedRed: 0.25,
                green: 0.63,
                blue: 1,
                alpha: 1
            )
        )
        drawText(
            "Keeps eligible local Codex work running after lid close, then restores sleep and brightness after the final task.",
            in: NSRect(x: 64, y: 210, width: 520, height: 108),
            size: 21,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.82),
            lineHeight: 31
        )
        drawPill(
            "PUBLIC ALPHA · MACBOOK TESTERS WANTED",
            rect: NSRect(x: 64, y: 142, width: 365, height: 42),
            color: NSColor(
                calibratedRed: 0.20,
                green: 0.87,
                blue: 0.39,
                alpha: 1
            )
        )
        drawText(
            "Open source · Native SwiftUI · macOS 13+",
            in: NSRect(x: 64, y: 76, width: 520, height: 36),
            size: 16,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.55)
        )

        drawRoundedImage(
            dashboard,
            in: NSRect(x: 660, y: 82, width: 558, height: 418),
            radius: 24
        )
    }
    try writeJPEG(
        bitmap,
        to: "docs/images/social-preview.jpg",
        quality: 0.86
    )
}

private func buildHeroGallery(
    background: NSImage,
    dashboard: NSImage
) throws {
    let bitmap = try canvas(width: 1270, height: 760) { bounds in
        drawCover(background, in: bounds)
        backgroundOverlay(in: bounds)
        drawText(
            "The guard follows real Codex work",
            in: NSRect(x: 64, y: 642, width: 820, height: 66),
            size: 42,
            weight: .bold,
            color: .white
        )
        drawText(
            "Concurrent task count · AC or battery policy · automatic final-task restore",
            in: NSRect(x: 66, y: 592, width: 960, height: 38),
            size: 20,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.72)
        )
        drawRoundedImage(
            dashboard,
            in: NSRect(x: 64, y: 62, width: 840, height: 500),
            radius: 24
        )

        let blue = NSColor(
            calibratedRed: 0.24,
            green: 0.64,
            blue: 1,
            alpha: 1
        )
        drawPill(
            "01 · DETECT",
            rect: NSRect(x: 950, y: 456, width: 176, height: 40),
            color: blue
        )
        drawText(
            "Two local lifecycle signals are merged and deduplicated.",
            in: NSRect(x: 950, y: 350, width: 250, height: 90),
            size: 19,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.88),
            lineHeight: 27
        )
        drawPill(
            "02 · GUARD",
            rect: NSRect(x: 950, y: 274, width: 176, height: 40),
            color: blue
        )
        drawText(
            "Guarding starts only when work and the selected power policy are eligible.",
            in: NSRect(x: 950, y: 156, width: 250, height: 100),
            size: 19,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.88),
            lineHeight: 27
        )
        drawPill(
            "03 · RESTORE",
            rect: NSRect(x: 950, y: 78, width: 188, height: 40),
            color: NSColor(
                calibratedRed: 0.20,
                green: 0.87,
                blue: 0.39,
                alpha: 1
            )
        )
        drawText(
            "The final task restores the saved sleep policy and display brightness.",
            in: NSRect(x: 950, y: 8, width: 250, height: 58),
            size: 15,
            weight: .medium,
            color: NSColor.white.withAlphaComponent(0.88),
            lineHeight: 20
        )
    }
    try writeJPEG(
        bitmap,
        to: "docs/images/gallery-01-hero.jpg",
        quality: 0.88
    )
}

private func buildSafetyGallery(
    background: NSImage,
    settings: NSImage
) throws {
    let bitmap = try canvas(width: 1270, height: 760) { bounds in
        drawCover(background, in: bounds)
        backgroundOverlay(in: bounds)
        drawRoundedImage(
            settings,
            in: NSRect(x: 40, y: 120, width: 590, height: 508),
            radius: 24
        )
        drawText(
            "Power boundaries you can see",
            in: NSRect(x: 660, y: 602, width: 540, height: 82),
            size: 40,
            weight: .bold,
            color: .white
        )
        drawText(
            "AC only by default",
            in: NSRect(x: 660, y: 500, width: 500, height: 42),
            size: 25,
            weight: .semibold,
            color: NSColor(
                calibratedRed: 0.25,
                green: 0.63,
                blue: 1,
                alpha: 1
            )
        )
        drawText(
            "Battery operation is opt-in. The user selects a 30–100% floor; the root watchdog keeps an independent 30% hard minimum.",
            in: NSRect(x: 660, y: 365, width: 510, height: 118),
            size: 20,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.82),
            lineHeight: 30
        )
        drawText(
            "Recovery is a first-class control",
            in: NSRect(x: 660, y: 292, width: 500, height: 42),
            size: 25,
            weight: .semibold,
            color: NSColor(
                calibratedRed: 0.20,
                green: 0.87,
                blue: 0.39,
                alpha: 1
            )
        )
        drawText(
            "Final-task completion or any safety stop triggers restoration of the previously saved sleep policy. Emergency restore and uninstall do the same.",
            in: NSRect(x: 660, y: 135, width: 510, height: 136),
            size: 20,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.82),
            lineHeight: 30
        )
        drawPill(
            "SUPERVISED DESK TESTING ONLY",
            rect: NSRect(x: 660, y: 64, width: 310, height: 42),
            color: NSColor(
                calibratedRed: 1,
                green: 0.62,
                blue: 0.08,
                alpha: 1
            )
        )
    }
    try writeJPEG(
        bitmap,
        to: "docs/images/gallery-02-safety.jpg",
        quality: 0.88
    )
}

private func buildThumbnail(
    background: NSImage,
    icon: NSImage
) throws {
    let bitmap = try canvas(width: 240, height: 240) { bounds in
        drawCover(background, in: bounds)
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
        drawRoundedImage(
            icon,
            in: NSRect(x: 42, y: 42, width: 156, height: 156),
            radius: 38,
            borderColor: NSColor.white.withAlphaComponent(0.10)
        )
    }
    try writePNG(
        bitmap,
        to: "docs/images/producthunt-thumbnail.png"
    )
}

do {
    try FileManager.default.createDirectory(
        at: imageDirectory,
        withIntermediateDirectories: true
    )
    let background = try image("docs/launch/source-background.png")
    let icon = try image("Resources/App/AppIcon.png")
    let dashboard = try image("docs/images/dashboard-zh.png")
    let settings = try image("docs/images/settings-power-zh.png")

    try buildSocialPreview(
        background: background,
        icon: icon,
        dashboard: dashboard
    )
    try buildHeroGallery(
        background: background,
        dashboard: dashboard
    )
    try buildSafetyGallery(
        background: background,
        settings: settings
    )
    try buildThumbnail(background: background, icon: icon)
    print("Built launch assets in \(imageDirectory.path)")
} catch {
    fputs("build_marketing_assets: \(error.localizedDescription)\n", stderr)
    exit(1)
}
