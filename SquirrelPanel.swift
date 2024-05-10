import AppKit
import Cocoa
import QuartzCore

let kDefaultCandidateFormat: String = "%c. %@"
let kTipSpecifier: String = "%s"
let kFullWidthSpace: String = "　"
let kShowStatusDuration: TimeInterval = 2.0
let kBlendedBackgroundColorFraction: Double  = 0.2
let kDefaultFontSize: Double  = 24
let kOffsetGap: Double = 5

func clamp<T: Comparable>(_ x: T, _ min: T, _ max: T) -> T {
  let y = x < min ? min : x
  return y > max ? max : y
}

extension NSBezierPath {

  var quartzPath: CGPath? {
    get {
      if #available(macOS 14.0, *) {
        return self.cgPath
      }
      if (elementCount > 0) {
        // Need to begin a path here.
        let path: CGMutablePath = CGMutablePath()
        // Then draw the path elements.
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        for i in 0..<elementCount {
          switch (element(at: i, associatedPoints: points)) {
          case .moveTo:
            path.move(to: points[0])
            break
          case .lineTo:
            path.addLine(to: points[0])
            break
          case .cubicCurveTo:
            path.addCurve(to: points[0], control1: points[1], control2: points[2])
            break
          case .quadraticCurveTo:
            path.addQuadCurve(to: points[0], control: points[1])
            break
          case .closePath:
            path.closeSubpath()
            break
          default:
            break
          }
        }
        return path.copy()
      }
      return nil
    }
  }

}  // NSBezierPath (BezierPathQuartzUtilities)


extension NSMutableAttributedString {

  private func superscriptionRange(_ range: NSRange) {
    enumerateAttribute(.font, in: range, options: [.longestEffectiveRangeNotRequired])
    { (value: Any?, subRange: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
      if let oldFont = value as? NSFont {
        let newFont = NSFont(descriptor: oldFont.fontDescriptor,
                             size: floor(oldFont.pointSize * 0.55))
        addAttributes([.font: newFont!,
                       kCTBaselineClassAttributeName as NSAttributedString.Key: kCTBaselineClassIdeographicCentered,
                       NSAttributedString.Key.superscript: 1],
                      range: subRange)
      }
    }
  }

  private func subscriptionRange(_ range: NSRange) {
    enumerateAttribute(.font, in: range, options: [.longestEffectiveRangeNotRequired])
    { (value: Any?, subRange: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
      if let oldFont = value as? NSFont {
        let newFont = NSFont(descriptor: oldFont.fontDescriptor,
                             size: floor(oldFont.pointSize * 0.55))
        addAttributes([.font: newFont!,
                       kCTBaselineClassAttributeName as NSAttributedString.Key: kCTBaselineClassIdeographicCentered,
                       NSAttributedString.Key.superscript: -1],
                      range: subRange)
      }
    }
  }

  static let markDownPattern: String =
    "((\\*{1,2}|\\^|~{1,2})|((?<=\\b)_{1,2})|<(b|strong|i|em|u|sup|sub|s)>)(.+?)(\\2|\\3(?=\\b)|<\\/\\4>)"

  func formatMarkDown() {
    if let regex = try? NSRegularExpression(pattern: NSMutableAttributedString.markDownPattern,
                                            options: [.useUnicodeWordBoundaries]) {
      var offset: Int = 0
      regex.enumerateMatches(in: string,
                             options: [],
                             range: NSMakeRange(0, length),
                             using: { (result: NSTextCheckingResult?,
                                       flags: NSRegularExpression.MatchingFlags,
                                       stop: UnsafeMutablePointer<ObjCBool>) in
        if let adjusted = result?.adjustingRanges(offset: offset) {
          let tag: String! = self.mutableString.substring(with: adjusted.range(at: 1))
          if (tag == "**") || (tag == "__") ||
              (tag == "<b>") || (tag == "<strong>") {
            applyFontTraits(.boldFontMask, range:adjusted.range(at: 5))
          } else if (tag == "*") || (tag == "_") ||
                      (tag == "<i>") || (tag == "<em>") {
            applyFontTraits(.italicFontMask, range:adjusted.range(at: 5))
          } else if (tag == "<u>") {
            addAttribute(NSAttributedString.Key.underlineStyle,
                         value: NSUnderlineStyle.single.rawValue,
                         range: adjusted.range(at: 5))
          } else if (tag == "~~") || (tag == "<s>") {
            addAttribute(NSAttributedString.Key.strikethroughStyle,
                         value: NSUnderlineStyle.single.rawValue,
                         range: adjusted.range(at: 5))
          } else if (tag == "^") || (tag == "<sup>") {
            superscriptionRange(adjusted.range(at: 5))
          } else if (tag == "~") || (tag == "<sub>") {
            subscriptionRange(adjusted.range(at: 5))
          }
          deleteCharacters(in: adjusted.range(at: 6))
          deleteCharacters(in: adjusted.range(at: 1))
          offset -= adjusted.range(at: 6).length + adjusted.range(at: 1).length
        }
     })
     if (offset != 0) { // repeat until no more nested markdown
       formatMarkDown()
     }
    }
  }

  static let rubyPattern: String = "(\u{FFF9}\\s*)(\\S+?)(\\s*\u{FFFA}(.+?)\u{FFFB})"

  func annotateRuby(inRange range: NSRange,
                    verticalOrientation isVertical: Boolean,
                    maximumLength maxLength: Double,
                    scriptVariant: String) -> Double {
    var rubyLineHeight: Double = 0.0
    if let regex = try? NSRegularExpression(pattern: NSMutableAttributedString.rubyPattern, options: []) {
      regex.enumerateMatches(in: string,
                             options: [],
                             range: range,
                             using: { (result: NSTextCheckingResult?,
                                       flags: NSRegularExpression.MatchingFlags,
                                       stop: UnsafeMutablePointer<ObjCBool>) in
        let baseRange: NSRange = (result!.range(at: 2))
        // no ruby annotation if the base string includes line breaks
        if (attributedSubstring(from: NSMakeRange(0, NSMaxRange(baseRange))).size().width > maxLength - 0.1) {
          deleteCharacters(in: NSMakeRange(NSMaxRange(result!.range) - 1, 1))
          deleteCharacters(in: NSMakeRange(result!.range(at: 3).location, 1))
          deleteCharacters(in: NSMakeRange(result!.range(at: 1).location, 1))
        } else {
          /* base string must use only one font so that all fall within one glyph run and
             the ruby annotation is aligned with no duplicates */
          var baseFont: NSFont! = attribute(NSAttributedString.Key.font,
                                            at: baseRange.location, effectiveRange:nil) as? NSFont
          baseFont = CTFontCreateForStringWithLanguage(baseFont, mutableString,
                                                       CFRangeMake(baseRange.location, baseRange.length),
                                                       scriptVariant as CFString)
          addAttribute(NSAttributedString.Key.font, value: baseFont!, range: baseRange)

          let rubyScale: Double = 0.5
          let rubyString = self.mutableString.substring(with: result!.range(at: 4)) as CFString
          let height: Double = isVertical ? (baseFont.vertical.ascender - baseFont.vertical.descender)
                                          : (baseFont.ascender - baseFont.descender)
          rubyLineHeight = ceil(height * rubyScale)
          let rubyText = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(
            capacity: Int(CTRubyPosition.count.rawValue))
          rubyText[Int(CTRubyPosition.before.rawValue)] = Unmanaged.passUnretained(rubyString)
          rubyText[Int(CTRubyPosition.after.rawValue)] = nil
          rubyText[Int(CTRubyPosition.interCharacter.rawValue)] = nil
          rubyText[Int(CTRubyPosition.inline.rawValue)] = nil
          let rubyAnnotation: CTRubyAnnotation = CTRubyAnnotationCreate(
            .distributeSpace, .none, rubyScale, rubyText)

          if #available(macOS 12.0, *) {
          } else {
            // use U+008B as placeholder for line-forward spaces in case ruby is wider than base
            replaceCharacters(in: NSMakeRange(NSMaxRange(baseRange), 0),
                              with: String(format:"%C", 0x8B))
          }
          addAttributes([kCTRubyAnnotationAttributeName as NSAttributedString.Key: rubyAnnotation,
                         NSAttributedString.Key.font: baseFont!,
                         NSAttributedString.Key.verticalGlyphForm: isVertical],
                        range: baseRange)
        }
      })
      mutableString.replaceOccurrences(of: "[\u{FFF9}-\u{FFFB}]", with: "",
                                       options: .regularExpression, range: range)
    }
    return ceil(rubyLineHeight)
  }

}  // NSMutableAttributedString (NSMutableAttributedStringMarkDownFormatting)


extension NSAttributedString {

  func horizontalInVerticalForms() -> NSAttributedString! {
    var attrs = attributes(at: 0, effectiveRange: nil)
    let font: NSFont! = attrs[NSAttributedString.Key.font] as? NSFont
    let height: Double = ceil(font.ascender - font.descender)
    let width: Double = max(height, ceil(size().width))
    let image: NSImage! = NSImage(
      size: NSMakeSize(height, width), flipped:true,
      drawingHandler:{ (dstRect: NSRect) in
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = true
        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = NSAffineTransform()
        transform.translateX(by: NSWidth(dstRect) * 0.5, yBy: NSHeight(dstRect) * 0.5)
        transform.rotate(byDegrees: -90)
        transform.concat()
        let origin: CGPoint = CGPointMake(0 - self.size().width / width * NSHeight(dstRect) * 0.5, 0 - NSWidth(dstRect) * 0.5)
        self.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
        return true
      })
    image.resizingMode = .stretch
    image.size = NSMakeSize(height, height)
    let attm: NSTextAttachment! = NSTextAttachment()
    attm.image = image
    attm.bounds = NSMakeRect(0, font.descender, height, height)
    attrs[NSAttributedString.Key.attachment] = attm
    return NSAttributedString(string: String(unichar(NSTextAttachment.character)), attributes: attrs)
  }

}  // NSAttributedString (NSAttributedStringHorizontalInVerticalForms)


extension NSColorSpace {

  static var labColorSpace: NSColorSpace = {
    let whitePoint: [CGFloat] = [0.950489, 1.0, 1.088840]
    let blackPoint: [CGFloat] = [0.0, 0.0, 0.0]
    let range: [CGFloat] = [-127.0, 127.0, -127.0, 127.0]
    let colorSpaceLab = CGColorSpace(labWhitePoint: whitePoint,
                                     blackPoint: blackPoint,
                                     range: range)!
    return NSColorSpace(cgColorSpace: colorSpaceLab)!
  }()

}  // NSColorSpace

@frozen enum ColorInversionExtent: Int {
  case standard = 0
  case augmented = 1
  case moderate = -1
}

extension NSColor {

  var lStarComponent: Double? {
    var lStar: Double? = 0.0
    var aStar: Double? = nil
    var bStar: Double? = nil
    var alpha: Double? = nil
    getLAB(lStar: &lStar, aStar: &aStar, bStar: &bStar, alpha: &alpha)
    return lStar
  }

  var aStarComponent:  Double? { // Green-Red
    var lStar: Double? = nil
    var aStar: Double? = 0.0
    var bStar: Double? = nil
    var alpha: Double? = nil
    getLAB(lStar: &lStar, aStar: &aStar, bStar: &bStar, alpha: &alpha)
    return aStar
  }

  var bStarComponent:  Double? { // Blue-Yellow
    var lStar: Double? = nil
    var aStar: Double? = nil
    var bStar: Double? = 0.0
    var alpha: Double? = nil
    getLAB(lStar: &lStar, aStar: &aStar, bStar: &bStar, alpha: &alpha)
    return bStar
  }

  class func colorWithLabLuminance(luminance: Double,
                                   aGnRd: Double,
                                   bBuYl: Double,
                                   alpha: Double) -> NSColor {
    let lum: Double = clamp(luminance, 0.0, 100.0)
    let green_red: Double = clamp(aGnRd, -127.0, 127.0)
    let blue_yellow: Double = clamp(bBuYl, -127.0, 127.0)
    let opaque: Double = clamp(alpha, 0.0, 1.0)
    let components: [CGFloat] = [lum, green_red, blue_yellow, opaque]
    return NSColor(colorSpace: NSColorSpace.labColorSpace,
                   components: components, count: 4)
  }

  func getLAB(lStar: inout Double?,
              aStar: inout Double?,
              bStar: inout Double?,
              alpha: inout Double?) {
    if let componentBased = self.usingType(.componentBased)?.usingColorSpace(NSColorSpace.labColorSpace) {
      var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
      componentBased.getComponents(&components)
      if (lStar != nil) {
        lStar = components[0] / 100.0
      }
      if (aStar != nil) {
        aStar = components[1] / 127.0 // green-red
      }
      if (bStar != nil) {
        bStar = components[2] / 127.0 // blue-yellow
      }
      if (alpha != nil) {
        alpha = components[3]
      }
    }
  }

  func invertLuminance(toExtent extent: ColorInversionExtent) -> NSColor {
    if let componentBased = self.usingType(.componentBased)?.usingColorSpace(NSColorSpace.labColorSpace) {
      var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
      componentBased.getComponents(&components)
      switch (extent) {
      case .augmented:
        components[0] = 100.0 - components[0]
        break
      case .moderate:
        components[0] = 80.0 - components[0] * 0.6
        break
      case .standard:
        components[0] = 90.0 - components[0] * 0.8
        break
      }
      let invertedColor: NSColor = NSColor(colorSpace: NSColorSpace.labColorSpace,
                                           components: components, count: 4)
      return invertedColor.usingColorSpace(colorSpace)!
    } else {
      return self
    }
  }

  // Semantic Colors

  static var accentColor: NSColor {
    get {
      if #available(macOS 10.14, *) {
        return NSColor.controlAccentColor
      } else {
        return NSColor(for: NSColor.currentControlTint)
      }
    }
  }

  var hooverColor: NSColor {
    get {
      if #available(macOS 10.14, *) {
        return withSystemEffect(.rollover)
      } else {
        return NSAppearance.current.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? highlight(withLevel: 0.3)! : shadow(withLevel: 0.3)!
      }
    }
  }

  var disabledColor: NSColor {
    get {
      if #available(macOS 10.14, *) {
        return withSystemEffect(.disabled)
      } else {
        return NSAppearance.current.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? shadow(withLevel: 0.3)! : highlight(withLevel: 0.3)!
      }
    }
  }

  func blendWithColor(_ color: NSColor, ofFraction fraction: CGFloat) -> NSColor? {
    let alpha: CGFloat = self.alphaComponent * color.alphaComponent
    let opaqueColor: NSColor = self.withAlphaComponent(1.0).blended(
      withFraction: fraction, of: color.withAlphaComponent(1.0))!
    return opaqueColor.withAlphaComponent(alpha)
  }

}  // NSColor

// MARK: - Color scheme and other user configurations

@objc @frozen enum SquirrelAppearance: Int {
  case light = 0
  case dark = 1
}

@frozen enum SquirrelStatusMessageType {
  case mixed
  case short
  case long
}

func blendColors(foreground: NSColor!,
                 background: NSColor?) -> NSColor! {
  return foreground.blended(withFraction: kBlendedBackgroundColorFraction,
                            of: background ?? NSColor.lightGray)!.withAlphaComponent(foreground.alphaComponent)
}

func getFontDescriptor(fullname: String!) -> NSFontDescriptor? {
  if (fullname?.isEmpty ?? true) {
    return nil
  }
  let fontNames: [String] = fullname.components(separatedBy: ",")
  var validFontDescriptors: [NSFontDescriptor] = []
  for fontName: String in fontNames {
    if let font = NSFont(name: fontName.trimmingCharacters(in: .whitespacesAndNewlines), size: 0.0) {
      // If the font name is not valid, NSFontDescriptor will still create something for us.
      // However, when we draw the actual text, Squirrel will crash if there is any font descriptor
      // with invalid font name.
      let fontDescriptor = font.fontDescriptor
      let UIFontDescriptor = fontDescriptor.withSymbolicTraits(.UIOptimized)
      validFontDescriptors.append(NSFont(descriptor: UIFontDescriptor, size: 0.0) != nil ? UIFontDescriptor : fontDescriptor)
    }
  }
  if (validFontDescriptors.count == 0) {
    return nil
  }
  let initialFontDescriptor = validFontDescriptors[0]
  var fallbackDescriptors = validFontDescriptors.suffix(validFontDescriptors.count - 1)
  fallbackDescriptors.append(NSFontDescriptor(name:"AppleColorEmoji", size:0.0))
  return initialFontDescriptor.addingAttributes(
    [NSFontDescriptor.AttributeName.cascadeList: fallbackDescriptors as Any])
}

func getLineHeight(font: NSFont!,
                               vertical: Boolean) -> Double! {
  var lineHeight: Double = ceil(vertical ? font.vertical.ascender - font.vertical.descender : font.ascender - font.descender)
  let fallbackList: [NSFontDescriptor] = font.fontDescriptor.fontAttributes[.cascadeList] as? [NSFontDescriptor] ?? []
  for fallback in fallbackList {
    let fallbackFont = NSFont(descriptor: fallback, size: font.pointSize)!
    lineHeight = max(lineHeight, ceil(vertical ? fallbackFont.vertical.ascender - fallbackFont.vertical.descender
                                               : fallbackFont.ascender - fallbackFont.descender))
  }
  return lineHeight
}

func updateCandidateListLayout(isLinear: inout Boolean,
                               isTabular: inout Boolean,
                               config: SquirrelConfig,
                               prefix: String) {
  let candidateListLayout: String = config.getStringForOption(prefix + "/candidate_list_layout") ?? ""
  if (candidateListLayout.caseInsensitiveCompare("stacked") == .orderedSame) {
    isLinear = false
    isTabular = false
  } else if (candidateListLayout.caseInsensitiveCompare("linear") == .orderedSame) {
    isLinear = true
    isTabular = false
  } else if (candidateListLayout.caseInsensitiveCompare("tabular") == .orderedSame) {
    // `tabular` is a derived layout of `linear`; tabular implies linear
    isLinear = true
    isTabular = true
  } else if let horizontal = config.getOptionalBoolForOption(prefix + "/horizontal") {
    // Deprecated. Not to be confused with text_orientation: horizontal
    isLinear = horizontal
    isTabular = false
  }
}

func updateTextOrientation(isVertical: inout Boolean,
                           config: SquirrelConfig,
                           prefix: String) {
  let textOrientation: String = config.getStringForOption(prefix + "/text_orientation") ?? ""
  if (textOrientation.caseInsensitiveCompare("horizontal") == .orderedSame) {
    isVertical = false
  } else if (textOrientation.caseInsensitiveCompare("vertical") == .orderedSame) {
    isVertical = true
  } else if let vertical = config.getOptionalBoolForOption(prefix + "/vertical") {
    isVertical = vertical
  }
}

// functions for post-retrieve processing
func positive(param: Double) -> Double { return max(0.0, param) }
func pos_round(param: Double) -> Double { return round(max(0.0, param)) }
func pos_ceil(param: Double) -> Double { return ceil(max(0.0, param)) }
func clamp_uni(param: Double) -> Double { return min(1.0, max(0.0, param)) }

class SquirrelTheme: NSObject {

  private var _backColor: NSColor = NSColor.controlBackgroundColor
  var backColor: NSColor { get { return _backColor } }
  private var _preeditForeColor: NSColor = NSColor.textColor
  var preeditForeColor: NSColor { get { return _preeditForeColor } }
  private var _textForeColor: NSColor = NSColor.controlTextColor
  var textForeColor: NSColor { get { return _textForeColor } }
  private var _commentForeColor: NSColor = NSColor.secondaryLabelColor
  var commentForeColor: NSColor { get { return _commentForeColor } }
  private var _labelForeColor: NSColor = NSColor.accentColor
  var labelForeColor: NSColor { get { return _labelForeColor } }
  private var _hilitedPreeditForeColor: NSColor = NSColor.selectedTextColor
  var hilitedPreeditForeColor: NSColor { get { return _hilitedPreeditForeColor } }
  private var _hilitedTextForeColor: NSColor = NSColor.selectedMenuItemTextColor
  var hilitedTextForeColor: NSColor { get { return _hilitedTextForeColor } }
  private var _hilitedCommentForeColor: NSColor = NSColor.alternateSelectedControlTextColor
  var hilitedCommentForeColor: NSColor { get { return _hilitedCommentForeColor } }
  private var _hilitedLabelForeColor: NSColor = NSColor.alternateSelectedControlTextColor
  var hilitedLabelForeColor: NSColor { get { return _hilitedLabelForeColor } }
  private var _dimmedLabelForeColor: NSColor?
  var dimmedLabelForeColor: NSColor? { get { return _dimmedLabelForeColor } }
  private(set) var _hilitedCandidateBackColor: NSColor?
  var hilitedCandidateBackColor: NSColor? { get { return _hilitedCandidateBackColor } }
  private var _hilitedPreeditBackColor: NSColor?
  var hilitedPreeditBackColor: NSColor? { get { return _hilitedPreeditBackColor } }
  private var _preeditBackColor: NSColor?
  var preeditBackColor: NSColor? { get { return _preeditBackColor } }
  private var _borderColor: NSColor?
  var borderColor: NSColor? { get { return _borderColor } }
  private var _backImage: NSImage?
  var backImage: NSImage? { get { return _backImage } }

  private var _borderInsets: NSSize = NSZeroSize
  var borderInsets: NSSize { get { return _borderInsets } }
  private var _cornerRadius: Double = 0
  var cornerRadius: Double { get { return _cornerRadius } }
  private var _hilitedCornerRadius: Double = 0
  var hilitedCornerRadius: Double { get { return _hilitedCornerRadius } }
  private var _fullWidth: Double
  var fullWidth: Double { get { return _fullWidth } }
  private var _lineSpacing: Double = 0
  var lineSpacing: Double { get { return _lineSpacing } }
  private var _preeditSpacing: Double = 0
  var preeditSpacing: Double { get { return _preeditSpacing } }
  private var _opacity: Double = 1
  var opacity: Double { get { return _opacity } }
  private var _lineLength: Double = 0
  var lineLength: Double { get { return _lineLength } }
  private var _translucency: Float = 0
  var translucency: Float { get { return _translucency } }

  private var _showPaging: Boolean = false
  var showPaging: Boolean { get { return _showPaging } }
  private var _rememberSize: Boolean = false
  var rememberSize: Boolean { get { return _rememberSize } }
  private var _tabular: Boolean = false
  var tabular: Boolean { get { return _tabular } }
  private var _linear: Boolean = false
  var linear: Boolean { get { return _linear } }
  private var _vertical: Boolean = false
  var vertical: Boolean { get { return _vertical } }
  private var _inlinePreedit: Boolean = false
  var inlinePreedit: Boolean { get { return _inlinePreedit } }
  private var _inlineCandidate: Boolean = true
  var inlineCandidate: Boolean { get { return _inlineCandidate } }

  private var _textAttrs: [NSAttributedString.Key : Any]
  var textAttrs: [NSAttributedString.Key : Any] { get { return _textAttrs } }
  private var _labelAttrs: [NSAttributedString.Key : Any]
  var labelAttrs: [NSAttributedString.Key : Any] { get { return _labelAttrs } }
  private var _commentAttrs: [NSAttributedString.Key : Any]
  var commentAttrs: [NSAttributedString.Key : Any] { get { return _commentAttrs } }
  private var _preeditAttrs: [NSAttributedString.Key : Any]
  var preeditAttrs: [NSAttributedString.Key : Any] { get { return _preeditAttrs } }
  private var _pagingAttrs: [NSAttributedString.Key : Any]
  var pagingAttrs: [NSAttributedString.Key : Any] { get { return _pagingAttrs } }
  private var _statusAttrs: [NSAttributedString.Key : Any]
  var statusAttrs: [NSAttributedString.Key : Any] { get { return _statusAttrs } }

  private var _candidateParagraphStyle: NSParagraphStyle
  var candidateParagraphStyle: NSParagraphStyle { get { return _candidateParagraphStyle } }
  private var _preeditParagraphStyle: NSParagraphStyle
  var preeditParagraphStyle: NSParagraphStyle { get { return _preeditParagraphStyle } }
  private var _statusParagraphStyle: NSParagraphStyle
  var statusParagraphStyle: NSParagraphStyle { get { return _statusParagraphStyle } }
  private var _pagingParagraphStyle: NSParagraphStyle
  var pagingParagraphStyle: NSParagraphStyle { get { return _pagingParagraphStyle } }
  private var _truncatedParagraphStyle: NSParagraphStyle?
  var truncatedParagraphStyle: NSParagraphStyle? { get { return _truncatedParagraphStyle } }

  private var _separator: NSAttributedString
  var separator: NSAttributedString { get { return _separator } }
  private var _symbolDeleteFill: NSAttributedString?
  var symbolDeleteFill: NSAttributedString? { get { return _symbolDeleteFill } }
  private var _symbolDeleteStroke: NSAttributedString?
  var symbolDeleteStroke: NSAttributedString? { get { return _symbolDeleteStroke } }
  private var _symbolBackFill: NSAttributedString?
  var symbolBackFill: NSAttributedString? { get { return _symbolBackFill } }
  private var _symbolBackStroke: NSAttributedString?
  var symbolBackStroke: NSAttributedString? { get { return _symbolBackStroke } }
  private var _symbolForwardFill: NSAttributedString?
  var symbolForwardFill: NSAttributedString? { get { return _symbolForwardFill } }
  private var _symbolForwardStroke: NSAttributedString?
  var symbolForwardStroke: NSAttributedString? { get { return _symbolForwardStroke } }
  private var _symbolCompress: NSAttributedString?
  var symbolCompress: NSAttributedString? { get { return _symbolCompress } }
  private var _symbolExpand: NSAttributedString?
  var symbolExpand: NSAttributedString? { get { return _symbolExpand } }
  private var _symbolLock: NSAttributedString?
  var symbolLock: NSAttributedString? { get { return _symbolLock } }

  private var _labels: [String] = ["１", "２", "３", "４", "５"]
  var labels: [String] { get {return _labels } }
  private var _candidateTemplate: NSAttributedString = NSAttributedString(string: kDefaultCandidateFormat)
  var candidateTemplate: NSAttributedString { get { return _candidateTemplate } }
  private var _candidateHilitedTemplate: NSAttributedString = NSAttributedString(string: kDefaultCandidateFormat)
  var candidateHilitedTemplate: NSAttributedString { get { return _candidateHilitedTemplate } }
  private var _candidateDimmedTemplate: NSAttributedString?
  var candidateDimmedTemplate: NSAttributedString? { get { return _candidateDimmedTemplate } }
  private var _selectKeys: String = "12345"
  var selectKeys: String { get { return _selectKeys } }
  private var _candidateFormat: String = kDefaultCandidateFormat
  var candidateFormat: String { get { return _candidateFormat } }
  private var _scriptVariant: String = "zh"
  var scriptVariant: String { get { return _scriptVariant } }
  private var _statusMessageType: SquirrelStatusMessageType = .mixed
  var statusMessageType: SquirrelStatusMessageType { get { return _statusMessageType } }
  private var _pageSize: Int = 5
  var pageSize: Int { get { return _pageSize } }
  private var _appearance: SquirrelAppearance
  var appearance: SquirrelAppearance { get { return _appearance } }

  init(appearance: SquirrelAppearance) {
    _appearance = appearance

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

    _candidateParagraphStyle = candidateParagraphStyle
    _preeditParagraphStyle = preeditParagraphStyle
    _pagingParagraphStyle = pagingParagraphStyle
    _statusParagraphStyle = statusParagraphStyle

    let userFont: NSFont! = NSFont(descriptor: getFontDescriptor(fullname:NSFont.userFont(ofSize: 0.0)!.fontName)!,
                                   size: kDefaultFontSize)
    let userMonoFont: NSFont! = NSFont(descriptor: getFontDescriptor(fullname:NSFont.userFixedPitchFont(ofSize: 0.0)!.fontName)!,
                                       size: kDefaultFontSize)
    let monoDigitFont: NSFont! = NSFont.monospacedDigitSystemFont(ofSize: kDefaultFontSize, weight: .regular)

    _textAttrs = [:]
    _textAttrs[.foregroundColor] = NSColor.controlTextColor
    _textAttrs[.font] = userFont
    // Use left-to-right embedding to prevent right-to-left text from changing the layout of the candidate.
    _textAttrs[.writingDirection] = [0]

    _labelAttrs = _textAttrs
    _labelAttrs[.foregroundColor] = NSColor.accentColor
    _labelAttrs[.font] = userMonoFont

    _commentAttrs = [:]
    _commentAttrs[.foregroundColor] = NSColor.secondaryLabelColor
    _commentAttrs[.font] = userFont

    _preeditAttrs = [:]
    _preeditAttrs[.foregroundColor] = NSColor.textColor
    _preeditAttrs[.font] = userFont
    _preeditAttrs[.ligature] = 0
    _preeditAttrs[.paragraphStyle] = preeditParagraphStyle

    _pagingAttrs = [:]
    _pagingAttrs[.font] = monoDigitFont
    _pagingAttrs[.foregroundColor] = NSColor.controlTextColor
    _pagingAttrs[.paragraphStyle] = pagingParagraphStyle

    _statusAttrs = _commentAttrs
    _statusAttrs[.paragraphStyle] = statusParagraphStyle

    _separator = NSAttributedString(string: "\n", attributes: [.font: userFont!])
    _fullWidth = ceil(userFont.advancement(forCGGlyph: CGGlyph(unichar(0x3000))).width)

    super.init()
    updateCandidateFormat(forAttributesOnly: false)
    updateSeperatorAndSymbolAttrs()
  }

  override convenience init() {
    self.init(appearance: .light)
  }

  private func updateSeperatorAndSymbolAttrs() {
    var sepAttrs: [NSAttributedString.Key : Any] = commentAttrs
    sepAttrs[NSAttributedString.Key.verticalGlyphForm] = false
    sepAttrs[NSAttributedString.Key.kern] = 0.0
    _separator = NSAttributedString(string: linear ? (tabular ? "\u{3000}\t\u{1D}" : "\u{3000}\u{1D}") : "\n",
                                    attributes: sepAttrs)
    // Symbols for function buttons
    let attmCharacter: String = String(NSTextAttachment.character)

    let attmDeleteFill: NSTextAttachment = NSTextAttachment()
    attmDeleteFill.image = NSImage(named: "Symbols/delete.backward.fill")
    var attrsDeleteFill: [NSAttributedString.Key : Any]! = preeditAttrs
    attrsDeleteFill[NSAttributedString.Key.attachment] = attmDeleteFill
    attrsDeleteFill[NSAttributedString.Key.verticalGlyphForm] = false
    _symbolDeleteFill = NSAttributedString(string: attmCharacter, attributes: attrsDeleteFill)

    let attmDeleteStroke: NSTextAttachment = NSTextAttachment()
    attmDeleteStroke.image = NSImage(named: "Symbols/delete.backward")
    var attrsDeleteStroke: [NSAttributedString.Key : Any]! = preeditAttrs
    attrsDeleteStroke[NSAttributedString.Key.attachment] = attmDeleteStroke
    attrsDeleteStroke[NSAttributedString.Key.verticalGlyphForm] = false
    _symbolDeleteStroke = NSAttributedString(string: attmCharacter, attributes: attrsDeleteStroke)

    if (tabular) {
      let attmCompress: NSTextAttachment = NSTextAttachment()
      attmCompress.image = NSImage(named: "Symbols/rectangle.compress.vertical")
      var attrsCompress: [NSAttributedString.Key : Any]! = pagingAttrs
      attrsCompress[NSAttributedString.Key.attachment] = attmCompress
      _symbolCompress = NSAttributedString(string: attmCharacter, attributes: attrsCompress)

      let attmExpand:NSTextAttachment = NSTextAttachment()
      attmExpand.image = NSImage(named: "Symbols/rectangle.expand.vertical")
      var attrsExpand:[NSAttributedString.Key : Any]! = pagingAttrs
      attrsExpand[NSAttributedString.Key.attachment] = attmExpand
      _symbolExpand = NSAttributedString(string: attmCharacter, attributes: attrsExpand)

      let attmLock: NSTextAttachment = NSTextAttachment()
      attmLock.image = NSImage(named: String(format: "Symbols/lock%@.fill", vertical ? ".vertical" : ""))
      var attrsLock: [NSAttributedString.Key : Any]! = pagingAttrs
      attrsLock[NSAttributedString.Key.attachment] = attmLock
      _symbolLock = NSAttributedString(string: attmCharacter, attributes: attrsLock)
    } else {
      _symbolCompress = nil
      _symbolExpand = nil
      _symbolLock = nil
    }

    if (showPaging) {
      let attmBackFill: NSTextAttachment = NSTextAttachment()
      attmBackFill.image = NSImage(named: String(format: "Symbols/chevron.%@.circle.fill", linear ? "up" : "left"))
      var attrsBackFill: [NSAttributedString.Key : Any]! = pagingAttrs
      attrsBackFill[NSAttributedString.Key.attachment] = attmBackFill
      _symbolBackFill = NSAttributedString(string: attmCharacter, attributes: attrsBackFill)

      let attmBackStroke:NSTextAttachment = NSTextAttachment()
      attmBackStroke.image = NSImage(named: String(format: "Symbols/chevron.%@.circle", linear ? "up" : "left"))
      var attrsBackStroke: [NSAttributedString.Key : Any]! = pagingAttrs
      attrsBackStroke[NSAttributedString.Key.attachment] = attmBackStroke
      _symbolBackStroke = NSAttributedString(string: attmCharacter, attributes: attrsBackStroke)

      let attmForwardFill:NSTextAttachment = NSTextAttachment()
      attmForwardFill.image = NSImage(named: String(format: "Symbols/chevron.%@.circle.fill", linear ? "down" : "right"))
      var attrsForwardFill:[NSAttributedString.Key : Any]! = pagingAttrs
      attrsForwardFill[NSAttributedString.Key.attachment] = attmForwardFill
      _symbolForwardFill = NSAttributedString(string: attmCharacter, attributes: attrsForwardFill)

      let attmForwardStroke: NSTextAttachment = NSTextAttachment()
      attmForwardStroke.image = NSImage(named: String(format: "Symbols/chevron.%@.circle", linear ? "down" : "right"))
      var attrsForwardStroke: [NSAttributedString.Key : Any]! = pagingAttrs
      attrsForwardStroke[NSAttributedString.Key.attachment] = attmForwardStroke
      _symbolForwardStroke = NSAttributedString(string: attmCharacter, attributes: attrsForwardStroke)
    } else {
      _symbolBackFill = nil
      _symbolBackStroke = nil
      _symbolForwardFill = nil
      _symbolForwardStroke = nil
    }
  }

  func updateLabelsWithConfig(_ config: SquirrelConfig,
                              directUpdate update: Boolean) {
    let menuSize: Int = config.getIntForOption("menu/page_size") ?? 5
    var labels: [String] = []
    var selectKeys: String? = config.getStringForOption("menu/alternative_select_keys")
    let selectLabels: [String] = config.getListForOption("menu/alternative_select_labels") ?? []
    if (!selectLabels.isEmpty) {
      for i in 0..<menuSize {
        labels.append(selectLabels[i])
      }
    }
    if (selectKeys != nil) {
      if (selectLabels.isEmpty) {
        let keyCaps: String.UTF16View = selectKeys!.uppercased()
          .applyingTransform(.fullwidthToHalfwidth, reverse: true)!.utf16
        for i in 0..<menuSize {
          labels.append(String(keyCaps[keyCaps.index(keyCaps.startIndex, offsetBy: i)]))
        }
      }
    } else {
      selectKeys = String("1234567890".prefix(menuSize))
      if (selectLabels.isEmpty) {
        let numerals: String.UTF16View = selectKeys!
          .applyingTransform(.fullwidthToHalfwidth, reverse: true)!.utf16
        for i in 0..<menuSize {
          labels.append(String(numerals[numerals.index(numerals.startIndex, offsetBy: i)]))
        }
      }
    }
    setSelectKeys(selectKeys!, labels: labels, directUpdate: update)
  }

  func setSelectKeys(_ selectKeys: String,
                     labels: [String],
                     directUpdate update: Boolean) {
    _selectKeys = selectKeys
    _labels = labels
    _pageSize = labels.count
    if (update) {
      updateCandidateFormat(forAttributesOnly: true)
    }
  }

  func setCandidateFormat(_ candidateFormat: String) {
    let attrsOnly: Boolean = candidateFormat == _candidateFormat
    if (!attrsOnly) {
      _candidateFormat = candidateFormat
    }
    updateCandidateFormat(forAttributesOnly: attrsOnly)
    updateSeperatorAndSymbolAttrs()
  }

  private func updateCandidateFormat(forAttributesOnly attrsOnly: Boolean) {
    var candidateTemplate: NSMutableAttributedString
    if (!attrsOnly) {
      // validate candidate format: must have enumerator '%c' before candidate '%@'
      var format: String = candidateFormat
      var textRange: Range<String.Index>? = format.range(of: "%@", options: .literal)
      if (textRange == nil) {
        format.append("%@")
      }
      var labelRange: Range<String.Index>? = format.range(of: "%c", options: .literal)
      if (labelRange == nil) {
        format.insert(contentsOf: "%c", at: format.startIndex)
        labelRange = format.range(of: "%c", options: .literal)
      }
      textRange = format.range(of: "%@", options: .literal)
      if (labelRange!.lowerBound > textRange!.lowerBound) {
        format = kDefaultCandidateFormat
      }
      var labels: [String] = _labels
      var enumRange: Range<String.Index>?
      let labelCharacters: CharacterSet = CharacterSet(charactersIn: _labels.joined())
      if (CharacterSet(charactersIn: Unicode.Scalar(0xFF10)!...Unicode.Scalar(0xFF19)!)
        .isSuperset(of: labelCharacters)) { // ０１...９
        if let range = format.range(of: "%c\u{20E3}", options: .literal) { // 1︎⃣...9︎⃣0︎⃣
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF10 + 0x0030
            labels[i] = String(chars) + "\u{FE0E}\u{20E3}"
          }
        } else if let range = format.range(of: "%c\u{20DD}", options: .literal) { // ①...⑨⓪
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value == 0xFF10 ? 0x24EA : _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF11 + 0x2460
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "(%c)", options: .literal) { // ⑴...⑼⑽
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value == 0xFF10 ? 0x247D : _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF11 + 0x2474
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "%c.", options: .literal) { // ⒈...⒐🄀
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value == 0xFF10 ? 0x1F100 : _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF11 + 0x2488
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "%c,", options: .literal) { // 🄂...🄊🄁
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF10 + 0x1F101
            labels[i] = String(chars)
          }
        }
      } else if (CharacterSet(charactersIn: Unicode.Scalar(0xFF21)!...Unicode.Scalar(0xFF3A)!)
        .isSuperset(of: labelCharacters)) { // Ａ...Ｚ
        if let range = format.range(of: "%c\u{20DD}", options: .literal) { // Ⓐ...Ⓩ
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF21 + 0x24B6
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "(%c)", options: .literal) { // 🄐...🄩
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF21 + 0x1F110
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "%c\u{20DE}", options: .literal) { // 🄰...🅉
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF21 + 0x1F130
            labels[i] = String(chars)
          }
        }
      }
      if (enumRange != nil) {
        format = format.replacingCharacters(in: enumRange!, with: "%c")
        _labels = labels
      }
      candidateTemplate = NSMutableAttributedString(string: format)
    } else {
      candidateTemplate = _candidateTemplate as! NSMutableAttributedString
    }
    // make sure label font can render all possible enumerators
    let labelString: String = _labels.joined()
    let labelFont = _labelAttrs[.font] as! NSFont
    var substituteFont: NSFont = CTFontCreateForString(labelFont, labelString as CFString,
                                                       CFRangeMake(0, labelString.count))
    if (substituteFont.isNotEqual(to: labelFont)) {
      let monoDigitAttrs: [NSFontDescriptor.AttributeName: [[NSFontDescriptor.FeatureKey: Int]]] =
      [.featureSettings:
        [[.typeIdentifier: kNumberSpacingType,
          .selectorIdentifier: kMonospacedNumbersSelector],
         [.typeIdentifier: kTextSpacingType,
          .selectorIdentifier: kHalfWidthTextSelector]]]
      let subFontDescriptor = substituteFont.fontDescriptor.addingAttributes(monoDigitAttrs)
      substituteFont = NSFont(descriptor: subFontDescriptor, size: labelFont.pointSize)!
      _labelAttrs[.font] = substituteFont
    }

    var textRange = candidateTemplate.mutableString.range(of: "%@", options: .literal)
    var labelRange = NSMakeRange(0, textRange.location)
    var commentRange = NSMakeRange(NSMaxRange(textRange),
                                   candidateTemplate.length - NSMaxRange(textRange))
    // parse markdown formats
    candidateTemplate.setAttributes(_labelAttrs, range: labelRange)
    candidateTemplate.setAttributes(_textAttrs, range: textRange)
    if (commentRange.length > 0) {
      candidateTemplate.setAttributes(_commentAttrs, range: commentRange)
    }

    // parse markdown formats
    if (!attrsOnly) {
      candidateTemplate.formatMarkDown()
      // add placeholder for comment `%s`
      textRange = candidateTemplate.mutableString.range(of: "%@", options: .literal)
      labelRange = NSMakeRange(0, textRange.location)
      commentRange = NSMakeRange(NSMaxRange(textRange),
                                 candidateTemplate.length - NSMaxRange(textRange))
      if (commentRange.length > 0) {
        candidateTemplate.replaceCharacters(in: commentRange, with: kTipSpecifier + 
                                            candidateTemplate.mutableString.substring(with: commentRange))
      } else {
        candidateTemplate.append(NSAttributedString(string: kTipSpecifier,
                                                    attributes: _commentAttrs))
      }
      commentRange.length += kTipSpecifier.count

      if (!linear) {
        candidateTemplate.replaceCharacters(in: NSMakeRange(textRange.location, 0), with: "\t")
        labelRange.length += 1
        textRange.location += 1
        commentRange.location += 1
      }
    }

    // for stacked layout, calculate head indent
    let candidateParagraphStyle = _candidateParagraphStyle as! NSMutableParagraphStyle
    if (!linear) {
      var indent: CGFloat = 0.0
      let labelFormat = candidateTemplate.attributedSubstring(from: NSMakeRange(0, labelRange.length - 1))
      for label in _labels {
        let enumString = labelFormat as! NSMutableAttributedString
        enumString.mutableString.replaceOccurrences(of: "%c", with: label, options: .literal,
                                                    range: NSMakeRange(0, enumString.length))
        enumString.addAttribute(.verticalGlyphForm, value: vertical,
                                range: NSMakeRange(0, enumString.length))
        indent = max(indent, enumString.size().width)
      }
      indent = floor(indent) + 1.0
      candidateParagraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
      candidateParagraphStyle.headIndent = indent
      _candidateParagraphStyle = candidateParagraphStyle
    } else {
      candidateParagraphStyle.tabStops = []
      candidateParagraphStyle.headIndent = 0.0
      _candidateParagraphStyle = candidateParagraphStyle
      let truncatedParagraphStyle = candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
      truncatedParagraphStyle.lineBreakMode = .byTruncatingMiddle
      truncatedParagraphStyle.tighteningFactorForTruncation = 0.0
      _truncatedParagraphStyle = truncatedParagraphStyle
    }

    _textAttrs[.paragraphStyle] = candidateParagraphStyle
    _commentAttrs[.paragraphStyle] = candidateParagraphStyle
    _labelAttrs[.paragraphStyle] = candidateParagraphStyle
    candidateTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle,
                                   range: NSMakeRange(0, candidateTemplate.length))
    _candidateTemplate = candidateTemplate

    let candidateHilitedTemplate = candidateTemplate.mutableCopy() as! NSMutableAttributedString
    candidateHilitedTemplate.addAttribute(
      .foregroundColor, value: hilitedLabelForeColor, range: labelRange)
    candidateHilitedTemplate.addAttribute(
      .foregroundColor, value: hilitedTextForeColor, range: textRange)
    candidateHilitedTemplate.addAttribute(
      .foregroundColor, value: hilitedCommentForeColor, range: commentRange)
    _candidateHilitedTemplate = candidateHilitedTemplate

    if (tabular) {
      let candidateDimmedTemplate = candidateTemplate.mutableCopy() as! NSMutableAttributedString
      candidateDimmedTemplate.addAttribute(
        .foregroundColor, value: dimmedLabelForeColor!, range: labelRange)
      _candidateDimmedTemplate = candidateDimmedTemplate
    }
  }

  func setStatusMessageType(_ type: String?) {
    if (type == nil) {
      _statusMessageType = .mixed
    } else if (type!.caseInsensitiveCompare("long") == .orderedSame) {
      _statusMessageType = .long
    } else if (type!.caseInsensitiveCompare("short") == .orderedSame) {
      _statusMessageType = .short
    } else {
      _statusMessageType = .mixed
    }
  }

  func updateWithConfig(_ config: SquirrelConfig,
                        styleOptions: Set<String>,
                        scriptVariant: String,
                        forAppearance appearance: SquirrelAppearance) {
    /*** INTERFACE ***/
    var linear: Boolean = false
    var tabular: Boolean = false
    var vertical: Boolean = false
    updateCandidateListLayout(isLinear: &linear, isTabular: &tabular, config: config, prefix: "style")
    updateTextOrientation(isVertical: &vertical, config: config, prefix: "style")
    var inlinePreedit: Boolean? = config.getOptionalBoolForOption("style/inline_preedit")
    var inlineCandidate: Boolean? = config.getOptionalBoolForOption("style/inline_candidate")
    var showPaging: Boolean? = config.getOptionalBoolForOption("style/show_paging")
    var rememberSize: Boolean? = config.getOptionalBoolForOption("style/remember_size")
    var statusMessageType: String? = config.getStringForOption("style/status_message_type")
    var candidateFormat: String? = config.getStringForOption("style/candidate_format")
    /*** TYPOGRAPHY ***/
    var fontName: String? = config.getStringForOption("style/font_face")
    var fontSize: Double? = config.getOptionalDoubleForOption("style/font_point",
                                                              applyConstraint: pos_round)
    var labelFontName: String? = config.getStringForOption("style/label_font_face")
    var labelFontSize: Double? = config.getOptionalDoubleForOption("style/label_font_point",
                                                                   applyConstraint: pos_round)
    var commentFontName: String? = config.getStringForOption("style/comment_font_face")
    var commentFontSize: Double? = config.getOptionalDoubleForOption("style/comment_font_point",
                                                                     applyConstraint: pos_round)
    var opacity: Double? = config.getOptionalDoubleForOption("style/opacity", alias: "alpha",
                                                             applyConstraint: clamp_uni)
    var translucency: Double? = config.getOptionalDoubleForOption("style/translucency",
                                                                  applyConstraint: clamp_uni)
    var cornerRadius: Double? = config.getOptionalDoubleForOption("style/corner_radius",
                                                                  applyConstraint: positive)
    var hilitedCornerRadius: Double? = config.getOptionalDoubleForOption("style/hilited_corner_radius",
                                                                         applyConstraint: positive)
    var borderHeight: Double? = config.getOptionalDoubleForOption("style/border_height",
                                                                  applyConstraint: pos_ceil)
    var borderWidth: Double? = config.getOptionalDoubleForOption("style/border_width",
                                                                 applyConstraint: pos_ceil)
    var lineSpacing: Double? = config.getOptionalDoubleForOption("style/line_spacing",
                                                                 applyConstraint: pos_round)
    var spacing: Double? = config.getOptionalDoubleForOption("style/spacing",
                                                             applyConstraint: pos_round)
    var baseOffset: Double? = config.getOptionalDoubleForOption("style/base_offset")
    var lineLength: Double? = config.getOptionalDoubleForOption("style/line_length")
    /*** CHROMATICS ***/
    var backImage: NSImage?
    var backColor: NSColor?
    var preeditBackColor: NSColor?
    var hilitedPreeditBackColor: NSColor?
    var hilitedCandidateBackColor: NSColor?
    var borderColor: NSColor?
    var preeditForeColor: NSColor?
    var textForeColor: NSColor?
    var commentForeColor: NSColor?
    var labelForeColor: NSColor?
    var hilitedPreeditForeColor: NSColor?
    var hilitedTextForeColor: NSColor?
    var hilitedCommentForeColor: NSColor?
    var hilitedLabelForeColor: NSColor?

    var colorScheme: String?
    if (appearance == .dark) {
      for option in styleOptions {
        if let value = config.getStringForOption("style/" + option + "/color_scheme_dark") {
          colorScheme = value
          break
        }
      }
      colorScheme = colorScheme ?? config.getStringForOption("style/color_scheme_dark")
    }
    if (colorScheme == nil) {
      for option in styleOptions {
        if let value = config.getStringForOption("style/" + option + "/color_scheme") {
          colorScheme = value
          break
        }
      }
      colorScheme = colorScheme ?? config.getStringForOption("style/color_scheme")
    }
    let isNative: Boolean = (colorScheme == nil) || (colorScheme! == "native")
    var configPrefixes: [String] = styleOptions.map({ "style/" + $0 })
    if (!isNative) {
      configPrefixes.insert("preset_color_schemes/" + colorScheme!, at: 0)
    }

    // get color scheme and then check possible overrides from styleSwitcher
    for prefix in configPrefixes {
      /*** CHROMATICS override ***/
      config.colorSpace = config.getStringForOption(prefix + "/color_space") ?? config.colorSpace
      backColor = config.getColorForOption(prefix + "/back_color") ?? backColor
      borderColor = config.getColorForOption(prefix + "/border_color") ?? borderColor
      preeditBackColor = config.getColorForOption(prefix + "/preedit_back_color") ?? preeditBackColor
      preeditForeColor = config.getColorForOption(prefix + "/text_color") ?? preeditForeColor
      textForeColor = config.getColorForOption(prefix + "/candidate_text_color") ?? textForeColor
      commentForeColor = config.getColorForOption(prefix + "/comment_text_color") ?? commentForeColor
      labelForeColor = config.getColorForOption(prefix + "/label_color") ?? labelForeColor
      hilitedPreeditBackColor = config.getColorForOption(prefix + "/hilited_back_color") ?? hilitedPreeditBackColor
      hilitedPreeditForeColor = config.getColorForOption(prefix + "/hilited_text_color") ?? hilitedPreeditForeColor
      hilitedCandidateBackColor = config.getColorForOption(prefix + "/hilited_candidate_back_color") ?? hilitedCandidateBackColor
      hilitedTextForeColor = config.getColorForOption(prefix + "/hilited_candidate_text_color") ?? hilitedTextForeColor
      hilitedCommentForeColor = config.getColorForOption(prefix + "/hilited_comment_text_color") ?? hilitedCommentForeColor
      // for backward compatibility, `label_hilited_color` and `hilited_candidate_label_color` are both valid
      hilitedLabelForeColor = config.getColorForOption(prefix + "/label_hilited_color",
                                                       alias: "hilited_candidate_label_color") ?? hilitedLabelForeColor
      backImage = config.getImageForOption(prefix + "/back_image") ?? backImage

      /* the following per-color-scheme configurations, if exist, will
         override configurations with the same name under the global 'style' section */
      /*** INTERFACE override ***/
      updateCandidateListLayout(isLinear: &linear, isTabular: &tabular, config: config, prefix: prefix)
      updateTextOrientation(isVertical: &vertical, config: config, prefix: prefix)
      inlinePreedit = config.getOptionalBoolForOption(prefix + "/inline_preedit") ?? inlinePreedit
      inlineCandidate = config.getOptionalBoolForOption(prefix + "/inline_candidate") ?? inlineCandidate
      showPaging = config.getOptionalBoolForOption(prefix + "/show_paging") ?? showPaging
      rememberSize = config.getOptionalBoolForOption(prefix + "/remember_size") ?? rememberSize
      statusMessageType = config.getStringForOption(prefix + "/status_message_type") ?? statusMessageType
      candidateFormat = config.getStringForOption(prefix + "/candidate_format") ?? candidateFormat
      /*** TYPOGRAPHY override ***/
      fontName = config.getStringForOption(prefix + "/font_face") ?? fontName
      fontSize = config.getOptionalDoubleForOption(prefix + "/font_point", applyConstraint: pos_round) ?? fontSize
      labelFontName = config.getStringForOption(prefix + "/label_font_face") ?? labelFontName
      labelFontSize = config.getOptionalDoubleForOption(prefix + "/label_font_point", applyConstraint: pos_round) ?? labelFontSize
      commentFontName = config.getStringForOption(prefix + "/comment_font_face") ?? commentFontName
      commentFontSize = config.getOptionalDoubleForOption(prefix + "/comment_font_point", applyConstraint: pos_round) ?? commentFontSize
      opacity = config.getOptionalDoubleForOption(prefix + "/opacity", alias: "alpha", applyConstraint: clamp_uni) ?? opacity
      translucency = config.getOptionalDoubleForOption(prefix + "/translucency", applyConstraint: clamp_uni) ?? translucency
      cornerRadius = config.getOptionalDoubleForOption(prefix + "/corner_radius", applyConstraint: positive) ?? cornerRadius
      hilitedCornerRadius = config.getOptionalDoubleForOption(prefix + "/hilited_corner_radius", applyConstraint: positive) ?? hilitedCornerRadius
      borderHeight = config.getOptionalDoubleForOption(prefix + "/border_height", applyConstraint: pos_ceil) ?? borderHeight
      borderWidth = config.getOptionalDoubleForOption(prefix + "/border_width", applyConstraint: pos_ceil) ?? borderWidth
      lineSpacing = config.getOptionalDoubleForOption(prefix + "/line_spacing", applyConstraint: pos_round) ?? lineSpacing
      spacing = config.getOptionalDoubleForOption(prefix + "/spacing", applyConstraint: pos_round) ?? spacing
      baseOffset = config.getOptionalDoubleForOption(prefix + "/base_offset") ?? baseOffset
      lineLength = config.getOptionalDoubleForOption(prefix + "/line_length") ?? lineLength
    }

    /*** TYPOGRAPHY refinement ***/
    fontSize = fontSize ?? kDefaultFontSize
    labelFontSize = labelFontSize ?? fontSize
    commentFontSize = commentFontSize ?? fontSize
    let monoDigitAttrs: [NSFontDescriptor.AttributeName: [[NSFontDescriptor.FeatureKey: Any]]] =
      [.featureSettings: [[.typeIdentifier: kNumberSpacingType,
                           .selectorIdentifier: kMonospacedNumbersSelector],
                          [.typeIdentifier: kTextSpacingType,
                           .selectorIdentifier: kHalfWidthTextSelector]]]

    let fontDescriptor: NSFontDescriptor! = getFontDescriptor(fullname: fontName)
    let font = NSFont(descriptor: (fontDescriptor ?? getFontDescriptor(
      fullname: NSFont.userFont(ofSize: 0)?.fontName))!, size: fontSize!)

    let labelFontDescriptor: NSFontDescriptor! = (getFontDescriptor(
      fullname: labelFontName) ?? fontDescriptor)!.addingAttributes(monoDigitAttrs)
    let labelFont: NSFont! = labelFontDescriptor != nil
    ? NSFont(descriptor: labelFontDescriptor, size: labelFontSize!)
    : NSFont.monospacedDigitSystemFont(ofSize: labelFontSize!, weight: .regular)

    let commentFontDescriptor: NSFontDescriptor! = getFontDescriptor(fullname: commentFontName)
    let commentFont = NSFont(descriptor: commentFontDescriptor ?? fontDescriptor,
                             size: commentFontSize!)

    let pagingFont = NSFont.monospacedDigitSystemFont(ofSize: labelFontSize!, weight: .regular)

    let fontHeight: Double = getLineHeight(font: font, vertical: vertical)
    let labelFontHeight: Double = getLineHeight(font: labelFont, vertical: vertical)
    let commentFontHeight: Double = getLineHeight(font: commentFont, vertical: vertical)
    let lineHeight: Double = max(fontHeight, max(labelFontHeight, commentFontHeight))
    let fullWidth: Double = ceil(commentFont!.advancement(forCGGlyph: CGGlyph(unichar(0x3000))).width)
    spacing = spacing ?? 0
    lineSpacing = lineSpacing ?? 0

    let preeditRulerAttrs = _preeditParagraphStyle as! NSMutableParagraphStyle
    preeditRulerAttrs.minimumLineHeight = fontHeight
    preeditRulerAttrs.maximumLineHeight = fontHeight
    preeditRulerAttrs.paragraphSpacing = spacing!
    preeditRulerAttrs.tabStops = []

    let candidateRulerAttrs = _candidateParagraphStyle as! NSMutableParagraphStyle
    candidateRulerAttrs.minimumLineHeight = lineHeight
    candidateRulerAttrs.maximumLineHeight = lineHeight
    candidateRulerAttrs.paragraphSpacingBefore = linear ? 0.0 : ceil(lineSpacing! * 0.5)
    candidateRulerAttrs.paragraphSpacing = linear ? 0.0 : floor(lineSpacing! * 0.5)
    candidateRulerAttrs.tabStops = []
    candidateRulerAttrs.defaultTabInterval = fullWidth * 2

    let pagingRulerAttrs = _pagingParagraphStyle as! NSMutableParagraphStyle
    pagingRulerAttrs.minimumLineHeight = ceil(pagingFont.ascender - pagingFont.descender)
    pagingRulerAttrs.maximumLineHeight = ceil(pagingFont.ascender - pagingFont.descender)
    pagingRulerAttrs.tabStops = []

    let statusRulerAttrs = _statusParagraphStyle as! NSMutableParagraphStyle
    statusRulerAttrs.minimumLineHeight = commentFontHeight
    statusRulerAttrs.maximumLineHeight = commentFontHeight

    _candidateParagraphStyle = candidateRulerAttrs
    _preeditParagraphStyle = preeditRulerAttrs
    _pagingParagraphStyle = pagingRulerAttrs
    _statusParagraphStyle = statusRulerAttrs

    _textAttrs[.font] = font
    _labelAttrs[.font] = labelFont
    _commentAttrs[.font] = commentFont
    _preeditAttrs[.font] = font
    _pagingAttrs[.font] = linear ? labelFont : pagingFont
    _statusAttrs[.font] = commentFont

    var zhFont: NSFont = CTFontCreateUIFontForLanguage(.system, fontSize!, scriptVariant as CFString)!
    var zhCommentFont = NSFont(descriptor: zhFont.fontDescriptor, size: commentFontSize!)!
    let maxFontSize: Double = max(fontSize!, max(commentFontSize!, labelFontSize!))
    var refFont = NSFont(descriptor: zhFont.fontDescriptor, size: maxFontSize)!
    if (vertical) {
      zhFont = zhFont.vertical
      zhCommentFont = zhCommentFont.vertical
      refFont = refFont.vertical
    }
    let baselineRefInfo: [CFString : Any] = 
      [kCTBaselineReferenceFont: refFont,
       kCTBaselineClassIdeographicCentered: vertical ? 0.0 : (refFont.ascender + refFont.descender) * 0.5,
       kCTBaselineClassRoman: vertical ? -(refFont.ascender + refFont.descender) * 0.5 : 0.0,
       kCTBaselineClassIdeographicLow: vertical ? (refFont.descender - refFont.ascender) * 0.5 : refFont.descender]

    _textAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _labelAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _commentAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _preeditAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = [kCTBaselineReferenceFont: zhFont]
    _pagingAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = [kCTBaselineReferenceFont: pagingFont]
    _statusAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = [kCTBaselineReferenceFont: zhCommentFont]

    _textAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    _labelAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] = kCTBaselineClassIdeographicCentered
    _commentAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    _preeditAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman;
    _statusAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman;
    _pagingAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] = kCTBaselineClassIdeographicCentered;

    _textAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant
    _labelAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant
    _commentAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant
    _preeditAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant
    _statusAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant

    baseOffset = baseOffset ?? 0
    _textAttrs[.baselineOffset] = baseOffset
    _labelAttrs[.baselineOffset] = baseOffset
    _commentAttrs[.baselineOffset] = baseOffset
    _preeditAttrs[.baselineOffset] = baseOffset
    _pagingAttrs[.baselineOffset] = baseOffset
    _statusAttrs[.baselineOffset] = baseOffset

    _preeditAttrs[.paragraphStyle] = preeditRulerAttrs
    _pagingAttrs[.paragraphStyle] = pagingRulerAttrs
    _statusAttrs[.paragraphStyle] = statusRulerAttrs

    _labelAttrs[.verticalGlyphForm] = vertical
    _pagingAttrs[.verticalGlyphForm] = false

    // CHROMATICS refinement
    translucency = translucency ?? 0.0
    if #available(macOS 10.14, *) {
      if (translucency! > 0.001 && !isNative && backColor != nil &&
          (appearance == .dark ? backColor!.lStarComponent! > 0.6 : backColor!.lStarComponent! < 0.4)) {
        backColor = backColor?.invertLuminance(toExtent: .standard)
        borderColor = borderColor?.invertLuminance(toExtent: .standard)
        preeditBackColor = preeditBackColor?.invertLuminance(toExtent: .standard)
        preeditForeColor = preeditForeColor?.invertLuminance(toExtent: .standard)
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

    _backImage = backImage
    _backColor = backColor ?? .controlBackgroundColor
    _borderColor = borderColor ?? (isNative ? .gridColor : nil)
    _preeditBackColor = preeditBackColor ?? (isNative ? .windowBackgroundColor : nil)
    _preeditForeColor = preeditForeColor ?? .textColor
    _textForeColor = textForeColor ?? .controlTextColor
    _commentForeColor = commentForeColor ?? .secondaryLabelColor
    _labelForeColor = labelForeColor ?? (isNative ? .accentColor : blendColors(foreground: _textForeColor,
                                                                               background: _backColor))
    _hilitedPreeditBackColor = hilitedPreeditBackColor ?? (isNative ? .selectedTextBackgroundColor : nil)
    _hilitedPreeditForeColor = hilitedPreeditForeColor ?? .selectedTextColor
    _hilitedCandidateBackColor = hilitedCandidateBackColor ?? (isNative ? .selectedContentBackgroundColor : nil)
    _hilitedTextForeColor = hilitedTextForeColor ?? .selectedMenuItemTextColor
    _hilitedCommentForeColor = hilitedCommentForeColor ?? .alternateSelectedControlTextColor
    _hilitedLabelForeColor = hilitedLabelForeColor ?? (isNative ? .alternateSelectedControlTextColor 
      : blendColors(foreground: _hilitedTextForeColor, background: _hilitedCandidateBackColor))
    _dimmedLabelForeColor = tabular ? _labelForeColor.withAlphaComponent(_labelForeColor.alphaComponent * 0.5) : nil

    _textAttrs[.foregroundColor] = _textForeColor
    _labelAttrs[.foregroundColor] = _labelForeColor
    _commentAttrs[.foregroundColor] = _commentForeColor
    _preeditAttrs[.foregroundColor] = _preeditForeColor
    _pagingAttrs[.foregroundColor] = _preeditForeColor
    _statusAttrs[.foregroundColor] = _commentForeColor

    _borderInsets = vertical ? NSMakeSize(borderHeight ?? 0, borderWidth ?? 0)
                             : NSMakeSize(borderWidth ?? 0, borderHeight ?? 0)
    _cornerRadius = min(cornerRadius ?? 0, lineHeight * 0.5)
    _hilitedCornerRadius = min(hilitedCornerRadius ?? 0, lineHeight * 0.5)
    _fullWidth = fullWidth
    _lineSpacing = lineSpacing!
    _preeditSpacing = spacing!
    _opacity = opacity ?? 1.0
    _translucency = Float(translucency ?? 0.0)
    _lineLength = lineLength != nil && lineLength! > 0.1 ? max(ceil(lineLength!), fullWidth * 5) : 0
    _showPaging = showPaging ?? false
    _rememberSize = rememberSize ?? false
    _tabular = tabular
    _linear = linear
    _vertical = vertical
    _inlinePreedit = inlinePreedit ?? false
    _inlineCandidate = inlineCandidate ?? false

    _scriptVariant = scriptVariant
    setCandidateFormat(candidateFormat ?? kDefaultCandidateFormat)
    setStatusMessageType(statusMessageType)
  }

  func setAnnotationHeight(_ height: Double) {
    if (height > 0.1 && lineSpacing < height * 2) {
      _lineSpacing = height * 2
      let candidateParagraphStyle = _candidateParagraphStyle as! NSMutableParagraphStyle
      candidateParagraphStyle.paragraphSpacingBefore = height
      candidateParagraphStyle.paragraphSpacing = height
      _candidateParagraphStyle = candidateParagraphStyle as NSParagraphStyle
    }
  }

  func setScriptVariant(_ scriptVariant: String) {
    if (scriptVariant == _scriptVariant) {
      return
    }
    _scriptVariant = scriptVariant;

    let textFontSize: Double = (_textAttrs[.font] as! NSFont).pointSize
    let commentFontSize: Double = (_commentAttrs[.font] as! NSFont).pointSize
    let labelFontSize: Double = (_labelAttrs[.font] as! NSFont).pointSize
    var zhFont: NSFont = CTFontCreateUIFontForLanguage(.system, textFontSize, scriptVariant as CFString)!
    var zhCommentFont = NSFont(descriptor: zhFont.fontDescriptor, size: commentFontSize)!
    let maxFontSize: Double = max(textFontSize, commentFontSize, labelFontSize)
    var refFont = NSFont(descriptor: zhFont.fontDescriptor, size: maxFontSize)!
    if (vertical) {
      zhFont = zhFont.vertical
      zhCommentFont = zhCommentFont.vertical
      refFont = refFont.vertical
    }
    let baselineRefInfo: [CFString : Any] =
    [kCTBaselineReferenceFont: refFont,
     kCTBaselineClassIdeographicCentered: vertical ? 0.0 : (refFont.ascender + refFont.descender) * 0.5,
     kCTBaselineClassRoman: vertical ? -(refFont.ascender + refFont.descender) * 0.5 : 0.0,
     kCTBaselineClassIdeographicLow: vertical ? (refFont.descender - refFont.ascender) * 0.5 : refFont.descender]

    _textAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _labelAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _commentAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _preeditAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = [kCTBaselineReferenceFont: zhFont]
    _statusAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = [kCTBaselineReferenceFont: zhCommentFont]

    _textAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
    _labelAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
    _commentAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
    _preeditAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
    _statusAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;

    let candidateTemplate = _candidateTemplate.mutableCopy() as! NSMutableAttributedString
    let textRange: NSRange = candidateTemplate.mutableString.range(of: "%@", options: .literal)
    let labelRange: NSRange = NSMakeRange(0, textRange.location)
    let commentRange: NSRange = NSMakeRange(NSMaxRange(textRange), candidateTemplate.length - NSMaxRange(textRange))
    candidateTemplate.addAttributes(_labelAttrs, range: labelRange)
    candidateTemplate.addAttributes(_textAttrs, range: textRange)
    candidateTemplate.addAttributes(_commentAttrs, range: commentRange)
    _candidateTemplate = candidateTemplate

    let candidateHilitedTemplate = candidateTemplate.mutableCopy() as! NSMutableAttributedString
    candidateHilitedTemplate.addAttribute(
      .foregroundColor, value: hilitedLabelForeColor, range: labelRange)
    candidateHilitedTemplate.addAttribute(
      .foregroundColor, value: hilitedTextForeColor, range: textRange)
    candidateHilitedTemplate.addAttribute(
      .foregroundColor, value: hilitedCommentForeColor, range: commentRange)
    _candidateHilitedTemplate = candidateHilitedTemplate

    if (tabular) {
      let candidateDimmedTemplate = candidateTemplate.mutableCopy() as! NSMutableAttributedString
      candidateDimmedTemplate.addAttribute(
        .foregroundColor, value: dimmedLabelForeColor!, range: labelRange)
      _candidateDimmedTemplate = candidateDimmedTemplate
    }
  }

}  // SquirrelTheme

// MARK: - Typesetting extensions for TextKit 1 (Mac OSX 10.9 to MacOS 11)

@frozen enum SquirrelContentBlock: Int {
  case preedit = 1
  case linearCandidates = 2
  case stackedCandidates = 3
  case paging = 4
  case status = 5
}

class SquirrelLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {

  var contentBlock: SquirrelContentBlock = .stackedCandidates

  override func drawGlyphs(forGlyphRange glyphsToShow: NSRange,
                           at origin: NSPoint) {
    let textContainer = textContainer(forGlyphAt: glyphsToShow.location,
                                      effectiveRange: nil, withoutAdditionalLayout: true)!
    let verticalOrientation: Boolean = textContainer.layoutOrientation == .vertical
    let context: CGContext = NSGraphicsContext.current!.cgContext
    context.resetClip()
    enumerateLineFragments(forGlyphRange: glyphsToShow) { 
      (lineRect: NSRect, lineUsedRect: NSRect, textContainer: NSTextContainer,
       lineRange: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
      let charRange: NSRange = self.characterRange(forGlyphRange: lineRange,
                                                   actualGlyphRange: nil)
      self.textStorage!.enumerateAttributes(in: charRange,
                                       options: [.longestEffectiveRangeNotRequired])
      { (attrs: [NSAttributedString.Key : Any], runRange: NSRange,
         stop: UnsafeMutablePointer<ObjCBool>) in
        let runGlyphRange = self.glyphRange(forCharacterRange: runRange,
                                            actualCharacterRange: nil)
        if (attrs[kCTRubyAnnotationAttributeName as NSAttributedString.Key] != nil) {
          context.saveGState()
          context.scaleBy(x: 1.0, y: -1.0)
          var glyphIndex: Int = runGlyphRange.location
          let line: CTLine = CTLineCreateWithAttributedString(
            self.textStorage!.attributedSubstring(from: runRange))
          let runs: CFArray = CTLineGetGlyphRuns(line)
          for i in 0..<CFArrayGetCount(runs) {
            let position: CGPoint = self.location(forGlyphAt: glyphIndex)
            let run: CTRun = CFArrayGetValueAtIndex(runs, i) as! CTRun
            let glyphCount: Int = CTRunGetGlyphCount(run)
            var matrix: CGAffineTransform = CTRunGetTextMatrix(run)
            var glyphOrigin: CGPoint = CGPointMake(origin.x + lineRect.origin.x + position.x,
                                                   -origin.y - lineRect.origin.y - position.y)
            glyphOrigin = textContainer.textView!.convertToBacking(glyphOrigin)
            glyphOrigin.x = round(glyphOrigin.x)
            glyphOrigin.y = round(glyphOrigin.y)
            glyphOrigin = textContainer.textView!.convertFromBacking(glyphOrigin)
            matrix.tx = glyphOrigin.x
            matrix.ty = glyphOrigin.y
            context.textMatrix = matrix
            CTRunDraw(run, context, CFRangeMake(0, glyphCount))
            glyphIndex += glyphCount
          }
        } else {
          var position: NSPoint = self.location(forGlyphAt: runGlyphRange.location)
          position.x += origin.x
          position.y += origin.y
          let runFont = attrs[NSAttributedString.Key.font] as! NSFont
          let baselineClass = attrs[kCTBaselineClassAttributeName as NSAttributedString.Key] as! String
          var offset: NSPoint = NSZeroPoint
          if (!verticalOrientation && (baselineClass == kCTBaselineClassIdeographicCentered as String ||
                                       baselineClass == kCTBaselineClassMath as String)) {
            let refFont = (attrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] as!
                           [String: Any])[kCTBaselineReferenceFont as String] as! NSFont
            offset.y += (runFont.ascender + runFont.descender - refFont.ascender - refFont.descender) * 0.5
          } else if (verticalOrientation && runFont.pointSize < 24 && (runFont.fontName == "AppleColorEmoji")) {
            let superscript: Int! = attrs[NSAttributedString.Key.superscript] as? Int
            offset.x += runFont.capHeight - runFont.pointSize
            offset.y += (runFont.capHeight - runFont.pointSize) *
              (superscript == 0 ? 0.25 : (superscript == 1 ? 0.5 / 0.55 : 0.0))
          }
          var glyphOrigin: NSPoint = textContainer.textView!.convertToBacking(
            NSMakePoint(position.x + offset.x, position.y + offset.y))
          glyphOrigin = textContainer.textView!.convertFromBacking(
            NSMakePoint(round(glyphOrigin.x), round(glyphOrigin.y)))
          super.drawGlyphs(forGlyphRange: runGlyphRange, at: NSMakePoint(glyphOrigin.x - position.x,
                                                                         glyphOrigin.y - position.y))
        }
        context.restoreGState()
      }
    }
    context.clip(to: textContainer.textView!.superview!.bounds)
  }

  func layoutManager(_ layoutManager: NSLayoutManager,
                     shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                     lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                     baselineOffset: UnsafeMutablePointer<CGFloat>, 
                     in textContainer: NSTextContainer,
                     forGlyphRange glyphRange: NSRange) -> Boolean {
    var didModify: Boolean = false
    let verticalOrientation: Boolean = textContainer.layoutOrientation == .vertical
    let charRange: NSRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange:nil)
    let rulerAttrs = layoutManager.textStorage!.attribute(.paragraphStyle, at: charRange.location,
                                                          effectiveRange: nil) as! NSParagraphStyle
    let lineSpacing: Double = rulerAttrs.lineSpacing
    let lineHeight: Double = rulerAttrs.minimumLineHeight
    var baseline: Double = lineHeight * 0.5
    if (!verticalOrientation) {
      let refFont = (layoutManager.textStorage!.attribute(kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key,
                                                          at: charRange.location, effectiveRange: nil) as!
                     Dictionary<CFString, Any>)[kCTBaselineReferenceFont] as! NSFont
      baseline += (refFont.ascender + refFont.descender) * 0.5
    }
    let lineHeightDelta: Double = lineFragmentUsedRect.pointee.size.height - lineHeight - lineSpacing
    if (fabs(lineHeightDelta) > 0.1) {
      lineFragmentUsedRect.pointee.size.height = round(lineFragmentUsedRect.pointee.size.height - lineHeightDelta)
      lineFragmentRect.pointee.size.height = round(lineFragmentRect.pointee.size.height - lineHeightDelta)
      didModify = true
    }
    let newBaselineOffset: Double = floor(lineFragmentUsedRect.pointee.origin.y - lineFragmentRect.pointee.origin.y + baseline)
    if (fabs(baselineOffset.pointee - newBaselineOffset) > 0.1) {
      baselineOffset.pointee = newBaselineOffset
      didModify = true
    }
    return didModify
  }

  func layoutManager(_ layoutManager: NSLayoutManager,
                     shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Boolean {
    if (charIndex <= 1) {
      return true
    } else {
      let charBeforeIndex: unichar = layoutManager.textStorage!.mutableString.character(at: charIndex - 1)
      return contentBlock == .linearCandidates ? charBeforeIndex == 0x1D
                                               : charBeforeIndex != 0x9
    }
  }

  func layoutManager(_ layoutManager: NSLayoutManager,
                     shouldUse action: NSLayoutManager.ControlCharacterAction,
                     forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
    if (charIndex > 0 && layoutManager.textStorage!.mutableString.character(at: charIndex) == 0x8B &&
        layoutManager.textStorage!.attribute(kCTRubyAnnotationAttributeName as NSAttributedString.Key,
                                             at: charIndex - 1, effectiveRange: nil) != nil) {
      return .whitespace
    } else {
      return action
    }
  }

  func layoutManager(_ layoutManager: NSLayoutManager,
                     boundingBoxForControlGlyphAt glyphIndex: Int,
                     for textContainer: NSTextContainer,
                     proposedLineFragment proposedRect: NSRect,
                     glyphPosition: NSPoint,
                     characterIndex charIndex: Int) -> NSRect {
    var width: Double = 0.0
    if (charIndex > 0 && layoutManager.textStorage!.mutableString.character(at: charIndex) == 0x8B) {
      var rubyRange: NSRange = NSMakeRange(NSNotFound, 0)
      if (layoutManager.textStorage!.attribute(kCTRubyAnnotationAttributeName as NSAttributedString.Key,
                                               at: charIndex - 1, effectiveRange: &rubyRange) != nil) {
        let rubyString = layoutManager.textStorage!.attributedSubstring(from: rubyRange)
        let line: CTLine = CTLineCreateWithAttributedString(rubyString)
        let rubyRect: CGRect = CTLineGetBoundsWithOptions(line, [])
        width = fdim(rubyRect.size.width, rubyString.size().width)
      }
    }
    return NSMakeRect(glyphPosition.x, 0.0, width, glyphPosition.y)
  }

}  // SquirrelLayoutManager

// MARK: - Typesetting extensions for TextKit 2 (MacOS 12 or higher)

@available(macOS 12.0, *)
class SquirrelTextLayoutFragment: NSTextLayoutFragment {

  override func draw(at point: CGPoint,
                     in context: CGContext) {
    var origin: CGPoint = point
    if #available(macOS 14.0, *) {
    } else { // in macOS 12 and 13, textLineFragments.typographicBouonds are in textContainer coordinates
      origin.x -= self.layoutFragmentFrame.origin.x
      origin.y -= self.layoutFragmentFrame.origin.y
    }
    let verticalOrientation: Boolean = textLayoutManager!.textContainer!.layoutOrientation == .vertical
    for lineFrag in textLineFragments {
      let lineRect: CGRect = CGRectOffset(lineFrag.typographicBounds, origin.x, origin.y)
      var baseline: Double = CGRectGetMidY(lineRect)
      if (!verticalOrientation) {
        let refFont = (lineFrag.attributedString.attribute(kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key,
                                                           at: lineFrag.characterRange.location, effectiveRange: nil) as!
                       Dictionary<CFString, Any>)[kCTBaselineReferenceFont] as! NSFont
        baseline += (refFont.ascender + refFont.descender) * 0.5
      }
      var renderOrigin: CGPoint = CGPointMake(NSMinX(lineRect) + lineFrag.glyphOrigin.x,
                                              floor(baseline) - lineFrag.glyphOrigin.y)
      let deviceOrigin: CGPoint = context.convertToDeviceSpace(renderOrigin)
      renderOrigin = context.convertToUserSpace(CGPointMake(round(deviceOrigin.x),
                                                            round(deviceOrigin.y)))
      lineFrag.draw(at: renderOrigin, in:context)
    }
  }

}  // SquirrelTextLayoutFragment


@available(macOS 12.0, *)
class SquirrelTextLayoutManager: NSTextLayoutManager, NSTextLayoutManagerDelegate {

  var contentBlock: SquirrelContentBlock = .stackedCandidates

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                         shouldBreakLineBefore location: any NSTextLocation,
                         hyphenating: Boolean) -> Boolean {
    let contentStorage = textLayoutManager.textContentManager as! NSTextContentStorage
    let charIndex: Int = contentStorage.offset(from: contentStorage.documentRange.location, to: location)
    if (charIndex <= 1) {
      return true
    } else {
      let charBeforeIndex: unichar = contentStorage.textStorage!.mutableString.character(at: charIndex - 1)
      return contentBlock == .linearCandidates ? charBeforeIndex == 0x1D
                                               : charBeforeIndex != 0x9
    }
  }

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                         textLayoutFragmentFor location: any NSTextLocation,
                         in textElement: NSTextElement) -> NSTextLayoutFragment {
    let textRange = NSTextRange(location: location,
                                end: textElement.elementRange!.endLocation)
    return SquirrelTextLayoutFragment(textElement: textElement, range: textRange)
  }

}  // SquirrelTextLayoutManager

// MARK: - View behind text, containing drawings of backgrounds and highlights

struct SquirrelTextPolygon {
  var head: NSRect = NSZeroRect
  var body: NSRect = NSZeroRect
  var tail: NSRect = NSZeroRect

  func origin() -> NSPoint {
    return (NSIsEmptyRect(head) ? body : head).origin
  }
  func minY() -> Double {
    return NSMinY(NSIsEmptyRect(head) ? body : head)
  }
  func maxY() -> Double {
    return NSMaxY(NSIsEmptyRect(head) ? body : head)
  }
  func separated() -> Boolean {
    return !NSIsEmptyRect(head) && NSIsEmptyRect(body) &&
           !NSIsEmptyRect(tail) && NSMaxX(tail) < NSMinX(head)
  }
  func mouseInPolygon(point: NSPoint, flipped: Boolean) -> Boolean {
    return (!NSIsEmptyRect(body) && NSMouseInRect(point, body, flipped)) ||
           (!NSIsEmptyRect(head) && NSMouseInRect(point, head, flipped)) ||
           (!NSIsEmptyRect(tail) && NSMouseInRect(point, tail, flipped))
  }
}

typealias SquirrelTabularIndex = (index: Int, lineNum: Int, tabNum: Int)

struct SquirrelCandidateRanges {
  var location: Int = 0
  var length: Int = 0
  var text: Int = 0
  var comment: Int = 0

  func candidateRange() -> NSRange {
    return NSMakeRange(location, length)
  }
  func maxRange() -> Int {
    return location + length
  }
  func labelRange() -> NSRange {
    return NSMakeRange(location, text)
  }
  func textRange() -> NSRange {
    return NSMakeRange(location + text, comment - text)
  }
  func commentRange() -> NSRange {
    return NSMakeRange(location + comment, length - comment)
  }
}

func squirclePath(rect: NSRect,
                  cornerRadius: Double) -> NSBezierPath {
  return squirclePath(vertices: rectVertices(rect), cornerRadius: cornerRadius)!
}

func squirclePath(polygon: SquirrelTextPolygon,
                  cornerRadius: Double) -> NSBezierPath {
  let path: NSBezierPath!
  if (NSIsEmptyRect(polygon.body) && !NSIsEmptyRect(polygon.head) &&
      !NSIsEmptyRect(polygon.tail) && NSMaxX(polygon.tail) < NSMinX(polygon.head)) {
    path = squirclePath(vertices: rectVertices(polygon.head),
                        cornerRadius: cornerRadius)
    path.append(squirclePath(vertices: rectVertices(polygon.tail),
                             cornerRadius: cornerRadius)!)
  } else {
    path = squirclePath(vertices: textPolygonVertices(polygon),
                        cornerRadius: cornerRadius)
  }
  return path;
}

// Bezier squircle curves, whose rounded corners are smooth (continously differentiable)
func squirclePath(vertices: [NSPoint],
                  cornerRadius: Double) -> NSBezierPath? {
  if (vertices.count < 4) {
    return nil
  }
  let path = NSBezierPath()
  var point: NSPoint = vertices.last!
  var nextPoint: NSPoint = vertices.first!
  var nextDiff: CGVector = CGVectorMake(nextPoint.x - point.x, nextPoint.y - point.y)
  var lastDiff: CGVector
  var arcRadius: Double = min(cornerRadius, Swift.abs(nextDiff.dx) * 0.3)
  var startPoint: NSPoint
  var relayPointA: NSPoint, relayPointB: NSPoint
  var controlPointA1: NSPoint, controlPointA2: NSPoint
  var controlPointB1: NSPoint, controlPointB2: NSPoint
  var endPoint: NSPoint = NSMakePoint(point.x + copysign(arcRadius * 1.528664, nextDiff.dx), nextPoint.y)
  var controlPoint1: NSPoint, controlPoint2: NSPoint
  path.move(to: endPoint)
  for i in 0..<vertices.count {
    lastDiff = nextDiff
    point = nextPoint
    nextPoint = vertices[(i + 1) % vertices.count]
    nextDiff = CGVectorMake(nextPoint.x - point.x, nextPoint.y - point.y)
    if (abs(nextDiff.dx) >= abs(nextDiff.dy)) {
      arcRadius = min(cornerRadius, min(abs(nextDiff.dx), abs(lastDiff.dy)) * 0.5)
      startPoint = NSMakePoint(point.x, fma(copysign(arcRadius, lastDiff.dy), -1.528664, nextPoint.y))
      relayPointA = NSMakePoint(fma(copysign(arcRadius, nextDiff.dx), 0.074911, point.x),
                                fma(copysign(arcRadius, lastDiff.dy), -0.631494, nextPoint.y))
      controlPointA1 = NSMakePoint(point.x, fma(copysign(arcRadius, lastDiff.dy), -1.088493, nextPoint.y))
      controlPointA2 = NSMakePoint(point.x, fma(copysign(arcRadius, lastDiff.dy), -0.868407, nextPoint.y))
      relayPointB = NSMakePoint(fma(copysign(arcRadius, nextDiff.dx), 0.631494, point.x),
                                fma(copysign(arcRadius, lastDiff.dy), -0.074911, nextPoint.y))
      controlPointB1 = NSMakePoint(fma(copysign(arcRadius, nextDiff.dx), 0.372824, point.x),
                                   fma(copysign(arcRadius, lastDiff.dy), -0.169060, nextPoint.y))
      controlPointB2 = NSMakePoint(fma(copysign(arcRadius, nextDiff.dx), 0.169060, point.x),
                                   fma(copysign(arcRadius, lastDiff.dy), -0.372824, nextPoint.y))
      endPoint = NSMakePoint(fma(copysign(arcRadius, nextDiff.dx), 1.528664, point.x), nextPoint.y)
      controlPoint1 = NSMakePoint(fma(copysign(arcRadius, nextDiff.dx), 0.868407, point.x), nextPoint.y)
      controlPoint2 = NSMakePoint(fma(copysign(arcRadius, nextDiff.dx), 1.088493, point.x), nextPoint.y)
    } else {
      arcRadius = min(cornerRadius, min(abs(nextDiff.dy), abs(lastDiff.dx)) * 0.3)
      startPoint = NSMakePoint(fma(copysign(arcRadius, lastDiff.dx), -1.528664, nextPoint.x), point.y)
      relayPointA = NSMakePoint(fma(copysign(arcRadius, lastDiff.dx), -0.631494, nextPoint.x),
                                fma(copysign(arcRadius, nextDiff.dy), 0.074911, point.y))
      controlPointA1 = NSMakePoint(fma(copysign(arcRadius, lastDiff.dx), -1.088493, nextPoint.x), point.y)
      controlPointA2 = NSMakePoint(fma(copysign(arcRadius, lastDiff.dx), -0.868407, nextPoint.x), point.y)
      relayPointB = NSMakePoint(fma(copysign(arcRadius, lastDiff.dx), -0.074911, nextPoint.x),
                                fma(copysign(arcRadius, nextDiff.dy), 0.631494, point.y))
      controlPointB1 = NSMakePoint(fma(copysign(arcRadius, lastDiff.dx), -0.169060, nextPoint.x),
                                   fma(copysign(arcRadius, nextDiff.dy), 0.372824, point.y))
      controlPointB2 = NSMakePoint(fma(copysign(arcRadius, lastDiff.dx), -0.372824, nextPoint.x),
                                   fma(copysign(arcRadius, nextDiff.dy), 0.169060, point.y))
      endPoint = NSMakePoint(nextPoint.x, fma(copysign(arcRadius, nextDiff.dy), 1.528664, point.y))
      controlPoint1 = NSMakePoint(nextPoint.x, fma(copysign(arcRadius, nextDiff.dy), 0.868407, point.y))
      controlPoint2 = NSMakePoint(nextPoint.x, fma(copysign(arcRadius, nextDiff.dy), 1.088493, point.y))
    }
    path.line(to: startPoint)
    path.curve(to: relayPointA, controlPoint1: controlPointA1, controlPoint2: controlPointA2)
    path.curve(to: relayPointB, controlPoint1: controlPointB1, controlPoint2: controlPointB2)
    path.curve(to: endPoint, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
  }
  path.close()
  return path
}

func rectVertices(_ rect: NSRect) -> [NSPoint] {
  return [rect.origin,
          NSMakePoint(NSMinX(rect), NSMaxY(rect)),
          NSMakePoint(NSMaxX(rect), NSMaxY(rect)),
          NSMakePoint(NSMaxX(rect), NSMinY(rect))]
}

func textPolygonVertices(_ textPolygon: SquirrelTextPolygon) -> [NSPoint] {
  switch (((NSIsEmptyRect(textPolygon.head) ? 1 : 0) << 2) +
          ((NSIsEmptyRect(textPolygon.body) ? 1 : 0) << 1) +
          ((NSIsEmptyRect(textPolygon.tail) ? 1 : 0) << 0)) {
  case 0b011:
    return rectVertices(textPolygon.head)
  case 0b110:
    return rectVertices(textPolygon.tail)
  case 0b101:
    return rectVertices(textPolygon.body)
  case 0b001:
    let headVertices: [NSPoint] = rectVertices(textPolygon.head)
    let bodyVertices: [NSPoint] = rectVertices(textPolygon.body)
    return [headVertices[0], headVertices[1],
            bodyVertices[0], bodyVertices[1],
            bodyVertices[2], headVertices[3]]
  case 0b100:
    let bodyVertices: [NSPoint] = rectVertices(textPolygon.body)
    let tailVertices: [NSPoint] = rectVertices(textPolygon.tail)
    return [bodyVertices[0], tailVertices[1],
            tailVertices[2], tailVertices[3],
            bodyVertices[2], bodyVertices[3]]
  case 0b010:
    if (NSMinX(textPolygon.head) <= NSMaxX(textPolygon.tail)) {
      let headVertices: [NSPoint] = rectVertices(textPolygon.head)
      let tailVertices: [NSPoint] = rectVertices(textPolygon.tail)
      return [headVertices[0], headVertices[1],
              tailVertices[0], tailVertices[1],
              tailVertices[2], tailVertices[3],
              headVertices[2], headVertices[3]]
    } else {
      return []
    }
  case 0b000:
    let headVertices: [NSPoint] = rectVertices(textPolygon.head)
    let bodyVertices: [NSPoint] = rectVertices(textPolygon.body)
    let tailVertices: [NSPoint] = rectVertices(textPolygon.tail)
    return [headVertices[0], headVertices[1],
            bodyVertices[0], tailVertices[1],
            tailVertices[2], tailVertices[3],
            bodyVertices[2], headVertices[3]]
  default:
    return []
  }
}

func any(_ array: [Boolean]) -> Boolean {
  for element in array {
    if (element) {
      return true
    }
  }
  return false
}

class NSFlippedView: NSView {
  override var isFlipped: Boolean { get { return true } }
}

func layoutTextView(_ view: NSTextView) -> NSRect {
  if #available(macOS 12.0, *) {
    view.textLayoutManager!.ensureLayout(for: view.textLayoutManager!.documentRange)
    return NSIntegralRect(view.textLayoutManager!.usageBoundsForTextContainer)
  } else {
    view.layoutManager!.ensureLayout(for: view.textContainer!)
    return NSIntegralRect(view.layoutManager!.usedRect(for: view.textContainer!))
  }
}

func setupTextView(forContentBlock contentBlock: SquirrelContentBlock,
                   textStorage: inout NSTextStorage) -> NSTextView {
  let textContainer: NSTextContainer = NSTextContainer(size: NSZeroSize)
  textContainer.lineFragmentPadding = 0
  if #available(macOS 12.0, *) {
    let textLayoutManager = SquirrelTextLayoutManager()
    textLayoutManager.contentBlock = contentBlock
    textLayoutManager.usesFontLeading = false
    textLayoutManager.usesHyphenation = false
    textLayoutManager.delegate = textLayoutManager
    textLayoutManager.textContainer = textContainer
    let contentStorage = NSTextContentStorage()
    contentStorage.addTextLayoutManager(textLayoutManager)
    contentStorage.textStorage = textStorage
  } else {
    let layoutManager = SquirrelLayoutManager()
    layoutManager.contentBlock = contentBlock
    layoutManager.backgroundLayoutEnabled = true
    layoutManager.usesFontLeading = false
    layoutManager.typesetterBehavior = .latestBehavior
    layoutManager.delegate = layoutManager
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
  }
  let textView = NSTextView(frame: NSZeroRect, textContainer: textContainer)
  textView.drawsBackground = false
  textView.isSelectable = false
  textView.wantsLayer = false
  textView.clipsToBounds = false
  return textView
}

class SquirrelView: NSView {
  // Need flipped coordinate system, as required by textStorage
  static var defaultTheme: SquirrelTheme = SquirrelTheme(appearance: .light)
  @available(macOS 10.14, *) static var darkTheme : SquirrelTheme = SquirrelTheme(appearance: .dark)
  private var _theme: SquirrelTheme
  var theme: SquirrelTheme { get { return _theme } }
  private var _textView: NSTextView
  var textView: NSTextView { get { return _textView } }
  private var _preeditView: NSTextView
  var preeditView: NSTextView { get { return _preeditView } }
  private var _pagingView: NSTextView
  var pagingView: NSTextView { get { return _pagingView } }
  private var _statusView: NSTextView
  var statusView: NSTextView { get { return _statusView } }
  private var _scrollView: NSScrollView
  var scrollView: NSScrollView { get { return _scrollView } }
  private var _documentView: NSFlippedView
  var documentView: NSFlippedView { get { return _documentView } }
  private var _contents: NSTextStorage
  var contents: NSTextStorage { get { return _contents } }
  private var _preeditContents: NSTextStorage
  var preeditContents: NSTextStorage { get { return _preeditContents } }
  private var _pagingContents: NSTextStorage
  var pagingContents: NSTextStorage { get { return _pagingContents } }
  private var _statusContents: NSTextStorage
  var statusContents: NSTextStorage { get { return _statusContents } }
  @available(macOS 10.14, *) private var _shape: CAShapeLayer?
  @available(macOS 10.14, *) var shape: CAShapeLayer? { get { return _shape } }
  private var _BackLayers = CALayer()
  var BackLayers: CALayer { get { return _BackLayers } }
  private var _backImageLayer = CAShapeLayer()
  var backImageLayer: CAShapeLayer { get { return _backImageLayer } }
  private var _backColorLayer = CAShapeLayer()
  var backColorLayer: CAShapeLayer { get { return _backColorLayer } }
  private var _borderLayer = CAShapeLayer()
  var borderLayer: CAShapeLayer { get { return _borderLayer } }
  private var _ForeLayers = CALayer()
  var ForeLayers: CALayer { get { return _ForeLayers } }
  private var _hilitedPreeditLayer = CAShapeLayer()
  var hilitedPreeditLayer: CAShapeLayer { get { return _hilitedPreeditLayer } }
  private var _functionButtonLayer = CAShapeLayer()
  var functionButtonLayer: CAShapeLayer { get { return _functionButtonLayer } }
  private var _logoLayer = CAShapeLayer()
  var logoLayer: CAShapeLayer { get { return _logoLayer } }
  private var _documentLayer = CAShapeLayer()
  var documentLayer: CAShapeLayer { get { return _documentLayer } }
  private var _hilitedCandidateLayer = CAShapeLayer()
  var hilitedCandidateLayer: CAShapeLayer { get { return _hilitedCandidateLayer } }
  private var _activePageLayer = CAShapeLayer()
  var activePageLayer: CAShapeLayer { get { return _activePageLayer } }
  private var _gridLayer = CAShapeLayer()
  var gridLayer: CAShapeLayer { get { return _gridLayer } }
  private var _tabularIndices: [SquirrelTabularIndex] = []
  var tabularIndices: [SquirrelTabularIndex] { get { return _tabularIndices } }
  private var _candidatePolygons: [SquirrelTextPolygon] = []
  var candidatePolygons: [SquirrelTextPolygon] { get { return _candidatePolygons } }
  private var _sectionRects: [NSRect] = []
  var sectionRects: [NSRect] { get { return _sectionRects } }
  private var _candidateRanges: [SquirrelCandidateRanges] = []
  var candidateRanges: [SquirrelCandidateRanges] { get { return _candidateRanges } }
  private var _truncated: [Boolean] = []
  var truncated: [Boolean] { get { return _truncated } }
  private var _contentRect: NSRect = NSZeroRect
  var contentRect: NSRect { get { return _contentRect } }
  private var _documentRect: NSRect = NSZeroRect
  var documentRect: NSRect { get { return _documentRect } }
  private var _preeditRect: NSRect = NSZeroRect
  var preeditRect: NSRect { get { return _preeditRect } }
  private var _candidatesRect: NSRect = NSZeroRect
  var candidatesRect: NSRect { get { return _candidatesRect } }
  private var _pagingRect: NSRect = NSZeroRect
  var pagingRect: NSRect { get { return _pagingRect } }
  private var _deleteBackRect: NSRect = NSZeroRect
  var deleteBackRect: NSRect { get { return _deleteBackRect } }
  private var _expanderRect: NSRect = NSZeroRect
  var expanderRect: NSRect { get { return _expanderRect } }
  private var _pageUpRect: NSRect = NSZeroRect
  var pageUpRect: NSRect { get { return _pageUpRect } }
  private var _pageDownRect: NSRect = NSZeroRect
  var pageDownRect: NSRect { get { return _pageDownRect } }
  private var _clippedHeight: Double = 0.0
  var clippedHeight: Double { get { return _clippedHeight } }
  private var _appear: SquirrelAppearance
  @objc var appear: SquirrelAppearance {
    get { return _appear }
    set (newValue) {
      if #available(macOS 10.14, *) {
        if (_appear != newValue) {
          _appear = newValue
          if (newValue == .dark) {
            _theme = SquirrelView.darkTheme
            _scrollView.scrollerKnobStyle = NSScroller.KnobStyle.light
          } else {
            _theme = SquirrelView.defaultTheme
            _scrollView.scrollerKnobStyle = NSScroller.KnobStyle.dark
          }
        }
      }
    }
  }
  private var _functionButton: SquirrelIndex = .VoidSymbol
  var functionButton: SquirrelIndex { get { return _functionButton } }
  private var _hilitedCandidate: Int = NSNotFound
  var hilitedIndex: Int { get { return _hilitedCandidate } }
  private var _hilitedPreeditRange: NSRange = NSMakeRange(NSNotFound, 0)
  var hilitedPreeditRange: NSRange { get { return _hilitedPreeditRange } }
  private var _expanded: Boolean = false
  var expanded: Boolean { get { return _expanded }
                          set (newValue) { _expanded = newValue } }
  override var isFlipped: Boolean { get { return true } }
  override var wantsUpdateLayer: Boolean { get { return true } }

  init() {
    _contents = NSTextStorage()
    _preeditContents = NSTextStorage()
    _pagingContents = NSTextStorage()
    _statusContents = NSTextStorage()
    _textView = setupTextView(forContentBlock: .stackedCandidates, textStorage: &_contents)
    _preeditView = setupTextView(forContentBlock: .preedit, textStorage: &_preeditContents)
    _pagingView = setupTextView(forContentBlock: .paging, textStorage: &_pagingContents)
    _statusView = setupTextView(forContentBlock: .status, textStorage: &_statusContents)

    _documentView = NSFlippedView()
    _documentView.wantsLayer = true
    _documentView.layer!.isGeometryFlipped = true
    _documentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
    _documentView.autoresizesSubviews = false
    _documentView.addSubview(_textView)
    _scrollView = NSScrollView()
    _scrollView.documentView = _documentView
    _scrollView.drawsBackground = false
    _scrollView.automaticallyAdjustsContentInsets = false
    _scrollView.hasVerticalScroller = true
    _scrollView.scrollerStyle = .overlay
    _scrollView.scrollerKnobStyle = .dark

    _appear = .light
    _theme = SquirrelView.defaultTheme
    if #available(macOS 10.14, *) {
      _shape = CAShapeLayer()
      _shape!.fillColor = CGColor.black
    }

    super.init(frame: NSZeroRect)
    wantsLayer = true
    layer!.isGeometryFlipped = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay

    let backMaskLayer = CAShapeLayer()
    backMaskLayer.fillColor = CGColor.black
    _BackLayers.mask = backMaskLayer
    _backImageLayer.actions = ["affineTransform": NSNull()]
    _backColorLayer.fillRule = .evenOdd
    _borderLayer.fillRule = .evenOdd
    self.layer!.addSublayer(_BackLayers)
    _BackLayers.addSublayer(_backImageLayer)
    _BackLayers.addSublayer(_backColorLayer)
    _BackLayers.addSublayer(_borderLayer)

    let foreMaskLayer = CAShapeLayer()
    foreMaskLayer.fillColor = CGColor.black
    _ForeLayers.mask = foreMaskLayer
    _logoLayer.actions = ["affineTransform": NSNull()]
    self.layer!.addSublayer(_ForeLayers)
    _ForeLayers.addSublayer(_hilitedPreeditLayer)
    _ForeLayers.addSublayer(_functionButtonLayer)
    _ForeLayers.addSublayer(_logoLayer)

    _documentLayer.fillRule = .evenOdd
    _gridLayer.lineWidth = 1.0
    _documentView.layer!.addSublayer(_documentLayer)
    _documentLayer.addSublayer(_activePageLayer)
    _documentView.layer!.addSublayer(_gridLayer)
    _documentView.layer!.addSublayer(_hilitedCandidateLayer)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateColors() {
    _backColorLayer.fillColor = (_theme.preeditBackColor ?? _theme.backColor).cgColor
    _borderLayer.fillColor = (_theme.borderColor ?? _theme.backColor).cgColor
    _documentLayer.fillColor = _theme.backColor.cgColor
    if (_theme.backImage?.isValid ?? false) {
      _backImageLayer.fillColor = NSColor(patternImage: _theme.backImage!).cgColor
      _backImageLayer.isHidden = false
    } else {
      _backImageLayer.isHidden = true
    }
    if (_theme.hilitedPreeditBackColor != nil) {
      _hilitedPreeditLayer.fillColor = _theme.hilitedPreeditBackColor?.cgColor
    } else {
      _hilitedPreeditLayer.isHidden = true
    }
    if (_theme.hilitedCandidateBackColor != nil) {
      _hilitedCandidateLayer.fillColor = _theme.hilitedCandidateBackColor?.cgColor
    } else {
      _hilitedCandidateLayer.isHidden = true
    }
    if (_theme.tabular) {
      _activePageLayer.fillColor = _theme.backColor.hooverColor.cgColor
      _gridLayer.strokeColor = _theme.commentForeColor.blended(withFraction: 0.8, of: _theme.backColor)?.cgColor
    } else {
      _activePageLayer.isHidden = true
      _gridLayer.isHidden = true
    }
  }

  @available(macOS 12.0, *)
  private func textRange(fromCharRange charRange: NSRange) -> NSTextRange? {
    if (charRange.location == NSNotFound) {
      return nil
    } else {
      let storage: NSTextContentStorage! = textView.textContentStorage
      let start: NSTextLocation! = storage.location(storage.documentRange.location,
                                                    offsetBy: charRange.location)
      let end: NSTextLocation! = storage.location(start, offsetBy: charRange.length)
      return NSTextRange(location: start, end: end)
    }
  }

  @available(macOS 12.0, *)
  private func charRange(fromTextRange textRange: NSTextRange?) -> NSRange {
    if (textRange == nil) {
      return NSMakeRange(NSNotFound, 0)
    } else {
      let contentStorage: NSTextContentStorage! = textView.textContentStorage
      let location: Int = contentStorage.offset(from: contentStorage.documentRange.location,
                                                to: textRange!.location)
      let length: Int = contentStorage.offset(from: textRange!.location,
                                              to: textRange!.endLocation)
      return NSMakeRange(location, length)
    }
  }

  func estimateBounds(onScreen screen: NSRect,
                      withPreedit hasPreedit: Boolean,
                      candidates candidateRanges: [SquirrelCandidateRanges],
                      truncation truncated: [Boolean],
                      paging hasPaging: Boolean) {
    _candidateRanges = candidateRanges
    _truncated = truncated
    _preeditView.isHidden = !hasPreedit
    _scrollView.isHidden = candidateRanges.count == 0
    _pagingView.isHidden = !hasPaging
    _statusView.isHidden = hasPreedit || candidateRanges.count > 0
    // layout textviews and get their sizes
    _preeditRect = NSZeroRect
    _documentRect = NSZeroRect // in textView's own coordinates
    _candidatesRect = NSZeroRect
    _pagingRect = NSZeroRect
    _clippedHeight = 0.0
    if (!hasPreedit && candidateRanges.count == 0) {  // status
      _contentRect = layoutTextView(_statusView)
      return
    }
    if (hasPreedit) {
      _preeditRect = layoutTextView(_preeditView)
      _contentRect = _preeditRect
    }
    if (candidateRanges.count > 0) {
      _documentRect = layoutTextView(_textView)
      if #available(macOS 12.0, *) {
        _documentRect.size.height += _theme.lineSpacing
      } else {
        _documentRect.size.height += _theme.linear ? 0.0 : _theme.lineSpacing
      }
      if (_theme.linear && !any(truncated)) {
        _documentRect.size.width -= _theme.fullWidth
      }
      _candidatesRect.size = _documentRect.size
      _documentRect.size.width += _theme.fullWidth
      if (hasPreedit) {
        _candidatesRect.origin.y = NSMaxY(_preeditRect) + _theme.preeditSpacing
        _contentRect = NSUnionRect(_preeditRect, _candidatesRect)
      } else {
        _contentRect = _candidatesRect
      }
      if (hasPaging) {
        _pagingRect = layoutTextView(_pagingView)
        _pagingRect.origin.y = NSMaxY(_candidatesRect)
        _contentRect = NSUnionRect(_contentRect, _pagingRect)
      }
    } else {
      return
    }
    // clip candidate block if it has too many lines
    let maxHeight: Double = (_theme.vertical ? NSWidth(screen) : NSHeight(screen)) * 0.5 -
                            _theme.borderInsets.height * 2
    _clippedHeight = fdim(ceil(NSHeight(_contentRect)), ceil(maxHeight))
    _contentRect.size.height -= _clippedHeight
    _candidatesRect.size.height -= _clippedHeight
    _scrollView.verticalScroller?.knobProportion = NSHeight(_candidatesRect) / NSHeight(_documentRect)
  }

  // Get the rectangle containing entire contents
  func layoutContents() {
    let origin: NSPoint = NSMakePoint(_theme.borderInsets.width,
                                      _theme.borderInsets.height)
    if (!_statusView.isHidden) {  // status
      _contentRect.origin = NSMakePoint(origin.x + ceil(_theme.fullWidth * 0.5), origin.y)
      return;
    }
    if (!_preeditView.isHidden) {
      _preeditRect = layoutTextView(_preeditView)
      _preeditRect.size.width += _theme.fullWidth
      _preeditRect.origin = origin
      _contentRect = _preeditRect
    }
    if (!_scrollView.isHidden) {
      _candidatesRect.size.width = NSWidth(_documentRect)
      _candidatesRect.size.height = NSHeight(_documentRect) - _clippedHeight
      if (!_preeditView.isHidden) {
        _candidatesRect.origin.x = origin.x
        _candidatesRect.origin.y = NSMaxY(_preeditRect) + _theme.preeditSpacing
        _contentRect = NSUnionRect(_preeditRect, _candidatesRect)
      } else {
        _candidatesRect.origin = origin
        _contentRect = _candidatesRect
      }
      if (!_pagingView.isHidden) {
        _pagingRect = layoutTextView(_pagingView)
        _pagingRect.size.width += _theme.fullWidth
        _pagingRect.origin.x = origin.x
        _pagingRect.origin.y = NSMaxY(_candidatesRect)
        _contentRect = NSUnionRect(_contentRect, _pagingRect);
      }
      _contentRect.size.width -= _theme.fullWidth
      _contentRect.origin.x += ceil(_theme.fullWidth * 0.5)
    }
  }

  // Get the rectangle containing the range of text
  func blockRect(forRange charRange: NSRange,
                 inView view: NSTextView) -> NSRect {
    if (charRange.location == NSNotFound) {
      return NSZeroRect
    }
    if #available(macOS 12.0, *) {
      let layoutManager = view.textLayoutManager as! SquirrelTextLayoutManager
      let textRange: NSTextRange! = textRange(fromCharRange: charRange)
      var firstLineRect: NSRect = NSZeroRect
      var finalLineRect: NSRect = NSZeroRect
      layoutManager.enumerateTextSegments(
        in: textRange,
        type: .standard,
        options: [.rangeNotRequired],
        using: { (segRange: NSTextRange?, segFrame: CGRect, baseline: CGFloat,
                  textContainer: NSTextContainer) in
          if (!CGRectIsEmpty(segFrame)) {
            if (NSIsEmptyRect(firstLineRect) ||
                CGRectGetMinY(segFrame) < NSMaxY(firstLineRect)) {
              firstLineRect = NSUnionRect(segFrame, firstLineRect)
            } else {
              finalLineRect = NSUnionRect(segFrame, finalLineRect)
            }
          }
          return true
      })
      let lineSpacing = layoutManager.contentBlock == .linearCandidates
        ? _theme.lineSpacing : 0.0
      if (lineSpacing > 0.1) {
        firstLineRect.size.height += lineSpacing
        if (!NSIsEmptyRect(finalLineRect)) {
          finalLineRect.size.height += lineSpacing
        }
      }

      if (NSIsEmptyRect(finalLineRect)) {
        return firstLineRect
      } else {
        let containerWidth: Double = NSWidth(view.textLayoutManager!.usageBoundsForTextContainer)
        return NSMakeRect(0.0, NSMinY(firstLineRect), containerWidth,
                          NSMaxY(finalLineRect) - NSMinY(firstLineRect))
      }
    } else {
      let glyphRange: NSRange = view.layoutManager!
        .glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      var firstLineRange: NSRange = NSMakeRange(NSNotFound, 0)
      let firstLineRect: NSRect = view.layoutManager!
        .lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &firstLineRange)
      if (NSMaxRange(glyphRange) <= NSMaxRange(firstLineRange)) {
        let leading: CGFloat = view.layoutManager!.location(forGlyphAt: glyphRange.location).x
        let trailing: CGFloat = NSMaxRange(glyphRange) < NSMaxRange(firstLineRange)
        ? view.layoutManager!.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(firstLineRect)
        return NSMakeRect(NSMinX(firstLineRect) + leading, NSMinY(firstLineRect),
                          trailing - leading, NSHeight(firstLineRect))
      } else {
        let finalLineRect: NSRect = view.layoutManager!
          .lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphRange) - 1, effectiveRange: nil)
        let containerWidth: Double = NSWidth(view.layoutManager!.usedRect(for: view.textContainer!))
        return NSMakeRect(0.0, NSMinY(firstLineRect), containerWidth,
                          NSMaxY(finalLineRect) - NSMinY(firstLineRect))
      }
    }
  }

  /* Calculate 3 rectangles encloding the text in range. TextPolygon.head & .tail are incomplete line fragments
     TextPolygon.body is the complete line fragment in the middle if the range spans no less than one full line */
  private func textPolygon(forRange charRange: NSRange,
                           inView view: NSTextView) -> SquirrelTextPolygon {
    var textPolygon: SquirrelTextPolygon = SquirrelTextPolygon(
      head: NSZeroRect, body: NSZeroRect, tail: NSZeroRect)
    if (charRange.location == NSNotFound) {
      return textPolygon
    }
    if #available(macOS 12.0, *) {
      let layoutManager = view.textLayoutManager as! SquirrelTextLayoutManager
      let textRange: NSTextRange! = textRange(fromCharRange: charRange)
      var headLineRect: NSRect = NSZeroRect
      var tailLineRect: NSRect = NSZeroRect
      var headLineRange: NSTextRange?
      var tailLineRange: NSTextRange?
      layoutManager.enumerateTextSegments(
        in: textRange,
        type: .standard,
        options: .middleFragmentsExcluded,
        using: { (segRange: NSTextRange?, segFrame: CGRect,
                  baseline: CGFloat, textContainer: NSTextContainer) in
        if (!CGRectIsEmpty(segFrame)) {
          if (NSIsEmptyRect(headLineRect) ||
              CGRectGetMinY(segFrame) < NSMaxY(headLineRect)) {
            headLineRect = NSUnionRect(segFrame, headLineRect)
            headLineRange = headLineRange == nil ? segRange! : segRange!.union(headLineRange!)
          } else {
            tailLineRect = NSUnionRect(segFrame, tailLineRect)
            tailLineRange = tailLineRange == nil ? segRange! : segRange!.union(tailLineRange!)
          }
        }
        return true
      })
      let lineSpacing = layoutManager.contentBlock == .linearCandidates
      ? _theme.lineSpacing : 0.0
      if (lineSpacing > 0.1) {
        headLineRect.size.height += lineSpacing
        if (!NSIsEmptyRect(tailLineRect)) {
          tailLineRect.size.height += lineSpacing
        }
      }

      if (NSIsEmptyRect(tailLineRect)) {
        textPolygon.body = headLineRect
      } else {
        let containerWidth: Double = NSWidth(view.textLayoutManager!.usageBoundsForTextContainer)
        headLineRect.size.width = containerWidth - NSMinX(headLineRect)
        if (abs(NSMaxX(tailLineRect) - NSMaxX(headLineRect)) < 1) {
          if (abs(NSMinX(headLineRect) - NSMinX(tailLineRect)) < 1) {
            textPolygon.body = NSUnionRect(headLineRect, tailLineRect)
          } else {
            textPolygon.head = headLineRect
            textPolygon.body = NSMakeRect(0.0, NSMaxY(headLineRect), containerWidth,
                                          NSMaxY(tailLineRect) - NSMaxY(headLineRect))
          }
        } else {
          textPolygon.tail = tailLineRect
          if (abs(NSMinX(headLineRect) - NSMinX(tailLineRect)) < 1) {
            textPolygon.body = NSMakeRect(0.0, NSMinY(headLineRect), containerWidth,
                                          NSMinY(tailLineRect) - NSMinY(headLineRect))
          } else {
            textPolygon.head = headLineRect
            if (!tailLineRange!.contains(headLineRange!.endLocation)) {
              textPolygon.body = NSMakeRect(0.0, NSMaxY(headLineRect), containerWidth,
                                            NSMinY(tailLineRect) - NSMaxY(headLineRect))
            }
          }
        }
      }
    } else {
      let glyphRange: NSRange = view.layoutManager!
        .glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      var headLineRange: NSRange = NSMakeRange(NSNotFound, 0)
      let headLineRect: NSRect = view.layoutManager!
        .lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &headLineRange)
      let leading: Double = view.layoutManager!.location(forGlyphAt: glyphRange.location).x
      if (NSMaxRange(headLineRange) >= NSMaxRange(glyphRange)) {
        let trailing: Double = NSMaxRange(glyphRange) < NSMaxRange(headLineRange)
        ? view.layoutManager!.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(headLineRect)
        textPolygon.body = NSMakeRect(leading, NSMinY(headLineRect),
                                      trailing - leading, NSHeight(headLineRect))
      } else {
        let containerWidth: Double = NSWidth(view.layoutManager!.usedRect(for: view.textContainer!))
        var tailLineRange: NSRange = NSMakeRange(NSNotFound, 0)
        let tailLineRect: NSRect = view.layoutManager!
          .lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphRange) - 1, effectiveRange:&tailLineRange)
        let trailing: Double = NSMaxRange(glyphRange) < NSMaxRange(tailLineRange)
        ? view.layoutManager!.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(tailLineRect)
        if (NSMaxRange(tailLineRange) == NSMaxRange(glyphRange)) {
          if (glyphRange.location == headLineRange.location) {
            textPolygon.body = NSMakeRect(0.0, NSMinY(headLineRect), containerWidth,
                                          NSMaxY(tailLineRect) - NSMinY(headLineRect))
          } else {
            textPolygon.head = NSMakeRect(leading, NSMinY(headLineRect),
                                          containerWidth - leading, NSHeight(headLineRect))
            textPolygon.body = NSMakeRect(0.0, NSMaxY(headLineRect), containerWidth,
                                              NSMaxY(tailLineRect) - NSMaxY(headLineRect))
          }
        } else {
          textPolygon.tail = NSMakeRect(0.0, NSMinY(tailLineRect),
                                        trailing, NSHeight(tailLineRect))
          if (glyphRange.location == headLineRange.location) {
            textPolygon.body = NSMakeRect(0.0, NSMinY(headLineRect), containerWidth,
                                              NSMinY(tailLineRect) - NSMinY(headLineRect))
          } else {
            textPolygon.head = NSMakeRect(leading, NSMinY(headLineRect),
                                          containerWidth - leading, NSHeight(headLineRect))
            if (tailLineRange.location > NSMaxRange(headLineRange)) {
              textPolygon.body = NSMakeRect(0.0, NSMaxY(headLineRect), containerWidth,
                                            NSMinY(tailLineRect) - NSMaxY(headLineRect))
            }
          }
        }
      }
    }
    return textPolygon
  }

  // Will triger `updateLayer()`
  func drawView(withHilitedCandidate hilitedCandidate: Int,
                hilitedPreeditRange: NSRange) {
    _hilitedCandidate = hilitedCandidate
    _hilitedPreeditRange = hilitedPreeditRange
    _functionButton = .VoidSymbol
    // invalidate Rect beyond bound of textview to clear any out-of-bound drawing from last round
    setNeedsDisplay(self.bounds)
    if (!_statusView.isHidden) {
      _statusView.setNeedsDisplay(_statusView.bounds)
    } else {
      if (!_preeditView.isHidden) {
        _preeditView.setNeedsDisplay(_preeditView.bounds)
      }
      // invalidate Rect beyond bound of textview to clear any out-of-bound drawing from last round
      if (!_scrollView.isHidden) {
        _textView.setNeedsDisplay(_documentView.convert(_documentView.bounds, to: _textView))
      }
      if (!_pagingView.isHidden) {
        _pagingView.setNeedsDisplay(_pagingView.bounds)
      }
    }
    layoutContents()
  }

  func setPreedit(hilitedPreeditRange: NSRange) {
    _hilitedPreeditRange = hilitedPreeditRange
    setNeedsDisplay(_preeditRect)
    _preeditView.setNeedsDisplay(_preeditView.bounds)
    layoutContents()
  }

  func highlightCandidate(_ hilitedCandidate: Int) {
    if (expanded) {
      let priorActivePage: Int = _hilitedCandidate / _theme.pageSize
      let newActivePage: Int = hilitedCandidate / _theme.pageSize
      if (newActivePage != priorActivePage) {
        setNeedsDisplay(_documentView.convert(_sectionRects[priorActivePage], to: self))
        _textView.setNeedsDisplay(_documentView.convert(_sectionRects[priorActivePage], to: _textView))
      }
      setNeedsDisplay(_documentView.convert(_sectionRects[newActivePage], to: self))
      _textView.setNeedsDisplay(_documentView.convert(_sectionRects[newActivePage], to: _textView))

      if (NSMinY(_sectionRects[newActivePage]) < NSMinY(_scrollView.documentVisibleRect) - 0.1) {
        var origin: NSPoint = _scrollView.contentView.bounds.origin
        origin.y -= NSMinY(_scrollView.documentVisibleRect) - NSMinY(_sectionRects[newActivePage])
        _scrollView.contentView.scroll(to: origin)
        _scrollView.verticalScroller?.doubleValue = NSMinY(_scrollView.documentVisibleRect) / _clippedHeight
      } else if (NSMaxY(_sectionRects[newActivePage]) > NSMaxY(_scrollView.documentVisibleRect) + 0.1) {
        var origin: NSPoint = _scrollView.contentView.bounds.origin
        origin.y += NSMaxY(_sectionRects[newActivePage]) - NSMaxY(_scrollView.documentVisibleRect)
        _scrollView.contentView.scroll(to: origin)
        _scrollView.verticalScroller?.doubleValue = NSMinY(_scrollView.documentVisibleRect) / _clippedHeight
      }
    } else {
      setNeedsDisplay(_candidatesRect)
      _textView.setNeedsDisplay(_documentView.convert(_documentView.bounds, to: _textView))

      if (NSMinY(_scrollView.documentVisibleRect) > _candidatePolygons[hilitedCandidate].minY() + 0.1) {
        var origin: NSPoint = _scrollView.contentView.bounds.origin
        origin.y -= NSMinY(_scrollView.documentVisibleRect) - _candidatePolygons[hilitedCandidate].minY()
        _scrollView.contentView.scroll(to: origin)
        _scrollView.verticalScroller?.doubleValue = NSMinY(_scrollView.documentVisibleRect) / _clippedHeight
      } else if (NSMaxY(_scrollView.documentVisibleRect) < _candidatePolygons[hilitedCandidate].maxY() - 0.1) {
        var origin: NSPoint = _scrollView.contentView.bounds.origin
        origin.y += _candidatePolygons[hilitedCandidate].maxY() - NSMaxY(_scrollView.documentVisibleRect)
        _scrollView.contentView.scroll(to: origin)
        _scrollView.verticalScroller?.doubleValue = NSMinY(_scrollView.documentVisibleRect) / _clippedHeight
      }
    }
    _hilitedCandidate = hilitedCandidate
  }

  func highlightFunctionButton(_ functionButton: SquirrelIndex) {
    for funcBttn in [_functionButton, functionButton] {
      switch (funcBttn) {
      case .BackSpaceKey, .EscapeKey:
        setNeedsDisplay(_deleteBackRect)
        _preeditView.setNeedsDisplay(convert(_deleteBackRect, to: _preeditView),
                                     avoidAdditionalLayout: true)
        break
      case .PageUpKey, .HomeKey:
        setNeedsDisplay(_pageUpRect)
        _pagingView.setNeedsDisplay(convert(_pageUpRect, to: _pagingView),
                                    avoidAdditionalLayout: true)
        break
      case .PageDownKey, .EndKey:
        setNeedsDisplay(_pageDownRect)
        _pagingView.setNeedsDisplay(convert(_pageDownRect, to: _pagingView),
                                    avoidAdditionalLayout: true)
        break
      case .ExpandButton, .CompressButton, .LockButton:
        setNeedsDisplay(_expanderRect)
        _pagingView.setNeedsDisplay(convert(_expanderRect, to: _pagingView),
                                    avoidAdditionalLayout: true)
        break
      default:
        break
      }
    }
    _functionButton = functionButton
  }

  private func updateFunctionButtonLayer() {
    var buttonColor: NSColor!
    var buttonRect: NSRect = NSZeroRect
    switch (functionButton) {
    case .PageUpKey:
      buttonColor = _theme.hilitedPreeditBackColor?.hooverColor
      buttonRect = _pageUpRect
      break
    case .HomeKey:
      buttonColor = _theme.hilitedPreeditBackColor?.disabledColor
      buttonRect = _pageUpRect
      break
    case .PageDownKey:
      buttonColor = _theme.hilitedPreeditBackColor?.hooverColor
      buttonRect = _pageDownRect
      break
    case .EndKey:
      buttonColor = _theme.hilitedPreeditBackColor?.disabledColor
      buttonRect = _pageDownRect
      break
    case .ExpandButton, .CompressButton, .LockButton:
      buttonColor = _theme.hilitedPreeditBackColor?.hooverColor
      buttonRect = _expanderRect
      break
    case .BackSpaceKey:
      buttonColor = _theme.hilitedPreeditBackColor?.hooverColor
      buttonRect = _deleteBackRect
      break
    case .EscapeKey:
      buttonColor = _theme.hilitedPreeditBackColor?.disabledColor
      buttonRect = _deleteBackRect
      break
    default:
      break
    }
    if (!NSIsEmptyRect(buttonRect) && (buttonColor != nil)) {
      let cornerRadius: Double = min(_theme.hilitedCornerRadius,
                                     NSHeight(buttonRect) * 0.5)
      let buttonPath: NSBezierPath! = squirclePath(rect: buttonRect,
                                                   cornerRadius: cornerRadius)
      _functionButtonLayer.path = buttonPath.quartzPath
      _functionButtonLayer.fillColor = buttonColor.cgColor
      _functionButtonLayer.isHidden = false
    } else {
      _functionButtonLayer.isHidden = true
    }
  }

  // All draws happen here
  override func updateLayer() {
    let panelRect: NSRect = bounds
    let backgroundRect: NSRect = backingAlignedRect(NSInsetRect(
      panelRect, _theme.borderInsets.width, _theme.borderInsets.height),
                                                    options: .alignAllEdgesNearest)

    /*** Preedit Rects **/
    _deleteBackRect = NSZeroRect
    var hilitedPreeditPath: NSBezierPath?
    if (!_preeditView.isHidden) {
      _preeditRect.size.width = NSWidth(backgroundRect)
      _preeditRect = backingAlignedRect(_preeditRect, options: .alignAllEdgesNearest)
      // Draw the highlighted part of preedit text
      let cornerRadius: Double = min(_theme.hilitedCornerRadius,
                                     _theme.preeditParagraphStyle.minimumLineHeight * 0.5)
      if (_hilitedPreeditRange.length > 0 && (_theme.hilitedPreeditBackColor != nil)) {
        let padding: Double = ceil(_theme.preeditParagraphStyle.minimumLineHeight * 0.05)
        var innerBox: NSRect = _preeditRect
        innerBox.origin.x += ceil(_theme.fullWidth * 0.5) - padding
        innerBox.size.width = NSWidth(backgroundRect) - _theme.fullWidth + padding * 2
        innerBox = backingAlignedRect(innerBox, options: .alignAllEdgesNearest)
        var textPolygon: SquirrelTextPolygon = textPolygon(forRange: _hilitedPreeditRange,
                                                           inView: _preeditView)
        if (!NSIsEmptyRect(textPolygon.head)) {
          textPolygon.head.origin.x += _theme.borderInsets.width +
          ceil(_theme.fullWidth * 0.5) - padding
          textPolygon.head.origin.y += _theme.borderInsets.height
          textPolygon.head.size.width += padding * 2
          textPolygon.head = backingAlignedRect(NSIntersectionRect(textPolygon.head, innerBox),
                                                options: .alignAllEdgesNearest)
        }
        if (!NSIsEmptyRect(textPolygon.body)) {
          textPolygon.body.origin.x += _theme.borderInsets.width +
          ceil(_theme.fullWidth * 0.5) - padding
          textPolygon.body.origin.y += _theme.borderInsets.height
          textPolygon.body.size.width += padding
          if (!NSIsEmptyRect(textPolygon.tail) ||
              NSMaxRange(_hilitedPreeditRange) + 2 == _preeditContents.length) {
            textPolygon.body.size.width += padding
          }
          textPolygon.body = backingAlignedRect(NSIntersectionRect(textPolygon.body, innerBox),
                                                options: .alignAllEdgesNearest)
        }
        if (!NSIsEmptyRect(textPolygon.tail)) {
          textPolygon.tail.origin.x += _theme.borderInsets.width +
          ceil(_theme.fullWidth * 0.5) - padding
          textPolygon.tail.origin.y += _theme.borderInsets.height
          textPolygon.tail.size.width += padding
          if (NSMaxRange(_hilitedPreeditRange) + 2 == _preeditContents.length) {
            textPolygon.tail.size.width += padding
          }
          textPolygon.tail = backingAlignedRect(NSIntersectionRect(textPolygon.tail, innerBox),
                                                options: .alignAllEdgesNearest)
        }
        hilitedPreeditPath = squirclePath(polygon: textPolygon, cornerRadius: cornerRadius)
      }
      _deleteBackRect = blockRect(forRange: NSMakeRange(_preeditContents.length - 1, 1),
                                  inView: _preeditView)
      _deleteBackRect.size.width += _theme.fullWidth
      _deleteBackRect.origin.x = NSMaxX(backgroundRect) - NSWidth(_deleteBackRect)
      _deleteBackRect.origin.y += _theme.borderInsets.height
      _deleteBackRect = backingAlignedRect(NSIntersectionRect(_deleteBackRect, _preeditRect),
                                           options: .alignAllEdgesNearest)
    }

    /*** Candidates Rects, all in documentView coordinates (except for `candidatesRect`) ***/
    _candidatePolygons = []
    _sectionRects = []
    _tabularIndices = []
    var candidatesPath: NSBezierPath?, documentPath: NSBezierPath?, gridPath: NSBezierPath?
    if (!_scrollView.isHidden) {
      _candidatesRect.size.width = NSWidth(backgroundRect)
      _candidatesRect = backingAlignedRect(NSIntersectionRect(_candidatesRect, backgroundRect),
                                           options: .alignAllEdgesNearest)
      _documentRect.size.width = NSWidth(backgroundRect)
      _documentRect = _documentView.backingAlignedRect(_documentRect, options: .alignAllEdgesNearest)
      let blockCornerRadius: Double = min(_theme.hilitedCornerRadius,
                                          NSHeight(_candidatesRect) * 0.5);
      candidatesPath = squirclePath(rect: _candidatesRect, cornerRadius: blockCornerRadius)
      documentPath = squirclePath(rect: _documentRect, cornerRadius: blockCornerRadius)

      // Draw candidate highlight rect
      if (_theme.linear) {  // linear layout
        var gridOriginY: Double = NSMinY(_documentRect)
        let tabInterval: Double = theme.fullWidth * 2
        var lineNum: Int = 0
        var sectionRect: NSRect = _documentRect
        if (_theme.tabular) {
          gridPath = NSBezierPath()
          sectionRect.size.height = 0
        }
        for i in 0..<_candidateRanges.count {
          var candidatePolygon: SquirrelTextPolygon = textPolygon(forRange: _candidateRanges[i].candidateRange(),
                                                                  inView: _textView)
          if (!NSIsEmptyRect(candidatePolygon.head)) {
            candidatePolygon.head.size.width += _theme.fullWidth
            candidatePolygon.head = _documentView.backingAlignedRect(NSIntersectionRect(candidatePolygon.head, _documentRect),
                                                                     options: .alignAllEdgesNearest)
          }
          if (!NSIsEmptyRect(candidatePolygon.tail)) {
            candidatePolygon.tail = _documentView.backingAlignedRect(NSIntersectionRect(candidatePolygon.tail, _documentRect),
                                                                     options: .alignAllEdgesNearest)
          }
          if (!NSIsEmptyRect(candidatePolygon.body)) {
            if (_truncated[i]) {
              candidatePolygon.body.size.width = NSWidth(_documentRect)
            } else if (!NSIsEmptyRect(candidatePolygon.tail)) {
              candidatePolygon.body.size.width += _theme.fullWidth
            }
            candidatePolygon.body = _documentView.backingAlignedRect(NSIntersectionRect(candidatePolygon.body, _documentRect),
                                                                     options: .alignAllEdgesNearest)
          }
          if (_theme.tabular) {
            if (_expanded) {
              if (i % _theme.pageSize == 0) {
                sectionRect.origin.y = ceil(NSMaxY(sectionRect))
              } else if (i % _theme.pageSize == _theme.pageSize - 1 || i == _candidateRanges.count - 1) {
                sectionRect.size.height = candidatePolygon.maxY()
                let sec: Int = i / _theme.pageSize
                _sectionRects[sec] = sectionRect
              }
            }
            let bottomEdge: Double = candidatePolygon.maxY()
            if (Swift.abs(bottomEdge - gridOriginY) > 2) {
              lineNum += i > 0 ? 1 : 0
              // horizontal border except for the last line
              if (bottomEdge < NSMaxY(_documentRect) - 2) {
                gridPath!.move(to: NSMakePoint(ceil(_theme.fullWidth * 0.5), bottomEdge))
                gridPath!.line(to: NSMakePoint(NSMaxX(_documentRect) - floor(_theme.fullWidth * 0.5), bottomEdge))
              }
              gridOriginY = bottomEdge
            }
            let leadOrigin: CGPoint = candidatePolygon.origin()
            let leadTabColumn: Int = Int(round((leadOrigin.x - NSMinX(_documentRect)) / tabInterval))
            // vertical bar
            if (leadOrigin.x > NSMinX(_candidatesRect) + _theme.fullWidth) {
              gridPath!.move(to: NSMakePoint(leadOrigin.x, leadOrigin.y + _theme.candidateParagraphStyle.minimumLineHeight * 0.3))
              gridPath!.line(to: NSMakePoint(leadOrigin.x, candidatePolygon.maxY() - _theme.candidateParagraphStyle.minimumLineHeight * 0.3))
            }
            _tabularIndices.append(SquirrelTabularIndex(index: i, lineNum: lineNum, tabNum: leadTabColumn))
          }
          _candidatePolygons.append(candidatePolygon)
        }
      } else { // stacked layout
        for i in 0..<_candidateRanges.count {
          var candidateRect: NSRect = blockRect(forRange: _candidateRanges[i].candidateRange(), inView: _textView)
          candidateRect.size.width = NSWidth(_documentRect)
          candidateRect.size.height += _theme.lineSpacing
          candidateRect = _documentView.backingAlignedRect(candidateRect, options: .alignAllEdgesNearest)
          _candidatePolygons.append(SquirrelTextPolygon(head: NSZeroRect, body: candidateRect, tail: NSZeroRect))
        }
      }
    }

    /*** Paging Rects ***/
    _pageUpRect = NSZeroRect
    _pageDownRect = NSZeroRect
    _expanderRect = NSZeroRect
    if (!_pagingView.isHidden) {
      if (_theme.linear) {
        _pagingRect.origin.x = NSMaxX(backgroundRect) - NSWidth(_pagingRect)
      } else {
        _pagingRect.size.width = NSWidth(backgroundRect)
      }
      if (_theme.showPaging) {
        _pageUpRect = blockRect(forRange: NSMakeRange(0, 1),
                                inView: _pagingView)
        _pageDownRect = blockRect(forRange: NSMakeRange(_pagingContents.length - 1, 1),
                                  inView: _pagingView)
        _pageDownRect.origin.x += NSMinX(_pagingRect)
        _pageDownRect.size.width += _theme.fullWidth
        _pageDownRect.origin.y += NSMinY(_pagingRect)
        _pageUpRect.origin.x += NSMinX(_pagingRect)
        // bypass the bug of getting wrong glyph position when tab is presented
        _pageUpRect.size.width = NSWidth(_pageDownRect)
        _pageUpRect.origin.y += NSMinY(_pagingRect)
        _pageUpRect = backingAlignedRect(NSIntersectionRect(_pageUpRect, _pagingRect),
                                         options: .alignAllEdgesNearest)
        _pageDownRect = backingAlignedRect(NSIntersectionRect(_pageDownRect, _pagingRect),
                                           options: .alignAllEdgesNearest)
      }
      if (_theme.tabular) {
        _expanderRect = blockRect(forRange: NSMakeRange(_pagingContents.length / 2, 1),
                                  inView: _pagingView)
        _expanderRect.origin.x += NSMinX(_pagingRect);
        _expanderRect.size.width += _theme.fullWidth;
        _expanderRect.origin.y += NSMinY(_pagingRect);
        _expanderRect = backingAlignedRect(NSIntersectionRect(_expanderRect, _pagingRect),
                                           options: .alignAllEdgesNearest)
      }
    }

    /*** Border Rects ***/
    let outerCornerRadius: Double = min(_theme.cornerRadius, NSHeight(panelRect) * 0.5)
    let innerCornerRadius: Double = clamp(_theme.hilitedCornerRadius,
                                          outerCornerRadius - min(_theme.borderInsets.width,
                                                                  _theme.borderInsets.height),
                                          NSHeight(backgroundRect) * 0.5)
    var panelPath: NSBezierPath!, backgroundPath: NSBezierPath!
    if (!_theme.linear || _pagingView.isHidden) {
      panelPath = squirclePath(rect: panelRect,
                               cornerRadius: outerCornerRadius)
      backgroundPath = squirclePath(rect: backgroundRect,
                                    cornerRadius: innerCornerRadius)
    } else {
      var mainPanelRect: NSRect = panelRect
      mainPanelRect.size.height -= NSHeight(_pagingRect)
      let tailPanelRect: NSRect = NSInsetRect(NSOffsetRect(_pagingRect, 0, _theme.borderInsets.height),
                                              -_theme.borderInsets.width, 0)
      panelPath = squirclePath(polygon: SquirrelTextPolygon(head: mainPanelRect, body: tailPanelRect, tail: NSZeroRect),
                               cornerRadius: outerCornerRadius)
      var mainBackgroundRect: NSRect = backgroundRect
      mainBackgroundRect.size.height -= NSHeight(_pagingRect)
      backgroundPath = squirclePath(polygon: SquirrelTextPolygon(head: mainBackgroundRect, body: _pagingRect, tail: NSZeroRect),
                                    cornerRadius: innerCornerRadius)
    }
    let borderPath: NSBezierPath = panelPath.copy() as! NSBezierPath
    borderPath.append(backgroundPath)

    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: NSHeight(panelRect))
    flip.scaleX(by: 1, yBy: -1)
    let shapePath: NSBezierPath = flip.transform(panelPath)

    /*** Draw into layers ***/
    _shape?.path = shapePath.quartzPath
    // BackLayers: large background elements
    (_BackLayers.mask as! CAShapeLayer).path = panelPath.quartzPath
    if (_theme.backImage?.isValid ?? false) {
      // background image (pattern style) layer
      var transform: CGAffineTransform = _theme.vertical
      ? CGAffineTransformMakeRotation(.pi / 2) : CGAffineTransformIdentity
      transform = CGAffineTransformTranslate(transform, -backgroundRect.origin.x,
                                             -backgroundRect.origin.y)
      _backImageLayer.path = backgroundPath.quartzPath?.copy(using: &transform)
      _backImageLayer.setAffineTransform(CGAffineTransformInvert(transform))
    }
    // background color layer
    if (!NSIsEmptyRect(_preeditRect) || !NSIsEmptyRect(_pagingRect)) {
      if (candidatesPath != nil) {
        let nonCandidatePath = backgroundPath.copy() as! NSBezierPath
        nonCandidatePath.append(candidatesPath!)
        _backColorLayer.path = nonCandidatePath.quartzPath
      } else {
        _backColorLayer.path = backgroundPath.quartzPath
      }
      _backColorLayer.isHidden = false
    } else {
      _backColorLayer.isHidden = true
    }
    // border layer
    _borderLayer.path = borderPath.quartzPath
    // ForeLayers: small highlighting elements
    (_ForeLayers.mask as! CAShapeLayer).path = backgroundPath.quartzPath
    // highlighted preedit layer
    if (hilitedPreeditPath != nil && _theme.hilitedPreeditBackColor != nil) {
      _hilitedPreeditLayer.path = hilitedPreeditPath!.quartzPath
      _hilitedPreeditLayer.isHidden = false
    } else {
      _hilitedPreeditLayer.isHidden = true
    }
    // highlighted candidate layer
    if (!_scrollView.isHidden) {
      if (_candidateRanges.count > _theme.pageSize) {
        let activePageRect: NSRect = _sectionRects[_hilitedCandidate / _theme.pageSize]
        let pageCornerRadius: Double = min(_theme.hilitedCornerRadius, NSHeight(activePageRect) * 0.5)
        let activePagePath: NSBezierPath = squirclePath(rect: activePageRect, cornerRadius: pageCornerRadius)
        let nonActivePagePath: NSBezierPath = documentPath?.copy() as! NSBezierPath
        nonActivePagePath.append(activePagePath)
        _documentLayer.path = nonActivePagePath.quartzPath
        _activePageLayer.path = activePagePath.quartzPath
        _activePageLayer.isHidden = false
      } else {
        _activePageLayer.isHidden = true
        _documentLayer.path = documentPath?.quartzPath
      }
      // grids (in candidate block) layer
      if (gridPath != nil) {
        _gridLayer.path = gridPath!.quartzPath
        _gridLayer.isHidden = false
      } else {
        _gridLayer.isHidden = true
      }
      if (_hilitedCandidate != NSNotFound && _theme.hilitedCandidateBackColor != nil) {
        let cornerRadius: Double = min(_theme.hilitedCornerRadius,
                                       _theme.candidateParagraphStyle.minimumLineHeight * 0.5)
        let hilitedPolygon: SquirrelTextPolygon = _candidatePolygons[_hilitedCandidate]
        let hilitedCandidatePath: NSBezierPath = _theme.linear
        ? squirclePath(polygon: hilitedPolygon, cornerRadius: cornerRadius)
        : squirclePath(rect: hilitedPolygon.body, cornerRadius: cornerRadius)
        _hilitedCandidateLayer.path = hilitedCandidatePath.quartzPath
        _hilitedCandidateLayer.isHidden = false
      } else {
        _hilitedCandidateLayer.isHidden = true
      }
      //    _documentView.layer?.addSublayer(_textView.layer!)
    }
    // function buttons (page up, page down, backspace) layer
    if (_functionButton != .VoidSymbol) {
      updateFunctionButtonLayer()
    } else {
      _functionButtonLayer.isHidden = true
    }
    // logo at the beginning for status message
    if (!_statusView.isHidden) {
      _logoLayer.contentsScale = (_logoLayer.contents as! NSImage).recommendedLayerContentsScale(self.window!.backingScaleFactor)
      _logoLayer.isHidden = false
    } else {
      _logoLayer.isHidden = true
    }
  }

  func getIndexFromMouseSpot(_ spot: NSPoint) -> SquirrelIndex! {
    if (NSMouseInRect(spot, bounds, true)) {
      if (NSMouseInRect(spot, _preeditRect, true)) {
        return NSMouseInRect(spot, _deleteBackRect, true) ? .BackSpaceKey : .CodeInputArea
      }
      if (NSMouseInRect(spot, _expanderRect, true)) {
        return .ExpandButton
      }
      if (NSMouseInRect(spot, _pageUpRect, true)) {
        return .PageUpKey
      }
      if (NSMouseInRect(spot, _pageDownRect, true)) {
        return .PageDownKey
      }
      if (NSMouseInRect(spot, _candidatesRect, true)) {
        let scrollSpot: NSPoint = convert(spot, to: _documentView)
        for i in 0..<_candidateRanges.count {
          if (_candidatePolygons[i].mouseInPolygon(point: scrollSpot, flipped: true)) {
            return SquirrelIndex(rawValue: i)
          }
        }
      }
    }
    return .VoidSymbol
  }
}  // SquirrelView


/* In order to put SquirrelPanel above client app windows,
   SquirrelPanel needs to be assigned a window level higher
   than kCGHelpWindowLevelKey that the system tooltips use.
   This class makes system-alike tooltips above SquirrelPanel */
class SquirrelToolTip: NSPanel {

  private var backView: NSVisualEffectView!
  private var textView: NSTextField!
  var displayTimer: Timer?
  var hideTimer: Timer?

  init() {
    super.init(contentRect: NSZeroRect,
               styleMask: [.nonactivatingPanel],
               backing: .buffered,
               defer: true)
    backgroundColor = NSColor.clear
    isOpaque = true
    hasShadow = true
    let contentView = NSView()
    backView = NSVisualEffectView()
    backView.material = .toolTip
    contentView.addSubview(backView)
    textView = NSTextField()
    textView.isBezeled = true
    textView.bezelStyle = .squareBezel
    textView.isSelectable = false
    contentView.addSubview(textView)
    self.contentView = contentView
  }

  func show(withToolTip toolTip: String!,
            delay: Boolean) {
    if (toolTip.count == 0) {
      hide()
      return
    }
    let Panel: SquirrelPanel! = NSApp.squirrelApp.panel
    level = Panel.level + 1
    appearanceSource = Panel

    textView.stringValue = toolTip
    textView.font = NSFont.toolTipsFont(ofSize: 0)
    textView.textColor = NSColor.windowFrameTextColor
    textView.sizeToFit()
    let contentSize: NSSize = textView.fittingSize

    var spot: NSPoint = NSEvent.mouseLocation
    let cursor: NSCursor! = NSCursor.currentSystem
    spot.x += cursor.image.size.width - cursor.hotSpot.x
    spot.y -= cursor.image.size.height - cursor.hotSpot.y
    var windowRect: NSRect = NSMakeRect(spot.x, spot.y - contentSize.height,
                                        contentSize.width, contentSize.height)

    let screenRect: NSRect = Panel.screen!.visibleFrame
    if (NSMaxX(windowRect) > NSMaxX(screenRect)) {
      windowRect.origin.x = NSMaxX(screenRect) - NSWidth(windowRect)
    }
    if (NSMinY(windowRect) < NSMinY(screenRect)) {
      windowRect.origin.y = NSMinY(screenRect)
    }
    setFrame(Panel.screen!.backingAlignedRect(windowRect, options: .alignAllEdgesNearest),
             display: false)
    textView.frame = self.contentView!.bounds
    backView.frame = self.contentView!.bounds

    displayTimer?.invalidate()
    if (delay) {
      displayTimer = Timer.scheduledTimer(timeInterval: 3.0,
                                          target: self,
                                          selector: #selector(delayedDisplay(_:)),
                                          userInfo: nil,
                                          repeats: false)
    } else {
      display()
      orderFrontRegardless()
    }
  }

  @objc func delayedDisplay(_ timer: Timer!) {
    display()
    orderFrontRegardless()
    hideTimer?.invalidate()
    hideTimer = Timer.scheduledTimer(timeInterval: 5.0,
                                     target: self,
                                     selector: #selector(delayedHide(_:)),
                                     userInfo: nil,
                                     repeats: false)
  }

  @objc func delayedHide(_ timer: Timer!) {
    hide()
  }

  func hide() {
    displayTimer?.invalidate()
    displayTimer = nil
    hideTimer?.invalidate()
    hideTimer = nil
    if (isVisible) {
      orderOut(nil)
    }
  }
}  // SquirrelToolTipView

// MARK: - Panel window, dealing with text content and mouse interactions

func textWidth(_ string: NSAttributedString,
               vertical: Boolean) -> Double {
  if (vertical) {
    let verticalString = string.mutableCopy() as! NSMutableAttributedString
    verticalString.addAttribute(.verticalGlyphForm, value: NSNumber(integerLiteral: 1),
                                range: NSMakeRange(0, verticalString.length))
    return ceil(verticalString.size().width)
  } else {
    return ceil(string.size().width)
  }
}

@objc class SquirrelPanel: NSPanel, NSWindowDelegate {
  // Squirrel panel layouts
  private var _back: NSVisualEffectView?
  private var _toolTip = SquirrelToolTip()
  private var _view = SquirrelView()
  private var _statusTimer: Timer?
  private var _maxSize: NSSize = NSZeroSize
  private var _scrollLocus: NSPoint = NSZeroPoint
  private var _cursorIndex: SquirrelIndex = .VoidSymbol
  private var _textWidthLimit: Double = CGFLOAT_MAX
  private var _anchorOffset: Double = 0
  private var _scrollByLine: Boolean = false
  private var _initPosition: Boolean = true
  private var _needsRedraw: Boolean = false
  // Rime contents and actions
  private var _indexRange: Range<Int> = 0..<0
  private var _highlightedCandidate: Int = NSNotFound
  private var _functionButton: SquirrelIndex = .VoidSymbol
  private var _caretPos: Int = NSNotFound
  private var _pageNum: Int = 0
  private var _sectionNum: Int = 0
  private var _finalPage: Boolean = false
  // Show preedit text inline.
  var inlinePreedit: Boolean {
    get { return _view.theme.inlinePreedit }
  }
  // Show primary candidate inline
  var inlineCandidate: Boolean {
    get { return _view.theme.inlineCandidate }
  }
  // Vertical text orientation, as opposed to horizontal text orientation.
  var vertical: Boolean {
    get { return _view.theme.vertical }
  }
  // Linear candidate list layout, as opposed to stacked candidate list layout.
  var linear: Boolean {
    get { return _view.theme.linear }
  }
  /* Tabular candidate list layout, initializes as tab-aligned linear layout,
     expandable to stack 5 (3 for vertical) pages/sections of candidates */
  var tabular: Boolean {
    get { return _view.theme.tabular }
  }
  private var _locked: Boolean = false
  var locked: Boolean {
    get { return _locked }
    set(newValue) {
      if (_view.theme.tabular && _locked != newValue) {
        _locked = locked
        let userConfig = SquirrelConfig()
        if (userConfig.open(userConfig: "user")) {
          _ = userConfig.setOption("var/option/_lock_tabular", withBool: newValue)
          if (newValue) {
            _ = userConfig.setOption("var/option/_expand_tabular", withBool: _view.expanded)
          }
        }
        userConfig.close()
      }
    }
  }
  private func getLocked() {
    if (_view.theme.tabular) {
      let userConfig: SquirrelConfig! = SquirrelConfig()
      if (userConfig.open(userConfig: "user")) {
        _locked = userConfig.getBoolForOption("var/option/_lock_tabular")
        if (_locked) {
          _view.expanded = userConfig.getBoolForOption("var/option/_expand_tabular")
        }
      }
      userConfig.close()
      _sectionNum = 0
    }
  }
  var firstLine: Boolean {
    get { return _view.tabularIndices.isEmpty ? true : _view.tabularIndices[_highlightedCandidate].lineNum == 0 }
  }
  var expanded: Boolean {
    get { return _view.expanded }
    set(newValue) {
      if (_view.theme.tabular && !_locked && _view.expanded != newValue) {
        _view.expanded = newValue
        _sectionNum = 0
        _needsRedraw = true
      }
    }
  }
  var sectionNum: Int {
    get { return _sectionNum }
    set (newValue) {
      if (_view.theme.tabular && _view.expanded && _sectionNum != newValue) {
        _sectionNum = clamp(newValue, 0, _view.theme.vertical ? 2 : 4)
      }
    }
  }
  // position of the text input I-beam cursor on screen.
  private var _IbeamRect: NSRect = NSZeroRect
  var IbeamRect: NSRect {
    get { return _IbeamRect }
    set(newValue) {
      if (!NSEqualRects(_IbeamRect, newValue)) {
        _IbeamRect = newValue
        if (!NSIntersectsRect(newValue, _screen.frame)) {
          willChangeValue(forKey: "screen")
          updateScreen()
          didChangeValue(forKey: "screen")
          updateDisplayParameters()
        }
      }
    }
  }
  private var _screen: NSScreen! = .main
  override var screen: NSScreen? {
    get { return _screen }
  }
  @objc private var _inputController: SquirrelInputController?
  // Status message before pop-up is displayed; nil before normal panel is displayed
  private var _statusMessage: String?
  var statusMessage: String? { get { return _statusMessage } }
  // Store switch options that change style (color theme) settings
  var optionSwitcher: SquirrelOptionSwitcher = SquirrelOptionSwitcher()

  init() {
    super.init(contentRect: NSZeroRect,
               styleMask: [.borderless, .nonactivatingPanel],
               backing: .buffered,
               defer: true)
    level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow) - 100))
    hasShadow = false
    isOpaque = false
    backgroundColor = NSColor.clear
    delegate = self
    acceptsMouseMovedEvents = true

    let contentView = NSFlippedView()
    if #available(macOS 10.14, *) {
      _back = NSVisualEffectView()
      _back!.blendingMode = .behindWindow
      _back!.material = .hudWindow
      _back!.state = .active
      _back!.wantsLayer = true
      _back!.layer!.mask = _view.shape
      contentView.addSubview(_back!)
    }
    contentView.addSubview(_view)
    contentView.addSubview(_view.preeditView)
    contentView.addSubview(_view.scrollView)
    contentView.addSubview(_view.pagingView)
    contentView.addSubview(_view.statusView)
    self.contentView = contentView

    appearance = NSAppearance(named: .aqua)
    updateDisplayParameters()
  }

  @objc func windowDidChangeBackingProperties(_ notification: Notification) {
    if let panel = notification.object as? SquirrelPanel {
      panel.updateDisplayParameters()
    }
  }

  @objc override func observeValue(forKeyPath keyPath: String?,
                                   of object: Any?,
                                   change: [NSKeyValueChangeKey : Any]?,
                                   context: UnsafeMutableRawPointer?) {
    if let inputController = object as? SquirrelInputController {
      if (keyPath == "viewEffectiveAppearance") {
        _inputController = inputController
        if #available(macOS 10.14, *) {
          let clientAppearance: NSAppearance = change![.newKey] as! NSAppearance
          let appearName: NSAppearance.Name = clientAppearance.bestMatch(from: [.aqua, .darkAqua])!
          let appear: SquirrelAppearance = appearName == .darkAqua ? .dark : .light
          if (appear != _view.appear) {
            _view.appear = appear
            self.appearance = NSAppearance(named: appearName)
          }
        }
      }
    } else {
      super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
  }

  func candidateIndexOnDirection(arrowKey: SquirrelIndex) -> Int {
    if (!tabular || _indexRange.count == 0 || _highlightedCandidate == NSNotFound) {
      return NSNotFound
    }
    let currentTab: Int = _view.tabularIndices[_highlightedCandidate].tabNum
    let currentLine: Int = _view.tabularIndices[_highlightedCandidate].lineNum
    let finalLine: Int = _view.tabularIndices[_indexRange.count - 1].lineNum
    if (arrowKey == (self.vertical ? .LeftKey : .DownKey)) {
      if (_highlightedCandidate == _indexRange.count - 1 && _finalPage) {
        return NSNotFound
      }
      if (currentLine == finalLine && !_finalPage) {
        return _indexRange.upperBound
      }
      var newIndex: Int = _highlightedCandidate + 1
      while  newIndex < _indexRange.count &&
              (_view.tabularIndices[newIndex].lineNum == currentLine ||
               (_view.tabularIndices[newIndex].lineNum == currentLine + 1 &&
                _view.tabularIndices[newIndex].tabNum <= currentTab)) {
        newIndex += 1
      }
      if (newIndex != _indexRange.count || _finalPage) {
        newIndex -= 1
      }
      return newIndex + _indexRange.lowerBound
    } else if (arrowKey == (self.vertical ? .RightKey : .UpKey)) {
      if (currentLine == 0) {
        return _pageNum == 0 ? NSNotFound : _indexRange.lowerBound - 1
      }
      var newIndex: Int = _highlightedCandidate - 1
      while newIndex > 0 &&
              (_view.tabularIndices[newIndex].lineNum == currentLine ||
               (_view.tabularIndices[newIndex].lineNum == currentLine - 1 &&
                _view.tabularIndices[newIndex].tabNum > currentTab)) {
        newIndex -= 1
      }
      return newIndex + _indexRange.lowerBound
    }
    return NSNotFound
  }

  // handle mouse interaction events
  override func sendEvent(_ event: NSEvent) {
    let theme: SquirrelTheme! = _view.theme
    switch (event.type) {
    case .leftMouseDown:
      if (event.clickCount == 1 && _cursorIndex == .CodeInputArea && _caretPos != NSNotFound) {
        let spot: NSPoint = _view.preeditView.convert(mouseLocationOutsideOfEventStream, from: nil)
        let inputIndex: Int = _view.preeditView.characterIndexForInsertion(at: spot)
        if (inputIndex == 0) {
          _inputController?.perform(action: .PROCESS, onIndex: .HomeKey)
        } else if (inputIndex < _caretPos) {
          _inputController?.moveCursor(_caretPos, to: inputIndex,
                                       inlinePreedit: false, inlineCandidate: false)
        } else if (inputIndex >= _view.preeditContents.length - 2) {
          _inputController?.perform(action: .PROCESS, onIndex: .EndKey)
        } else if (inputIndex > _caretPos + 1) {
          _inputController?.moveCursor(_caretPos, to: inputIndex - 1,
                                       inlinePreedit: false, inlineCandidate: false)
        }
      }
      break
    case .leftMouseUp:
      if (event.clickCount == 1 && _cursorIndex != .VoidSymbol) {
        if (_cursorIndex.rawValue == _highlightedCandidate) {
          _inputController?.perform(action: .SELECT, onIndex: SquirrelIndex(
            rawValue: _cursorIndex.rawValue + _indexRange.lowerBound)!)
        } else if (_cursorIndex == _functionButton) {
          if (_cursorIndex == .ExpandButton) {
            if (_locked) {
              locked = false
              _view.pagingContents.replaceCharacters(in: NSMakeRange(_view.pagingContents.length / 2, 1),
                                                     with: (_view.expanded ? theme.symbolCompress : theme.symbolExpand)!)
              _view.pagingView.setNeedsDisplay(_view.convert(_view.expanderRect,
                                                             to: _view.pagingView))
            } else {
              expanded = !_view.expanded
              sectionNum = 0
            }
          }
          _inputController?.perform(action: .PROCESS, onIndex: _cursorIndex)
        }
      }
      break
    case .rightMouseUp:
      if (event.clickCount == 1 && _cursorIndex != .VoidSymbol) {
        if (_cursorIndex.rawValue == _highlightedCandidate) {
          _inputController?.perform(action: .DELETE, onIndex: SquirrelIndex(
            rawValue: _cursorIndex.rawValue + _indexRange.lowerBound)!)
        } else if (_cursorIndex == _functionButton) {
          switch (_functionButton) {
          case .PageUpKey:
            _inputController?.perform(action: .PROCESS, onIndex: .HomeKey)
            break
          case .PageDownKey:
            _inputController?.perform(action: .PROCESS, onIndex: .EndKey)
            break
          case .ExpandButton:
            locked = !_locked
            _view.pagingContents.replaceCharacters(in: NSMakeRange(_view.pagingContents.length / 2, 1),
                                                   with: (_locked ? theme.symbolLock : _view.expanded ? theme.symbolCompress : theme.symbolExpand)!)
            _view.pagingContents.addAttribute(.foregroundColor,
                                              value: theme.hilitedPreeditForeColor,
                                              range: NSMakeRange(_view.pagingContents.length / 2, 1))
            _view.pagingView.setNeedsDisplay(_view.convert(_view.expanderRect, to: _view.pagingView),
                                             avoidAdditionalLayout: true)
            _inputController?.perform(action: .PROCESS, onIndex: .LockButton)
            break
          case .BackSpaceKey:
            _inputController?.perform(action: .PROCESS, onIndex: .EscapeKey)
            break
          default:
            break
          }
        }
      }
      break
    case .mouseMoved:
      if (event.modifierFlags.contains(.control)) {
        return
      }
      let noDelay: Boolean = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.option]
      _cursorIndex = _view.getIndexFromMouseSpot(_view.convert(mouseLocationOutsideOfEventStream, from: nil))
      if (_cursorIndex.rawValue != _highlightedCandidate && _cursorIndex != _functionButton) {
        _toolTip.hide()
      } else if (noDelay) {
        _toolTip.displayTimer?.fire()
      }
      if (_cursorIndex.rawValue >= 0 && _cursorIndex.rawValue < _indexRange.count &&
          _highlightedCandidate != _cursorIndex.rawValue) {
        highlightFunctionButton(.VoidSymbol, delayToolTip: !noDelay)
        if (theme.linear && _view.truncated[_cursorIndex.rawValue]) {
          _toolTip.show(withToolTip: _view.contents.mutableString.substring(
            with: _view.candidateRanges[_cursorIndex.rawValue].candidateRange()), delay: false)
        } else if (noDelay) {
          _toolTip.show(withToolTip: NSLocalizedString("candidate", comment: ""), delay: !noDelay)
        }
        sectionNum = _cursorIndex.rawValue / theme.pageSize
        _inputController?.perform(action: .HIGHLIGHT, onIndex: SquirrelIndex(
          rawValue: _cursorIndex.rawValue + _indexRange.lowerBound)!)
      } else if (_cursorIndex == .PageUpKey || _cursorIndex == .PageDownKey ||
                 _cursorIndex == .ExpandButton || _cursorIndex == .BackSpaceKey) &&
                  _functionButton != _cursorIndex {
        highlightFunctionButton(_cursorIndex, delayToolTip: !noDelay)
      }
      break
    case .mouseExited:
      _toolTip.displayTimer?.invalidate()
      break
    case .leftMouseDragged:
      // reset the `remember_size` references after moving the panel
      _maxSize = NSZeroSize
      performDrag(with: event)
      break
    case .scrollWheel:
      let scrollThreshold: Double = _view.scrollView.lineScroll
      if (event.phase == .began) {
        _scrollLocus = NSZeroPoint
        _scrollByLine = false
      } else if (event.phase == .changed && !_scrollLocus.x.isNaN && !_scrollLocus.y.isNaN) {
        var scrollDistance: Double = 0.0
        // determine scrolling direction by confining to sectors within ±30º of any axis
        if (abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * sqrt(3.0)) {
          scrollDistance = event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : scrollThreshold)
          _scrollLocus.x += scrollDistance
        } else if (abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) * sqrt(3.0)) {
          scrollDistance = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : scrollThreshold)
          _scrollLocus.y += scrollDistance
        }
        // compare accumulated locus length against threshold and limit paging to max once
        if (_scrollLocus.x > scrollThreshold) {
          if (theme.vertical && NSMaxY(_view.scrollView.documentVisibleRect) < NSMaxY(_view.documentRect) - 0.1) {
            _scrollByLine = true
            var origin: NSPoint = _view.scrollView.contentView.bounds.origin
            origin.y += min(scrollDistance, NSMaxY(_view.documentRect) - NSMaxY(_view.scrollView.documentVisibleRect))
            _view.scrollView.contentView.scroll(to: origin)
            _view.scrollView.verticalScroller?.doubleValue =
              NSMinY(_view.scrollView.documentVisibleRect) / _view.clippedHeight
          } else if (!_scrollByLine) {
            _inputController?.perform(action: .PROCESS, onIndex: theme.vertical ? .PageDownKey : .PageUpKey)
            _scrollLocus = NSMakePoint(.nan, .nan)
          }
        } else if (_scrollLocus.y > scrollThreshold) {
          if (NSMinY(_view.scrollView.documentVisibleRect) > NSMinY(_view.documentRect) + 0.1) {
            _scrollByLine = true
            var origin: NSPoint = _view.scrollView.contentView.bounds.origin
            origin.y -= min(scrollDistance, NSMinY(_view.scrollView.documentVisibleRect) - NSMinY(_view.documentRect))
            _view.scrollView.contentView.scroll(to: origin)
            _view.scrollView.verticalScroller?.doubleValue =
              NSMinY(_view.scrollView.documentVisibleRect) / _view.clippedHeight
          } else if (!_scrollByLine) {
            _inputController?.perform(action: .PROCESS, onIndex: .PageUpKey)
            _scrollLocus = NSMakePoint(.nan, .nan)
          }
        } else if (_scrollLocus.x < -scrollThreshold) {
          if (theme.vertical && NSMinY(_view.scrollView.documentVisibleRect) > NSMinY(_view.documentRect) + 0.1) {
            _scrollByLine = true
            var origin: NSPoint = _view.scrollView.contentView.bounds.origin;
            origin.y += max(scrollDistance, NSMinY(_view.documentRect) - NSMinY(_view.scrollView.documentVisibleRect))
            _view.scrollView.contentView.scroll(to: origin)
            _view.scrollView.verticalScroller?.doubleValue =
              NSMinY(_view.scrollView.documentVisibleRect) / _view.clippedHeight
          } else if (!_scrollByLine) {
            _inputController?.perform(action: .PROCESS, onIndex: theme.vertical ? .PageUpKey : .PageDownKey)
            _scrollLocus = NSMakePoint(.nan, .nan)
          }
        } else if (_scrollLocus.y < -scrollThreshold) {
          if (NSMaxY(_view.scrollView.documentVisibleRect) < NSMaxY(_view.documentRect) - 0.1) {
            _scrollByLine = true
            var origin: NSPoint = _view.scrollView.contentView.bounds.origin;
            origin.y -= max(scrollDistance, NSMaxY(_view.scrollView.documentVisibleRect) - NSMaxY(_view.documentRect))
            _view.scrollView.contentView.scroll(to: origin)
            _view.scrollView.verticalScroller?.doubleValue =
              NSMinY(_view.scrollView.documentVisibleRect) / _view.clippedHeight
          } else if (!_scrollByLine) {
            _inputController?.perform(action: .PROCESS, onIndex: .PageDownKey)
            _scrollLocus = NSMakePoint(.nan, .nan)
          }
        }
      }
      break
    default:
      super.sendEvent(event)
      break
    }
  }

  private func highlightCandidate(_ highlightedCandidate: Int) {
    let theme: SquirrelTheme! = _view.theme
    let priorHilitedCandidate: Int = _highlightedCandidate
    let priorSectionNum: Int = priorHilitedCandidate / theme.pageSize
    _highlightedCandidate = highlightedCandidate
    sectionNum = highlightedCandidate / theme.pageSize
    // apply new foreground colors
    for i in 0..<theme.pageSize {
      let priorCandidate: Int = i + priorSectionNum * theme.pageSize
      if ((_sectionNum != priorSectionNum || priorCandidate == priorHilitedCandidate) && priorCandidate < _indexRange.count) {
        let labelColor = priorCandidate == priorHilitedCandidate && _sectionNum == priorSectionNum ? theme.labelForeColor : theme.dimmedLabelForeColor!
        _view.contents.addAttribute(.foregroundColor, value: labelColor,
                                    range: _view.candidateRanges[priorCandidate].labelRange())
        if (priorCandidate == priorHilitedCandidate) {
          _view.contents.addAttribute(.foregroundColor, value: theme.textForeColor,
                                      range: _view.candidateRanges[priorCandidate].textRange())
          _view.contents.addAttribute(.foregroundColor, value: theme.commentForeColor,
                                      range: _view.candidateRanges[priorCandidate].commentRange())
        }
      }
      let newCandidate: Int = i + _sectionNum * theme.pageSize
      if ((_sectionNum != priorSectionNum || newCandidate == _highlightedCandidate) && newCandidate < _indexRange.count ){
        _view.contents.addAttribute(.foregroundColor,
                                    value: newCandidate == _highlightedCandidate ? theme.hilitedLabelForeColor : theme.labelForeColor,
                                    range: _view.candidateRanges[newCandidate].labelRange())
        if (newCandidate == highlightedCandidate) {
          _view.contents.addAttribute(.foregroundColor,
                                      value: newCandidate == _highlightedCandidate ? theme.hilitedTextForeColor : theme.textForeColor,
                                      range: _view.candidateRanges[newCandidate].textRange())
          _view.contents.addAttribute(.foregroundColor,
                                      value: newCandidate == _highlightedCandidate ? theme.hilitedCommentForeColor : theme.commentForeColor,
                                      range: _view.candidateRanges[newCandidate].commentRange())
        }
      }
    }
    _view.highlightCandidate(highlightedCandidate)
  }

  private func highlightFunctionButton(_ functionButton: SquirrelIndex,
                                       delayToolTip delay: Boolean) {
    if (_functionButton == functionButton) {
      return
    }
    let theme: SquirrelTheme! = _view.theme
    switch (_functionButton) {
    case .PageUpKey:
      _view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor,
                                        range: NSMakeRange(0, 1))
      break
    case .PageDownKey:
      _view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor,
                                        range: NSMakeRange(_view.pagingContents.length - 1, 1))
      break
    case .ExpandButton:
      _view.pagingContents.addAttribute(.foregroundColor, value: theme.preeditForeColor,
                                        range: NSMakeRange(_view.pagingContents.length / 2, 1))
      break
    case .BackSpaceKey:
      _view.preeditContents.addAttribute(.foregroundColor, value: theme.preeditForeColor,
                                         range: NSMakeRange(_view.preeditContents.length - 1, 1))
      break
    default:
      break
    }
    _functionButton = functionButton
    var newFunctionButton: SquirrelIndex = .VoidSymbol
    switch (functionButton) {
    case .PageUpKey:
      _view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor,
                                        range: NSMakeRange(0, 1))
      newFunctionButton = _pageNum == 0 ? .HomeKey : .PageUpKey
      _toolTip.show(withToolTip: NSLocalizedString(_pageNum == 0 ? "home" : "page_up", comment: ""), delay: delay)
      break
    case .PageDownKey:
      _view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor,
                                        range: NSMakeRange(_view.pagingContents.length - 1, 1))
      newFunctionButton = _finalPage ? .EndKey : .PageDownKey
      _toolTip.show(withToolTip: NSLocalizedString(_finalPage ? "end" : "page_down", comment: ""), delay: delay)
      break
    case .ExpandButton:
      _view.pagingContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor,
                                        range: NSMakeRange(_view.pagingContents.length / 2, 1))
      newFunctionButton = _locked ? .LockButton : _view.expanded ? .CompressButton : .ExpandButton
      _toolTip.show(withToolTip: NSLocalizedString(_locked ? "unlock" : _view.expanded ? "compress" : "expand",
                                                   comment:""), delay: delay)
      break
    case .BackSpaceKey:
      _view.preeditContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor,
                                         range: NSMakeRange(_view.preeditContents.length - 1, 1))
      newFunctionButton = _caretPos == NSNotFound || _caretPos == 0 ? .EscapeKey : .BackSpaceKey
      _toolTip.show(withToolTip: NSLocalizedString(_caretPos == NSNotFound || _caretPos == 0 ? "escape" : "delete",
                                                   comment: ""), delay: delay)
      break
    default:
      break
    }
    _view.highlightFunctionButton(newFunctionButton)
    displayIfNeeded()
  }

  private func updateScreen() {
    for scrn in NSScreen.screens {
      if (NSPointInRect(IbeamRect.origin, scrn.frame)) {
        _screen = scrn
        return
      }
    }
    _screen = NSScreen.main
  }

  private func updateDisplayParameters() {
    // repositioning the panel window
    _initPosition = true
    _maxSize = NSZeroSize

    _view.textView.setLayoutOrientation(_view.theme.vertical ? .vertical : .horizontal)
    _view.preeditView.setLayoutOrientation(_view.theme.vertical ? .vertical : .horizontal)
    _view.pagingView.setLayoutOrientation(_view.theme.vertical ? .vertical : .horizontal)
    _view.statusView.setLayoutOrientation(_view.theme.vertical ? .vertical : .horizontal)
    // rotate the view, the core in vertical mode!
    contentView!.boundsRotation = _view.theme.vertical ? -90.0 : 0.0
    _view.textView.boundsRotation = 0.0
    _view.preeditView.boundsRotation = 0.0
    _view.pagingView.boundsRotation = 0.0
    _view.statusView.boundsRotation = 0.0
    _view.textView.setBoundsOrigin(NSZeroPoint)
    _view.preeditView.setBoundsOrigin(NSZeroPoint)
    _view.pagingView.setBoundsOrigin(NSZeroPoint)
    _view.statusView.setBoundsOrigin(NSZeroPoint)

    _view.scrollView.lineScroll = _view.theme.candidateParagraphStyle.minimumLineHeight
    _view.scrollView.hasVerticalScroller = !_view.theme.vertical
    _view.scrollView.hasHorizontalScroller = _view.theme.vertical
    if #available(macOS 12.0, *) {
      let textLayoutManager = _view.textView.textLayoutManager as! SquirrelTextLayoutManager
      textLayoutManager.contentBlock = _view.theme.linear ? .linearCandidates : .stackedCandidates
    } else {
      let layoutManager = _view.textView.layoutManager as! SquirrelLayoutManager
      layoutManager.contentBlock = _view.theme.linear ? .linearCandidates : .stackedCandidates
    }

    // size limits on textContainer
    let screenRect: NSRect = _screen.visibleFrame
    let textWidthRatio: Double = min(0.8, 1.0 / (_view.theme.vertical ? 4 : 3) +
                                     (_view.theme.textAttrs[.font] as! NSFont).pointSize / 144.0)
    _textWidthLimit = floor((_view.theme.vertical ? NSHeight(screenRect) : NSWidth(screenRect)) * textWidthRatio -
                            _view.theme.fullWidth - _view.theme.borderInsets.width * 2)
    if (_view.theme.lineLength > 0.1) {
      _textWidthLimit = min(_view.theme.lineLength, _textWidthLimit)
    }
    if (_view.theme.tabular) {
      _textWidthLimit = floor((_textWidthLimit + _view.theme.fullWidth) / (_view.theme.fullWidth * 2)) *
      (_view.theme.fullWidth * 2) - _view.theme.fullWidth
    }
    _view.textView.textContainer!.size = NSMakeSize(_textWidthLimit, CGFLOAT_MAX)
    _view.preeditView.textContainer!.size = NSMakeSize(_textWidthLimit, CGFLOAT_MAX)
    _view.pagingView.textContainer!.size = NSMakeSize(_textWidthLimit, CGFLOAT_MAX)
    _view.statusView.textContainer!.size = NSMakeSize(_textWidthLimit, CGFLOAT_MAX)

    // color, opacity and transluecency
    _view.updateColors()
    alphaValue = _view.theme.opacity
    if #available(macOS 10.14, *) {
      _back?.isHidden = _view.theme.translucency < 0.001
      _view.BackLayers.opacity = 1.0 - _view.theme.translucency
      _view.BackLayers.allowsGroupOpacity = true
      _view.documentLayer.opacity = 1.0 - _view.theme.translucency
      _view.documentLayer.allowsGroupOpacity = true
    }
    // resize logo and background image, if any
    let statusHeight: Double = _view.theme.statusParagraphStyle.minimumLineHeight
    let logoRect: NSRect = NSMakeRect(_view.theme.borderInsets.width - 0.1 * statusHeight,
                                      _view.theme.borderInsets.height - 0.1 * statusHeight,
                                      statusHeight * 1.2, statusHeight * 1.2)
    _view.logoLayer.frame = logoRect
    let logoImage = NSImage.init(named: NSImage.applicationIconName)!
    logoImage.size = logoRect.size
    _view.logoLayer.contents = logoImage
    _view.logoLayer.setAffineTransform(_view.theme.vertical ?
      CGAffineTransform(rotationAngle: -.pi/2) : CGAffineTransformIdentity)
    if let defaultBackImage = SquirrelView.defaultTheme.backImage, defaultBackImage.isValid {
      let widthLimit: Double = _textWidthLimit + SquirrelView.defaultTheme.fullWidth
      defaultBackImage.resizingMode = .stretch
      defaultBackImage.size = SquirrelView.defaultTheme.vertical
      ? NSMakeSize(defaultBackImage.size.width / defaultBackImage.size.height * widthLimit, widthLimit)
      : NSMakeSize(widthLimit, defaultBackImage.size.height / defaultBackImage.size.width * widthLimit)
    }
    if let darkBackImage = SquirrelView.darkTheme.backImage, darkBackImage.isValid {
      let widthLimit: Double = _textWidthLimit + SquirrelView.defaultTheme.fullWidth
      darkBackImage.resizingMode = .stretch
      darkBackImage.size = SquirrelView.darkTheme.vertical
      ? NSMakeSize(darkBackImage.size.width / darkBackImage.size.height * widthLimit, widthLimit)
      : NSMakeSize(widthLimit, darkBackImage.size.height / darkBackImage.size.width * widthLimit);
    }
  }

  // Get the window size, it will be the dirtyRect in SquirrelView.drawRect
  private func show() {
    if (!_needsRedraw && !_initPosition) {
      isVisible ? update() : orderFront(nil)
      return
    }
    //Break line if the text is too long, based on screen size.
    let theme: SquirrelTheme = _view.theme
    let border: NSSize = theme.borderInsets
    let textWidthRatio: Double = min(0.8, 1.0 / (theme.vertical ? 4 : 3) + (theme.textAttrs[.font] as! NSFont).pointSize / 144.0)
    let screenRect: NSRect = _screen.visibleFrame

    // the sweep direction of the client app changes the behavior of adjusting Squirrel panel position
    let sweepVertical: Boolean = NSWidth(IbeamRect) > NSHeight(IbeamRect)
    var contentRect: NSRect = _view.contentRect
    // fixed line length (text width), but not applicable to status message
    if (theme.lineLength > 0.1 && statusMessage == nil) {
      contentRect.size.width = _textWidthLimit
    }
    /* remember panel size (fix the top leading anchor of the panel in screen coordiantes)
       but only when the text would expand on the side of upstream (i.e. towards the beginning of text) */
    if (theme.rememberSize && _view.statusView.isHidden) {
      if (theme.lineLength < 0.1 && theme.vertical
        ? sweepVertical ? (NSMinY(_IbeamRect) - max(NSWidth(contentRect), _maxSize.width) - border.width - floor(theme.fullWidth * 0.5) < NSMinY(screenRect))
                        : (NSMinY(_IbeamRect) - kOffsetGap - NSHeight(screenRect) * textWidthRatio - border.width * 2 - theme.fullWidth < NSMinY(screenRect))
        : sweepVertical ? (NSMinX(_IbeamRect) - kOffsetGap - NSWidth(screenRect) * textWidthRatio - border.width * 2 - theme.fullWidth >= NSMinX(screenRect))
                        : (NSMaxX(_IbeamRect) + max(NSWidth(contentRect), _maxSize.width) + border.width + floor(theme.fullWidth * 0.5) > NSMaxX(screenRect))) {
        if (NSWidth(contentRect) >= _maxSize.width) {
          _maxSize.width = NSWidth(contentRect)
        } else {
          contentRect.size.width = _maxSize.width
        }
      }
      let textHeight: Double = max(NSHeight(contentRect), _maxSize.height) + border.height * 2
      if (theme.vertical ? (NSMinX(_IbeamRect) - textHeight - (sweepVertical ? kOffsetGap : 0) < NSMinX(screenRect))
          : (NSMinY(_IbeamRect) - textHeight - (sweepVertical ? 0 : kOffsetGap) < NSMinY(screenRect))) {
        if (NSHeight(contentRect) >= _maxSize.height) {
          _maxSize.height = NSHeight(contentRect)
        } else {
          contentRect.size.height = _maxSize.height
        }
      }
    }

    var windowRect: NSRect = NSZeroRect
    if (_statusMessage != nil) {
      // following system UI, middle-align status message with cursor
      _initPosition = true
      if (theme.vertical) {
        windowRect.size.width = NSHeight(contentRect) + border.height * 2
        windowRect.size.height = NSWidth(contentRect) + border.width * 2 + theme.fullWidth
      } else {
        windowRect.size.width = NSWidth(contentRect) + border.width * 2 + theme.fullWidth
        windowRect.size.height = NSHeight(contentRect) + border.height * 2
      }
      if (sweepVertical) { 
        // vertically centre-align (MidY) in screen coordinates
        windowRect.origin.x = NSMinX(_IbeamRect) - kOffsetGap - NSWidth(windowRect)
        windowRect.origin.y = NSMidY(_IbeamRect) - NSHeight(windowRect) * 0.5
      } else {
        // horizontally centre-align (MidX) in screen coordinates
        windowRect.origin.x = NSMidX(_IbeamRect) - NSWidth(windowRect) * 0.5
        windowRect.origin.y = NSMinY(_IbeamRect) - kOffsetGap - NSHeight(windowRect)
      }
    } else {
      if (theme.vertical) { 
        // anchor is the top right corner in screen coordinates (MaxX, MaxY)
        windowRect = NSMakeRect(NSMaxX(frame) - NSHeight(contentRect) - border.height * 2,
                                NSMaxY(frame) - NSWidth(contentRect) - border.width * 2 - theme.fullWidth,
                                NSHeight(contentRect) + border.height * 2,
                                NSWidth(contentRect) +  border.width * 2 + theme.fullWidth)
        _initPosition = _initPosition || NSIntersectsRect(windowRect, _IbeamRect) ||
                        !NSContainsRect(screenRect, windowRect)
        if (_initPosition) {
          if (!sweepVertical) {
            // To avoid jumping up and down while typing, use the lower screen when typing on upper, and vice versa
            if (NSMinY(_IbeamRect) - kOffsetGap - NSHeight(screenRect) * textWidthRatio -
                border.width * 2 - theme.fullWidth < NSMinY(screenRect)) {
              windowRect.origin.y = NSMaxY(_IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.y = NSMinY(_IbeamRect) - kOffsetGap - NSHeight(windowRect)
            }
            // Make the right edge of candidate block fixed at the left of cursor
            windowRect.origin.x = NSMinX(_IbeamRect) + border.height - NSWidth(windowRect)
          } else {
            if (NSMinX(_IbeamRect) - kOffsetGap - NSWidth(windowRect) < NSMinX(screenRect)) {
              windowRect.origin.x = NSMaxX(_IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.x = NSMinX(_IbeamRect) - kOffsetGap - NSWidth(windowRect)
            }
            windowRect.origin.y = NSMinY(_IbeamRect) + border.width + ceil(theme.fullWidth * 0.5) - NSHeight(windowRect)
          }
        }
      } else {
        // anchor is the top left corner in screen coordinates (MinX, MaxY)
        windowRect = NSMakeRect(NSMinX(frame),
                                NSMaxY(frame) - NSHeight(contentRect) - border.height * 2,
                                NSWidth(contentRect) + border.width * 2 + theme.fullWidth,
                                NSHeight(contentRect) + border.height * 2)
        _initPosition = _initPosition || NSIntersectsRect(windowRect, _IbeamRect) ||
                        !NSContainsRect(screenRect, windowRect)
        if (_initPosition) {
          if (sweepVertical) {
            // To avoid jumping left and right while typing, use the lefter screen when typing on righter, and vice versa
            if (NSMinX(_IbeamRect) - kOffsetGap - NSWidth(screenRect) * textWidthRatio -
                border.width * 2 - theme.fullWidth >= NSMinX(screenRect)) {
              windowRect.origin.x = NSMinX(_IbeamRect) - kOffsetGap - NSWidth(windowRect)
            } else {
              windowRect.origin.x = NSMaxX(_IbeamRect) + kOffsetGap
            }
            windowRect.origin.y = NSMinY(_IbeamRect) + border.height - NSHeight(windowRect)
          } else {
            if (NSMinY(_IbeamRect) - kOffsetGap - NSHeight(windowRect) < NSMinY(screenRect)) {
              windowRect.origin.y = NSMaxY(_IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.y = NSMinY(_IbeamRect) - kOffsetGap - NSHeight(windowRect)
            }
            windowRect.origin.x = NSMaxX(_IbeamRect) - border.width - ceil(theme.fullWidth * 0.5)
          }
        }
      }
    }

    if (!_view.preeditView.isHidden) {
      if (_initPosition) {
        _anchorOffset = 0
      }
      if (theme.vertical != sweepVertical) {
        let anchorOffset: Double = NSHeight(_view.preeditRect)
        if (theme.vertical) {
          windowRect.origin.x += anchorOffset - _anchorOffset
        } else {
          windowRect.origin.y += anchorOffset - _anchorOffset
        }
        _anchorOffset = anchorOffset
      }
    }
    if (NSMaxX(windowRect) > NSMaxX(screenRect)) {
      windowRect.origin.x = (_initPosition && sweepVertical ? fmin(NSMinX(IbeamRect) - kOffsetGap, NSMaxX(screenRect))
                                                            : NSMaxX(screenRect)) - NSWidth(windowRect)
    }
    if (NSMinX(windowRect) < NSMinX(screenRect)) {
      windowRect.origin.x = _initPosition && sweepVertical ? fmax(NSMaxX(IbeamRect) + kOffsetGap,
                                                                  NSMinX(screenRect)) : NSMinX(screenRect)
    }
    if (NSMinY(windowRect) < NSMinY(screenRect)) {
      windowRect.origin.y = _initPosition && !sweepVertical ? fmax(NSMaxY(IbeamRect) + kOffsetGap,
                                                                   NSMinY(screenRect)) : NSMinY(screenRect)
    }
    if (NSMaxY(windowRect) > NSMaxY(screenRect)) {
      windowRect.origin.y = (_initPosition && !sweepVertical ? fmin(NSMinY(IbeamRect) - kOffsetGap, NSMaxY(screenRect)) 
                                                             : NSMaxY(screenRect)) - NSHeight(windowRect)
    }

    if (theme.vertical) {
      windowRect.origin.x += NSHeight(contentRect) - NSHeight(_view.contentRect)
      windowRect.size.width -= NSHeight(contentRect) - NSHeight(_view.contentRect)
    } else {
      windowRect.origin.y += NSHeight(contentRect) - NSHeight(_view.contentRect)
      windowRect.size.height -= NSHeight(contentRect) - NSHeight(_view.contentRect)
    }
    windowRect = _screen.backingAlignedRect(NSIntersectionRect(windowRect, screenRect),
                                            options: .alignAllEdgesNearest)
    setFrame(windowRect, display: true)

    contentView!.setBoundsOrigin(theme.vertical ? NSMakePoint(0.0, NSWidth(windowRect)) : NSZeroPoint)
    let viewRect: NSRect = contentView!.bounds
    _view.frame = viewRect
    if (!_view.statusView.isHidden) {
      _view.statusView.frame = NSMakeRect(NSMinX(viewRect) + border.width + ceil(theme.fullWidth * 0.5) - _view.statusView.textContainerOrigin.x,
                                          NSMinY(viewRect) + border.height - _view.statusView.textContainerOrigin.y,
                                          NSWidth(viewRect) - border.width * 2 - theme.fullWidth,
                                          NSHeight(viewRect) - border.height * 2);
    }
    if (!_view.preeditView.isHidden) {
      _view.preeditView.frame = NSMakeRect(NSMinX(viewRect) + border.width + ceil(theme.fullWidth * 0.5) - _view.preeditView.textContainerOrigin.x,
                                           NSMinY(viewRect) + border.height - _view.preeditView.textContainerOrigin.y,
                                           NSWidth(viewRect) - border.width * 2 - theme.fullWidth,
                                           NSHeight(_view.preeditRect));
    }
    if (!_view.pagingView.isHidden) {
      let leadOrigin: Double = theme.linear ? NSMaxX(viewRect) - NSWidth(_view.pagingRect) - border.width + ceil(theme.fullWidth * 0.5)
                                            : NSMinX(viewRect) + border.width + ceil(theme.fullWidth * 0.5);
      _view.pagingView.frame = NSMakeRect(leadOrigin - _view.pagingView.textContainerOrigin.x,
                                          NSMaxY(viewRect) - border.height - NSHeight(_view.pagingRect) - _view.pagingView.textContainerOrigin.y,
                                          (theme.linear ? NSWidth(_view.pagingRect) : NSWidth(viewRect) - border.width * 2) - theme.fullWidth,
                                          NSHeight(_view.pagingRect));
    }
    if (!_view.scrollView.isHidden) {
      _view.scrollView.frame = NSMakeRect(NSMinX(viewRect) + border.width,
                                          NSMinY(viewRect) + NSMinY(_view.candidatesRect),
                                          NSWidth(viewRect) - border.width * 2,
                                          NSHeight(_view.candidatesRect));
      _view.documentView.frame = NSMakeRect(0.0, 0.0, NSWidth(viewRect) - border.width * 2, NSHeight(_view.documentRect))
      _view.textView.frame = NSMakeRect(ceil(theme.fullWidth * 0.5) - _view.textView.textContainerOrigin.x,
                                        ceil(theme.lineSpacing * 0.5) - _view.textView.textContainerOrigin.y,
                                        NSWidth(viewRect) - border.width * 2 - theme.fullWidth,
                                        NSHeight(_view.documentRect) - theme.lineSpacing)
    }
    if (!(_back?.isHidden ?? true)) {
      _back?.frame = viewRect
    }
    orderFront(nil)
    // reset to initial position after showing status message
    _initPosition = !_view.statusView.isHidden
    _needsRedraw = false
    // voila !
  }

  func hide() {
    _statusTimer?.invalidate()
    _statusTimer = nil
    _toolTip.hide()
    self.orderOut(nil)
    _maxSize = NSZeroSize
    _initPosition = true
    expanded = false
    sectionNum = 0
  }

  // Main function to add attributes to text output from librime
  func showPreedit(_ preedit: String?,
                   selRange: NSRange,
                   caretPos: Int,
                   candidateIndices indexRange: Range<Int>,
                   highlightedCandidate: Int,
                   pageNum: Int,
                   finalPage: Boolean,
                   didCompose: Boolean) {
    let updateCandidates: Boolean = didCompose || _indexRange != indexRange
    _caretPos = caretPos
    _pageNum = pageNum
    _finalPage = finalPage
    _functionButton = .VoidSymbol
    if (indexRange.count > 0 || !(preedit?.isEmpty ?? true)) {
      _statusMessage = nil
      if (_view.statusContents.length > 0) {
        _view.statusContents.deleteCharacters(in: NSMakeRange(0, _view.statusContents.length))
      }
      if (_statusTimer != nil && _statusTimer!.isValid) {
        _statusTimer!.invalidate()
        _statusTimer = nil
      }
    } else {
      if (_statusMessage != nil) {
        showStatus(message: _statusMessage)
        _statusMessage = nil
      } else if !(_statusTimer?.isValid ?? false) {
        hide()
      }
      return
    }

    let theme: SquirrelTheme = _view.theme
    var rulerAttrsPreedit: NSParagraphStyle?
    let priorSize: NSSize = _view.candidateRanges.count > 0 || !_view.preeditView.isHidden ? _view.contentRect.size : NSZeroSize
    if ((indexRange.count == 0 || !updateCandidates) &&
        !(preedit?.isEmpty ?? true) && !_view.preeditView.isHidden) {
      rulerAttrsPreedit = _view.preeditContents.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }
    if (updateCandidates) {
      _view.contents.setAttributedString(NSAttributedString())
      if (theme.lineLength > 0.1) {
        _maxSize.width = min(theme.lineLength, _textWidthLimit)
      }
      _indexRange = indexRange
      _highlightedCandidate = highlightedCandidate
    }
    var candidateRanges: [SquirrelCandidateRanges] = []
    var truncated: [Boolean] = []
    var skipCandidates: Boolean = false

    // preedit
    if (!(preedit?.isEmpty ?? true)) {
      _view.preeditContents.setAttributedString(NSAttributedString(string: preedit!, attributes: theme.preeditAttrs))
      _view.preeditContents.mutableString.append(rulerAttrsPreedit == nil ? kFullWidthSpace : "\t")
      if (selRange.length > 0) {
        _view.preeditContents.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: selRange)
        let padding: Double = ceil(theme.preeditParagraphStyle.minimumLineHeight * 0.05)
        if (selRange.location > 0) {
          _view.preeditContents.addAttribute(.kern, value: padding,
                                             range: NSMakeRange(selRange.location - 1, 1))
        }
        if (NSMaxRange(selRange) < preedit!.count) {
          _view.preeditContents.addAttribute(.kern, value: padding,
                                             range: NSMakeRange(NSMaxRange(selRange) - 1, 1))
        }
      }
      _view.preeditContents.append(caretPos == NSNotFound || caretPos == 0 ? theme.symbolDeleteStroke! : theme.symbolDeleteFill!)
      // force caret to be rendered sideways, instead of uprights, in vertical orientation
      if (theme.vertical && caretPos != NSNotFound) {
        _view.preeditContents.addAttribute(.verticalGlyphForm, value: false,
                                           range: NSMakeRange(caretPos - (caretPos < NSMaxRange(selRange) ? 1 : 0), 1))
      }
      if (rulerAttrsPreedit != nil) {
        _view.preeditContents.addAttribute(.paragraphStyle, value: rulerAttrsPreedit!,
                                           range: NSMakeRange(0, _view.preeditContents.length))
      }

      if (updateCandidates && indexRange.isEmpty) {
        sectionNum = 0
        skipCandidates = true
      } else {
        _view.setPreedit(hilitedPreeditRange: selRange)
      }
    } else if (_view.preeditContents.length > 0) {
      _view.preeditContents.deleteCharacters(in: NSMakeRange(0, _view.preeditContents.length))
    }

    if (!updateCandidates) {
      if (_highlightedCandidate != highlightedCandidate) {
        highlightCandidate(highlightedCandidate)
      }
      let newSize: NSSize = _view.contentRect.size
      _needsRedraw = _needsRedraw || !NSEqualSizes(priorSize, newSize)
      show()
      return
    }

    // candidate items
    if (!skipCandidates && indexRange.count > 0) {
      for idx in 0..<indexRange.count {
        let col: Int = idx % theme.pageSize
        let candidate = (idx / theme.pageSize != _sectionNum ? theme.candidateDimmedTemplate!.mutableCopy()
                         : idx == highlightedCandidate ? theme.candidateHilitedTemplate.mutableCopy()
                         : theme.candidateTemplate.mutableCopy()) as! NSMutableAttributedString
        // plug in enumerator, candidate text and comment into the template
        let enumRange: NSRange = candidate.mutableString.range(of: "%c")
        candidate.replaceCharacters(in: enumRange, with: theme.labels[col])

        var textRange: NSRange = candidate.mutableString.range(of: "%@")
        let text: String = _inputController!.candidateTexts[idx + indexRange.lowerBound]
        candidate.replaceCharacters(in: textRange, with: text)

        let commentRange: NSRange = candidate.mutableString.range(of: kTipSpecifier)
        let comment: String = _inputController!.candidateComments[idx + indexRange.lowerBound]
        if (comment.count > 0) {
          candidate.replaceCharacters(in: commentRange, with: "\u{A0}" + comment)
        } else {
          candidate.deleteCharacters(in: commentRange)
        }
        // parse markdown and ruby annotation
        candidate.formatMarkDown()
        let annotationHeight: Double = candidate.annotateRuby(inRange: NSMakeRange(0, candidate.length),
                                                              verticalOrientation: theme.vertical,
                                                              maximumLength: _textWidthLimit,
                                                              scriptVariant: optionSwitcher.currentScriptVariant)
        if (annotationHeight * 2 > theme.lineSpacing) {
          setAnnotationHeight(annotationHeight)
          candidate.addAttribute(.paragraphStyle,
                                 value: theme.candidateParagraphStyle,
                                 range: NSMakeRange(0, candidate.length))
          if (idx > 0) {
            if (theme.linear) {
              var isTruncated: Boolean = truncated[0]
              var start: Int = candidateRanges[0].location
              for i in 1..<idx {
                if (i == idx || truncated[i] != isTruncated) {
                  _view.contents.addAttribute(.paragraphStyle,
                                              value: isTruncated ? theme.truncatedParagraphStyle! : theme.candidateParagraphStyle,
                                              range: NSMakeRange(start, candidateRanges[i - 1].maxRange() - start))
                  if (i < idx) {
                    isTruncated = truncated[i]
                    start = candidateRanges[i].location
                  }
                }
              }
            } else {
              _view.contents.addAttribute(.paragraphStyle, value: theme.candidateParagraphStyle,
                                          range: NSMakeRange(0, _view.contents.length))
            }
          }
        }
        // store final in-candidate locations of label, text, and comment
        textRange = candidate.mutableString.range(of: text)

        if (idx > 0 && col == 0 && theme.linear && !truncated[idx - 1]) {
          _view.contents.mutableString.append("\n")
        }
        let candidateStart: Int = _view.contents.length
        var ranges = SquirrelCandidateRanges(location: candidateStart,
                                             text: textRange.location,
                                             comment: NSMaxRange(textRange))
        _view.contents.append(candidate)
        // for linear layout, middle-truncate candidates that are longer than one line
        if (theme.linear && textWidth(candidate, vertical: theme.vertical) > _textWidthLimit - theme.fullWidth * (theme.tabular ? 3 : 2)) {
          truncated.append(true)
          ranges.length = _view.contents.length - candidateStart
          candidateRanges.append(ranges)
          if (idx < indexRange.count - 1 || theme.tabular || theme.showPaging) {
            _view.contents.mutableString.append("\n")
          }
          _view.contents.addAttribute(.paragraphStyle,
                                      value: theme.truncatedParagraphStyle!,
                                      range: NSMakeRange(candidateStart, _view.contents.length - candidateStart))
        } else {
          if (theme.linear || idx < indexRange.count - 1) {
            // separator: linear = "\u3000\x1D"; tabular = "\u3000\t\x1D"; stacked = "\n"
            _view.contents.append(theme.separator)
          }
          truncated.append(false)
          ranges.length = candidate.length + (theme.tabular ? 3 : theme.linear ? 2 : 0)
          candidateRanges.append(ranges)
        }
      }

      // paging indication
      if (theme.tabular || theme.showPaging) {
        if (theme.tabular) {
          _view.pagingContents.setAttributedString(_locked ? theme.symbolLock! : _view.expanded ? theme.symbolCompress! : theme.symbolExpand!)
        } else {
          let pageNumString = NSAttributedString(string: String(format: "%lu", pageNum + 1), attributes: theme.pagingAttrs)
          _view.pagingContents.setAttributedString(theme.vertical ? pageNumString.horizontalInVerticalForms() : pageNumString)
        }
        if (theme.showPaging) {
          _view.pagingContents.insert(_pageNum > 0 ? theme.symbolBackFill! : theme.symbolBackStroke!, at: 0)
          _view.pagingContents.mutableString.insert(kFullWidthSpace, at: 1)
          _view.pagingContents.mutableString.append(kFullWidthSpace)
          _view.pagingContents.append(_finalPage ? theme.symbolForwardStroke! : theme.symbolForwardFill!)
        }
      } else if (_view.pagingContents.length > 0) {
        _view.pagingContents.deleteCharacters(in: NSMakeRange(0, _view.pagingContents.length))
      }
    }

    _view.estimateBounds(onScreen: _screen.visibleFrame,
                         withPreedit: !(preedit?.isEmpty ?? true),
                         candidates: candidateRanges,
                         truncation: truncated,
                         paging: !indexRange.isEmpty && (theme.tabular || theme.showPaging))
    let textWidth: Double = clamp(NSWidth(_view.contentRect), _maxSize.width, _textWidthLimit)
    // right-align the backward delete symbol
    if (!(preedit?.isEmpty ?? true) && rulerAttrsPreedit == nil) {
      _view.preeditContents.replaceCharacters(in: NSMakeRange(_view.preeditContents.length - 2, 1), with: "\t")
      let rulerAttrs = theme.preeditParagraphStyle as! NSMutableParagraphStyle
      rulerAttrs.tabStops = [NSTextTab(textAlignment: .right, location: textWidth)]
      _view.preeditContents.addAttribute(.paragraphStyle, value: rulerAttrs,
                                         range: NSMakeRange(0, _view.preeditContents.length))
    }
    if (!theme.linear && theme.showPaging) {
      _view.pagingContents.replaceCharacters(in: NSMakeRange(1, 1), with: "\t")
      _view.pagingContents.replaceCharacters(in: NSMakeRange(_view.pagingContents.length - 2, 1), with: "\t")
      let rulerAttrsPaging: NSMutableParagraphStyle = theme.pagingParagraphStyle as! NSMutableParagraphStyle
      rulerAttrsPaging.tabStops = [NSTextTab(textAlignment: .center, location: textWidth * 0.5),
                                   NSTextTab(textAlignment: .right, location: textWidth)]
      _view.pagingContents.addAttribute(.paragraphStyle, value: rulerAttrsPaging, range: NSMakeRange(0, _view.pagingContents.length))
    }

    // text done!
    animationBehavior = caretPos == NSNotFound ? .utilityWindow : .default
    _view.drawView(withHilitedCandidate: highlightedCandidate,
                   hilitedPreeditRange: selRange)

    let newSize: NSSize = _view.contentRect.size
    _needsRedraw = _needsRedraw || !NSEqualSizes(priorSize, newSize)
    show()
  }

  func updateStatus(long: String?,
                    short: String?) {
    switch (_view.theme.statusMessageType) {
    case .mixed:
      _statusMessage = short != nil ? short : long
      break
    case .long:
      _statusMessage = long
      break
    case .short:
      _statusMessage = short != nil ? short : long != nil ? String(long![long!.rangeOfComposedCharacterSequence(at: long!.startIndex)]) : nil
      break
    }
  }

  private func showStatus(message:String!) {
    let theme: SquirrelTheme! = _view.theme
    let priorSize: NSSize = !_view.statusView.isHidden ? _view.contentRect.size : NSZeroSize

    _view.contents.deleteCharacters(in: NSMakeRange(0, _view.contents.length))
    _view.preeditContents.deleteCharacters(in: NSMakeRange(0, _view.preeditContents.length))
    _view.pagingContents.deleteCharacters(in: NSMakeRange(0, _view.pagingContents.length))

    _view.statusContents.setAttributedString(NSAttributedString(string: String(format:"\u{3000}\u{2002}%@", message),
                                                                attributes: theme.statusAttrs))

    _view.estimateBounds(onScreen: _screen.visibleFrame,
                         withPreedit: false,
                         candidates: [],
                         truncation: [],
                         paging: false)

    // disable remember_size and fixed line_length for status messages
    _initPosition = true
    _maxSize = NSZeroSize
    _statusTimer?.invalidate()
    animationBehavior = .utilityWindow
    _view.drawView(withHilitedCandidate: NSNotFound,
                   hilitedPreeditRange: NSMakeRange(NSNotFound, 0))

    let newSize: NSSize = _view.contentRect.size
    _needsRedraw = _needsRedraw || !NSEqualSizes(priorSize, newSize)
    show()
    _statusTimer = Timer.scheduledTimer(timeInterval: kShowStatusDuration,
                                        target: self,
                                        selector: #selector(hideStatus(_:)),
                                        userInfo: nil,
                                        repeats: false)
  }

  @objc func hideStatus(_ timer: Timer!) {
    hide()
  }

  private func setAnnotationHeight(_ height: Double) {
    SquirrelView.defaultTheme.setAnnotationHeight(height)
    if #available(macOS 10.14, *) {
      SquirrelView.darkTheme.setAnnotationHeight(height)
    }
  }

  func loadLabelConfig(_ config: SquirrelConfig,
                       directUpdate update: Boolean) {
    SquirrelView.defaultTheme.updateLabelsWithConfig(config, directUpdate: update)
    if #available(macOS 10.14, *) {
      SquirrelView.darkTheme.updateLabelsWithConfig(config, directUpdate: update)
    }
    if (update) {
      updateDisplayParameters()
    }
  }

  func loadConfig(_ config: SquirrelConfig) {
    SquirrelView.defaultTheme.updateWithConfig(config, styleOptions: optionSwitcher.optionStates,
                                               scriptVariant: optionSwitcher.currentScriptVariant,
                                               forAppearance: .light)
    if #available(macOS 10.14, *) {
      SquirrelView.darkTheme.updateWithConfig(config, styleOptions: optionSwitcher.optionStates,
                                              scriptVariant: optionSwitcher.currentScriptVariant,
                                              forAppearance: .dark)
    }
    getLocked()
    updateDisplayParameters()
  }

  func updateScriptVariant() {
    SquirrelView.defaultTheme.setScriptVariant(optionSwitcher.currentScriptVariant)
  }
}  // SquirrelPanel

