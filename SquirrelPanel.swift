import Cocoa
import QuartzCore

let kDefaultCandidateFormat: String = "%c. %@"
let kTipSpecifier: String = "%s"
let kFullWidthSpace: String  = "　"
let kShowStatusDuration: TimeInterval = 2.0
let kBlendedBackgroundColorFraction: Double  = 0.2
let kDefaultFontSize: Double  = 24
let kOffsetGap: Double = 5


extension NSBezierPath {

  var quartzPath: CGPath? {
    get {
      if #available(macOS 14.0, *) {
        return self.cgPath
      }
      // Need to begin a path here.
      let path: CGMutablePath = CGMutablePath()
      // Then draw the path elements.
      if (elementCount > 0) {
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
      }
      let immutablePath: CGPath? = path.copy()
      return immutablePath
    }
  }

}  // NSBezierPath (BezierPathQuartzUtilities)


extension NSMutableAttributedString {

  private func superscriptionRange(_ range: NSRange) {
    enumerateAttribute(.font, in: range, options: [.longestEffectiveRangeNotRequired])
    { (value: Any?, subRange: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
      if let oldFont = value as? NSFont {
        let newFont: NSFont! = NSFont.init(descriptor: oldFont.fontDescriptor, size: floor(oldFont.pointSize * 0.55))
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
        let newFont: NSFont! = NSFont.init(descriptor: oldFont.fontDescriptor, size: floor(oldFont.pointSize * 0.55))
        addAttributes([.font: newFont!,
                       kCTBaselineClassAttributeName as NSAttributedString.Key: kCTBaselineClassIdeographicCentered,
                       NSAttributedString.Key.superscript: -1],
                      range: subRange)
      }
    }
  }

  static let markDownPattern: String = "((\\*{1,2}|\\^|~{1,2})|((?<=\\b)_{1,2})|<(b|strong|i|em|u|sup|sub|s)>)(.+?)(\\2|\\3(?=\\b)|<\\/\\4>)"

  fileprivate func formatMarkDown() {
    if let regex = try? NSRegularExpression.init(pattern: NSMutableAttributedString.markDownPattern,
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

  fileprivate func annotateRuby(inRange range: NSRange,
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
          // base string must use only one font so that all fall within one glyph run and
          // the ruby annotation is aligned with no duplicates
          var baseFont: NSFont! = attribute(NSAttributedString.Key.font, at: baseRange.location, effectiveRange:nil) as? NSFont
          baseFont = CTFontCreateForStringWithLanguage(baseFont as CTFont, mutableString as CFString,
                                                       CFRangeMake(baseRange.location, baseRange.length), scriptVariant as CFString) as NSFont
          addAttribute(NSAttributedString.Key.font, value: baseFont!, range: baseRange)

          let rubyScale: Double = 0.5
          let rubyString: CFString = mutableString.substring(with: result!.range(at: 4)) as CFString
          let height: Double = isVertical ? (baseFont.vertical.ascender - baseFont.vertical.descender) : (baseFont.ascender - baseFont.descender)
          rubyLineHeight = ceil(height * rubyScale)
          let rubyText = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: Int(CTRubyPosition.count.rawValue))
          rubyText[Int(CTRubyPosition.before.rawValue)] = Unmanaged.passUnretained(rubyString)
          rubyText[Int(CTRubyPosition.after.rawValue)] = nil
          rubyText[Int(CTRubyPosition.interCharacter.rawValue)] = nil
          rubyText[Int(CTRubyPosition.inline.rawValue)] = nil
          let rubyAnnotation: CTRubyAnnotation = CTRubyAnnotationCreate(.distributeSpace, .none, rubyScale, rubyText)

          if #available(macOS 12.0, *) {
          } else {
            // use U+008B as placeholder for line-forward spaces in case ruby is wider than base
            replaceCharacters(in: NSMakeRange(NSMaxRange(baseRange), 0), with: String(format:"%C", 0x8B))
          }
          addAttributes([kCTRubyAnnotationAttributeName as NSAttributedString.Key: rubyAnnotation,
                         NSAttributedString.Key.font: baseFont!,
                         NSAttributedString.Key.verticalGlyphForm: isVertical],
                        range: baseRange)
        }
      })
      mutableString.replaceOccurrences(of: "[\u{FFF9}-\u{FFFB}]", with: "", options: .regularExpression, range: range)
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
        let context:CGContext = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.translateBy(x: NSWidth(dstRect) * 0.5, y: NSHeight(dstRect) * 0.5)
        context.rotate(by: -.pi / 2)
        let origin: CGPoint = CGPointMake(0 - self.size().width / width * NSHeight(dstRect) * 0.5, 0 - NSWidth(dstRect) * 0.5)
        self.draw(at: origin)
        context.restoreGState()
        return true
      })
    image.resizingMode = .stretch
    image.size = NSMakeSize(height, height)
    let attm: NSTextAttachment! = NSTextAttachment()
    attm.image = image
    attm.bounds = NSMakeRect(0, font.descender, height, height)
    attrs[NSAttributedString.Key.attachment] = attm
    return NSAttributedString.init(string: String(unichar(NSTextAttachment.character)), attributes: attrs)
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

}  // NSColorSpace (labColorSpace)

enum ColorInversionExtent: Int {
  case standard = 0
  case augmented = 1
  case moderate = -1
}

extension NSColor {

  var luminanceComponent: Double? {
    var luminance: Double? = 0.0
    var aGnRd: Double? = nil
    var bBuYl: Double? = nil
    var alpha: Double? = nil
    getLuminance(luminance: &luminance, aGnRd: &aGnRd, bBuYl: &bBuYl, alpha: &alpha)
    return luminance
  }

  var aGnRdComponent:  Double? {
    var luminance: Double? = nil
    var aGnRd: Double? = 0.0
    var bBuYl: Double? = nil
    var alpha: Double? = nil
    getLuminance(luminance: &luminance, aGnRd: &aGnRd, bBuYl: &bBuYl, alpha: &alpha)
    return aGnRd
  }

  var bBuYlComponent:  Double? {
    var luminance: Double? = nil
    var aGnRd: Double? = nil
    var bBuYl: Double? = 0.0
    var alpha: Double? = nil
    getLuminance(luminance: &luminance, aGnRd: &aGnRd, bBuYl: &bBuYl, alpha: &alpha)
    return bBuYl
  }

  class func colorWithLabLuminance(luminance: Double,
                                   aGnRd: Double,
                                   bBuYl: Double,
                                   alpha: Double) -> NSColor {
    let lum: Double = max(min(luminance, 100.0), 0.0)
    let green_red: Double = max(min(aGnRd, 127.0), -127.0)
    let blue_yellow: Double = max(min(bBuYl, 127.0), -127.0)
    let opaque: Double = max(min(alpha, 1.0), 0.0)
    let components: [CGFloat] = [lum, green_red, blue_yellow, opaque]
    return NSColor(colorSpace: NSColorSpace.labColorSpace,
                   components: components, count: 4)
  }

  func getLuminance(luminance: inout Double?,
                    aGnRd: inout Double?,
                    bBuYl: inout Double?,
                    alpha: inout Double?) {
    let labColor: NSColor = colorSpace.isEqual(to: NSColorSpace.labColorSpace) ? self : self.usingColorSpace(NSColorSpace.labColorSpace)!
    var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
    labColor.getComponents(&components)
    if (luminance != nil) {
      luminance = components[0] / 100.0
    }
    if (aGnRd != nil) {
      aGnRd = components[1] / 127.0 // green-red
    }
    if (bBuYl != nil) {
      bBuYl = components[2] / 127.0 // blue-yellow
    }
    if (alpha != nil) {
      alpha = components[3]
    }
  }

  func invertLuminance(toExtent extent: ColorInversionExtent) -> NSColor {
    let labColor: NSColor = usingColorSpace(NSColorSpace.labColorSpace)!
    var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
    labColor.getComponents(&components)
    let isDark: Boolean = components[0] < 60
    switch (extent) {
    case .augmented:
      components[0] = isDark ? 100.0 - components[0] * 2.0 / 3.0 : 150.0 - components[0] * 1.5
      break
    case .moderate:
      components[0] = isDark ? 80.0 - components[0] / 3.0 : 135.0 - components[0] * 1.25
      break
    case .standard:
      components[0] = isDark ? 90.0 - components[0] / 2.0 : 120.0 - components[0]
      break
    }
    let invertedColor: NSColor = NSColor(colorSpace: NSColorSpace.labColorSpace,
                                         components: components, count: 4)
    return invertedColor.usingColorSpace(colorSpace)!
  }

  // semantic colors
  static var secondaryTextColor: NSColor {
    get {
      if #available(macOS 10.10, *) {
        return NSColor.secondaryLabelColor
      } else {
        return NSColor.disabledControlTextColor
      }
    }
  }

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
        return NSAppearance.current.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? highlight(withLevel: 0.3)! : shadow(withLevel: 0.3)!
      }
    }
  }

  var disabledColor: NSColor {
    get {
      if #available(macOS 10.14, *) {
        return withSystemEffect(.disabled)
      } else {
        return NSAppearance.current.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? shadow(withLevel: 0.3)! : highlight(withLevel: 0.3)!
      }
    }
  }

  func blendWithColor(_ color: NSColor, ofFraction fraction: CGFloat) -> NSColor? {
    let alpha: CGFloat = self.alphaComponent * color.alphaComponent
    let opaqueColor: NSColor = self.withAlphaComponent(1.0).blended(withFraction: fraction, of: color.withAlphaComponent(1.0))!
    return opaqueColor.withAlphaComponent(alpha)
  }

}  // NSColor (colorWithLabColorSpace)

// MARK: - Color scheme and other user configurations

enum SquirrelAppear: Int {
  case defaultAppear = 0
  case darkAppear = 1
}

enum SquirrelStatusMessageType {
  case mixed
  case short
  case long
}

fileprivate func blendColors(foreground: NSColor!,
                             background: NSColor?) -> NSColor! {
  return foreground.blended(withFraction: kBlendedBackgroundColorFraction,
                            of: background ?? NSColor.lightGray)!.withAlphaComponent(foreground.alphaComponent)
}

fileprivate func getFontDescriptor(fullname: String!) -> NSFontDescriptor? {
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
      let fontDescriptor: NSFontDescriptor! = font.fontDescriptor
      let UIFontDescriptor: NSFontDescriptor = fontDescriptor.withSymbolicTraits(.UIOptimized)
      validFontDescriptors.append(NSFont(descriptor: UIFontDescriptor, size: 0.0) != nil ? UIFontDescriptor : fontDescriptor)
    }
  }
  if (validFontDescriptors.count == 0) {
    return nil
  }
  let initialFontDescriptor: NSFontDescriptor! = validFontDescriptors[0]
  var fallbackDescriptors: [NSFontDescriptor]! = validFontDescriptors.suffix(validFontDescriptors.count - 1)
  fallbackDescriptors.append(NSFontDescriptor(name:"AppleColorEmoji", size:0.0))
  return initialFontDescriptor.addingAttributes([NSFontDescriptor.AttributeName.cascadeList : fallbackDescriptors as Any])
}

fileprivate func getLineHeight(font: NSFont!,
                               vertical: Boolean) -> Double! {
  var lineHeight: Double = ceil(vertical ? font.vertical.ascender - font.vertical.descender : font.ascender - font.descender)
  let fallbackList: [NSFontDescriptor]! = font.fontDescriptor.fontAttributes[NSFontDescriptor.AttributeName.cascadeList] as? [NSFontDescriptor]
  for fallback: NSFontDescriptor in fallbackList {
    let fallbackFont: NSFont! = NSFont(descriptor: fallback, size: font.pointSize)
    lineHeight = max(lineHeight, ceil(vertical ? fallbackFont.vertical.ascender - fallbackFont.vertical.descender
                                               : fallbackFont.ascender - fallbackFont.descender))
  }
  return lineHeight
}

fileprivate func updateCandidateListLayout(isLinear: inout Boolean,
                                           isTabular: inout Boolean,
                                           config: SquirrelConfig,
                                           prefix: String) {
  let candidateListLayout: String = config.getStringForOption(prefix + "/candidate_list_layout") ?? ""
  if (candidateListLayout == "stacked") {
    isLinear = false
    isTabular = false
  } else if (candidateListLayout == "linear") {
    isLinear = true
    isTabular = false
  } else if (candidateListLayout == "tabular") {
    // `tabular` is a derived layout of `linear`; tabular implies linear
    isLinear = true
    isTabular = true
  } else {
    // Deprecated. Not to be confused with text_orientation: horizontal
    if let horizontal = config.getOptionalBoolForOption(prefix + "/horizontal") {
      isLinear = horizontal
      isTabular = false
    }
  }
}

fileprivate func updateTextOrientation(isVertical: inout Boolean,
                                       config: SquirrelConfig,
                                       prefix: String) {
  let textOrientation: String = config.getStringForOption(prefix + "/text_orientation") ?? ""
  if (textOrientation == "horizontal") {
    isVertical = false
  } else if (textOrientation == "vertical") {
    isVertical = true
  } else {
    if let vertical = config.getOptionalBoolForOption(prefix + "/vertical") {
      isVertical = vertical
    }
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
  private var _commentForeColor: NSColor = NSColor.secondaryTextColor
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
  private var _cornerRadius: Double = 0
  var cornerRadius: Double { get { return _cornerRadius } }
  private var _hilitedCornerRadius: Double = 0
  var hilitedCornerRadius: Double { get { return _hilitedCornerRadius } }
  private var _fullWidth: Double
  var fullWidth: Double { get { return _fullWidth } }
  private var _linespace: Double = 0
  var linespace: Double { get { return _linespace } }
  private var _preeditLinespace: Double = 0
  var preeditLinespace: Double { get { return _preeditLinespace } }
  private var _opacity: Double = 1
  var opacity: Double { get { return _opacity } }
  private var _translucency: Double = 0
  var translucency: Double { get { return _translucency } }
  private var _lineLength: Double = 0
  var lineLength: Double { get { return _lineLength } }
  private var _borderInsets: NSSize = NSZeroSize
  var borderInsets: NSSize { get { return _borderInsets } }
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
  private var _fullWidthPlaceholder: NSAttributedString
  var fullWidthPlaceholder: NSAttributedString { get { return _fullWidthPlaceholder } }
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
  var pageSize: Int { get {return _pageSize } }

  override init() {
    let candidateParagraphStyle: NSMutableParagraphStyle! = NSMutableParagraphStyle()
    candidateParagraphStyle.alignment = .left
    // Use left-to-right marks to declare the default writing direction and prevent strong right-to-left
    // characters from setting the writing direction in case the label are direction-less symbols
    candidateParagraphStyle.baseWritingDirection = .leftToRight

    let preeditParagraphStyle: NSMutableParagraphStyle! = candidateParagraphStyle
    let pagingParagraphStyle: NSMutableParagraphStyle! = candidateParagraphStyle
    let statusParagraphStyle: NSMutableParagraphStyle! = candidateParagraphStyle

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
    _commentAttrs[.foregroundColor] = NSColor.secondaryTextColor
    _commentAttrs[.font] = userFont

    _preeditAttrs = [:]
    _preeditAttrs[.foregroundColor] = NSColor.textColor
    _preeditAttrs[.font] = userFont
    _preeditAttrs[.ligature] = 0
    _preeditAttrs[.paragraphStyle] = preeditParagraphStyle

    _pagingAttrs = [:]
    _pagingAttrs[.font] = monoDigitFont
    _pagingAttrs[.foregroundColor] = NSColor.controlTextColor

    _statusAttrs = _commentAttrs
    _statusAttrs[.paragraphStyle] = statusParagraphStyle

    _separator = NSAttributedString(string: "\n", attributes: [.font: userFont!])
    _fullWidthPlaceholder = NSAttributedString(string: kFullWidthSpace, attributes: [.font: userFont!])
    _fullWidth = ceil(_fullWidthPlaceholder.size().width)

    super.init()
    updateCandidateFormat(forAttributesOnly: false)
    updateSeperatorAndSymbolAttrs()
  }

  private func updateSeperatorAndSymbolAttrs() {
    var sepAttrs: [NSAttributedString.Key : Any] = commentAttrs
    sepAttrs[NSAttributedString.Key.verticalGlyphForm] = false
    sepAttrs[NSAttributedString.Key.kern] = 0.0
    _separator = NSAttributedString(string: linear ? (tabular ? "\u{3000}\t\u{1D}" : "\u{3000}\u{1D}") : "\n",
                                    attributes: sepAttrs)
    _fullWidthPlaceholder = NSAttributedString(string: kFullWidthSpace, attributes: commentAttrs)
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

  fileprivate func updateLabelsWithConfig(_ config: SquirrelConfig,
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
        let keyCaps: String.UTF16View = selectKeys!.uppercased().applyingTransform(.fullwidthToHalfwidth, reverse: true)!.utf16
        for i in 0..<menuSize {
          labels.append(String(keyCaps[keyCaps.index(keyCaps.startIndex, offsetBy: i)]))
        }
      }
    } else {
      selectKeys = String("1234567890".prefix(menuSize))
      if (selectLabels.isEmpty) {
        let numerals: String.UTF16View = selectKeys!.applyingTransform(.fullwidthToHalfwidth, reverse: true)!.utf16
        for i in 0..<menuSize {
          labels.append(String(numerals[numerals.index(numerals.startIndex, offsetBy: i)]))
        }
      }
    }
    setSelectKeys(selectKeys!, labels: labels, directUpdate: update)
  }

  fileprivate func setSelectKeys(_ selectKeys: String,
                                 labels: [String],
                                 directUpdate update: Boolean) {
    _selectKeys = selectKeys
    _labels = labels
    _pageSize = labels.count
    if (update) {
      updateCandidateFormat(forAttributesOnly: true)
    }
  }

  fileprivate func setCandidateFormat(_ candidateFormat: String) {
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
      let labelCharacters: CharacterSet = CharacterSet.init(charactersIn: _labels.joined())
      if (CharacterSet.init(charactersIn: Unicode.Scalar(0xFF10)!...Unicode.Scalar(0xFF19)!).isSuperset(of: labelCharacters)) { // ０１..９
        if let range = format.range(of: "%c\u{20E3}", options: .literal) { // 1︎⃣..9︎⃣0︎⃣
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF10 + 0x0030
            labels[i] = String(chars) + "\u{FE0E}\u{20E3}"
          }
        } else if let range = format.range(of: "%c\u{20DD}", options: .literal) { // ①..⑨⓪
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value == 0xFF10 ? 0x24EA : _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF11 + 0x2460
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "(%c)", options: .literal) { // ⑴..⑼⑽
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value == 0xFF10 ? 0x247D : _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF11 + 0x2474
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "%c.", options: .literal) { // ⒈..⒐🄀
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value == 0xFF10 ? 0x1F100 : _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF11 + 0x2488
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "%c,", options: .literal) { // 🄂..🄊🄁
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF10 + 0x1F101
            labels[i] = String(chars)
          }
        }
      } else if (CharacterSet.init(charactersIn: Unicode.Scalar(0xFF21)!...Unicode.Scalar(0xFF3A)!).isSuperset(of: labelCharacters)) { // Ａ..Ｚ
        if let range = format.range(of: "%c\u{20DD}", options: .literal) { // Ⓐ..Ⓩ
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF21 + 0x24B6
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "(%c)", options: .literal) { // 🄐..🄩
          enumRange = range
          for i in 0..<_labels.count {
            let chars: UTF32.CodeUnit = _labels[i].unicodeScalars[_labels[i].startIndex].value - 0xFF21 + 0x1F110
            labels[i] = String(chars)
          }
        } else if let range = format.range(of: "%c\u{20DE}", options: .literal) { // 🄰..🅉
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
    let labelFont: NSFont = _labelAttrs[.font] as! NSFont
    var substituteFont: NSFont! = CTFontCreateForString(labelFont as CTFont, labelString as CFString, CFRangeMake(0, labelString.count)) as NSFont
    if (substituteFont.isNotEqual(to: labelFont)) {
      let monoDigitAttrs: [NSFontDescriptor.AttributeName: [[NSFontDescriptor.FeatureKey: Int]]] =
      [.featureSettings:
        [[.typeIdentifier: kNumberSpacingType,
          .selectorIdentifier: kMonospacedNumbersSelector],
         [.typeIdentifier: kTextSpacingType,
          .selectorIdentifier: kHalfWidthTextSelector]]]
      let subFontDescriptor: NSFontDescriptor = substituteFont.fontDescriptor.addingAttributes(monoDigitAttrs)
      substituteFont = NSFont.init(descriptor: subFontDescriptor, size: labelFont.pointSize)
      _labelAttrs[.font] = substituteFont
    }

    var textRange: NSRange = candidateTemplate.mutableString.range(of: "%@", options: .literal)
    var labelRange: NSRange = NSMakeRange(0, textRange.location)
    var commentRange: NSRange = NSMakeRange(NSMaxRange(textRange), candidateTemplate.length - NSMaxRange(textRange))
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
      commentRange = NSMakeRange(NSMaxRange(textRange), candidateTemplate.length - NSMaxRange(textRange))
      if (commentRange.length > 0) {
        candidateTemplate.replaceCharacters(in: commentRange, with: kTipSpecifier + candidateTemplate.mutableString.substring(with: commentRange))
      } else {
        candidateTemplate.append(NSAttributedString(string: kTipSpecifier, attributes: _commentAttrs))
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
    let candidateParagraphStyle: NSMutableParagraphStyle = _candidateParagraphStyle as! NSMutableParagraphStyle
    if (!linear) {
      var indent: CGFloat = 0.0
      let labelFormat: NSAttributedString = candidateTemplate.attributedSubstring(from: NSMakeRange(0, labelRange.length - 1))
      for label in _labels {
        let enumString: NSMutableAttributedString = labelFormat as! NSMutableAttributedString
        enumString.mutableString.replaceOccurrences(of: "%c", with: label, options: .literal, range: NSMakeRange(0, enumString.length))
        enumString.addAttribute(.verticalGlyphForm, value: vertical, range: NSMakeRange(0, enumString.length))
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
      let truncatedParagraphStyle: NSMutableParagraphStyle = candidateParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
      truncatedParagraphStyle.lineBreakMode = .byTruncatingMiddle
      truncatedParagraphStyle.tighteningFactorForTruncation = 0.0
      _truncatedParagraphStyle = truncatedParagraphStyle
    }

    _textAttrs[.paragraphStyle] = candidateParagraphStyle
    _commentAttrs[.paragraphStyle] = candidateParagraphStyle
    _labelAttrs[.paragraphStyle] = candidateParagraphStyle
    candidateTemplate.addAttribute(.paragraphStyle, value: candidateParagraphStyle, range: NSMakeRange(0, candidateTemplate.length))
    _candidateTemplate = candidateTemplate

    let candidateHilitedTemplate: NSMutableAttributedString = candidateTemplate.mutableCopy() as! NSMutableAttributedString
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedLabelForeColor, range: labelRange)
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedTextForeColor, range: textRange)
    candidateHilitedTemplate.addAttribute(.foregroundColor, value: hilitedCommentForeColor, range: commentRange)
    _candidateHilitedTemplate = candidateHilitedTemplate

    if (tabular) {
      let candidateDimmedTemplate: NSMutableAttributedString = candidateTemplate.mutableCopy() as! NSMutableAttributedString
      candidateDimmedTemplate.addAttribute(.foregroundColor, value: dimmedLabelForeColor!, range: labelRange)
      _candidateDimmedTemplate = candidateDimmedTemplate
    }
  }

  fileprivate func setStatusMessageType(_ type: String?) {
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

  fileprivate func updateWithConfig(_ config: SquirrelConfig,
                                    styleOptions: Set<String>,
                                    scriptVariant: String,
                                    forAppearance appear: SquirrelAppear) {
    // INTERFACE
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
    // TYPOGRAPHY
    var fontName: String? = config.getStringForOption("style/font_face")
    var fontSize: Double? = config.getOptionalDoubleForOption("style/font_point", applyConstraint: pos_round)
    var labelFontName: String? = config.getStringForOption("style/label_font_face")
    var labelFontSize: Double? = config.getOptionalDoubleForOption("style/label_font_point", applyConstraint: pos_round)
    var commentFontName: String? = config.getStringForOption("style/comment_font_face")
    var commentFontSize: Double? = config.getOptionalDoubleForOption("style/comment_font_point", applyConstraint: pos_round)
    var opacity: Double? = config.getOptionalDoubleForOption("style/opacity", alias: "alpha", applyConstraint: clamp_uni)
    var translucency: Double? = config.getOptionalDoubleForOption("style/translucency", applyConstraint: clamp_uni)
    var cornerRadius: Double? = config.getOptionalDoubleForOption("style/corner_radius", applyConstraint: positive)
    var hilitedCornerRadius: Double? = config.getOptionalDoubleForOption("style/hilited_corner_radius", applyConstraint: positive)
    var borderHeight: Double? = config.getOptionalDoubleForOption("style/border_height", applyConstraint: pos_ceil)
    var borderWidth: Double? = config.getOptionalDoubleForOption("style/border_width", applyConstraint: pos_ceil)
    var lineSpacing: Double? = config.getOptionalDoubleForOption("style/line_spacing", applyConstraint: pos_round)
    var spacing: Double? = config.getOptionalDoubleForOption("style/spacing", applyConstraint: pos_round)
    var baseOffset: Double? = config.getOptionalDoubleForOption("style/base_offset")
    var lineLength: Double? = config.getOptionalDoubleForOption("style/line_length")
    // CHROMATICS
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
    if (appear == .darkAppear) {
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
      // CHROMATICS override
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
      // for backward compatibility, 'label_hilited_color' and 'hilited_candidate_label_color' are both valid
      hilitedLabelForeColor = config.getColorForOption(prefix + "/label_hilited_color", alias: "hilited_candidate_label_color") ?? hilitedLabelForeColor
      backImage = config.getImageForOption(prefix + "/back_image") ?? backImage

      // the following per-color-scheme configurations, if exist, will
      // override configurations with the same name under the global 'style' section
      // INTERFACE override
      updateCandidateListLayout(isLinear: &linear, isTabular: &tabular, config: config, prefix: prefix)
      updateTextOrientation(isVertical: &vertical, config: config, prefix: prefix)
      inlinePreedit = config.getOptionalBoolForOption(prefix + "/inline_preedit") ?? inlinePreedit
      inlineCandidate = config.getOptionalBoolForOption(prefix + "/inline_candidate") ?? inlineCandidate
      showPaging = config.getOptionalBoolForOption(prefix + "/show_paging") ?? showPaging
      rememberSize = config.getOptionalBoolForOption(prefix + "/remember_size") ?? rememberSize
      statusMessageType = config.getStringForOption(prefix + "/status_message_type") ?? statusMessageType
      candidateFormat = config.getStringForOption(prefix + "/candidate_format") ?? candidateFormat
      // TYPOGRAPHY override
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

    // TYPOGRAPHY refinement
    fontSize = fontSize ?? kDefaultFontSize
    labelFontSize = labelFontSize ?? fontSize
    commentFontSize = commentFontSize ?? fontSize
    let monoDigitAttrs: [NSFontDescriptor.AttributeName: [[NSFontDescriptor.FeatureKey: Any]]] =
      [.featureSettings: [[.typeIdentifier: kNumberSpacingType,
                           .selectorIdentifier: kMonospacedNumbersSelector],
                          [.typeIdentifier: kTextSpacingType,
                           .selectorIdentifier: kHalfWidthTextSelector]]]

    let fontDescriptor: NSFontDescriptor! = getFontDescriptor(fullname: fontName)
    let font: NSFont! = NSFont.init(descriptor: (fontDescriptor ?? getFontDescriptor(fullname: NSFont.userFont(ofSize: 0)?.fontName))!, size: fontSize!)

    let labelFontDescriptor: NSFontDescriptor! = (getFontDescriptor(fullname: labelFontName) ?? fontDescriptor)!.addingAttributes(monoDigitAttrs)
    let labelFont: NSFont! = labelFontDescriptor != nil ? NSFont.init(descriptor: labelFontDescriptor, size: labelFontSize!) : NSFont.monospacedDigitSystemFont(ofSize: labelFontSize!, weight: .regular)

    let commentFontDescriptor: NSFontDescriptor! = getFontDescriptor(fullname: commentFontName)
    let commentFont: NSFont! = NSFont.init(descriptor: commentFontDescriptor ?? fontDescriptor, size: commentFontSize!)

    let pagingFont: NSFont! = NSFont.monospacedDigitSystemFont(ofSize: labelFontSize!, weight: .regular)

    let fontHeight: Double = getLineHeight(font: font, vertical: vertical)
    let labelFontHeight: Double = getLineHeight(font: labelFont, vertical: vertical)
    let commentFontHeight: Double = getLineHeight(font: commentFont, vertical: vertical)
    let lineHeight: Double = max(fontHeight, max(labelFontHeight, commentFontHeight))
    let fullWidth: Double = ceil(kFullWidthSpace.size(withAttributes: [NSAttributedString.Key.font : commentFont!]).width)
    spacing = spacing ?? 0
    lineSpacing = lineSpacing ?? 0

    let preeditRulerAttrs: NSMutableParagraphStyle = _preeditParagraphStyle as! NSMutableParagraphStyle
    preeditRulerAttrs.minimumLineHeight = fontHeight
    preeditRulerAttrs.maximumLineHeight = fontHeight
    preeditRulerAttrs.paragraphSpacing = spacing!
    preeditRulerAttrs.tabStops = []

    let candidateRulerAttrs: NSMutableParagraphStyle = _candidateParagraphStyle as! NSMutableParagraphStyle
    candidateRulerAttrs.minimumLineHeight = lineHeight
    candidateRulerAttrs.maximumLineHeight = lineHeight
    candidateRulerAttrs.paragraphSpacingBefore = ceil(lineSpacing! * 0.5)
    candidateRulerAttrs.paragraphSpacing = floor(lineSpacing! * 0.5)
    candidateRulerAttrs.tabStops = []
    candidateRulerAttrs.defaultTabInterval = fullWidth * 2

    let pagingRulerAttrs: NSMutableParagraphStyle = _pagingParagraphStyle as! NSMutableParagraphStyle
    pagingRulerAttrs.minimumLineHeight = ceil(pagingFont.ascender - pagingFont.descender)
    pagingRulerAttrs.maximumLineHeight = ceil(pagingFont.ascender - pagingFont.descender)
    pagingRulerAttrs.tabStops = []

    let statusRulerAttrs: NSMutableParagraphStyle = _statusParagraphStyle as! NSMutableParagraphStyle
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

    let zhFont: NSFont = CTFontCreateUIFontForLanguage(.system, fontSize!, scriptVariant as CFString)!
    let zhCommentFont: NSFont = NSFont.init(descriptor: zhFont.fontDescriptor, size: commentFontSize!)!
    let maxFontSize: Double = max(fontSize!, max(commentFontSize!, labelFontSize!))
    let refFont: NSFont = NSFont.init(descriptor: zhFont.fontDescriptor, size: maxFontSize)!
    let baselineRefInfo = [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont,
                kCTBaselineClassIdeographicCentered: vertical ? 0.0 : refFont.ascender * 0.5 + refFont.descender * 0.5,
                              kCTBaselineClassRoman: vertical ? 0.0 - refFont.vertical.ascender * 0.5 - refFont.vertical.descender * 0.5 : 0.0,
                     kCTBaselineClassIdeographicLow: vertical ? refFont.vertical.descender * 0.5 - refFont.vertical.ascender * 0.5 : refFont.descender] as [CFString : Any]

    _textAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _labelAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _commentAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] = baselineRefInfo
    _preeditAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? zhFont.vertical : zhFont]
    _pagingAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: linear ? (vertical ? refFont.vertical : refFont) : pagingFont]
    _statusAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? zhCommentFont.vertical : zhCommentFont]

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
          (appear == .darkAppear ? backColor!.luminanceComponent! > 0.65 : backColor!.luminanceComponent! < 0.55)) {
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
    _commentForeColor = commentForeColor ?? .secondaryTextColor
    _labelForeColor = labelForeColor ?? (isNative ? .accentColor : blendColors(foreground: _textForeColor, background: _backColor))
    _hilitedPreeditBackColor = hilitedPreeditBackColor ?? (isNative ? .selectedTextBackgroundColor : nil)
    _hilitedPreeditForeColor = hilitedPreeditForeColor ?? .selectedTextColor
    _hilitedCandidateBackColor = hilitedCandidateBackColor ?? (isNative ? .selectedContentBackgroundColor : nil)
    _hilitedTextForeColor = hilitedTextForeColor ?? .selectedMenuItemTextColor
    _hilitedCommentForeColor = hilitedCommentForeColor ?? .alternateSelectedControlTextColor
    _hilitedLabelForeColor = hilitedLabelForeColor ?? (isNative ? .alternateSelectedControlTextColor : blendColors(foreground: _hilitedTextForeColor, background: _hilitedCandidateBackColor))
    _dimmedLabelForeColor = tabular ? _labelForeColor.withAlphaComponent(_labelForeColor.alphaComponent * 0.5) : nil

    _textAttrs[.foregroundColor] = _textForeColor
    _labelAttrs[.foregroundColor] = _labelForeColor
    _commentAttrs[.foregroundColor] = _commentForeColor
    _preeditAttrs[.foregroundColor] = _preeditForeColor
    _pagingAttrs[.foregroundColor] = _preeditForeColor
    _statusAttrs[.foregroundColor] = _commentForeColor

    _cornerRadius = min(cornerRadius ?? 0, lineHeight * 0.5)
    _hilitedCornerRadius = min(hilitedCornerRadius ?? 0, lineHeight * 0.5)
    _fullWidth = fullWidth
    _linespace = lineSpacing!
    _preeditLinespace = spacing!
    _opacity = opacity ?? 1.0
    _translucency = translucency!
    _lineLength = lineLength != nil && lineLength! > 0.1 ? max(ceil(lineLength!), fullWidth * 5) : 0
    _borderInsets = vertical ? NSMakeSize(borderHeight ?? 0, borderWidth ?? 0)
                            : NSMakeSize(borderWidth ?? 0, borderHeight ?? 0)
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

  fileprivate func setAnnotationHeight(_ height: Double) {
    if (height > 0.1 && linespace < height * 2) {
      _linespace = height * 2
      let candidateParagraphStyle: NSMutableParagraphStyle = _candidateParagraphStyle as! NSMutableParagraphStyle
      candidateParagraphStyle.paragraphSpacingBefore = height
      candidateParagraphStyle.paragraphSpacing = height
      _candidateParagraphStyle = candidateParagraphStyle as NSParagraphStyle
    }
  }

  fileprivate func setScriptVariant(_ scriptVariant: String) {
    if (scriptVariant == _scriptVariant) {
      return
    }
    _scriptVariant = scriptVariant;

    let textFontSize: Double = (_textAttrs[.font] as! NSFont).pointSize
    let commentFontSize: Double = (_commentAttrs[.font] as! NSFont).pointSize
    let labelFontSize: Double = (_labelAttrs[.font] as! NSFont).pointSize
    let zhFont: NSFont = CTFontCreateUIFontForLanguage(.system, textFontSize, scriptVariant as CFString)!
    let zhCommentFont: NSFont = NSFont.init(descriptor: zhFont.fontDescriptor, size: commentFontSize)!
    let maxFontSize: Double = max(textFontSize, commentFontSize, labelFontSize)
    let refFont: NSFont = NSFont.init(descriptor: zhFont.fontDescriptor, size: maxFontSize)!

    _textAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    _labelAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    _commentAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    _preeditAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? zhFont.vertical : zhFont]
    _statusAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? zhCommentFont.vertical : zhCommentFont]

    _textAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
    _labelAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
    _commentAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
    _preeditAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
    _statusAttrs[kCTLanguageAttributeName as NSAttributedString.Key] = scriptVariant;
  }

}  // SquirrelTheme

// MARK: - Typesetting extensions for TextKit 1 (Mac OSX 10.9 to MacOS 11)

class SquirrelLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {

  override func drawGlyphs(forGlyphRange glyphsToShow: NSRange,
                           at origin: NSPoint) {
    let textContainer: NSTextContainer! = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil, withoutAdditionalLayout: true)
    let verticalOrientation: Boolean = textContainer.layoutOrientation == .vertical
    let context: CGContext = NSGraphicsContext.current!.cgContext
    context.resetClip()
    enumerateLineFragments(forGlyphRange: glyphsToShow) { (lineRect: NSRect, lineUsedRect: NSRect, textContainer: NSTextContainer, lineRange: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
      let charRange: NSRange = self.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)
      self.textStorage!.enumerateAttributes(in: charRange,
                                       options: [.longestEffectiveRangeNotRequired])
      { (attrs: [NSAttributedString.Key : Any], runRange: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
        let runGlyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
        if (attrs[kCTRubyAnnotationAttributeName as NSAttributedString.Key] != nil) {
          context.saveGState()
          context.scaleBy(x: 1.0, y: -1.0)
          var glyphIndex: Int = runGlyphRange.location
          let line: CTLine = CTLineCreateWithAttributedString(self.textStorage!.attributedSubstring(from: runRange) as CFAttributedString)
          let runs: CFArray = CTLineGetGlyphRuns(line)
          for i in 0..<CFArrayGetCount(runs) {
            let position: CGPoint = self.location(forGlyphAt: glyphIndex)
            let run: CTRun = CFArrayGetValueAtIndex(runs, i) as! CTRun
            let glyphCount: Int = CTRunGetGlyphCount(run)
            var matrix: CGAffineTransform = CTRunGetTextMatrix(run)
            var glyphOrigin: CGPoint = CGPointMake(origin.x + lineRect.origin.x + position.x, -origin.y - lineRect.origin.y - position.y)
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
          let runFont: NSFont! = attrs[NSAttributedString.Key.font] as? NSFont
          let baselineClass: String! = attrs[kCTBaselineClassAttributeName as NSAttributedString.Key] as? String
          var offset: NSPoint = NSZeroPoint
          if (!verticalOrientation && (baselineClass == kCTBaselineClassIdeographicCentered as String ||
                                       baselineClass == kCTBaselineClassMath as String)) {
            let refFont: NSFont = (attrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] as! [String: Any])[kCTBaselineReferenceFont as String] as! NSFont
            offset.y += runFont.ascender * 0.5 + runFont.descender * 0.5 - refFont.ascender * 0.5 - refFont.descender * 0.5
          } else if (verticalOrientation && runFont.pointSize < 24 && (runFont.fontName == "AppleColorEmoji")) {
            let superscript: Int! = attrs[NSAttributedString.Key.superscript] as? Int
            offset.x += runFont.capHeight - runFont.pointSize
            offset.y += (runFont.capHeight - runFont.pointSize) * (superscript == 0 ? 0.25 : (superscript == 1 ? 0.5 / 0.55 : 0.0))
          }
          var glyphOrigin: NSPoint = textContainer.textView!.convertToBacking(NSMakePoint(position.x + offset.x, position.y + offset.y))
          glyphOrigin = textContainer.textView!.convertFromBacking(NSMakePoint(round(glyphOrigin.x), round(glyphOrigin.y)))
          super.drawGlyphs(forGlyphRange: runGlyphRange, at: NSMakePoint(glyphOrigin.x - position.x, glyphOrigin.y - position.y))
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
    let rulerAttrs: NSParagraphStyle! = layoutManager.textStorage!.attribute(.paragraphStyle, at: charRange.location, effectiveRange: nil) as? NSParagraphStyle
    let lineSpacing: Double = rulerAttrs.lineSpacing
    let lineHeight: Double = rulerAttrs.minimumLineHeight
    var baseline: Double = lineHeight * 0.5
    if (!verticalOrientation) {
      let refFont: NSFont = (layoutManager.textStorage!.attribute(kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key, at: charRange.location, effectiveRange: nil) as! Dictionary<CFString, Any>)[kCTBaselineReferenceFont] as! NSFont
      baseline += refFont.ascender * 0.5 + refFont.descender * 0.5
    }
    let lineHeightDelta: Double = lineFragmentUsedRect.pointee.size.height - lineHeight - lineSpacing
    if (abs(lineHeightDelta) > 0.1) {
      lineFragmentUsedRect.pointee.size.height = round(lineFragmentUsedRect.pointee.size.height - lineHeightDelta)
      lineFragmentRect.pointee.size.height = round(lineFragmentRect.pointee.size.height - lineHeightDelta)
      didModify = true
    }
    // move half of the linespacing above the line fragment
    if (lineSpacing > 0.1) {
      baseline += lineSpacing * 0.5
    }
    let newBaselineOffset: Double = floor(lineFragmentUsedRect.pointee.origin.y - lineFragmentRect.pointee.origin.y + baseline)
    if (abs(baselineOffset.pointee - newBaselineOffset) > 0.1) {
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
      let alignment: NSTextAlignment = (layoutManager.textStorage!.attribute(.paragraphStyle, at: charIndex, effectiveRange: nil) as! NSParagraphStyle).alignment
      if (alignment == .natural) { // candidates in linear layout
        return charBeforeIndex == 0x1D
      } else {
        return charBeforeIndex != 0x9
      }
    }
  }

  func layoutManager(_ layoutManager: NSLayoutManager,
                     shouldUse action: NSLayoutManager.ControlCharacterAction,
                     forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
    if (charIndex > 0 && layoutManager.textStorage!.mutableString.character(at: charIndex) == 0x8B && layoutManager.textStorage!.attribute(kCTRubyAnnotationAttributeName as NSAttributedString.Key, at: charIndex - 1, effectiveRange: nil) != nil) {
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
        let rubyString: NSAttributedString = layoutManager.textStorage!.attributedSubstring(from: rubyRange)
        let line: CTLine = CTLineCreateWithAttributedString(rubyString as CFAttributedString)
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

  private var _topMargin: CGFloat = 0.0
  override var topMargin: CGFloat {
    get { return _topMargin }
    set(newValue) { _topMargin = newValue }
  }

  override func draw(at point: CGPoint,
                     in context:CGContext) {
    var origin: CGPoint = point
    if #available(macOS 14.0, *) {
    } else { // in macOS 12 and 13, textLineFragments.typographicBouonds are in textContainer coordinates
      origin.x -= self.layoutFragmentFrame.origin.x
      origin.y -= self.layoutFragmentFrame.origin.y
    }
    let verticalOrientation: Boolean = textLayoutManager!.textContainer!.layoutOrientation == .vertical
    for lineFrag in textLineFragments {
      let lineRect: CGRect = CGRectOffset(lineFrag.typographicBounds, origin.x, origin.y)
      let lineSpacing: Double = (lineFrag.attributedString.attribute(.paragraphStyle, at: lineFrag.characterRange.location, effectiveRange: nil) as! NSParagraphStyle).lineSpacing
      var baseline: Double = CGRectGetMidY(lineRect) - lineSpacing * 0.5
      if (!verticalOrientation) {
        let refFont: NSFont = (lineFrag.attributedString.attribute(kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key, at: lineFrag.characterRange.location, effectiveRange: nil) as! Dictionary<CFString, Any>)[kCTBaselineReferenceFont] as! NSFont
        baseline += refFont.ascender * 0.5 + refFont.descender * 0.5
      }
      var renderOrigin: CGPoint = CGPointMake(NSMinX(lineRect) + lineFrag.glyphOrigin.x,
                                              ceil(baseline) - lineFrag.glyphOrigin.y)
      let deviceOrigin: CGPoint = context.convertToDeviceSpace(renderOrigin)
      renderOrigin = context.convertToUserSpace(CGPointMake(round(deviceOrigin.x), round(deviceOrigin.y)))
      lineFrag.draw(at: renderOrigin, in:context)
    }
  }

}  // SquirrelTextLayoutFragment


@available(macOS 12.0, *)
class SquirrelTextLayoutManager: NSTextLayoutManager, NSTextLayoutManagerDelegate {

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                         shouldBreakLineBefore location: any NSTextLocation,
                         hyphenating: Boolean) -> Boolean {
    let contentStorage: NSTextContentStorage! = textLayoutManager.textContainer!.textView?.textContentStorage
    let charIndex: Int = contentStorage.offset(from: contentStorage.documentRange.location, to: location)
    if (charIndex <= 1) {
      return true
    } else {
      let charBeforeIndex: unichar = contentStorage.textStorage!.mutableString.character(at: charIndex - 1)
      let alignment: NSTextAlignment = (contentStorage.textStorage!.attribute(.paragraphStyle, at: charIndex, effectiveRange: nil) as! NSParagraphStyle).alignment
      if (alignment == .natural) { // candidates in linear layout
        return charBeforeIndex == 0x1D
      } else {
        return charBeforeIndex != 0x9
      }
    }
  }

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                         textLayoutFragmentFor location: any NSTextLocation,
                         in textElement: NSTextElement) -> NSTextLayoutFragment {
    let textRange: NSTextRange! = NSTextRange(location: location, end: textElement.elementRange?.endLocation)
    let fragment: SquirrelTextLayoutFragment = SquirrelTextLayoutFragment(textElement: textElement, range: textRange)
    if let textStorage = textLayoutManager.textContainer?.textView?.textContentStorage?.textStorage {
      if (textStorage.length > 0 && location.isEqual(self.documentRange.location)) {
        fragment.topMargin = (textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).lineSpacing
      }
    }
    return fragment
  }

}  // SquirrelTextLayoutManager

// MARK: - View behind text, containing drawings of backgrounds and highlights

typealias SquirrelTabularIndex = (index: Int, lineNum: Int, tabNum: Int)
typealias SquirrelTextPolygon = (leading: NSRect, body: NSRect, trailing: NSRect)

struct SquirrelCandidateRanges {
  var location: Int = 0
  var length: Int = 0
  var text: Int = 0
  var comment: Int = 0

  func NSRange() -> NSRange {
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

// Bezier cubic curve, which has continuous roundness
fileprivate func squirclePath(vertices: [NSPoint],
                              radius: Double) -> NSBezierPath? {
  if (vertices.isEmpty) {
    return nil
  }
  let path: NSBezierPath! = NSBezierPath()
  var point: NSPoint = vertices.last!
  var nextPoint: NSPoint = vertices.first!
  var startPoint: NSPoint
  var endPoint: NSPoint
  var controlPoint1: NSPoint
  var controlPoint2: NSPoint
  var arcRadius: CGFloat
  var nextDiff: CGVector = CGVectorMake(nextPoint.x - point.x, nextPoint.y - point.y)
  var lastDiff: CGVector
  if (abs(nextDiff.dx) >= abs(nextDiff.dy)) {
    endPoint = NSMakePoint(point.x + nextDiff.dx * 0.5, nextPoint.y)
  } else {
    endPoint = NSMakePoint(nextPoint.x, point.y + nextDiff.dy * 0.5)
  }
  path.move(to: endPoint)
  for i in 0..<vertices.count {
    lastDiff = nextDiff
    point = nextPoint
    nextPoint = vertices[(i + 1) % vertices.count]
    nextDiff = CGVectorMake(nextPoint.x - point.x, nextPoint.y - point.y)
    if (abs(nextDiff.dx) >= abs(nextDiff.dy)) {
      arcRadius = min(radius, min(abs(nextDiff.dx), abs(lastDiff.dy)) * 0.5)
      point.y = nextPoint.y
      startPoint = NSMakePoint(point.x, point.y - copysign(arcRadius, lastDiff.dy))
      controlPoint1 = NSMakePoint(point.x, point.y - copysign(arcRadius * 0.3, lastDiff.dy))
      endPoint = NSMakePoint(point.x + copysign(arcRadius, nextDiff.dx), nextPoint.y)
      controlPoint2 = NSMakePoint(point.x + copysign(arcRadius * 0.3, nextDiff.dx), nextPoint.y)
    } else {
      arcRadius = min(radius, min(abs(nextDiff.dy), abs(lastDiff.dx)) * 0.5)
      point.x = nextPoint.x
      startPoint = NSMakePoint(point.x - copysign(arcRadius, lastDiff.dx), point.y)
      controlPoint1 = NSMakePoint(point.x - copysign(arcRadius * 0.3, lastDiff.dx), point.y)
      endPoint = NSMakePoint(nextPoint.x, point.y + copysign(arcRadius, nextDiff.dy))
      controlPoint2 = NSMakePoint(nextPoint.x, point.y + copysign(arcRadius * 0.3, nextDiff.dy))
    }
    path.line(to: startPoint)
    path.curve(to: endPoint, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
  }
  path.close()
  return path
}

fileprivate func rectVertices(_ rect: NSRect) -> [NSPoint] {
  return [rect.origin,
          NSMakePoint(NSMinX(rect), NSMaxY(rect)),
          NSMakePoint(NSMaxX(rect), NSMaxY(rect)),
          NSMakePoint(NSMaxX(rect), NSMinY(rect))]
}

fileprivate func textPolygonVertices(_ textPolygon: SquirrelTextPolygon) -> [NSPoint] {
  switch (((NSIsEmptyRect(textPolygon.leading) ? 1 : 0) << 2) +
          ((NSIsEmptyRect(textPolygon.body) ? 1 : 0) << 1) +
          ((NSIsEmptyRect(textPolygon.trailing) ? 1 : 0) << 0)) {
  case 0b011:
    return rectVertices(textPolygon.leading)
  case 0b110:
    return rectVertices(textPolygon.trailing)
  case 0b101:
    return rectVertices(textPolygon.body)
  case 0b001:
    let leadingVertices: [NSPoint] = rectVertices(textPolygon.leading)
    let bodyVertices: [NSPoint] = rectVertices(textPolygon.body)
    return [leadingVertices[0], leadingVertices[1],
            bodyVertices[0], bodyVertices[1],
            bodyVertices[2], leadingVertices[3]]
  case 0b100:
    let bodyVertices: [NSPoint] = rectVertices(textPolygon.body)
    let trailingVertices: [NSPoint] = rectVertices(textPolygon.trailing)
    return [bodyVertices[0], trailingVertices[1],
            trailingVertices[2], trailingVertices[3],
            bodyVertices[2], bodyVertices[3]]
  case 0b010:
    if (NSMinX(textPolygon.leading) <= NSMaxX(textPolygon.trailing)) {
      let leadingVertices: [NSPoint] = rectVertices(textPolygon.leading)
      let trailingVertices: [NSPoint] = rectVertices(textPolygon.trailing)
      return [leadingVertices[0], leadingVertices[1],
              trailingVertices[0], trailingVertices[1],
              trailingVertices[2], trailingVertices[3],
              leadingVertices[2], leadingVertices[3]]
    } else {
      return []
    }
  case 0b000:
    let leadingVertices: [NSPoint] = rectVertices(textPolygon.leading)
    let bodyVertices: [NSPoint] = rectVertices(textPolygon.body)
    let trailingVertices: [NSPoint] = rectVertices(textPolygon.trailing)
    return [leadingVertices[0], leadingVertices[1],
            bodyVertices[0], trailingVertices[1],
            trailingVertices[2], trailingVertices[3],
            bodyVertices[2], leadingVertices[3]]
  default:
    return []
  }
}

class SquirrelView: NSView {
  // Need flipped coordinate system, as required by textStorage
  static var defaultTheme: SquirrelTheme = SquirrelTheme()
  @available(macOS 10.14, *) static var darkTheme : SquirrelTheme = SquirrelTheme()
  private var _currentTheme: SquirrelTheme
  var currentTheme: SquirrelTheme { get { return _currentTheme } }
  private var _textView: NSTextView
  var textView: NSTextView { get { return _textView } }
  private var _textStorage: NSTextStorage
  var textStorage: NSTextStorage { get { return _textStorage } }
  private var _shape: CAShapeLayer
  var shape: CAShapeLayer { get { return _shape } }
  private var _tabularIndices: [SquirrelTabularIndex] = []
  var tabularIndices: [SquirrelTabularIndex] { get { return _tabularIndices } }
  private var _candidatePolygons: [SquirrelTextPolygon] = []
  var candidatePolygons: [SquirrelTextPolygon] { get { return _candidatePolygons } }
  private var _sectionRects: [NSRect] = []
  var sectionRects: [NSRect] { get { return _sectionRects } }
  private var _contentRect: NSRect = NSZeroRect
  var contentRect: NSRect { get { return _contentRect } }
  private var _preeditBlock: NSRect = NSZeroRect
  var preeditBlock: NSRect { get { return _preeditBlock } }
  private var _candidateBlock: NSRect = NSZeroRect
  var candidateBlock: NSRect { get { return _candidateBlock } }
  private var _pagingBlock: NSRect = NSZeroRect
  var pagingBlock: NSRect { get { return _pagingBlock } }
  private var _deleteBackRect: NSRect = NSZeroRect
  var deleteBackRect: NSRect { get { return _deleteBackRect } }
  private var _expanderRect: NSRect = NSZeroRect
  var expanderRect: NSRect { get { return _expanderRect } }
  private var _pageUpRect: NSRect = NSZeroRect
  var pageUpRect: NSRect { get { return _pageUpRect } }
  private var _pageDownRect: NSRect = NSZeroRect
  var pageDownRect: NSRect { get { return _pageDownRect } }
  private var _appear: SquirrelAppear
  var appear: SquirrelAppear {
    get { return _appear }
    set(newValue) {
      if #available(macOS 10.14, *) {
        if (_appear != newValue) {
          _appear = newValue
          _currentTheme = newValue == .darkAppear ? SquirrelView.darkTheme : SquirrelView.defaultTheme
        }
      }
    }
  }
  private var _functionButton: SquirrelIndex = .kVoidSymbol
  var functionButton: SquirrelIndex { get { return _functionButton } }
  private var _marginInsets: NSEdgeInsets = NSEdgeInsetsZero
  var marginInsets: NSEdgeInsets { get { return _marginInsets } }
  private var _numCandidates: Int = 0
  var numCandidates: Int { get { return _numCandidates } }
  private var _hilitedIndex: Int = NSNotFound
  var hilitedIndex: Int { get { return _hilitedIndex } }
  private var _preeditRange: NSRange = NSMakeRange(NSNotFound, 0)
  var preeditRange: NSRange { get { return _preeditRange } }
  private var _hilitedPreeditRange: NSRange = NSMakeRange(NSNotFound, 0)
  var hilitedPreeditRange: NSRange { get { return _hilitedPreeditRange } }
  private var _pagingRange: NSRange = NSMakeRange(NSNotFound, 0)
  var pagingRange: NSRange { get { return _pagingRange } }
  private var _trailPadding: Double = 0.0
  var trailPadding: Double { get { return _trailPadding } }
  private var _candidateRanges: [SquirrelCandidateRanges] = []
  var candidateRanges: [SquirrelCandidateRanges] { get { return _candidateRanges } }
  private var _truncated: [Boolean] = []
  var truncated: [Boolean] { get { return _truncated } }
  private var _expanded: Boolean = false
  var expanded: Boolean {
    get { return _expanded }
    set(newValue) {
      _expanded = newValue
    }
  }
  override var isFlipped: Boolean {
    get { return true }
  }
  override var wantsUpdateLayer: Boolean {
    get { return true }
  }

  override init(frame frameRect: NSRect) {
    if #available(macOS 12.0, *) {
      let textLayoutManager: SquirrelTextLayoutManager! = SquirrelTextLayoutManager()
      textLayoutManager.usesFontLeading = false
      textLayoutManager.usesHyphenation = false
      textLayoutManager.delegate = textLayoutManager
      let textContainer: NSTextContainer! = NSTextContainer(size: NSZeroSize)
      textContainer.lineFragmentPadding = 0
      textLayoutManager.textContainer = textContainer
      let contentStorage: NSTextContentStorage! = NSTextContentStorage()
      _textStorage = contentStorage.textStorage!
      contentStorage.addTextLayoutManager(textLayoutManager)
      _textView = NSTextView(frame: frameRect, textContainer: textContainer)
    } else {
      let layoutManager: SquirrelLayoutManager! = SquirrelLayoutManager()
      layoutManager.backgroundLayoutEnabled = true
      layoutManager.usesFontLeading = false
      layoutManager.typesetterBehavior = .latestBehavior
      layoutManager.delegate = layoutManager
      let textContainer: NSTextContainer! = NSTextContainer(containerSize: NSZeroSize)
      textContainer.lineFragmentPadding = 0
      layoutManager.addTextContainer(textContainer)
      _textStorage = NSTextStorage()
      _textStorage.addLayoutManager(layoutManager)
      _textView = NSTextView(frame: frameRect, textContainer: textContainer)
    }
    _textView.drawsBackground = false
    _textView.isSelectable = false
    _textView.wantsLayer = true

    _appear = .defaultAppear
    _currentTheme = SquirrelView.defaultTheme
    _shape = CAShapeLayer()

    super.init(frame: frameRect)
    wantsLayer = true
    layer!.isGeometryFlipped = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  @available(macOS 12.0, *)
  private func getTextRange(fromCharRange charRange: NSRange) -> NSTextRange? {
    if (charRange.location == NSNotFound) {
      return nil
    } else {
      let contentStorage: NSTextContentStorage! = textView.textContentStorage
      let start: NSTextLocation! = contentStorage.location(contentStorage.documentRange.location,
                                                           offsetBy: charRange.location)
      let end: NSTextLocation! = contentStorage.location(start, offsetBy: charRange.length)
      return NSTextRange(location: start, end: end)
    }
  }

  @available(macOS 12.0, *)
  private func getCharRange(fromTextRange textRange: NSTextRange?) -> NSRange {
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

  // Get the rectangle containing entire contents, expensive to calculate
  private func layoutContents() {
    if #available(macOS 12.0, *) {
      _textView.textLayoutManager!.ensureLayout(for: _textView.textContentStorage!.documentRange)
      _contentRect = _textView.textLayoutManager!.usageBoundsForTextContainer
    } else {
      _textView.layoutManager!.ensureLayout(for: _textView.textContainer!)
      _contentRect = _textView.layoutManager!.usedRect(for: _textView.textContainer!)
    }
    _contentRect.size = NSMakeSize(ceil(NSWidth(_contentRect)),
                                   ceil(NSHeight(_contentRect)))
  }

  // Get the rectangle containing the range of text, will first convert to glyph or text range, expensive to calculate
  fileprivate func blockRect(forRange charRange: NSRange) -> NSRect {
    if (charRange.location == NSNotFound) {
      return NSZeroRect
    }
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange! = getTextRange(fromCharRange: charRange)
      var firstLineRect: NSRect = CGRectNull
      var finalLineRect: NSRect = CGRectNull
      _textView.textLayoutManager!.enumerateTextSegments(
        in: textRange,
        type: .standard,
        options: [.rangeNotRequired, .middleFragmentsExcluded],
        using: { (segRange: NSTextRange?, segFrame: CGRect, baseline: CGFloat, textContainer: NSTextContainer) in
          if (!CGRectIsEmpty(segFrame)) {
            if (NSIsEmptyRect(firstLineRect) || CGRectGetMinY(segFrame) < NSMaxY(firstLineRect)) {
              firstLineRect = NSUnionRect(segFrame, firstLineRect)
            } else {
              finalLineRect = NSUnionRect(segFrame, finalLineRect)
            }
          }
          return true
      })
      if (_currentTheme.linear && _currentTheme.linespace > 0.1 && _numCandidates > 0) {
        if (charRange.location >= candidateRanges[0].location &&
            charRange.location < candidateRanges[_numCandidates - 1].maxRange()) {
          firstLineRect.size.height += _currentTheme.linespace
          firstLineRect.origin.y -= _currentTheme.linespace
        }
        if (!NSIsEmptyRect(finalLineRect) && NSMaxRange(charRange) > candidateRanges[0].location &&
            NSMaxRange(charRange) <= candidateRanges[_numCandidates - 1].maxRange()) {
          finalLineRect.size.height += _currentTheme.linespace
          finalLineRect.origin.y -= _currentTheme.linespace
        }
      }
      if (NSIsEmptyRect(finalLineRect)) {
        return firstLineRect
      } else {
        return NSMakeRect(NSMinX(_contentRect),
                          NSMinY(firstLineRect),
                          NSWidth(_contentRect) - _trailPadding,
                          NSMaxY(finalLineRect) - NSMinY(firstLineRect))
      }
    } else {
      let layoutManager: NSLayoutManager! = _textView.layoutManager
      let glyphRange: NSRange = layoutManager.glyphRange(forCharacterRange: charRange,
                                                         actualCharacterRange: nil)
      var firstLineRange: NSRange = NSMakeRange(NSNotFound, 0)
      let firstLineRect: NSRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location,
                                                                     effectiveRange: &firstLineRange)
      if (NSMaxRange(glyphRange) <= NSMaxRange(firstLineRange)) {
        let headX: CGFloat = layoutManager.location(forGlyphAt: glyphRange.location).x
        let tailX: CGFloat = NSMaxRange(glyphRange) < NSMaxRange(firstLineRange)
        ? layoutManager.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(firstLineRect)
        return NSMakeRect(NSMinX(firstLineRect) + headX, NSMinY(firstLineRect),
                          tailX - headX, NSHeight(firstLineRect))
      } else {
        let finalLineRect: NSRect = layoutManager.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphRange) - 1,
                                                                       effectiveRange: nil)
        return NSMakeRect(NSMinX(firstLineRect),
                          NSMinY(firstLineRect),
                          NSWidth(_contentRect) - _trailPadding,
                          NSMaxY(finalLineRect) - NSMinY(firstLineRect))
      }
    }
  }

  // Calculate 3 boxes containing the text in range. leadingRect and trailingRect are incomplete line rectangle
  // bodyRect is the complete line fragment in the middle if the range spans no less than one full line
  private func textPolygon(forRange charRange: NSRange) -> SquirrelTextPolygon {
    var textPolygon: SquirrelTextPolygon = SquirrelTextPolygon(
      leading: NSZeroRect, body: NSZeroRect, trailing: NSZeroRect)
    if (charRange.location == NSNotFound) {
      return textPolygon
    }
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange! = getTextRange(fromCharRange: charRange)
      var leadingLineRect: NSRect = CGRectNull
      var trailingLineRect: NSRect = CGRectNull
      var leadingLineRange: NSTextRange?
      var trailingLineRange: NSTextRange?
      _textView.textLayoutManager!.enumerateTextSegments(
        in: textRange,
        type: .standard,
        options: .middleFragmentsExcluded,
        using: { (segRange: NSTextRange?, segFrame: CGRect, baseline: CGFloat, textContainer: NSTextContainer) in
        if (!CGRectIsEmpty(segFrame)) {
          if (NSIsEmptyRect(leadingLineRect) || CGRectGetMinY(segFrame) < NSMaxY(leadingLineRect)) {
            leadingLineRect = NSUnionRect(segFrame, leadingLineRect)
            leadingLineRange = leadingLineRange == nil ? segRange! : segRange!.union(leadingLineRange!)
          } else {
            trailingLineRect = NSUnionRect(segFrame, trailingLineRect)
            trailingLineRange = trailingLineRange == nil ? segRange! : segRange!.union(trailingLineRange!)
          }
        }
        return true
      })
      if (_currentTheme.linear && _currentTheme.linespace > 0.1 && _numCandidates > 0) {
        if (charRange.location >= candidateRanges[0].location &&
            charRange.location < candidateRanges[_numCandidates - 1].maxRange()) {
          leadingLineRect.size.height += _currentTheme.linespace
          leadingLineRect.origin.y -= _currentTheme.linespace
        }
      }

      if (NSIsEmptyRect(trailingLineRect)) {
        textPolygon.body = leadingLineRect
      } else {
        if (_currentTheme.linear && _currentTheme.linespace > 0.1 && _numCandidates > 0) {
          if (NSMaxRange(charRange) > candidateRanges[0].location &&
              NSMaxRange(charRange) <= candidateRanges[_numCandidates - 1].maxRange()) {
            trailingLineRect.size.height += _currentTheme.linespace
            trailingLineRect.origin.y -= _currentTheme.linespace
          }
        }

        let containerWidth: Double = NSMaxX(_contentRect) - _trailPadding
        leadingLineRect.size.width = containerWidth - NSMinX(leadingLineRect)
        if (abs(NSMaxX(trailingLineRect) - NSMaxX(leadingLineRect)) < 1) {
          if (abs(NSMinX(leadingLineRect) - NSMinX(trailingLineRect)) < 1) {
            textPolygon.body = NSUnionRect(leadingLineRect, trailingLineRect)
          } else {
            textPolygon.leading = leadingLineRect
            textPolygon.body = NSMakeRect(0.0, NSMaxY(leadingLineRect), containerWidth,
                                              NSMaxY(trailingLineRect) - NSMaxY(leadingLineRect))
          }
        } else {
          textPolygon.trailing = trailingLineRect
          if (abs(NSMinX(leadingLineRect) - NSMinX(trailingLineRect)) < 1) {
            textPolygon.body = NSMakeRect(0.0, NSMinY(leadingLineRect), containerWidth,
                                              NSMinY(trailingLineRect) - NSMinY(leadingLineRect))
          } else {
            textPolygon.leading = leadingLineRect
            if (!trailingLineRange!.contains(leadingLineRange!.endLocation)) {
              textPolygon.body = NSMakeRect(0.0, NSMaxY(leadingLineRect), containerWidth,
                                                NSMinY(trailingLineRect) - NSMaxY(leadingLineRect))
            }
          }
        }
      }
    } else {
      let layoutManager: NSLayoutManager! = textView.layoutManager
      let glyphRange: NSRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      var leadingLineRange: NSRange = NSMakeRange(NSNotFound, 0)
      let leadingLineRect: NSRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &leadingLineRange)
      let headX: Double = layoutManager.location(forGlyphAt: glyphRange.location).x
      if (NSMaxRange(leadingLineRange) >= NSMaxRange(glyphRange)) {
        let tailX: Double = NSMaxRange(glyphRange) < NSMaxRange(leadingLineRange)
        ? layoutManager.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(leadingLineRect)
        textPolygon.body = NSMakeRect(headX, NSMinY(leadingLineRect), tailX - headX, NSHeight(leadingLineRect))
      } else {
        let containerWidth: Double = NSWidth(_contentRect)
        var trailingLineRange: NSRange = NSMakeRange(NSNotFound, 0)
        let trailingLineRect: NSRect = layoutManager.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphRange) - 1,
                                                                          effectiveRange:&trailingLineRange)
        let tailX: Double = NSMaxRange(glyphRange) < NSMaxRange(trailingLineRange)
        ? layoutManager.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(trailingLineRect)
        if (NSMaxRange(trailingLineRange) == NSMaxRange(glyphRange)) {
          if (glyphRange.location == leadingLineRange.location) {
            textPolygon.body = NSMakeRect(0.0, NSMinY(leadingLineRect), containerWidth,
                                              NSMaxY(trailingLineRect) - NSMinY(leadingLineRect))
          } else {
            textPolygon.leading = NSMakeRect(headX, NSMinY(leadingLineRect),
                                                 containerWidth - headX, NSHeight(leadingLineRect))
            textPolygon.body = NSMakeRect(0.0, NSMaxY(leadingLineRect), containerWidth,
                                              NSMaxY(trailingLineRect) - NSMaxY(leadingLineRect))
          }
        } else {
          textPolygon.trailing = NSMakeRect(0.0, NSMinY(trailingLineRect),
                                                tailX, NSHeight(trailingLineRect))
          if (glyphRange.location == leadingLineRange.location) {
            textPolygon.body = NSMakeRect(0.0, NSMinY(leadingLineRect), containerWidth,
                                              NSMinY(trailingLineRect) - NSMinY(leadingLineRect))
          } else {
            textPolygon.leading = NSMakeRect(headX, NSMinY(leadingLineRect),
                                                 containerWidth - headX, NSHeight(leadingLineRect))
            if (trailingLineRange.location > NSMaxRange(leadingLineRange)) {
              textPolygon.body = NSMakeRect(0.0, NSMaxY(leadingLineRect), containerWidth,
                                                NSMinY(trailingLineRect) - NSMaxY(leadingLineRect))
            }
          }
        }
      }
    }
    return textPolygon
  }

  fileprivate func estimateBounds(forPreedit preeditRange: NSRange,
                                  candidates candidateRanges : [SquirrelCandidateRanges],
                                  truncation truncated: [Boolean],
                                  paging pagingRange: NSRange) {
    _preeditRange = preeditRange
    _candidateRanges = candidateRanges
    _truncated = truncated
    _pagingRange = pagingRange
    layoutContents()
    if (_currentTheme.linear && (candidateRanges.count > 0 || preeditRange.length > 0)) {
      var width: Double = 0.0
      if (preeditRange.length > 0) {
        width = ceil(NSMaxX(blockRect(forRange: preeditRange)))
      }
      if (candidateRanges.count > 0) {
        var isTruncated = truncated[0]
        var start: Int = candidateRanges[0].location
        for i in 1..<candidateRanges.count {
          if (i == candidateRanges.count || truncated[i] != isTruncated) {
            let candidateRect: NSRect = blockRect(forRange: NSMakeRange(start, candidateRanges[i - 1].maxRange() - start))
            width = max(width, ceil(NSMaxX(candidateRect)) - (isTruncated ? 0.0 : _currentTheme.fullWidth))
            if (i < candidateRanges.count) {
              isTruncated = truncated[i]
              start = candidateRanges[i].location
            }
          }
        }
      }
      if (pagingRange.length > 0) {
        width = max(width, ceil(NSMaxX(blockRect(forRange: pagingRange))))
      }
      _trailPadding = max(NSMaxX(_contentRect) - width, 0.0)
    } else {
      _trailPadding = 0.0
    }
  }

  // Will triger - (void)updateLayer
  fileprivate func drawView(withInsets marginInsets: NSEdgeInsets,
                            hilitedIndex: Int,
                            hilitedPreeditRange: NSRange) {
    _marginInsets = marginInsets
    _hilitedIndex = hilitedIndex
    _hilitedPreeditRange = hilitedPreeditRange
    _functionButton = .kVoidSymbol
    // invalidate Rect beyond bound of textview to clear any out-of-bound drawing from last round
    setNeedsDisplay(self.bounds)
    _textView.setNeedsDisplay(convert(self.bounds, to: _textView))
    layoutContents()
  }

  fileprivate func setPreeditRange(_ preeditRange: NSRange,
                                   hilitedPreeditRange: NSRange) {
    if (_preeditRange.length != preeditRange.length) {
      for i in 0..<_numCandidates {
        _candidateRanges[i].location += preeditRange.length - _preeditRange.length
      }
      if (_pagingRange.location != NSNotFound) {
        _pagingRange.location += preeditRange.length - _preeditRange.length
      }
    }
    _preeditRange = preeditRange
    _hilitedPreeditRange = hilitedPreeditRange
    setNeedsDisplay(_preeditBlock)
    _textView.setNeedsDisplay(convert(_preeditBlock, to: _textView))
    layoutContents()
  }

  fileprivate func highlightCandidate(_ hilitedIndex: Int) {
    if (expanded) {
      let priorActivePage: Int = _hilitedIndex / _currentTheme.pageSize
      let newActivePage: Int = hilitedIndex / _currentTheme.pageSize
      if (newActivePage != priorActivePage) {
        setNeedsDisplay(_sectionRects[priorActivePage])
        _textView.setNeedsDisplay(convert(_sectionRects[priorActivePage], to: _textView))
      }
      setNeedsDisplay(_sectionRects[newActivePage])
      _textView.setNeedsDisplay(convert(_sectionRects[newActivePage], to: _textView))
    } else {
      setNeedsDisplay(_candidateBlock)
      _textView.setNeedsDisplay(convert(_candidateBlock, to: _textView))
    }
    _hilitedIndex = hilitedIndex
  }

  fileprivate func highlightFunctionButton(_ functionButton: SquirrelIndex) {
    for funcBttn in [_functionButton, functionButton] {
      switch (funcBttn) {
      case .kPageUpKey, .kHomeKey:
        setNeedsDisplay(_pageUpRect)
        _textView.setNeedsDisplay(convert(_pageUpRect, to: _textView))
        break
      case .kPageDownKey, .kEndKey:
        setNeedsDisplay(_pageDownRect)
        _textView.setNeedsDisplay(convert(_pageDownRect, to: _textView))
        break
      case .kBackSpaceKey, .kEscapeKey:
        setNeedsDisplay(_deleteBackRect)
        _textView.setNeedsDisplay(convert(_deleteBackRect, to: _textView))
        break
      case .kExpandButton, .kCompressButton, .kLockButton:
        setNeedsDisplay(_expanderRect)
        _textView.setNeedsDisplay(convert(_expanderRect, to: _textView))
        break
      default:
        break
      }
    }
    _functionButton = functionButton
  }

  private func getFunctionButtonLayer() -> CAShapeLayer? {
    var buttonColor: NSColor!
    var buttonRect: NSRect = NSZeroRect
    switch (functionButton) {
    case .kPageUpKey:
      buttonColor = _currentTheme.hilitedPreeditBackColor?.hooverColor
      buttonRect = _pageUpRect
      break
    case .kHomeKey:
      buttonColor = _currentTheme.hilitedPreeditBackColor?.disabledColor
      buttonRect = _pageUpRect
      break
    case .kPageDownKey:
      buttonColor = _currentTheme.hilitedPreeditBackColor?.hooverColor
      buttonRect = _pageDownRect
      break
    case .kEndKey:
      buttonColor = _currentTheme.hilitedPreeditBackColor?.disabledColor
      buttonRect = _pageDownRect
      break
    case .kExpandButton, .kCompressButton, .kLockButton:
      buttonColor = _currentTheme.hilitedPreeditBackColor?.hooverColor
      buttonRect = _expanderRect
      break
    case .kBackSpaceKey:
      buttonColor = _currentTheme.hilitedPreeditBackColor?.hooverColor
      buttonRect = _deleteBackRect
      break
    case .kEscapeKey:
      buttonColor = _currentTheme.hilitedPreeditBackColor?.disabledColor
      buttonRect = _deleteBackRect
      break
    default:
      return nil
    }
    if (!NSIsEmptyRect(buttonRect) && (buttonColor != nil)) {
      let cornerRadius: Double = min(_currentTheme.hilitedCornerRadius, NSHeight(buttonRect) * 0.5)
      let buttonPath: NSBezierPath! = squirclePath(vertices: rectVertices(buttonRect), radius: cornerRadius)
      let functionButtonLayer: CAShapeLayer = CAShapeLayer()
      functionButtonLayer.path = buttonPath.quartzPath
      functionButtonLayer.fillColor = buttonColor.cgColor
      return functionButtonLayer
    }
    return nil
  }

  // All draws happen here
  override func updateLayer() {
    let panelRect: NSRect = bounds
    let backgroundRect: NSRect = backingAlignedRect(NSInsetRect(panelRect,
                                                                _currentTheme.borderInsets.width,
                                                                _currentTheme.borderInsets.height),
                                                    options: .alignAllEdgesNearest)

    var visibleRange: NSRange
    if #available(macOS 12.0, *) {
      visibleRange = getCharRange(fromTextRange: _textView.textLayoutManager!.textViewportLayoutController.viewportRange)
    } else {
      var containerGlyphRange: NSRange = NSMakeRange(NSNotFound, 0)
      _ = _textView.layoutManager!.textContainer(forGlyphAt: 0, effectiveRange: &containerGlyphRange)
      visibleRange = _textView.layoutManager!.characterRange(forGlyphRange: containerGlyphRange, actualGlyphRange: nil)
    }
    let preeditRange: NSRange = NSIntersectionRange(_preeditRange, visibleRange)
    var candidateBlockRange: NSRange
    if (_numCandidates > 0) {
      candidateBlockRange = NSMakeRange(candidateRanges[0].location,
                                        candidateRanges[_numCandidates - 1].maxRange() - candidateRanges[0].location)
      candidateBlockRange = NSIntersectionRange(candidateBlockRange, visibleRange)
    } else {
      candidateBlockRange = NSMakeRange(NSNotFound, 0)
    }
    let pagingRange: NSRange = NSIntersectionRange(_pagingRange, visibleRange)

    // Draw preedit Rect
    _preeditBlock = NSZeroRect
    _deleteBackRect = NSZeroRect
    var hilitedPreeditPath: NSBezierPath?
    if (preeditRange.length > 0) {
      var innerBox: NSRect = blockRect(forRange: preeditRange)
      _preeditBlock = NSMakeRect(backgroundRect.origin.x,
                                 backgroundRect.origin.y,
                                 backgroundRect.size.width,
                                 innerBox.size.height + (candidateBlockRange.length > 0 ? _currentTheme.preeditLinespace : 0.0))
      _preeditBlock = backingAlignedRect(preeditBlock, options: .alignAllEdgesNearest)

      // Draw highlighted part of preedit text
      let hilitedPreeditRange: NSRange = NSIntersectionRange(_hilitedPreeditRange, visibleRange)
      let cornerRadius: Double = min(_currentTheme.hilitedCornerRadius,
                                     _currentTheme.preeditParagraphStyle.minimumLineHeight * 0.5)
      if (hilitedPreeditRange.length > 0 && (_currentTheme.hilitedPreeditBackColor != nil)) {
        let padding: Double = ceil(_currentTheme.preeditParagraphStyle.minimumLineHeight * 0.05)
        innerBox.origin.x += _marginInsets.left - padding
        innerBox.size.width = backgroundRect.size.width - _currentTheme.fullWidth + padding * 2
        innerBox.origin.y += _marginInsets.top
        innerBox = backingAlignedRect(innerBox, options: .alignAllEdgesNearest)
        var textPolygon: SquirrelTextPolygon = textPolygon(forRange: hilitedPreeditRange)
        if (!NSIsEmptyRect(textPolygon.leading)) {
          textPolygon.leading.origin.x += _marginInsets.left - padding
          textPolygon.leading.origin.y += _marginInsets.top
          textPolygon.leading.size.width += padding * 2
          textPolygon.leading = backingAlignedRect(NSIntersectionRect(textPolygon.leading, innerBox), options: .alignAllEdgesNearest)
        }
        if (!NSIsEmptyRect(textPolygon.body)) {
          textPolygon.body.origin.x += _marginInsets.left - padding
          textPolygon.body.origin.y += _marginInsets.top
          textPolygon.body.size.width += padding
          if (!NSIsEmptyRect(textPolygon.trailing) || NSMaxRange(hilitedPreeditRange) + 2 == NSMaxRange(preeditRange)) {
            textPolygon.body.size.width += padding
          }
          textPolygon.body = backingAlignedRect(NSIntersectionRect(textPolygon.body, innerBox), options: .alignAllEdgesNearest)
        }
        if (!NSIsEmptyRect(textPolygon.trailing)) {
          textPolygon.trailing.origin.x += _marginInsets.left - padding
          textPolygon.trailing.origin.y += _marginInsets.top
          textPolygon.trailing.size.width += padding
          if (NSMaxRange(hilitedPreeditRange) + 2 == NSMaxRange(preeditRange)) {
            textPolygon.trailing.size.width += padding
          }
          textPolygon.trailing = backingAlignedRect(NSIntersectionRect(textPolygon.trailing, innerBox), options: .alignAllEdgesNearest)
        }

        // Handles the special case where containing boxes are separated
        if (NSIsEmptyRect(textPolygon.body) &&
            !NSIsEmptyRect(textPolygon.leading) &&
            !NSIsEmptyRect(textPolygon.trailing) &&
            NSMaxX(textPolygon.trailing) < NSMinX(textPolygon.leading)) {
          hilitedPreeditPath = squirclePath(vertices: rectVertices(textPolygon.leading),
                                            radius: cornerRadius)
          hilitedPreeditPath!.append(squirclePath(vertices: rectVertices(textPolygon.trailing),
                                                  radius: cornerRadius)!)
        } else {
          hilitedPreeditPath = squirclePath(vertices: textPolygonVertices(textPolygon),
                                            radius: cornerRadius)
        }
      }
      _deleteBackRect = blockRect(forRange: NSMakeRange(NSMaxRange(preeditRange) - 1, 1))
      _deleteBackRect.size.width += floor(_currentTheme.fullWidth * 0.5)
      _deleteBackRect.origin.x = NSMaxX(backgroundRect) - NSWidth(_deleteBackRect)
      _deleteBackRect.origin.y += _marginInsets.top
      _deleteBackRect = backingAlignedRect(NSIntersectionRect(_deleteBackRect, _preeditBlock),
                                           options: .alignAllEdgesNearest)
    }

    
    // Draw candidate Rect
    _candidateBlock = NSZeroRect
    _candidatePolygons = []
    _sectionRects = []
    _tabularIndices = []
    var candidateBlockPath: NSBezierPath?, hilitedCandidatePath: NSBezierPath?
    var gridPath: NSBezierPath?, activePagePath: NSBezierPath?
    if (candidateBlockRange.length > 0) {
      _candidateBlock = blockRect(forRange: candidateBlockRange)
      _candidateBlock.size.width = backgroundRect.size.width
      _candidateBlock.origin.x = backgroundRect.origin.x
      _candidateBlock.origin.y = preeditRange.length == 0 ? NSMinY(backgroundRect) : NSMaxY(preeditBlock)
      if (pagingRange.length == 0) {
        _candidateBlock.size.height = NSMaxY(backgroundRect) - NSMinY(_candidateBlock)
      } else if (!_currentTheme.linear) {
        _candidateBlock.size.height += _currentTheme.linespace
      }
      _candidateBlock = backingAlignedRect(NSIntersectionRect(_candidateBlock, backgroundRect),
                                           options: .alignAllEdgesNearest)
      let blockCornerRadius: Double = min(_currentTheme.hilitedCornerRadius,
                                          NSHeight(_candidateBlock) * 0.5);
      candidateBlockPath = squirclePath(vertices: rectVertices(_candidateBlock),
                                        radius: blockCornerRadius)

      // Draw candidate highlight rect
      let cornerRadius: Double = min(_currentTheme.hilitedCornerRadius,
                                     _currentTheme.candidateParagraphStyle.minimumLineHeight * 0.5)
      if (_currentTheme.linear) {
        var gridOriginY: Double = NSMinY(candidateBlock)
        let tabInterval: Double = currentTheme.fullWidth * 2
        var lineNum: Int = 0
        var sectionRect: NSRect = candidateBlock
        if (_currentTheme.tabular) {
          gridPath = NSBezierPath()
          sectionRect.size.height = 0
        }
        for i in 0..<_numCandidates {
          let candidateRange: NSRange = NSIntersectionRange(candidateRanges[i].NSRange(), visibleRange)
          if (candidateRange.length == 0) {
            _numCandidates = i
            break
          }
          var candidatePolygon: SquirrelTextPolygon = textPolygon(forRange: candidateRange)
          if (!NSIsEmptyRect(candidatePolygon.leading)) {
            candidatePolygon.leading.origin.x += _currentTheme.borderInsets.width
            candidatePolygon.leading.size.width += _currentTheme.fullWidth
            candidatePolygon.leading.origin.y += _marginInsets.top
            candidatePolygon.leading = backingAlignedRect(NSIntersectionRect(candidatePolygon.leading, _candidateBlock), options: .alignAllEdgesNearest)
          }
          if (!NSIsEmptyRect(candidatePolygon.trailing)) {
            candidatePolygon.trailing.origin.x += _currentTheme.borderInsets.width
            candidatePolygon.trailing.origin.y += _marginInsets.top
            candidatePolygon.trailing = backingAlignedRect(NSIntersectionRect(candidatePolygon.trailing, _candidateBlock), options: .alignAllEdgesNearest)
          }
          if (!NSIsEmptyRect(candidatePolygon.body)) {
            candidatePolygon.body.origin.x += _currentTheme.borderInsets.width
            if (truncated[i]) {
              candidatePolygon.body.size.width = NSMaxX(_candidateBlock) - NSMinX(candidatePolygon.body)
            } else if (!NSIsEmptyRect(candidatePolygon.trailing)) {
              candidatePolygon.body.size.width += _currentTheme.fullWidth
            }
            candidatePolygon.body.origin.y += _marginInsets.top
            candidatePolygon.body = backingAlignedRect(NSIntersectionRect(candidatePolygon.body, _candidateBlock), options: .alignAllEdgesNearest)
          }
          if (_currentTheme.tabular) {
            if (expanded) {
              if (i % _currentTheme.pageSize == 0) {
                sectionRect.origin.y += NSHeight(sectionRect)
              } else if (i % _currentTheme.pageSize == _currentTheme.pageSize - 1) {
                sectionRect.size.height = NSMaxY(NSIsEmptyRect(candidatePolygon.trailing) ? candidatePolygon.body : candidatePolygon.trailing) - NSMinY(sectionRect)
                let sec: Int = i / _currentTheme.pageSize
                _sectionRects[sec] = sectionRect
                if (sec == _hilitedIndex / _currentTheme.pageSize) {
                  let pageCornerRadius: Double = min(_currentTheme.hilitedCornerRadius,
                                                     NSHeight(sectionRect) * 0.5)
                  activePagePath = squirclePath(vertices: rectVertices(sectionRect),
                                                radius: pageCornerRadius)
                }
              }
            }
            let bottomEdge: Double = NSMaxY(NSIsEmptyRect(candidatePolygon.trailing) ? candidatePolygon.body : candidatePolygon.trailing)
            if (abs(bottomEdge - gridOriginY) > 2) {
              lineNum += i > 0 ? 1 : 0
              // horizontal border except for the last line
              if (abs(bottomEdge - NSMaxY(_candidateBlock)) > 2) {
                gridPath!.move(to: NSMakePoint(NSMinX(_candidateBlock) + ceil(_currentTheme.fullWidth * 0.5), bottomEdge))
                gridPath!.line(to: NSMakePoint(NSMaxX(_candidateBlock) - floor(_currentTheme.fullWidth * 0.5), bottomEdge))
              }
              gridOriginY = bottomEdge
            }
            let headOrigin: CGPoint = (NSIsEmptyRect(candidatePolygon.leading) ? candidatePolygon.body : candidatePolygon.leading).origin
            let headTabColumn: Int = Int(round((headOrigin.x - _marginInsets.left) / tabInterval))
            // vertical bar
            if (headOrigin.x > NSMinX(_candidateBlock) + _currentTheme.fullWidth) {
              gridPath!.move(to: NSMakePoint(headOrigin.x, headOrigin.y + cornerRadius * 0.8))
              gridPath!.line(to: NSMakePoint(headOrigin.x, NSMaxY(NSIsEmptyRect(candidatePolygon.leading) ? candidatePolygon.body : candidatePolygon.leading) - cornerRadius * 0.8))
            }
            _tabularIndices.append(SquirrelTabularIndex(index: i, lineNum: lineNum, tabNum: headTabColumn))
          }
          _candidatePolygons.append(candidatePolygon)
        }
        if (_hilitedIndex < _numCandidates) {
          let hilitedPolygon: SquirrelTextPolygon = _candidatePolygons[_hilitedIndex]
          // Handles the special case where containing boxes are separated
          if (!NSIsEmptyRect(hilitedPolygon.leading) &&
              NSIsEmptyRect(hilitedPolygon.body) &&
              !NSIsEmptyRect(hilitedPolygon.trailing) &&
              NSMaxX(hilitedPolygon.trailing) < NSMinX(hilitedPolygon.leading)) {
            hilitedCandidatePath = squirclePath(vertices: rectVertices(hilitedPolygon.leading), radius: cornerRadius)
            hilitedCandidatePath!.append(squirclePath(vertices: rectVertices(hilitedPolygon.trailing), radius: cornerRadius)!)
          } else {
            hilitedCandidatePath = squirclePath(vertices: textPolygonVertices(hilitedPolygon), radius: cornerRadius)
          }
        }
      } else { // stacked layout
        for i in 0..<candidateRanges.count {
          let candidateRange: NSRange = NSIntersectionRange(candidateRanges[i].NSRange(), visibleRange)
          if (candidateRange.length == 0) {
            _numCandidates = i
            break
          }
          var candidateRect: NSRect = blockRect(forRange: candidateRange)
          candidateRect.size.width = backgroundRect.size.width
          candidateRect.origin.x = backgroundRect.origin.x

          candidateRect.origin.y += _marginInsets.top - ceil(_currentTheme.linespace * 0.5)
          candidateRect.size.height += _currentTheme.linespace
          candidateRect = backingAlignedRect(NSIntersectionRect(candidateRect, _candidateBlock), options: .alignAllEdgesNearest)
          _candidatePolygons.append(SquirrelTextPolygon(leading: NSZeroRect, body: candidateRect, trailing: NSZeroRect))
        }
        if (_hilitedIndex < _numCandidates) {
          hilitedCandidatePath = squirclePath(vertices: rectVertices(_candidatePolygons[_hilitedIndex].body), radius: cornerRadius)
        }
      }
    }

    // Draw paging Rect
    _pagingBlock = NSZeroRect
    _pageUpRect = NSZeroRect
    _pageDownRect = NSZeroRect
    _expanderRect = NSZeroRect
    if (pagingRange.length > 0) {
      if (_currentTheme.linear) {
        _pagingBlock = blockRect(forRange: pagingRange)
        _pagingBlock.size.width += _currentTheme.fullWidth
        _pagingBlock.origin.x = NSMaxX(backgroundRect) - NSWidth(_pagingBlock)
      } else {
        _pagingBlock = backgroundRect
      }
      _pagingBlock.origin.y = NSMaxY(_candidateBlock)
      _pagingBlock.size.height = NSMaxY(backgroundRect) - NSMaxY(_candidateBlock)
      if (_currentTheme.showPaging) {
        _pageUpRect = blockRect(forRange: NSMakeRange(pagingRange.location, 1))
        _pageDownRect = blockRect(forRange: NSMakeRange(NSMaxRange(pagingRange) - 1, 1))
        _pageDownRect.origin.x += _marginInsets.left
        _pageDownRect.size.width += ceil(_currentTheme.fullWidth * 0.5)
        _pageDownRect.origin.y += _marginInsets.top
        _pageUpRect.origin.x += _currentTheme.borderInsets.width
        // bypass the bug of getting wrong glyph position when tab is presented
        _pageUpRect.size.width = NSWidth(_pageDownRect)
        _pageUpRect.origin.y += _marginInsets.top
        _pageUpRect = backingAlignedRect(NSIntersectionRect(_pageUpRect, _pagingBlock),
                                         options: .alignAllEdgesNearest)
        _pageDownRect = backingAlignedRect(NSIntersectionRect(_pageDownRect, _pagingBlock),
                                           options: .alignAllEdgesNearest)
      }
      if (_currentTheme.tabular) {
        _expanderRect = blockRect(forRange: NSMakeRange(pagingRange.location + pagingRange.length / 2, 1))
        _expanderRect.origin.x += _currentTheme.borderInsets.width;
        _expanderRect.size.width += _currentTheme.fullWidth;
        _expanderRect.origin.y += _marginInsets.top;
        _expanderRect = backingAlignedRect(NSIntersectionRect(_expanderRect, backgroundRect),
                                           options: .alignAllEdgesNearest)
      }
    }

    // Draw borders
    let outerCornerRadius: Double = min(_currentTheme.cornerRadius, NSHeight(panelRect) * 0.5)
    let innerCornerRadius: Double = max(min(_currentTheme.hilitedCornerRadius,
                                            NSHeight(backgroundRect) * 0.5),
                                        outerCornerRadius - min(_currentTheme.borderInsets.width,
                                                                _currentTheme.borderInsets.height))
    var panelPath: NSBezierPath!, backgroundPath: NSBezierPath!
    if (!_currentTheme.linear || pagingRange.length == 0) {
      panelPath = squirclePath(vertices: rectVertices(panelRect), radius: outerCornerRadius)
      backgroundPath = squirclePath(vertices: rectVertices(backgroundRect), radius: innerCornerRadius)
    } else {
      var mainPanelRect: NSRect = panelRect
      mainPanelRect.size.height -= NSHeight(_pagingBlock)
      let tailPanelRect: NSRect = NSInsetRect(NSOffsetRect(_pagingBlock, 0, _currentTheme.borderInsets.height), 0 - _currentTheme.borderInsets.width, 0)
      let panelPolygon = SquirrelTextPolygon(leading: mainPanelRect,
                                             body: tailPanelRect, trailing: NSZeroRect)
      panelPath = squirclePath(vertices: textPolygonVertices(panelPolygon),
                               radius: outerCornerRadius)
      var mainBackgroundRect: NSRect = backgroundRect
      mainBackgroundRect.size.height -= NSHeight(_pagingBlock)
      let backgroundPolygon = SquirrelTextPolygon(leading: mainBackgroundRect,
                                                  body: _pagingBlock, trailing: NSZeroRect)
      backgroundPath = squirclePath(vertices: textPolygonVertices(backgroundPolygon),
                                    radius: innerCornerRadius)
    }
    let borderPath: NSBezierPath = panelPath.copy() as! NSBezierPath
    borderPath.append(backgroundPath)

    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: NSHeight(panelRect))
    flip.scaleX(by: 1, yBy: -1)
    let shapePath: NSBezierPath = flip.transform(panelPath)

    // Set layers
    shape.path = shapePath.quartzPath
    shape.fillColor = NSColor.white.cgColor
    layer!.sublayers = nil
    // layers of large background elements
    let BackLayers = CALayer()
    let shapeLayer = CAShapeLayer()
    shapeLayer.path = panelPath.quartzPath
    shapeLayer.fillColor = NSColor.white.cgColor
    BackLayers.mask = shapeLayer
    if #available(macOS 10.14, *) {
      BackLayers.opacity = Float(1.0 - _currentTheme.translucency)
      BackLayers.allowsGroupOpacity = true
    }
    layer!.addSublayer(BackLayers)
    // background image (pattern style) layer
    if (_currentTheme.backImage?.isValid ?? false) {
      let backImageLayer = CAShapeLayer()
      var transform:CGAffineTransform = _currentTheme.vertical ? CGAffineTransformMakeRotation(.pi / 2)
      : CGAffineTransformIdentity
      transform = CGAffineTransformTranslate(transform, -backgroundRect.origin.x, -backgroundRect.origin.y)
      backImageLayer.path = backgroundPath.quartzPath?.copy(using: &transform)
      backImageLayer.fillColor = NSColor(patternImage: _currentTheme.backImage!).cgColor
      backImageLayer.setAffineTransform(CGAffineTransformInvert(transform))
      BackLayers.addSublayer(backImageLayer)
    }
    // background color layer
    let backColorLayer = CAShapeLayer()
    if (!NSIsEmptyRect(_preeditBlock) || !NSIsEmptyRect(_pagingBlock) ||
        !NSIsEmptyRect(_expanderRect)) && _currentTheme.preeditBackColor != nil {
      if (candidateBlockPath != nil) {
        let nonCandidatePath: NSBezierPath! = backgroundPath.copy() as? NSBezierPath
        nonCandidatePath.append(candidateBlockPath!)
        backColorLayer.path = nonCandidatePath.quartzPath
        backColorLayer.fillRule = .evenOdd
        backColorLayer.strokeColor = _currentTheme.preeditBackColor!.cgColor
        backColorLayer.lineWidth = 0.5
        backColorLayer.fillColor = _currentTheme.preeditBackColor!.cgColor
        BackLayers.addSublayer(backColorLayer)
        // candidate block's background color layer
        let candidateLayer = CAShapeLayer()
        candidateLayer.path = candidateBlockPath!.quartzPath
        candidateLayer.fillColor = _currentTheme.backColor.cgColor
        BackLayers.addSublayer(candidateLayer)
      } else {
        backColorLayer.path = backgroundPath.quartzPath
        backColorLayer.strokeColor = _currentTheme.preeditBackColor!.cgColor
        backColorLayer.lineWidth = 0.5
        backColorLayer.fillColor = _currentTheme.preeditBackColor!.cgColor
        BackLayers.addSublayer(backColorLayer)
      }
    } else {
      backColorLayer.path = backgroundPath.quartzPath
      backColorLayer.strokeColor = _currentTheme.backColor.cgColor
      backColorLayer.lineWidth = 0.5
      backColorLayer.fillColor = _currentTheme.backColor.cgColor
      BackLayers.addSublayer(backColorLayer)
    }
    // border layer
    let borderLayer = CAShapeLayer()
    borderLayer.path = borderPath.quartzPath
    borderLayer.fillRule = .evenOdd
    borderLayer.fillColor = (_currentTheme.borderColor != nil ? _currentTheme.borderColor! : _currentTheme.backColor).cgColor
    BackLayers.addSublayer(borderLayer)
    // layers of small highlighting elements
    let ForeLayers = CALayer()
    let maskLayer = CAShapeLayer()
    maskLayer.path = backgroundPath.quartzPath
    maskLayer.fillColor = NSColor.white.cgColor
    ForeLayers.mask = maskLayer
    layer!.addSublayer(ForeLayers)
    // highlighted preedit layer
    if (hilitedPreeditPath != nil) && (_currentTheme.hilitedPreeditBackColor != nil) {
      let hilitedPreeditLayer = CAShapeLayer()
      hilitedPreeditLayer.path = hilitedPreeditPath!.quartzPath
      hilitedPreeditLayer.fillColor = _currentTheme.hilitedPreeditBackColor!.cgColor
      ForeLayers.addSublayer(hilitedPreeditLayer)
    }
    // highlighted candidate layer
    if (hilitedCandidatePath != nil) && (_currentTheme.hilitedCandidateBackColor != nil) {
      if (activePagePath != nil) {
        let activePageLayer = CAShapeLayer()
        activePageLayer.path = activePagePath!.quartzPath
        activePageLayer.fillColor = _currentTheme.hilitedCandidateBackColor!.blendWithColor(_currentTheme.backColor, ofFraction: 0.8)!.cgColor
        BackLayers.addSublayer(activePageLayer)
      }
      let hilitedCandidateLayer = CAShapeLayer()
      hilitedCandidateLayer.path = hilitedCandidatePath!.quartzPath
      hilitedCandidateLayer.fillColor = _currentTheme.hilitedCandidateBackColor!.cgColor
      ForeLayers.addSublayer(hilitedCandidateLayer)
    }
    // function buttons (page up, page down, backspace) layer
    if (_functionButton != .kVoidSymbol) {
      if let functionButtonLayer = getFunctionButtonLayer() {
        ForeLayers.addSublayer(functionButtonLayer)
      }
    }
    // grids (in candidate block) layer
    if (gridPath != nil) {
      let gridLayer = CAShapeLayer()
      gridLayer.path = gridPath!.quartzPath
      gridLayer.lineWidth = 1.0
      gridLayer.strokeColor = (_currentTheme.commentAttrs[.foregroundColor] as! NSColor).blendWithColor(_currentTheme.backColor, ofFraction: 0.8)!.cgColor
      ForeLayers.addSublayer(gridLayer)
    }
    // logo at the beginning for status message
    if (NSIsEmptyRect(_preeditBlock) && NSIsEmptyRect(_candidateBlock)) {
      let logoLayer = CALayer()
      let height: Double = (currentTheme.statusAttrs[NSAttributedString.Key.paragraphStyle] as! NSParagraphStyle).minimumLineHeight
      let logoRect: NSRect = NSMakeRect(backgroundRect.origin.x, backgroundRect.origin.y, height, height)
      logoLayer.frame = self.backingAlignedRect(NSInsetRect(logoRect, -0.1 * height, -0.1 * height), options: .alignAllEdgesNearest)
      let logoImage: NSImage! = NSImage(named: NSImage.applicationIconName)
      logoImage.size = logoRect.size
      let scaleFactor: Double = logoImage.recommendedLayerContentsScale(window!.backingScaleFactor)
      logoLayer.contents = logoImage
      logoLayer.contentsScale = scaleFactor
      logoLayer.setAffineTransform(currentTheme.vertical ? CGAffineTransformMakeRotation(-.pi / 2) : CGAffineTransformIdentity)
      ForeLayers.addSublayer(logoLayer)
    }
  }

  fileprivate func getIndexFromMouseSpot(_ spot: NSPoint) -> Int {
    let point: NSPoint = convert(spot, from: nil)
    if (NSMouseInRect(point, bounds, true)) {
      if (NSMouseInRect(point, preeditBlock, true)) {
        return NSMouseInRect(point, deleteBackRect, true)
        ? SquirrelIndex.kBackSpaceKey.rawValue
        : SquirrelIndex.kCodeInputArea.rawValue
      }
      if (NSMouseInRect(point, expanderRect, true)) {
        return SquirrelIndex.kExpandButton.rawValue
      }
      if (NSMouseInRect(point, pageUpRect, true)) {
        return SquirrelIndex.kPageUpKey.rawValue
      }
      if (NSMouseInRect(point, pageDownRect, true)) {
        return SquirrelIndex.kPageDownKey.rawValue
      }
      for i in 0..<candidateRanges.count {
        if (NSMouseInRect(point, _candidatePolygons[i].body, true) ||
            NSMouseInRect(point, _candidatePolygons[i].leading, true) ||
            NSMouseInRect(point, _candidatePolygons[i].trailing, true)) {
          return i
        }
      }
    }
    return NSNotFound
  }
}  // SquirrelView


/* In order to put SquirrelPanel above client app windows,
 SquirrelPanel needs to be assigned a window level higher
 than kCGHelpWindowLevelKey that the system tooltips use.
 This class makes system-alike tooltips above SquirrelPanel
 */

class SquirrelToolTip: NSWindow {

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

  fileprivate func show(withToolTip toolTip: String!,
                        delay: Boolean) {
    if (toolTip.count == 0) {
      hide()
      return
    }
    let panel: SquirrelPanel! = NSApp.squirrelAppDelegate.panel
    level = panel.level + 1
    appearanceSource = panel

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

    let screenRect: NSRect = panel.screen!.visibleFrame
    if (NSMaxX(windowRect) > NSMaxX(screenRect)) {
      windowRect.origin.x = NSMaxX(screenRect) - NSWidth(windowRect)
    }
    if (NSMinY(windowRect) < NSMinY(screenRect)) {
      windowRect.origin.y = NSMinY(screenRect)
    }
    setFrame(panel.screen!.backingAlignedRect(windowRect, options: .alignAllEdgesNearest),
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

  fileprivate func hide() {
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

class SquirrelPanel: NSPanel, NSWindowDelegate {
  // Squirrel panel layouts
  private var _back: NSVisualEffectView?
  private var _toolTip: SquirrelToolTip
  private var _view: SquirrelView = SquirrelView(frame: NSZeroRect)
  private var _statusTimer: Timer?
  private var _maxSize: NSSize = NSZeroSize
  private var _scrollLocus: NSPoint = NSZeroPoint
  private var _cursorIndex: SquirrelIndex = .kVoidSymbol
  private var _textWidthLimit: Double = CGFLOAT_MAX
  private var _anchorOffset: Double = 0
  private var _initPosition: Boolean = true
  private var _needsRedraw: Boolean = false
  // Rime contents and actions
  private var _candTexts: [String]
  private var _candComments: [String]
  private var _indexRange: Range<Int> = 0..<0
  private var _highlightedIndex: Int = NSNotFound
  private var _functionButton: SquirrelIndex = .kVoidSymbol
  private var _caretPos: Int = NSNotFound
  private var _pageNum: Int = 0
  private var _sectionNum: Int = 0
  private var _finalPage: Boolean = false
  var numCachedCandidates: Int { get { return _candTexts.count } }
  // Show preedit text inline.
  var inlinePreedit: Boolean {
    get { return _view.currentTheme.inlinePreedit }
  }
  // Show primary candidate inline
  var inlineCandidate: Boolean {
    get { return _view.currentTheme.inlineCandidate }
  }
  // Vertical text orientation, as opposed to horizontal text orientation.
  var vertical: Boolean {
    get { return _view.currentTheme.vertical }
  }
  // Linear candidate list layout, as opposed to stacked candidate list layout.
  var linear: Boolean {
    get { return _view.currentTheme.linear }
  }
  // Tabular candidate list layout, initializes as tab-aligned linear layout,
  // expandable to stack 5 (3 for vertical) pages/sections of candidates
  var tabular: Boolean {
    get { return _view.currentTheme.tabular }
  }
  private var _locked: Boolean = false
  var locked: Boolean {
    get { return _locked }
  }
  var firstLine: Boolean {
    get { return _view.tabularIndices.isEmpty ? true : _view.tabularIndices[_highlightedIndex].lineNum == 0 }
  }
  var expanded: Boolean {
    get { return _view.expanded }
    set (expanded) {
      if (_view.currentTheme.tabular && !_locked && _view.expanded != expanded) {
        _view.expanded = expanded
        _sectionNum = 0
      }
    }
  }
  var sectionNum: Int {
    get { return _sectionNum }
    set (sectionNum) {
      if (_view.currentTheme.tabular && _view.expanded && _sectionNum != sectionNum) {
        let maxSections: Int = _view.currentTheme.vertical ? 2 : 4
        _sectionNum = sectionNum < 0 ? 0 : sectionNum > maxSections ? maxSections : sectionNum
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
  private var _inputController: SquirrelInputController?
  // Status message before pop-up is displayed; nil before normal panel is displayed
  private var _statusMessage: String?
  var statusMessage: String? { get { return _statusMessage } }
  // Store switch options that change style (color theme) settings
  var optionSwitcher: SquirrelOptionSwitcher = SquirrelOptionSwitcher()

  init() {
    let contentView = NSView()
    _view = SquirrelView(frame: contentView.bounds)
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
    contentView.addSubview(_view.textView)
    _toolTip = SquirrelToolTip()
    _candTexts = []
    _candComments = []

    super.init(contentRect: NSZeroRect,
               styleMask: [.borderless, .nonactivatingPanel],
               backing: .buffered,
               defer: true)
    level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow) - 100))
    alphaValue = 1.0
    hasShadow = false
    isOpaque = false
    backgroundColor = NSColor.clear
    delegate = self
    acceptsMouseMovedEvents = true
    self.contentView = contentView
    self.appearance = NSAppearance(named: .aqua)
    updateDisplayParameters()
  }

  private func setLocker(_ locked: Boolean) {
    if (_view.currentTheme.tabular && _locked != locked) {
      _locked = locked
      let userConfig = SquirrelConfig()
      if (userConfig.open(userConfig: "user")) {
        _ = userConfig.setOption("var/option/_lock_tabular", withBool:locked)
        if (locked) {
          _ = userConfig.setOption("var/option/_expand_tabular", withBool:_view.expanded)
        }
      }
      userConfig.close()
    }
  }

  private func getLocker() {
    if (_view.currentTheme.tabular) {
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

  func windowDidChangeBackingProperties(_ notification: Notification) {
    if let panel = notification.object as? SquirrelPanel {
      panel.updateDisplayParameters()
    }
  }

  override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                             change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
    if let inputController = object as? SquirrelInputController {
      if (keyPath == "viewEffectiveAppearance") {
        _inputController = inputController
        if #available(macOS 10.14, *) {
          let clientAppearance: NSAppearance = change![.newKey] as! NSAppearance
          let appearName: NSAppearance.Name = clientAppearance.bestMatch(from: [.aqua, .darkAqua])!
          let appear: SquirrelAppear = appearName == .darkAqua ? .darkAppear : .defaultAppear
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
    if (!tabular || _indexRange.count == 0 || _highlightedIndex == NSNotFound) {
      return NSNotFound
    }
    let pageSize: Int = _view.currentTheme.pageSize
    let currentTab: Int = _view.tabularIndices[_highlightedIndex].tabNum
    let currentLine: Int = _view.tabularIndices[_highlightedIndex].lineNum
    let finalLine: Int = _view.tabularIndices[_indexRange.count - 1].lineNum
    if (arrowKey == (self.vertical ? .kLeftKey : .kDownKey)) {
      if (_highlightedIndex == _indexRange.count - 1 && _finalPage) {
        return NSNotFound
      }
      if (currentLine == finalLine && !_finalPage) {
        return _highlightedIndex + pageSize + _indexRange.lowerBound
      }
      var newIndex: Int = _highlightedIndex + 1
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
    } else if (arrowKey == (self.vertical ? .kRightKey : .kUpKey)) {
      if (currentLine == 0) {
        return _pageNum == 0 ? NSNotFound : pageSize * (_pageNum - _sectionNum) - 1
      }
      var newIndex: Int = _highlightedIndex - 1
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
    let theme: SquirrelTheme! = _view.currentTheme
    switch (event.type) {
    case .leftMouseDown:
      if (event.clickCount == 1 && _cursorIndex == .kCodeInputArea) {
        let spot:NSPoint = _view.textView.convert(mouseLocationOutsideOfEventStream, from: nil)
        let inputIndex: Int = _view.textView.characterIndexForInsertion(at: spot)
        if (inputIndex == 0) {
          _inputController?.perform(action: .PROCESS, onIndex: .kHomeKey)
        } else if (inputIndex < _caretPos) {
          _inputController?.moveCursor(_caretPos, to: inputIndex,
                                      inlinePreedit: false, inlineCandidate: false)
        } else if (inputIndex >= _view.preeditRange.length) {
          _inputController?.perform(action: .PROCESS, onIndex: .kEndKey)
        } else if (inputIndex > _caretPos + 1) {
          _inputController?.moveCursor(_caretPos, to: inputIndex - 1,
                                      inlinePreedit: false, inlineCandidate: false)
        }
      }
      break
    case .leftMouseUp:
      if (event.clickCount == 1 && _cursorIndex.rawValue != NSNotFound) {
        if (_cursorIndex.rawValue == _highlightedIndex) {
          _inputController?.perform(action: .SELECT, onIndex: SquirrelIndex(rawValue: _cursorIndex.rawValue + _indexRange.lowerBound)!)
        } else if (_cursorIndex == _functionButton) {
          if (_cursorIndex == .kExpandButton) {
            if (_locked) {
              setLocker(false)
              _view.textStorage.replaceCharacters(in: NSMakeRange(_view.textStorage.length - 1, 1),
                                                  with: (_view.expanded ? theme.symbolCompress : theme.symbolExpand)!)
              _view.textView.setNeedsDisplay(_view.expanderRect)
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
      if (event.clickCount == 1 && _cursorIndex.rawValue != NSNotFound) {
        if (_cursorIndex.rawValue == _highlightedIndex) {
          _inputController?.perform(action: .DELETE, onIndex: SquirrelIndex(rawValue: _cursorIndex.rawValue + _indexRange.lowerBound)!)
        } else if (_cursorIndex == _functionButton) {
          switch (_functionButton) {
          case .kPageUpKey:
            _inputController?.perform(action: .PROCESS, onIndex: .kHomeKey)
            break
          case .kPageDownKey:
            _inputController?.perform(action: .PROCESS, onIndex: .kEndKey)
            break
          case .kExpandButton:
            setLocker(!_locked)
            _view.textStorage.replaceCharacters(in: NSMakeRange(_view.textStorage.length - 1, 1),
                                                with: (_locked ? theme.symbolLock : _view.expanded ? theme.symbolCompress : theme.symbolExpand)!)
            _view.textStorage.addAttribute(.foregroundColor,
                                           value: theme.hilitedPreeditForeColor,
                                           range: NSMakeRange(_view.textStorage.length - 1, 1))
            _view.textView.setNeedsDisplay(_view.expanderRect)
            _inputController?.perform(action: .PROCESS, onIndex: .kLockButton)
            break
          case .kBackSpaceKey:
            _inputController?.perform(action: .PROCESS, onIndex: .kEscapeKey)
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
      let noDelay: Boolean = event.modifierFlags.contains(.option)
      _cursorIndex = SquirrelIndex(rawValue: _view.getIndexFromMouseSpot(mouseLocationOutsideOfEventStream))!
      if (_cursorIndex.rawValue != _highlightedIndex && _cursorIndex != _functionButton) {
        _toolTip.hide()
      } else if (noDelay) {
        _toolTip.displayTimer?.fire()
      }
      if (_cursorIndex.rawValue >= 0 &&
          _cursorIndex.rawValue < _indexRange.count &&
          _highlightedIndex != _cursorIndex.rawValue) {
        highlightFunctionButton(.kVoidSymbol, delayToolTip: !noDelay)
        if (noDelay) {
          _toolTip.show(withToolTip: NSLocalizedString("candidate", comment: ""), delay: !noDelay)
        }
        sectionNum = _cursorIndex.rawValue / theme.pageSize
        _inputController?.perform(action: .HIGHLIGHT, onIndex: SquirrelIndex(rawValue: _cursorIndex.rawValue + _indexRange.lowerBound)!)
      } else if (_cursorIndex == .kPageUpKey || _cursorIndex == .kPageDownKey ||
                 _cursorIndex == .kExpandButton || _cursorIndex == .kBackSpaceKey) &&
                  _functionButton != _cursorIndex {
        highlightFunctionButton(_cursorIndex, delayToolTip: !noDelay)
      }
      break
    case .mouseExited:
      _toolTip.displayTimer?.invalidate()
      break
    case .leftMouseDragged:
      // reset the remember_size references after moving the panel
      _maxSize = NSZeroSize
      performDrag(with: event)
      break
    case .scrollWheel:
      let rulerStyle: NSParagraphStyle = theme.candidateParagraphStyle
      let scrollThreshold: Double = rulerStyle.minimumLineHeight + rulerStyle.lineSpacing
      if (event.phase == .began) {
        _scrollLocus = NSZeroPoint
      } else if (event.phase == .changed && !_scrollLocus.x.isNaN && !_scrollLocus.y.isNaN) {
        // determine scrolling direction by confining to sectors within ±30º of any axis
        if (abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * sqrt(3.0)) {
          _scrollLocus.x += event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 10)
        } else if (abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) * sqrt(3.0)) {
          _scrollLocus.y += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        }
        // compare accumulated locus length against threshold and limit paging to max once
        if (_scrollLocus.x > scrollThreshold) {
          _inputController?.perform(action: .PROCESS, onIndex: theme.vertical ? .kPageDownKey : .kPageUpKey)
          _scrollLocus = NSMakePoint(.nan, .nan)
        } else if (_scrollLocus.y > scrollThreshold) {
          _inputController?.perform(action: .PROCESS, onIndex: .kPageUpKey)
          _scrollLocus = NSMakePoint(.nan, .nan)
        } else if (_scrollLocus.x < -scrollThreshold) {
          _inputController?.perform(action: .PROCESS, onIndex: theme.vertical ? .kPageUpKey : .kPageDownKey)
          _scrollLocus = NSMakePoint(.nan, .nan)
        } else if (_scrollLocus.y < -scrollThreshold) {
          _inputController?.perform(action: .PROCESS, onIndex: .kPageDownKey)
          _scrollLocus = NSMakePoint(.nan, .nan)
        }
      }
      break
    default:
      super.sendEvent(event)
      break
    }
  }

  private func highlightCandidate(_ highlightedIndex: Int) {
    let theme: SquirrelTheme! = _view.currentTheme
    let priorHilitedIndex: Int = _highlightedIndex
    let priorSectionNum: Int = priorHilitedIndex / theme.pageSize
    _highlightedIndex = highlightedIndex
    sectionNum = highlightedIndex / theme.pageSize
    // apply new foreground colors
    for i in 0..<theme.pageSize {
      let priorIndex: Int = i + priorSectionNum * theme.pageSize
      if ((_sectionNum != priorSectionNum || priorIndex == priorHilitedIndex) && priorIndex < _indexRange.count) {
        let labelColor = priorIndex == priorHilitedIndex && _sectionNum == priorSectionNum ? theme.labelForeColor : theme.dimmedLabelForeColor!
        _view.textStorage.addAttribute(.foregroundColor,
                                       value: labelColor,
                                       range: NSMakeRange(_view.candidateRanges[priorIndex].location, _view.candidateRanges[priorIndex].text))
        if (priorIndex == priorHilitedIndex) {
          _view.textStorage.addAttribute(.foregroundColor,
                                         value: theme.textForeColor,
                                         range: NSMakeRange(_view.candidateRanges[priorIndex].location + _view.candidateRanges[priorIndex].text,
                                                            _view.candidateRanges[priorIndex].comment - _view.candidateRanges[priorIndex].text))
          _view.textStorage.addAttribute(.foregroundColor,
                                         value: theme.commentForeColor,
                                         range: NSMakeRange(_view.candidateRanges[priorIndex].location + _view.candidateRanges[priorIndex].comment,
                                                            _view.candidateRanges[priorIndex].length - _view.candidateRanges[priorIndex].comment))
        }
      }
      let newIndex: Int = i + _sectionNum * theme.pageSize
      if ((_sectionNum != priorSectionNum || newIndex == _highlightedIndex) && newIndex < _indexRange.count ){
        let labelColor = newIndex == _highlightedIndex ? theme.hilitedLabelForeColor : theme.labelForeColor
        _view.textStorage.addAttribute(.foregroundColor,
                                       value: labelColor,
                                       range: NSMakeRange(_view.candidateRanges[newIndex].location, _view.candidateRanges[newIndex].text))
        let textColor = newIndex == _highlightedIndex ? theme.hilitedTextForeColor : theme.textForeColor
        _view.textStorage.addAttribute(.foregroundColor,
                                       value: textColor,
                                       range: NSMakeRange(_view.candidateRanges[newIndex].location + _view.candidateRanges[newIndex].text,
                                                          _view.candidateRanges[newIndex].comment - _view.candidateRanges[newIndex].text))
        let commentColor = newIndex == _highlightedIndex ? theme.hilitedCommentForeColor : theme.commentForeColor
        _view.textStorage.addAttribute(.foregroundColor,
                                       value: commentColor,
                                       range: NSMakeRange(_view.candidateRanges[newIndex].location + _view.candidateRanges[newIndex].comment,
                                                          _view.candidateRanges[newIndex].length - _view.candidateRanges[newIndex].comment))
      }
    }
    _view.highlightCandidate(_highlightedIndex)
    displayIfNeeded()
  }

  private func highlightFunctionButton(_ functionButton: SquirrelIndex,
                                       delayToolTip delay: Boolean) {
    if (_functionButton == functionButton) {
      return
    }
    let theme: SquirrelTheme! = _view.currentTheme
    switch (_functionButton) {
    case .kPageUpKey:
      _view.textStorage.addAttribute(.foregroundColor,
                                     value: theme.preeditForeColor,
                                     range: NSMakeRange(_view.pagingRange.location, 1))
      break
    case .kPageDownKey:
      _view.textStorage.addAttribute(.foregroundColor,
                                     value: theme.preeditForeColor,
                                     range: NSMakeRange(NSMaxRange(_view.pagingRange) - 1, 1))
      break
    case .kExpandButton:
      _view.textStorage.addAttribute(.foregroundColor,
                                     value: theme.preeditForeColor,
                                     range: NSMakeRange(_view.pagingRange.location + _view.pagingRange.length / 2, 1))
      break
    case .kBackSpaceKey:
      _view.textStorage.addAttribute(.foregroundColor,
                                     value: theme.preeditForeColor,
                                     range: NSMakeRange(NSMaxRange(_view.preeditRange) - 1, 1))
      break
    default:
      break
    }
    _functionButton = functionButton
    var newFunctionButton: SquirrelIndex = .kVoidSymbol
    switch (functionButton) {
    case .kPageUpKey:
      _view.textStorage.addAttribute(.foregroundColor,
                                     value: theme.hilitedPreeditForeColor,
                                     range: NSMakeRange(_view.pagingRange.location, 1))
      newFunctionButton = _pageNum == 0 ? .kHomeKey : .kPageUpKey
      _toolTip.show(withToolTip: NSLocalizedString(_pageNum == 0 ? "home" : "page_up", comment: ""), delay: delay)
      break
    case .kPageDownKey:
      _view.textStorage.addAttribute(.foregroundColor,
                                     value: theme.hilitedPreeditForeColor,
                                     range: NSMakeRange(NSMaxRange(_view.pagingRange) - 1, 1))
      newFunctionButton = _finalPage ? .kEndKey : .kPageDownKey
      _toolTip.show(withToolTip: NSLocalizedString(_finalPage ? "end" : "page_down", comment: ""), delay: delay)
      break
    case .kExpandButton:
      _view.textStorage.addAttribute(.foregroundColor,
                                     value: theme.hilitedPreeditForeColor,
                                     range: NSMakeRange(_view.pagingRange.location + _view.pagingRange.length / 2, 1))
      newFunctionButton = _locked ? .kLockButton : _view.expanded ? .kCompressButton : .kExpandButton
      _toolTip.show(withToolTip: NSLocalizedString(_locked ? "unlock" : _view.expanded ? "compress" : "expand",
                                                   comment:""), delay: delay)
      break
    case .kBackSpaceKey:
      _view.textStorage.addAttribute(.foregroundColor,
                                     value: theme.hilitedPreeditForeColor,
                                     range: NSMakeRange(NSMaxRange(_view.preeditRange) - 1, 1))
      newFunctionButton = _caretPos == NSNotFound || _caretPos == 0 ? .kEscapeKey : .kBackSpaceKey
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

    // size limits on textContainer
    let screenRect: NSRect = _screen.visibleFrame
    let theme: SquirrelTheme = _view.currentTheme
    _view.textView.setLayoutOrientation(theme.vertical ? .vertical : .horizontal)
    // rotate the view, the core in vertical mode!
    contentView!.boundsRotation = theme.vertical ? -90.0 : 0.0
    _view.textView.boundsRotation = 0.0
    _view.textView.setBoundsOrigin(NSZeroPoint)

    let textWidthRatio: Double = min(0.8, 1.0 / (theme.vertical ? 4 : 3) + (theme.textAttrs[.font] as! NSFont).pointSize / 144.0)
    _textWidthLimit = floor((theme.vertical ? NSHeight(screenRect) : NSWidth(screenRect)) * textWidthRatio - theme.fullWidth - theme.borderInsets.width * 2)
    if (theme.lineLength > 0.1) {
      _textWidthLimit = min(theme.lineLength, _textWidthLimit)
    }
    if (theme.tabular) {
      _textWidthLimit = floor((_textWidthLimit + theme.fullWidth) / (theme.fullWidth * 2)) * (theme.fullWidth * 2) - theme.fullWidth
    }
    let textHeightLimit: Double = floor((theme.vertical ? NSWidth(screenRect) : NSHeight(screenRect)) * 0.8 - theme.borderInsets.height * 2 - theme.linespace)
    _view.textView.textContainer!.size = NSMakeSize(_textWidthLimit, textHeightLimit)

    // resize background image, if any
    if (theme.backImage?.isValid ?? false) {
      let widthLimit:Double = _textWidthLimit + theme.fullWidth
      let backImageSize:NSSize = theme.backImage!.size
      theme.backImage!.resizingMode = .stretch
      theme.backImage!.size = theme.vertical
      ? NSMakeSize(backImageSize.width / backImageSize.height * widthLimit, widthLimit)
      : NSMakeSize(widthLimit, backImageSize.height / backImageSize.width * widthLimit)
    }
  }

  // Get the window size, it will be the dirtyRect in SquirrelView.drawRect
  private func show() {
    if (!_needsRedraw && !_initPosition) {
      isVisible ? display() : orderFront(nil)
      return
    }
    //Break line if the text is too long, based on screen size.
    let theme: SquirrelTheme = _view.currentTheme
    let insets: NSEdgeInsets = _view.marginInsets
    let textWidthRatio: Double = min(0.8, 1.0 / (theme.vertical ? 4 : 3) + (theme.textAttrs[.font] as! NSFont).pointSize / 144.0)
    let screenRect: NSRect = _screen.visibleFrame

    // the sweep direction of the client app changes the behavior of adjusting Squirrel panel position
    let sweepVertical: Boolean = NSWidth(IbeamRect) > NSHeight(IbeamRect)
    var contentRect: NSRect = _view.contentRect
    contentRect.size.width -= _view.trailPadding
    // fixed line length (text width), but not applicable to status message
    if (theme.lineLength > 0.1 && statusMessage == nil) {
      contentRect.size.width = _textWidthLimit
    }
    // remember panel size (fix the top leading anchor of the panel in screen coordiantes)
    // but only when the text would expand on the side of upstream (i.e. towards the beginning of text)
    if (theme.rememberSize && statusMessage == nil) {
      if (theme.lineLength < 0.1 &&
          (theme.vertical ? (sweepVertical ? (NSMinY(IbeamRect) - fmax(NSWidth(contentRect), _maxSize.width) - insets.right < NSMinY(screenRect))
                             : (NSMinY(IbeamRect) - kOffsetGap - NSHeight(screenRect) * textWidthRatio - insets.left - insets.right < NSMinY(screenRect)))
           : (sweepVertical ? (NSMinX(IbeamRect) - kOffsetGap - NSWidth(screenRect) * textWidthRatio - insets.left - insets.right >= NSMinX(screenRect))
              : (NSMaxX(IbeamRect) + fmax(NSWidth(contentRect), _maxSize.width) + insets.right > NSMaxX(screenRect))))) {
        if (NSWidth(contentRect) >= _maxSize.width) {
          _maxSize.width = NSWidth(contentRect)
        } else {
          contentRect.size.width = _maxSize.width
        }
      }
      let textHeight:Double = max(NSHeight(contentRect), _maxSize.height) + insets.top + insets.bottom
      if (theme.vertical ? (NSMinX(IbeamRect) - textHeight - (sweepVertical ? kOffsetGap : 0) < NSMinX(screenRect))
          : (NSMinY(IbeamRect) - textHeight - (sweepVertical ? 0 : kOffsetGap) < NSMinY(screenRect))) {
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
        windowRect.size.width = NSHeight(contentRect) + insets.top + insets.bottom
        windowRect.size.height = NSWidth(contentRect) + insets.left + insets.right
      } else {
        windowRect.size.width = NSWidth(contentRect) + insets.left + insets.right
        windowRect.size.height = NSHeight(contentRect) + insets.top + insets.bottom
      }
      if (sweepVertical) { 
        // vertically centre-align (MidY) in screen coordinates
        windowRect.origin.x = NSMinX(IbeamRect) - kOffsetGap - NSWidth(windowRect)
        windowRect.origin.y = NSMidY(IbeamRect) - NSHeight(windowRect) * 0.5
      } else {
        // horizontally centre-align (MidX) in screen coordinates
        windowRect.origin.x = NSMidX(IbeamRect) - NSWidth(windowRect) * 0.5
        windowRect.origin.y = NSMinY(IbeamRect) - kOffsetGap - NSHeight(windowRect)
      }
    } else {
      if (theme.vertical) { 
        // anchor is the top right corner in screen coordinates (MaxX, MaxY)
        windowRect = NSMakeRect(NSMaxX(frame) - NSHeight(contentRect) - insets.top - insets.bottom,
                                NSMaxY(frame) - NSWidth(contentRect) - insets.left - insets.right,
                                NSHeight(contentRect) + insets.top + insets.bottom,
                                NSWidth(contentRect) + insets.left + insets.right)
        _initPosition = _initPosition || NSIntersectsRect(windowRect, IbeamRect)
        if (_initPosition) {
          if (!sweepVertical) {
            // To avoid jumping up and down while typing, use the lower screen when typing on upper, and vice versa
            if (NSMinY(IbeamRect) - kOffsetGap - NSHeight(screenRect) * textWidthRatio - insets.left - insets.right < NSMinY(screenRect)) {
              windowRect.origin.y = NSMaxY(IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.y = NSMinY(IbeamRect) - kOffsetGap - NSHeight(windowRect)
            }
            // Make the right edge of candidate block fixed at the left of cursor
            windowRect.origin.x = NSMinX(IbeamRect) + insets.top - NSWidth(windowRect)
          } else {
            if (NSMinX(IbeamRect) - kOffsetGap - NSWidth(windowRect) < NSMinX(screenRect)) {
              windowRect.origin.x = NSMaxX(IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.x = NSMinX(IbeamRect) - kOffsetGap - NSWidth(windowRect)
            }
            windowRect.origin.y = NSMinY(IbeamRect) + insets.left - NSHeight(windowRect)
          }
        }
      } else {
        // anchor is the top left corner in screen coordinates (MinX, MaxY)
        windowRect = NSMakeRect(NSMinX(frame),
                                NSMaxY(frame) - NSHeight(contentRect) - insets.top - insets.bottom,
                                NSWidth(contentRect) + insets.left + insets.right,
                                NSHeight(contentRect) + insets.top + insets.bottom)
        _initPosition = _initPosition || NSIntersectsRect(windowRect, IbeamRect)
        if (_initPosition) {
          if (sweepVertical) {
            // To avoid jumping left and right while typing, use the lefter screen when typing on righter, and vice versa
            if (NSMinX(IbeamRect) - kOffsetGap - NSWidth(screenRect) * textWidthRatio - insets.left - insets.right >= NSMinX(screenRect)) {
              windowRect.origin.x = NSMinX(IbeamRect) - kOffsetGap - NSWidth(windowRect)
            } else {
              windowRect.origin.x = NSMaxX(IbeamRect) + kOffsetGap
            }
            windowRect.origin.y = NSMinY(IbeamRect) + insets.top - NSHeight(windowRect)
          } else {
            if (NSMinY(IbeamRect) - kOffsetGap - NSHeight(windowRect) < NSMinY(screenRect)) {
              windowRect.origin.y = NSMaxY(IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.y = NSMinY(IbeamRect) - kOffsetGap - NSHeight(windowRect)
            }
            windowRect.origin.x = NSMaxX(IbeamRect) - insets.left
          }
        }
      }
    }

    if (_view.preeditRange.length > 0) {
      if (_initPosition) {
        _anchorOffset = 0
      }
      if (theme.vertical != sweepVertical) {
        let anchorOffset: Double = NSHeight(_view .blockRect(forRange: _view.preeditRange))
        if (theme.vertical) {
          windowRect.origin.x += anchorOffset - _anchorOffset
        } else {
          windowRect.origin.y += anchorOffset - _anchorOffset
        }
        _anchorOffset = anchorOffset
      }
    }
    if (NSMaxX(windowRect) > NSMaxX(screenRect)) {
      windowRect.origin.x = (_initPosition && sweepVertical ? fmin(NSMinX(IbeamRect) - kOffsetGap, NSMaxX(screenRect)) : NSMaxX(screenRect)) - NSWidth(windowRect)
    }
    if (NSMinX(windowRect) < NSMinX(screenRect)) {
      windowRect.origin.x = _initPosition && sweepVertical ? fmax(NSMaxX(IbeamRect) + kOffsetGap, NSMinX(screenRect)) : NSMinX(screenRect)
    }
    if (NSMinY(windowRect) < NSMinY(screenRect)) {
      windowRect.origin.y = _initPosition && !sweepVertical ? fmax(NSMaxY(IbeamRect) + kOffsetGap, NSMinY(screenRect)) : NSMinY(screenRect)
    }
    if (NSMaxY(windowRect) > NSMaxY(screenRect)) {
      windowRect.origin.y = (_initPosition && !sweepVertical ? fmin(NSMinY(IbeamRect) - kOffsetGap, NSMaxY(screenRect)) : NSMaxY(screenRect)) - NSHeight(windowRect)
    }

    if (theme.vertical) {
      windowRect.origin.x += NSHeight(contentRect) - NSHeight(_view.contentRect)
      windowRect.size.width -= NSHeight(contentRect) - NSHeight(_view.contentRect)
    } else {
      windowRect.origin.y += NSHeight(contentRect) - NSHeight(_view.contentRect)
      windowRect.size.height -= NSHeight(contentRect) - NSHeight(_view.contentRect)
    }
    windowRect = _screen.backingAlignedRect(NSIntersectionRect(windowRect, screenRect), options: .alignAllEdgesNearest)
    setFrame(windowRect, display: true)

    contentView!.setBoundsOrigin(theme.vertical ? NSMakePoint(0.0, NSWidth(windowRect)) : NSZeroPoint)
    let viewRect: NSRect = contentView!.bounds
    _view.frame = viewRect
    _view.textView.frame = NSMakeRect(NSMinX(viewRect) + insets.left - _view.textView.textContainerOrigin.x,
                                      NSMinY(viewRect) + insets.bottom - _view.textView.textContainerOrigin.y,
                                      NSWidth(viewRect) - insets.left - insets.right,
                                      NSHeight(viewRect) - insets.top - insets.bottom)
    if #available(macOS 10.14, *) {
      if (theme.translucency > 0.001) {
        _back!.frame = viewRect
        _back!.isHidden = false
      } else {
        _back!.isHidden = true
      }
    }
    alphaValue = theme.opacity
    orderFront(nil)
    // reset to initial position after showing status message
    _initPosition = statusMessage != nil
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
  func showPreedit(_ preeditString: String?,
                   selRange: NSRange,
                   caretPos: Int,
                   candidateIndices indexRange: Range<Int>,
                   highlightedIndex: Int,
                   pageNum: Int,
                   finalPage: Boolean,
                   didCompose: Boolean) {
    let updateCandidates: Boolean = didCompose || _indexRange != indexRange
    _caretPos = caretPos
    _pageNum = pageNum
    _finalPage = finalPage
    _functionButton = .kVoidSymbol
    if (indexRange.count > 0 || !(preeditString?.isEmpty ?? true)) {
      _statusMessage = nil
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

    let theme: SquirrelTheme = _view.currentTheme
    let contents: NSTextStorage = _view.textStorage
    var rulerAttrsPreedit: NSParagraphStyle?
    let priorSize: NSSize = contents.length > 0 ? _view.contentRect.size : NSZeroSize
    if ((indexRange.count == 0 && preeditString != nil &&
         _view.preeditRange.length > 0) || !updateCandidates) {
      rulerAttrsPreedit = contents.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }
    if (updateCandidates) {
      contents.setAttributedString(NSAttributedString())
      if (theme.lineLength > 0.1) {
        _maxSize.width = min(theme.lineLength, _textWidthLimit)
      }
      _indexRange = indexRange
      _highlightedIndex = highlightedIndex
    }
    var candidateRanges: [SquirrelCandidateRanges] = updateCandidates ? [] : _view.candidateRanges
    var truncated: [Boolean] = updateCandidates ? [] : _view.truncated
    var preeditRange: NSRange = NSMakeRange(NSNotFound, 0)
    var pagingRange: NSRange = NSMakeRange(NSNotFound, 0)
    var candidatesStart: Int = 0
    var pagingStart: Int = 0
    var skipCandidates: Boolean = false

    // preedit
    if (preeditString != nil) {
      let preedit = NSMutableAttributedString.init(string: preeditString!, attributes: theme.preeditAttrs)
      preedit.mutableString.append(rulerAttrsPreedit == nil ? kFullWidthSpace : "\t")
      if (selRange.length > 0) {
        preedit.addAttribute(.foregroundColor, value: theme.hilitedPreeditForeColor, range: selRange)
        let padding: Double = ceil(theme.preeditParagraphStyle.minimumLineHeight * 0.05)
        if (selRange.location > 0) {
          preedit.addAttribute(.kern, value: padding,
                               range: NSMakeRange(selRange.location - 1, 1))
        }
        if (NSMaxRange(selRange) < preedit.length) {
          preedit.addAttribute(.kern, value: padding,
                               range: NSMakeRange(NSMaxRange(selRange) - 1, 1))
        }
      }
      preedit.append(caretPos == NSNotFound || caretPos == 0 ? theme.symbolDeleteStroke! : theme.symbolDeleteFill!)
      // force caret to be rendered sideways, instead of uprights, in vertical orientation
      if (theme.vertical && caretPos != NSNotFound) {
        preedit.addAttribute(.verticalGlyphForm, value: false,
                             range: NSMakeRange(caretPos - (caretPos < NSMaxRange(selRange) ? 1 : 0), 1))
      }
      preeditRange = NSMakeRange(0, preedit.length)
      if (rulerAttrsPreedit != nil) {
        preedit.addAttribute(.paragraphStyle, value: rulerAttrsPreedit!, range: preeditRange)
      }

      if (updateCandidates) {
        contents.append(preedit)
        if (indexRange.count > 0) {
          contents.mutableString.append("\n")
        } else {
          self.sectionNum = 0
          skipCandidates = true
        }
      } else {
        contents.replaceCharacters(in: _view.preeditRange, with: preedit)
        _view.setPreeditRange(preeditRange, hilitedPreeditRange: selRange)
      }
    }

    if (!updateCandidates) {
      if (_highlightedIndex != highlightedIndex) {
        highlightCandidate(highlightedIndex)
      }
      let newSize: NSSize = _view.contentRect.size
      _needsRedraw = _needsRedraw || !NSEqualSizes(priorSize, newSize)
      show()
      return
    }

    // candidate items
    if (!skipCandidates && indexRange.count > 0) {
      candidatesStart = contents.length
      for idx in 0..<indexRange.count {
        let col: Int = idx % theme.pageSize
        let candidate = (idx / theme.pageSize != _sectionNum ? theme.candidateDimmedTemplate!.mutableCopy()
                         : idx == highlightedIndex ? theme.candidateHilitedTemplate.mutableCopy()
                         : theme.candidateTemplate.mutableCopy()) as! NSMutableAttributedString
        // plug in enumerator, candidate text and comment into the template
        let enumRange: NSRange = candidate.mutableString.range(of: "%c")
        candidate.replaceCharacters(in: enumRange, with: theme.labels[col])

        var textRange: NSRange = candidate.mutableString.range(of: "%@")
        let text: String = _inputController!.candidateTexts[idx + indexRange.lowerBound]
        candidate.replaceCharacters(in: textRange, with: _candTexts[idx + indexRange.lowerBound])

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
        if (annotationHeight * 2 > theme.linespace) {
          setAnnotationHeight(annotationHeight)
          candidate.addAttribute(.paragraphStyle,
                                 value: theme.candidateParagraphStyle,
                                 range: NSMakeRange(0, candidate.length))
          if (idx > 0) {
            if (theme.linear) {
              var truncated: Boolean = _view.truncated[0]
              var start: Int = _view.candidateRanges[0].location
              for i in 1..<idx {
                if (i == idx || _view.truncated[i] != truncated) {
                  let end: Int = i == idx ? contents.length : _view.candidateRanges[i].location
                  contents.addAttribute(.paragraphStyle,
                                        value: truncated ? theme.truncatedParagraphStyle! : theme.candidateParagraphStyle,
                                        range: NSMakeRange(start, end - start))
                  start = end
                }
                truncated = _view.truncated[i]
              }
            } else {
              contents.addAttribute(.paragraphStyle,
                                    value: theme.candidateParagraphStyle,
                                    range: NSMakeRange(candidatesStart, contents.length - candidatesStart))
            }
          }
        }
        // store final in-candidate locations of label, text, and comment
        textRange = candidate.mutableString.range(of: text)

        if (idx > 0 && (!theme.linear || _view.truncated[idx - 1])) {
          // separator: linear = "\u3000\x1D"; tabular = "\u3000\t\x1D"; stacked = "\n"
          contents.append(theme.separator)
          if (theme.linear && col == 0) {
            contents.mutableString.append("\n")
          }
        }
        let candidateStart: Int = contents.length
        var ranges = SquirrelCandidateRanges(location: candidateStart,
                                             text: textRange.location,
                                             comment: NSMaxRange(textRange))
        contents.append(candidate)
        // for linear layout, middle-truncate candidates that are longer than one line
        if (theme.linear && ceil(candidate.size().width) > _textWidthLimit - theme.fullWidth * (theme.tabular ? 2 : 1) - 0.1) {
          contents.append(theme.fullWidthPlaceholder)
          truncated.append(true)
          ranges.length = contents.length - candidateStart
          candidateRanges.append(ranges)
          if (idx < indexRange.count - 1 || theme.tabular || theme.showPaging) {
            contents.mutableString.append("\n")
          }
          contents.addAttribute(.paragraphStyle,
                                value: theme.truncatedParagraphStyle!,
                                range: NSMakeRange(candidateStart, contents.length - candidateStart))
        } else {
          truncated.append(false)
          ranges.length = candidate.length + (theme.tabular ? 3 : theme.linear ? 2 : 0)
          candidateRanges.append(ranges)
        }
      }

      // paging indication
      if (theme.tabular || theme.showPaging) {
        var paging: NSMutableAttributedString
        if (theme.tabular) {
          paging = NSMutableAttributedString.init(attributedString: _locked ? theme.symbolLock! : _view.expanded ? theme.symbolCompress! : theme.symbolExpand!)
        } else {
          let pageNumString = NSAttributedString.init(string: String(format: "%lu", pageNum + 1), attributes: theme.pagingAttrs)
          if (theme.vertical) {
            paging = NSMutableAttributedString.init(attributedString: pageNumString.horizontalInVerticalForms())
          } else {
            paging = NSMutableAttributedString.init(attributedString: pageNumString)
          }
        }
        if (theme.showPaging) {
          paging.insert(_pageNum > 0 ? theme.symbolBackFill! : theme.symbolBackStroke!, at: 0)
          paging.mutableString.insert(kFullWidthSpace, at: 1)
          paging.mutableString.append(kFullWidthSpace)
          paging.append(_finalPage ? theme.symbolForwardStroke! : theme.symbolForwardFill!)
        }
        if (!theme.linear || !_view.truncated[indexRange.count - 1]) {
          contents.append(theme.separator)
          if (theme.linear) {
            contents.replaceCharacters(in: NSMakeRange(contents.length, 0), with: "\n")
          }
        }
        pagingStart = contents.length;
        if (theme.linear) {
          contents.append(NSAttributedString(string: kFullWidthSpace, attributes: theme.pagingAttrs))
        }
        contents.append(paging)
        pagingRange = NSMakeRange(contents.length - paging.length, paging.length);
      } else if (theme.linear && !_view.truncated[indexRange.count - 1]) {
        contents.append(theme.separator)
      }
    }

    _view.estimateBounds(forPreedit: preeditRange,
                         candidates: candidateRanges,
                         truncation: truncated,
                         paging: pagingRange)
    let textWidth: Double = min(max(NSMaxX(_view.contentRect) - _view.trailPadding, _maxSize.width), _textWidthLimit)
    // right-align the backward delete symbol
    if (preeditRange.length > 0 &&
        NSMaxX(_view.blockRect(forRange: NSMakeRange(preeditRange.length - 1, 1))) < textWidth - 0.1) {
      contents.replaceCharacters(in: NSMakeRange(preeditRange.length - 2, 1), with: "\t")
      let rulerAttrs: NSMutableParagraphStyle = theme.preeditParagraphStyle as! NSMutableParagraphStyle
      rulerAttrs.tabStops = [NSTextTab.init(textAlignment: .right, location: textWidth)]
      contents.addAttribute(.paragraphStyle,
                            value: rulerAttrs,
                            range: preeditRange)
    }
    if (pagingRange.length > 0 &&
        NSMaxX(_view.blockRect(forRange: pagingRange)) < textWidth - 0.1) {
      let rulerAttrsPaging: NSMutableParagraphStyle = theme.pagingParagraphStyle as! NSMutableParagraphStyle
      if (theme.linear) {
        contents.replaceCharacters(in: NSMakeRange(pagingStart, 1), with: "\t")
        rulerAttrsPaging.tabStops = [NSTextTab.init(textAlignment: .right, location: textWidth)]
      } else {
        contents.replaceCharacters(in: NSMakeRange(pagingStart + 1, 1), with: "\t")
        contents.replaceCharacters(in: NSMakeRange(contents.length - 2, 1), with: "\t")
        rulerAttrsPaging.tabStops = [NSTextTab.init(textAlignment: .center, location: textWidth * 0.5),
                                     NSTextTab.init(textAlignment: .right, location: textWidth)]
      }
      contents.addAttribute(.paragraphStyle,
                            value: rulerAttrsPaging,
                            range: NSMakeRange(pagingStart, contents.length - pagingStart))
    }

    // text done!
    let topMargin: Double = preeditString != nil || theme.linear ? 0.0 : ceil(theme.linespace * 0.5)
    let bottomMargin: Double = !theme.linear && indexRange.count > 0 && pagingRange.length == 0 ? floor(theme.linespace * 0.5) : 0.0
    let insets: NSEdgeInsets = NSEdgeInsetsMake(theme.borderInsets.height + topMargin,
                                                theme.borderInsets.width + ceil(theme.fullWidth * 0.5),
                                                theme.borderInsets.height + bottomMargin,
                                                theme.borderInsets.width + floor(theme.fullWidth * 0.5))

    animationBehavior = caretPos == NSNotFound ? .utilityWindow : .default
    _view.drawView(withInsets: insets,
                   hilitedIndex: highlightedIndex,
                   hilitedPreeditRange: selRange)

    let newSize: NSSize = _view.contentRect.size
    _needsRedraw = _needsRedraw || !NSEqualSizes(priorSize, newSize)
    show()
  }

  func updateStatus(long: String?,
                    short: String?) {
    switch (_view.currentTheme.statusMessageType) {
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
    let theme: SquirrelTheme! = _view.currentTheme
    let contents: NSTextStorage! = _view.textStorage
    let priorSize: NSSize = contents.length > 0 ? _view.contentRect.size : NSZeroSize

    contents.setAttributedString(NSAttributedString(string: String(format:"\u{3000}\u{2002}%@", message),
                                                    attributes: theme.statusAttrs))

    _view.estimateBounds(forPreedit: NSMakeRange(NSNotFound, 0),
                         candidates: [],
                         truncation: [],
                         paging: NSMakeRange(NSNotFound, 0))
    let insets: NSEdgeInsets = NSEdgeInsetsMake(theme.borderInsets.height,
                                                theme.borderInsets.width + ceil(theme.fullWidth * 0.5),
                                                theme.borderInsets.height,
                                                theme.borderInsets.width + floor(theme.fullWidth * 0.5))

    // disable remember_size and fixed line_length for status messages
    _initPosition = true
    _maxSize = NSZeroSize
    _statusTimer?.invalidate()
    animationBehavior = .utilityWindow
    _view.drawView(withInsets: insets,
                   hilitedIndex: NSNotFound,
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
                                               forAppearance: .defaultAppear)
    if #available(macOS 10.14, *) {
      SquirrelView.darkTheme.updateWithConfig(config, styleOptions: optionSwitcher.optionStates,
                                              scriptVariant: optionSwitcher.currentScriptVariant,
                                              forAppearance: .darkAppear)
    }
    getLocker()
    updateDisplayParameters()
  }

  func updateScriptVariant() {
    SquirrelView.defaultTheme.setScriptVariant(optionSwitcher.currentScriptVariant)
  }
}  // SquirrelPanel

