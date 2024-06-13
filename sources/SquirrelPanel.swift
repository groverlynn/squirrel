import AppKit
import QuartzCore

// MARK: Auxiliaries

extension Comparable {
  func clamp(min: Self, max: Self) -> Self {
    self < min ? min : self > max ? max : self
  }
}

// coalesce: assign new value if current value is null
infix operator ?= : AssignmentPrecedence
func ?= <T: Any>(lhs: inout T?, rhs: T?) { if lhs == nil, rhs != nil { lhs = rhs } }

// overwrite current value with new value (provided not null)
infix operator =? : AssignmentPrecedence
func =? <T: Any>(lhs: inout T?, rhs: T?) { if rhs != nil { lhs = rhs } }
func =? <T: Any>(lhs: inout T, rhs: T?) { if rhs != nil { lhs = rhs! } }

extension CharacterSet {
  static var fullWidthDigits: Self { .init(charactersIn: UnicodeScalar(0xFF10)! ... UnicodeScalar(0xFF19)!) }
  static var fullWidthLatinCapitals: Self { .init(charactersIn: UnicodeScalar(0xFF21)! ... UnicodeScalar(0xFF3A)!) }
}

extension NSPoint: @retroactive AdditiveArithmetic {
  static public func + (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
  static public func - (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
  static public func += (lhs: inout Self, rhs: Self) { lhs.x += rhs.x; lhs.y += rhs.y }
  static public func -= (lhs: inout Self, rhs: Self) { lhs.x -= rhs.x; lhs.y -= rhs.y }
}

extension NSRect { // top-left -> bottom-left -> bottom-right -> top-right
  var vertices: [NSPoint] { isEmpty ? [] : [origin, NSPoint(x: minX, y: maxY), NSPoint(x: maxX, y: maxY), NSPoint(x: maxX, y: minY)] }

  func integral(options: AlignmentOptions) -> Self { NSIntegralRectWithOptions(self, options) }

  func squirclePath(cornerRadius: Double) -> CGPath? {
    CGMutablePath.squirclePath(vertices: vertices, cornerRadius: cornerRadius)?.copy()
  }
}

struct SquirrelTextPolygon: Sendable {
  var head: NSRect = .zero; var body: NSRect = .zero; var tail: NSRect = .zero

  init(head: NSRect = .zero, body: NSRect = .zero, tail: NSRect = .zero) {
    self.head = head; self.body = body; self.tail = tail
  }

  var origin: NSPoint { head.isEmpty ? body.origin : head.origin }
  var minY: CGFloat { head.isEmpty ? body.minY : head.minY }
  var maxY: CGFloat { head.isEmpty ? body.maxY : head.maxY }
  var isSeparated: Bool { !head.isEmpty && body.isEmpty && !tail.isEmpty && tail.maxX < head.minX.nextDown }

  var vertices: [NSPoint] {
    if isSeparated { return [] }
    return switch (head.vertices, body.vertices, tail.vertices) {
    case let (h, [], []): h
    case let ([], [], t): t
    case let ([], b, []): b
    case let (h, b, []): [h[0], h[1], b[0], b[1], b[2], h[3]]
    case let ([], b, t): [b[0], t[1], t[2], t[3], b[2], b[3]]
    case let (h, [], t): [h[0], h[1], t[0], t[1], t[2], t[3], h[2], h[3]]
    case let (h, b, t): [h[0], h[1], b[0], t[1], t[2], t[3], b[2], h[3]]
    }
  }

  func mouseInPolygon(point: NSPoint, flipped: Bool) -> Bool {
    [body, head, tail].contains(where: { !$0.isEmpty && NSMouseInRect(point, $0, flipped) })
  }

  func squirclePath(cornerRadius: Double) -> CGPath? {
    if isSeparated {
      guard let headPath: CGMutablePath = .squirclePath(vertices: head.vertices, cornerRadius: cornerRadius), let tailPath: CGMutablePath = .squirclePath(vertices: tail.vertices, cornerRadius: cornerRadius) else { return nil }
      headPath.addPath(tailPath)
      return headPath.copy()
    } else {
      return CGMutablePath.squirclePath(vertices: vertices, cornerRadius: cornerRadius)?.copy()
    }
  }
}

struct SquirrelTabularIndex: Sendable {
  var index: Int; var lineNum: Int; var tabNum: Int

  init(index: Int, lineNum: Int, tabNum: Int) { self.index = index; self.lineNum = lineNum; self.tabNum = tabNum }
}

struct SquirrelCandidateInfo: Sendable {
  var location: Int; var length: Int; var text: Int; var comment: Int
  var idx: Int; var col: Int; var isTruncated: Bool

  init(location: Int, length: Int, text: Int, comment: Int, idx: Int, col: Int, isTruncated: Bool) {
    self.location = location; self.length = length; self.text = text; self.comment = comment
    self.idx = idx; self.col = col; self.isTruncated = isTruncated
  }

  var candidateRange: NSRange { .init(location: location, length: length) }
  var upperBound: Int { location + length }
  var labelRange: NSRange { .init(location: location, length: text) }
  var textRange: NSRange { .init(location: location + text, length: comment - text) }
  var commentRange: NSRange { .init(location: location + comment, length: length - comment) }
}

extension CGPath {
  class func combinePaths(_ x: CGPath?, _ y: CGPath?) -> CGPath? {
    guard let x = x, let y = y else { return y?.copy() ?? x?.copy() }
    let path: CGMutablePath? = x.mutableCopy()
    path?.addPath(y)
    return path?.copy()
  }
}

extension CGMutablePath {
  // Bezier squircle curves, whose rounded corners are smooth (continously differentiable)
  class func squirclePath(vertices: [CGPoint], cornerRadius: Double) -> Self? {
    guard [4, 6, 8].contains(vertices.count) else { return nil }
    let path: Self = .init()
    var vertex: CGPoint = vertices.last!
    var nextVertex: CGPoint = vertices.first!
    var nextDiff: CGVector = .init(dx: nextVertex.x - vertex.x, dy: nextVertex.y - vertex.y)
    var lastDiff: CGVector
    var arcRadius: Double
    var startPoint: CGPoint
    var endPoint: CGPoint = .init(x: vertex.x + nextDiff.dx * 0.5, y: nextVertex.y)
    path.move(to: endPoint)
    for i in 0 ..< vertices.count {
      lastDiff = nextDiff
      vertex = nextVertex
      nextVertex = vertices[(i + 1) % vertices.count]
      nextDiff = CGVector(dx: nextVertex.x - vertex.x, dy: nextVertex.y - vertex.y)
      if nextDiff.dx.magnitude >= nextDiff.dy.magnitude {
        arcRadius = min(cornerRadius.magnitude, nextDiff.dx.magnitude * 0.5, lastDiff.dy.magnitude * 0.5).rounded(.down)
        startPoint = CGPoint(x: vertex.x, y: vertex.y - Double(signOf: lastDiff.dy, magnitudeOf: arcRadius))
        endPoint = CGPoint(x: vertex.x + Double(signOf: nextDiff.dx, magnitudeOf: arcRadius), y: vertex.y)
      } else {
        arcRadius = min(cornerRadius.magnitude, nextDiff.dy.magnitude * 0.5, lastDiff.dx.magnitude * 0.5).rounded(.down)
        startPoint = CGPoint(x: vertex.x - Double(signOf: lastDiff.dx, magnitudeOf: arcRadius), y: vertex.y)
        endPoint = CGPoint(x: vertex.x, y: vertex.y + Double(signOf: nextDiff.dy, magnitudeOf: arcRadius))
      }
      path.addLine(to: startPoint)
      path.addCurve(to: endPoint, control1: vertex, control2: vertex)
    }
    path.closeSubpath()
    return path
  }
}

protocol ContrastingMutability {
  associatedtype ImmutableType
  associatedtype MutableType
  func copy() -> ImmutableType
  func mutableCopy() -> MutableType
}

extension NSParagraphStyle: ContrastingMutability {
  typealias ImmutableType = NSParagraphStyle
  typealias MutableType = NSMutableParagraphStyle
  func mutableCopy() -> MutableType { mutableCopy(with: nil) as! MutableType }
  func copy() -> ImmutableType { copy(with: nil) as! ImmutableType }
}

extension NSAttributedString: ContrastingMutability {
  typealias ImmutableType = NSAttributedString
  typealias MutableType = NSMutableAttributedString
  func mutableCopy() -> MutableType { mutableCopy(with: nil) as! MutableType }
  func copy() -> ImmutableType { copy(with: nil) as! ImmutableType }
}

extension NSAttributedString.Key {
  static let baselineClass: Self = .init(kCTBaselineClassAttributeName as String)
  static let baselineReferenceInfo: Self = .init(kCTBaselineReferenceInfoAttributeName as String)
  static let rubyAnnotation: Self = .init(kCTRubyAnnotationAttributeName as String)
  static let language: Self = .init(kCTLanguageAttributeName as String)
  static let controlCharacterSize: Self = .init("ControlCharacterSize")
}

extension NSMutableAttributedString {
  private func superscriptionRange(_ range: NSRange) {
    enumerateAttribute(.font, in: range, options: [.longestEffectiveRangeNotRequired]) { value, subRange, stop in
      guard let oldFont: NSFont = value as? NSFont else { return }
      let newFont: NSFont = .init(descriptor: oldFont.fontDescriptor, size: (oldFont.pointSize * 0.55).rounded(.down))!
      let attrs: [NSAttributedString.Key : Any] = [.font : newFont, .superscript : 1]
      addAttributes(attrs, range: subRange)
    }
  }

  private func subscriptionRange(_ range: NSRange) {
    enumerateAttribute(.font, in: range, options: [.longestEffectiveRangeNotRequired]) { value, subRange, stop in
      guard let oldFont: NSFont = value as? NSFont else { return }
      let newFont: NSFont = .init(descriptor: oldFont.fontDescriptor, size: (oldFont.pointSize * 0.55).rounded(.down))!
      let attrs: [NSAttributedString.Key : Any] = [.font : newFont, .superscript : -1]
      addAttributes(attrs, range: subRange)
    }
  }

  static private let markDownRegex: NSRegularExpression = try! .init(pattern: "((\\*{1,2}|\\^|~{1,2})|((?<=\\b)_{1,2})|<(b|strong|i|em|u|sup|sub|s)>)(.+?)(\\2|\\3(?=\\b)|<\\/\\4>)", options: [.useUnicodeWordBoundaries])
  func formatMarkDown() {
    var offset: Int = 0
    Self.markDownRegex.enumerateMatches(in: string, options: [], range: NSRange(location: 0, length: length)) { match, flags, stop in
      guard let match = match else { return }
      let adjusted: NSTextCheckingResult = match.adjustingRanges(offset: offset)
      switch mutableString.substring(with: adjusted.range(at: 1)) {
      case "**", "__", "<b>", "<strong>":
        applyFontTraits(.boldFontMask, range: adjusted.range(at: 5))
      case "*", "_", "<i>", "<em>":
        applyFontTraits(.italicFontMask, range: adjusted.range(at: 5))
      case "<u>":
        addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: adjusted.range(at: 5))
      case "~~", "<s>":
        addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: adjusted.range(at: 5))
      case "^", "<sup>":
        superscriptionRange(adjusted.range(at: 5))
      case "~", "<sub>":
        subscriptionRange(adjusted.range(at: 5))
      default: break
      }
      deleteCharacters(in: adjusted.range(at: 6))
      deleteCharacters(in: adjusted.range(at: 1))
      offset -= adjusted.range(at: 6).length + adjusted.range(at: 1).length
    }
    if offset != 0 { // repeat until no more nested markdown
      formatMarkDown()
    }
  }

  static private let rubyRegex: NSRegularExpression = try! .init(pattern: "(\\x{FFF9}\\s*)(\\S+?)(\\s*\\x{FFFA}(.+?)\\x{FFFB})")
  func annotateRuby(inRange range: NSRange, verticalOrientation isVertical: Bool, maximumLength maxLength: Double, scriptVariant: String) -> Double {
    var rubyLineHeight: Double = .zero
    Self.rubyRegex.enumerateMatches(in: string, options: [], range: range) { match, flags, stop in
      guard let match = match else { return }
      let baseRange: NSRange = match.range(at: 2)
      // no ruby annotation if the base string includes line breaks
      if attributedSubstring(from: NSRange(location: 0, length: baseRange.upperBound)).size().width > maxLength.nextDown {
        deleteCharacters(in: NSRange(location: match.range.upperBound - 1, length: 1))
        deleteCharacters(in: NSRange(location: match.range(at: 3).location, length: 1))
        deleteCharacters(in: NSRange(location: match.range(at: 1).location, length: 1))
      } else {
        // base string must use only one font so that all fall within one glyph run
        // and the ruby annotation is aligned with no duplicates
        var baseFont: NSFont = attribute(.font, at: baseRange.location, effectiveRange: nil) as! NSFont
        let baseString: NSString = mutableString.substring(with: baseRange) as NSString
        baseFont = CTFont(font: baseFont, string: baseString, range: CFRange(location: 0, length: baseString.length), language: scriptVariant as CFString)
        let rubyString: NSString = mutableString.substring(with: match.range(at: 4)) as NSString
        rubyLineHeight = baseFont.lineHeight(asVertical: isVertical) * 0.5
        var rubyTexts: [Unmanaged<CFString>?] = [.passUnretained(rubyString), nil, nil, nil]
        let rubyAnnotation: CTRubyAnnotation = CTRubyAnnotationCreate(.distributeSpace, .none, 0.5, &rubyTexts)
        addAttributes([.font : baseFont, .verticalGlyphForm : isVertical ? 1 : 0], range: match.range)

        if #available(macOS 12.0, *) {
          deleteCharacters(in: match.range(at: 3))
        } else { // use U+008B as placeholder for line-forward spaces in case ruby is wider than base
          let baseSize: NSSize = attributedSubstring(from: baseRange).size()
          let rubyWidth: Double = attributedSubstring(from: match.range(at: 4)).size().width * 0.5
          deleteCharacters(in: match.range(at: 3))
          replaceCharacters(in: NSRange(location: baseRange.upperBound, length: 0), with: "\u{008B}")
          addAttribute(.controlCharacterSize, value: NSSize(width: fdim(rubyWidth.rounded(.up), baseSize.width.rounded(.down)), height: baseSize.height), range: NSRange(location: baseRange.upperBound, length: 1))
        }
        addAttribute(.rubyAnnotation, value: rubyAnnotation, range: baseRange)
        deleteCharacters(in: match.range(at: 1))
      }
    }
    mutableString.replaceOccurrences(of: "(.)?[\\x{FFF9}-\\x{FFFB}]", with: "$1", options: [.regularExpression], range: NSRange(location: 0, length: length))
    return rubyLineHeight.rounded(.up)
  }
}

extension NSAttributedString {
  func horizontalInVerticalForms() -> Self {
    var attrs: [NSAttributedString.Key : Any] = attributes(at: 0, effectiveRange: nil)
    let font: NSFont = attrs[.font] as! NSFont
    let attrString: Self = .init(string: string, attributes: fontAttributes(in: NSRange(location: 0, length: length)))
    let stringWidth: Double = attrString.size().width.rounded(.up)
    let height: Double = attrString.size().height.rounded(.up)
    let width: Double = max(height, stringWidth)
    let image: NSImage = .init(size: NSSize(width: height, height: height), flipped: true) { dstRect in
      NSGraphicsContext.saveGraphicsState()
      let transform: NSAffineTransform = .init()
      transform.scaleX(by: 1.0, yBy: height / width)
      transform.translateX(by: (height * 0.5).rounded(.up), yBy: (width * 0.5).rounded(.up))
      transform.rotate(byDegrees: -90)
      transform.concat()
      attrString.draw(with: NSRect(x: -(stringWidth * 0.5).rounded(.up), y: -(height * 0.5).rounded(.up), width: stringWidth, height: height), options: .usesLineFragmentOrigin)
      NSGraphicsContext.restoreGraphicsState()
      return true
    }
    let attm: NSTextAttachment = .init()
    attm.image = image
    attm.bounds = NSRect(x: 0, y: font.descender.rounded(.up), width: height, height: height)
    attrs[.attachment] = attm
    return .init(string: String(UnicodeScalar(NSTextAttachment.character)!), attributes: attrs)
  }

  static let textAttachmentBaseString: String = .init(UnicodeScalar(NSTextAttachment.character)!)
  convenience init(attachment: NSTextAttachment, attributes: [NSAttributedString.Key : Any]) {
    var attrs: [NSAttributedString.Key : Any] = attributes
    attrs[.attachment] = attachment
    self.init(string: Self.textAttachmentBaseString, attributes: attrs)
  }
}

extension NSColorSpace {
  static let labColorSpace: NSColorSpace = {
    let whitePoint: [CGFloat] = [0.950489, 1.0, 1.088840]
    let blackPoint: [CGFloat] = [0.0, 0.0, 0.0]
    let range: [CGFloat] = [-127.0, 127.0, -127.0, 127.0]
    let colorSpaceLab: CGColorSpace = .init(labWhitePoint: whitePoint, blackPoint: blackPoint, range: range)!
    return .init(cgColorSpace: colorSpaceLab)!
  }()
}

extension NSColor {
  convenience init(lStar: CGFloat, aStar: CGFloat, bStar: CGFloat, alpha: CGFloat) {
    let lum: CGFloat = lStar.clamp(min: 0.0, max: 100.0)
    let greenRed: CGFloat = aStar.clamp(min: -127.0, max: 127.0)
    let blueYellow: CGFloat = bStar.clamp(min: -127.0, max: 127.0)
    let opaque: CGFloat = alpha.clamp(min: 0.0, max: 1.0)
    let components: [CGFloat] = [lum, greenRed, blueYellow, opaque]
    self.init(colorSpace: .labColorSpace, components: components, count: 4)
  }

  private var LABComponents: [CGFloat?] {
    guard let componentBased: NSColor = usingType(.componentBased)?.usingColorSpace(.labColorSpace) else { return [nil, nil, nil, nil] }
    var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
    componentBased.getComponents(&components)
    components[0] /= 100.0 // Luminance
    components[1] /= 127.0 // Green-Red
    components[2] /= 127.0 // Blue-Yellow
    return components
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

  enum ColorInversionExtent: Int, Sendable {
    case standard = 0, augmented = 1, moderate = -1
  }

  func invertLuminance(toExtent extent: ColorInversionExtent) -> NSColor {
    guard let componentBased: NSColor = usingType(.componentBased), let labColor: NSColor = componentBased.usingColorSpace(.labColorSpace) else { return self }
    var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
    labColor.getComponents(&components)
    components[0] = switch extent {
    case .augmented: 100.0 - components[0]
    case .moderate: 80.0 - components[0] * 0.6
    case .standard: 90.0 - components[0] * 0.8
    }
    let invertedColor: NSColor = .init(colorSpace: .labColorSpace, components: components, count: 4)
    return invertedColor.usingColorSpace(componentBased.colorSpace)!
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

  static private let kBlendedBackgroundColorFraction: Double = 0.2
  func blend(background: NSColor?) -> NSColor {
    return blended(withFraction: Self.kBlendedBackgroundColorFraction, of: background ?? .lightGray)?.withAlphaComponent(alphaComponent) ?? self
  }

  func blendWithColor(_ color: NSColor, ofFraction fraction: CGFloat) -> NSColor? {
    let alpha: CGFloat = alphaComponent * color.alphaComponent
    let opaqueColor: NSColor = withAlphaComponent(1.0).blended(withFraction: fraction, of: color.withAlphaComponent(1.0))!
    return opaqueColor.withAlphaComponent(alpha)
  }
}

// MARK: Theme - color scheme and other user configurations

enum SquirrelStyle: Int, Sendable {
  case light = 0, dark = 1
}

enum SquirrelStatusMessageType: Sendable {
  case mixed, short, long
}

extension NSFontDescriptor {
  static private let features: [[NSFontDescriptor.FeatureKey : Int]] = [[.typeIdentifier : kVerticalSubstitutionType, .selectorIdentifier : kSubstituteVerticalFormsOnSelector], [.typeIdentifier : kCJKVerticalRomanPlacementType, .selectorIdentifier : kCJKVerticalRomanCenteredSelector], [.typeIdentifier : kRubyKanaType, .selectorIdentifier : kRubyKanaOffSelector]]
  class func create(fullname: String?) -> NSFontDescriptor? {
    guard let fullname = fullname, !fullname.isEmpty else { return nil }
    let fontNames: [String] = fullname.components(separatedBy: ",")
    let validFontDescriptors: [NSFontDescriptor] = fontNames.compactMap { name in
      guard let font: NSFont = .init(name: name.trimmingCharacters(in: .whitespaces), size: 0.0) else { return nil }
      let fontDescriptor: NSFontDescriptor = font.fontDescriptor.addingAttributes([.featureSettings : features])
      let UIFontDescriptor: NSFontDescriptor = fontDescriptor.withSymbolicTraits([.UIOptimized])
      return NSFont(descriptor: UIFontDescriptor, size: 0.0) == nil ? fontDescriptor : UIFontDescriptor
    }
    guard let fontDescriptor: NSFontDescriptor = validFontDescriptors.first else { return nil }
    let fallbackDescriptors: [NSFontDescriptor] = validFontDescriptors.dropFirst() + [NSFontDescriptor(name: "AppleColorEmoji", size: 0.0).addingAttributes([.featureSettings : features])]
    return fontDescriptor.addingAttributes([.cascadeList : fallbackDescriptors])
  }
}

extension NSFont {
  func lineHeight(asVertical: Bool) -> Double {
    var lineHeight: Double = (asVertical ? vertical.ascender - vertical.descender : ascender - descender).rounded(.up)
    guard let fallbackList: [NSFontDescriptor] = fontDescriptor.fontAttributes[.cascadeList] as? [NSFontDescriptor] else { return lineHeight }
    for fallback in fallbackList {
      guard let fallbackFont: NSFont = .init(descriptor: fallback, size: pointSize) else { continue }
      let fallbackHeight: Double = asVertical ? fallbackFont.vertical.ascender - fallbackFont.vertical.descender : fallbackFont.ascender - fallbackFont.descender
      lineHeight = max(lineHeight, fallbackHeight.rounded(.up))
    }
    return lineHeight
  }
}

private func updateCandidateListLayout(isLinear: inout Bool, isTabular: inout Bool, config: SquirrelConfig, prefix: String) {
  if let candidateListLayout: String = config.stringValue(for: "\(prefix)/candidate_list_layout") {
    switch candidateListLayout {
    case "stacked": (isLinear, isTabular) = (false, false)
    case "linear": (isLinear, isTabular) = (true, false)
    // `isTabular` is a derived layout of `isLinear`; isTabular implies isLinear
    case "tabular": (isLinear, isTabular) = (true, true)
    default: break
    }
  } else if let horizontal: Bool = config.boolValue(for: "\(prefix)/horizontal") {
    // Deprecated. Not to be confused with text_orientation: horizontal
    (isLinear, isTabular) = (horizontal, false)
  }
}

private func updateTextOrientation(isVertical: inout Bool, config: SquirrelConfig, prefix: String) {
  if let textOrientation: String = config.stringValue(for: "\(prefix)/text_orientation") {
    switch textOrientation {
    case "horizontal": isVertical = false
    case "vertical": isVertical = true
    default: break
    }
  } else if let vertical: Bool = config.boolValue(for: "\(prefix)/vertical") {
    isVertical = vertical
  }
}

// functions for post-retrieve processing
@inlinable func positive(param: Double) -> Double { param < .zero ? .zero : param }
@inlinable func positiveRound(param: Double) -> Double { param < .zero ? .zero : param.rounded() }
@inlinable func positiveCeil(param: Double) -> Double { param < .zero ? .zero : param.rounded(.up) }
@inlinable func clampUniform(param: Double) -> Double { param < .zero ? .zero : param > 1.0 ? 1.0 : param }

final class SquirrelTheme: NSObject {
  static private let defaultFontSize: Double = 24
  static private let defaultCandidateFormat: String = "%c. %@ %s"

  @MainActor static let light: SquirrelTheme = .init(style: .light)
  @available(macOS 10.14, *) @MainActor static let dark: SquirrelTheme = .init(style: .dark)
  @MainActor static var currentStyle: SquirrelStyle = .light
  class var current: SquirrelTheme { @MainActor get { if #available(macOS 10.14, *), currentStyle == .dark { dark } else { light } } }

  private(set) var backColor: NSColor = .controlBackgroundColor
  private(set) var preeditForeColor: NSColor = .textColor
  private(set) var textForeColor: NSColor = .controlTextColor
  private(set) var commentForeColor: NSColor = .secondaryLabelColor
  private(set) var labelForeColor: NSColor = .secondaryLabelColor
  private(set) var hilitedPreeditForeColor: NSColor = .selectedTextColor
  private(set) var hilitedTextForeColor: NSColor = .selectedMenuItemTextColor
  private(set) var hilitedCommentForeColor: NSColor = .alternateSelectedControlTextColor
  private(set) var hilitedLabelForeColor: NSColor = .alternateSelectedControlTextColor
  private(set) var dimmedLabelForeColor: NSColor? = nil
  private(set) var hilitedCandidateBackColor: NSColor? = nil
  private(set) var hilitedPreeditBackColor: NSColor? = nil
  private(set) var candidateBackColor: NSColor? = nil
  private(set) var preeditBackColor: NSColor? = nil
  private(set) var borderColor: NSColor? = nil
  private(set) var backImage: NSImage? = nil

  private(set) var borderInsets: NSSize = .zero
  private(set) var cornerRadius: Double = .zero
  private(set) var hilitedCornerRadius: Double = .zero
  private(set) lazy var fullWidth: Double = NSString(string: .fullWidthSpace).size(withAttributes: commentAttrs.filter({$0.key == .font})).width.rounded(.up)
  private(set) var lineSpacing: Double = .zero
  private(set) var preeditSpacing: Double = .zero
  private(set) var opacity: Double = 1
  private(set) var lineLength: Double = .zero
  private(set) var shadowSize: Double = .zero
  private(set) var translucency: Float = .zero

  private(set) var stackColors: Bool = false
  private(set) var showPaging: Bool = false
  private(set) var rememberSize: Bool = false
  private(set) var isTabular: Bool = false
  private(set) var isLinear: Bool = false
  private(set) var isVertical: Bool = false
  private(set) var inlinePreedit: Bool = false
  private(set) var inlineCandidate: Bool = true

  private(set) var textAttrs: [NSAttributedString.Key : Any] = [:]
  private(set) var labelAttrs: [NSAttributedString.Key : Any] = [:]
  private(set) var commentAttrs: [NSAttributedString.Key : Any] = [:]
  private(set) var preeditAttrs: [NSAttributedString.Key : Any] = [:]
  private(set) var pagingAttrs: [NSAttributedString.Key : Any] = [:]
  private(set) var statusAttrs: [NSAttributedString.Key : Any] = [:]

  private(set) var candidateParagraphStyle: NSParagraphStyle
  private(set) var preeditParagraphStyle: NSParagraphStyle
  private(set) var statusParagraphStyle: NSParagraphStyle
  private(set) var pagingParagraphStyle: NSParagraphStyle
  private(set) var truncatedParagraphStyle: NSParagraphStyle? = nil

  private(set) lazy var separator: NSAttributedString = .init(string: "\n", attributes: commentAttrs)
  private(set) var symbolDeleteFill: NSAttributedString? = nil
  private(set) var symbolDeleteStroke: NSAttributedString? = nil
  private(set) var symbolBackFill: NSAttributedString? = nil
  private(set) var symbolBackStroke: NSAttributedString? = nil
  private(set) var symbolForwardFill: NSAttributedString? = nil
  private(set) var symbolForwardStroke: NSAttributedString? = nil
  private(set) var symbolCompress: NSAttributedString? = nil
  private(set) var symbolExpand: NSAttributedString? = nil
  private(set) var symbolLock: NSAttributedString? = nil

  private(set) var rawLabels: [String] = ["１", "２", "３", "４", "５"]
  private(set) var labels: [String] = []
  private(set) var candidateTemplate: NSAttributedString = .init(string: defaultCandidateFormat)
  private(set) var candidateHilitedTemplate: NSAttributedString = .init(string: defaultCandidateFormat)
  private(set) var candidateDimmedTemplate: NSAttributedString?
  private(set) var selectKeys: String = "12345"
  private(set) var rawCandidateFormat: String = defaultCandidateFormat
  private(set) var candidateFormat: String = ""
  private(set) var scriptVariant: String = "zh"
  private(set) var statusMessageType: SquirrelStatusMessageType = .mixed
  private(set) var pageSize: Int = 5
  private(set) var style: SquirrelStyle

  init(style: SquirrelStyle = .light) {
    self.style = style

    let candidateParagraphStyle: NSMutableParagraphStyle = .init()
    candidateParagraphStyle.alignment = .left
    // Use left-to-right marks to declare the default writing direction and prevent strong right-to-left
    // characters from setting the writing direction in case the label are direction-less symbols
    candidateParagraphStyle.baseWritingDirection = .leftToRight
    let preeditParagraphStyle: NSMutableParagraphStyle = candidateParagraphStyle.mutableCopy()
    let pagingParagraphStyle: NSMutableParagraphStyle = candidateParagraphStyle.mutableCopy()
    let statusParagraphStyle: NSMutableParagraphStyle = candidateParagraphStyle.mutableCopy()
    preeditParagraphStyle.lineBreakMode = .byWordWrapping
    statusParagraphStyle.lineBreakMode = .byTruncatingTail
    self.candidateParagraphStyle = candidateParagraphStyle.copy()
    self.preeditParagraphStyle = preeditParagraphStyle.copy()
    self.pagingParagraphStyle = pagingParagraphStyle.copy()
    self.statusParagraphStyle = statusParagraphStyle.copy()

    let userFont: NSFont = .init(descriptor: .create(fullname: NSFont.userFont(ofSize: Self.defaultFontSize)!.fontName)!, size: Self.defaultFontSize)!
    let userMonoFont: NSFont = .init(descriptor: .create(fullname: NSFont.userFixedPitchFont(ofSize: Self.defaultFontSize)!.fontName)!, size: Self.defaultFontSize)!
    let monoDigitFont: NSFont = .monospacedDigitSystemFont(ofSize: Self.defaultFontSize, weight: .regular)

    textAttrs[.foregroundColor] = NSColor.controlTextColor
    textAttrs[.font] = userFont
    textAttrs[.kern] = 0
    // Use left-to-right embedding to prevent right-to-left text from changing the layout of the candidate.
    textAttrs[.writingDirection] = [0]
    labelAttrs[.foregroundColor] = NSColor.labelColor
    labelAttrs[.font] = userMonoFont
    labelAttrs[.kern] = 0
    commentAttrs[.foregroundColor] = NSColor.secondaryLabelColor
    commentAttrs[.font] = userFont
    commentAttrs[.kern] = 0
    preeditAttrs[.foregroundColor] = NSColor.textColor
    preeditAttrs[.font] = userFont
    preeditAttrs[.ligature] = 0
    preeditAttrs[.paragraphStyle] = preeditParagraphStyle
    pagingAttrs[.font] = monoDigitFont
    pagingAttrs[.foregroundColor] = NSColor.controlTextColor
    pagingAttrs[.paragraphStyle] = pagingParagraphStyle
    statusAttrs = commentAttrs
    statusAttrs[.paragraphStyle] = statusParagraphStyle

    super.init()
    updateCandidateTemplates()
    updateSeperatorAndSymbolAttrs()
  }

  private func updateSeperatorAndSymbolAttrs() {
    var sepAttrs: [NSAttributedString.Key : Any] = commentAttrs
    sepAttrs[.verticalGlyphForm] = 0
    sepAttrs[.kern] = 0
    separator = NSAttributedString(string: isLinear ? (isTabular ? "\u{3000}\t\u{001D}" : "\u{3000}\u{001D}") : "\n", attributes: sepAttrs)

    var attrs: [NSAttributedString.Key : Any] = preeditAttrs
    attrs[.verticalGlyphForm] = 0
    let attmDeleteFill: NSTextAttachment = .init()
    attmDeleteFill.image = NSImage(named: "Symbols/delete.backward.fill")
    symbolDeleteFill = NSAttributedString(attachment: attmDeleteFill, attributes: attrs)
    let attmDeleteStroke: NSTextAttachment = .init()
    attmDeleteStroke.image = NSImage(named: "Symbols/delete.backward")
    symbolDeleteStroke = NSAttributedString(attachment: attmDeleteStroke, attributes: attrs)

    if isTabular {
      let attmCompress: NSTextAttachment = .init()
      attmCompress.image = NSImage(named: "Symbols/rectangle.compress.vertical")
      symbolCompress = NSAttributedString(attachment: attmCompress, attributes: pagingAttrs)
      let attmExpand: NSTextAttachment = .init()
      attmExpand.image = NSImage(named: "Symbols/rectangle.expand.vertical")
      symbolExpand = NSAttributedString(attachment: attmExpand, attributes: pagingAttrs)
      let attmLock: NSTextAttachment = .init()
      attmLock.image = NSImage(named: "Symbols/lock\(isVertical ? ".vertical" : "").fill")
      symbolLock = NSAttributedString(attachment: attmLock, attributes: pagingAttrs)
    } else {
      symbolCompress = nil
      symbolExpand = nil
      symbolLock = nil
    }

    if showPaging {
      let attmBackFill: NSTextAttachment = .init()
      attmBackFill.image = NSImage(named: "Symbols/chevron.\(isLinear ? "up" : "left").circle.fill")
      symbolBackFill = NSAttributedString(attachment: attmBackFill, attributes: pagingAttrs)
      let attmBackStroke: NSTextAttachment = .init()
      attmBackStroke.image = NSImage(named: "Symbols/chevron.\(isLinear ? "up" : "left").circle")
      symbolBackStroke = NSAttributedString(attachment: attmBackStroke, attributes: pagingAttrs)
      let attmForwardFill: NSTextAttachment = .init()
      attmForwardFill.image = NSImage(named: "Symbols/chevron.\(isLinear ? "down" : "right").circle.fill")
      symbolForwardFill = NSAttributedString(attachment: attmForwardFill, attributes: pagingAttrs)
      let attmForwardStroke: NSTextAttachment = .init()
      attmForwardStroke.image = NSImage(named: "Symbols/chevron.\(isLinear ? "down" : "right").circle")
      symbolForwardStroke = NSAttributedString(attachment: attmForwardStroke, attributes: pagingAttrs)
    } else {
      symbolBackFill = nil
      symbolBackStroke = nil
      symbolForwardFill = nil
      symbolForwardStroke = nil
    }
  }

  func updateLabels(withConfig config: SquirrelConfig, directUpdate: Bool) {
    let menuSize: Int = config.intValue(for: "menu/page_size") ?? 5
    let selectKeys: String =  String((config.stringValue(for: "menu/alternative_select_keys") ?? "1234567890").prefix(menuSize))
    let selectLabels: [String]? = config.listValue(for: "menu/alternative_select_labels")
    let rawLabels: [String] = selectLabels == nil ? selectKeys.map { $0.uppercased().applyingTransform(.fullwidthToHalfwidth, reverse: true)! } : Array(selectLabels!.prefix(menuSize))
    updateSelectKeys(selectKeys, labels: rawLabels, directUpdate: directUpdate)
  }

  private func updateSelectKeys(_ selectKeys: String, labels rawLabels: [String], directUpdate: Bool) {
    guard self.selectKeys != selectKeys, self.rawLabels != rawLabels else { return }
    self.selectKeys = selectKeys
    self.rawLabels = rawLabels
    pageSize = rawLabels.count
    labels = []
    if directUpdate { updateCandidateTemplates() }
  }

  private func updateCandidateFormat(_ rawCandidateFormat: String) {
    if self.rawCandidateFormat != rawCandidateFormat {
      self.rawCandidateFormat = rawCandidateFormat
      candidateFormat = ""
    }
    updateCandidateTemplates()
  }

  private func updateCandidateTemplates() {
    if candidateFormat.isEmpty || labels.isEmpty {
      candidateFormat = rawCandidateFormat
      // validate candidate format: must have enumerator '%c' before candidate '%@'
      var textRange: Range<String.Index>? = candidateFormat.range(of: "%@", options: [.literal])
      if textRange == nil {
        candidateFormat.append("%@")
      }
      var labelRange: Range<String.Index>? = candidateFormat.range(of: "%c", options: [.literal])
      if labelRange == nil {
        candidateFormat.insert(contentsOf: "%c", at: candidateFormat.startIndex)
        labelRange = candidateFormat.range(of: "%c", options: [.literal])
      }
      textRange = candidateFormat.range(of: "%@", options: [.literal])
      if labelRange!.lowerBound > textRange!.lowerBound {
        candidateFormat = Self.defaultCandidateFormat
      }
      textRange = candidateFormat.range(of: "(\\x{FFF9})?%@", options: [.regularExpression])
      let commentRange: Range<String.Index> = textRange!.upperBound ..< candidateFormat.endIndex
      if commentRange.isEmpty || !candidateFormat[commentRange].contains("%s") {
        candidateFormat.insert(contentsOf: "%s", at: textRange!.upperBound)
      }
      if !isLinear {
        candidateFormat.insert("\t", at: textRange!.lowerBound)
      }

      labels = rawLabels
      let labelCharacters: CharacterSet = .init(charactersIn: rawLabels.joined())
      if CharacterSet.fullWidthDigits.isSuperset(of: labelCharacters) { // ０１...９
        if let range: Range<String.Index> = candidateFormat.range(of: "%c\u{20E3}", options: [.literal]) { // 1︎⃣...9︎⃣0︎⃣
          candidateFormat.replaceSubrange(range, with: "%c")
          labels = rawLabels.map { String(UnicodeScalar($0.unicodeScalars.first!.value - 0xFF10 + 0x0030)!) + "\u{FE0E}\u{20E3}" }
        } else if let range: Range<String.Index> = candidateFormat.range(of: "%c\u{20DD}", options: [.literal]) { // ①...⑨⓪
          candidateFormat.replaceSubrange(range, with: "%c")
          labels = rawLabels.map { String(UnicodeScalar($0.unicodeScalars.first!.value == 0xFF10 ? 0x24EA : $0.unicodeScalars.first!.value - 0xFF11 + 0x2460)!) }
        } else if let range: Range<String.Index> = candidateFormat.range(of: "(%c)", options: [.literal]) { // ⑴...⑼⑽
          candidateFormat.replaceSubrange(range, with: "%c")
          labels = rawLabels.map { String(UnicodeScalar($0.unicodeScalars.first!.value == 0xFF10 ? 0x247D : $0.unicodeScalars.first!.value - 0xFF11 + 0x2474)!) }
        } else if let range: Range<String.Index> = candidateFormat.range(of: "%c.", options: [.literal]) { // ⒈...⒐🄀
          candidateFormat.replaceSubrange(range, with: "%c")
          labels = rawLabels.map { String(UnicodeScalar($0.unicodeScalars.first!.value == 0xFF10 ? 0x1F100 : $0.unicodeScalars.first!.value - 0xFF11 + 0x2488)!) }
        } else if let range: Range<String.Index> = candidateFormat.range(of: "%c,", options: [.literal]) { // 🄂...🄊🄁
          candidateFormat.replaceSubrange(range, with: "%c")
          labels = rawLabels.map { String(UnicodeScalar($0.unicodeScalars.first!.value - 0xFF10 + 0x1F101)!) }
        }
      } else if CharacterSet.fullWidthLatinCapitals.isSuperset(of: labelCharacters) {
        if let range: Range<String.Index> = candidateFormat.range(of: "%c\u{20DD}", options: [.literal]) { // Ⓐ...Ⓩ
          candidateFormat.replaceSubrange(range, with: "%c")
          labels = rawLabels.map { String(UnicodeScalar($0.unicodeScalars.first!.value - 0xFF21 + 0x24B6)!) }
        } else if let range: Range<String.Index> = candidateFormat.range(of: "(%c)", options: [.literal]) { // 🄐...🄩
          candidateFormat.replaceSubrange(range, with: "%c")
          labels = rawLabels.map { String(UnicodeScalar($0.unicodeScalars.first!.value - 0xFF21 + 0x1F110)!) }
        } else if let range: Range<String.Index> = candidateFormat.range(of: "%c\u{20DE}", options: [.literal]) { // 🄰...🅉
          candidateFormat.replaceSubrange(range, with: "%c")
          labels = rawLabels.map { String(UnicodeScalar($0.unicodeScalars.first!.value - 0xFF21 + 0x1F130)!) }
        }
      }
    }

    // make sure label font can render all possible enumerators
    let labelFont: NSFont = labelAttrs[.font] as! NSFont
    let labelString: CFString = labels.joined() as CFString
    let substituteFont: NSFont = CTFont(font: labelFont, string: labelString, range: CFRange(location: 0, length: labelString.length))
    if substituteFont.isNotEqual(to: labelFont) {
      labelAttrs[.font] = CTFont(font: substituteFont, string: labelString, range: CFRange(location: 0, length: labelString.length))
    }

    // parse markdown formats
    let candidateTemplate: NSMutableAttributedString = .init(string: candidateFormat)
    var textRange: NSRange = candidateTemplate.mutableString.range(of: "(\\x{FFF9})?%@", options: [.regularExpression])
    var labelRange: NSRange = .init(location: 0, length: textRange.location)
    var commentRange: NSRange = .init(location: textRange.upperBound, length: candidateTemplate.length - textRange.upperBound)
    candidateTemplate.setAttributes(labelAttrs, range: labelRange)
    candidateTemplate.setAttributes(textAttrs, range: textRange)
    candidateTemplate.setAttributes(commentAttrs, range: commentRange)
    candidateTemplate.formatMarkDown()
    textRange = candidateTemplate.mutableString.range(of: "(\\x{FFF9})?%@", options: [.regularExpression])
    labelRange = NSRange(location: 0, length: textRange.location)
    commentRange = NSRange(location: textRange.upperBound, length: candidateTemplate.length - textRange.upperBound)

    // for stacked layout, calculate head indent
    let candidateParagraphStyle: NSMutableParagraphStyle = self.candidateParagraphStyle.mutableCopy()
    if !isLinear {
      let enumRange: NSRange = candidateTemplate.mutableString.range(of: "%c", options: [.literal])
      let textStorage: NSTextStorage = .init()
      let textContainer: SquirrelTextContainer = .init(contentBlock: .stackedCandidate, textStorage: textStorage)
      textContainer.layoutOrientation = isVertical ? .vertical : .horizontal
      for label in labels {
        let labelString: NSMutableAttributedString = candidateTemplate.attributedSubstring(from: NSRange(location: 0, length: labelRange.length - 1)).mutableCopy()
        labelString.replaceCharacters(in: enumRange, with: label)
        textStorage.append(labelString)
        textStorage.append(NSAttributedString(string: "\n"))
      }
      let indent: Double = textContainer.layoutText().maxX.rounded(.down) + 1.0
      candidateParagraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
      candidateParagraphStyle.headIndent = indent
      self.candidateParagraphStyle = candidateParagraphStyle.copy()
      truncatedParagraphStyle = nil
    } else {
      candidateParagraphStyle.tabStops = []
      candidateParagraphStyle.headIndent = .zero
      self.candidateParagraphStyle = candidateParagraphStyle.copy()
      let truncatedParagraphStyle: NSMutableParagraphStyle = candidateParagraphStyle.mutableCopy()
      truncatedParagraphStyle.lineBreakMode = .byTruncatingMiddle
      truncatedParagraphStyle.tighteningFactorForTruncation = .zero
      self.truncatedParagraphStyle = truncatedParagraphStyle.copy()
    }

    textAttrs[.paragraphStyle] = candidateParagraphStyle
    commentAttrs[.paragraphStyle] = candidateParagraphStyle
    labelAttrs[.paragraphStyle] = candidateParagraphStyle
    candidateTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSRange(location: 0, length: candidateTemplate.length))
    self.candidateTemplate = candidateTemplate.copy()

    let candidateHilitedTemplate: NSMutableAttributedString = candidateTemplate.mutableCopy()
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedLabelForeColor, range: labelRange)
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedTextForeColor, range: textRange)
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedCommentForeColor, range: commentRange)
    self.candidateHilitedTemplate = candidateHilitedTemplate.copy()

    if isTabular {
      let candidateDimmedTemplate: NSMutableAttributedString = candidateTemplate.mutableCopy()
      candidateDimmedTemplate.addAttribute(.foregroundColor, value: dimmedLabelForeColor!, range: labelRange)
      self.candidateDimmedTemplate = candidateDimmedTemplate.copy()
    } else {
      candidateDimmedTemplate = nil
    }
  }

  private func updateStatusMessageType(_ type: String?) {
    statusMessageType = switch type {
    case "long": .long
    case "short": .short
    default: .mixed
    }
  }

  static private let monoDigitFeatures: [[NSFontDescriptor.FeatureKey : Int]] = [[.typeIdentifier : kNumberSpacingType, .selectorIdentifier : kMonospacedNumbersSelector], [.typeIdentifier : kTextSpacingType, .selectorIdentifier : kHalfWidthTextSelector], [.typeIdentifier : kCJKRomanSpacingType, .selectorIdentifier : kHalfWidthCJKRomanSelector]]

  func updateTheme(withConfig config: SquirrelConfig, styleOptions: Set<String>, scriptVariant: String) {
    /* INTERFACE */
    var isLinear: Bool = false
    var isTabular: Bool = false
    var isVertical: Bool = false
    updateCandidateListLayout(isLinear: &isLinear, isTabular: &isTabular, config: config, prefix: "style")
    updateTextOrientation(isVertical: &isVertical, config: config, prefix: "style")
    var inlinePreedit: Bool? = config.boolValue(for: "style/inline_preedit")
    var inlineCandidate: Bool? = config.boolValue(for: "style/inline_candidate")
    var showPaging: Bool? = config.boolValue(for: "style/show_paging")
    var rememberSize: Bool? = config.boolValue(for: "style/remember_size", alias: "memorize_size")
    var statusMessageType: String? = config.stringValue(for: "style/status_message_type")
    var rawCandidateFormat: String? = config.stringValue(for: "style/candidate_format")
    /* TYPOGRAPHY */
    var fontName: String? = config.stringValue(for: "style/font_face")
    var fontSize: Double? = config.doubleValue(for: "style/font_point", constraint: positiveRound)
    var labelFontName: String? = config.stringValue(for: "style/label_font_face")
    var labelFontSize: Double? = config.doubleValue(for: "style/label_font_point", constraint: positiveRound)
    var commentFontName: String? = config.stringValue(for: "style/comment_font_face")
    var commentFontSize: Double? = config.doubleValue(for: "style/comment_font_point", constraint: positiveRound)
    var opacity: Double? = config.doubleValue(for: "style/opacity", alias: "alpha", constraint: clampUniform)
    var translucency: Double? = config.doubleValue(for: "style/translucency", constraint: clampUniform)
    var stackColors: Bool? = config.boolValue(for: "style/stack_colors", alias: "mutual_exclusive")
    var cornerRadius: Double? = config.doubleValue(for: "style/corner_radius", constraint: positive)
    var hilitedCornerRadius: Double? = config.doubleValue(for: "style/hilited_corner_radius", constraint: positive)
    var borderHeight: Double? = config.doubleValue(for: "style/border_height", constraint: positiveCeil)
    var borderWidth: Double? = config.doubleValue(for: "style/border_width", constraint: positiveCeil)
    var lineSpacing: Double? = config.doubleValue(for: "style/line_spacing", constraint: positiveRound)
    var preeditSpacing: Double? = config.doubleValue(for: "style/spacing", constraint: positiveRound)
    var baseOffset: Double? = config.doubleValue(for: "style/base_offset")
    var lineLength: Double? = config.doubleValue(for: "style/line_length")
    var shadowSize: Double? = config.doubleValue(for: "style/shadow_size", constraint: positive)
    /* CHROMATICS */
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
      colorScheme = styleOptions.lazy.compactMap({ config.stringValue(for: "style/\($0)/color_scheme_dark") }).first ?? config.stringValue(for: "style/color_scheme_dark")
    }
    colorScheme ?= styleOptions.lazy.compactMap({ config.stringValue(for: "style/\($0)/color_scheme") }).first ?? config.stringValue(for: "style/color_scheme")
    let isNative: Bool = (colorScheme == nil) || (colorScheme! == "native")
    var configPrefixes: [String] = styleOptions.map { "style/" + $0 }
    if !isNative { configPrefixes.insert("preset_color_schemes/" + colorScheme!, at: 0) }

    // get color scheme and then check possible overrides from styleSwitcher
    for prefix in configPrefixes {
      /* CHROMATICS override */
      config.colorSpace =? config.stringValue(for: prefix + "/color_space")
      backColor =? config.colorValue(for: prefix + "/back_color")
      borderColor =? config.colorValue(for: prefix + "/border_color")
      preeditBackColor =? config.colorValue(for: prefix + "/preedit_back_color")
      preeditForeColor =? config.colorValue(for: prefix + "/text_color")
      candidateBackColor =? config.colorValue(for: prefix + "/candidate_back_color")
      textForeColor =? config.colorValue(for: prefix + "/candidate_text_color")
      commentForeColor =? config.colorValue(for: prefix + "/comment_text_color")
      labelForeColor =? config.colorValue(for: prefix + "/label_color")
      hilitedPreeditBackColor =? config.colorValue(for: prefix + "/hilited_back_color")
      hilitedPreeditForeColor =? config.colorValue(for: prefix + "/hilited_text_color")
      hilitedCandidateBackColor =? config.colorValue(for: prefix + "/hilited_candidate_back_color")
      hilitedTextForeColor =? config.colorValue(for: prefix + "/hilited_candidate_text_color")
      hilitedCommentForeColor =? config.colorValue(for: prefix + "/hilited_comment_text_color")
      // for backward compatibility, `labelHilited_color` and `hilited_candidateLabel_color` are both valid
      hilitedLabelForeColor =? config.colorValue(for: prefix + "/label_hilited_color", alias: "hilited_candidate_label_color")
      backImage =? config.imageValue(for: prefix + "/back_image")

      // the following per-color-scheme configurations, if exist, will override
      // configurations with the same name under the global 'style' section
      /* INTERFACE override */
      updateCandidateListLayout(isLinear: &isLinear, isTabular: &isTabular, config: config, prefix: prefix)
      updateTextOrientation(isVertical: &isVertical, config: config, prefix: prefix)
      inlinePreedit =? config.boolValue(for: prefix + "/inline_preedit")
      inlineCandidate =? config.boolValue(for: prefix + "/inline_candidate")
      showPaging =? config.boolValue(for: prefix + "/show_paging")
      rememberSize =? config.boolValue(for: prefix + "/remember_size", alias: "memorize_size")
      statusMessageType =? config.stringValue(for: prefix + "/status_message_type")
      rawCandidateFormat =? config.stringValue(for: prefix + "/candidate_format")
      /* TYPOGRAPHY override */
      fontName =? config.stringValue(for: prefix + "/font_face")
      fontSize =? config.doubleValue(for: prefix + "/font_point", constraint: positiveRound)
      labelFontName =? config.stringValue(for: prefix + "/label_font_face")
      labelFontSize =? config.doubleValue(for: prefix + "/label_font_point", constraint: positiveRound)
      commentFontName =? config.stringValue(for: prefix + "/comment_font_face")
      commentFontSize =? config.doubleValue(for: prefix + "/comment_font_point", constraint: positiveRound)
      opacity =? config.doubleValue(for: prefix + "/opacity", alias: "alpha", constraint: clampUniform)
      translucency =? config.doubleValue(for: prefix + "/translucency", constraint: clampUniform)
      stackColors =? config.boolValue(for: prefix + "/stack_colors", alias: "mutual_exclusive")
      cornerRadius =? config.doubleValue(for: prefix + "/corner_radius", constraint: positive)
      hilitedCornerRadius =? config.doubleValue(for: prefix + "/hilited_corner_radius", constraint: positive)
      borderHeight =? config.doubleValue(for: prefix + "/border_height", constraint: positiveCeil)
      borderWidth =? config.doubleValue(for: prefix + "/border_width", constraint: positiveCeil)
      lineSpacing =? config.doubleValue(for: prefix + "/line_spacing", constraint: positiveRound)
      preeditSpacing =? config.doubleValue(for: prefix + "/spacing", constraint: positiveRound)
      baseOffset =? config.doubleValue(for: prefix + "/base_offset")
      lineLength =? config.doubleValue(for: prefix + "/line_length")
      shadowSize =? config.doubleValue(for: prefix + "/shadow_size", constraint: positive)
    }

    /* FORMAT reset */
    rawCandidateFormat ?= Self.defaultCandidateFormat
    if self.isLinear != isLinear {
      candidateFormat = ""  // reset format after switching between linear and stacked
    }

    /* TYPOGRAPHY refinement */
    fontSize ?= Self.defaultFontSize
    labelFontSize ?= fontSize
    commentFontSize ?= fontSize
    let fontDescriptor: NSFontDescriptor = .create(fullname: fontName) ?? .create(fullname: NSFont.userFont(ofSize: .zero)?.fontName)!
    let font: NSFont = .init(descriptor: fontDescriptor, size: fontSize!)!
    let labelFont: NSFont = .init(descriptor: (.create(fullname: labelFontName) ?? fontDescriptor).addingAttributes([.featureSettings : Self.monoDigitFeatures]), size: labelFontSize!)!
    let commentFont: NSFont = .init(descriptor: .create(fullname: commentFontName) ?? fontDescriptor, size: commentFontSize!)!
    let systemFont: NSFont = .systemFont(ofSize: labelFontSize!)
    let pagingFont: NSFont = .init(descriptor: labelFont.fontDescriptor.addingAttributes([.cascadeList : [systemFont.fontDescriptor]]), size: labelFontSize!)!

    let fontHeight: Double = font.lineHeight(asVertical: isVertical)
    let labelFontHeight: Double = labelFont.lineHeight(asVertical: isVertical)
    let commentFontHeight: Double = commentFont.lineHeight(asVertical: isVertical)
    let pagingFontHeight: Double = pagingFont.lineHeight(asVertical: false)
    let lineHeight: Double = max(fontHeight, labelFontHeight, commentFontHeight)
    let fullWidth: Double = NSString(string: .fullWidthSpace).size(withAttributes: [.font : commentFont]).width.rounded(.up)
    preeditSpacing ?= .zero
    lineSpacing ?= .zero

    let candidateParagraphStyle: NSMutableParagraphStyle = self.candidateParagraphStyle.mutableCopy()
    candidateParagraphStyle.minimumLineHeight = lineHeight
    candidateParagraphStyle.maximumLineHeight = lineHeight
    candidateParagraphStyle.paragraphSpacingBefore = isLinear ? .zero : (lineSpacing! * 0.5).rounded(.down)
    candidateParagraphStyle.paragraphSpacing = isLinear ? .zero : (lineSpacing! * 0.5).rounded(.up)
    candidateParagraphStyle.lineSpacing = isLinear ? lineSpacing! : .zero
    candidateParagraphStyle.tabStops = []
    candidateParagraphStyle.defaultTabInterval = fullWidth * 2
    self.candidateParagraphStyle = candidateParagraphStyle.copy()

    let preeditParagraphStyle: NSMutableParagraphStyle = self.preeditParagraphStyle.mutableCopy()
    preeditParagraphStyle.minimumLineHeight = fontHeight
    preeditParagraphStyle.maximumLineHeight = fontHeight
    preeditParagraphStyle.tabStops = []
    self.preeditParagraphStyle = preeditParagraphStyle.copy()

    let pagingParagraphStyle: NSMutableParagraphStyle = self.pagingParagraphStyle.mutableCopy()
    pagingParagraphStyle.minimumLineHeight = pagingFontHeight
    pagingParagraphStyle.maximumLineHeight = pagingFontHeight
    pagingParagraphStyle.tabStops = []
    self.pagingParagraphStyle = pagingParagraphStyle.copy()

    let statusParagraphStyle: NSMutableParagraphStyle = self.statusParagraphStyle.mutableCopy()
    statusParagraphStyle.minimumLineHeight = commentFontHeight
    statusParagraphStyle.maximumLineHeight = commentFontHeight
    self.statusParagraphStyle = statusParagraphStyle.copy()

    textAttrs[.font] = font
    labelAttrs[.font] = labelFont
    commentAttrs[.font] = commentFont
    preeditAttrs[.font] = font
    pagingAttrs[.font] = pagingFont
    statusAttrs[.font] = commentFont
    textAttrs[.kern] = isVertical ? 0.1 * fontSize! : .zero
    labelAttrs[.kern] = isVertical ? 0.1 * labelFontSize! : .zero
    commentAttrs[.kern] = isVertical ? 0.1 * commentFontSize! : .zero

    var zhFont: NSFont = CTFont(.system, size: fontSize!, language: scriptVariant as CFString)
    var zhCommentFont: NSFont = .init(descriptor: zhFont.fontDescriptor, size: commentFontSize!)!
    let maxFontSize: Double = max(fontSize!, commentFontSize!, labelFontSize!)
    var refFont: NSFont = .init(descriptor: zhFont.fontDescriptor, size: maxFontSize)!
    if isVertical {
      zhFont = zhFont.vertical
      zhCommentFont = zhCommentFont.vertical
      refFont = refFont.vertical
    }
    let baselineRefInfo: NSDictionary = [kCTBaselineReferenceFont : refFont, kCTBaselineClassIdeographicCentered : isVertical ? .zero : (refFont.ascender + refFont.descender) * 0.5, kCTBaselineClassRoman : isVertical ? -(refFont.ascender + refFont.descender) * 0.5 : .zero, kCTBaselineClassIdeographicLow : isVertical ? (refFont.descender - refFont.ascender) * 0.5 : refFont.descender]

    textAttrs[.baselineReferenceInfo] = baselineRefInfo
    labelAttrs[.baselineReferenceInfo] = baselineRefInfo
    commentAttrs[.baselineReferenceInfo] = baselineRefInfo
    preeditAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont : zhFont]
    pagingAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont : systemFont]
    statusAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont : zhCommentFont]

    textAttrs[.baselineClass] = isVertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    labelAttrs[.baselineClass] = kCTBaselineClassIdeographicCentered
    commentAttrs[.baselineClass] = isVertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    preeditAttrs[.baselineClass] = isVertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    statusAttrs[.baselineClass] = isVertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    pagingAttrs[.baselineClass] = kCTBaselineClassRoman

    textAttrs[.language] = scriptVariant
    labelAttrs[.language] = scriptVariant
    commentAttrs[.language] = scriptVariant
    preeditAttrs[.language] = scriptVariant
    statusAttrs[.language] = scriptVariant

    baseOffset ?= .zero
    textAttrs[.baselineOffset] = baseOffset
    labelAttrs[.baselineOffset] = baseOffset
    commentAttrs[.baselineOffset] = baseOffset
    preeditAttrs[.baselineOffset] = baseOffset
    pagingAttrs[.baselineOffset] = baseOffset
    statusAttrs[.baselineOffset] = baseOffset

    preeditAttrs[.paragraphStyle] = preeditParagraphStyle
    pagingAttrs[.paragraphStyle] = pagingParagraphStyle
    statusAttrs[.paragraphStyle] = statusParagraphStyle
    pagingAttrs[.verticalGlyphForm] = 0

    // CHROMATICS refinement
    translucency ?= .zero
    if #available(macOS 10.14, *), translucency!.isNormal, !isNative, backColor != nil, style == .dark ? backColor!.lStarComponent! > 0.6 : backColor!.lStarComponent! < 0.4 {
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
    self.dimmedLabelForeColor = isTabular ? self.labelForeColor.withAlphaComponent(self.labelForeColor.alphaComponent * 0.2) : nil

    textAttrs[.foregroundColor] = self.textForeColor
    commentAttrs[.foregroundColor] = self.commentForeColor
    labelAttrs[.foregroundColor] = self.labelForeColor
    preeditAttrs[.foregroundColor] = self.preeditForeColor
    pagingAttrs[.foregroundColor] = self.preeditForeColor
    statusAttrs[.foregroundColor] = self.commentForeColor

    self.borderInsets = isVertical ? NSSize(width: borderHeight ?? .zero, height: borderWidth ?? .zero) : NSSize(width: borderWidth ?? .zero, height: borderHeight ?? .zero)
    self.cornerRadius = min(cornerRadius ?? .zero, lineHeight * 0.5)
    self.hilitedCornerRadius = min(hilitedCornerRadius ?? .zero, lineHeight * 0.5)
    self.fullWidth = fullWidth
    self.lineSpacing = lineSpacing!
    self.preeditSpacing = preeditSpacing!
    self.opacity = opacity ?? 1.0
    self.lineLength = lineLength != nil && lineLength!.isNormal ? max(lineLength!.rounded(.up), fullWidth * 5) : .zero
    self.shadowSize = shadowSize ?? .zero
    self.translucency = Float(translucency ?? .zero)
    self.stackColors = stackColors ?? false
    self.showPaging = showPaging ?? false
    self.rememberSize = rememberSize ?? false
    self.isTabular = isTabular
    self.isLinear = isLinear
    self.isVertical = isVertical
    self.inlinePreedit = inlinePreedit ?? false
    self.inlineCandidate = inlineCandidate ?? false
    self.scriptVariant = scriptVariant

    updateStatusMessageType(statusMessageType)
    updateCandidateFormat(rawCandidateFormat!)
    updateSeperatorAndSymbolAttrs()
  }

  func updateAnnotationHeight(_ height: Double) {
    guard height.isNormal, lineSpacing < height * 2 else { return }
    lineSpacing = height * 2
    let candidateParagraphStyle: NSMutableParagraphStyle = self.candidateParagraphStyle.mutableCopy()
    if isLinear {
      candidateParagraphStyle.lineSpacing = height * 2
      let truncatedParagraphStyle: NSMutableParagraphStyle = candidateParagraphStyle.mutableCopy()
      truncatedParagraphStyle.lineBreakMode = .byTruncatingMiddle
      truncatedParagraphStyle.tighteningFactorForTruncation = .zero
      self.truncatedParagraphStyle = truncatedParagraphStyle.copy()
    } else {
      candidateParagraphStyle.paragraphSpacingBefore = height
      candidateParagraphStyle.paragraphSpacing = height
    }
    self.candidateParagraphStyle = candidateParagraphStyle.copy()

    textAttrs[.paragraphStyle] = candidateParagraphStyle
    commentAttrs[.paragraphStyle] = candidateParagraphStyle
    labelAttrs[.paragraphStyle] = candidateParagraphStyle

    let candidateTemplate: NSMutableAttributedString = self.candidateTemplate.mutableCopy()
    candidateTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSRange(location: 0, length: candidateTemplate.length))
    self.candidateTemplate = candidateTemplate.copy()
    let candidateHilitedTemplate: NSMutableAttributedString = self.candidateHilitedTemplate.mutableCopy()
    candidateHilitedTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSRange(location: 0, length: candidateHilitedTemplate.length))
    self.candidateHilitedTemplate = candidateHilitedTemplate.copy()
    if isTabular {
      let candidateDimmedTemplate: NSMutableAttributedString = self.candidateDimmedTemplate!.mutableCopy()
      candidateDimmedTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSRange(location: 0, length: candidateDimmedTemplate.length))
      self.candidateDimmedTemplate = candidateDimmedTemplate.copy()
    }
  }

  func updateScriptVariant(_ scriptVariant: String) {
    if scriptVariant == self.scriptVariant { return }
    self.scriptVariant = scriptVariant

    let textFontSize: Double = (textAttrs[.font] as! NSFont).pointSize
    let commentFontSize: Double = (commentAttrs[.font] as! NSFont).pointSize
    let labelFontSize: Double = (labelAttrs[.font] as! NSFont).pointSize
    var zhFont: NSFont = CTFont(.system, size: textFontSize, language: scriptVariant as CFString)
    var zhCommentFont: NSFont = .init(descriptor: zhFont.fontDescriptor, size: commentFontSize)!
    let maxFontSize: Double = max(textFontSize, commentFontSize, labelFontSize)
    var refFont: NSFont = .init(descriptor: zhFont.fontDescriptor, size: maxFontSize)!
    if isVertical {
      zhFont = zhFont.vertical
      zhCommentFont = zhCommentFont.vertical
      refFont = refFont.vertical
    }
    let baselineRefInfo: NSDictionary = [kCTBaselineReferenceFont : refFont, kCTBaselineClassIdeographicCentered : isVertical ? .zero : (refFont.ascender + refFont.descender) * 0.5, kCTBaselineClassRoman : isVertical ? -(refFont.ascender + refFont.descender) * 0.5 : .zero, kCTBaselineClassIdeographicLow : isVertical ? (refFont.descender - refFont.ascender) * 0.5 : refFont.descender]

    textAttrs[.baselineReferenceInfo] = baselineRefInfo
    labelAttrs[.baselineReferenceInfo] = baselineRefInfo
    commentAttrs[.baselineReferenceInfo] = baselineRefInfo
    preeditAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont : zhFont]
    statusAttrs[.baselineReferenceInfo] = [kCTBaselineReferenceFont : zhCommentFont]

    textAttrs[.language] = scriptVariant
    labelAttrs[.language] = scriptVariant
    commentAttrs[.language] = scriptVariant
    preeditAttrs[.language] = scriptVariant
    statusAttrs[.language] = scriptVariant

    let candidateTemplate: NSMutableAttributedString = self.candidateTemplate.mutableCopy()
    let templateRange: NSRange = .init(location: 0, length: candidateTemplate.length)
    candidateTemplate.addAttribute(.baselineReferenceInfo, value: baselineRefInfo, range: templateRange)
    candidateTemplate.addAttribute(.language, value: scriptVariant, range: templateRange)
    self.candidateTemplate = candidateTemplate.copy()

    let candidateHilitedTemplate: NSMutableAttributedString = self.candidateHilitedTemplate.mutableCopy()
    candidateHilitedTemplate.addAttribute(.baselineReferenceInfo, value: baselineRefInfo, range: templateRange)
    candidateHilitedTemplate.addAttribute(.language, value: scriptVariant, range: templateRange)
    self.candidateHilitedTemplate = candidateHilitedTemplate.copy()

    if isTabular {
      let candidateDimmedTemplate: NSMutableAttributedString? = self.candidateDimmedTemplate?.mutableCopy()
      candidateDimmedTemplate?.addAttribute(.baselineReferenceInfo, value: baselineRefInfo, range: templateRange)
      candidateDimmedTemplate?.addAttribute(.language, value: scriptVariant, range: templateRange)
      self.candidateDimmedTemplate = candidateDimmedTemplate?.copy()
    }
  }
}  // SquirrelTheme

// MARK: Typesetting extensions for TextKit 1 (Mac OSX 10.9 to MacOS 11)

enum SquirrelContentBlock: Sendable {
  case preedit, linearCandidate, stackedCandidate, paging, status
  var isCandidate: Bool { [.linearCandidate, .stackedCandidate].contains(self) }
}

final class SquirrelLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
  override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    let textContainer: NSTextContainer = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil, withoutAdditionalLayout: true)!
    let verticalOrientation: Bool = textContainer.layoutOrientation == .vertical
    let context: CGContext = NSGraphicsContext.current!.cgContext
    context.resetClip()
    enumerateLineFragments(forGlyphRange: glyphsToShow) { lineRect, lineUsedRect, container, lineRange, flag in
      let charRange: NSRange = self.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)
      self.textStorage!.enumerateAttributes(in: charRange, options: [.longestEffectiveRangeNotRequired]) { attrs, runRange, stop in
        let runGlyphRange: NSRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
        let runFont: NSFont = attrs[.font] as! NSFont
        if attrs[.rubyAnnotation] != nil || (verticalOrientation && runFont.fontName == "AppleColorEmoji" && runFont.pointSize < 24) {
          context.saveGState()
          context.scaleBy(x: 1.0, y: -1.0)
          var position: NSPoint = self.location(forGlyphAt: runGlyphRange.location) + lineRect.origin + origin
          var line: CTLine
          if attrs[.rubyAnnotation] == nil {
            let subString: NSMutableAttributedString = self.textStorage!.attributedSubstring(from: runRange).mutableCopy()
            subString.addAttribute(.verticalGlyphForm, value: 1, range: NSRange(location: 0, length: runRange.length))
            line = CTLineCreateWithAttributedString(subString)
            if let superscript: Int = attrs[.superscript] as? Int {
              position.y -= runFont.descender * Double(superscript) * 0.5
            }
          } else {
            line = CTLineCreateWithAttributedString(self.textStorage!.attributedSubstring(from: runRange))
          }
          let glyphRuns: [CTRun] = CTLineGetGlyphRuns(line) as! [CTRun]
          for (i, run) in glyphRuns.enumerated() {
            var matrix: CGAffineTransform = CTRunGetTextMatrix(run)
            var glyphOrigin: NSPoint = context.convertToDeviceSpace(position)
            glyphOrigin = context.convertToUserSpace(NSPoint(x: glyphOrigin.x.rounded(.up), y: glyphOrigin.y.rounded(.up)))
            matrix.tx = glyphOrigin.x
            matrix.ty = -glyphOrigin.y
            context.textMatrix = matrix
            CTRunDraw(run, context, CFRange(location: 0, length: 0))
            if i < glyphRuns.count - 1 {
              position.x += CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil)
            }
          }
          context.restoreGState()
        } else {
          var glyphOrigin: NSPoint = origin
          if !verticalOrientation {
            let refFont: NSFont = (attrs[.baselineReferenceInfo] as! NSDictionary)[kCTBaselineReferenceFont] as! NSFont
            glyphOrigin.y = (runFont.ascender + runFont.descender - refFont.ascender - refFont.descender) * 0.5
          }
          glyphOrigin = context.convertToDeviceSpace(glyphOrigin)
          glyphOrigin = context.convertToUserSpace(NSPoint(x: glyphOrigin.x.rounded(.up), y: glyphOrigin.y.rounded(.up)))
          super.drawGlyphs(forGlyphRange: runGlyphRange, at: glyphOrigin)
        }
      }
    }
  }

  func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
    guard let defaultParagraphStyle = (textContainer as? SquirrelTextContainer)?.defaultParagraphStyle else { return false }
    var didModify: Bool = false
    let verticalOrientation: Bool = textContainer.layoutOrientation == .vertical
    let charRange: NSRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    let lineHeight: Double = defaultParagraphStyle.minimumLineHeight
    var baseline: Double = lineHeight * 0.5
    if !verticalOrientation {
      let refFont: NSFont = (layoutManager.textStorage!.attribute(.baselineReferenceInfo, at: charRange.location, effectiveRange: nil) as! NSDictionary)[kCTBaselineReferenceFont] as! NSFont
      baseline += (refFont.ascender + refFont.descender) * 0.5
    }
    let newBaselineOffset: Double = (lineFragmentUsedRect.pointee.minY - lineFragmentRect.pointee.minY + baseline).rounded()
    if (baselineOffset.pointee - newBaselineOffset).isNormal {
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
      let contentBlock: SquirrelContentBlock? = (layoutManager.textContainers.first as? SquirrelTextContainer)?.contentBlock
      return contentBlock == .linearCandidate ? charBeforeIndex == 0x1D : charBeforeIndex != UInt8(ascii: "\t")
    }
  }

  func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
    if charIndex > 0, layoutManager.textStorage!.mutableString.character(at: charIndex) == 0x8B, layoutManager.textStorage!.attribute(.rubyAnnotation, at: charIndex - 1, effectiveRange: nil) != nil {
      return .whitespace
    } else {
      return action
    }
  }

  func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
    var rect: NSRect = .init(origin: glyphPosition, size: .zero)
    if layoutManager.textStorage!.mutableString.character(at: charIndex) == 0x8B, let controlCharacterSize: NSSize = layoutManager.textStorage!.attribute(.controlCharacterSize, at: charIndex, effectiveRange: nil) as? NSSize {
      rect.size = controlCharacterSize
    }
    return rect
  }
}  // SquirrelLayoutManager

// MARK: Typesetting extensions for TextKit 2 (MacOS 12 or higher)

@available(macOS 12.0, *) final class SquirrelTextLayoutFragment: NSTextLayoutFragment, NSTextLayoutOrientationProvider {
  lazy var layoutOrientation: NSLayoutManager.TextLayoutOrientation = textLayoutManager?.textContainer?.layoutOrientation ?? .horizontal

  override var renderingSurfaceBounds: CGRect {
    var bounds: CGRect = super.renderingSurfaceBounds
    guard state == .layoutAvailable, let textLayoutManager: SquirrelTextLayoutManager = textLayoutManager as? SquirrelTextLayoutManager, let textContainer: SquirrelTextContainer = textLayoutManager.textContainer as? SquirrelTextContainer, textContainer.contentBlock.isCandidate, let defaultParagraphStyle = textContainer.defaultParagraphStyle else { return bounds }
    if rangeInElement.location.isEqual(textLayoutManager.documentRange.location) {
      let spacing: Double = textContainer.contentBlock == .stackedCandidate ? defaultParagraphStyle.paragraphSpacingBefore : (defaultParagraphStyle.lineSpacing * 0.5).rounded(.down)
      bounds.origin.y -= spacing
      bounds.size.height += spacing
    }
    if rangeInElement.endLocation.isEqual(textLayoutManager.documentRange.endLocation) {
      bounds.size.height += textContainer.contentBlock == .stackedCandidate ? defaultParagraphStyle.paragraphSpacing : (defaultParagraphStyle.lineSpacing * 0.5).rounded(.up)
    }
    return bounds
  }

  override func draw(at point: NSPoint, in context: CGContext) {
    var origin: NSPoint = point
    if #available(macOS 14.0, *) {
    } else { // in macOS 12 and 13, textLineFragments.typographicBouonds are in textContainer coordinates
      origin.x -= layoutFragmentFrame.minX
      origin.y -= layoutFragmentFrame.minY
    }
    context.resetClip()
    for lineFrag in textLineFragments {
      let lineRect: NSRect = lineFrag.typographicBounds.offsetBy(dx: origin.x, dy: origin.y)
      var baseline: Double = lineRect.midY
      if layoutOrientation == .horizontal {
        let refFont: NSFont = (lineFrag.attributedString.attribute(.baselineReferenceInfo, at: lineFrag.characterRange.location, effectiveRange: nil) as! NSDictionary)[kCTBaselineReferenceFont] as! NSFont
        baseline += (refFont.ascender + refFont.descender) * 0.5
      }
      var renderOrigin: NSPoint = .init(x: lineRect.minX + lineFrag.glyphOrigin.x, y: baseline.rounded() - lineFrag.glyphOrigin.y)
      renderOrigin = context.convertToDeviceSpace(renderOrigin)
      renderOrigin = context.convertToUserSpace(NSPoint(x: renderOrigin.x.rounded(.up), y: renderOrigin.y.rounded(.up)))
      lineFrag.draw(at: renderOrigin, in: context)
    }
  }
}  // SquirrelTextLayoutFragment

@available(macOS 12.0, *) final class SquirrelTextLayoutManager: NSTextLayoutManager, NSTextLayoutManagerDelegate {
  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, shouldBreakLineBefore location: any NSTextLocation, hyphenating: Bool) -> Bool {
    let contentStorage: NSTextContentStorage = textLayoutManager.textContentManager as! NSTextContentStorage
    let charIndex: Int = contentStorage.offset(from: contentStorage.documentRange.location, to: location)
    if charIndex <= 1 {
      return true
    } else {
      let charBeforeIndex: unichar = contentStorage.textStorage!.mutableString.character(at: charIndex - 1)
      let contentBlock: SquirrelContentBlock? = (textLayoutManager.textContainer as? SquirrelTextContainer)?.contentBlock
      return contentBlock == .linearCandidate ? charBeforeIndex == 0x1D : charBeforeIndex != UInt8(ascii: "\t")
    }
  }

  func textLayoutManager(_: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
    let textRange: NSTextRange? = .init(location: location, end: textElement.elementRange!.endLocation)
    return SquirrelTextLayoutFragment(textElement: textElement, range: textRange)
  }
}  // SquirrelTextLayoutManager

final class NSFlippedView: NSView, Sendable {
  override var isFlipped: Bool { true }
}

final class SquirrelTextContainer: NSTextContainer {
  var contentBlock: SquirrelContentBlock
  weak var defaultParagraphStyle: NSParagraphStyle?
  private var _layoutOrientation: NSLayoutManager.TextLayoutOrientation = .horizontal
  override var layoutOrientation: NSLayoutManager.TextLayoutOrientation {
    get { _layoutOrientation }
    set { _layoutOrientation = newValue }
  }

  init(contentBlock: SquirrelContentBlock, textStorage: NSTextStorage) {
    self.contentBlock = contentBlock
    super.init(size: .zero)
    lineFragmentPadding = 0
    if #available(macOS 12.0, *) {
      let textLayoutManager: SquirrelTextLayoutManager = .init()
      textLayoutManager.usesFontLeading = false
      textLayoutManager.usesHyphenation = false
      textLayoutManager.delegate = textLayoutManager
      textLayoutManager.textContainer = self
      let contentStorage: NSTextContentStorage = .init()
      contentStorage.addTextLayoutManager(textLayoutManager)
      contentStorage.textStorage = textStorage
    } else {
      let layoutManager: SquirrelLayoutManager = .init()
      layoutManager.backgroundLayoutEnabled = true
      layoutManager.usesFontLeading = false
      layoutManager.typesetterBehavior = .latestBehavior
      layoutManager.delegate = layoutManager
      layoutManager.addTextContainer(self)
      textStorage.addLayoutManager(layoutManager)
    }
  }

  @available(*, unavailable) required init(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func layoutText() -> NSRect {
    var rect: NSRect = .zero
    if #available(macOS 12.0, *) {
      textLayoutManager!.ensureLayout(for: textLayoutManager!.documentRange)
      rect = textLayoutManager!.usageBoundsForTextContainer
    } else {
      layoutManager!.ensureLayout(for: self)
      rect = layoutManager!.usedRect(for: self)
    }
    return rect.integral(options: [.alignMinXNearest, .alignMinYNearest, .alignWidthOutward, .alignHeightOutward])
  }
}

final class SquirrelTextView: NSTextView, Sendable {
  var container: SquirrelTextContainer
  var contentBlock: SquirrelContentBlock {
    get { container.contentBlock }
    set { container.contentBlock = newValue }
  }
  override var defaultParagraphStyle: NSParagraphStyle? {
    get { container.defaultParagraphStyle}
    set { container.defaultParagraphStyle = newValue }
  }

  init(contentBlock: SquirrelContentBlock, textStorage: NSTextStorage) {
    container = .init(contentBlock: contentBlock, textStorage: textStorage)
    super.init(frame: .zero, textContainer: container)
    drawsBackground = false
    isSelectable = false
    wantsLayer = false
    clipsToBounds = false
  }

  @available(*, unavailable) required init(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var layoutOrientation: NSLayoutManager.TextLayoutOrientation { container.layoutOrientation }
  override func setLayoutOrientation(_ orientation: NSLayoutManager.TextLayoutOrientation) {
    super.setLayoutOrientation(orientation)
    container.layoutOrientation = orientation
  }

  @available(macOS 12.0, *) private func textRange(fromCharRange charRange: NSRange) -> NSTextRange? {
    if charRange.location == NSNotFound { return nil }
    let start: NSTextLocation = textContentStorage!.location(textContentStorage!.documentRange.location, offsetBy: charRange.location)!
    let end: NSTextLocation = textContentStorage!.location(start, offsetBy: charRange.length)!
    return NSTextRange(location: start, end: end)
  }

  @available(macOS 12.0, *) private func charRange(fromTextRange textRange: NSTextRange?) -> NSRange {
    guard let textRange = textRange else { return NSRange(location: NSNotFound, length: 0) }
    let location: Int = textContentStorage!.offset(from: textContentStorage!.documentRange.location, to: textRange.location)
    let length: Int = textContentStorage!.offset(from: textRange.location, to: textRange.endLocation)
    return NSRange(location: location, length: length)
  }

  func layoutText() -> NSRect {
    return container.layoutText()
  }

  // Get the rectangle containing the range of text
  func blockRect(for charRange: NSRange) -> NSRect {
    if charRange.location == NSNotFound { return .zero }
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange = textRange(fromCharRange: charRange)!
      var firstLineRect: NSRect = .null
      var finalLineRect: NSRect = .null
      textLayoutManager?.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { segRange, segFrame, baseline, textContainer in
        guard !segFrame.isEmpty else { return true }
        if firstLineRect.isEmpty || segFrame.minY < firstLineRect.maxY.nextDown {
          firstLineRect = segFrame.union(firstLineRect)
        } else {
          finalLineRect = segFrame.union(finalLineRect)
        }
        return true
      }
      if contentBlock == .linearCandidate, let lineSpacing: CGFloat = defaultParagraphStyle?.lineSpacing, lineSpacing.isNormal {
        firstLineRect.size.height += lineSpacing
        if !finalLineRect.isEmpty {
          finalLineRect.size.height += lineSpacing
        }
      }

      if finalLineRect.isEmpty {
        return firstLineRect
      } else {
        let containerWidth: CGFloat = textLayoutManager?.usageBoundsForTextContainer.width ?? 0
        return NSRect(x: .zero, y: firstLineRect.minY, width: containerWidth, height: finalLineRect.maxY - firstLineRect.minY)
      }
    } else {
      let glyphRange: NSRange = layoutManager!.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      var firstLineRange: NSRange = .init(location: NSNotFound, length: 0)
      let firstLineRect: NSRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &firstLineRange)
      if glyphRange.upperBound <= firstLineRange.upperBound {
        let leading: Double = layoutManager!.location(forGlyphAt: glyphRange.location).x
        let trailing: Double = glyphRange.upperBound < firstLineRange.upperBound ? layoutManager!.location(forGlyphAt: glyphRange.upperBound).x : firstLineRect.width
        var height: Double = firstLineRect.height
        if contentBlock == .linearCandidate, firstLineRange.upperBound == layoutManager!.numberOfGlyphs, let lineSpacing: CGFloat = defaultParagraphStyle?.lineSpacing, lineSpacing.isNormal {
          height += lineSpacing
        }
        return NSRect(x: firstLineRect.minX + leading, y: firstLineRect.minY, width: trailing - leading, height: height)
      } else {
        var finalLineRange: NSRange = .init(location: NSNotFound, length: 0)
        let finalLineRect: NSRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphRange.upperBound - 1, effectiveRange: &finalLineRange)
        let containerWidth: Double = layoutManager!.usedRect(for: textContainer!).width
        var height: Double = finalLineRect.maxY - firstLineRect.minY
        if contentBlock == .linearCandidate, finalLineRange.upperBound == layoutManager!.numberOfGlyphs, let lineSpacing: CGFloat = defaultParagraphStyle?.lineSpacing, lineSpacing.isNormal {
          height += lineSpacing
        }
        return NSRect(x: .zero, y: firstLineRect.minY, width: containerWidth, height: height)
      }
    }
  }

  /** Calculate 3 rectangles enclosing the text in range. `textPolygon.head` & `.tail` are incomplete line fragments
      `textPolygon.body` is the complete line fragment in the middle if the range spans no less than one full line */
  func textPolygon(forRange charRange: NSRange) -> SquirrelTextPolygon {
    var textPolygon: SquirrelTextPolygon = .init(head: .zero, body: .zero, tail: .zero)
    if charRange.location == NSNotFound { return textPolygon }
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange = textRange(fromCharRange: charRange)!
      var headLineRect: NSRect = .null
      var tailLineRect: NSRect = .null
      var headLineRange: NSTextRange?
      var tailLineRange: NSTextRange?
      textLayoutManager?.enumerateTextSegments(in: textRange, type: .standard, options: [.middleFragmentsExcluded]) { segRange, segFrame, baseline, textContainer in
        guard !segFrame.isEmpty, let segRange = segRange else { return true }
        if headLineRect.isEmpty || segFrame.minY < headLineRect.maxY.nextDown {
          headLineRect = segFrame.union(headLineRect)
          headLineRange = headLineRange == nil ? segRange : segRange.union(headLineRange!)
        } else {
          tailLineRect = segFrame.union(tailLineRect)
          tailLineRange = tailLineRange == nil ? segRange : segRange.union(tailLineRange!)
        }
        return true
      }
      if contentBlock == .linearCandidate, let lineSpacing: CGFloat = defaultParagraphStyle?.lineSpacing, lineSpacing.isNormal {
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
        if (tailLineRect.maxX - headLineRect.maxX).magnitude < 1 {
          if (headLineRect.minX - tailLineRect.minX).magnitude < 1 {
            textPolygon.body = headLineRect.union(tailLineRect)
          } else {
            textPolygon.head = headLineRect
            textPolygon.body = NSRect(x: .zero, y: headLineRect.maxY, width: containerWidth, height: tailLineRect.maxY - headLineRect.maxY)
          }
        } else {
          textPolygon.tail = tailLineRect
          if (headLineRect.minX - tailLineRect.minX).magnitude < 1 {
            textPolygon.body = NSRect(x: .zero, y: headLineRect.minY, width: containerWidth, height: tailLineRect.minY - headLineRect.minY)
          } else {
            textPolygon.head = headLineRect
            if !tailLineRange!.contains(headLineRange!.endLocation) {
              textPolygon.body = NSRect(x: .zero, y: headLineRect.maxY, width: containerWidth, height: tailLineRect.minY - headLineRect.maxY)
            }
          }
        }
      }
    } else {
      let glyphRange: NSRange = layoutManager!.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      var headLineRange: NSRange = .init(location: NSNotFound, length: 0)
      var headLineRect: NSRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &headLineRange)
      let leading: Double = layoutManager!.location(forGlyphAt: glyphRange.location).x
      if headLineRange.upperBound >= glyphRange.upperBound {
        let trailing: Double = glyphRange.upperBound < headLineRange.upperBound ? layoutManager!.location(forGlyphAt: glyphRange.upperBound).x : headLineRect.width
        var height: Double = headLineRect.height
        if contentBlock == .linearCandidate, headLineRange.upperBound == layoutManager!.numberOfGlyphs, let lineSpacing = defaultParagraphStyle?.lineSpacing, lineSpacing.isNormal {
          height += lineSpacing
        }
        textPolygon.body = NSRect(x: leading, y: headLineRect.minY, width: trailing - leading, height: height)
      } else {
        let containerWidth: Double = layoutManager!.usedRect(for: textContainer!).width
        headLineRect.size.width = containerWidth - headLineRect.minX
        var tailLineRange: NSRange = .init(location: NSNotFound, length: 0)
        var tailLineRect: NSRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphRange.upperBound - 1, effectiveRange: &tailLineRange)
        if contentBlock == .linearCandidate, tailLineRange.upperBound == layoutManager!.numberOfGlyphs, let lineSpacing: CGFloat = defaultParagraphStyle?.lineSpacing, lineSpacing.isNormal {
          tailLineRect.size.height += lineSpacing
        }
        let trailing: Double = glyphRange.upperBound < tailLineRange.upperBound ? layoutManager!.location(forGlyphAt: glyphRange.upperBound).x : tailLineRect.width
        if tailLineRange.upperBound == glyphRange.upperBound {
          if glyphRange.location == headLineRange.location {
            textPolygon.body = NSRect(x: .zero, y: headLineRect.minY, width: containerWidth, height: tailLineRect.maxY - headLineRect.minY)
          } else {
            textPolygon.head = NSRect(x: leading, y: headLineRect.minY, width: containerWidth - leading, height: headLineRect.height)
            textPolygon.body = NSRect(x: .zero, y: headLineRect.maxY, width: containerWidth, height: tailLineRect.maxY - headLineRect.maxY)
          }
        } else {
          textPolygon.tail = NSRect(x: .zero, y: tailLineRect.minY, width: trailing, height: tailLineRect.height)
          if glyphRange.location == headLineRange.location {
            textPolygon.body = NSRect(x: .zero, y: headLineRect.minY, width: containerWidth, height: tailLineRect.minY - headLineRect.minY)
          } else {
            textPolygon.head = NSRect(x: leading, y: headLineRect.minY, width: containerWidth - leading, height: headLineRect.height)
            if tailLineRange.location > headLineRange.upperBound {
              textPolygon.body = NSRect(x: .zero, y: headLineRect.maxY, width: containerWidth, height: tailLineRect.minY - headLineRect.maxY)
            }
          }
        }
      }
    }
    return textPolygon
  }
}  // SquirrelTextView

// MARK: View behind text, containing drawings of backgrounds and highlights

final class SquirrelView: NSView, Sendable {
  let candidateView: SquirrelTextView
  let preeditView: SquirrelTextView
  let pagingView: SquirrelTextView
  let statusView: SquirrelTextView
  let scrollView: NSScrollView
  let documentView: NSFlippedView
  let candidateContents: NSTextStorage = .init()
  let preeditContents: NSTextStorage = .init()
  let pagingContents: NSTextStorage = .init()
  let statusContents: NSTextStorage = .init()
  @available(macOS 10.14, *) let shape: CAShapeLayer = .init()
  let logoLayer: CALayer = .init()
  let backImageLayer: CAShapeLayer = .init()
  let backColorLayer: CAShapeLayer = .init()
  let borderLayer: CAShapeLayer = .init()
  let documentLayer: CAShapeLayer = .init()
  private let activePageLayer: CAShapeLayer = .init()
  private let gridLayer: CAShapeLayer = .init()
  private let nonHilitedCandidateLayer: CAShapeLayer = .init()
  private let hilitedCandidateLayer: CAShapeLayer = .init()
  private let clipLayer: CAShapeLayer = .init()
  private let hilitedPreeditLayer: CAShapeLayer = .init()
  private let functionButtonLayer: CAShapeLayer = .init()
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
  private(set) var clippedHeight: Double = .zero
  private(set) var functionButton: SquirrelIndex = .VoidSymbol
  private(set) var hilitedCandidate: Int?
  private(set) var hilitedPreeditRange: NSRange = .init(location: NSNotFound, length: 0)
  var sectionNum: Int = 0
  var isExpanded: Bool = false
  var isLocked: Bool = false
  var style: SquirrelStyle = .light { didSet {
    SquirrelTheme.currentStyle = style
    scrollView.scrollerKnobStyle = style == .dark ? .light : .dark
  } }
  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }

  override init(frame frameRect: NSRect = .zero) {
    candidateView = SquirrelTextView(contentBlock: .stackedCandidate, textStorage: candidateContents)
    preeditView = SquirrelTextView(contentBlock: .preedit, textStorage: preeditContents)
    pagingView = SquirrelTextView(contentBlock: .paging, textStorage: pagingContents)
    statusView = SquirrelTextView(contentBlock: .status, textStorage: statusContents)

    documentView = NSFlippedView()
    documentView.wantsLayer = true
    documentView.layer?.isGeometryFlipped = true
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
    scrollView.wantsLayer = true
    scrollView.layer?.isGeometryFlipped = true

    if #available(macOS 10.14, *) {
      shape.fillColor = .white
    }
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.isGeometryFlipped = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay

    backColorLayer.fillRule = .evenOdd
    borderLayer.fillRule = .evenOdd
    backImageLayer.actions = ["transform" : NSNull()]
    layer?.actions = ["sublayers" : NSNull()]
    layer?.addSublayer(backImageLayer)
    layer?.addSublayer(backColorLayer)
    layer?.addSublayer(hilitedPreeditLayer)
    layer?.addSublayer(functionButtonLayer)
    layer?.addSublayer(logoLayer)
    layer?.addSublayer(borderLayer)

    documentLayer.allowsGroupOpacity = true
    documentLayer.fillRule = .evenOdd
    activePageLayer.fillRule = .evenOdd
    gridLayer.lineCap = .round
    gridLayer.lineWidth = 1.0
    clipLayer.fillColor = .white
    documentView.layer?.actions = ["sublayers" : NSNull()]
    documentView.layer?.addSublayer(documentLayer)
    documentLayer.addSublayer(activePageLayer)
    documentView.layer?.addSublayer(gridLayer)
    documentView.layer?.addSublayer(nonHilitedCandidateLayer)
    documentView.layer?.addSublayer(hilitedCandidateLayer)
    scrollView.layer?.mask = clipLayer
  }

  @available(*, unavailable) required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func estimateBounds(onScreen screen: NSRect, withPreedit hasPreedit: Bool, candidates candidateInfos: [SquirrelCandidateInfo], paging hasPaging: Bool) {
    self.candidateInfos = candidateInfos
    preeditView.isHidden = !hasPreedit
    scrollView.isHidden = candidateInfos.isEmpty
    pagingView.isHidden = !hasPaging
    statusView.isHidden = hasPreedit || !candidateInfos.isEmpty
    // layout textviews and get their sizes
    preeditRect = .zero
    documentRect = .zero // in textView's own coordinates
    clipRect = .zero
    pagingRect = .zero
    clippedHeight = .zero
    if !hasPreedit, candidateInfos.isEmpty { // status
      contentRect = statusView.layoutText(); return
    }
    if hasPreedit {
      preeditRect = preeditView.layoutText()
      contentRect = preeditRect
    }
    if candidateInfos.isEmpty { return }
    documentRect = candidateView.layoutText()
    documentRect.size.height += SquirrelTheme.current.lineSpacing
    if SquirrelTheme.current.isLinear, !candidateInfos.contains(where: \.isTruncated) {
      documentRect.size.width -= SquirrelTheme.current.fullWidth
    }
    clipRect = documentRect
    if hasPreedit {
      clipRect.origin.y = preeditRect.maxY + SquirrelTheme.current.preeditSpacing
      contentRect = preeditRect.union(clipRect)
    } else {
      contentRect = clipRect
    }
    clipRect.size.width += SquirrelTheme.current.fullWidth
    if hasPaging {
      pagingRect = pagingView.layoutText()
      pagingRect.origin.y = clipRect.maxY
      contentRect = contentRect.union(pagingRect)
    }
    // clip candidate block if it has too many lines
    let maxHeight: Double = (SquirrelTheme.current.isVertical ? screen.width : screen.height) * 0.5 - SquirrelTheme.current.borderInsets.height * 2
    clippedHeight = fdim(contentRect.height.rounded(.up), maxHeight.rounded(.up))
    contentRect.size.height -= clippedHeight
    clipRect.size.height -= clippedHeight
    scrollView.verticalScroller?.knobProportion = clipRect.height / documentRect.height
  }

  // Get the rectangles enclosing each part and the entire panel
  func layoutContents() {
    let origin: NSPoint = .init(x: SquirrelTheme.current.borderInsets.width, y: SquirrelTheme.current.borderInsets.height)
    let fullWidth = SquirrelTheme.current.fullWidth
    if !statusView.isHidden { // status
      contentRect.origin = NSPoint(x: origin.x + (fullWidth * 0.5).rounded(.up), y: origin.y)
      statusView.frame = contentRect
      return
    }
    if !preeditView.isHidden {
      preeditRect = preeditView.layoutText()
      preeditRect.size.width += fullWidth
      preeditRect.origin = origin
      contentRect = preeditRect
    }
    if !scrollView.isHidden {
      if !preeditView.isHidden {
        clipRect.origin.x = origin.x
        clipRect.origin.y = preeditRect.maxY + SquirrelTheme.current.preeditSpacing
        contentRect = preeditRect.union(clipRect)
      } else {
        clipRect.origin = origin
        contentRect = clipRect
      }
      if !pagingView.isHidden {
        pagingRect = pagingView.layoutText()
        pagingRect.size.width += fullWidth
        pagingRect.origin.x = origin.x
        pagingRect.origin.y = clipRect.maxY
        contentRect = contentRect.union(pagingRect)
      }
    }
    contentRect.size.width -= fullWidth
    contentRect.origin.x += (fullWidth * 0.5).rounded(.up)
    if !preeditView.isHidden {
      preeditView.frame = NSRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: preeditRect.height)
    }
    if !scrollView.isHidden {
      scrollView.frame = NSRect(x: clipRect.minX, y: clipRect.minY, width: contentRect.width + fullWidth, height: clipRect.height)
      documentView.frame = NSRect(x: .zero, y: .zero, width: contentRect.width + fullWidth, height: documentRect.height)
      candidateView.frame = NSRect(x: (fullWidth * 0.5).rounded(.up), y: (SquirrelTheme.current.lineSpacing * 0.5).rounded(.down), width: contentRect.width, height: documentRect.height - SquirrelTheme.current.lineSpacing)
    }
    if !pagingView.isHidden {
      pagingView.frame = NSRect(x: SquirrelTheme.current.isLinear ? contentRect.maxX - pagingRect.width + fullWidth : contentRect.minX, y: contentRect.maxY - pagingRect.height, width: SquirrelTheme.current.isLinear ? pagingRect.width - fullWidth : contentRect.width, height: pagingRect.height)
    }
  }

  // Will triger `updateLayer()`
  func drawView(withHilitedCandidate hilitedCandidate: Int?, hilitedPreeditRange: NSRange) {
    self.hilitedCandidate = hilitedCandidate
    self.hilitedPreeditRange = hilitedPreeditRange
    functionButton = .VoidSymbol
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
    guard let hilitedCandidate = hilitedCandidate, let priorHilitedCandidate: Int = self.hilitedCandidate else { return }
    if isExpanded {
      let priorActivePage: Int = priorHilitedCandidate / SquirrelTheme.current.pageSize
      let newActivePage: Int = hilitedCandidate / SquirrelTheme.current.pageSize
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

  private func unclipHighlightedCandidate() {
    guard let hilitedCandidate = hilitedCandidate, clippedHeight.isNormal else { return }
    if isExpanded {
      let activePage: Int = hilitedCandidate / SquirrelTheme.current.pageSize
      if sectionRects[activePage].minY < scrollView.documentVisibleRect.minY.nextDown {
        var origin: NSPoint = scrollView.contentView.bounds.origin
        origin.y -= scrollView.documentVisibleRect.minY - sectionRects[activePage].minY
        scrollView.contentView.scroll(to: origin)
        scrollView.verticalScroller?.doubleValue = scrollView.documentVisibleRect.minY / clippedHeight
      } else if sectionRects[activePage].maxY > scrollView.documentVisibleRect.maxY.nextUp {
        var origin: NSPoint = scrollView.contentView.bounds.origin
        origin.y += sectionRects[activePage].maxY - scrollView.documentVisibleRect.maxY
        scrollView.contentView.scroll(to: origin)
        scrollView.verticalScroller?.doubleValue = scrollView.documentVisibleRect.minY / clippedHeight
      }
    } else {
      if scrollView.documentVisibleRect.minY > candidatePolygons[hilitedCandidate].minY.nextUp {
        var origin: NSPoint = scrollView.contentView.bounds.origin
        origin.y -= scrollView.documentVisibleRect.minY - candidatePolygons[hilitedCandidate].minY
        scrollView.contentView.scroll(to: origin)
        scrollView.verticalScroller?.doubleValue = scrollView.documentVisibleRect.minY / clippedHeight
      } else if scrollView.documentVisibleRect.maxY < candidatePolygons[hilitedCandidate].maxY.nextDown {
        var origin: NSPoint = scrollView.contentView.bounds.origin
        origin.y += candidatePolygons[hilitedCandidate].maxY - scrollView.documentVisibleRect.maxY
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
      default: break
      }
    }
    self.functionButton = functionButton
  }

  private func updateFunctionButtonLayer() -> CGPath? {
    guard functionButton != .VoidSymbol else { return nil }
    let (buttonColor, buttonRect): (NSColor?, NSRect) = switch functionButton {
    case .PageUpKey: (SquirrelTheme.current.hilitedPreeditBackColor?.hooverColor, pageUpRect)
    case .HomeKey: (SquirrelTheme.current.hilitedPreeditBackColor?.disabledColor, pageUpRect)
    case .PageDownKey: (SquirrelTheme.current.hilitedPreeditBackColor?.hooverColor, pageDownRect)
    case .EndKey: (SquirrelTheme.current.hilitedPreeditBackColor?.disabledColor, pageDownRect)
    case .ExpandButton, .CompressButton, .LockButton: (SquirrelTheme.current.hilitedPreeditBackColor?.hooverColor, expanderRect)
    case .BackSpaceKey: (SquirrelTheme.current.hilitedPreeditBackColor?.hooverColor, deleteBackRect)
    case .EscapeKey: (SquirrelTheme.current.hilitedPreeditBackColor?.disabledColor, deleteBackRect)
    default: (nil, .zero)
    }
    guard !buttonRect.isEmpty, let buttonColor = buttonColor else { return nil }
    let cornerRadius: Double = min(SquirrelTheme.current.hilitedCornerRadius, buttonRect.height * 0.5)
    let buttonPath: CGPath? = buttonRect.squirclePath(cornerRadius: cornerRadius)
    functionButtonLayer.path = buttonPath
    functionButtonLayer.fillColor = buttonColor.cgColor
    functionButtonLayer.isHidden = false
    if SquirrelTheme.current.shadowSize.isNormal {
      functionButtonLayer.shadowOffset = NSSize(width: SquirrelTheme.current.shadowSize, height: SquirrelTheme.current.shadowSize)
      functionButtonLayer.shadowOpacity = 1.0
      functionButtonLayer.shadowColor = buttonColor.shadow(withLevel: 0.7)?.cgColor
    } else {
      functionButtonLayer.shadowOpacity = .zero
    }
    return buttonPath
  }

  // All draws happen here
  override func updateLayer() {
    let theme: SquirrelTheme = .current
    let panelRect: NSRect = bounds
    let backgroundRect: NSRect = backingAlignedRect(panelRect.insetBy(dx: theme.borderInsets.width, dy: theme.borderInsets.height), options: [.alignAllEdgesNearest])
    let hilitedCornerRadius: Double = min(theme.hilitedCornerRadius, theme.candidateParagraphStyle.minimumLineHeight * 0.5)

    /* Preedit */
    deleteBackRect = .zero
    var hilitedPreeditPath: CGPath?
    if !preeditView.isHidden {
      preeditRect.origin = backgroundRect.origin
      preeditRect.size.width = backgroundRect.width
      preeditRect = backingAlignedRect(preeditRect, options: [.alignAllEdgesNearest])
      // Draw the highlighted part of preedit text
      if hilitedPreeditRange.length > 0, theme.hilitedPreeditBackColor != nil {
        let padding: Double = (theme.preeditParagraphStyle.minimumLineHeight * 0.05).rounded(.up)
        var innerBox: NSRect = preeditRect
        innerBox.origin.x += (theme.fullWidth * 0.5).rounded(.up) - padding
        innerBox.size.width = backgroundRect.width - theme.fullWidth + padding * 2
        innerBox = backingAlignedRect(innerBox, options: [.alignAllEdgesNearest])
        var textPolygon: SquirrelTextPolygon = preeditView.textPolygon(forRange: hilitedPreeditRange)
        if !textPolygon.head.isEmpty {
          textPolygon.head = textPolygon.head.offsetBy(dx: theme.borderInsets.width + (theme.fullWidth * 0.5).rounded(.up), dy: theme.borderInsets.height).insetBy(dx: -padding, dy: 0)
          textPolygon.head = backingAlignedRect(textPolygon.head.intersection(innerBox), options: [.alignAllEdgesNearest])
        }
        if !textPolygon.body.isEmpty {
          textPolygon.body = textPolygon.body.offsetBy(dx: theme.borderInsets.width + (theme.fullWidth * 0.5).rounded(.up) - padding, dy: theme.borderInsets.height)
          textPolygon.body.size.width += padding
          if !textPolygon.tail.isEmpty || hilitedPreeditRange.upperBound + 2 == preeditContents.length {
            textPolygon.body.size.width += padding
          }
          if textPolygon.body.maxX > innerBox.maxX - 2 {
            textPolygon.body.size.width = innerBox.maxX - textPolygon.body.minX
          }
          textPolygon.body = backingAlignedRect(textPolygon.body.intersection(innerBox), options: [.alignAllEdgesNearest])
        }
        if !textPolygon.tail.isEmpty {
          textPolygon.tail = textPolygon.tail.offsetBy(dx: theme.borderInsets.width + (theme.fullWidth * 0.5).rounded(.up) - padding, dy: theme.borderInsets.height)
          textPolygon.tail.size.width += padding
          if hilitedPreeditRange.upperBound + 2 == preeditContents.length {
            textPolygon.tail.size.width += padding
          }
          textPolygon.tail = backingAlignedRect(textPolygon.tail.intersection(innerBox), options: [.alignAllEdgesNearest])
        }
        hilitedPreeditPath = textPolygon.squirclePath(cornerRadius: hilitedCornerRadius)
      }
      deleteBackRect = preeditView.blockRect(for: NSRange(location: preeditContents.length - 1, length: 1))
      deleteBackRect.size.width += theme.fullWidth
      deleteBackRect.origin = NSPoint(x: preeditRect.maxX - deleteBackRect.width, y: preeditRect.maxY - deleteBackRect.height)
      deleteBackRect = backingAlignedRect(deleteBackRect.intersection(preeditRect), options: [.alignAllEdgesNearest])
    }

    /* Candidates (in documentView coordinates, except for `clipRect`) */
    candidatePolygons = []
    sectionRects = []
    tabularIndices = []
    var clipPath: CGPath?, documentPath: CGMutablePath?, gridPath: CGMutablePath?
    if !scrollView.isHidden {
      clipRect.size.width = backgroundRect.width
      clipRect = backingAlignedRect(clipRect.intersection(backgroundRect), options: [.alignAllEdgesNearest])
      documentRect.size.width = backgroundRect.width
      documentRect = documentView.backingAlignedRect(documentRect, options: [.alignAllEdgesNearest])
      clipPath = clipRect.squirclePath(cornerRadius: hilitedCornerRadius)
      documentPath = .squirclePath(vertices: documentRect.vertices, cornerRadius: hilitedCornerRadius)

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
          var candidatePolygon: SquirrelTextPolygon = candidateView.textPolygon(forRange: candInfo.candidateRange)
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
            } else if candidatePolygon.body.maxX > documentRect.maxX - 2 {
              candidatePolygon.body.size.width = documentRect.maxX - candidatePolygon.body.minX
            }
            candidatePolygon.body = documentView.backingAlignedRect(candidatePolygon.body.intersection(documentRect), options: [.alignAllEdgesNearest])
          }
          if theme.isTabular {
            if isExpanded {
              if candInfo.col == 0 {
                sectionRect.origin.y = sectionRect.maxY.rounded(.up)
              }
              if candInfo.col == theme.pageSize - 1 || candInfo.idx == candidateInfos.count - 1 {
                sectionRect.size.height = candidatePolygon.maxY.rounded(.up) - sectionRect.minY
                sectionRects.append(sectionRect)
              }
            }
            let bottomEdge: Double = candidatePolygon.maxY
            if (bottomEdge - gridOriginY).magnitude > 2 {
              lineNum += candInfo.idx > 0 ? 1 : 0
              // horizontal border except for the last line
              if bottomEdge < documentRect.maxY - 2 {
                gridPath?.move(to: NSPoint(x: theme.fullWidth * 0.5, y: bottomEdge))
                gridPath?.addLine(to: NSPoint(x: documentRect.maxX - theme.fullWidth * 0.5, y: bottomEdge))
              }
              gridOriginY = bottomEdge
            }
            let leadOrigin: NSPoint = candidatePolygon.origin
            let leadTabColumn: Int = Int(((leadOrigin.x - documentRect.minX) / tabInterval).rounded())
            tabularIndices.append(SquirrelTabularIndex(index: candInfo.idx, lineNum: lineNum, tabNum: leadTabColumn))
          }
          candidatePolygons.append(candidatePolygon)
        }
      } else { // stacked layout
        for candInfo in candidateInfos {
          var candidateRect: NSRect = candidateView.blockRect(for: candInfo.candidateRange)
          candidateRect.size.width = documentRect.width
          candidateRect.size.height += theme.lineSpacing
          candidateRect = documentView.backingAlignedRect(candidateRect.intersection(documentRect), options: [.alignAllEdgesNearest])
          candidatePolygons.append(SquirrelTextPolygon(head: .zero, body: candidateRect, tail: .zero))
        }
      }
    }

    /* Paging */
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
        pageUpRect = pagingView.blockRect(for: NSRange(location: 0, length: 1)).offsetBy(dx: pagingRect.minX, dy: pagingRect.minY)
        pageDownRect = pagingView.blockRect(for: NSRange(location: pagingContents.length - 1, length: 1)).offsetBy(dx: pagingRect.minX, dy: pagingRect.minY)
        pageDownRect.size.width += theme.fullWidth
        // bypass the bug of getting wrong glyph position when tab is presented
        pageUpRect.size = pageDownRect.size
        pageUpRect = backingAlignedRect(pageUpRect.intersection(pagingRect), options: [.alignAllEdgesNearest])
        pageDownRect = backingAlignedRect(pageDownRect.intersection(pagingRect), options: [.alignAllEdgesNearest])
      }
      if theme.isTabular {
        expanderRect = pagingView.blockRect(for: NSRange(location: pagingContents.length / 2, length: 1)).offsetBy(dx: pagingRect.minX, dy: pagingRect.minY)
        expanderRect.size.width += theme.fullWidth
        expanderRect = backingAlignedRect(expanderRect.intersection(pagingRect), options: [.alignAllEdgesNearest])
      }
    }

    /* Border */
    let outerCornerRadius: Double = min(theme.cornerRadius, panelRect.height * 0.5)
    let innerCornerRadius: Double = hilitedCornerRadius.clamp(min: outerCornerRadius - min(theme.borderInsets.width, theme.borderInsets.height), max: backgroundRect.height * 0.5)
    let panelPath: CGPath?, backgroundPath: CGPath?
    if !theme.isLinear || pagingView.isHidden {
      panelPath = panelRect.squirclePath(cornerRadius: outerCornerRadius)
      backgroundPath = backgroundRect.squirclePath(cornerRadius: innerCornerRadius)
    } else {
      var mainPanelRect: NSRect = panelRect
      mainPanelRect.size.height -= pagingRect.height
      let tailPanelRect: NSRect = pagingRect.offsetBy(dx: 0, dy: theme.borderInsets.height).insetBy(dx: -theme.borderInsets.width, dy: 0)
      panelPath = SquirrelTextPolygon(head: mainPanelRect, body: tailPanelRect, tail: .zero).squirclePath(cornerRadius: outerCornerRadius)
      var mainBackgroundRect: NSRect = backgroundRect
      mainBackgroundRect.size.height -= pagingRect.height
      backgroundPath = SquirrelTextPolygon(head: mainBackgroundRect, body: pagingRect, tail: .zero).squirclePath(cornerRadius: innerCornerRadius)
    }
    let borderPath: CGPath? = .combinePaths(panelPath, backgroundPath)
    var flip: CGAffineTransform = .init(translationX: 0, y: panelRect.height).scaledBy(x: 1, y: -1)
    let shapePath: CGPath? = panelPath?.copy(using: &flip)

    /* Draw into layers */
    if #available(macOS 10.14, *) {
      shape.path = shapePath
    }
    // highlighted preedit layer
    if let hilitedPreeditPath = hilitedPreeditPath, let hilitedPreeditBackColor = theme.hilitedPreeditBackColor {
      hilitedPreeditLayer.path = hilitedPreeditPath
      hilitedPreeditLayer.fillColor = hilitedPreeditBackColor.cgColor
      hilitedPreeditLayer.isHidden = false
    } else {
      hilitedPreeditLayer.isHidden = true
    }
    // highlighted candidate layer
    if !scrollView.isHidden {
      clipLayer.path = scrollView.bounds.squirclePath(cornerRadius: hilitedCornerRadius)
      var activePagePath: CGMutablePath?
      if isExpanded {
        let activePageRect: NSRect = sectionRects[sectionNum]
        activePagePath = .squirclePath(vertices: activePageRect.vertices, cornerRadius: hilitedCornerRadius)
        documentPath?.addPath(activePagePath!.copy()!)
      }
      if let candidateBackColor = theme.candidateBackColor {
        let nonHilitedCandidatePath: CGMutablePath = .init()
        let stackColors: Bool = theme.stackColors && theme.candidateBackColor!.alphaComponent < 1.0.nextDown
        for i in 0 ..< candidateInfos.count {
          if i != hilitedCandidate, let candidatePath: CGPath = theme.isLinear ? candidatePolygons[i].squirclePath(cornerRadius: hilitedCornerRadius) : candidatePolygons[i].body.squirclePath(cornerRadius: hilitedCornerRadius) {
            nonHilitedCandidatePath.addPath(candidatePath)
            if stackColors {
              (isExpanded && i / theme.pageSize == hilitedCandidate! / theme.pageSize ? activePagePath : documentPath)?.addPath(candidatePath)
            }
          }
        }
        nonHilitedCandidateLayer.path = nonHilitedCandidatePath.copy()
        nonHilitedCandidateLayer.fillColor = candidateBackColor.cgColor
        nonHilitedCandidateLayer.isHidden = false
      } else {
        nonHilitedCandidateLayer.isHidden = true
      }
      if let hilitedCandidate = hilitedCandidate, let hilitedCandidateBackColor = theme.hilitedCandidateBackColor, let hilitedCandidatePath: CGPath = theme.isLinear ? candidatePolygons[hilitedCandidate].squirclePath(cornerRadius: hilitedCornerRadius) : candidatePolygons[hilitedCandidate].body.squirclePath(cornerRadius: hilitedCornerRadius) {
        if theme.stackColors, theme.hilitedCandidateBackColor!.alphaComponent < 1.0.nextDown {
          (isExpanded ? activePagePath : documentPath)?.addPath(hilitedCandidatePath.copy()!)
        }
        hilitedCandidateLayer.path = hilitedCandidatePath
        hilitedCandidateLayer.fillColor = hilitedCandidateBackColor.cgColor
        hilitedCandidateLayer.isHidden = false
        if theme.shadowSize.isNormal {
          hilitedCandidateLayer.shadowOffset = NSSize(width: theme.shadowSize, height: theme.shadowSize)
          hilitedCandidateLayer.shadowOpacity = 1.0
          hilitedCandidateLayer.shadowColor = hilitedCandidateBackColor.shadow(withLevel: 0.7)?.cgColor
        } else {
          hilitedCandidateLayer.shadowOpacity = .zero
        }
      } else {
        hilitedCandidateLayer.isHidden = true
      }
      if isExpanded {
        activePageLayer.path = activePagePath?.copy()
        activePageLayer.fillColor = theme.backColor.hooverColor.cgColor
        activePageLayer.isHidden = false
      } else {
        activePageLayer.isHidden = true
      }
      documentLayer.path = documentPath?.copy()
      documentLayer.fillColor = theme.backColor.cgColor
      if let gridPath = gridPath {
        gridLayer.path = gridPath.copy()
        gridLayer.strokeColor = theme.commentForeColor.blended(withFraction: 0.8, of: theme.backColor)?.cgColor
        gridLayer.isHidden = false
      } else {
        gridLayer.isHidden = true
      }
    }
    // function buttons (page up, page down, backspace) layer
    let functionButtonPath: CGPath? = updateFunctionButtonLayer()
    if functionButtonPath == nil {
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
    if let backImage = theme.backImage, backImage.isValid {
      var transform: CGAffineTransform = theme.isVertical ? .init(rotationAngle: .pi / 2) : .identity
      transform = transform.translatedBy(x: -backgroundRect.minX, y: -backgroundRect.minY)
      backImageLayer.path = backgroundPath?.copy(using: &transform)
      backImageLayer.setAffineTransform(transform.inverted())
      backImageLayer.isHidden = false
    } else {
      backImageLayer.isHidden = true
    }
    // background color layer
    if !statusView.isHidden || !preeditRect.isEmpty || !pagingRect.isEmpty {
      if let clipPath = clipPath {
        let nonCandidatePath: CGMutablePath? = backgroundPath?.mutableCopy()
        nonCandidatePath?.addPath(clipPath)
        if theme.stackColors, theme.hilitedPreeditBackColor != nil, theme.hilitedPreeditBackColor!.alphaComponent < 1.0.nextDown {
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
      backColorLayer.fillColor = (theme.preeditBackColor ?? theme.backColor).cgColor
      backColorLayer.isHidden = false
    } else {
      backColorLayer.isHidden = true
    }
    // border layer
    borderLayer.path = borderPath
    borderLayer.fillColor = (theme.borderColor ?? theme.backColor).cgColor

    unclipHighlightedCandidate()
  }

  func index(mouseSpot spot: NSPoint) -> SquirrelIndex? {
    var point: NSPoint = convert(spot, from: nil)
    guard NSMouseInRect(point, bounds, true) else { return nil }
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
    guard NSMouseInRect(point, clipRect, true) else { return nil }
    point = convert(point, to: documentView)
    if let idx: Int = candidatePolygons.firstIndex(where: { $0.mouseInPolygon(point: point, flipped: true) }) {
      return .Ordinal(idx)
    }
    return nil
  }
}  // SquirrelView

enum SquirrelTooltipDisplay: Sendable {
  case now, delayed, onRequest, none
}

/** In order to put SquirrelPanel above client app windows,
    SquirrelPanel needs to be assigned a window level higher
    than `kCGHelpWindowLevelKey` that the system tooltips use.
    This class makes system-alike tooltips above SquirrelPanel */
final class SquirrelToolTip: NSPanel, Sendable {
  static private let showDelay: TimeInterval = 3.0
  static private let hideDelay: TimeInterval = 5.0
  private let backView: NSVisualEffectView = .init()
  private let textView: NSTextField = .init()
  private var showTimer: Timer?
  private var hideTimer: Timer?
  private unowned var panel: SquirrelPanel
  private(set) var isEmpty: Bool = true

  init(panel: SquirrelPanel) {
    self.panel = panel
    super.init(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
    backgroundColor = .clear
    isOpaque = true
    hasShadow = true
    appearanceSource = panel
    let contentView: NSView = .init()
    backView.material = .toolTip
    contentView.addSubview(backView)
    textView.isBezeled = true
    textView.bezelStyle = .squareBezel
    textView.isBordered = true
    textView.isSelectable = false
    textView.usesSingleLineMode = false
    textView.lineBreakMode = .byWordWrapping
    contentView.addSubview(textView)
    self.contentView = contentView
  }

  func showToolTip(_ toolTip: String!, display: SquirrelTooltipDisplay) {
    if display == .none || toolTip.isEmpty {
      clear(); return
    }
    level = panel.level + 1

    isEmpty = false
    textView.stringValue = toolTip
    textView.preferredMaxLayoutWidth = panel.screen!.visibleFrame.width * 0.25
    textView.font = .toolTipsFont(ofSize: 0)
    textView.textColor = .windowFrameTextColor
    textView.sizeToFit()
    var contentSize: NSSize = textView.fittingSize
    contentSize.width += 3
    contentSize.height += 3

    var spot: NSPoint = NSEvent.mouseLocation
    let cursor: NSCursor = .currentSystem!
    spot.x += cursor.image.size.width - cursor.hotSpot.x
    spot.y -= cursor.image.size.height - cursor.hotSpot.y
    var windowRect: NSRect = .init(x: spot.x, y: spot.y - contentSize.height, width: contentSize.width, height: contentSize.height)

    let screenRect: NSRect = panel.screen!.visibleFrame
    if windowRect.maxX > screenRect.maxX.nextDown {
      windowRect.origin.x = screenRect.maxX - windowRect.width
    }
    if windowRect.minY < screenRect.minY.nextUp {
      windowRect.origin.y = screenRect.minY
    }
    windowRect = panel.screen!.backingAlignedRect(windowRect, options: [.alignAllEdgesNearest])
    setFrame(windowRect, display: false)
    textView.frame = contentView!.bounds
    backView.frame = contentView!.bounds

    showTimer.take()?.invalidate()
    switch display {
    case .now: show()
    case .delayed: showTimer = .scheduledTimer(withTimeInterval: Self.showDelay, repeats: false) { _ in MainActor.assumeIsolated { self.show() } }
    default: break
    }
  }

  func show() {
    if isEmpty { return }
    showTimer.take()?.invalidate()
    display()
    orderFrontRegardless()
    hideTimer?.invalidate()
    hideTimer = .scheduledTimer(withTimeInterval: Self.hideDelay, repeats: false) { _ in MainActor.assumeIsolated { self.hide() } }
  }

  func hide() {
    showTimer.take()?.invalidate()
    hideTimer.take()?.invalidate()
    if isVisible { orderOut(nil) }
  }

  func clear() {
    isEmpty = true
    textView.stringValue = ""
    hide()
  }
}  // SquirrelToolTipView

// MARK: Panel window, dealing with text content and mouse interactions

final class SquirrelPanel: NSPanel, NSWindowDelegate, Sendable {
  static private let showStatusDuration: TimeInterval = 2.0
  static private let offsetGap: Double = 5
  // Squirrel panel layouts
  @available(macOS 10.14, *) private let back: NSVisualEffectView = .init()
  private let view: SquirrelView = .init()
  private lazy var toolTip: SquirrelToolTip = .init(panel: self)
  private var statusTimer: Timer?
  private var maxSizeAttained: NSSize = .zero
  private var scrollLocus: NSPoint = .zero
  private var cursorIndex: SquirrelIndex?
  private var textWidthLimit: Double = CGFLOAT_MAX
  private var anchorOffset: Double = 0
  private var scrollByLine: Bool = false
  private var initPosition: Bool = true
  private var needsRedraw: Bool = false
  // Rime contents and actions
  private weak var inputController: SquirrelInputController? { .current }
  private var theme: SquirrelTheme { .current }
  private var candidateIndices: Range<Int> = 0 ..< 0
  private var functionButton: SquirrelIndex = .VoidSymbol
  private var caretPos: Int?
  private var pageNum: Int = 0
  private var isLastPage: Bool = false
  /// Show preedit text inline.
  var inlinePreedit: Bool { SquirrelTheme.current.inlinePreedit }
  /// Show primary candidate inline.
  var inlineCandidate: Bool { SquirrelTheme.current.inlineCandidate }
  /// Vertical text orientation, as opposed to horizontal text orientation.
  var isVertical: Bool { SquirrelTheme.current.isVertical }
  /// Linear candidate list layout, as opposed to stacked candidate list layout.
  var isLinear: Bool { SquirrelTheme.current.isLinear }
  /// Tabular candidate list layout, initializes as tab-aligned linear layout,
  /// expandable to stack 5 (3 for vertical) pages/sections of candidates.
  var isTabular: Bool { SquirrelTheme.current.isTabular }
  var isFirstLine: Bool { view.tabularIndices.isEmpty ? true : view.tabularIndices[view.hilitedCandidate!].lineNum == 0 }
  var isLocked: Bool {
    get { view.isLocked }
    set { guard isTabular, view.isLocked != newValue else { return }
          view.isLocked = newValue
          let userConfig: SquirrelConfig = .init(.user)
          _ = userConfig.setOption("var/option/_isLockedTabular", with: newValue)
          if newValue { _ = userConfig.setOption("var/option/_isExpandedTabular", with: view.isExpanded) }
          userConfig.close() }
  }
  var isExpanded: Bool {
    get { view.isExpanded }
    set { guard isTabular, !view.isLocked, !(isLastPage && pageNum == 0), view.isExpanded != newValue else { return }
          view.isExpanded = newValue
          view.sectionNum = 0
          needsRedraw = true }
  }
  var sectionNum: Int {
    get { view.sectionNum }
    set { guard isTabular, view.isExpanded, view.sectionNum != newValue else { return }
          view.sectionNum = newValue.clamp(min: 0, max: isVertical ? 2 : 4) }
  }
  /// Position of the text input I-beam cursor on screen.
  var IbeamRect: NSRect = .zero { didSet {
    guard oldValue != IbeamRect else { return }
    needsRedraw = true
    if IbeamRect == .zero {
      initPosition = true
    } else if !_screen.frame.contains(IbeamRect), !_screen.frame.intersects(IbeamRect) {
      updateScreen()
      updateDisplayParameters()
    }
  } }
  private var _screen: NSScreen = .main!
  override var screen: NSScreen? { _screen }
  var style: SquirrelStyle {
    get { view.style }
    set { guard #available(macOS 10.14, *), view.style != newValue else { return }
          view.style = newValue
          appearance = NSAppearance(named: newValue == .dark ? .darkAqua : .aqua)
          view.needsDisplay = true
          display() }
  }
  /// Status message when pop-up is about to be displayed; nil when normal panel is about to be displayed.
  private(set) var statusMessage: String?
  /// Stores switch options that change style (color theme) settings.
  var optionSwitcher: SquirrelOptionSwitcher = .init()

  init(contentRect: NSRect = .zero) {
    super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    level = NSWindow.Level(Int(CGWindowLevelForKey(.cursorWindow) - 100))
    hasShadow = false
    isOpaque = false
    backgroundColor = .clear
    delegate = self
    acceptsMouseMovedEvents = true
    displaysWhenScreenProfileChanges = true
    worksWhenModal = true

    let contentView: NSFlippedView = .init()
    contentView.autoresizesSubviews = false
    if #available(macOS 10.14, *) {
      back.blendingMode = .behindWindow
      back.material = .hudWindow
      back.state = .active
      back.isEmphasized = true
      back.wantsLayer = true
      back.layer?.mask = view.shape
      contentView.addSubview(back)
    }
    contentView.addSubview(view)
    contentView.addSubview(view.statusView)
    contentView.addSubview(view.preeditView)
    contentView.addSubview(view.scrollView)
    contentView.addSubview(view.pagingView)
    self.contentView = contentView

    appearance = NSAppearance(named: .aqua)
    updateDisplayParameters()
  }

  func windowDidChangeBackingProperties(_ notification: Notification) {
    if let panel: SquirrelPanel = notification.object as? SquirrelPanel {
      panel.updateDisplayParameters()
    }
  }

  func updateDisplayParameters() {
    // repositioning the panel window
    initPosition = true
    maxSizeAttained = .zero
    needsRedraw |= isVisible && (view.candidateView.layoutOrientation == .vertical) != isVertical
    needsRedraw |= isVisible && !view.scrollView.isHidden && (view.candidateView.contentBlock == .linearCandidate) != isLinear
    let textViews: [SquirrelTextView] = [view.candidateView, view.preeditView, view.pagingView, view.statusView]

    // rotate the view, the core in vertical mode!
    textViews.forEach { $0.setLayoutOrientation(isVertical ? .vertical : .horizontal) }
    contentView?.boundsRotation = isVertical ? 90 : .zero
    textViews.forEach { $0.boundsRotation = .zero; $0.setBoundsOrigin(.zero) }

    view.candidateView.contentBlock = isLinear ? .linearCandidate : .stackedCandidate
    view.candidateView.defaultParagraphStyle = theme.candidateParagraphStyle
    view.preeditView.defaultParagraphStyle = theme.preeditParagraphStyle
    view.pagingView.defaultParagraphStyle = theme.pagingParagraphStyle
    view.statusView.defaultParagraphStyle = theme.statusParagraphStyle
    view.scrollView.lineScroll = theme.candidateParagraphStyle.minimumLineHeight

    // Break line if the text is too long, based on screen size.
    let prevTextWidthLimit: Double = textWidthLimit
    let screenRect: NSRect = _screen.visibleFrame
    let textWidthRatio: Double = min(0.8, 1.0 / (isVertical ? 4 : 3) + (theme.textAttrs[.font] as! NSFont).pointSize / 144.0)
    textWidthLimit = ((isVertical ? screenRect.height : screenRect.width) * textWidthRatio - theme.borderInsets.width * 2 - theme.fullWidth).rounded(.up)
    if theme.lineLength.isNormal, theme.lineLength < textWidthLimit {
      textWidthLimit = theme.lineLength
    }
    if isTabular {
      textWidthLimit = (textWidthLimit / (theme.fullWidth * 2)).rounded(.down) * (theme.fullWidth * 2)
    }
    textViews.forEach { $0.textContainer?.size = NSSize(width: textWidthLimit, height: .zero) }
    needsRedraw |= isVisible && prevTextWidthLimit != textWidthLimit

    // color, opacity and transluecency; resize logo and background image, if any
    alphaValue = theme.opacity
    let statusHeight: Double = theme.statusParagraphStyle.minimumLineHeight
    let logoRect: NSRect = .init(x: theme.borderInsets.width - 0.1 * statusHeight, y: theme.borderInsets.height - 0.1 * statusHeight, width: statusHeight * 1.2, height: statusHeight * 1.2)
    view.logoLayer.frame = logoRect
    let logoImage: NSImage = .init(named: NSImage.applicationIconName)!
    logoImage.size = logoRect.size
    view.logoLayer.contents = logoImage
    view.logoLayer.setAffineTransform(isVertical ? .init(rotationAngle: -.pi / 2) : .identity)
    if let backImage = theme.backImage, backImage.isValid {
      let widthLimit: Double = textWidthLimit + theme.fullWidth
      backImage.resizingMode = .stretch
      backImage.size = isVertical ? NSSize(width: backImage.size.width / backImage.size.height * widthLimit, height: widthLimit) : NSSize(width: widthLimit, height: backImage.size.height / backImage.size.width * widthLimit)
      view.backImageLayer.fillColor = NSColor(patternImage: backImage).cgColor
    }
    if #available(macOS 10.14, *) {
      back.isHidden = theme.translucency.isFinite && !theme.translucency.isNormal
      view.backImageLayer.opacity = 1.0 - theme.translucency
      view.backColorLayer.opacity = 1.0 - theme.translucency
      view.borderLayer.opacity = 1.0 - theme.translucency
      view.documentLayer.opacity = 1.0 - theme.translucency
    }
  }

  func candidateIndex(onDirection arrowKey: SquirrelIndex) -> Int? {
    guard let hilitedCandidate = view.hilitedCandidate, isTabular, !candidateIndices.isEmpty else { return nil }
    let currentTab: Int = view.tabularIndices[hilitedCandidate].tabNum
    let currentLine: Int = view.tabularIndices[hilitedCandidate].lineNum
    let finalLine: Int = view.tabularIndices[candidateIndices.count - 1].lineNum
    if arrowKey == (isVertical ? .LeftKey : .DownKey) {
      if hilitedCandidate == candidateIndices.count - 1, isLastPage {
        return nil
      }
      if currentLine == finalLine, !isLastPage {
        return candidateIndices.upperBound
      }
      var newIndex: Int = hilitedCandidate + 1
      while newIndex < candidateIndices.count, view.tabularIndices[newIndex].lineNum == currentLine || (view.tabularIndices[newIndex].lineNum == currentLine + 1 && view.tabularIndices[newIndex].tabNum <= currentTab) {
        newIndex += 1
      }
      if newIndex != candidateIndices.count || isLastPage {
        newIndex -= 1
      }
      return newIndex + candidateIndices.lowerBound
    } else if arrowKey == (isVertical ? .RightKey : .UpKey) {
      if currentLine == 0 {
        return pageNum == 0 ? nil : candidateIndices.lowerBound - 1
      }
      var newIndex: Int = hilitedCandidate - 1
      while newIndex > 0, view.tabularIndices[newIndex].lineNum == currentLine || (view.tabularIndices[newIndex].lineNum == currentLine - 1 && view.tabularIndices[newIndex].tabNum > currentTab) {
        newIndex -= 1
      }
      return newIndex + candidateIndices.lowerBound
    }
    return nil
  }

  // handle mouse interaction events
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      guard event.clickCount == 1, cursorIndex == .CodeInputArea, let caretPos = caretPos else { break }
      let spot: NSPoint = view.preeditView.convert(mouseLocationOutsideOfEventStream, from: nil)
      let inputIndex: Int = view.preeditView.characterIndexForInsertion(at: spot)
      switch inputIndex {
      case 0: inputController?.perform(action: .Process, onIndex: .HomeKey)
      case ..<caretPos: inputController?.moveCursor(caretPos, to: inputIndex, inlinePreedit: false, inlineCandidate: false)
      case (view.preeditContents.length - 2)...: inputController?.perform(action: .Process, onIndex: .EndKey)
      case (caretPos + 1)...: inputController?.moveCursor(caretPos, to: inputIndex - 1, inlinePreedit: false, inlineCandidate: false)
      default: break
      }
    case .leftMouseUp:
      guard event.clickCount == 1, let cursorIndex = cursorIndex else { break }
      switch cursorIndex {
      case .Ordinal(view.hilitedCandidate):
        inputController?.perform(action: .Select, onIndex: cursorIndex + candidateIndices.lowerBound)
      case .ExpandButton:
        if view.isLocked {
          isLocked = false
          view.pagingContents.replaceCharacters(in: NSRange(location: view.pagingContents.length / 2, length: 1), with: (isExpanded ? theme.symbolCompress : theme.symbolExpand)!)
          view.pagingView.setNeedsDisplay(view.convert(view.expanderRect, to: view.pagingView))
        } else {
          isExpanded = !view.isExpanded
          sectionNum = 0
        }
        fallthrough
      case functionButton:
        inputController?.perform(action: .Process, onIndex: cursorIndex)
      default: break
      }
    case .rightMouseUp:
      guard event.clickCount == 1, let cursorIndex = cursorIndex else { break }
      switch cursorIndex {
      case .Ordinal(view.hilitedCandidate):
        inputController?.perform(action: .Delete, onIndex: cursorIndex + candidateIndices.lowerBound)
      case .PageUpKey:
        inputController?.perform(action: .Process, onIndex: .HomeKey)
      case .PageDownKey:
        inputController?.perform(action: .Process, onIndex: .EndKey)
      case .ExpandButton:
        isLocked = !view.isLocked
        view.pagingContents.replaceCharacters(in: NSRange(location: view.pagingContents.length / 2, length: 1), with: isLocked ? theme.symbolLock! : isExpanded ? theme.symbolCompress! : theme.symbolExpand!)
        view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: view.pagingContents.length / 2, length: 1))
        view.pagingView.setNeedsDisplay(view.convert(view.expanderRect, to: view.pagingView), avoidAdditionalLayout: true)
        inputController?.perform(action: .Process, onIndex: .LockButton)
      case .BackSpaceKey:
        inputController?.perform(action: .Process, onIndex: .EscapeKey)
      default: break
      }
    case .mouseMoved:
      if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control] { break }
      let noDelay: Bool = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.option]
      cursorIndex = view.index(mouseSpot: mouseLocationOutsideOfEventStream)
      if let cursorIndex = cursorIndex {
        if cursorIndex != view.hilitedCandidate, cursorIndex != functionButton {
          toolTip.clear()
        } else if noDelay {
          toolTip.show()
        }
        switch cursorIndex {
        case .Ordinal(view.hilitedCandidate), functionButton: break
        case .Ordinal(0 ..< candidateIndices.count):
          if functionButton != .VoidSymbol {
            highlightFunctionButton(.VoidSymbol, displayToolTip: .none)
          }
          if isLinear, view.candidateInfos[cursorIndex.rawValue].isTruncated {
            toolTip.showToolTip(view.candidateContents.mutableString.substring(with: view.candidateInfos[cursorIndex.rawValue].candidateRange), display: .now)
          } else {
            toolTip.showToolTip(Bundle.main.localizedString(forKey: "candidate", value: nil, table: "Tooltips"), display: .onRequest)
          }
          sectionNum = cursorIndex.rawValue / theme.pageSize
          inputController?.perform(action: .Highlight, onIndex: cursorIndex + candidateIndices.lowerBound)
        case .PageUpKey, .PageDownKey, .ExpandButton, .BackSpaceKey:
          highlightFunctionButton(cursorIndex, displayToolTip: noDelay ? .now : .delayed)
        default: break
        }
      } else {
        toolTip.clear()
        if functionButton != .VoidSymbol {
          highlightFunctionButton(.VoidSymbol, displayToolTip: .none)
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
      let scrollThreshold: Double = theme.candidateParagraphStyle.minimumLineHeight
      if event.phase == .began {
        scrollLocus = .zero
        scrollByLine = false
      } else if event.phase == .changed, scrollLocus.x.isFinite, scrollLocus.y.isFinite {
        var scrollDistance: Double = .zero
        // determine scrolling direction by confining to sectors within ±30º of any axis
        if event.scrollingDeltaX.magnitude > event.scrollingDeltaY.magnitude * 3.squareRoot() {
          scrollDistance = event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : scrollThreshold)
          scrollLocus.x += scrollDistance
        } else if event.scrollingDeltaY.magnitude > event.scrollingDeltaX.magnitude * 3.squareRoot() {
          scrollDistance = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : scrollThreshold)
          scrollLocus.y += scrollDistance
        }
        // compare accumulated locus length against threshold and limit paging to max once
        switch scrollLocus {
        case let p where p.x > scrollThreshold:
          if isVertical, view.scrollView.documentVisibleRect.maxY < view.documentRect.maxY.nextDown {
            scrollByLine = true
            var origin: NSPoint = view.scrollView.contentView.bounds.origin
            origin.y += min(scrollDistance, view.documentRect.maxY - view.scrollView.documentVisibleRect.maxY)
            view.scrollView.contentView.scroll(to: origin)
            view.scrollView.verticalScroller?.doubleValue = view.scrollView.documentVisibleRect.minY / view.clippedHeight
          } else if !scrollByLine {
            inputController?.perform(action: .Process, onIndex: isVertical ? .PageDownKey : .PageUpKey)
            scrollLocus = NSPoint(x: Double.infinity, y: Double.infinity)
          }
        case let p where p.y > scrollThreshold:
          if view.scrollView.documentVisibleRect.minY > view.documentRect.minY.nextUp {
            scrollByLine = true
            var origin: NSPoint = view.scrollView.contentView.bounds.origin
            origin.y -= min(scrollDistance, view.scrollView.documentVisibleRect.minY - view.documentRect.minY)
            view.scrollView.contentView.scroll(to: origin)
            view.scrollView.verticalScroller?.doubleValue = view.scrollView.documentVisibleRect.minY / view.clippedHeight
          } else if !scrollByLine {
            inputController?.perform(action: .Process, onIndex: .PageUpKey)
            scrollLocus = NSPoint(x: Double.infinity, y: Double.infinity)
          }
        case let p where p.x < -scrollThreshold:
          if isVertical, view.scrollView.documentVisibleRect.minY > view.documentRect.minY.nextUp {
            scrollByLine = true
            var origin: NSPoint = view.scrollView.contentView.bounds.origin
            origin.y += max(scrollDistance, view.documentRect.minY - view.scrollView.documentVisibleRect.minY)
            view.scrollView.contentView.scroll(to: origin)
            view.scrollView.verticalScroller?.doubleValue = view.scrollView.documentVisibleRect.minY / view.clippedHeight
          } else if !scrollByLine {
            inputController?.perform(action: .Process, onIndex: isVertical ? .PageUpKey : .PageDownKey)
            scrollLocus = NSPoint(x: Double.infinity, y: Double.infinity)
          }
        case let p where p.y < -scrollThreshold:
          if view.scrollView.documentVisibleRect.maxY < view.documentRect.maxY.nextDown {
            scrollByLine = true
            var origin: NSPoint = view.scrollView.contentView.bounds.origin
            origin.y -= max(scrollDistance, view.scrollView.documentVisibleRect.maxY - view.documentRect.maxY)
            view.scrollView.contentView.scroll(to: origin)
            view.scrollView.verticalScroller?.doubleValue = view.scrollView.documentVisibleRect.minY / view.clippedHeight
          } else if !scrollByLine {
            inputController?.perform(action: .Process, onIndex: .PageDownKey)
            scrollLocus = NSPoint(x: Double.infinity, y: Double.infinity)
          }
        default: break
        }
      }
    default: super.sendEvent(event)
    }
  }

  func showToolTip() -> Bool {
    guard !toolTip.isEmpty else { return false }
    toolTip.show()
    return true
  }

  private func highlightCandidate(_ highlightedCandidate: Int?) {
    guard let highlightedCandidate = highlightedCandidate, let priorHilitedCandidate: Int = view.hilitedCandidate else { return }
    let priorSectionNum: Int = priorHilitedCandidate / theme.pageSize
    view.sectionNum = highlightedCandidate / theme.pageSize
    // apply new foreground colors
    for i in 0 ..< theme.pageSize {
      let priorCandidate: Int = i + priorSectionNum * theme.pageSize
      if view.sectionNum != priorSectionNum || priorCandidate == priorHilitedCandidate, priorCandidate < candidateIndices.count {
        let labelColor: NSColor = priorCandidate == priorHilitedCandidate && view.sectionNum == priorSectionNum ? theme.labelForeColor : theme.dimmedLabelForeColor!
        view.candidateContents.addAttribute(.foregroundColor, value: labelColor, range: view.candidateInfos[priorCandidate].labelRange)
        if priorCandidate == priorHilitedCandidate {
          view.candidateContents.addAttribute(.foregroundColor, value: theme.textForeColor, range: view.candidateInfos[priorCandidate].textRange)
          view.candidateContents.addAttribute(.foregroundColor, value: theme.commentForeColor, range: view.candidateInfos[priorCandidate].commentRange)
        }
      }
      let newCandidate: Int = i + view.sectionNum * theme.pageSize
      if view.sectionNum != priorSectionNum || newCandidate == highlightedCandidate, newCandidate < candidateIndices.count {
        view.candidateContents.addAttribute(.foregroundColor, value: newCandidate == highlightedCandidate ? theme.hilitedLabelForeColor : theme.labelForeColor, range: view.candidateInfos[newCandidate].labelRange)
        if newCandidate == highlightedCandidate {
          view.candidateContents.addAttribute(.foregroundColor, value: theme.hilitedTextForeColor, range: view.candidateInfos[newCandidate].textRange)
          view.candidateContents.addAttribute(.foregroundColor, value: theme.hilitedCommentForeColor, range: view.candidateInfos[newCandidate].commentRange)
        }
      }
    }
    view.highlightCandidate(highlightedCandidate)
  }

  static private let buttonToolTip: [SquirrelIndex : String] = [.HomeKey : "home", .PageUpKey : "page_up", .EndKey : "end", .PageDownKey : "page_down", .LockButton : "unlock", .CompressButton : "compress", .ExpandButton : "expand", .EscapeKey : "escape", .BackSpaceKey : "delete"]

  private func highlightFunctionButton(_ functionButton: SquirrelIndex, displayToolTip display: SquirrelTooltipDisplay) {
    if self.functionButton == functionButton { return }
    switch self.functionButton {
    case .PageUpKey:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor, range: NSRange(location: 0, length: 1))
    case .PageDownKey:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor, range: NSRange(location: view.pagingContents.length - 1, length: 1))
    case .ExpandButton:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor, range: NSRange(location: view.pagingContents.length / 2, length: 1))
    case .BackSpaceKey:
      view.preeditContents.addAttribute(.foregroundColor, value: theme.preeditForeColor, range: NSRange(location: view.preeditContents.length - 1, length: 1))
    default: break
    }
    self.functionButton = functionButton
    var newFunctionButton: SquirrelIndex = .VoidSymbol
    switch functionButton {
    case .PageUpKey:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: 0, length: 1))
      newFunctionButton = pageNum == 0 ? .HomeKey : .PageUpKey
    case .PageDownKey:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: view.pagingContents.length - 1, length: 1))
      newFunctionButton = isLastPage ? .EndKey : .PageDownKey
    case .ExpandButton:
      view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: view.pagingContents.length / 2, length: 1))
      newFunctionButton = isLocked ? .LockButton : isExpanded ? .CompressButton : .ExpandButton
    case .BackSpaceKey:
      view.preeditContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: NSRange(location: view.preeditContents.length - 1, length: 1))
      newFunctionButton = caretPos == nil || caretPos == 0 ? .EscapeKey : .BackSpaceKey
    default: break
    }
    if newFunctionButton != .VoidSymbol, let toolTipKey: String = Self.buttonToolTip[newFunctionButton] {
      toolTip.showToolTip(Bundle.main.localizedString(forKey: toolTipKey, value: nil, table: "Tooltips"), display: display)
    }
    view.highlightFunctionButton(newFunctionButton)
    displayIfNeeded()
  }

  func updateScreen() {
    _screen = .screens.first { $0.frame.contains(IbeamRect.origin) } ?? .main!
  }

  // Get the window size, it will be the dirtyRect in SquirrelView.drawRect
  private func show() {
    if !needsRedraw, !initPosition {
      isVisible ? displayIfNeeded() : orderFront(nil); return
    }

    let fullWidth: Double = SquirrelTheme.current.fullWidth
    let border: NSSize = SquirrelTheme.current.borderInsets
    let textWidthRatio: Double = min(0.8, 1.0 / (isVertical ? 4 : 3) + (theme.textAttrs[.font] as! NSFont).pointSize / 144.0)
    let screenRect: NSRect = _screen.visibleFrame

    // the sweep direction of the client app changes the behavior of adjusting Squirrel panel position
    let sweepVertical: Bool = IbeamRect.width > IbeamRect.height
    var contentRect: NSRect = view.contentRect
    // fixed line length (text width), but not applicable to status message
    if theme.lineLength.isNormal, view.statusView.isHidden {
      contentRect.size.width = textWidthLimit
    }
    // remember panel size (fix the top leading anchor of the panel in screen coordiantes)
    // but only when the text would expand upstreams (towards the leading and/or top edges)
    if theme.rememberSize, view.statusView.isHidden {
      if theme.lineLength.isFinite, !theme.lineLength.isNormal {
        let attained: Bool = switch (isVertical, sweepVertical) {
        case (true, true): IbeamRect.minY - max(contentRect.width, maxSizeAttained.width) - border.width - (fullWidth * 0.5).rounded(.down) < screenRect.minY.nextUp
        case (true, false): IbeamRect.minY - Self.offsetGap - screenRect.height * textWidthRatio - border.width * 2 - fullWidth < screenRect.minY.nextUp
        case (false, true): IbeamRect.minX - Self.offsetGap - screenRect.width * textWidthRatio - border.width * 2 - fullWidth > screenRect.minX.nextUp
        case (false, false): IbeamRect.maxX + max(contentRect.width, maxSizeAttained.width) + border.width + (fullWidth * 0.5).rounded(.down) > screenRect.maxX.nextDown
        }
        if attained {
          if contentRect.width > maxSizeAttained.width.nextUp {
            maxSizeAttained.width = contentRect.width
          } else {
            contentRect.size.width = maxSizeAttained.width
          }
        }
      }
      let textHeight: Double = max(contentRect.height, maxSizeAttained.height) + border.height * 2
      if isVertical ? (IbeamRect.minX - textHeight - (sweepVertical ? Self.offsetGap : 0) < screenRect.minX.nextUp)
                    : (IbeamRect.minY - textHeight - (sweepVertical ? 0 : Self.offsetGap) < screenRect.minY.nextUp) {
        if contentRect.height > maxSizeAttained.height.nextUp {
          maxSizeAttained.height = contentRect.height
        } else {
          contentRect.size.height = maxSizeAttained.height
        }
      }
    }

    var windowRect: NSRect = .zero
    if view.statusView.isHidden {
      if isVertical {
        // anchor is the top right corner in screen coordinates (maxX, maxY)
        windowRect = NSRect(x: frame.maxX - contentRect.height - border.height * 2, y: frame.maxY - contentRect.width - border.width * 2 - fullWidth, width: contentRect.height + border.height * 2, height: contentRect.width + border.width * 2 + fullWidth)
        initPosition |= windowRect.intersects(IbeamRect) || windowRect.contains(IbeamRect) || (!screenRect.contains(windowRect) && !screenRect.intersects(windowRect))
        if initPosition {
          if !sweepVertical {
            // To avoid jumping up and down while typing, use the lower screen when typing on upper, and vice versa
            windowRect.origin.y = IbeamRect.minY - Self.offsetGap - screenRect.height * textWidthRatio - border.width * 2 - fullWidth < screenRect.minY.nextUp ? IbeamRect.maxY + Self.offsetGap : IbeamRect.minY - Self.offsetGap - windowRect.height
            // Make the right edge of candidate block fixed at the left of cursor
            windowRect.origin.x = IbeamRect.minX + border.height - windowRect.width
          } else {
            windowRect.origin.x = IbeamRect.minX - Self.offsetGap - windowRect.width < screenRect.minX.nextUp ? IbeamRect.maxX + Self.offsetGap : IbeamRect.minX - Self.offsetGap - windowRect.width
            windowRect.origin.y = IbeamRect.minY + border.width + (fullWidth * 0.5).rounded(.up) - windowRect.height
          }
        }
      } else {
        // anchor is the top left corner in screen coordinates (minX, maxY)
        windowRect = NSRect(x: frame.minX, y: frame.maxY - contentRect.height - border.height * 2, width: contentRect.width + border.width * 2 + fullWidth, height: contentRect.height + border.height * 2)
        initPosition |= windowRect.intersects(IbeamRect) || windowRect.contains(IbeamRect) || (!screenRect.contains(windowRect) && !screenRect.intersects(windowRect))
        if initPosition {
          if sweepVertical {
            // To avoid jumping left and right while typing, use the lefter screen when typing on righter, and vice versa
            windowRect.origin.x = IbeamRect.minX - Self.offsetGap - screenRect.width * textWidthRatio - border.width * 2 - fullWidth > screenRect.minX.nextUp ? IbeamRect.minX - Self.offsetGap - windowRect.width : IbeamRect.maxX + Self.offsetGap
            windowRect.origin.y = IbeamRect.minY + border.height - windowRect.height
          } else {
            windowRect.origin.y = IbeamRect.minY - Self.offsetGap - windowRect.height < screenRect.minY.nextUp ? IbeamRect.maxY + Self.offsetGap : IbeamRect.minY - Self.offsetGap - windowRect.height
            windowRect.origin.x = IbeamRect.maxX - border.width - (fullWidth * 0.5).rounded(.up)
          }
        }
      }
    } else {
      // following system UI, middle-align status message with cursor
      initPosition = true
      windowRect.size = isVertical ? NSSize(width: contentRect.height + border.height * 2, height: contentRect.width + border.width * 2 + fullWidth) : NSSize(width: contentRect.width + border.width * 2 + fullWidth, height: contentRect.height + border.height * 2)
      // vertically/horizontally centre-align (midY/midX) in screen coordinates
      windowRect.origin = sweepVertical ? NSPoint(x: IbeamRect.minX - Self.offsetGap - windowRect.width, y: IbeamRect.midY - windowRect.height * 0.5) : NSPoint(x: IbeamRect.midX - windowRect.width * 0.5, y: IbeamRect.minY - Self.offsetGap - windowRect.height)
    }

    if !view.preeditView.isHidden {
      if initPosition { anchorOffset = 0 }
      if isVertical != sweepVertical {
        let offset: Double = view.preeditRect.height
        if isVertical {
          windowRect.origin.x += offset - anchorOffset
        } else {
          windowRect.origin.y += offset - anchorOffset
        }
        anchorOffset = offset
      }
    }
    if windowRect.maxX > screenRect.maxX.nextDown {
      windowRect.origin.x = (initPosition && sweepVertical ? min(IbeamRect.minX - Self.offsetGap, screenRect.maxX) : screenRect.maxX) - windowRect.width
    }
    if windowRect.minX < screenRect.minX.nextUp {
      windowRect.origin.x = initPosition && sweepVertical ? max(IbeamRect.maxX + Self.offsetGap, screenRect.minX) : screenRect.minX
    }
    if windowRect.minY < screenRect.minY.nextUp {
      windowRect.origin.y = initPosition && !sweepVertical ? max(IbeamRect.maxY + Self.offsetGap, screenRect.minY) : screenRect.minY
    }
    if windowRect.maxY > screenRect.maxY.nextDown {
      windowRect.origin.y = (initPosition && !sweepVertical ? min(IbeamRect.minY - Self.offsetGap, screenRect.maxY) : screenRect.maxY) - windowRect.height
    }

    if isVertical {
      windowRect.origin.x += contentRect.height - view.contentRect.height
      windowRect.size.width -= contentRect.height - view.contentRect.height
    } else {
      windowRect.origin.y += contentRect.height - view.contentRect.height
      windowRect.size.height -= contentRect.height - view.contentRect.height
    }
    windowRect = _screen.backingAlignedRect(windowRect.intersection(screenRect), options: [.alignAllEdgesNearest])
    setFrame(windowRect, display: true)

    contentView?.setBoundsOrigin(isVertical ? NSPoint(x: -windowRect.width, y: .zero) : .zero)
    let viewRect: NSRect = contentView!.bounds.integral(options: [.alignAllEdgesNearest])
    view.frame = viewRect
    if !back.isHidden { back.frame = viewRect }
    orderFront(nil)
    // reset to initial position after showing status message
    initPosition = !view.statusView.isHidden
    needsRedraw = false
    // voila !
  }

  func hide() {
    statusTimer.take()?.invalidate()
    toolTip.hide()
    orderOut(nil)
    maxSizeAttained = .zero
    IbeamRect = .zero
    isExpanded = false
    sectionNum = 0
  }

  // Main function to add attributes to text output from librime
  func showPanel(withPreedit preedit: String, selRange: NSRange, caretPos: Int?, candidateIndices: Range<Int>, highlightedCandidate: Int?, pageNum: Int, isLastPage: Bool, didCompose: Bool) {
    self.caretPos = caretPos
    self.pageNum = pageNum
    self.isLastPage = isLastPage
    functionButton = .VoidSymbol
    if !candidateIndices.isEmpty || !preedit.isEmpty {
      statusMessage = nil
      view.statusView.isHidden = true
      if view.statusContents.length > 0 {
        view.statusContents.deleteCharacters(in: NSRange(location: 0, length: view.statusContents.length))
      }
      if let timer: Timer = statusTimer.take(), timer.isValid {
        timer.invalidate()
      }
    } else {
      if let message = statusMessage.take() {
        showStatus(message: message)
      } else if !(statusTimer?.isValid ?? false) {
        hide()
      }
      return
    }

    let updateCandidates: Bool = needsRedraw || didCompose || self.candidateIndices != candidateIndices
    var rulerAttrsPreedit: NSParagraphStyle?
    let priorSize: NSSize = !view.candidateInfos.isEmpty || !view.preeditView.isHidden ? view.contentRect.size : .zero
    if candidateIndices.isEmpty || !updateCandidates, !preedit.isEmpty, view.preeditContents.length > 0 {
      rulerAttrsPreedit = view.preeditContents.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }
    if updateCandidates {
      view.candidateContents.deleteCharacters(in: NSRange(location: 0, length: view.candidateContents.length))
      if theme.lineLength.isNormal {
        maxSizeAttained.width = min(theme.lineLength, textWidthLimit)
      }
      self.candidateIndices = candidateIndices
    }

    // preedit
    if !preedit.isEmpty {
      view.preeditContents.setAttributedString(.init(string: preedit, attributes: theme.preeditAttrs))
      view.preeditContents.mutableString.append(rulerAttrsPreedit == nil ? .fullWidthSpace : "\t")
      if selRange.length > 0 {
        view.preeditContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: selRange)
        let padding: Double = (theme.preeditParagraphStyle.minimumLineHeight * 0.05).rounded(.up)
        if selRange.location > 0 {
          view.preeditContents.addAttribute(.kern, value: padding, range: NSRange(location: selRange.location - 1, length: 1))
        }
        if selRange.upperBound < view.preeditContents.length - 1 {
          view.preeditContents.addAttribute(.kern, value: padding, range: NSRange(location: selRange.upperBound - 1, length: 1))
        }
      }
      view.preeditContents.append(caretPos == nil || caretPos == 0 ? theme.symbolDeleteStroke! : theme.symbolDeleteFill!)
      // force caret to be rendered sideways, instead of uprights, in vertical orientation
      if isVertical, let caretPos = caretPos {
        view.preeditContents.addAttribute(.verticalGlyphForm, value: 0, range: NSRange(location: caretPos, length: 1))
      }
      if let rulerAttrsPreedit = rulerAttrsPreedit {
        view.preeditContents.addAttribute(.paragraphStyle, value: rulerAttrsPreedit, range: NSRange(location: 0, length: view.preeditContents.length))
      }

      if updateCandidates, candidateIndices.isEmpty {
        sectionNum = 0
      } else {
        view.setPreedit(hilitedPreeditRange: selRange)
      }
    } else if view.preeditContents.length > 0 {
      view.preeditContents.deleteCharacters(in: NSRange(location: 0, length: view.preeditContents.length))
    }

    if !updateCandidates {
      if view.hilitedCandidate != highlightedCandidate {
        highlightCandidate(highlightedCandidate)
      }
      let newSize: NSSize = view.contentRect.size
      needsRedraw |= priorSize != newSize
      show()
      return
    }

    // candidate items
    var candidateInfos: [SquirrelCandidateInfo] = []
    if !candidateIndices.isEmpty {
      candidateInfos.reserveCapacity(candidateIndices.count)
      for idx in 0 ..< candidateIndices.count {
        let col: Int = idx % theme.pageSize
        let candidate: NSMutableAttributedString = (idx / theme.pageSize != view.sectionNum ? theme.candidateDimmedTemplate! : idx == highlightedCandidate ? theme.candidateHilitedTemplate : theme.candidateTemplate).mutableCopy()
        // plug in enumerator, candidate text and comment into the template
        let enumRange: NSRange = candidate.mutableString.range(of: "%c")
        candidate.replaceCharacters(in: enumRange, with: theme.labels[col])

        var textRange: NSRange = candidate.mutableString.range(of: "%@")
        let text: String = inputController!.candidateTexts[idx + candidateIndices.lowerBound]
        candidate.replaceCharacters(in: textRange, with: text)

        let commentRange: NSRange = candidate.mutableString.range(of: "%s")
        let comment: String = inputController!.candidateComments[idx + candidateIndices.lowerBound]
        if !comment.isEmpty {
          candidate.replaceCharacters(in: commentRange, with: "\u{A0}" + comment)
        } else {
          candidate.deleteCharacters(in: commentRange)
        }
        // parse markdown and ruby annotation
        candidate.formatMarkDown()
        let annotationHeight: Double = candidate.annotateRuby(inRange: NSRange(location: 0, length: candidate.length), verticalOrientation: isVertical, maximumLength: textWidthLimit, scriptVariant: optionSwitcher.currentScriptVariant)
        if annotationHeight * 2 > theme.lineSpacing {
          updateAnnotationHeight(annotationHeight)
          candidate.addAttribute(.paragraphStyle, value: theme.candidateParagraphStyle, range: NSRange(location: 0, length: candidate.length))
          if idx > 0 {
            if isLinear {
              var isTruncated: Bool = candidateInfos[0].isTruncated
              var location: Int = candidateInfos[0].location
              for i in 1 ... idx {
                guard i == idx || candidateInfos[i].isTruncated != isTruncated else { continue }
                view.candidateContents.addAttribute(.paragraphStyle, value: isTruncated ? theme.truncatedParagraphStyle! : theme.candidateParagraphStyle, range: NSRange(location: location, length: candidateInfos[i - 1].upperBound - location))
                if i < idx {
                  isTruncated = candidateInfos[i].isTruncated
                  location = candidateInfos[i].location
                }
              }
            } else {
              view.candidateContents.addAttribute(.paragraphStyle, value: theme.candidateParagraphStyle, range: NSRange(location: 0, length: view.candidateContents.length))
            }
          }
        }
        // store final in-candidate locations of label, text, and comment
        textRange = candidate.mutableString.range(of: text)
        if idx > 0, col == 0, isLinear, !candidateInfos[idx - 1].isTruncated {
          view.candidateContents.mutableString.append("\n")
        }
        var candidateStart: Int = view.candidateContents.length
        view.candidateContents.append(candidate)
        // for linear layout, middle-truncate candidates that are longer than one line
        if isLinear, view.candidateView.blockRect(for: NSRange(location: candidateStart, length: candidate.length)).width > textWidthLimit - theme.fullWidth * (isTabular ? 3 : 2) {
          if col > 0, !candidateInfos[idx - 1].isTruncated {
            view.candidateContents.mutableString.insert("\n", at: candidateStart)
            candidateStart += 1
          }
          candidateInfos.append(SquirrelCandidateInfo(location: candidateStart, length: view.candidateContents.length - candidateStart, text: textRange.location, comment: textRange.upperBound, idx: idx, col: col, isTruncated: true))
          if idx < candidateIndices.count - 1 {
            view.candidateContents.mutableString.append("\n")
          }
          view.candidateContents.addAttribute(.paragraphStyle, value: theme.truncatedParagraphStyle!, range: NSRange(location: candidateStart, length: view.candidateContents.length - candidateStart))
        } else {
          if isLinear || idx < candidateIndices.count - 1 {
            // separator: linear = "\u3000\x1D"; tabular = "\u3000\t\x1D"; stacked = "\n"
            view.candidateContents.append(theme.separator)
          }
          candidateInfos.append(SquirrelCandidateInfo(location: candidateStart, length: candidate.length + (isTabular ? 3 : isLinear ? 2 : 0), text: textRange.location, comment: textRange.upperBound, idx: idx, col: col, isTruncated: false))
        }
      }

      // paging indication
      if isTabular || theme.showPaging {
        if isTabular {
          view.pagingContents.setAttributedString(isLocked ? theme.symbolLock! : isExpanded ? theme.symbolCompress! : theme.symbolExpand!)
        } else {
          let pageNumString: NSAttributedString = .init(string: "\(pageNum + 1)", attributes: theme.pagingAttrs)
          view.pagingContents.setAttributedString(isVertical ? pageNumString.horizontalInVerticalForms() : pageNumString)
        }
        if theme.showPaging {
          view.pagingContents.insert(pageNum > 0 ? theme.symbolBackFill! : theme.symbolBackStroke!, at: 0)
          view.pagingContents.mutableString.insert(.fullWidthSpace, at: 1)
          view.pagingContents.mutableString.append(.fullWidthSpace)
          view.pagingContents.append(isLastPage ? theme.symbolForwardStroke! : theme.symbolForwardFill!)
        }
      } else if view.pagingContents.length > 0 {
        view.pagingContents.deleteCharacters(in: NSRange(location: 0, length: view.pagingContents.length))
      }
    }

    view.estimateBounds(onScreen: _screen.visibleFrame, withPreedit: !preedit.isEmpty, candidates: candidateInfos, paging: !candidateIndices.isEmpty && (isTabular || theme.showPaging))
    let textWidth: Double = view.contentRect.width.clamp(min: maxSizeAttained.width, max: textWidthLimit)
    // right-align the backward delete symbol
    if !preedit.isEmpty, rulerAttrsPreedit == nil || rulerAttrsPreedit!.tabStops.first!.location < textWidth.nextDown {
      if rulerAttrsPreedit == nil {
        view.preeditContents.replaceCharacters(in: NSRange(location: view.preeditContents.length - 2, length: 1), with: "\t")
      }
      let rulerAttrs: NSMutableParagraphStyle = theme.preeditParagraphStyle.mutableCopy()
      rulerAttrs.tabStops = [NSTextTab(textAlignment: .right, location: textWidth)]
      view.preeditContents.addAttribute(.paragraphStyle, value: rulerAttrs, range: NSRange(location: 0, length: view.preeditContents.length))
    }
    if !isLinear, theme.showPaging {
      let rulerAttrsPaging: NSMutableParagraphStyle = theme.pagingParagraphStyle.mutableCopy()
      view.pagingContents.replaceCharacters(in: NSRange(location: 1, length: 1), with: "\t")
      view.pagingContents.replaceCharacters(in: NSRange(location: view.pagingContents.length - 2, length: 1), with: "\t")
      rulerAttrsPaging.tabStops = [NSTextTab(textAlignment: .center, location: (textWidth * 0.5).rounded()), NSTextTab(textAlignment: .right, location: textWidth)]
      view.pagingContents.addAttribute(.paragraphStyle, value: rulerAttrsPaging, range: NSRange(location: 0, length: view.pagingContents.length))
    }

    // text done!
    animationBehavior = .default
    view.drawView(withHilitedCandidate: highlightedCandidate, hilitedPreeditRange: selRange)

    let newSize: NSSize = view.contentRect.size
    needsRedraw |= priorSize != newSize
    show()
  }

  func updateStatus(long: String?, short: String?) {
    statusMessage = switch SquirrelTheme.current.statusMessageType {
    case .mixed: short ?? long
    case .long: long
    case .short: short ?? (long == nil ? nil : String(long!.first!)) }
  }

  private func showStatus(message: String) {
    let priorSize: NSSize = view.statusView.isHidden ? .zero : view.contentRect.size

    view.candidateContents.deleteCharacters(in: NSRange(location: 0, length: view.candidateContents.length))
    view.preeditContents.deleteCharacters(in: NSRange(location: 0, length: view.preeditContents.length))
    view.pagingContents.deleteCharacters(in: NSRange(location: 0, length: view.pagingContents.length))

    let attrString: NSAttributedString = .init(string: "\u{3000}\u{2002}" + message, attributes: theme.statusAttrs)
    view.statusContents.setAttributedString(attrString)
    view.estimateBounds(onScreen: _screen.visibleFrame, withPreedit: false, candidates: [], paging: false)

    // disable both `remember_size` and fixed lineLength for status messages
    maxSizeAttained = .zero
    statusTimer?.invalidate()
    animationBehavior = .utilityWindow
    view.drawView(withHilitedCandidate: nil, hilitedPreeditRange: NSRange(location: NSNotFound, length: 0))

    let newSize: NSSize = view.contentRect.size
    needsRedraw |= priorSize != newSize
    show()
    statusTimer = .scheduledTimer(withTimeInterval: Self.showStatusDuration, repeats: false) { _ in MainActor.assumeIsolated { self.hide() } }
  }

  private func updateAnnotationHeight(_ height: Double) {
    SquirrelTheme.light.updateAnnotationHeight(height)
    if #available(macOS 10.14, *) {
      SquirrelTheme.dark.updateAnnotationHeight(height)
    }
    view.candidateView.defaultParagraphStyle = SquirrelTheme.current.candidateParagraphStyle
  }

  func getLocked() {
    guard SquirrelTheme.current.isTabular else { return }
    let userConfig: SquirrelConfig = .init(.user)
    view.isLocked = userConfig.boolValue(for: "var/option/_isLockedTabular") ?? false
    if view.isLocked { view.isExpanded = userConfig.boolValue(for: "var/option/_isExpandedTabular") ?? false }
    userConfig.close()
    view.sectionNum = 0
  }

  func updateScriptVariant() {
    SquirrelTheme.light.updateScriptVariant(optionSwitcher.currentScriptVariant)
    if #available(macOS 10.14, *) {
      SquirrelTheme.dark.updateScriptVariant(optionSwitcher.currentScriptVariant)
    }
  }
}  // SquirrelPanel
