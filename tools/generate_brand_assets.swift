import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconSpec {
  let path: String
  let size: Int
}

enum ScriptError: Error, CustomStringConvertible {
  case invalidArguments
  case loadFailed(String)
  case contextFailed(String)
  case saveFailed(String)

  var description: String {
    switch self {
    case .invalidArguments:
      return "Usage: swift generate_brand_assets.swift <input-png> <output-dir>"
    case let .loadFailed(message),
      let .contextFailed(message),
      let .saveFailed(message):
      return message
    }
  }
}

func makeRGBAImage(_ image: CGImage) throws -> CGImage {
  let width = image.width
  let height = image.height
  let bytesPerRow = width * 4
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  guard
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw ScriptError.contextFailed("Could not create RGBA conversion context.")
  }

  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  guard let normalized = context.makeImage() else {
    throw ScriptError.contextFailed("Could not render normalized RGBA image.")
  }
  return normalized
}

func trimmedBounds(of image: CGImage, alphaThreshold: UInt8 = 8) throws -> CGRect {
  let rgba = try makeRGBAImage(image)
  guard let data = rgba.dataProvider?.data else {
    throw ScriptError.loadFailed("Could not access RGBA image data.")
  }

  let pointer = CFDataGetBytePtr(data)!
  let width = rgba.width
  let height = rgba.height
  let bytesPerRow = rgba.bytesPerRow

  var minX = width
  var minY = height
  var maxX = -1
  var maxY = -1

  for y in 0..<height {
    for x in 0..<width {
      let offset = y * bytesPerRow + x * 4 + 3
      let alpha = pointer[offset]
      if alpha > alphaThreshold {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
      }
    }
  }

  if maxX < minX || maxY < minY {
    return CGRect(x: 0, y: 0, width: width, height: height)
  }

  return CGRect(
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1
  )
}

func createContext(size: Int, opaque: Bool) throws -> CGContext {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo: UInt32 = opaque
    ? CGImageAlphaInfo.noneSkipLast.rawValue
    : CGImageAlphaInfo.premultipliedLast.rawValue

  guard
    let context = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: size * 4,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    )
  else {
    throw ScriptError.contextFailed("Could not create drawing context for \(size)x\(size).")
  }

  context.interpolationQuality = .high
  return context
}

func savePNG(_ image: CGImage, to url: URL) throws {
  guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
  ) else {
    throw ScriptError.saveFailed("Could not create image destination for \(url.path).")
  }

  CGImageDestinationAddImage(destination, image, nil)
  if !CGImageDestinationFinalize(destination) {
    throw ScriptError.saveFailed("Could not finalize PNG at \(url.path).")
  }
}

func renderMark(from emblem: CGImage, size: Int) throws -> CGImage {
  let context = try createContext(size: size, opaque: false)
  let targetSize = CGFloat(size) * 0.80
  let drawRect = CGRect(
    x: (CGFloat(size) - targetSize) / 2,
    y: (CGFloat(size) - targetSize) / 2,
    width: targetSize,
    height: targetSize
  )
  context.clear(CGRect(x: 0, y: 0, width: size, height: size))
  context.draw(emblem, in: drawRect)
  guard let result = context.makeImage() else {
    throw ScriptError.contextFailed("Could not create transparent mark image.")
  }
  return result
}

func renderIcon(from emblem: CGImage, size: Int) throws -> CGImage {
  let context = try createContext(size: size, opaque: true)
  let canvas = CGRect(x: 0, y: 0, width: size, height: size)
  let background = CGColor(red: 10 / 255, green: 10 / 255, blue: 15 / 255, alpha: 1)

  context.setFillColor(background)
  context.fill(canvas)

  let targetSize = CGFloat(size) * 0.82
  let drawRect = CGRect(
    x: (CGFloat(size) - targetSize) / 2,
    y: (CGFloat(size) - targetSize) / 2,
    width: targetSize,
    height: targetSize
  )
  context.draw(emblem, in: drawRect)

  guard let result = context.makeImage() else {
    throw ScriptError.contextFailed("Could not create app icon image.")
  }
  return result
}

let androidIcons = [
  IconSpec(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", size: 48),
  IconSpec(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", size: 72),
  IconSpec(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", size: 96),
  IconSpec(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", size: 144),
  IconSpec(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", size: 192),
]

let iosIcons = [
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png", size: 20),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png", size: 40),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png", size: 60),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png", size: 29),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png", size: 58),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png", size: 87),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png", size: 40),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png", size: 80),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png", size: 120),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png", size: 120),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png", size: 180),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png", size: 76),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png", size: 152),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png", size: 167),
  IconSpec(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png", size: 1024),
]

do {
  guard CommandLine.arguments.count == 3 else {
    throw ScriptError.invalidArguments
  }

  let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
  let outputDir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
  let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil)
  guard let source, let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    throw ScriptError.loadFailed("Could not load source logo from \(inputURL.path).")
  }

  let emblemCandidateSize = min(Int(Double(fullImage.height) * 0.87), fullImage.height)
  guard let emblemCandidate = fullImage.cropping(
    to: CGRect(x: 0, y: 0, width: emblemCandidateSize, height: fullImage.height)
  ) else {
    throw ScriptError.loadFailed("Could not crop emblem candidate from source logo.")
  }

  let trimRect = try trimmedBounds(of: emblemCandidate).insetBy(dx: -10, dy: -10)
  let safeTrimRect = CGRect(
    x: max(0, trimRect.origin.x.rounded(.down)),
    y: max(0, trimRect.origin.y.rounded(.down)),
    width: min(CGFloat(emblemCandidate.width), trimRect.width.rounded(.up)),
    height: min(CGFloat(emblemCandidate.height), trimRect.height.rounded(.up))
  )

  guard let emblem = emblemCandidate.cropping(to: safeTrimRect) else {
    throw ScriptError.loadFailed("Could not trim the emblem artwork.")
  }

  try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

  let mark1024 = try renderMark(from: emblem, size: 1024)
  let icon1024 = try renderIcon(from: emblem, size: 1024)

  try savePNG(mark1024, to: outputDir.appendingPathComponent("seeknirvana_mark.png"))
  try savePNG(icon1024, to: outputDir.appendingPathComponent("seeknirvana_icon_master.png"))

  for spec in androidIcons + iosIcons {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let destinationURL = root.appendingPathComponent(spec.path)
    let icon = try renderIcon(from: emblem, size: spec.size)
    try savePNG(icon, to: destinationURL)
  }

  fputs("Generated brand assets in \(outputDir.path)\n", stdout)
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
