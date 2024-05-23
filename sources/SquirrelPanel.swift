import AppKit
import QuartzCore

private let kDefaultCandidateFormat: String = "%c. %@"
private let kTipSpecifier: String = "%s"
private let kFullWidthSpace: String = "　"
private let kShowStatusDuration: TimeInterval = 2.0
private let kBlendedBackgroundColorFraction: Double = 0.2
private let kDefaultFontSize: Double = 24
private let kOffsetGap: Double = 5

// MARK: Auxiliaries

func clamp<T: Comparable>(_ x: T, _ min: T, _ max: T) -> T {
  let y = x < min ? min : x
  return y > max ? max : y
}

// coalesce: assign new value if current value is null
infix operator ?= : AssignmentPrecedence
func ?= <T: Any>(left: inout T?, right: T?) {
  if left == nil && right != nil {
    left = right
  }
}

// overwrite current value with new value (provided not null)
infix operator =? : AssignmentPrecedence
func =? <T: Any>(left: inout T?, right: T?) {
  if right != nil {
    left = right
  }
}

func =? <T: Any>(left: inout T, right: T?) {
  if right != nil {
    left = right!
  }
}

extension CFString {
  static func == (left: CFString, right: CFString) -> Bool {
    return CFStringCompare(left, right, []) == .compareEqualTo
  }

  static func != (left: CFString, right: CFString) -> Bool {
    return CFStringCompare(left, right, []) != .compareEqualTo
  }
}

extension CharacterSet {
  static let fullWidthDigits = CharacterSet(charactersIn: Unicode.Scalar(0xFF10)! ... Unicode.Scalar(0xFF19)!)
  static let fullWidthLatinCapitals = CharacterSet(charactersIn: Unicode.Scalar(0xFF21)! ... Unicode.Scalar(0xFF3A)!)
}

extension NSRect { // top-left -> bottom-left -> bottom-right -> top-right
  var vertices: [NSPoint] { isEmpty ? [] : [origin, .init(x: minX, y: maxY), .init(x: maxX, y: maxY), .init(x: maxX, y: minY)] }

  func integral(options: AlignmentOptions) -> NSRect { return NSIntegralRectWithOptions(self, options) }
}

struct SquirrelTextPolygon: Sendable {
  var head: NSRect = .zero; var body: NSRect = .zero; var tail: NSRect = .zero

  init(head: NSRect, body: NSRect, tail: NSRect) {
    self.head = head; self.body = body; self.tail = tail
  }
}

extension SquirrelTextPolygon {
  var origin: NSPoint { head.isEmpty ? body.origin : head.origin }
  var minY: CGFloat { head.isEmpty ? body.minY : head.minY }
  var maxY: CGFloat { head.isEmpty ? body.maxY : head.maxY }
  var isSeparated: Bool { !head.isEmpty && body.isEmpty && !tail.isEmpty && tail.maxX < head.minX - 0.1 }

  var vertices: [NSPoint] {
    if isSeparated { return [] }
    switch (head.vertices, body.vertices, tail.vertices) {
    case let (headVertices, [], []):
      return headVertices
    case let ([], [], tailVertices):
      return tailVertices
    case let ([], bodyVertices, []):
      return bodyVertices
    case let (headVertices, bodyVertices, []):
      return [headVertices[0], headVertices[1], bodyVertices[0], bodyVertices[1], bodyVertices[2], headVertices[3]]
    case let ([], bodyVertices, tailVertices):
      return [bodyVertices[0], tailVertices[1], tailVertices[2], tailVertices[3], bodyVertices[2], bodyVertices[3]]
    case let (headVertices, [], tailVertices):
      return [headVertices[0], headVertices[1], tailVertices[0], tailVertices[1], tailVertices[2], tailVertices[3], headVertices[2], headVertices[3]]
    case let (headVertices, bodyVertices, tailVertices):
      return [headVertices[0], headVertices[1], bodyVertices[0], tailVertices[1], tailVertices[2], tailVertices[3], bodyVertices[2], headVertices[3]]
    }
  }

  func mouseInPolygon(point: NSPoint, flipped: Bool) -> Bool {
    return (!body.isEmpty && NSMouseInRect(point, body, flipped)) || (!head.isEmpty && NSMouseInRect(point, head, flipped)) || (!tail.isEmpty && NSMouseInRect(point, tail, flipped))
  }
}

struct SquirrelTabularIndex: Sendable {
  var index: Int; var lineNum: Int; var tabNum: Int

  init(index: Int, lineNum: Int, tabNum: Int) {
    self.index = index; self.lineNum = lineNum; self.tabNum = tabNum
  }
}

struct SquirrelCandidateInfo: Sendable {
  var location: Int; var length: Int; var text: Int; var comment: Int
  var idx: Int; var col: Int; var isTruncated: Bool

  init(location: Int, length: Int, text: Int, comment: Int, idx: Int, col: Int, isTruncated: Bool) {
    self.location = location; self.length = length; self.text = text; self.comment = comment
    self.idx = idx; self.col = col; self.isTruncated = isTruncated
  }
}

extension SquirrelCandidateInfo {
  var candidateRange: NSRange { NSRange(location: location, length: length) }
  var upperBound: Int { location + length }
  var labelRange: NSRange { NSRange(location: location, length: text) }
  var textRange: NSRange { NSRange(location: location + text, length: comment - text) }
  var commentRange: NSRange { NSRange(location: location + comment, length: length - comment) }
}

extension CGPath {
  static func combinePaths(_ x: CGPath?, _ y: CGPath?) -> CGPath? {
    if x == nil { return y?.copy() }
    if y == nil { return x?.copy() }
    let path: CGMutablePath? = x!.mutableCopy()
    path?.addPath(y!)
    return path?.copy()
  }

  static func squirclePath(rect: NSRect, cornerRadius: Double) -> CGPath? {
    return squircleMutablePath(vertices: rect.vertices, cornerRadius: cornerRadius)?.copy()
  }

  static func squirclePath(polygon: SquirrelTextPolygon, cornerRadius: Double) -> CGPath? {
    if polygon.isSeparated {
      if let headPath = squircleMutablePath(vertices: polygon.head.vertices, cornerRadius: cornerRadius), let tailPath = squircleMutablePath(vertices: polygon.tail.vertices, cornerRadius: cornerRadius) {
        headPath.addPath(tailPath)
        return headPath.copy()
      } else { return nil }
    } else {
      return squircleMutablePath(vertices: polygon.vertices, cornerRadius: cornerRadius)?.copy()
    }
  }

  // Bezier squircle curves, whose rounded corners are smooth (continously differentiable)
  static func squircleMutablePath(vertices: [CGPoint], cornerRadius: Double) -> CGMutablePath? {
    if vertices.count < 4 { return nil }
    let path = CGMutablePath()
    var vertex: CGPoint = vertices.last!
    var nextVertex: CGPoint = vertices.first!
    var nextDiff = CGVector(dx: nextVertex.x - vertex.x, dy: nextVertex.y - vertex.y)
    var lastDiff: CGVector
    var arcRadius: CGFloat, arcRadiusDx: CGFloat, arcRadiusDy: CGFloat
    var startPoint: CGPoint
    var relayA: CGPoint, controlA1: CGPoint, controlA2: CGPoint
    var relayB: CGPoint, controlB1: CGPoint, controlB2: CGPoint
    var endPoint = CGPoint(x: vertex.x + nextDiff.dx * 0.5, y: nextVertex.y)
    var control1: CGPoint, control2: CGPoint
    path.move(to: endPoint)
    for i in 0 ..< vertices.count {
      lastDiff = nextDiff
      vertex = nextVertex
      nextVertex = vertices[(i + 1) % vertices.count]
      nextDiff = .init(dx: nextVertex.x - vertex.x, dy: nextVertex.y - vertex.y)
      if abs(nextDiff.dx) >= abs(nextDiff.dy) {
        arcRadius = min(cornerRadius, abs(nextDiff.dx) * 0.3, abs(lastDiff.dy) * 0.3)
        arcRadiusDy = copysign(arcRadius, lastDiff.dy)
        arcRadiusDx = copysign(arcRadius, nextDiff.dx)
        startPoint = .init(x: vertex.x, y: fma(arcRadiusDy, -1.528664, nextVertex.y))
        relayA = .init(x: fma(arcRadiusDx, 0.074911, vertex.x), y: fma(arcRadiusDy, -0.631494, nextVertex.y))
        controlA1 = .init(x: vertex.x, y: fma(arcRadiusDy, -1.088493, nextVertex.y))
        controlA2 = .init(x: vertex.x, y: fma(arcRadiusDy, -0.868407, nextVertex.y))
        relayB = .init(x: fma(arcRadiusDx, 0.631494, vertex.x), y: fma(arcRadiusDy, -0.074911, nextVertex.y))
        controlB1 = .init(x: fma(arcRadiusDx, 0.372824, vertex.x), y: fma(arcRadiusDy, -0.169060, nextVertex.y))
        controlB2 = .init(x: fma(arcRadiusDx, 0.169060, vertex.x), y: fma(arcRadiusDy, -0.372824, nextVertex.y))
        endPoint = .init(x: fma(arcRadiusDx, 1.528664, vertex.x), y: nextVertex.y)
        control1 = .init(x: fma(arcRadiusDx, 0.868407, vertex.x), y: nextVertex.y)
        control2 = .init(x: fma(arcRadiusDx, 1.088493, vertex.x), y: nextVertex.y)
      } else {
        arcRadius = min(cornerRadius, abs(nextDiff.dy) * 0.3, abs(lastDiff.dx) * 0.3)
        arcRadiusDx = copysign(arcRadius, lastDiff.dx)
        arcRadiusDy = copysign(arcRadius, nextDiff.dy)
        startPoint = .init(x: fma(arcRadiusDx, -1.528664, nextVertex.x), y: vertex.y)
        relayA = .init(x: fma(arcRadiusDx, -0.631494, nextVertex.x), y: fma(arcRadiusDy, 0.074911, vertex.y))
        controlA1 = .init(x: fma(arcRadiusDx, -1.088493, nextVertex.x), y: vertex.y)
        controlA2 = .init(x: fma(arcRadiusDx, -0.868407, nextVertex.x), y: vertex.y)
        relayB = .init(x: fma(arcRadiusDx, -0.074911, nextVertex.x), y: fma(arcRadiusDy, 0.631494, vertex.y))
        controlB1 = .init(x: fma(arcRadiusDx, -0.169060, nextVertex.x), y: fma(arcRadiusDy, 0.372824, vertex.y))
        controlB2 = .init(x: fma(arcRadiusDx, -0.372824, nextVertex.x), y: fma(arcRadiusDy, 0.169060, vertex.y))
        endPoint = .init(x: nextVertex.x, y: fma(arcRadiusDy, 1.528664, vertex.y))
        control1 = .init(x: nextVertex.x, y: fma(arcRadiusDy, 0.868407, vertex.y))
        control2 = .init(x: nextVertex.x, y: fma(arcRadiusDy, 1.088493, vertex.y))
      }
      path.addLine(to: startPoint)
      path.addCurve(to: relayA, control1: controlA1, control2: controlA2)
      path.addCurve(to: relayB, control1: controlB1, control2: controlB2)
      path.addCurve(to: endPoint, control1: control1, control2: control2)
    }
    path.closeSubpath()
    return path
  }
} // NSBezierPath (NSBezierSquirclePath)

extension NSAttributedString.Key {
  static let baselineClass: NSAttributedString.Key = .init(kCTBaselineClassAttributeName as String)
  static let baselineReferenceInfo: NSAttributedString.Key = .init(kCTBaselineReferenceInfoAttributeName as String)
  static let rubyAnnotation: NSAttributedString.Key = .init(kCTRubyAnnotationAttributeName as String)
  static let language: NSAttributedString.Key = .init(kCTLanguageAttributeName as String)
}

extension NSMutableAttributedString {
  private func superscriptionRange(_ range: NSRange) {
    enumerateAttribute(.font, in: range, options: [.longestEffectiveRangeNotRequired]) { value, subRange, stop in
      if let oldFont = value as? NSFont {
        let newFont = NSFont(descriptor: oldFont.fontDescriptor, size: floor(oldFont.pointSize * 0.55))
        let attrs: [NSAttributedString.Key: Any] = [.font: newFont!,
                                                    .baselineClass: kCTBaselineClassIdeographicCentered,
                                                    .superscript: NSNumber(value: 1)]
        addAttributes(attrs, range: subRange)
      }
    }
  }

  private func subscriptionRange(_ range: NSRange) {
    enumerateAttribute(.font, in: range, options: [.longestEffectiveRangeNotRequired]) { value, subRange, stop in
      if let oldFont = value as? NSFont {
        let newFont = NSFont(descriptor: oldFont.fontDescriptor, size: floor(oldFont.pointSize * 0.55))
        let attrs: [NSAttributedString.Key: Any] = [.font: newFont!,
                                                    .baselineClass: kCTBaselineClassIdeographicCentered,
                                                    .superscript: NSNumber(value: -1)]
        addAttributes(attrs, range: subRange)
      }
    }
  }

  static let markDownPattern: String =
    "((\\*{1,2}|\\^|~{1,2})|((?<=\\b)_{1,2})|<(b|strong|i|em|u|sup|sub|s)>)(.+?)(\\2|\\3(?=\\b)|<\\/\\4>)"
  func formatMarkDown() {
    if let regex = try? NSRegularExpression(pattern: Self.markDownPattern, options: [.useUnicodeWordBoundaries]) {
      var offset: Int = 0
      regex.enumerateMatches(in: string, options: [], range: NSRange(location: 0, length: length)) { match, flags, stop in
        guard let match = match else { return }
        let adjusted = match.adjustingRanges(offset: offset)
        let tag: String! = mutableString.substring(with: adjusted.range(at: 1))
        switch tag {
        case "**", "__", "<b>", "<strong>":
          applyFontTraits(.boldFontMask, range: adjusted.range(at: 5))
        case "*", "_", "<i>", "<em>":
          applyFontTraits(.italicFontMask, range: adjusted.range(at: 5))
        case "<u>":
          addAttribute(.underlineStyle, value: NSUnderlineStyle.single, range: adjusted.range(at: 5))
        case "~~", "<s>":
          addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single, range: adjusted.range(at: 5))
        case "^", "<sup>":
          superscriptionRange(adjusted.range(at: 5))
        case "~", "<sub>":
          subscriptionRange(adjusted.range(at: 5))
        default:
          break
        }
        deleteCharacters(in: adjusted.range(at: 6))
        deleteCharacters(in: adjusted.range(at: 1))
        offset -= adjusted.range(at: 6).length + adjusted.range(at: 1).length
      }
      if offset != 0 { // repeat until no more nested markdown
        formatMarkDown()
      }
    }
  }

  static let rubyPattern: String = "(\u{FFF9}\\s*)(\\S+?)(\\s*\u{FFFA}(.+?)\u{FFFB})"
  func annotateRuby(inRange range: NSRange, verticalOrientation isVertical: Bool, maximumLength maxLength: Double, scriptVariant: String) -> Double {
    var rubyLineHeight: Double = 0.0
    if let regex = try? NSRegularExpression(pattern: Self.rubyPattern, options: []) {
      regex.enumerateMatches(in: string, options: [], range: range) { match, flags, stop in
        guard let match = match else { return }
        let baseRange: NSRange = match.range(at: 2)
        // no ruby annotation if the base string includes line breaks
        if attributedSubstring(from: NSRange(location: 0, length: baseRange.upperBound)).size().width > maxLength - 0.1 {
          deleteCharacters(in: NSRange(location: match.range.upperBound - 1, length: 1))
          deleteCharacters(in: NSRange(location: match.range(at: 3).location, length: 1))
          deleteCharacters(in: NSRange(location: match.range(at: 1).location, length: 1))
        } else {
          /* base string must use only one font so that all fall within one glyph run and
           the ruby annotation is aligned with no duplicates */
          var baseFont: NSFont = attribute(.font, at: baseRange.location, effectiveRange: nil) as! NSFont
          baseFont = CTFontCreateForStringWithLanguage(baseFont, mutableString, CFRange(location: baseRange.location, length: baseRange.length), scriptVariant as CFString)
          let rubyString = mutableString.substring(with: match.range(at: 4)) as CFString
          var rubyFont: NSFont = attribute(.font, at: match.range(at: 4).location, effectiveRange: nil) as! NSFont
          rubyFont = NSFont(descriptor: rubyFont.fontDescriptor, size: ceil(rubyFont.pointSize * 0.5))!
          rubyLineHeight = isVertical ? rubyFont.vertical.ascender - rubyFont.vertical.descender + 1.0 : rubyFont.ascender - rubyFont.descender + 1.0
          let rubyAttrs: [CFString: AnyObject] = [kCTFontAttributeName: rubyFont]
          let rubyAnnotation = CTRubyAnnotationCreateWithAttributes(.distributeSpace, .none, .before, rubyString, rubyAttrs as CFDictionary)

          deleteCharacters(in: match.range(at: 3))
          if #available(macOS 12.0, *) {
          } else { // use U+008B as placeholder for line-forward spaces in case ruby is wider than base
            replaceCharacters(in: NSRange(location: baseRange.upperBound, length: 0), with: "\u{008B}")
          }
          let attrs: [NSAttributedString.Key: Any] = [.font: baseFont,
                                                      .verticalGlyphForm: NSNumber(value: isVertical),
                                                      .rubyAnnotation: rubyAnnotation]
          addAttributes(attrs, range: baseRange)
          deleteCharacters(in: match.range(at: 1))
        }
      }
      mutableString.replaceOccurrences(of: "[\u{FFF9}-\u{FFFB}]", with: "", options: [.regularExpression], range: NSRange(location: 0, length: length))
    }
    return ceil(rubyLineHeight)
  }
} // NSMutableAttributedString (NSMutableAttributedStringMarkDownFormatting)

extension NSAttributedString {
  func horizontalInVerticalForms() -> NSAttributedString {
    var attrs = attributes(at: 0, effectiveRange: nil)
    let font = attrs[.font] as! NSFont
    let stringWidth = floor(size().width)
    let height: Double = floor(font.ascender - font.descender)
    let width: Double = max(height, stringWidth)
    let image = NSImage(size: .init(width: height, height: width), flipped: true, drawingHandler: { dstRect in
      NSGraphicsContext.saveGraphicsState()
      let transform = NSAffineTransform()
      transform.rotate(byDegrees: -90)
      transform.concat()
      let origin = NSPoint(x: floor((width - stringWidth) * 0.5 - dstRect.height), y: 0)
      self.draw(at: origin)
      NSGraphicsContext.restoreGraphicsState()
      return true
    })
    image.resizingMode = .stretch
    image.size = .init(width: height, height: height)
    let attm = NSTextAttachment()
    attm.image = image
    attm.bounds = .init(x: 0, y: floor(font.descender), width: height, height: height)
    attrs[.attachment] = attm
    return .init(string: String(Unicode.Scalar(NSTextAttachment.character)!), attributes: attrs)
  }
} // NSAttributedString (NSAttributedStringHorizontalInVerticalForms)

extension NSColorSpace {
  static let labColorSpace: NSColorSpace = {
    let whitePoint: [CGFloat] = [0.950489, 1.0, 1.088840]
    let blackPoint: [CGFloat] = [0.0, 0.0, 0.0]
    let range: [CGFloat] = [-127.0, 127.0, -127.0, 127.0]
    let colorSpaceLab = CGColorSpace(labWhitePoint: whitePoint, blackPoint: blackPoint, range: range)
    return NSColorSpace(cgColorSpace: colorSpaceLab!)!
  }()
} // NSColorSpace

extension NSColor {
  convenience init(lStar: CGFloat, aStar: CGFloat, bStar: CGFloat, alpha: CGFloat) {
    let lum: CGFloat = clamp(lStar, 0.0, 100.0)
    let green_red: CGFloat = clamp(aStar, -127.0, 127.0)
    let blue_yellow: CGFloat = clamp(bStar, -127.0, 127.0)
    let opaque: CGFloat = clamp(alpha, 0.0, 1.0)
    let components: [CGFloat] = [lum, green_red, blue_yellow, opaque]
    self.init(colorSpace: .labColorSpace, components: components, count: 4)
  }

  private var LABComponents: [CGFloat?] {
    if let componentBased = usingType(.componentBased)?.usingColorSpace(.labColorSpace) {
      var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
      componentBased.getComponents(&components)
      components[0] /= 100.0 // Luminance
      components[1] /= 127.0 // Green-Red
      components[2] /= 127.0 // Blue-Yellow
      return components
    }
    return [nil, nil, nil, nil]
  }

  var lStarComponent: CGFloat? { LABComponents[0] }
  var aStarComponent: CGFloat? { LABComponents[1] }
  var bStarComponent: CGFloat? { LABComponents[2] }

  func getLAB(lStar: inout CGFloat?, aStar: inout CGFloat?, bStar: inout CGFloat?, alpha: inout CGFloat?) {
    if lStar != nil { lStar = LABComponents[0] }
    if aStar != nil { aStar = LABComponents[1] }
    if bStar != nil { bStar = LABComponents[2] }
    if alpha != nil { alpha = LABComponents[3] }
  }

  @frozen enum ColorInversionExtent: Int {
    case standard = 0, augmented = 1, moderate = -1
  }

  func invertLuminance(toExtent extent: ColorInversionExtent) -> NSColor {
    if let componentBased = usingType(.componentBased),
       let labColor = componentBased.usingColorSpace(.labColorSpace) {
      var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
      labColor.getComponents(&components)
      switch extent {
      case .augmented:
        components[0] = 100.0 - components[0]
      case .moderate:
        components[0] = 80.0 - components[0] * 0.6
      case .standard:
        components[0] = 90.0 - components[0] * 0.8
      }
      let invertedColor = NSColor(colorSpace: .labColorSpace, components: components, count: 4)
      return invertedColor.usingColorSpace(componentBased.colorSpace)!
    } else {
      return self
    }
  }

  var hooverColor: NSColor {
    if #available(macOS 10.14, *) {
      return withSystemEffect(.rollover)
    } else {
      return NSAppearance.current.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? highlight(withLevel: 0.3)! : shadow(withLevel: 0.3)!
    }
  }

  var disabledColor: NSColor {
    if #available(macOS 10.14, *) {
      return withSystemEffect(.disabled)
    } else {
      return NSAppearance.current.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? shadow(withLevel: 0.3)! : highlight(withLevel: 0.3)!
    }
  }

  func blend(background: NSColor?) -> NSColor {
    return blended(withFraction: kBlendedBackgroundColorFraction, of: background ?? .lightGray)?.withAlphaComponent(alphaComponent) ?? self
  }

  func blendWithColor(_ color: NSColor, ofFraction fraction: CGFloat) -> NSColor? {
    let alpha: CGFloat = alphaComponent * color.alphaComponent
    let opaqueColor: NSColor = withAlphaComponent(1.0).blended(withFraction: fraction, of: color.withAlphaComponent(1.0))!
    return opaqueColor.withAlphaComponent(alpha)
  }
} // NSColor

// MARK: Theme - color scheme and other user configurations

@frozen enum SquirrelStyle: Int, Sendable {
  case light = 0, dark = 1
}

@frozen enum SquirrelStatusMessageType: Sendable {
  case mixed, short, long
}

extension NSFontDescriptor {
  static func create(fullname: String?) -> NSFontDescriptor? {
    if fullname?.isEmpty ?? true {
      return nil
    }
    let fontNames: [String] = fullname!.components(separatedBy: ",")
    var validFontDescriptors: [NSFontDescriptor] = []
    for name in fontNames {
      if let font = NSFont(name: name.trimmingCharacters(in: .whitespaces), size: 0.0) {
        /* If the font name is not valid, NSFontDescriptor will still create something for us.
         However, when we draw the actual text, Squirrel will crash if there is any font descriptor
         with invalid font name. */
        let fontDescriptor = font.fontDescriptor
        let UIFontDescriptor = fontDescriptor.withSymbolicTraits(.UIOptimized)
        validFontDescriptors.append(NSFont(descriptor: UIFontDescriptor, size: 0.0) != nil ? UIFontDescriptor : fontDescriptor)
      }
    }
    if let fontDescriptor = validFontDescriptors.first {
      var fallbackDescriptors: [NSFontDescriptor] = Array(validFontDescriptors.dropFirst())
      fallbackDescriptors.append(NSFontDescriptor(name: "AppleColorEmoji", size: 0.0))
      return fontDescriptor.addingAttributes([.cascadeList: fallbackDescriptors as NSArray])
    } else {
      return nil
    }
  }
}

extension NSFont {
  func lineHeight(asVertical: Bool) -> Double {
    var lineHeight: Double = ceil(asVertical ? vertical.ascender - vertical.descender : ascender - descender)
    let fallbackList = fontDescriptor.fontAttributes[.cascadeList] as! [NSFontDescriptor]
    for fallback in fallbackList {
      if let fallbackFont = NSFont(descriptor: fallback, size: pointSize) {
        let fallbackHeight = asVertical ? fallbackFont.vertical.ascender - fallbackFont.vertical.descender : fallbackFont.ascender - fallbackFont.descender
        lineHeight = max(lineHeight, ceil(fallbackHeight))
      }
    }
    return lineHeight
  }
}

private func updateCandidateListLayout(isLinear: inout Bool, isTabular: inout Bool, config: SquirrelConfig, prefix: String) {
  if let candidateListLayout = config.string(forOption: "\(prefix)/candidate_list_layout") {
    if candidateListLayout.caseInsensitiveCompare("stacked") == .orderedSame {
      isLinear = false
      isTabular = false
    } else if candidateListLayout.caseInsensitiveCompare("linear") == .orderedSame {
      isLinear = true
      isTabular = false
    } else if candidateListLayout.caseInsensitiveCompare("tabular") == .orderedSame {
      // `isTabular` is a derived layout of `isLinear`; isTabular implies isLinear
      isLinear = true
      isTabular = true
    }
  } else if let horizontal = config.nullableBool(forOption: "\(prefix)/horizontal") {
    // Deprecated. Not to be confused with text_orientation: horizontal
    isLinear = horizontal
    isTabular = false
  }
}

private func updateTextOrientation(isVertical: inout Bool, config: SquirrelConfig, prefix: String) {
  if let textOrientation = config.string(forOption: "\(prefix)/text_orientation") {
    if textOrientation.caseInsensitiveCompare("horizontal") == .orderedSame {
      isVertical = false
    } else if textOrientation.caseInsensitiveCompare("vertical") == .orderedSame {
      isVertical = true
    }
  } else if let vertical = config.nullableBool(forOption: "\(prefix)/vertical") {
    isVertical = vertical
  }
}

// functions for post-retrieve processing
func positive(param: Double) -> Double { return param < 0.0 ? 0.0 : param }
func pos_round(param: Double) -> Double { return param < 0.0 ? 0.0 : round(param) }
func pos_ceil(param: Double) -> Double { return param < 0.0 ? 0.0 : ceil(param) }
func clamp_uni(param: Double) -> Double { return param < 0.0 ? 0.0 : param > 1.0 ? 1.0 : param }

final class SquirrelTheme: NSObject {
  private(set) var backColor: NSColor = .controlBackgroundColor
  private(set) var preeditForeColor: NSColor = .textColor
  private(set) var textForeColor: NSColor = .controlTextColor
  private(set) var commentForeColor: NSColor = .secondaryLabelColor
  private(set) var labelForeColor: NSColor = .secondaryLabelColor
  private(set) var hilitedPreeditForeColor: NSColor = .selectedTextColor
  private(set) var hilitedTextForeColor: NSColor = .selectedMenuItemTextColor
  private(set) var hilitedCommentForeColor: NSColor = .alternateSelectedControlTextColor
  private(set) var hilitedLabelForeColor: NSColor = .alternateSelectedControlTextColor
  private(set) var dimmedLabelForeColor: NSColor?
  private(set) var hilitedCandidateBackColor: NSColor?
  private(set) var hilitedPreeditBackColor: NSColor?
  private(set) var candidateBackColor: NSColor?
  private(set) var preeditBackColor: NSColor?
  private(set) var borderColor: NSColor?
  private(set) var backImage: NSImage?

  private(set) var borderInsets: NSSize = .zero
  private(set) var cornerRadius: Double = 0
  private(set) var hilitedCornerRadius: Double = 0
  private(set) var fullWidth: Double
  private(set) var lineSpacing: Double = 0
  private(set) var preeditSpacing: Double = 0
  private(set) var opacity: Double = 1
  private(set) var lineLength: Double = 0
  private(set) var shadowSize: Double = 0
  private(set) var translucency: Float = 0

  private(set) var stackColors: Bool = false
  private(set) var showPaging: Bool = false
  private(set) var rememberSize: Bool = false
  private(set) var isTabular: Bool = false
  private(set) var isLinear: Bool = false
  private(set) var isVertical: Bool = false
  private(set) var inlinePreedit: Bool = false
  private(set) var inlineCandidate: Bool = true

  private(set) var textAttrs: [NSAttributedString.Key: Any] = [:]
  private(set) var labelAttrs: [NSAttributedString.Key: Any] = [:]
  private(set) var commentAttrs: [NSAttributedString.Key: Any] = [:]
  private(set) var preeditAttrs: [NSAttributedString.Key: Any] = [:]
  private(set) var pagingAttrs: [NSAttributedString.Key: Any] = [:]
  private(set) var statusAttrs: [NSAttributedString.Key: Any] = [:]

  private(set) var candidateParagraphStyle: NSParagraphStyle
  private(set) var preeditParagraphStyle: NSParagraphStyle
  private(set) var statusParagraphStyle: NSParagraphStyle
  private(set) var pagingParagraphStyle: NSParagraphStyle
  private(set) var truncatedParagraphStyle: NSParagraphStyle?

  private(set) var separator: NSAttributedString
  private(set) var symbolDeleteFill: NSAttributedString?
  private(set) var symbolDeleteStroke: NSAttributedString?
  private(set) var symbolBackFill: NSAttributedString?
  private(set) var symbolBackStroke: NSAttributedString?
  private(set) var symbolForwardFill: NSAttributedString?
  private(set) var symbolForwardStroke: NSAttributedString?
  private(set) var symbolCompress: NSAttributedString?
  private(set) var symbolExpand: NSAttributedString?
  private(set) var symbolLock: NSAttributedString?

  private(set) var labels: [String] = ["１", "２", "３", "４", "５"]
  private(set) var candidateTemplate: NSAttributedString
  private(set) var candidateHilitedTemplate: NSAttributedString
  private(set) var candidateDimmedTemplate: NSAttributedString?
  private(set) var selectKeys: String = "12345"
  private(set) var candidateFormat: String = kDefaultCandidateFormat
  private(set) var scriptVariant: String = "zh"
  private(set) var statusMessageType: SquirrelStatusMessageType = .mixed
  private(set) var pageSize: Int = 5
  private(set) var style: SquirrelStyle

  init(style: SquirrelStyle) {
    self.style = style

    let candidateParagraphStyle = NSMutableParagraphStyle()
    candidateParagraphStyle.alignment = .left
    /* Use left-to-right marks to declare the default writing direction and prevent strong right-to-left
     characters from setting the writing direction in case the label are direction-less symbols */
    candidateParagraphStyle.baseWritingDirection = .leftToRight
    let preeditParagraphStyle = candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    let pagingParagraphStyle = candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    let statusParagraphStyle = candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    preeditParagraphStyle.lineBreakMode = .byWordWrapping
    statusParagraphStyle.lineBreakMode = .byTruncatingTail
    self.candidateParagraphStyle = candidateParagraphStyle.copy() as! NSParagraphStyle
    self.preeditParagraphStyle = preeditParagraphStyle.copy() as! NSParagraphStyle
    self.pagingParagraphStyle = pagingParagraphStyle.copy() as! NSParagraphStyle
    self.statusParagraphStyle = statusParagraphStyle.copy() as! NSParagraphStyle

    let userFont: NSFont! = NSFont(descriptor: .create(fullname: NSFont.userFont(ofSize: kDefaultFontSize)!.fontName)!, size: kDefaultFontSize)
    let userMonoFont: NSFont! = NSFont(descriptor: .create(fullname: NSFont.userFixedPitchFont(ofSize: kDefaultFontSize)!.fontName)!, size: kDefaultFontSize)
    let monoDigitFont: NSFont! = .monospacedDigitSystemFont(ofSize: kDefaultFontSize, weight: .regular)

    textAttrs[.foregroundColor] = NSColor.controlTextColor
    textAttrs[.font] = userFont
    // Use left-to-right embedding to prevent right-to-left text from changing the layout of the candidate.
    textAttrs[.writingDirection] = NSArray(object: NSNumber(value: 0))
    labelAttrs[.foregroundColor] = NSColor.labelColor
    labelAttrs[.font] = userMonoFont
    labelAttrs[.strokeWidth] = NSNumber(value: -2.0 / kDefaultFontSize)
    commentAttrs[.foregroundColor] = NSColor.secondaryLabelColor
    commentAttrs[.font] = userFont
    preeditAttrs[.foregroundColor] = NSColor.textColor
    preeditAttrs[.font] = userFont
    preeditAttrs[.ligature] = NSNumber(value: 0)
    preeditAttrs[.paragraphStyle] = preeditParagraphStyle
    pagingAttrs[.font] = monoDigitFont
    pagingAttrs[.foregroundColor] = NSColor.controlTextColor
    pagingAttrs[.paragraphStyle] = pagingParagraphStyle
    statusAttrs = commentAttrs
    statusAttrs[.paragraphStyle] = statusParagraphStyle

    separator = NSAttributedString(string: "\n", attributes: commentAttrs)
    fullWidth = ceil(NSAttributedString(string: kFullWidthSpace, attributes: commentAttrs).size().width)
    let template = NSMutableAttributedString(string: "%c. ", attributes: labelAttrs)
    template.append(.init(string: "%@", attributes: textAttrs))
    candidateTemplate = template.copy() as! NSAttributedString
    candidateHilitedTemplate = template.copy() as! NSAttributedString

    super.init()
    updateCandidateTemplates(forAttributesOnly: false)
    updateSeperatorAndSymbolAttrs()
  }

  override convenience init() {
    self.init(style: .light)
  }

  private func updateSeperatorAndSymbolAttrs() {
    var sepAttrs: [NSAttributedString.Key: Any] = commentAttrs
    sepAttrs[.verticalGlyphForm] = NSNumber(value: false)
    sepAttrs[.kern] = NSNumber(value: 0.0)
    separator = NSAttributedString(string: isLinear ? (isTabular ? "\u{3000}\t\u{001D}" : "\u{3000}\u{001D}") : "\n", attributes: sepAttrs)
    // Symbols for function buttons
    let attmCharacter = String(Unicode.Scalar(NSTextAttachment.character)!)

    let attmDeleteFill = NSTextAttachment()
    attmDeleteFill.image = NSImage(named: "Symbols/delete.backward.fill")
    var attrsDeleteFill: [NSAttributedString.Key: Any] = preeditAttrs
    attrsDeleteFill[.attachment] = attmDeleteFill
    attrsDeleteFill[.verticalGlyphForm] = NSNumber(value: false)
    symbolDeleteFill = NSAttributedString(string: attmCharacter, attributes: attrsDeleteFill)
    let attmDeleteStroke = NSTextAttachment()
    attmDeleteStroke.image = NSImage(named: "Symbols/delete.backward")
    var attrsDeleteStroke: [NSAttributedString.Key: Any] = preeditAttrs
    attrsDeleteStroke[.attachment] = attmDeleteStroke
    attrsDeleteStroke[.verticalGlyphForm] = NSNumber(value: false)
    symbolDeleteStroke = NSAttributedString(string: attmCharacter, attributes: attrsDeleteStroke)

    if isTabular {
      let attmCompress = NSTextAttachment()
      attmCompress.image = NSImage(named: "Symbols/rectangle.compress.vertical")
      var attrsCompress: [NSAttributedString.Key: Any] = pagingAttrs
      attrsCompress[.attachment] = attmCompress
      symbolCompress = NSAttributedString(string: attmCharacter, attributes: attrsCompress)
      let attmExpand = NSTextAttachment()
      attmExpand.image = NSImage(named: "Symbols/rectangle.expand.vertical")
      var attrsExpand: [NSAttributedString.Key: Any] = pagingAttrs
      attrsExpand[.attachment] = attmExpand
      symbolExpand = NSAttributedString(string: attmCharacter, attributes: attrsExpand)
      let attmLock = NSTextAttachment()
      attmLock.image = NSImage(named: "Symbols/lock\(isVertical ? ".vertical" : "").fill")
      var attrsLock: [NSAttributedString.Key: Any] = pagingAttrs
      attrsLock[.attachment] = attmLock
      symbolLock = NSAttributedString(string: attmCharacter, attributes: attrsLock)
    } else {
      symbolCompress = nil
      symbolExpand = nil
      symbolLock = nil
    }

    if showPaging {
      let attmBackFill = NSTextAttachment()
      attmBackFill.image = NSImage(named: "Symbols/chevron.\(isLinear ? "up" : "left").circle.fill")
      var attrsBackFill: [NSAttributedString.Key: Any] = pagingAttrs
      attrsBackFill[.attachment] = attmBackFill
      symbolBackFill = NSAttributedString(string: attmCharacter, attributes: attrsBackFill)
      let attmBackStroke = NSTextAttachment()
      attmBackStroke.image = NSImage(named: "Symbols/chevron.\(isLinear ? "up" : "left").circle")
      var attrsBackStroke: [NSAttributedString.Key: Any] = pagingAttrs
      attrsBackStroke[.attachment] = attmBackStroke
      symbolBackStroke = NSAttributedString(string: attmCharacter, attributes: attrsBackStroke)
      let attmForwardFill = NSTextAttachment()
      attmForwardFill.image = NSImage(named: "Symbols/chevron.\(isLinear ? "down" : "right").circle.fill")
      var attrsForwardFill: [NSAttributedString.Key: Any] = pagingAttrs
      attrsForwardFill[.attachment] = attmForwardFill
      symbolForwardFill = NSAttributedString(string: attmCharacter, attributes: attrsForwardFill)
      let attmForwardStroke = NSTextAttachment()
      attmForwardStroke.image = NSImage(named: "Symbols/chevron.\(isLinear ? "down" : "right").circle")
      var attrsForwardStroke: [NSAttributedString.Key: Any] = pagingAttrs
      attrsForwardStroke[.attachment] = attmForwardStroke
      symbolForwardStroke = NSAttributedString(string: attmCharacter, attributes: attrsForwardStroke)
    } else {
      symbolBackFill = nil
      symbolBackStroke = nil
      symbolForwardFill = nil
      symbolForwardStroke = nil
    }
  }

  func updateLabelsWithConfig(_ config: SquirrelConfig, directUpdate update: Bool) {
    let menuSize: Int = config.nullableInt(forOption: "menu/page_size") ?? 5
    var labels: [String] = []
    var selectKeys: String? = config.string(forOption: "menu/alternative_select_keys")
    let selectLabels: [String] = config.list(forOption: "menu/alternative_select_labels") ?? []
    if !selectLabels.isEmpty {
      for i in 0 ..< menuSize {
        labels.append(selectLabels[i])
      }
    }
    if selectKeys != nil {
      if selectLabels.isEmpty {
        for i in 0 ..< menuSize {
          let keyCap = String(selectKeys![selectKeys!.index(selectKeys!.startIndex, offsetBy: i)])
          labels.append(keyCap.uppercased().applyingTransform(.fullwidthToHalfwidth, reverse: true)!)
        }
      }
    } else {
      selectKeys = String("1234567890".prefix(menuSize))
      if selectLabels.isEmpty {
        for i in 0 ..< menuSize {
          let numeral = String(selectKeys![selectKeys!.index(selectKeys!.startIndex, offsetBy: i)])
          labels.append(numeral.applyingTransform(.fullwidthToHalfwidth, reverse: true)!)
        }
      }
    }
    updateSelectKeys(selectKeys!, labels: labels, directUpdate: update)
  }

  func updateSelectKeys(_ selectKeys: String, labels: [String], directUpdate update: Bool) {
    self.selectKeys = selectKeys
    self.labels = labels
    pageSize = labels.count
    if update {
      updateCandidateTemplates(forAttributesOnly: true)
    }
  }

  func updateCandidateFormat(_ candidateFormat: String) {
    let attrsOnly: Bool = candidateFormat == self.candidateFormat
    if !attrsOnly {
      self.candidateFormat = candidateFormat
    }
    updateCandidateTemplates(forAttributesOnly: attrsOnly)
    updateSeperatorAndSymbolAttrs()
  }

  private func updateCandidateTemplates(forAttributesOnly attrsOnly: Bool) {
    var candidateTemplate: NSMutableAttributedString
    if !attrsOnly {
      // validate candidate format: must have enumerator '%c' before candidate '%@'
      var candidateFormat: String = self.candidateFormat
      var textRange: Range<String.Index>? = candidateFormat.range(of: "%@", options: [.literal])
      if textRange == nil {
        candidateFormat += "%@"
      }
      var labelRange: Range<String.Index>? = candidateFormat.range(of: "%c", options: [.literal])
      if labelRange == nil {
        candidateFormat = "%c" + candidateFormat
        labelRange = candidateFormat.range(of: "%c", options: [.literal])
      }
      textRange = candidateFormat.range(of: "%@", options: [.literal])
      if labelRange!.lowerBound > textRange!.lowerBound {
        candidateFormat = kDefaultCandidateFormat
      }
      var labels: [String] = self.labels
      var enumRange: Range<String.Index>?
      let labelCharacters: CharacterSet = CharacterSet(charactersIn: labels.joined())
      if CharacterSet.fullWidthDigits.isSuperset(of: labelCharacters) { // ０１...９
        if let range = candidateFormat.range(of: "%c\u{20E3}", options: [.literal]) { // 1︎⃣...9︎⃣0︎⃣
          enumRange = range
          for i in 0 ..< pageSize {
            let wchar: UInt32 = labels[i].unicodeScalars.first!.value - 0xFF10 + 0x0030
            labels[i] = String(Character(UnicodeScalar(wchar)!)) + "\u{FE0E}\u{20E3}"
          }
        } else if let range = candidateFormat.range(of: "%c\u{20DD}", options: [.literal]) { // ①...⑨⓪
          enumRange = range
          for i in 0 ..< pageSize {
            let wchar: UInt32 = labels[i].unicodeScalars.first!.value == 0xFF10 ? 0x24EA : labels[i].unicodeScalars.first!.value - 0xFF11 + 0x2460
            labels[i] = String(Character(UnicodeScalar(wchar)!))
          }
        } else if let range = candidateFormat.range(of: "(%c)", options: [.literal]) { // ⑴...⑼⑽
          enumRange = range
          for i in 0 ..< pageSize {
            let wchar: UInt32 = labels[i].unicodeScalars.first!.value == 0xFF10 ? 0x247D : labels[i].unicodeScalars.first!.value - 0xFF11 + 0x2474
            labels[i] = String(Character(UnicodeScalar(wchar)!))
          }
        } else if let range = candidateFormat.range(of: "%c.", options: [.literal]) { // ⒈...⒐🄀
          enumRange = range
          for i in 0 ..< pageSize {
            let wchar: UInt32 = labels[i].unicodeScalars.first!.value == 0xFF10 ? 0x1F100 : labels[i].unicodeScalars.first!.value - 0xFF11 + 0x2488
            labels[i] = String(Character(UnicodeScalar(wchar)!))
          }
        } else if let range = candidateFormat.range(of: "%c,", options: [.literal]) { // 🄂...🄊🄁
          enumRange = range
          for i in 0 ..< pageSize {
            let wchar: UInt32 = labels[i].unicodeScalars.first!.value - 0xFF10 + 0x1F101
            labels[i] = String(Character(UnicodeScalar(wchar)!))
          }
        }
      } else if CharacterSet.fullWidthLatinCapitals.isSuperset(of: labelCharacters) {
        if let range = candidateFormat.range(of: "%c\u{20DD}", options: [.literal]) { // Ⓐ...Ⓩ
          enumRange = range
          for i in 0 ..< pageSize {
            let wchar: UInt32 = labels[i].unicodeScalars.first!.value - 0xFF21 + 0x24B6
            labels[i] = String(Character(UnicodeScalar(wchar)!))
          }
        } else if let range = candidateFormat.range(of: "(%c)", options: [.literal]) { // 🄐...🄩
          enumRange = range
          for i in 0 ..< pageSize {
            let wchar: UInt32 = labels[i].unicodeScalars.first!.value - 0xFF21 + 0x1F110
            labels[i] = String(Character(UnicodeScalar(wchar)!))
          }
        } else if let range = candidateFormat.range(of: "%c\u{20DE}", options: [.literal]) { // 🄰...🅉
          enumRange = range
          for i in 0 ..< pageSize {
            let wchar: UInt32 = labels[i].unicodeScalars.first!.value - 0xFF21 + 0x1F130
            labels[i] = String(Character(UnicodeScalar(wchar)!))
          }
        }
      }
      if enumRange != nil {
        candidateFormat = candidateFormat.replacingCharacters(in: enumRange!, with: "%c")
        self.labels = labels
      }
      candidateTemplate = NSMutableAttributedString(string: candidateFormat)
    } else {
      candidateTemplate = self.candidateTemplate.mutableCopy() as! NSMutableAttributedString
    }
    // make sure label font can render all possible enumerators
    let labelFont = labelAttrs[.font] as! NSFont
    let labelString = labels.joined() as NSString
    let substituteFont: NSFont = CTFontCreateForStringWithLanguage(labelFont, labelString, CFRange(location: 0, length: labelString.length), scriptVariant as CFString)
    if substituteFont != labelFont {
      let monoDigitAttrs: [NSFontDescriptor.AttributeName: [[NSFontDescriptor.FeatureKey: NSNumber]]] =
        [.featureSettings: [[.typeIdentifier: NSNumber(value: kNumberSpacingType),
                             .selectorIdentifier: NSNumber(value: kMonospacedNumbersSelector)],
                            [.typeIdentifier: NSNumber(value: kTextSpacingType),
                             .selectorIdentifier: NSNumber(value: kHalfWidthTextSelector)]]]
      let subFontDescriptor = substituteFont.fontDescriptor.addingAttributes(monoDigitAttrs)
      labelAttrs[.font] = NSFont(descriptor: subFontDescriptor, size: labelFont.pointSize)
    }

    var textRange: NSRange = candidateTemplate.mutableString.range(of: "%@", options: [.literal])
    var labelRange = NSRange(location: 0, length: textRange.location)
    var commentRange = NSRange(location: textRange.upperBound, length: candidateTemplate.length - textRange.upperBound)
    // parse markdown formats
    candidateTemplate.setAttributes(labelAttrs, range: labelRange)
    candidateTemplate.setAttributes(textAttrs, range: textRange)
    if commentRange.length > 0 {
      candidateTemplate.setAttributes(commentAttrs, range: commentRange)
    }

    // parse markdown formats
    if !attrsOnly {
      candidateTemplate.formatMarkDown()
      // add placeholder for comment `%s`
      textRange = candidateTemplate.mutableString.range(of: "%@", options: [.literal])
      labelRange = NSRange(location: 0, length: textRange.location)
      commentRange = NSRange(location: textRange.upperBound, length: candidateTemplate.length - textRange.upperBound)
      if commentRange.length > 0 {
        candidateTemplate.replaceCharacters(in: commentRange, with: kTipSpecifier + candidateTemplate.mutableString.substring(with: commentRange))
      } else {
        candidateTemplate.append(NSAttributedString(string: kTipSpecifier, attributes: commentAttrs))
      }
      commentRange.length += kTipSpecifier.utf16.count

      if !isLinear {
        candidateTemplate.replaceCharacters(in: NSRange(location: textRange.location, length: 0), with: "\t")
        labelRange.length += 1
        textRange.location += 1
        commentRange.location += 1
      }
    }

    // for stacked layout, calculate head indent
    let candidateParagraphStyle = self.candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    if !isLinear {
      var indent: Double = 0.0
      let labelFormat = candidateTemplate.attributedSubstring(from: NSRange(location: 0, length: labelRange.length - 1))
      for label in labels {
        let enumString = labelFormat.mutableCopy() as! NSMutableAttributedString
        let enumRange = enumString.mutableString.range(of: "%c", options: [.literal])
        enumString.mutableString.replaceCharacters(in: enumRange, with: label)
        enumString.addAttribute(.verticalGlyphForm, value: NSNumber(value: isVertical), range: NSRange(location: enumRange.location, length: label.utf16.count))
        indent = max(indent, enumString.size().width)
      }
      indent = floor(indent) + 1.0
      candidateParagraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
      candidateParagraphStyle.headIndent = indent
      self.candidateParagraphStyle = candidateParagraphStyle.copy() as! NSParagraphStyle
      truncatedParagraphStyle = nil
    } else {
      candidateParagraphStyle.tabStops = []
      candidateParagraphStyle.headIndent = 0.0
      self.candidateParagraphStyle = candidateParagraphStyle.copy() as! NSParagraphStyle
      let truncatedParagraphStyle = candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
      truncatedParagraphStyle.lineBreakMode = .byTruncatingMiddle
      truncatedParagraphStyle.tighteningFactorForTruncation = 0.0
      self.truncatedParagraphStyle = truncatedParagraphStyle.copy() as? NSParagraphStyle
    }

    textAttrs[.paragraphStyle] = candidateParagraphStyle
    commentAttrs[.paragraphStyle] = candidateParagraphStyle
    labelAttrs[.paragraphStyle] = candidateParagraphStyle
    candidateTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSRange(location: 0, length: candidateTemplate.length))
    self.candidateTemplate = candidateTemplate.copy() as! NSAttributedString

    let candidateHilitedTemplate = candidateTemplate.mutableCopy() as! NSMutableAttributedString
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedLabelForeColor, range: labelRange)
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedTextForeColor, range: textRange)
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedCommentForeColor, range: commentRange)
    self.candidateHilitedTemplate = candidateHilitedTemplate.copy() as! NSAttributedString

    if isTabular {
      let candidateDimmedTemplate = candidateTemplate.mutableCopy() as! NSMutableAttributedString
      candidateDimmedTemplate.addAttribute(.foregroundColor, value: dimmedLabelForeColor!, range: labelRange)
      self.candidateDimmedTemplate = candidateDimmedTemplate.copy() as? NSAttributedString
    } else {
      candidateDimmedTemplate = nil
    }
  }

  func updateStatusMessageType(_ type: String?) {
    if type?.caseInsensitiveCompare("long") == .orderedSame {
      statusMessageType = .long
    } else if type?.caseInsensitiveCompare("short") == .orderedSame {
      statusMessageType = .short
    } else {
      statusMessageType = .mixed
    }
  }

  func updateThemeWithConfig(_ config: SquirrelConfig, styleOptions: Set<String>, scriptVariant: String) {
    /*** INTERFACE ***/
    var isLinear: Bool = false
    var isTabular: Bool = false
    var isVertical: Bool = false
    updateCandidateListLayout(isLinear: &isLinear, isTabular: &isTabular, config: config, prefix: "style")
    updateTextOrientation(isVertical: &isVertical, config: config, prefix: "style")
    var inlinePreedit: Bool? = config.nullableBool(forOption: "style/inline_preedit")
    var inlineCandidate: Bool? = config.nullableBool(forOption: "style/inline_candidate")
    var showPaging: Bool? = config.nullableBool(forOption: "style/show_paging")
    var rememberSize: Bool? = config.nullableBool(forOption: "style/remember_size", alias: "memorize_size")
    var statusMessageType: String? = config.string(forOption: "style/status_message_type")
    var candidateFormat: String? = config.string(forOption: "style/candidate_format")
    /*** TYPOGRAPHY ***/
    var fontName: String? = config.string(forOption: "style/font_face")
    var fontSize: Double? = config.nullableDouble(forOption: "style/font_point", constraint: pos_round)
    var labelFontName: String? = config.string(forOption: "style/label_font_face")
    var labelFontSize: Double? = config.nullableDouble(forOption: "style/label_font_point", constraint: pos_round)
    var commentFontName: String? = config.string(forOption: "style/comment_font_face")
    var commentFontSize: Double? = config.nullableDouble(forOption: "style/comment_font_point", constraint: pos_round)
    var opacity: Double? = config.nullableDouble(forOption: "style/opacity", alias: "alpha", constraint: clamp_uni)
    var translucency: Double? = config.nullableDouble(forOption: "style/translucency", constraint: clamp_uni)
    var stackColors: Bool? = config.nullableBool(forOption: "style/stack_colors", alias: "mutual_exclusive")
    var cornerRadius: Double? = config.nullableDouble(forOption: "style/corner_radius", constraint: positive)
    var hilitedCornerRadius: Double? = config.nullableDouble(forOption: "style/hilited_corner_radius", constraint: positive)
    var borderHeight: Double? = config.nullableDouble(forOption: "style/border_height", constraint: pos_ceil)
    var borderWidth: Double? = config.nullableDouble(forOption: "style/border_width", constraint: pos_ceil)
    var lineSpacing: Double? = config.nullableDouble(forOption: "style/line_spacing", constraint: pos_round)
    var preeditSpacing: Double? = config.nullableDouble(forOption: "style/spacing", constraint: pos_round)
    var baseOffset: Double? = config.nullableDouble(forOption: "style/base_offset")
    var lineLength: Double? = config.nullableDouble(forOption: "style/line_length")
    var shadowSize: Double? = config.nullableDouble(forOption: "style/shadow_size", constraint: positive)
    /*** CHROMATICS ***/
    var backColor: NSColor?
    var borderColor: NSColor?
    var preeditBackColor: NSColor?
    var preeditForeColor: NSColor?
    var candidateBackColor: NSColor?
    var textForeColor: NSColor?
    var commentForeColor: NSColor?
    var labelForeColor: NSColor?
    var hilitedPreeditBackColor: NSColor?
    var hilitedPreeditForeColor: NSColor?
    var hilitedCandidateBackColor: NSColor?
    var hilitedTextForeColor: NSColor?
    var hilitedCommentForeColor: NSColor?
    var hilitedLabelForeColor: NSColor?
    var backImage: NSImage?

    var colorScheme: String?
    if style == .dark {
      for option in styleOptions {
        if let value = config.string(forOption: "style/\(option)/color_scheme_dark") {
          colorScheme = value; break
        }
      }
      colorScheme ?= config.string(forOption: "style/color_scheme_dark")
    }
    if colorScheme == nil {
      for option in styleOptions {
        if let value = config.string(forOption: "style/\(option)/color_scheme") {
          colorScheme = value; break
        }
      }
      colorScheme ?= config.string(forOption: "style/color_scheme")
    }
    let isNative: Bool = (colorScheme == nil) || (colorScheme! == "native")
    var configPrefixes: [String] = styleOptions.map { "style/" + $0 }
    if !isNative {
      configPrefixes.insert("preset_color_schemes/" + colorScheme!, at: 0)
    }

    // get color scheme and then check possible overrides from styleSwitcher
    for prefix in configPrefixes {
      /*** CHROMATICS override ***/
      config.colorSpace =? config.string(forOption: prefix + "/color_space")
      backColor =? config.color(forOption: prefix + "/back_color")
      borderColor =? config.color(forOption: prefix + "/border_color")
      preeditBackColor =? config.color(forOption: prefix + "/preedit_back_color")
      preeditForeColor =? config.color(forOption: prefix + "/text_color")
      candidateBackColor =? config.color(forOption: prefix + "/candidate_back_color")
      textForeColor =? config.color(forOption: prefix + "/candidate_text_color")
      commentForeColor =? config.color(forOption: prefix + "/comment_text_color")
      labelForeColor =? config.color(forOption: prefix + "/label_color")
      hilitedPreeditBackColor =? config.color(forOption: prefix + "/hilited_back_color")
      hilitedPreeditForeColor =? config.color(forOption: prefix + "/hilited_text_color")
      hilitedCandidateBackColor =? config.color(forOption: prefix + "/hilited_candidate_back_color")
      hilitedTextForeColor =? config.color(forOption: prefix + "/hilited_candidate_text_color")
      hilitedCommentForeColor =? config.color(forOption: prefix + "/hilited_comment_text_color")
      // for backward compatibility, `labelHilited_color` and `hilited_candidateLabel_color` are both valid
      hilitedLabelForeColor =? config.color(forOption: prefix + "/label_hilited_color", alias: "hilited_candidate_label_color")
      backImage =? config.image(forOption: prefix + "/back_image")

      /* the following per-color-scheme configurations, if exist, will
       override configurations with the same name under the global 'style' section */
      /*** INTERFACE override ***/
      updateCandidateListLayout(isLinear: &isLinear, isTabular: &isTabular, config: config, prefix: prefix)
      updateTextOrientation(isVertical: &isVertical, config: config, prefix: prefix)
      inlinePreedit =? config.nullableBool(forOption: prefix + "/inline_preedit")
      inlineCandidate =? config.nullableBool(forOption: prefix + "/inline_candidate")
      showPaging =? config.nullableBool(forOption: prefix + "/show_paging")
      rememberSize =? config.nullableBool(forOption: prefix + "/remember_size", alias: "memorize_size")
      statusMessageType =? config.string(forOption: prefix + "/status_message_type")
      candidateFormat =? config.string(forOption: prefix + "/candidate_format")
      /*** TYPOGRAPHY override ***/
      fontName =? config.string(forOption: prefix + "/font_face")
      fontSize =? config.nullableDouble(forOption: prefix + "/font_point", constraint: pos_round)
      labelFontName =? config.string(forOption: prefix + "/label_font_face")
      labelFontSize =? config.nullableDouble(forOption: prefix + "/label_font_point", constraint: pos_round)
      commentFontName =? config.string(forOption: prefix + "/comment_font_face")
      commentFontSize =? config.nullableDouble(forOption: prefix + "/comment_font_point", constraint: pos_round)
      opacity =? config.nullableDouble(forOption: prefix + "/opacity", alias: "alpha", constraint: clamp_uni)
      translucency =? config.nullableDouble(forOption: prefix + "/translucency", constraint: clamp_uni)
      stackColors =? config.nullableBool(forOption: prefix + "/stack_colors", alias: "mutual_exclusive")
      cornerRadius =? config.nullableDouble(forOption: prefix + "/corner_radius", constraint: positive)
      hilitedCornerRadius =? config.nullableDouble(forOption: prefix + "/hilited_corner_radius", constraint: positive)
      borderHeight =? config.nullableDouble(forOption: prefix + "/border_height", constraint: pos_ceil)
      borderWidth =? config.nullableDouble(forOption: prefix + "/border_width", constraint: pos_ceil)
      lineSpacing =? config.nullableDouble(forOption: prefix + "/line_spacing", constraint: pos_round)
      preeditSpacing =? config.nullableDouble(forOption: prefix + "/spacing", constraint: pos_round)
      baseOffset =? config.nullableDouble(forOption: prefix + "/base_offset")
      lineLength =? config.nullableDouble(forOption: prefix + "/line_length")
      shadowSize =? config.nullableDouble(forOption: prefix + "/shadow_size", constraint: positive)
    }

    /*** TYPOGRAPHY refinement ***/
    fontSize ?= kDefaultFontSize
    labelFontSize ?= fontSize
    commentFontSize ?= fontSize
    let monoDigitAttrs: [NSFontDescriptor.AttributeName: [[NSFontDescriptor.FeatureKey: NSNumber]]] =
      [.featureSettings: [[.typeIdentifier: NSNumber(value: kNumberSpacingType),
                           .selectorIdentifier: NSNumber(value: kMonospacedNumbersSelector)],
                          [.typeIdentifier: NSNumber(value: kTextSpacingType),
                           .selectorIdentifier: NSNumber(value: kHalfWidthTextSelector)]]]

    let fontDescriptor: NSFontDescriptor = .create(fullname: fontName) ?? .create(fullname: NSFont.userFont(ofSize: 0)?.fontName)!
    let font = NSFont(descriptor: fontDescriptor, size: fontSize!)!
    let labelFontDescriptor: NSFontDescriptor? = (.create(fullname: labelFontName) ?? fontDescriptor)!.addingAttributes(monoDigitAttrs)
    let labelFont: NSFont = labelFontDescriptor != nil ? NSFont(descriptor: labelFontDescriptor!, size: labelFontSize!)! : .monospacedDigitSystemFont(ofSize: labelFontSize!, weight: .regular)
    let commentFontDescriptor: NSFontDescriptor? = .create(fullname: commentFontName)
    let commentFont = NSFont(descriptor: commentFontDescriptor ?? fontDescriptor, size: commentFontSize!)!
    let pagingFont: NSFont = .monospacedDigitSystemFont(ofSize: labelFontSize!, weight: .regular)

    let fontHeight: Double = font.lineHeight(asVertical: isVertical)
    let labelFontHeight: Double = labelFont.lineHeight(asVertical: isVertical)
    let commentFontHeight: Double = commentFont.lineHeight(asVertical: isVertical)
    let lineHeight: Double = max(fontHeight, labelFontHeight, commentFontHeight)
    let fullWidth: Double = ceil(NSAttributedString(string: kFullWidthSpace, attributes: [.font: commentFont]).size().width)
    preeditSpacing ?= 0
    lineSpacing ?= 0

    let candidateParagraphStyle = self.candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    candidateParagraphStyle.minimumLineHeight = lineHeight
    candidateParagraphStyle.maximumLineHeight = lineHeight
    candidateParagraphStyle.paragraphSpacingBefore = isLinear ? 0.0 : ceil(lineSpacing! * 0.5)
    candidateParagraphStyle.paragraphSpacing = isLinear ? 0.0 : floor(lineSpacing! * 0.5)
    candidateParagraphStyle.lineSpacing = isLinear ? lineSpacing! : 0.0
    candidateParagraphStyle.tabStops = []
    candidateParagraphStyle.defaultTabInterval = fullWidth * 2
    self.candidateParagraphStyle = candidateParagraphStyle.copy() as! NSParagraphStyle

    let preeditParagraphStyle = self.preeditParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    preeditParagraphStyle.minimumLineHeight = fontHeight
    preeditParagraphStyle.maximumLineHeight = fontHeight
    preeditParagraphStyle.paragraphSpacing = preeditSpacing!
    preeditParagraphStyle.tabStops = []
    self.preeditParagraphStyle = preeditParagraphStyle.copy() as! NSParagraphStyle

    let pagingParagraphStyle = self.pagingParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    pagingParagraphStyle.minimumLineHeight = ceil(pagingFont.ascender - pagingFont.descender)
    pagingParagraphStyle.maximumLineHeight = ceil(pagingFont.ascender - pagingFont.descender)
    pagingParagraphStyle.tabStops = []
    self.pagingParagraphStyle = pagingParagraphStyle.copy() as! NSParagraphStyle

    let statusParagraphStyle = self.statusParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
    statusParagraphStyle.minimumLineHeight = commentFontHeight
    statusParagraphStyle.maximumLineHeight = commentFontHeight
    self.statusParagraphStyle = statusParagraphStyle.copy() as! NSParagraphStyle

    textAttrs[.font] = font
    labelAttrs[.font] = labelFont
    commentAttrs[.font] = commentFont
    preeditAttrs[.font] = font
    pagingAttrs[.font] = pagingFont
    statusAttrs[.font] = commentFont
    labelAttrs[.strokeWidth] = NSNumber(value: -2.0 / labelFontSize!)

    var zhFont: NSFont = CTFontCreateUIFontForLanguage(.system, fontSize!, scriptVariant as CFString)!
    var zhCommentFont = NSFont(descriptor: zhFont.fontDescriptor, size: commentFontSize!)!
    let maxFontSize: Double = max(fontSize!, commentFontSize!, labelFontSize!)
    var refFont = NSFont(descriptor: zhFont.fontDescriptor, size: maxFontSize)!
    if isVertical {
      zhFont = zhFont.vertical
      zhCommentFont = zhCommentFont.vertical
      refFont = refFont.vertical
    }
    let baselineRefInfo: NSDictionary =
      [kCTBaselineReferenceFont: refFont,
       kCTBaselineClassIdeographicCentered: NSNumber(value: isVertical ? 0.0 : (refFont.ascender + refFont.descender) * 0.5),
       kCTBaselineClassRoman: NSNumber(value: isVertical ? -(refFont.ascender + refFont.descender) * 0.5 : 0.0),
       kCTBaselineClassIdeographicLow: NSNumber(value: isVertical ? (refFont.descender - refFont.ascender) * 0.5 : refFont.descender)]

    textAttrs[.baselineReferenceInfo] = baselineRefInfo
    labelAttrs[.baselineReferenceInfo] = baselineRefInfo
    commentAttrs[.baselineReferenceInfo] = baselineRefInfo
    preeditAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont: zhFont] as NSDictionary
    pagingAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont: pagingFont] as NSDictionary
    statusAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont: zhCommentFont] as NSDictionary

    textAttrs[.baselineClass] = isVertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    labelAttrs[.baselineClass] = kCTBaselineClassIdeographicCentered
    commentAttrs[.baselineClass] = isVertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    preeditAttrs[.baselineClass] = isVertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    statusAttrs[.baselineClass] = isVertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    pagingAttrs[.baselineClass] = kCTBaselineClassIdeographicCentered

    textAttrs[.language] = scriptVariant as NSString
    labelAttrs[.language] = scriptVariant as NSString
    commentAttrs[.language] = scriptVariant as NSString
    preeditAttrs[.language] = scriptVariant as NSString
    statusAttrs[.language] = scriptVariant as NSString

    baseOffset ?= 0
    textAttrs[.baselineOffset] = NSNumber(value: baseOffset!)
    labelAttrs[.baselineOffset] = NSNumber(value: baseOffset!)
    commentAttrs[.baselineOffset] = NSNumber(value: baseOffset!)
    preeditAttrs[.baselineOffset] = NSNumber(value: baseOffset!)
    pagingAttrs[.baselineOffset] = NSNumber(value: baseOffset!)
    statusAttrs[.baselineOffset] = NSNumber(value: baseOffset!)

    preeditAttrs[.paragraphStyle] = preeditParagraphStyle
    pagingAttrs[.paragraphStyle] = pagingParagraphStyle
    statusAttrs[.paragraphStyle] = statusParagraphStyle

    labelAttrs[.verticalGlyphForm] = NSNumber(value: isVertical)
    pagingAttrs[.verticalGlyphForm] = NSNumber(value: false)

    // CHROMATICS refinement
    translucency ?= 0.0
    if #available(macOS 10.14, *) {
      if translucency! > 0.001 && !isNative && backColor != nil && (style == .dark ? backColor!.lStarComponent! > 0.6 : backColor!.lStarComponent! < 0.4) {
        backColor = backColor?.invertLuminance(toExtent: .standard)
        borderColor = borderColor?.invertLuminance(toExtent: .standard)
        preeditBackColor = preeditBackColor?.invertLuminance(toExtent: .standard)
        preeditForeColor = preeditForeColor?.invertLuminance(toExtent: .standard)
        candidateBackColor = candidateBackColor?.invertLuminance(toExtent: .standard)
        textForeColor = textForeColor?.invertLuminance(toExtent: .standard)
        commentForeColor = commentForeColor?.invertLuminance(toExtent: .standard)
        labelForeColor = labelForeColor?.invertLuminance(toExtent: .standard)
        hilitedPreeditBackColor = hilitedPreeditBackColor?.invertLuminance(toExtent: .moderate)
        hilitedPreeditForeColor = hilitedPreeditForeColor?.invertLuminance(toExtent: .augmented)
        hilitedCandidateBackColor = hilitedCandidateBackColor?.invertLuminance(toExtent: .moderate)
        hilitedTextForeColor = hilitedTextForeColor?.invertLuminance(toExtent: .augmented)
        hilitedCommentForeColor = hilitedCommentForeColor?.invertLuminance(toExtent: .augmented)
        hilitedLabelForeColor = hilitedLabelForeColor?.invertLuminance(toExtent: .augmented)
      }
    }

    self.backImage = backImage
    self.backColor = backColor ?? .controlBackgroundColor
    self.borderColor = borderColor ?? (isNative ? .gridColor : nil)
    self.preeditBackColor = preeditBackColor ?? (isNative ? .windowBackgroundColor : nil)
    self.preeditForeColor = preeditForeColor ?? .textColor
    self.candidateBackColor = candidateBackColor
    self.textForeColor = textForeColor ?? .controlTextColor
    self.commentForeColor = commentForeColor ?? .secondaryLabelColor
    self.labelForeColor = labelForeColor ?? (isNative ? .secondaryLabelColor : self.textForeColor.blend(background: self.backColor))
    self.hilitedPreeditBackColor = hilitedPreeditBackColor ?? (isNative ? .selectedTextBackgroundColor : nil)
    self.hilitedPreeditForeColor = hilitedPreeditForeColor ?? .selectedTextColor
    self.hilitedCandidateBackColor = hilitedCandidateBackColor ?? (isNative ? .selectedContentBackgroundColor : nil)
    self.hilitedTextForeColor = hilitedTextForeColor ?? .selectedMenuItemTextColor
    self.hilitedCommentForeColor = hilitedCommentForeColor ?? .alternateSelectedControlTextColor
    self.hilitedLabelForeColor = hilitedLabelForeColor ?? (isNative ? .alternateSelectedControlTextColor : self.hilitedTextForeColor.blend(background: self.hilitedCandidateBackColor))
    dimmedLabelForeColor = isTabular ? self.labelForeColor.withAlphaComponent(self.labelForeColor.alphaComponent * 0.2) : nil

    textAttrs[.foregroundColor] = self.textForeColor
    commentAttrs[.foregroundColor] = self.commentForeColor
    labelAttrs[.foregroundColor] = self.labelForeColor
    preeditAttrs[.foregroundColor] = self.preeditForeColor
    pagingAttrs[.foregroundColor] = self.preeditForeColor
    statusAttrs[.foregroundColor] = self.commentForeColor

    borderInsets = isVertical ? .init(width: borderHeight ?? 0, height: borderWidth ?? 0) : .init(width: borderWidth ?? 0, height: borderHeight ?? 0)
    self.cornerRadius = min(cornerRadius ?? 0, lineHeight * 0.5)
    self.hilitedCornerRadius = min(hilitedCornerRadius ?? 0, lineHeight * 0.5)
    self.fullWidth = fullWidth
    self.lineSpacing = lineSpacing!
    self.preeditSpacing = preeditSpacing!
    self.opacity = opacity ?? 1.0
    self.lineLength = lineLength != nil && lineLength! > 0.1 ? max(ceil(lineLength!), fullWidth * 5) : 0
    self.shadowSize = shadowSize ?? 0.0
    self.translucency = Float(translucency ?? 0.0)
    self.stackColors = stackColors ?? false
    self.showPaging = showPaging ?? false
    self.rememberSize = rememberSize ?? false
    self.isTabular = isTabular
    self.isLinear = isLinear
    self.isVertical = isVertical
    self.inlinePreedit = inlinePreedit ?? false
    self.inlineCandidate = inlineCandidate ?? false

    self.scriptVariant = scriptVariant
    updateCandidateFormat(candidateFormat ?? kDefaultCandidateFormat)
    updateStatusMessageType(statusMessageType)
  }

  func updateAnnotationHeight(_ height: Double) {
    if height > 0.1 && lineSpacing < height * 2 {
      lineSpacing = height * 2
      let candidateParagraphStyle = self.candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
      if isLinear {
        candidateParagraphStyle.lineSpacing = height * 2
        let truncatedParagraphStyle = candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
        truncatedParagraphStyle.lineBreakMode = .byTruncatingMiddle
        truncatedParagraphStyle.tighteningFactorForTruncation = 0.0
        self.truncatedParagraphStyle = truncatedParagraphStyle.copy() as? NSParagraphStyle
      } else {
        candidateParagraphStyle.paragraphSpacingBefore = height
        candidateParagraphStyle.paragraphSpacing = height
      }
      self.candidateParagraphStyle = candidateParagraphStyle.copy() as! NSParagraphStyle

      textAttrs[.paragraphStyle] = candidateParagraphStyle
      commentAttrs[.paragraphStyle] = candidateParagraphStyle
      labelAttrs[.paragraphStyle] = candidateParagraphStyle

      let candidateTemplate = self.candidateTemplate.mutableCopy() as! NSMutableAttributedString
      candidateTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSRange(location: 0, length: candidateTemplate.length))
      self.candidateTemplate = candidateTemplate.copy() as! NSAttributedString
      let candidateHilitedTemplate = self.candidateHilitedTemplate.mutableCopy() as! NSMutableAttributedString
      candidateHilitedTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSRange(location: 0, length: candidateHilitedTemplate.length))
      self.candidateHilitedTemplate = candidateHilitedTemplate.copy() as! NSAttributedString
      if isTabular {
        let candidateDimmedTemplate = self.candidateDimmedTemplate!.mutableCopy() as! NSMutableAttributedString
        candidateDimmedTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSRange(location: 0, length: candidateDimmedTemplate.length))
        self.candidateDimmedTemplate = candidateDimmedTemplate.copy() as? NSAttributedString
      }
    }
  }

  func updateScriptVariant(_ scriptVariant: String) {
    if scriptVariant == self.scriptVariant { return }
    self.scriptVariant = scriptVariant

    let textFontSize: Double = (textAttrs[.font] as! NSFont).pointSize
    let commentFontSize: Double = (commentAttrs[.font] as! NSFont).pointSize
    let labelFontSize: Double = (labelAttrs[.font] as! NSFont).pointSize
    var zhFont: NSFont = CTFontCreateUIFontForLanguage(.system, textFontSize, scriptVariant as CFString)!
    var zhCommentFont = NSFont(descriptor: zhFont.fontDescriptor, size: commentFontSize)!
    let maxFontSize: Double = max(textFontSize, commentFontSize, labelFontSize)
    var refFont = NSFont(descriptor: zhFont.fontDescriptor, size: maxFontSize)!
    if isVertical {
      zhFont = zhFont.vertical
      zhCommentFont = zhCommentFont.vertical
      refFont = refFont.vertical
    }
    let baselineRefInfo: NSDictionary =
      [kCTBaselineReferenceFont: refFont,
       kCTBaselineClassIdeographicCentered: NSNumber(value: isVertical ? 0.0 : (refFont.ascender + refFont.descender) * 0.5),
       kCTBaselineClassRoman: NSNumber(value: isVertical ? -(refFont.ascender + refFont.descender) * 0.5 : 0.0),
       kCTBaselineClassIdeographicLow: NSNumber(value: isVertical ? (refFont.descender - refFont.ascender) * 0.5 : refFont.descender)]

    textAttrs[.baselineReferenceInfo] = baselineRefInfo
    labelAttrs[.baselineReferenceInfo] = baselineRefInfo
    commentAttrs[.baselineReferenceInfo] = baselineRefInfo
    preeditAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont: zhFont] as NSDictionary
    statusAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont: zhCommentFont] as NSDictionary

    textAttrs[.language] = scriptVariant as NSString
    labelAttrs[.language] = scriptVariant as NSString
    commentAttrs[.language] = scriptVariant as NSString
    preeditAttrs[.language] = scriptVariant as NSString
    statusAttrs[.language] = scriptVariant as NSString

    let candidateTemplate = self.candidateTemplate.mutableCopy() as! NSMutableAttributedString
    let textRange: NSRange = candidateTemplate.mutableString.range(of: "%@", options: [.literal])
    let labelRange = NSRange(location: 0, length: textRange.location)
    let commentRange = NSRange(location: textRange.upperBound, length: candidateTemplate.length - textRange.upperBound)
    candidateTemplate.addAttributes(labelAttrs, range: labelRange)
    candidateTemplate.addAttributes(textAttrs, range: textRange)
    candidateTemplate.addAttributes(commentAttrs, range: commentRange)
    self.candidateTemplate = candidateTemplate.copy() as! NSAttributedString

    let candidateHilitedTemplate = candidateTemplate.mutableCopy() as! NSMutableAttributedString
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedLabelForeColor, range: labelRange)
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedTextForeColor, range: textRange)
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedCommentForeColor, range: commentRange)
    self.candidateHilitedTemplate = candidateHilitedTemplate.copy() as! NSAttributedString

    if isTabular {
      let candidateDimmedTemplate = candidateTemplate.mutableCopy() as! NSMutableAttributedString
      candidateDimmedTemplate.addAttribute(.foregroundColor, value: dimmedLabelForeColor!, range: labelRange)
      self.candidateDimmedTemplate = candidateDimmedTemplate.copy() as? NSAttributedString
    }
  }
} // SquirrelTheme

// MARK: Typesetting extensions for TextKit 1 (Mac OSX 10.9 to MacOS 11)

@frozen enum SquirrelContentBlock: Int, Sendable {
  case preedit, linearCandidates, stackedCandidates, paging, status
}

final class SquirrelLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
  var contentBlock: SquirrelContentBlock? { (firstTextView as? SquirrelTextView)?.contentBlock }

  override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    let textContainer = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil, withoutAdditionalLayout: true)!
    let verticalOrientation: Bool = textContainer.layoutOrientation == .vertical
    let context = NSGraphicsContext.current!.cgContext
    context.resetClip()
    enumerateLineFragments(forGlyphRange: glyphsToShow) { lineRect, lineUsedRect, container, lineRange, flag in
      let charRange: NSRange = self.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)
      self.textStorage!.enumerateAttributes(in: charRange, options: [.longestEffectiveRangeNotRequired]) { attrs, runRange, stop in
        let runGlyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
        if let _ = attrs[.rubyAnnotation] {
          context.saveGState()
          context.scaleBy(x: 1.0, y: -1.0)
          var glyphIndex: Int = runGlyphRange.location
          let line: CTLine = CTLineCreateWithAttributedString(self.textStorage!.attributedSubstring(from: runRange))
          let runs: CFArray = CTLineGetGlyphRuns(line)
          for i in 0 ..< CFArrayGetCount(runs) {
            let position: NSPoint = self.location(forGlyphAt: glyphIndex)
            let run: CTRun = Unmanaged.fromOpaque(CFArrayGetValueAtIndex(runs, i)).takeUnretainedValue()
            let glyphCount: Int = CTRunGetGlyphCount(run)
            var matrix: CGAffineTransform = CTRunGetTextMatrix(run)
            var glyphOrigin = NSPoint(x: origin.x + lineRect.origin.x + position.x, y: -origin.y - lineRect.origin.y - position.y)
            glyphOrigin = textContainer.textView!.convertToBacking(glyphOrigin)
            glyphOrigin.x = round(glyphOrigin.x)
            glyphOrigin.y = round(glyphOrigin.y)
            glyphOrigin = textContainer.textView!.convertFromBacking(glyphOrigin)
            matrix.tx = glyphOrigin.x
            matrix.ty = glyphOrigin.y
            context.textMatrix = matrix
            CTRunDraw(run, context, CFRange(location: 0, length: glyphCount))
            glyphIndex += glyphCount
          }
          context.restoreGState()
        } else {
          var position: NSPoint = self.location(forGlyphAt: runGlyphRange.location)
          position.x += origin.x
          position.y += origin.y
          let runFont = attrs[.font] as! NSFont
          let baselineClass = attrs[.baselineClass] as! CFString?
          var offset: NSPoint = .zero
          if !verticalOrientation && (baselineClass == kCTBaselineClassIdeographicCentered || baselineClass == kCTBaselineClassMath) {
            let refFont = (attrs[.baselineReferenceInfo] as! NSDictionary)[kCTBaselineReferenceFont] as! NSFont
            offset.y += (runFont.ascender + runFont.descender - refFont.ascender - refFont.descender) * 0.5
          } else if verticalOrientation && runFont.pointSize < 24 && (runFont.fontName == "AppleColorEmoji") {
            let superscript = (attrs[.superscript, default: NSNumber(value: 0)] as! NSNumber).intValue
            offset.x += runFont.capHeight - runFont.pointSize
            offset.y += (runFont.capHeight - runFont.pointSize) * (superscript == 0 ? 0.25 : (superscript == 1 ? 0.5 / 0.55 : 0.0))
          }
          var glyphOrigin: NSPoint = textContainer.textView!.convertToBacking(NSPoint(x: position.x + offset.x, y: position.y + offset.y))
          glyphOrigin = textContainer.textView!.convertFromBacking(NSPoint(x: round(glyphOrigin.x), y: round(glyphOrigin.y)))
          super.drawGlyphs(forGlyphRange: runGlyphRange, at: NSPoint(x: glyphOrigin.x - position.x, y: glyphOrigin.y - position.y))
        }
      }
    }
    context.clip(to: textContainer.textView!.superview!.bounds)
  }

  func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
    var didModify: Bool = false
    let verticalOrientation: Bool = textContainer.layoutOrientation == .vertical
    let charRange: NSRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    let rulerAttrs = textContainer.textView!.defaultParagraphStyle!
    let lineSpacing: Double = rulerAttrs.lineSpacing
    let lineHeight: Double = rulerAttrs.minimumLineHeight
    var baseline: Double = lineHeight * 0.5
    if !verticalOrientation {
      let refFont = (layoutManager.textStorage!.attribute(.baselineReferenceInfo, at: charRange.location, effectiveRange: nil) as! NSDictionary)[kCTBaselineReferenceFont] as! NSFont
      baseline += (refFont.ascender + refFont.descender) * 0.5
    }
    let lineHeightDelta: Double = lineFragmentUsedRect.pointee.size.height - lineHeight - lineSpacing
    if abs(lineHeightDelta) > 0.1 {
      lineFragmentUsedRect.pointee.size.height = round(lineFragmentUsedRect.pointee.size.height - lineHeightDelta)
      lineFragmentRect.pointee.size.height = round(lineFragmentRect.pointee.size.height - lineHeightDelta)
      didModify = true
    }
    let newBaselineOffset: Double = floor(lineFragmentUsedRect.pointee.origin.y - lineFragmentRect.pointee.origin.y + baseline)
    if abs(baselineOffset.pointee - newBaselineOffset) > 0.1 {
      baselineOffset.pointee = newBaselineOffset
      didModify = true
    }
    return didModify
  }

  func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
    if charIndex <= 1 {
      return true
    } else {
      let charBeforeIndex: unichar = layoutManager.textStorage!.mutableString.character(at: charIndex - 1)
      return contentBlock == .linearCandidates ? charBeforeIndex == 0x1D : charBeforeIndex != UInt8(ascii: "\t")
    }
  }

  func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
    if charIndex > 0 && layoutManager.textStorage!.mutableString.character(at: charIndex) == 0x8B &&
      layoutManager.textStorage!.attribute(.rubyAnnotation, at: charIndex - 1, effectiveRange: nil) != nil {
      return .whitespace
    } else {
      return action
    }
  }

  func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
    var width: Double = 0.0
    if charIndex > 0 && layoutManager.textStorage!.mutableString.character(at: charIndex) == 0x8B {
      var rubyRange = NSRange(location: NSNotFound, length: 0)
      if layoutManager.textStorage!.attribute(.rubyAnnotation, at: charIndex - 1, effectiveRange: &rubyRange) != nil {
        let rubyString = layoutManager.textStorage!.attributedSubstring(from: rubyRange)
        let line: CTLine = CTLineCreateWithAttributedString(rubyString)
        let rubyRect: NSRect = CTLineGetBoundsWithOptions(line, [])
        width = fdim(rubyRect.size.width, rubyString.size().width)
      }
    }
    return .init(x: glyphPosition.x, y: glyphPosition.y, width: width, height: proposedRect.maxY - glyphPosition.y)
  }
} // SquirrelLayoutManager

// MARK: Typesetting extensions for TextKit 2 (MacOS 12 or higher)

@available(macOS 12.0, *)
final class SquirrelTextLayoutFragment: NSTextLayoutFragment {
  override func draw(at point: NSPoint, in context: CGContext) {
    var origin: NSPoint = point
    if #available(macOS 14.0, *) {
    } else { // in macOS 12 and 13, textLineFragments.typographicBouonds are in textContainer coordinates
      origin.x -= layoutFragmentFrame.minX
      origin.y -= layoutFragmentFrame.minY
    }
    let verticalOrientation: Bool = textLayoutManager!.textContainer!.layoutOrientation == .vertical
    for lineFrag in textLineFragments {
      let lineRect: NSRect = lineFrag.typographicBounds.offsetBy(dx: origin.x, dy: origin.y)
      var baseline: Double = lineRect.midY
      if !verticalOrientation {
        let refFont = (lineFrag.attributedString.attribute(.baselineReferenceInfo, at: lineFrag.characterRange.location, effectiveRange: nil) as! NSDictionary)[kCTBaselineReferenceFont] as! NSFont
        baseline += (refFont.ascender + refFont.descender) * 0.5
      }
      var renderOrigin = NSPoint(x: lineRect.minX + lineFrag.glyphOrigin.x, y: floor(baseline) - lineFrag.glyphOrigin.y)
      let deviceOrigin: NSPoint = context.convertToDeviceSpace(renderOrigin)
      renderOrigin = context.convertToUserSpace(NSPoint(x: round(deviceOrigin.x), y: round(deviceOrigin.y)))
      lineFrag.draw(at: renderOrigin, in: context)
    }
  }
} // SquirrelTextLayoutFragment

@available(macOS 12.0, *)
final class SquirrelTextLayoutManager: NSTextLayoutManager, NSTextLayoutManagerDelegate {
  var contentBlock: SquirrelContentBlock? { (textContainer?.textView as? SquirrelTextView)?.contentBlock }

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, shouldBreakLineBefore location: any NSTextLocation, hyphenating: Bool) -> Bool {
    let contentStorage = textLayoutManager.textContentManager as! NSTextContentStorage
    let charIndex: Int = contentStorage.offset(from: contentStorage.documentRange.location, to: location)
    if charIndex <= 1 {
      return true
    } else {
      let charBeforeIndex: unichar = contentStorage.textStorage!.mutableString.character(at: charIndex - 1)
      return contentBlock == .linearCandidates ? charBeforeIndex == 0x1D : charBeforeIndex != UInt8(ascii: "\t")
    }
  }

  func textLayoutManager(_: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
    let textRange = NSTextRange(location: location, end: textElement.elementRange!.endLocation)
    return SquirrelTextLayoutFragment(textElement: textElement, range: textRange)
  }
} // SquirrelTextLayoutManager

final class NSFlippedView: NSView {
  override var isFlipped: Bool { true }
}

final class SquirrelTextView: NSTextView {
  var contentBlock: SquirrelContentBlock

  init(contentBlock: SquirrelContentBlock, textStorage: NSTextStorage) {
    self.contentBlock = contentBlock
    let textContainer = NSTextContainer(size: .zero)
    textContainer.lineFragmentPadding = 0
    if #available(macOS 12.0, *) {
      let textLayoutManager = SquirrelTextLayoutManager()
      textLayoutManager.usesFontLeading = false
      textLayoutManager.usesHyphenation = false
      textLayoutManager.delegate = textLayoutManager
      textLayoutManager.textContainer = textContainer
      let contentStorage = NSTextContentStorage()
      contentStorage.addTextLayoutManager(textLayoutManager)
      contentStorage.textStorage = textStorage
    } else {
      let layoutManager = SquirrelLayoutManager()
      layoutManager.backgroundLayoutEnabled = true
      layoutManager.usesFontLeading = false
      layoutManager.typesetterBehavior = .latestBehavior
      layoutManager.delegate = layoutManager
      layoutManager.addTextContainer(textContainer)
      textStorage.addLayoutManager(layoutManager)
    }
    super.init(frame: .zero, textContainer: textContainer)
    drawsBackground = false
    isSelectable = false
    wantsLayer = false
    clipsToBounds = false
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @available(macOS 12.0, *)
  private func textRange(fromCharRange charRange: NSRange) -> NSTextRange? {
    if charRange.location == NSNotFound {
      return nil
    } else {
      let start = textContentStorage!.location(textContentStorage!.documentRange.location, offsetBy: charRange.location)!
      let end = textContentStorage!.location(start, offsetBy: charRange.length)!
      return NSTextRange(location: start, end: end)
    }
  }

  @available(macOS 12.0, *)
  private func charRange(fromTextRange textRange: NSTextRange?) -> NSRange {
    if textRange == nil {
      return NSRange(location: NSNotFound, length: 0)
    } else {
      let location = textContentStorage!.offset(from: textContentStorage!.documentRange.location, to: textRange!.location)
      let length = textContentStorage!.offset(from: textRange!.location, to: textRange!.endLocation)
      return NSRange(location: location, length: length)
    }
  }

  func layoutText() -> NSRect {
    var rect: NSRect = .zero
    if #available(macOS 12.0, *) {
      textLayoutManager!.ensureLayout(for: textLayoutManager!.documentRange)
      rect = textLayoutManager!.usageBoundsForTextContainer
    } else {
      layoutManager!.ensureLayout(for: textContainer!)
      rect = layoutManager!.usedRect(for: textContainer!)
    }
    return rect.integral(options: [.alignMinXNearest, .alignMinYNearest, .alignWidthOutward, .alignHeightOutward])
  }

  // Get the rectangle containing the range of text
  func blockRect(for charRange: NSRange) -> NSRect {
    if charRange.location == NSNotFound {
      return .zero
    }
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange! = textRange(fromCharRange: charRange)
      var firstLineRect: NSRect = .null
      var finalLineRect: NSRect = .null
      textLayoutManager?.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { segRange, segFrame, baseline, textContainer in
        if !segFrame.isEmpty {
          if firstLineRect.isEmpty || segFrame.minY < firstLineRect.maxY - 0.1 {
            firstLineRect = segFrame.union(firstLineRect)
          } else {
            finalLineRect = segFrame.union(finalLineRect)
          }
        }
        return true
      }
      if contentBlock == .linearCandidates, let lineSpacing = defaultParagraphStyle?.lineSpacing, lineSpacing > 0.1 {
        firstLineRect.size.height += lineSpacing
        if !finalLineRect.isEmpty {
          finalLineRect.size.height += lineSpacing
        }
      }

      if finalLineRect.isEmpty {
        return firstLineRect
      } else {
        let containerWidth: CGFloat = textLayoutManager?.usageBoundsForTextContainer.width ?? 0
        return .init(x: 0.0, y: firstLineRect.minY, width: containerWidth, height: finalLineRect.maxY - firstLineRect.minY)
      }
    } else {
      let glyphRange: NSRange = layoutManager!.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      var firstLineRange = NSRange(location: NSNotFound, length: 0)
      let firstLineRect: NSRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &firstLineRange)
      if glyphRange.upperBound <= firstLineRange.upperBound {
        let leading: Double = layoutManager!.location(forGlyphAt: glyphRange.location).x
        let trailing: Double = glyphRange.upperBound < firstLineRange.upperBound ? layoutManager!.location(forGlyphAt: glyphRange.upperBound).x : firstLineRect.width
        return .init(x: firstLineRect.minX + leading, y: firstLineRect.minY, width: trailing - leading, height: firstLineRect.height)
      } else {
        let finalLineRect: NSRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphRange.upperBound - 1, effectiveRange: nil)
        let containerWidth: Double = layoutManager!.usedRect(for: textContainer!).width
        return .init(x: 0.0, y: firstLineRect.minY, width: containerWidth, height: finalLineRect.maxY - firstLineRect.minY)
      }
    }
  }

  /* Calculate 3 rectangles encloding the text in range. TextPolygon.head & .tail are incomplete line fragments
   TextPolygon.body is the complete line fragment in the middle if the range spans no less than one full line */
  func textPolygon(forRange charRange: NSRange) -> SquirrelTextPolygon {
    var textPolygon: SquirrelTextPolygon = .init(head: .zero, body: .zero, tail: .zero)
    if charRange.location == NSNotFound {
      return textPolygon
    }
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange! = textRange(fromCharRange: charRange)
      var headLineRect: NSRect = .null
      var tailLineRect: NSRect = .null
      var headLineRange: NSTextRange?
      var tailLineRange: NSTextRange?
      textLayoutManager?.enumerateTextSegments(in: textRange, type: .standard, options: [.middleFragmentsExcluded]) { segRange, segFrame, baseline, textContainer in
        if !segFrame.isEmpty {
          if headLineRect.isEmpty || segFrame.minY < headLineRect.maxY - 0.1 {
            headLineRect = segFrame.union(headLineRect)
            headLineRange = headLineRange == nil ? segRange! : segRange!.union(headLineRange!)
          } else {
            tailLineRect = segFrame.union(tailLineRect)
            tailLineRange = tailLineRange == nil ? segRange! : segRange!.union(tailLineRange!)
          }
        }
        return true
      }
      if contentBlock == .linearCandidates, let lineSpacing = defaultParagraphStyle?.lineSpacing, lineSpacing > 0.1 {
        headLineRect.size.height += lineSpacing
        if !tailLineRect.isEmpty {
          tailLineRect.size.height += lineSpacing
        }
      }

      if tailLineRect.isEmpty {
        textPolygon.body = headLineRect
      } else {
        let containerWidth: CGFloat = textLayoutManager?.usageBoundsForTextContainer.width ?? 0
        headLineRect.size.width = containerWidth - headLineRect.minX
        if abs(tailLineRect.maxX - headLineRect.maxX) < 1 {
          if abs(headLineRect.minX - tailLineRect.minX) < 1 {
            textPolygon.body = headLineRect.union(tailLineRect)
          } else {
            textPolygon.head = headLineRect
            textPolygon.body = NSRect(x: 0.0, y: headLineRect.maxY, width: containerWidth, height: tailLineRect.maxY - headLineRect.maxY)
          }
        } else {
          textPolygon.tail = tailLineRect
          if abs(headLineRect.minX - tailLineRect.minX) < 1 {
            textPolygon.body = NSRect(x: 0.0, y: headLineRect.minY, width: containerWidth, height: tailLineRect.minY - headLineRect.minY)
          } else {
            textPolygon.head = headLineRect
            if !tailLineRange!.contains(headLineRange!.endLocation) {
              textPolygon.body = NSRect(x: 0.0, y: headLineRect.maxY, width: containerWidth, height: tailLineRect.minY - headLineRect.maxY)
            }
          }
        }
      }
    } else {
      let glyphRange: NSRange = layoutManager!.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      var headLineRange = NSRange(location: NSNotFound, length: 0)
      let headLineRect: NSRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &headLineRange)
      let leading: Double = layoutManager!.location(forGlyphAt: glyphRange.location).x
      if headLineRange.upperBound >= glyphRange.upperBound {
        let trailing: Double = glyphRange.upperBound < headLineRange.upperBound ? layoutManager!.location(forGlyphAt: glyphRange.upperBound).x : headLineRect.width
        textPolygon.body = NSRect(x: leading, y: headLineRect.minY, width: trailing - leading, height: headLineRect.height)
      } else {
        let containerWidth: Double = layoutManager!.usedRect(for: textContainer!).width
        var tailLineRange = NSRange(location: NSNotFound, length: 0)
        let tailLineRect: NSRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphRange.upperBound - 1, effectiveRange: &tailLineRange)
        let trailing: Double = glyphRange.upperBound < tailLineRange.upperBound ? layoutManager!.location(forGlyphAt: glyphRange.upperBound).x : tailLineRect.width
        if tailLineRange.upperBound == glyphRange.upperBound {
          if glyphRange.location == headLineRange.location {
            textPolygon.body = NSRect(x: 0.0, y: headLineRect.minY, width: containerWidth, height: tailLineRect.maxY - headLineRect.minY)
          } else {
            textPolygon.head = NSRect(x: leading, y: headLineRect.minY, width: containerWidth - leading, height: headLineRect.height)
            textPolygon.body = NSRect(x: 0.0, y: headLineRect.maxY, width: containerWidth, height: tailLineRect.maxY - headLineRect.maxY)
          }
        } else {
          textPolygon.tail = NSRect(x: 0.0, y: tailLineRect.minY, width: trailing, height: tailLineRect.height)
          if glyphRange.location == headLineRange.location {
            textPolygon.body = NSRect(x: 0.0, y: headLineRect.minY, width: containerWidth, height: tailLineRect.minY - headLineRect.minY)
          } else {
            textPolygon.head = NSRect(x: leading, y: headLineRect.minY, width: containerWidth - leading, height: headLineRect.height)
            if tailLineRange.location > headLineRange.upperBound {
              textPolygon.body = NSRect(x: 0.0, y: headLineRect.maxY, width: containerWidth, height: tailLineRect.minY - headLineRect.maxY)
            }
          }
        }
      }
    }
    return textPolygon
  }
} // SquirrelTextView

// MARK: View behind text, containing drawings of backgrounds and highlights

final class SquirrelView: NSView {
  static var lightTheme: SquirrelTheme = SquirrelTheme(style: .light)
  @available(macOS 10.14, *) static var darkTheme: SquirrelTheme = SquirrelTheme(style: .dark)
  private(set) var theme: SquirrelTheme
  let candidateView: SquirrelTextView
  let preeditView: SquirrelTextView
  let pagingView: SquirrelTextView
  let statusView: SquirrelTextView
  let scrollView: NSScrollView
  let documentView: NSFlippedView
  let candidateContents = NSTextStorage()
  let preeditContents = NSTextStorage()
  let pagingContents = NSTextStorage()
  let statusContents = NSTextStorage()
  @available(macOS 10.14, *) let shape = CAShapeLayer()
  let logoLayer = CAShapeLayer()
  private let backImageLayer = CAShapeLayer()
  private let backColorLayer = CAShapeLayer()
  private let borderLayer = CAShapeLayer()
  private let hilitedPreeditLayer = CAShapeLayer()
  private let functionButtonLayer = CAShapeLayer()
  private let documentLayer = CAShapeLayer()
  private let activePageLayer = CAShapeLayer()
  private let gridLayer = CAShapeLayer()
  private let nonHilitedCandidateLayer = CAShapeLayer()
  private let hilitedCandidateLayer = CAShapeLayer()
  private let clipLayer = CAShapeLayer()
  private(set) var tabularIndices: [SquirrelTabularIndex] = []
  private(set) var candidatePolygons: [SquirrelTextPolygon] = []
  private(set) var sectionRects: [NSRect] = []
  private(set) var candidateInfos: [SquirrelCandidateInfo] = []
  private(set) var contentRect: NSRect = .zero
  private(set) var documentRect: NSRect = .zero
  private(set) var preeditRect: NSRect = .zero
  private(set) var clipRect: NSRect = .zero
  private(set) var pagingRect: NSRect = .zero
  private(set) var deleteBackRect: NSRect = .zero
  private(set) var expanderRect: NSRect = .zero
  private(set) var pageUpRect: NSRect = .zero
  private(set) var pageDownRect: NSRect = .zero
  private(set) var clippedHeight: Double = 0.0
  private(set) var functionButton: SquirrelIndex = .VoidSymbol
  private(set) var hilitedCandidate: Int?
  private(set) var hilitedPreeditRange = NSRange(location: NSNotFound, length: 0)
  var sectionNum: Int = 0
  var isExpanded: Bool = false
  var isLocked: Bool = false
  // Need flipped coordinate system, as required by textStorage
  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  var style: SquirrelStyle {
    didSet {
      if #available(macOS 10.14, *) {
        if oldValue != style {
          if style == .dark {
            theme = Self.darkTheme
            scrollView.scrollerKnobStyle = .light
          } else {
            theme = Self.lightTheme
            scrollView.scrollerKnobStyle = .dark
          }
          updateColors()
        }
      }
    }
  }

  override init(frame frameRect: NSRect) {
    candidateView = SquirrelTextView(contentBlock: .stackedCandidates, textStorage: candidateContents)
    preeditView = SquirrelTextView(contentBlock: .preedit, textStorage: preeditContents)
    pagingView = SquirrelTextView(contentBlock: .paging, textStorage: pagingContents)
    statusView = SquirrelTextView(contentBlock: .status, textStorage: statusContents)

    documentView = NSFlippedView()
    documentView.wantsLayer = true
    documentView.layer!.isGeometryFlipped = true
    documentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
    documentView.autoresizesSubviews = false
    documentView.addSubview(candidateView)
    scrollView = NSScrollView()
    scrollView.documentView = documentView
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.hasVerticalScroller = true
    scrollView.scrollerStyle = .overlay
    scrollView.scrollerKnobStyle = .dark
    scrollView.contentView.wantsLayer = true
    scrollView.contentView.layer!.isGeometryFlipped = true

    style = .light
    theme = Self.lightTheme
    if #available(macOS 10.14, *) {
      shape.fillColor = CGColor.white
    }
    super.init(frame: frameRect)
    wantsLayer = true
    layer!.isGeometryFlipped = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay

    backImageLayer.actions = ["transform": NSNull()]
    backColorLayer.fillRule = .evenOdd
    borderLayer.fillRule = .evenOdd
    layer!.addSublayer(backImageLayer)
    layer!.addSublayer(backColorLayer)
    layer!.addSublayer(hilitedPreeditLayer)
    layer!.addSublayer(functionButtonLayer)
    layer!.addSublayer(logoLayer)
    layer!.addSublayer(borderLayer)

    documentLayer.fillRule = .evenOdd
    documentLayer.allowsGroupOpacity = true
    activePageLayer.fillRule = .evenOdd
    gridLayer.lineWidth = 1.0
    clipLayer.fillColor = CGColor.white
    documentView.layer!.addSublayer(documentLayer)
    documentLayer.addSublayer(activePageLayer)
    documentView.layer!.addSublayer(gridLayer)
    documentView.layer!.addSublayer(nonHilitedCandidateLayer)
    documentView.layer!.addSublayer(hilitedCandidateLayer)
    scrollView.contentView.layer!.mask = clipLayer
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  convenience init() {
    self.init(frame: .zero)
  }

  func updateColors() {
    backColorLayer.fillColor = (theme.preeditBackColor ?? theme.backColor).cgColor
    borderLayer.fillColor = (theme.borderColor ?? theme.backColor).cgColor
    documentLayer.fillColor = theme.backColor.cgColor
    if let backImage = theme.backImage, backImage.isValid {
      backImageLayer.fillColor = NSColor(patternImage: theme.backImage!).cgColor
      backImageLayer.isHidden = false
    } else {
      backImageLayer.isHidden = true
    }
    if let hilitedPreeditBackColor = theme.hilitedPreeditBackColor {
      hilitedPreeditLayer.fillColor = hilitedPreeditBackColor.cgColor
    } else {
      hilitedPreeditLayer.isHidden = true
    }
    if let candidateBackColor = theme.candidateBackColor {
      nonHilitedCandidateLayer.fillColor = candidateBackColor.cgColor
    } else {
      nonHilitedCandidateLayer.isHidden = true
    }
    if let hilitedCandidateBackColor = theme.hilitedCandidateBackColor {
      hilitedCandidateLayer.fillColor = hilitedCandidateBackColor.cgColor
      if theme.shadowSize > 0.1 {
        hilitedCandidateLayer.shadowOffset = .init(width: theme.shadowSize, height: theme.shadowSize)
        hilitedCandidateLayer.shadowOpacity = 1.0
      } else {
        hilitedCandidateLayer.shadowOpacity = 0.0
      }
    } else {
      hilitedCandidateLayer.isHidden = true
    }
    if theme.isTabular {
      activePageLayer.fillColor = theme.backColor.hooverColor.cgColor
      gridLayer.strokeColor = theme.commentForeColor.blended(withFraction: 0.8, of: theme.backColor)?.cgColor
    } else {
      activePageLayer.isHidden = true
      gridLayer.isHidden = true
    }
    if #available(macOS 10.14, *) {
      backImageLayer.opacity = 1.0 - theme.translucency
      backColorLayer.opacity = 1.0 - theme.translucency
      borderLayer.opacity = 1.0 - theme.translucency
      documentLayer.opacity = 1.0 - theme.translucency
    }
  }

  func estimateBounds(onScreen screen: NSRect, withPreedit hasPreedit: Bool, candidates candidateInfos: [SquirrelCandidateInfo], paging hasPaging: Bool) {
    self.candidateInfos = candidateInfos
    preeditView.isHidden = !hasPreedit
    candidateView.isHidden = candidateInfos.isEmpty
    pagingView.isHidden = !hasPaging
    statusView.isHidden = hasPreedit || !candidateInfos.isEmpty
    // layout textviews and get their sizes
    preeditRect = .zero
    documentRect = .zero // in textView's own coordinates
    clipRect = .zero
    pagingRect = .zero
    clippedHeight = 0.0
    if !hasPreedit && candidateInfos.isEmpty { // status
      contentRect = statusView.layoutText(); return
    }
    if hasPreedit {
      preeditRect = preeditView.layoutText()
      contentRect = preeditRect
    }
    if !candidateInfos.isEmpty {
      documentRect = candidateView.layoutText()
      if #available(macOS 12.0, *) {
        documentRect.size.height += theme.lineSpacing
      } else {
        documentRect.size.height += theme.isLinear ? 0.0 : theme.lineSpacing
      }
      if theme.isLinear && candidateInfos.reduce(true, { $0 && !$1.isTruncated }) {
        documentRect.size.width -= theme.fullWidth
      }
      clipRect = documentRect
      if hasPreedit {
        clipRect.origin.y = preeditRect.maxY + theme.preeditSpacing
        contentRect = preeditRect.union(clipRect)
      } else {
        contentRect = clipRect
      }
      clipRect.size.width += theme.fullWidth
      if hasPaging {
        pagingRect = pagingView.layoutText()
        pagingRect.origin.y = clipRect.maxY
        contentRect = contentRect.union(pagingRect)
      }
    } else { return }
    // clip candidate block if it has too many lines
    let maxHeight: Double = (theme.isVertical ? screen.width : screen.height) * 0.5 - theme.borderInsets.height * 2
    clippedHeight = fdim(ceil(contentRect.height), ceil(maxHeight))
    contentRect.size.height -= clippedHeight
    clipRect.size.height -= clippedHeight
    scrollView.verticalScroller?.knobProportion = clipRect.height / documentRect.height
  }

  // Get the rectangles enclosing each part and the entire panel
  func layoutContents() {
    let origin = NSPoint(x: theme.borderInsets.width, y: theme.borderInsets.height)
    if !statusView.isHidden { // status
      contentRect.origin = NSPoint(x: origin.x + ceil(theme.fullWidth * 0.5), y: origin.y)
      return
    }
    if !preeditView.isHidden {
      preeditRect = preeditView.layoutText()
      preeditRect.size.width += theme.fullWidth
      preeditRect.origin = origin
      contentRect = preeditRect
    }
    if !scrollView.isHidden {
      clipRect.size.width = documentRect.width
      clipRect.size.height = documentRect.height - clippedHeight
      if !preeditView.isHidden {
        clipRect.origin.x = origin.x
        clipRect.origin.y = preeditRect.maxY + theme.preeditSpacing
        contentRect = preeditRect.union(clipRect)
      } else {
        clipRect.origin = origin
        contentRect = clipRect
      }
      if !pagingView.isHidden {
        pagingRect = pagingView.layoutText()
        pagingRect.size.width += theme.fullWidth
        pagingRect.origin.x = origin.x
        pagingRect.origin.y = clipRect.maxY
        contentRect = contentRect.union(pagingRect)
      }
      contentRect.size.width -= theme.fullWidth
      contentRect.origin.x += ceil(theme.fullWidth * 0.5)
    }
  }

  // Will triger `updateLayer()`
  func drawView(withHilitedCandidate hilitedCandidate: Int?, hilitedPreeditRange: NSRange) {
    self.hilitedCandidate = hilitedCandidate
    self.hilitedPreeditRange = hilitedPreeditRange
    functionButton = .VoidSymbol
    // invalidate Rect beyond bound of textview to clear any out-of-bound drawing from last round
    setNeedsDisplay(bounds)
    if !statusView.isHidden {
      statusView.setNeedsDisplay(statusView.bounds)
    } else {
      if !preeditView.isHidden {
        preeditView.setNeedsDisplay(preeditView.bounds)
      }
      // invalidate Rect beyond bound of textview to clear any out-of-bound drawing from last round
      if !scrollView.isHidden {
        candidateView.setNeedsDisplay(candidateView.convert(documentView.bounds, from: documentView))
      }
      if !pagingView.isHidden {
        pagingView.setNeedsDisplay(pagingView.bounds)
      }
    }
    layoutContents()
  }

  func setPreedit(hilitedPreeditRange: NSRange) {
    self.hilitedPreeditRange = hilitedPreeditRange
    setNeedsDisplay(preeditRect)
    preeditView.setNeedsDisplay(preeditView.bounds)
    layoutContents()
  }

  func highlightCandidate(_ hilitedCandidate: Int?) {
    if hilitedCandidate == nil || self.hilitedCandidate == nil { return }
    if isExpanded {
      let priorActivePage: Int = self.hilitedCandidate! / theme.pageSize
      let newActivePage: Int = hilitedCandidate! / theme.pageSize
      if newActivePage != priorActivePage {
        setNeedsDisplay(convert(sectionRects[priorActivePage], from: documentView))
        candidateView.setNeedsDisplay(documentView.convert(sectionRects[priorActivePage], to: candidateView))
        documentView.setNeedsDisplay(sectionRects[priorActivePage])
      }
      setNeedsDisplay(convert(sectionRects[newActivePage], from: documentView))
      candidateView.setNeedsDisplay(documentView.convert(sectionRects[newActivePage], to: candidateView))
      documentView.setNeedsDisplay(sectionRects[newActivePage])
    } else {
      setNeedsDisplay(clipRect)
      candidateView.setNeedsDisplay(documentView.convert(documentRect, to: candidateView))
      documentView.setNeedsDisplay(documentRect)
    }
    self.hilitedCandidate = hilitedCandidate
    unclipHighlightedCandidate()
  }

  func unclipHighlightedCandidate() {
    if hilitedCandidate == nil || clippedHeight < 0.1 { return }
    if isExpanded {
      let activePage: Int = hilitedCandidate! / theme.pageSize
      if sectionRects[activePage].minY < scrollView.documentVisibleRect.minY - 0.1 {
        var origin = scrollView.contentView.bounds.origin
        origin.y -= scrollView.documentVisibleRect.minY - sectionRects[activePage].minY
        scrollView.contentView.scroll(to: origin)
        scrollView.verticalScroller?.doubleValue = scrollView.documentVisibleRect.minY / clippedHeight
      } else if sectionRects[activePage].maxY > scrollView.documentVisibleRect.maxY + 0.1 {
        var origin = scrollView.contentView.bounds.origin
        origin.y += sectionRects[activePage].maxY - scrollView.documentVisibleRect.maxY
        scrollView.contentView.scroll(to: origin)
        scrollView.verticalScroller?.doubleValue = scrollView.documentVisibleRect.minY / clippedHeight
      }
    } else {
      if scrollView.documentVisibleRect.minY > candidatePolygons[hilitedCandidate!].minY + 0.1 {
        var origin = scrollView.contentView.bounds.origin
        origin.y -= scrollView.documentVisibleRect.minY - candidatePolygons[hilitedCandidate!].minY
        scrollView.contentView.scroll(to: origin)
        scrollView.verticalScroller?.doubleValue = scrollView.documentVisibleRect.minY / clippedHeight
      } else if scrollView.documentVisibleRect.maxY < candidatePolygons[hilitedCandidate!].maxY - 0.1 {
        var origin = scrollView.contentView.bounds.origin
        origin.y += candidatePolygons[hilitedCandidate!].maxY - scrollView.documentVisibleRect.maxY
        scrollView.contentView.scroll(to: origin)
        scrollView.verticalScroller?.doubleValue = scrollView.documentVisibleRect.minY / clippedHeight
      }
    }
  }

  func highlightFunctionButton(_ functionButton: SquirrelIndex) {
    for button in [self.functionButton, functionButton] {
      switch button {
      case .BackSpaceKey, .EscapeKey:
        setNeedsDisplay(deleteBackRect)
        preeditView.setNeedsDisplay(convert(deleteBackRect, to: preeditView), avoidAdditionalLayout: true)
      case .PageUpKey, .HomeKey:
        setNeedsDisplay(pageUpRect)
        pagingView.setNeedsDisplay(convert(pageUpRect, to: pagingView), avoidAdditionalLayout: true)
      case .PageDownKey, .EndKey:
        setNeedsDisplay(pageDownRect)
        pagingView.setNeedsDisplay(convert(pageDownRect, to: pagingView), avoidAdditionalLayout: true)
      case .ExpandButton, .CompressButton, .LockButton:
        setNeedsDisplay(expanderRect)
        pagingView.setNeedsDisplay(convert(expanderRect, to: pagingView), avoidAdditionalLayout: true)
      default:
        break
      }
    }
    self.functionButton = functionButton
  }

  private func updateFunctionButtonLayer() -> CGPath? {
    if functionButton == .VoidSymbol {
      functionButtonLayer.isHidden = true
      return nil
    }
    var buttonColor: NSColor?
    var buttonRect: NSRect = .zero
    switch functionButton {
    case .PageUpKey:
      buttonColor = theme.hilitedPreeditBackColor?.hooverColor
      buttonRect = pageUpRect
    case .HomeKey:
      buttonColor = theme.hilitedPreeditBackColor?.disabledColor
      buttonRect = pageUpRect
    case .PageDownKey:
      buttonColor = theme.hilitedPreeditBackColor?.hooverColor
      buttonRect = pageDownRect
    case .EndKey:
      buttonColor = theme.hilitedPreeditBackColor?.disabledColor
      buttonRect = pageDownRect
    case .ExpandButton, .CompressButton, .LockButton:
      buttonColor = theme.hilitedPreeditBackColor?.hooverColor
      buttonRect = expanderRect
    case .BackSpaceKey:
      buttonColor = theme.hilitedPreeditBackColor?.hooverColor
      buttonRect = deleteBackRect
    case .EscapeKey:
      buttonColor = theme.hilitedPreeditBackColor?.disabledColor
      buttonRect = deleteBackRect
    default:
      break
    }
    if !buttonRect.isEmpty && buttonColor != nil {
      let cornerRadius: Double = min(theme.hilitedCornerRadius, buttonRect.height * 0.5)
      let buttonPath: CGPath? = .squirclePath(rect: buttonRect, cornerRadius: cornerRadius)
      functionButtonLayer.path = buttonPath
      functionButtonLayer.fillColor = buttonColor!.cgColor
      functionButtonLayer.isHidden = false
      return buttonPath
    } else {
      functionButtonLayer.isHidden = true
      return nil
    }
  }

  // All draws happen here
  override func updateLayer() {
    let panelRect: NSRect = bounds
    let backgroundRect: NSRect = backingAlignedRect(panelRect.insetBy(dx: theme.borderInsets.width, dy: theme.borderInsets.height), options: [.alignAllEdgesNearest])
    let hilitedCornerRadius: Double = min(theme.hilitedCornerRadius, theme.candidateParagraphStyle.minimumLineHeight * 0.5)

    /*** Preedit Rects **/
    deleteBackRect = .zero
    var hilitedPreeditPath: CGPath?
    if !preeditView.isHidden {
      preeditRect.size.width = backgroundRect.width
      preeditRect = backingAlignedRect(preeditRect, options: [.alignAllEdgesNearest])
      // Draw the highlighted part of preedit text
      if hilitedPreeditRange.length > 0 && (theme.hilitedPreeditBackColor != nil) {
        let padding: Double = ceil(theme.preeditParagraphStyle.minimumLineHeight * 0.05)
        var innerBox: NSRect = preeditRect
        innerBox.origin.x += ceil(theme.fullWidth * 0.5) - padding
        innerBox.size.width = backgroundRect.width - theme.fullWidth + padding * 2
        innerBox = backingAlignedRect(innerBox, options: [.alignAllEdgesNearest])
        var textPolygon = preeditView.textPolygon(forRange: hilitedPreeditRange)
        if !textPolygon.head.isEmpty {
          textPolygon.head.origin.x += theme.borderInsets.width + ceil(theme.fullWidth * 0.5) - padding
          textPolygon.head.origin.y += theme.borderInsets.height
          textPolygon.head.size.width += padding * 2
          textPolygon.head = backingAlignedRect(textPolygon.head.intersection(innerBox), options: [.alignAllEdgesNearest])
        }
        if !textPolygon.body.isEmpty {
          textPolygon.body.origin.x += theme.borderInsets.width + ceil(theme.fullWidth * 0.5) - padding
          textPolygon.body.origin.y += theme.borderInsets.height
          textPolygon.body.size.width += padding
          if !textPolygon.tail.isEmpty || hilitedPreeditRange.upperBound + 2 == preeditContents.length {
            textPolygon.body.size.width += padding
          }
          textPolygon.body = backingAlignedRect(textPolygon.body.intersection(innerBox), options: [.alignAllEdgesNearest])
        }
        if !textPolygon.tail.isEmpty {
          textPolygon.tail.origin.x += theme.borderInsets.width + ceil(theme.fullWidth * 0.5) - padding
          textPolygon.tail.origin.y += theme.borderInsets.height
          textPolygon.tail.size.width += padding
          if hilitedPreeditRange.upperBound + 2 == preeditContents.length {
            textPolygon.tail.size.width += padding
          }
          textPolygon.tail = backingAlignedRect(textPolygon.tail.intersection(innerBox), options: [.alignAllEdgesNearest])
        }
        hilitedPreeditPath = .squirclePath(polygon: textPolygon, cornerRadius: hilitedCornerRadius)
      }
      deleteBackRect = preeditView.blockRect(for: NSRange(location: preeditContents.length - 1, length: 1))
      deleteBackRect.size.width += theme.fullWidth
      deleteBackRect.origin.x = backgroundRect.maxX - deleteBackRect.width
      deleteBackRect.origin.y += theme.borderInsets.height
      deleteBackRect = backingAlignedRect(deleteBackRect.intersection(preeditRect), options: [.alignAllEdgesNearest])
    }

    /*** Candidates Rects, all in documentView coordinates (except for `candidatesRect`) ***/
    candidatePolygons = []
    sectionRects = []
    tabularIndices = []
    var clipPath: CGPath?, documentPath: CGMutablePath?, gridPath: CGMutablePath?
    if !candidateView.isHidden {
      clipRect.size.width = backgroundRect.width
      clipRect = backingAlignedRect(clipRect.intersection(backgroundRect), options: [.alignAllEdgesNearest])
      documentRect.size.width = backgroundRect.width
      documentRect = documentView.backingAlignedRect(documentRect, options: [.alignAllEdgesNearest])
      clipPath = .squirclePath(rect: clipRect, cornerRadius: hilitedCornerRadius)
      documentPath = .squircleMutablePath(vertices: documentRect.vertices, cornerRadius: hilitedCornerRadius)

      // Draw candidate highlight rect
      candidatePolygons.reserveCapacity(candidateInfos.count)
      if theme.isLinear { // linear layout
        var gridOriginY: Double = documentRect.minY
        let tabInterval: Double = theme.fullWidth * 2
        var lineNum: Int = 0
        var sectionRect: NSRect = .zero
        if theme.isTabular {
          tabularIndices.reserveCapacity(candidateInfos.count)
          gridPath = CGMutablePath()
          if isExpanded {
            sectionRects.reserveCapacity(candidateInfos.count / theme.pageSize + 1)
            sectionRect.size.width = documentRect.width
          }
        }
        for candInfo in candidateInfos {
          var candidatePolygon = candidateView.textPolygon(forRange: candInfo.candidateRange)
          if !candidatePolygon.head.isEmpty {
            candidatePolygon.head.size.width += theme.fullWidth
            candidatePolygon.head = documentView.backingAlignedRect(candidatePolygon.head.intersection(documentRect), options: [.alignAllEdgesNearest])
          }
          if !candidatePolygon.tail.isEmpty {
            candidatePolygon.tail = documentView.backingAlignedRect(candidatePolygon.tail.intersection(documentRect), options: [.alignAllEdgesNearest])
          }
          if !candidatePolygon.body.isEmpty {
            if candInfo.isTruncated {
              candidatePolygon.body.size.width = documentRect.width
            } else if !candidatePolygon.tail.isEmpty {
              candidatePolygon.body.size.width += theme.fullWidth
            }
            candidatePolygon.body = documentView.backingAlignedRect(candidatePolygon.body.intersection(documentRect), options: [.alignAllEdgesNearest])
          }
          if theme.isTabular {
            if isExpanded {
              if candInfo.col == 0 {
                sectionRect.origin.y = ceil(sectionRect.maxY)
              }
              if candInfo.col == theme.pageSize - 1 || candInfo.idx == candidateInfos.count - 1 {
                sectionRect.size.height = ceil(candidatePolygon.maxY) - sectionRect.minY
                sectionRects.append(sectionRect)
              }
            }
            let bottomEdge: Double = candidatePolygon.maxY
            if abs(bottomEdge - gridOriginY) > 2 {
              lineNum += candInfo.idx > 0 ? 1 : 0
              // horizontal border except for the last line
              if bottomEdge < documentRect.maxY - 2 {
                gridPath!.move(to: .init(x: ceil(theme.fullWidth * 0.5), y: bottomEdge))
                gridPath!.addLine(to: .init(x: documentRect.maxX - floor(theme.fullWidth * 0.5), y: bottomEdge))
              }
              gridOriginY = bottomEdge
            }
            let leadOrigin: NSPoint = candidatePolygon.origin
            let leadTabColumn = Int(round((leadOrigin.x - documentRect.minX) / tabInterval))
            // vertical bar
            if leadOrigin.x > documentRect.minX + theme.fullWidth {
              gridPath!.move(to: .init(x: leadOrigin.x, y: leadOrigin.y + ceil(theme.lineSpacing * 0.5) + theme.candidateParagraphStyle.minimumLineHeight * 0.2))
              gridPath!.addLine(to: .init(x: leadOrigin.x, y: candidatePolygon.maxY - floor(theme.lineSpacing * 0.5) - theme.candidateParagraphStyle.minimumLineHeight * 0.2))
            }
            tabularIndices.append(.init(index: candInfo.idx, lineNum: lineNum, tabNum: leadTabColumn))
          }
          candidatePolygons.append(candidatePolygon)
        }
      } else { // stacked layout
        for candInfo in candidateInfos {
          var candidateRect: NSRect = candidateView.blockRect(for: candInfo.candidateRange)
          candidateRect.size.width = documentRect.width
          candidateRect.size.height += theme.lineSpacing
          candidateRect = documentView.backingAlignedRect(candidateRect.intersection(documentRect), options: [.alignAllEdgesNearest])
          candidatePolygons.append(.init(head: .zero, body: candidateRect, tail: .zero))
        }
      }
    }

    /*** Paging Rects ***/
    pageUpRect = .zero
    pageDownRect = .zero
    expanderRect = .zero
    if !pagingView.isHidden {
      if theme.isLinear {
        pagingRect.origin.x = backgroundRect.maxX - pagingRect.width
      } else {
        pagingRect.size.width = backgroundRect.width
      }
      pagingRect = backingAlignedRect(pagingRect.intersection(backgroundRect), options: [.alignAllEdgesNearest])
      if theme.showPaging {
        pageUpRect = pagingView.blockRect(for: NSRange(location: 0, length: 1))
        pageDownRect = pagingView.blockRect(for: NSRange(location: pagingContents.length - 1, length: 1))
        pageDownRect.origin.x += pagingRect.minX
        pageDownRect.size.width += theme.fullWidth
        pageDownRect.origin.y += pagingRect.minY
        pageUpRect.origin.x += pagingRect.minX
        // bypass the bug of getting wrong glyph position when tab is presented
        pageUpRect.size.width = pageDownRect.width
        pageUpRect.origin.y += pagingRect.minY
        pageUpRect = backingAlignedRect(pageUpRect.intersection(pagingRect), options: [.alignAllEdgesNearest])
        pageDownRect = backingAlignedRect(pageDownRect.intersection(pagingRect), options: [.alignAllEdgesNearest])
      }
      if theme.isTabular {
        expanderRect = pagingView.blockRect(for: NSRange(location: pagingContents.length / 2, length: 1))
        expanderRect.origin.x += pagingRect.minX
        expanderRect.size.width += theme.fullWidth
        expanderRect.origin.y += pagingRect.minY
        expanderRect = backingAlignedRect(expanderRect.intersection(pagingRect), options: [.alignAllEdgesNearest])
      }
    }

    /*** Border Rects ***/
    let outerCornerRadius: Double = min(theme.cornerRadius, panelRect.height * 0.5)
    let innerCornerRadius: Double = clamp(theme.hilitedCornerRadius, outerCornerRadius - min(theme.borderInsets.width, theme.borderInsets.height), backgroundRect.height * 0.5)
    let panelPath: CGPath?, backgroundPath: CGPath?
    if !theme.isLinear || pagingView.isHidden {
      panelPath = .squirclePath(rect: panelRect, cornerRadius: outerCornerRadius)
      backgroundPath = .squirclePath(rect: backgroundRect, cornerRadius: innerCornerRadius)
    } else {
      var mainPanelRect: NSRect = panelRect
      mainPanelRect.size.height -= pagingRect.height
      let tailPanelRect = pagingRect.offsetBy(dx: 0, dy: theme.borderInsets.height).insetBy(dx: -theme.borderInsets.width, dy: 0)
      panelPath = .squirclePath(polygon: .init(head: mainPanelRect, body: tailPanelRect, tail: .zero), cornerRadius: outerCornerRadius)
      var mainBackgroundRect: NSRect = backgroundRect
      mainBackgroundRect.size.height -= pagingRect.height
      backgroundPath = .squirclePath(polygon: .init(head: mainBackgroundRect, body: pagingRect, tail: .zero), cornerRadius: innerCornerRadius)
    }
    let borderPath: CGPath? = .combinePaths(panelPath, backgroundPath)
    var flip = CGAffineTransform(translationX: 0, y: panelRect.height)
    flip = flip.scaledBy(x: 1, y: -1)
    let shapePath: CGPath? = panelPath?.copy(using: &flip)!

    /*** Draw into layers ***/
    if #available(macOS 10.14, *) {
      shape.path = shapePath
    }
    // highlighted preedit layer
    if hilitedPreeditPath != nil && theme.hilitedPreeditBackColor != nil {
      hilitedPreeditLayer.path = hilitedPreeditPath!
      hilitedPreeditLayer.isHidden = false
    } else {
      hilitedPreeditLayer.isHidden = true
    }
    // highlighted candidate layer
    if !scrollView.isHidden {
      var translate = CGAffineTransform(translationX: -clipRect.minX, y: -clipRect.minY)
      clipLayer.path = clipPath?.copy(using: &translate)
      var activePagePath: CGMutablePath?
      let expanded: Bool = candidateInfos.count > theme.pageSize
      if expanded {
        let activePageRect: NSRect = sectionRects[sectionNum]
        activePagePath = .squircleMutablePath(vertices: activePageRect.vertices, cornerRadius: hilitedCornerRadius)
        documentPath?.addPath(activePagePath!.copy()!)
      }
      if theme.candidateBackColor != nil {
        let nonHilitedCandidatePath = CGMutablePath()
        let stackColors: Bool = theme.stackColors && theme.candidateBackColor!.alphaComponent < 0.999
        for i in 0 ..< candidateInfos.count {
          if i != hilitedCandidate, let candidatePath: CGPath = theme.isLinear
            ? .squirclePath(polygon: candidatePolygons[i], cornerRadius: hilitedCornerRadius)
            : .squirclePath(rect: candidatePolygons[i].body, cornerRadius: hilitedCornerRadius) {
            nonHilitedCandidatePath.addPath(candidatePath)
            if stackColors {
              (expanded && i / theme.pageSize == hilitedCandidate! / theme.pageSize ? activePagePath : documentPath)?.addPath(candidatePath)
            }
          }
        }
        nonHilitedCandidateLayer.path = nonHilitedCandidatePath.copy()
        nonHilitedCandidateLayer.isHidden = false
      } else {
        nonHilitedCandidateLayer.isHidden = true
      }
      if hilitedCandidate != nil && theme.hilitedCandidateBackColor != nil, let hilitedCandidatePath: CGPath = theme.isLinear
        ? .squirclePath(polygon: candidatePolygons[hilitedCandidate!], cornerRadius: hilitedCornerRadius)
        : .squirclePath(rect: candidatePolygons[hilitedCandidate!].body, cornerRadius: hilitedCornerRadius) {
        if theme.stackColors && theme.hilitedCandidateBackColor!.alphaComponent < 0.999 {
          (expanded ? activePagePath : documentPath)?.addPath(hilitedCandidatePath.copy()!)
        }
        hilitedCandidateLayer.path = hilitedCandidatePath
        hilitedCandidateLayer.isHidden = false
      } else {
        hilitedCandidateLayer.isHidden = true
      }
      if expanded {
        activePageLayer.path = activePagePath?.copy()
        activePageLayer.isHidden = false
      } else {
        activePageLayer.isHidden = true
      }
      documentLayer.path = documentPath?.copy()
      if gridPath != nil {
        gridLayer.path = gridPath?.copy()
        gridLayer.isHidden = false
      } else {
        gridLayer.isHidden = true
      }
    }
    // function buttons (page up, page down, backspace) layer
    var functionButtonPath: CGPath?
    if functionButton != .VoidSymbol {
      functionButtonPath = updateFunctionButtonLayer()
    } else {
      functionButtonLayer.isHidden = true
    }
    // logo at the beginning for status message
    if !statusView.isHidden {
      logoLayer.contentsScale = (logoLayer.contents as! NSImage).recommendedLayerContentsScale(window!.backingScaleFactor)
      logoLayer.isHidden = false
    } else {
      logoLayer.isHidden = true
    }
    // background image (pattern style) layer
    if theme.backImage != nil {
      var transform: CGAffineTransform = theme.isVertical ? CGAffineTransform(rotationAngle: .pi / 2) : CGAffineTransformIdentity
      transform = transform.translatedBy(x: -backgroundRect.origin.x, y: -backgroundRect.origin.y)
      backImageLayer.path = backgroundPath?.copy(using: &transform)
      backImageLayer.setAffineTransform(transform.inverted())
    }
    // background color layer
    if !preeditRect.isEmpty || !pagingRect.isEmpty {
      if clipPath != nil {
        let nonCandidatePath = backgroundPath?.mutableCopy()
        nonCandidatePath?.addPath(clipPath!)
        if theme.stackColors && theme.hilitedPreeditBackColor != nil && theme.hilitedPreeditBackColor!.alphaComponent < 0.999 {
          if hilitedPreeditPath != nil {
            nonCandidatePath?.addPath(hilitedPreeditPath!)
          }
          if functionButtonPath != nil {
            nonCandidatePath?.addPath(functionButtonPath!)
          }
        }
        backColorLayer.path = nonCandidatePath?.copy()
      } else {
        backColorLayer.path = backgroundPath
      }
      backColorLayer.isHidden = false
    } else {
      backColorLayer.isHidden = true
    }
    // border layer
    borderLayer.path = borderPath

    unclipHighlightedCandidate()
  }

  func index(mouseSpot spot: NSPoint) -> SquirrelIndex {
    var point = convert(spot, from: nil)
    if NSMouseInRect(point, bounds, true) {
      if NSMouseInRect(point, preeditRect, true) {
        return NSMouseInRect(point, deleteBackRect, true) ? .BackSpaceKey : .CodeInputArea
      }
      if NSMouseInRect(point, expanderRect, true) {
        return .ExpandButton
      }
      if NSMouseInRect(point, pageUpRect, true) {
        return .PageUpKey
      }
      if NSMouseInRect(point, pageDownRect, true) {
        return .PageDownKey
      }
      if NSMouseInRect(point, clipRect, true) {
        point = convert(point, to: documentView)
        for i in 0 ..< candidateInfos.count {
          if candidatePolygons[i].mouseInPolygon(point: point, flipped: true) {
            return SquirrelIndex(rawValue: i)!
          }
        }
      }
    }
    return .VoidSymbol
  }
} // SquirrelView

@frozen enum SquirrelTooltipDisplay: Sendable {
  case now, delayed, onRequest, none
}

/* In order to put SquirrelPanel above client app windows,
 SquirrelPanel needs to be assigned a window level higher
 than kCGHelpWindowLevelKey that the system tooltips use.
 This class makes system-alike tooltips above SquirrelPanel */
final class SquirrelToolTip: NSPanel {
  private let backView = NSVisualEffectView()
  private let textView = NSTextField()
  private var showTimer: Timer?
  private var hideTimer: Timer?
  private(set) var isEmpty: Bool = true

  init() {
    super.init(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
    backgroundColor = .clear
    isOpaque = true
    hasShadow = true
    let contentView = NSView()
    backView.material = .toolTip
    contentView.addSubview(backView)
    textView.isBezeled = true
    textView.bezelStyle = .squareBezel
    textView.isBordered = true
    textView.isSelectable = false
    contentView.addSubview(textView)
    self.contentView = contentView
  }

  func show(withToolTip toolTip: String!, display: SquirrelTooltipDisplay) {
    if display == .none || toolTip.isEmpty {
      clear(); return
    }
    let panel: SquirrelPanel = NSApp.SquirrelAppDelegate.panel
    level = panel.level + 1

    isEmpty = false
    textView.stringValue = toolTip
    textView.font = .toolTipsFont(ofSize: 0)
    textView.textColor = .windowFrameTextColor
    textView.sizeToFit()
    let contentSize: NSSize = textView.fittingSize

    var spot: NSPoint = NSEvent.mouseLocation
    let cursor: NSCursor! = .currentSystem
    spot.x += cursor.image.size.width - cursor.hotSpot.x
    spot.y -= cursor.image.size.height - cursor.hotSpot.y
    var windowRect = NSRect(x: spot.x, y: spot.y - contentSize.height, width: contentSize.width, height: contentSize.height)

    let screenRect: NSRect = panel.screen!.visibleFrame
    if windowRect.maxX > screenRect.maxX - 0.1 {
      windowRect.origin.x = screenRect.maxX - windowRect.width
    }
    if windowRect.minY < screenRect.minY + 0.1 {
      windowRect.origin.y = screenRect.minY
    }
    windowRect = panel.screen!.backingAlignedRect(windowRect, options: [.alignAllEdgesNearest])
    setFrame(windowRect, display: false)
    textView.frame = contentView!.bounds
    backView.frame = contentView!.bounds

    showTimer?.invalidate()
    showTimer = nil
    switch display {
    case .now:
      show()
    case .delayed:
      showTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in self.show() }
    default:
      break
    }
  }

  func show() {
    if isEmpty { return }
    showTimer?.invalidate()
    showTimer = nil
    display()
    orderFrontRegardless()
    hideTimer?.invalidate()
    hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in self.hide() }
  }

  func hide() {
    showTimer?.invalidate()
    showTimer = nil
    hideTimer?.invalidate()
    hideTimer = nil
    if isVisible {
      orderOut(nil)
    }
  }

  func clear() {
    isEmpty = true
    textView.stringValue = ""
    hide()
  }
} // SquirrelToolTipView

// MARK: Panel window, dealing with text content and mouse interactions

final class SquirrelPanel: NSPanel, NSWindowDelegate {
  // Squirrel panel layouts
  @available(macOS 10.14, *) private let back = NSVisualEffectView()
  private let toolTip = SquirrelToolTip()
  private let view = SquirrelView()
  private var statusTimer: Timer?
  private var maxSizeAttained: NSSize = .zero
  private var scrollLocus: NSPoint = .zero
  private var cursorIndex: SquirrelIndex = .VoidSymbol
  private var textWidthLimit: Double = CGFLOAT_MAX
  private var anchorOffset: Double = 0
  private var scrollByLine: Bool = false
  private var initPosition: Bool = true
  private var needsRedraw: Bool = false
  // Rime contents and actions
  private var indexRange: Range<Int> = 0 ..< 0
  private var highlightedCandidate: Int?
  private var functionButton: SquirrelIndex = .VoidSymbol
  private var caretPos: Int?
  private var pageNum: Int = 0
  private var isLastPage: Bool = false
  // Show preedit text inline.
  var inlinePreedit: Bool { view.theme.inlinePreedit }
  // Show primary candidate inline
  var inlineCandidate: Bool { view.theme.inlineCandidate }
  // Vertical text orientation, as opposed to horizontal text orientation.
  var isVertical: Bool { view.theme.isVertical }
  // Linear candidate list layout, as opposed to stacked candidate list layout.
  var isLinear: Bool { view.theme.isLinear }
  /* Tabular candidate list layout, initializes as tab-aligned linear layout,
   expandable to stack 5 (3 for vertical) pages/sections of candidates */
  var isTabular: Bool { view.theme.isTabular }
  var isLocked: Bool {
    get { return view.isLocked }
    set (newValue) {
      if view.theme.isTabular && view.isLocked != newValue {
        view.isLocked = isLocked
        let userConfig = SquirrelConfig("user")
        _ = userConfig.setOption("var/option/_isLockedTabular", withBool: newValue)
        if newValue {
          _ = userConfig.setOption("var/option/_isExpandedTabular", withBool: view.isExpanded)
        }
        userConfig.close()
      }
    }
  }

  private func getLocked() {
    if view.theme.isTabular {
      let userConfig = SquirrelConfig("user")
      view.isLocked = userConfig.boolValue(forOption: "var/option/_isLockedTabular")
      if view.isLocked {
        view.isExpanded = userConfig.boolValue(forOption: "var/option/_isExpandedTabular")
      }
      userConfig.close()
      view.sectionNum = 0
    }
  }

  var isFirstLine: Bool { view.tabularIndices.isEmpty ? true : view.tabularIndices[highlightedCandidate!].lineNum == 0 }
  var isExpanded: Bool {
    get { return view.isExpanded }
    set (newValue) {
      if view.theme.isTabular && !view.isLocked && !(isLastPage && pageNum == 0) && view.isExpanded != newValue {
        view.isExpanded = newValue
        view.sectionNum = 0
        needsRedraw = true
      }
    }
  }

  var sectionNum: Int {
    get { return view.sectionNum }
    set (newValue) {
      if view.theme.isTabular && view.isExpanded && view.sectionNum != newValue {
        view.sectionNum = clamp(newValue, 0, view.theme.isVertical ? 2 : 4)
      }
    }
  }

  // position of the text input I-beam cursor on screen.
  var IbeamRect: NSRect = .zero {
    didSet {
      if oldValue != IbeamRect {
        needsRedraw = true
        if !IbeamRect.intersects(_screen.frame) {
          updateScreen()
          updateDisplayParameters()
        }
      }
    }
  }

  private var _screen: NSScreen! = .main
  override var screen: NSScreen? { _screen }
  weak var inputController: SquirrelInputController?
  var style: SquirrelStyle {
    didSet {
      if oldValue != style {
        view.style = style
        appearance = NSAppearance(named: style == .dark ? .darkAqua : .aqua)
      }
    }
  }

  // Status message when pop-up is about to be displayed; nil when normal panel is about to be displayed
  private var statusMessage: String?
  var hasStatusMessage: Bool { statusMessage != nil }
  // Store switch options that change style (color theme) settings
  var optionSwitcher = SquirrelOptionSwitcher()

  init() {
    style = .light
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    level = .init(Int(CGWindowLevelForKey(.cursorWindow) - 100))
    hasShadow = false
    isOpaque = false
    backgroundColor = .clear
    delegate = self
    acceptsMouseMovedEvents = true

    let contentView = NSFlippedView()
    contentView.autoresizesSubviews = false
    if #available(macOS 10.14, *) {
      back.blendingMode = .behindWindow
      back.material = .hudWindow
      back.state = .active
      back.isEmphasized = true
      back.wantsLayer = true
      back.layer!.mask = view.shape
      contentView.addSubview(back)
    }
    contentView.addSubview(view)
    contentView.addSubview(view.statusView)
    contentView.addSubview(view.preeditView)
    contentView.addSubview(view.scrollView)
    contentView.addSubview(view.pagingView)
    self.contentView = contentView

    toolTip.appearanceSource = self
    appearance = NSAppearance(named: .aqua)
    updateDisplayParameters()
  }

  func windowDidChangeBackingProperties(_ notification: Notification) {
    if let panel = notification.object as? SquirrelPanel {
      panel.updateDisplayParameters()
    }
  }

  private func updateDisplayParameters() {
    let theme: SquirrelTheme = view.theme
    // repositioning the panel window
    initPosition = true
    maxSizeAttained = .zero

    view.candidateView.setLayoutOrientation(view.theme.isVertical ? .vertical : .horizontal)
    view.preeditView.setLayoutOrientation(view.theme.isVertical ? .vertical : .horizontal)
    view.pagingView.setLayoutOrientation(view.theme.isVertical ? .vertical : .horizontal)
    view.statusView.setLayoutOrientation(view.theme.isVertical ? .vertical : .horizontal)
    // rotate the view, the core in vertical mode!
    contentView!.boundsRotation = view.theme.isVertical ? 90.0 : 0.0
    view.candidateView.boundsRotation = 0.0
    view.preeditView.boundsRotation = 0.0
    view.pagingView.boundsRotation = 0.0
    view.statusView.boundsRotation = 0.0
    view.candidateView.setBoundsOrigin(.zero)
    view.preeditView.setBoundsOrigin(.zero)
    view.pagingView.setBoundsOrigin(.zero)
    view.statusView.setBoundsOrigin(.zero)

    view.scrollView.lineScroll = view.theme.candidateParagraphStyle.minimumLineHeight
    view.candidateView.contentBlock = view.theme.isLinear ? .linearCandidates : .stackedCandidates
    view.candidateView.defaultParagraphStyle = view.theme.candidateParagraphStyle
    view.preeditView.defaultParagraphStyle = view.theme.preeditParagraphStyle
    view.pagingView.defaultParagraphStyle = view.theme.pagingParagraphStyle
    view.statusView.defaultParagraphStyle = view.theme.statusParagraphStyle

    // size limits on textContainer
    let screenRect: NSRect = _screen.visibleFrame
    let textWidthRatio: Double = min(0.8, 1.0 / (theme.isVertical ? 4 : 3) + (theme.textAttrs[.font] as! NSFont).pointSize / 144.0)
    textWidthLimit = ceil((theme.isVertical ? screenRect.height : screenRect.width) * textWidthRatio - theme.borderInsets.width * 2 - theme.fullWidth)
    if view.theme.lineLength > 0.1 {
      textWidthLimit = min(theme.lineLength, textWidthLimit)
    }
    if view.theme.isTabular {
      textWidthLimit = floor((textWidthLimit + theme.fullWidth) / (theme.fullWidth * 2)) * (theme.fullWidth * 2) - theme.fullWidth
    }
    view.candidateView.textContainer!.size = .init(width: textWidthLimit, height: CGFLOAT_MAX)
    view.preeditView.textContainer!.size = .init(width: textWidthLimit, height: CGFLOAT_MAX)
    view.pagingView.textContainer!.size = .init(width: textWidthLimit, height: CGFLOAT_MAX)
    view.statusView.textContainer!.size = .init(width: textWidthLimit, height: CGFLOAT_MAX)

    // color, opacity and transluecency
    alphaValue = view.theme.opacity
    // resize logo and background image, if any
    let statusHeight: Double = view.theme.statusParagraphStyle.minimumLineHeight
    let logoRect = NSRect(x: view.theme.borderInsets.width - 0.1 * statusHeight, y: view.theme.borderInsets.height - 0.1 * statusHeight, width: statusHeight * 1.2, height: statusHeight * 1.2)
    view.logoLayer.frame = logoRect
    let logoImage = NSImage(named: NSImage.applicationIconName)!
    logoImage.size = logoRect.size
    view.logoLayer.contents = logoImage
    view.logoLayer.setAffineTransform(view.theme.isVertical ? CGAffineTransform(rotationAngle: -.pi / 2) : CGAffineTransformIdentity)
    if let lightBackImage = SquirrelView.lightTheme.backImage, lightBackImage.isValid {
      let widthLimit: Double = textWidthLimit + SquirrelView.lightTheme.fullWidth
      lightBackImage.resizingMode = .stretch
      lightBackImage.size = SquirrelView.lightTheme.isVertical ? .init(width: lightBackImage.size.width / lightBackImage.size.height * widthLimit, height: widthLimit) : .init(width: widthLimit, height: lightBackImage.size.height / lightBackImage.size.width * widthLimit)
    }
    if #available(macOS 10.14, *) {
      back.isHidden = view.theme.translucency < 0.001
      if let darkBackImage = SquirrelView.darkTheme.backImage, darkBackImage.isValid {
        let widthLimit: Double = textWidthLimit + SquirrelView.darkTheme.fullWidth
        darkBackImage.resizingMode = .stretch
        darkBackImage.size = SquirrelView.darkTheme.isVertical ? .init(width: darkBackImage.size.width / darkBackImage.size.height * widthLimit, height: widthLimit) : .init(width: widthLimit, height: darkBackImage.size.height / darkBackImage.size.width * widthLimit)
      }
    }
    view.updateColors()
  }

  func candidateIndex(onDirection arrowKey: SquirrelIndex) -> Int? {
    if highlightedCandidate == nil || !isTabular || indexRange.count == 0 {
      return nil
    }
    let currentTab: Int = view.tabularIndices[highlightedCandidate!].tabNum
    let currentLine: Int = view.tabularIndices[highlightedCandidate!].lineNum
    let finalLine: Int = view.tabularIndices[indexRange.count - 1].lineNum
    if arrowKey == (view.theme.isVertical ? .LeftKey : .DownKey) {
      if highlightedCandidate == indexRange.count - 1 && isLastPage {
        return nil
      }
      if currentLine == finalLine && !isLastPage {
        return indexRange.upperBound
      }
      var newIndex: Int = highlightedCandidate! + 1
      while newIndex < indexRange.count && (view.tabularIndices[newIndex].lineNum == currentLine ||
        (view.tabularIndices[newIndex].lineNum == currentLine + 1 &&
          view.tabularIndices[newIndex].tabNum <= currentTab)) {
        newIndex += 1
      }
      if newIndex != indexRange.count || isLastPage {
        newIndex -= 1
      }
      return newIndex + indexRange.lowerBound
    } else if arrowKey == (view.theme.isVertical ? .RightKey : .UpKey) {
      if currentLine == 0 {
        return pageNum == 0 ? nil : indexRange.lowerBound - 1
      }
      var newIndex: Int = highlightedCandidate! - 1
      while newIndex > 0 && (view.tabularIndices[newIndex].lineNum == currentLine ||
        (view.tabularIndices[newIndex].lineNum == currentLine - 1 &&
          view.tabularIndices[newIndex].tabNum > currentTab)) {
        newIndex -= 1
      }
      return newIndex + indexRange.lowerBound
    }
    return nil
  }

  // handle mouse interaction events
  override func sendEvent(_ event: NSEvent) {
    let theme: SquirrelTheme = view.theme
    switch event.type {
    case .leftMouseDown:
      if event.clickCount == 1 && cursorIndex == .CodeInputArea && caretPos != nil {
        let spot: NSPoint = view.preeditView.convert(mouseLocationOutsideOfEventStream, from: nil)
        let inputIndex: Int = view.preeditView.characterIndexForInsertion(at: spot)
        if inputIndex == 0 {
          inputController?.perform(action: .PROCESS, onIndex: .HomeKey)
        } else if inputIndex < caretPos! {
          inputController?.moveCursor(caretPos!, to: inputIndex, inlinePreedit: false, inlineCandidate: false)
        } else if inputIndex >= view.preeditContents.length - 2 {
          inputController?.perform(action: .PROCESS, onIndex: .EndKey)
        } else if inputIndex > caretPos! + 1 {
          inputController?.moveCursor(caretPos!, to: inputIndex - 1, inlinePreedit: false, inlineCandidate: false)
        }
      }
    case .leftMouseUp:
      if event.clickCount == 1 && cursorIndex != nil {
        if cursorIndex == highlightedCandidate {
          inputController?.perform(action: .SELECT, onIndex: cursorIndex + indexRange.lowerBound)
        } else if cursorIndex == functionButton {
          if cursorIndex == .ExpandButton {
            if view.isLocked {
              isLocked = false
              view.pagingContents.replaceCharacters(in: NSRange(location: view.pagingContents.length / 2, length: 1), with: (view.isExpanded ? theme.symbolCompress : theme.symbolExpand)!)
              view.pagingView.setNeedsDisplay(view.convert(view.expanderRect, to: view.pagingView))
            } else {
              isExpanded = !view.isExpanded
              sectionNum = 0
            }
          }
          inputController?.perform(action: .PROCESS, onIndex: cursorIndex)
        }
      }
    case .rightMouseUp:
      if event.clickCount == 1 && cursorIndex != nil {
        if cursorIndex == highlightedCandidate {
          inputController?.perform(action: .DELETE, onIndex: cursorIndex + indexRange.lowerBound)
        } else if cursorIndex == functionButton {
          switch functionButton {
          case .PageUpKey:
            inputController?.perform(action: .PROCESS, onIndex: .HomeKey)
          case .PageDownKey:
            inputController?.perform(action: .PROCESS, onIndex: .EndKey)
          case .ExpandButton:
            isLocked = !view.isLocked
            view.pagingContents.replaceCharacters(in: NSRange(location: view.pagingContents.length / 2, length: 1), with: (view.isLocked ? theme.symbolLock : view.isExpanded ? theme.symbolCompress : theme.symbolExpand)!)
            view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: view.pagingContents.length / 2, length: 1))
            view.pagingView.setNeedsDisplay(view.convert(view.expanderRect, to: view.pagingView), avoidAdditionalLayout: true)
            inputController?.perform(action: .PROCESS, onIndex: .LockButton)
          case .BackSpaceKey:
            inputController?.perform(action: .PROCESS, onIndex: .EscapeKey)
          default:
            break
          }
        }
      }
    case .mouseMoved:
      if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control] { return }
      let noDelay: Bool = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.option]
      cursorIndex = view.index(mouseSpot: mouseLocationOutsideOfEventStream)
      if cursorIndex == .VoidSymbol {
        toolTip.clear()
        highlightFunctionButton(.VoidSymbol, displayToolTip: .none)
      } else {
        if cursorIndex != highlightedCandidate && cursorIndex != functionButton {
          toolTip.clear()
        } else if noDelay {
          toolTip.show()
        }
        if cursorIndex >= 0 && cursorIndex < indexRange.count && cursorIndex != highlightedCandidate {
          highlightFunctionButton(.VoidSymbol, displayToolTip: .none)
          if theme.isLinear && view.candidateInfos[cursorIndex.rawValue].isTruncated {
            toolTip.show(withToolTip: view.candidateContents.mutableString.substring(with: view.candidateInfos[cursorIndex.rawValue].candidateRange), display: .now)
          } else {
            toolTip.show(withToolTip: NSLocalizedString("candidate", comment: ""), display: .onRequest )
          }
          sectionNum = cursorIndex.rawValue / theme.pageSize
          inputController?.perform(action: .HIGHLIGHT, onIndex: cursorIndex + indexRange.lowerBound)
        } else if (cursorIndex == .PageUpKey || cursorIndex == .PageDownKey ||
          cursorIndex == .ExpandButton || cursorIndex == .BackSpaceKey) && functionButton != cursorIndex {
          highlightFunctionButton(cursorIndex, displayToolTip: noDelay ? .now : .delayed)
        }
      }
    case .mouseExited:
      cursorIndex = .VoidSymbol
      toolTip.clear()
    case .leftMouseDragged:
      // reset the `remember_size` references after moving the panel
      maxSizeAttained = .zero
      performDrag(with: event)
    case .scrollWheel:
      let scrollThreshold: Double = view.theme.candidateParagraphStyle.minimumLineHeight
      if event.phase == .began {
        scrollLocus = .zero
        scrollByLine = false
      } else if event.phase == .changed && scrollLocus.x.isFinite && scrollLocus.y.isFinite {
        var scrollDistance: Double = 0.0
        // determine scrolling direction by confining to sectors within ±30º of any axis
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * sqrt(3.0) {
          scrollDistance = event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : scrollThreshold)
          scrollLocus.x += scrollDistance
        } else if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) * sqrt(3.0) {
          scrollDistance = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : scrollThreshold)
          scrollLocus.y += scrollDistance
        }
        // compare accumulated locus length against threshold and limit paging to max once
        if scrollLocus.x > scrollThreshold {
          if theme.isVertical && view.scrollView.documentVisibleRect.maxY < view.documentRect.maxY - 0.1 {
            scrollByLine = true
            var origin: NSPoint = view.scrollView.contentView.bounds.origin
            origin.y += min(scrollDistance, view.documentRect.maxY - view.scrollView.documentVisibleRect.maxY)
            view.scrollView.contentView.scroll(to: origin)
            view.scrollView.verticalScroller?.doubleValue =
              view.scrollView.documentVisibleRect.minY / view.clippedHeight
          } else if !scrollByLine {
            inputController?.perform(action: .PROCESS, onIndex: theme.isVertical ? .PageDownKey : .PageUpKey)
            scrollLocus = .init(x: Double.infinity, y: Double.infinity)
          }
        } else if scrollLocus.y > scrollThreshold {
          if view.scrollView.documentVisibleRect.minY > view.documentRect.minY + 0.1 {
            scrollByLine = true
            var origin: NSPoint = view.scrollView.contentView.bounds.origin
            origin.y -= min(scrollDistance, view.scrollView.documentVisibleRect.minY - view.documentRect.minY)
            view.scrollView.contentView.scroll(to: origin)
            view.scrollView.verticalScroller?.doubleValue =
              view.scrollView.documentVisibleRect.minY / view.clippedHeight
          } else if !scrollByLine {
            inputController?.perform(action: .PROCESS, onIndex: .PageUpKey)
            scrollLocus = .init(x: Double.infinity, y: Double.infinity)
          }
        } else if scrollLocus.x < -scrollThreshold {
          if theme.isVertical && view.scrollView.documentVisibleRect.minY > view.documentRect.minY + 0.1 {
            scrollByLine = true
            var origin: NSPoint = view.scrollView.contentView.bounds.origin
            origin.y += max(scrollDistance, view.documentRect.minY - view.scrollView.documentVisibleRect.minY)
            view.scrollView.contentView.scroll(to: origin)
            view.scrollView.verticalScroller?.doubleValue =
              view.scrollView.documentVisibleRect.minY / view.clippedHeight
          } else if !scrollByLine {
            inputController?.perform(action: .PROCESS, onIndex: theme.isVertical ? .PageUpKey : .PageDownKey)
            scrollLocus = .init(x: Double.infinity, y: Double.infinity)
          }
        } else if scrollLocus.y < -scrollThreshold {
          if view.scrollView.documentVisibleRect.maxY < view.documentRect.maxY - 0.1 {
            scrollByLine = true
            var origin: NSPoint = view.scrollView.contentView.bounds.origin
            origin.y -= max(scrollDistance, view.scrollView.documentVisibleRect.maxY - view.documentRect.maxY)
            view.scrollView.contentView.scroll(to: origin)
            view.scrollView.verticalScroller?.doubleValue =
              view.scrollView.documentVisibleRect.minY / view.clippedHeight
          } else if !scrollByLine {
            inputController?.perform(action: .PROCESS, onIndex: .PageDownKey)
            scrollLocus = .init(x: Double.infinity, y: Double.infinity)
          }
        }
      }
    default:
      super.sendEvent(event)
    }
  }

  func showToolTip() -> Bool {
    if !toolTip.isEmpty {
      toolTip.show()
      return true
    }
    return false
  }

  private func highlightCandidate(_ highlightedCandidate: Int?) {
    if highlightedCandidate == nil || self.highlightedCandidate == nil {
      return
    }
    let theme: SquirrelTheme = view.theme
    let priorHilitedCandidate: Int = self.highlightedCandidate!
    let priorSectionNum: Int = priorHilitedCandidate / theme.pageSize
    self.highlightedCandidate = highlightedCandidate
    view.sectionNum = highlightedCandidate! / theme.pageSize
    // apply new foreground colors
    for i in 0 ..< theme.pageSize {
      let priorCandidate: Int = i + priorSectionNum * theme.pageSize
      if (view.sectionNum != priorSectionNum || priorCandidate == priorHilitedCandidate) && priorCandidate < indexRange.count {
        let labelColor = priorCandidate == priorHilitedCandidate && view.sectionNum == priorSectionNum ? theme.labelForeColor : theme.dimmedLabelForeColor!
        view.candidateContents.addAttribute(.foregroundColor, value: labelColor, range: view.candidateInfos[priorCandidate].labelRange)
        if priorCandidate == priorHilitedCandidate {
          view.candidateContents.addAttribute(.foregroundColor, value: theme.textForeColor, range: view.candidateInfos[priorCandidate].textRange)
          view.candidateContents.addAttribute(.foregroundColor, value: theme.commentForeColor, range: view.candidateInfos[priorCandidate].commentRange)
        }
      }
      let newCandidate: Int = i + view.sectionNum * theme.pageSize
      if (view.sectionNum != priorSectionNum || newCandidate == highlightedCandidate) && newCandidate < indexRange.count {
        view.candidateContents.addAttribute(.foregroundColor, value: newCandidate == highlightedCandidate ? theme.hilitedLabelForeColor : theme.labelForeColor, range: view.candidateInfos[newCandidate].labelRange)
        if newCandidate == highlightedCandidate {
          view.candidateContents.addAttribute(.foregroundColor, value: theme.hilitedTextForeColor, range: view.candidateInfos[newCandidate].textRange)
          view.candidateContents.addAttribute(.foregroundColor, value: theme.hilitedCommentForeColor, range: view.candidateInfos[newCandidate].commentRange)
        }
      }
    }
    view.highlightCandidate(highlightedCandidate)
  }

  private func highlightFunctionButton(_ functionButton: SquirrelIndex, displayToolTip display: SquirrelTooltipDisplay) {
    if self.functionButton == functionButton { return }
    let theme: SquirrelTheme = view.theme
    switch self.functionButton {
    case .PageUpKey:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor, range: NSRange(location: 0, length: 1))
    case .PageDownKey:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor, range: NSRange(location: view.pagingContents.length - 1, length: 1))
    case .ExpandButton:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor, range: NSRange(location: view.pagingContents.length / 2, length: 1))
    case .BackSpaceKey:
      view.preeditContents.addAttribute(.foregroundColor, value: theme.preeditForeColor, range: NSRange(location: view.preeditContents.length - 1, length: 1))
    default:
      break
    }
    self.functionButton = functionButton
    var newFunctionButton: SquirrelIndex = .VoidSymbol
    switch functionButton {
    case .PageUpKey:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: 0, length: 1))
      newFunctionButton = pageNum == 0 ? .HomeKey : .PageUpKey
      toolTip.show(withToolTip: NSLocalizedString(pageNum == 0 ? "home" : "page_up", comment: ""), display: display)
    case .PageDownKey:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: view.pagingContents.length - 1, length: 1))
      newFunctionButton = isLastPage ? .EndKey : .PageDownKey
      toolTip.show(withToolTip: NSLocalizedString(isLastPage ? "end" : "pageDown", comment: ""), display: display)
    case .ExpandButton:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: view.pagingContents.length / 2, length: 1))
      newFunctionButton = view.isLocked ? .LockButton : view.isExpanded ? .CompressButton : .ExpandButton
      toolTip.show(withToolTip: NSLocalizedString(view.isLocked ? "unlock" : view.isExpanded ? "compress" : "expand", comment: ""), display: display)
    case .BackSpaceKey:
      view.preeditContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: view.preeditContents.length - 1, length: 1))
      newFunctionButton = caretPos == nil || caretPos == 0 ? .EscapeKey : .BackSpaceKey
      toolTip.show(withToolTip: NSLocalizedString(caretPos == nil || caretPos == 0 ? "escape" : "delete", comment: ""), display: display)
    default:
      break
    }
    view.highlightFunctionButton(newFunctionButton)
    displayIfNeeded()
  }

  private func updateScreen() {
    for screen in NSScreen.screens {
      if screen.frame.contains(IbeamRect.origin) {
        _screen = screen; return
      }
    }
    _screen = .main
  }

  // Get the window size, it will be the dirtyRect in SquirrelView.drawRect
  private func show() {
    if !needsRedraw && !initPosition {
      isVisible ? displayIfNeeded() : orderFront(nil); return
    }
    // Break line if the text is too long, based on screen size.
    let theme: SquirrelTheme = view.theme
    let border: NSSize = theme.borderInsets
    let textWidthRatio: Double = min(0.8, 1.0 / (theme.isVertical ? 4 : 3) + (theme.textAttrs[.font] as! NSFont).pointSize / 144.0)
    let screenRect: NSRect = _screen.visibleFrame

    // the sweep direction of the client app changes the behavior of adjusting Squirrel panel position
    let sweepVertical: Bool = IbeamRect.width > IbeamRect.height
    var contentRect: NSRect = view.contentRect
    // fixed line length (text width), but not applicable to status message
    if theme.lineLength > 0.1 && view.statusView.isHidden {
      contentRect.size.width = textWidthLimit
    }
    /* remember panel size (fix the top leading anchor of the panel in screen coordiantes)
     but only when the text would expand on the side of upstream (i.e. towards the beginning of text) */
    if theme.rememberSize && view.statusView.isHidden {
      if theme.lineLength < 0.1 && theme.isVertical
        ? sweepVertical ? (IbeamRect.minY - max(contentRect.width, maxSizeAttained.width) - border.width - floor(theme.fullWidth * 0.5) < screenRect.minY + 0.1)
        : (IbeamRect.minY - kOffsetGap - screenRect.height * textWidthRatio - border.width * 2 - theme.fullWidth < screenRect.minY + 0.1)
        : sweepVertical ? (IbeamRect.minX - kOffsetGap - screenRect.width * textWidthRatio - border.width * 2 - theme.fullWidth > screenRect.minX + 0.1)
        : (IbeamRect.maxX + max(contentRect.width, maxSizeAttained.width) + border.width + floor(theme.fullWidth * 0.5) > screenRect.maxX - 0.1) {
        if contentRect.width > maxSizeAttained.width + 0.1 {
          maxSizeAttained.width = contentRect.width
        } else {
          contentRect.size.width = maxSizeAttained.width
        }
      }
      let textHeight: Double = max(contentRect.height, maxSizeAttained.height) + border.height * 2
      if theme.isVertical ? (IbeamRect.minX - textHeight - (sweepVertical ? kOffsetGap : 0) < screenRect.minX + 0.1)
        : (IbeamRect.minY - textHeight - (sweepVertical ? 0 : kOffsetGap) < screenRect.minY + 0.1) {
        if contentRect.height > maxSizeAttained.height + 0.1 {
          maxSizeAttained.height = contentRect.height
        } else {
          contentRect.size.height = maxSizeAttained.height
        }
      }
    }

    var windowRect: NSRect = .zero
    if view.statusView.isHidden {
      if theme.isVertical {
        // anchor is the top right corner in screen coordinates (maxX, maxY)
        windowRect = NSRect(x: frame.maxX - contentRect.height - border.height * 2,
                            y: frame.maxY - contentRect.width - border.width * 2 - theme.fullWidth,
                            width: contentRect.height + border.height * 2,
                            height: contentRect.width + border.width * 2 + theme.fullWidth)
        initPosition = initPosition || windowRect.intersects(IbeamRect) || !screenRect.contains(windowRect)
        if initPosition {
          if !sweepVertical {
            // To avoid jumping up and down while typing, use the lower screen when typing on upper, and vice versa
            if IbeamRect.minY - kOffsetGap - screenRect.height * textWidthRatio - border.width * 2 - theme.fullWidth < screenRect.minY + 0.1 {
              windowRect.origin.y = IbeamRect.maxY + kOffsetGap
            } else {
              windowRect.origin.y = IbeamRect.minY - kOffsetGap - windowRect.height
            }
            // Make the right edge of candidate block fixed at the left of cursor
            windowRect.origin.x = IbeamRect.minX + border.height - windowRect.width
          } else {
            if IbeamRect.minX - kOffsetGap - windowRect.width < screenRect.minX + 0.1 {
              windowRect.origin.x = IbeamRect.maxX + kOffsetGap
            } else {
              windowRect.origin.x = IbeamRect.minX - kOffsetGap - windowRect.width
            }
            windowRect.origin.y = IbeamRect.minY + border.width + ceil(theme.fullWidth * 0.5) - windowRect.height
          }
        }
      } else {
        // anchor is the top left corner in screen coordinates (minX, maxY)
        windowRect = NSRect(x: frame.minX,
                            y: frame.maxY - contentRect.height - border.height * 2,
                            width: contentRect.width + border.width * 2 + theme.fullWidth,
                            height: contentRect.height + border.height * 2)
        initPosition = initPosition || windowRect.intersects(IbeamRect) || !screenRect.contains(windowRect)
        if initPosition {
          if sweepVertical {
            // To avoid jumping left and right while typing, use the lefter screen when typing on righter, and vice versa
            if IbeamRect.minX - kOffsetGap - screenRect.width * textWidthRatio - border.width * 2 - theme.fullWidth > screenRect.minX + 0.1 {
              windowRect.origin.x = IbeamRect.minX - kOffsetGap - windowRect.width
            } else {
              windowRect.origin.x = IbeamRect.maxX + kOffsetGap
            }
            windowRect.origin.y = IbeamRect.minY + border.height - windowRect.height
          } else {
            if IbeamRect.minY - kOffsetGap - windowRect.height < screenRect.minY + 0.1 {
              windowRect.origin.y = IbeamRect.maxY + kOffsetGap
            } else {
              windowRect.origin.y = IbeamRect.minY - kOffsetGap - windowRect.height
            }
            windowRect.origin.x = IbeamRect.maxX - border.width - ceil(theme.fullWidth * 0.5)
          }
        }
      }
    } else {
      // following system UI, middle-align status message with cursor
      initPosition = true
      if theme.isVertical {
        windowRect.size.width = contentRect.height + border.height * 2
        windowRect.size.height = contentRect.width + border.width * 2 + theme.fullWidth
      } else {
        windowRect.size.width = contentRect.width + border.width * 2 + theme.fullWidth
        windowRect.size.height = contentRect.height + border.height * 2
      }
      if sweepVertical {
        // vertically centre-align (midY) in screen coordinates
        windowRect.origin.x = IbeamRect.minX - kOffsetGap - windowRect.width
        windowRect.origin.y = IbeamRect.midY - windowRect.height * 0.5
      } else {
        // horizontally centre-align (midX) in screen coordinates
        windowRect.origin.x = IbeamRect.midX - windowRect.width * 0.5
        windowRect.origin.y = IbeamRect.minY - kOffsetGap - windowRect.height
      }
    }

    if !view.preeditView.isHidden {
      if initPosition {
        anchorOffset = 0
      }
      if theme.isVertical != sweepVertical {
        let anchorOffset: Double = view.preeditRect.height
        if theme.isVertical {
          windowRect.origin.x += anchorOffset - self.anchorOffset
        } else {
          windowRect.origin.y += anchorOffset - self.anchorOffset
        }
        self.anchorOffset = anchorOffset
      }
    }
    if windowRect.maxX > screenRect.maxX - 0.1 {
      windowRect.origin.x = (initPosition && sweepVertical ? min(IbeamRect.minX - kOffsetGap, screenRect.maxX) : screenRect.maxX) - windowRect.width
    }
    if windowRect.minX < screenRect.minX + 0.1 {
      windowRect.origin.x = initPosition && sweepVertical ? max(IbeamRect.maxX + kOffsetGap, screenRect.minX) : screenRect.minX
    }
    if windowRect.minY < screenRect.minY + 0.1 {
      windowRect.origin.y = initPosition && !sweepVertical ? max(IbeamRect.maxY + kOffsetGap, screenRect.minY) : screenRect.minY
    }
    if windowRect.maxY > screenRect.maxY - 0.1 {
      windowRect.origin.y = (initPosition && !sweepVertical ? min(IbeamRect.minY - kOffsetGap, screenRect.maxY) : screenRect.maxY) - windowRect.height
    }

    if theme.isVertical {
      windowRect.origin.x += contentRect.height - view.contentRect.height
      windowRect.size.width -= contentRect.height - view.contentRect.height
    } else {
      windowRect.origin.y += contentRect.height - view.contentRect.height
      windowRect.size.height -= contentRect.height - view.contentRect.height
    }
    windowRect = _screen.backingAlignedRect(windowRect.intersection(screenRect), options: [.alignAllEdgesNearest])
    setFrame(windowRect, display: true)

    contentView!.setBoundsOrigin(theme.isVertical ? .init(x: -windowRect.width, y: 0.0) : .zero)
    let viewRect: NSRect = contentView!.bounds.integral(options: [.alignAllEdgesNearest])
    view.frame = viewRect
    if !view.statusView.isHidden {
      view.statusView.frame = .init(x: viewRect.minX + border.width + ceil(theme.fullWidth * 0.5) - view.statusView.textContainerOrigin.x,
                                    y: viewRect.minY + border.height - view.statusView.textContainerOrigin.y,
                                    width: viewRect.width - border.width * 2 - theme.fullWidth,
                                    height: viewRect.height - border.height * 2)
    }
    if !view.preeditView.isHidden {
      view.preeditView.frame = .init(x: viewRect.minX + border.width + ceil(theme.fullWidth * 0.5) - view.preeditView.textContainerOrigin.x,
                                     y: viewRect.minY + border.height - view.preeditView.textContainerOrigin.y,
                                     width: viewRect.width - border.width * 2 - theme.fullWidth,
                                     height: view.preeditRect.height)
    }
    if !view.pagingView.isHidden {
      let leadOrigin: Double = theme.isLinear ? viewRect.maxX - view.pagingRect.width - border.width + ceil(theme.fullWidth * 0.5) : viewRect.minX + border.width + ceil(theme.fullWidth * 0.5)
      view.pagingView.frame = .init(x: leadOrigin - view.pagingView.textContainerOrigin.x,
                                    y: viewRect.maxY - border.height - view.pagingRect.height - view.pagingView.textContainerOrigin.y,
                                    width: (theme.isLinear ? view.pagingRect.width : viewRect.width - border.width * 2) - theme.fullWidth,
                                    height: view.pagingRect.height)
    }
    if !view.scrollView.isHidden {
      view.scrollView.frame = .init(x: viewRect.minX + border.width,
                                    y: viewRect.minY + view.clipRect.minY,
                                    width: viewRect.width - border.width * 2,
                                    height: view.clipRect.height)
      view.documentView.frame = .init(x: 0.0, y: 0.0, width: viewRect.width - border.width * 2, height: view.documentRect.height)
      view.candidateView.frame = .init(x: ceil(theme.fullWidth * 0.5) - view.candidateView.textContainerOrigin.x,
                                       y: ceil(theme.lineSpacing * 0.5) - view.candidateView.textContainerOrigin.y,
                                       width: viewRect.width - border.width * 2 - theme.fullWidth,
                                       height: view.documentRect.height - theme.lineSpacing)
    }
    if !back.isHidden { back.frame = viewRect }
    orderFront(nil)
    // reset to initial position after showing status message
    initPosition = !view.statusView.isHidden
    needsRedraw = false
    // voila !
  }

  func hide() {
    statusTimer?.invalidate()
    statusTimer = nil
    toolTip.hide()
    orderOut(nil)
    maxSizeAttained = .zero
    initPosition = true
    isExpanded = false
    sectionNum = 0
  }

  // Main function to add attributes to text output from librime
  func showPanel(withPreedit preedit: String, selRange: NSRange, caretPos: Int?, candidateIndices indexRange: Range<Int>, highlightedCandidate: Int?, pageNum: Int, isLastPage: Bool, didCompose: Bool) {
    let updateCandidates: Bool = didCompose || self.indexRange != indexRange
    self.caretPos = caretPos
    self.pageNum = pageNum
    self.isLastPage = isLastPage
    functionButton = .VoidSymbol
    if indexRange.count > 0 || !preedit.isEmpty {
      statusMessage = nil
      view.statusView.isHidden = true
      if view.statusContents.length > 0 {
        view.statusContents.deleteCharacters(in: NSRange(location: 0, length: view.statusContents.length))
      }
      if statusTimer?.isValid ?? false {
        statusTimer!.invalidate()
        statusTimer = nil
      }
    } else {
      if !(statusMessage?.isEmpty ?? true) {
        showStatus(message: statusMessage!)
        statusMessage = nil
      } else if !(statusTimer?.isValid ?? false) {
        hide()
      }
      return
    }

    let theme: SquirrelTheme = view.theme
    var rulerAttrsPreedit: NSParagraphStyle?
    let priorSize: NSSize = !view.candidateInfos.isEmpty || !view.preeditView.isHidden ? view.contentRect.size : .zero
    if (indexRange.isEmpty || !updateCandidates) && !preedit.isEmpty && view.preeditContents.length > 0 {
      rulerAttrsPreedit = view.preeditContents.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }
    if updateCandidates {
      view.candidateContents.deleteCharacters(in: NSRange(location: 0, length: view.candidateContents.length))
      if theme.lineLength > 0.1 {
        maxSizeAttained.width = min(theme.lineLength, textWidthLimit)
      }
      self.indexRange = indexRange
      self.highlightedCandidate = highlightedCandidate
    }

    // preedit
    if !preedit.isEmpty {
      view.preeditContents.setAttributedString(.init(string: preedit, attributes: theme.preeditAttrs))
      view.preeditContents.mutableString.append(rulerAttrsPreedit == nil ? kFullWidthSpace : "\t")
      if selRange.length > 0 {
        view.preeditContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: selRange)
        let padding = NSNumber(value: ceil(theme.preeditParagraphStyle.minimumLineHeight * 0.05))
        if selRange.location > 0 {
          view.preeditContents.addAttribute(.kern, value: padding, range: NSRange(location: selRange.location - 1, length: 1))
        }
        if selRange.upperBound < view.preeditContents.length {
          view.preeditContents.addAttribute(.kern, value: padding, range: NSRange(location: selRange.upperBound - 1, length: 1))
        }
      }
      view.preeditContents.append(caretPos == nil || caretPos == 0 ? theme.symbolDeleteStroke! : theme.symbolDeleteFill!)
      // force caret to be rendered sideways, instead of uprights, in vertical orientation
      if theme.isVertical && caretPos != nil {
        view.preeditContents.addAttribute(.verticalGlyphForm, value: NSNumber(value: false), range: NSRange(location: caretPos!, length: 1))
      }
      if rulerAttrsPreedit != nil {
        view.preeditContents.addAttribute(.paragraphStyle, value: rulerAttrsPreedit!, range: NSRange(location: 0, length: view.preeditContents.length))
      }

      if updateCandidates && indexRange.isEmpty {
        sectionNum = 0
      } else {
        view.setPreedit(hilitedPreeditRange: selRange)
      }
    } else if view.preeditContents.length > 0 {
      view.preeditContents.deleteCharacters(in: NSRange(location: 0, length: view.preeditContents.length))
    }

    if !updateCandidates {
      if self.highlightedCandidate != highlightedCandidate {
        highlightCandidate(highlightedCandidate)
      }
      let newSize: NSSize = view.contentRect.size
      needsRedraw = needsRedraw || priorSize != newSize
      show()
      return
    }

    // candidate items
    var candidateInfos: [SquirrelCandidateInfo] = []
    if indexRange.count > 0 {
      for idx in 0 ..< indexRange.count {
        let col: Int = idx % theme.pageSize
        let candidate = (idx / theme.pageSize != view.sectionNum ? theme.candidateDimmedTemplate! : idx == highlightedCandidate ? theme.candidateHilitedTemplate : theme.candidateTemplate).mutableCopy() as! NSMutableAttributedString
        // plug in enumerator, candidate text and comment into the template
        let enumRange: NSRange = candidate.mutableString.range(of: "%c")
        candidate.replaceCharacters(in: enumRange, with: theme.labels[col])

        var textRange: NSRange = candidate.mutableString.range(of: "%@")
        let text: String = inputController!.candidateTexts[idx + indexRange.lowerBound]
        candidate.replaceCharacters(in: textRange, with: text)

        let commentRange: NSRange = candidate.mutableString.range(of: kTipSpecifier)
        let comment: String = inputController!.candidateComments[idx + indexRange.lowerBound]
        if !comment.isEmpty {
          candidate.replaceCharacters(in: commentRange, with: "\u{00A0}" + comment)
        } else {
          candidate.deleteCharacters(in: commentRange)
        }
        // parse markdown and ruby annotation
        candidate.formatMarkDown()
        let annotationHeight: Double = candidate.annotateRuby(inRange: NSRange(location: 0, length: candidate.length), verticalOrientation: theme.isVertical, maximumLength: textWidthLimit, scriptVariant: optionSwitcher.currentScriptVariant)
        if annotationHeight * 2 > theme.lineSpacing {
          updateAnnotationHeight(annotationHeight)
          candidate.addAttribute(.paragraphStyle, value: theme.candidateParagraphStyle, range: NSRange(location: 0, length: candidate.length))
          if idx > 0 {
            if theme.isLinear {
              var isTruncated: Bool = candidateInfos[0].isTruncated
              var location: Int = candidateInfos[0].location
              for i in 1 ... idx {
                if i == idx || candidateInfos[i].isTruncated != isTruncated {
                  view.candidateContents.addAttribute(.paragraphStyle, value: isTruncated ? theme.truncatedParagraphStyle! : theme.candidateParagraphStyle, range: NSRange(location: location, length: candidateInfos[i - 1].upperBound - location))
                  if i < idx {
                    isTruncated = candidateInfos[i].isTruncated
                    location = candidateInfos[i].location
                  }
                }
              }
            } else {
              view.candidateContents.addAttribute(.paragraphStyle, value: theme.candidateParagraphStyle, range: NSRange(location: 0, length: view.candidateContents.length))
            }
          }
        }
        // store final in-candidate locations of label, text, and comment
        textRange = candidate.mutableString.range(of: text)

        if idx > 0 && col == 0 && theme.isLinear && !candidateInfos[idx - 1].isTruncated {
          view.candidateContents.mutableString.append("\n")
        }
        let candidateStart: Int = view.candidateContents.length
        view.candidateContents.append(candidate)
        // for linear layout, middle-truncate candidates that are longer than one line
        if theme.isLinear && textWidth(candidate, vertical: theme.isVertical) > textWidthLimit - theme.fullWidth * (theme.isTabular ? 3 : 2) {
          candidateInfos.append(SquirrelCandidateInfo(location: candidateStart, length: view.candidateContents.length - candidateStart, text: textRange.location, comment: textRange.upperBound, idx: idx, col: col, isTruncated: true))
          if idx < indexRange.count - 1 || theme.isTabular || theme.showPaging {
            view.candidateContents.mutableString.append("\n")
          }
          view.candidateContents.addAttribute(.paragraphStyle, value: theme.truncatedParagraphStyle!, range: NSRange(location: candidateStart, length: view.candidateContents.length - candidateStart))
        } else {
          if theme.isLinear || idx < indexRange.count - 1 {
            // separator: linear = "\u3000\x1D"; tabular = "\u3000\t\x1D"; stacked = "\n"
            view.candidateContents.append(theme.separator)
          }
          candidateInfos.append(SquirrelCandidateInfo(location: candidateStart, length: candidate.length + (theme.isTabular ? 3 : theme.isLinear ? 2 : 0), text: textRange.location, comment: textRange.upperBound, idx: idx, col: col, isTruncated: false))
        }
      }

      // paging indication
      if theme.isTabular || theme.showPaging {
        if theme.isTabular {
          view.pagingContents.setAttributedString(view.isLocked ? theme.symbolLock! : view.isExpanded ? theme.symbolCompress! : theme.symbolExpand!)
        } else {
          let pageNumString = NSAttributedString(string: "\(pageNum + 1)", attributes: theme.pagingAttrs)
          view.pagingContents.setAttributedString(theme.isVertical ? pageNumString.horizontalInVerticalForms() : pageNumString)
        }
        if theme.showPaging {
          view.pagingContents.insert(pageNum > 0 ? theme.symbolBackFill! : theme.symbolBackStroke!, at: 0)
          view.pagingContents.mutableString.insert(kFullWidthSpace, at: 1)
          view.pagingContents.mutableString.append(kFullWidthSpace)
          view.pagingContents.append(isLastPage ? theme.symbolForwardStroke! : theme.symbolForwardFill!)
        }
      } else if view.pagingContents.length > 0 {
        view.pagingContents.deleteCharacters(in: NSRange(location: 0, length: view.pagingContents.length))
      }
    }

    view.estimateBounds(onScreen: _screen.visibleFrame, withPreedit: !preedit.isEmpty, candidates: candidateInfos, paging: !indexRange.isEmpty && (theme.isTabular || theme.showPaging))
    let textWidth: Double = clamp(view.contentRect.width, maxSizeAttained.width, textWidthLimit)
    // right-align the backward delete symbol
    if !preedit.isEmpty && rulerAttrsPreedit == nil {
      view.preeditContents.replaceCharacters(in: NSRange(location: view.preeditContents.length - 2, length: 1), with: "\t")
      let rulerAttrs = theme.preeditParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
      rulerAttrs.tabStops = [NSTextTab(textAlignment: .right, location: textWidth)]
      view.preeditContents.addAttribute(.paragraphStyle, value: rulerAttrs, range: NSRange(location: 0, length: view.preeditContents.length))
    }
    if !theme.isLinear && theme.showPaging {
      let rulerAttrsPaging = theme.pagingParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
      view.pagingContents.replaceCharacters(in: NSRange(location: 1, length: 1), with: "\t")
      view.pagingContents.replaceCharacters(in: NSRange(location: view.pagingContents.length - 2, length: 1), with: "\t")
      rulerAttrsPaging.tabStops = [NSTextTab(textAlignment: .center, location: floor(textWidth * 0.5)),
                                   NSTextTab(textAlignment: .right, location: textWidth)]
      view.pagingContents.addAttribute(.paragraphStyle, value: rulerAttrsPaging, range: NSRange(location: 0, length: view.pagingContents.length))
    }

    // text done!
    animationBehavior = .default
    view.drawView(withHilitedCandidate: highlightedCandidate, hilitedPreeditRange: selRange)

    let newSize: NSSize = view.contentRect.size
    needsRedraw = needsRedraw || priorSize != newSize
    show()
  }

  func updateStatus(long: String?, short: String?) {
    switch view.theme.statusMessageType {
    case .mixed:
      statusMessage = short ?? long
    case .long:
      statusMessage = long
    case .short:
      statusMessage = short ?? long == nil ? nil : String(long![long!.rangeOfComposedCharacterSequence(at: long!.startIndex)])
    }
  }

  private func showStatus(message: String) {
    let priorSize: NSSize = view.statusView.isHidden ? .zero : view.contentRect.size

    view.candidateContents.deleteCharacters(in: NSRange(location: 0, length: view.candidateContents.length))
    view.preeditContents.deleteCharacters(in: NSRange(location: 0, length: view.preeditContents.length))
    view.pagingContents.deleteCharacters(in: NSRange(location: 0, length: view.pagingContents.length))

    let attrString = NSAttributedString(string: "\u{3000}\u{2002}" + message, attributes: view.theme.statusAttrs)
    view.statusContents.setAttributedString(attrString)
    view.estimateBounds(onScreen: _screen.visibleFrame, withPreedit: false, candidates: [], paging: false)

    // disable both `remember_size` and fixed lineLength for status messages
    initPosition = true
    maxSizeAttained = .zero
    statusTimer?.invalidate()
    animationBehavior = .utilityWindow
    view.drawView(withHilitedCandidate: nil, hilitedPreeditRange: NSRange(location: NSNotFound, length: 0))

    let newSize: NSSize = view.contentRect.size
    needsRedraw = needsRedraw || priorSize != newSize
    show()
    statusTimer = Timer.scheduledTimer(withTimeInterval: kShowStatusDuration, repeats: false) { _ in self.hide() }
  }

  private func updateAnnotationHeight(_ height: Double) {
    SquirrelView.lightTheme.updateAnnotationHeight(height)
    if #available(macOS 10.14, *) {
      SquirrelView.darkTheme.updateAnnotationHeight(height)
    }
    view.candidateView.defaultParagraphStyle = view.theme.candidateParagraphStyle
  }

  func loadLabelConfig(_ config: SquirrelConfig, directUpdate update: Bool) {
    SquirrelView.lightTheme.updateLabelsWithConfig(config, directUpdate: update)
    if #available(macOS 10.14, *) {
      SquirrelView.darkTheme.updateLabelsWithConfig(config, directUpdate: update)
    }
    if update {
      updateDisplayParameters()
    }
  }

  func loadConfig(_ config: SquirrelConfig) {
    SquirrelView.lightTheme.updateThemeWithConfig(config, styleOptions: optionSwitcher.optionStates, scriptVariant: optionSwitcher.currentScriptVariant)
    if #available(macOS 10.14, *) {
      SquirrelView.darkTheme.updateThemeWithConfig(config, styleOptions: optionSwitcher.optionStates, scriptVariant: optionSwitcher.currentScriptVariant)
    }
    getLocked()
    updateDisplayParameters()
  }

  func updateScriptVariant() {
    SquirrelView.lightTheme.updateScriptVariant(optionSwitcher.currentScriptVariant)
    if #available(macOS 10.14, *) {
      SquirrelView.darkTheme.updateScriptVariant(optionSwitcher.currentScriptVariant)
    }
  }
} // SquirrelPanel

private func textWidth(_ string: NSAttributedString, vertical: Bool) -> Double {
  if vertical {
    let verticalString = string.mutableCopy() as! NSMutableAttributedString
    verticalString.addAttribute(.verticalGlyphForm, value: NSNumber(value: true), range: NSRange(location: 0, length: verticalString.length))
    return ceil(verticalString.size().width)
  } else {
    return ceil(string.size().width)
  }
}
