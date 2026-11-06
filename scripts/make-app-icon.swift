// Рисует значок приложения IPCHEK во всех размерах для macOS.
// Запуск: make icon (или xcrun --sdk macosx swift scripts/make-app-icon.swift <папка AppIcon.appiconset>)
//
// Рисунок свой (волны сети), без SF Symbols: их лицензия запрещает использование в значках
// приложений. Фон сплошной на весь квадрат — форму скругления задаёт сама macOS.

import AppKit

let sizes: [(file: String, points: Int, scale: Int)] = [
  ("icon_16x16.png", 16, 1), ("icon_16x16@2x.png", 16, 2),
  ("icon_32x32.png", 32, 1), ("icon_32x32@2x.png", 32, 2),
  ("icon_128x128.png", 128, 1), ("icon_128x128@2x.png", 128, 2),
  ("icon_256x256.png", 256, 1), ("icon_256x256@2x.png", 256, 2),
  ("icon_512x512.png", 512, 1), ("icon_512x512@2x.png", 512, 2),
]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("make-app-icon: \(message)\n".utf8))
  exit(1)
}

func render(pixels: Int) -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
  else { fail("не удалось создать холст \(pixels)×\(pixels)") }

  let side = CGFloat(pixels)
  let context = graphics.cgContext
  let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
  let top = CGColor(srgbRed: 0.20, green: 0.52, blue: 1.00, alpha: 1)
  let bottom = CGColor(srgbRed: 0.07, green: 0.31, blue: 0.78, alpha: 1)
  guard
    let gradient = CGGradient(
      colorsSpace: sRGB, colors: [top, bottom] as CFArray, locations: [0, 1])
  else { fail("не удалось создать градиент") }
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])

  // Три дуги и точка — «волны сети».
  let center = CGPoint(x: side * 0.5, y: side * 0.28)
  let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
  context.setStrokeColor(white)
  context.setLineCap(.round)
  context.setLineWidth(side * 0.075)
  for radius in [0.17, 0.31, 0.45] {
    context.addArc(
      center: center, radius: side * radius, startAngle: .pi * 0.25, endAngle: .pi * 0.75,
      clockwise: false)
    context.strokePath()
  }
  let dot = side * 0.11
  context.setFillColor(white)
  context.fillEllipse(
    in: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot))
  context.flush()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fail("не удалось сохранить PNG \(pixels)×\(pixels)")
  }
  return png
}

guard CommandLine.arguments.count == 2 else {
  fail("укажите папку AppIcon.appiconset")
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  var images: [[String: String]] = []
  for size in sizes {
    try render(pixels: size.points * size.scale).write(to: folder.appendingPathComponent(size.file))
    images.append([
      "filename": size.file, "idiom": "mac", "scale": "\(size.scale)x",
      "size": "\(size.points)x\(size.points)",
    ])
  }
  let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
  let json = try JSONSerialization.data(
    withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
  try json.write(to: folder.appendingPathComponent("Contents.json"))
  print("make-app-icon: \(sizes.count) размеров записаны в \(folder.path)")
} catch {
  fail(error.localizedDescription)
}
