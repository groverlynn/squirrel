import Cocoa
import QuartzCore


enum SquirrelAppear: Int {
  case defaultAppear = 0
  case darkAppear = 1
}

let kOffsetGap: Double = 5
let kDefaultFontSize: Double  = 24
let kBlendedBackgroundColorFraction: Double  = 1.0 / 5
let kShowStatusDuration: TimeInterval = 2.0
let kDefaultCandidateFormat: String  = "%c. %@"
let kTipSpecifier: String = "%s"
let kFullWidthSpace: String  = "　"

fileprivate extension NSBezierPath {

  func quartzPath() -> CGPath? {
    if #available(macOS 14.0, *) {
      return self.cgPath
    }
    // Need to begin a path here.
    let path: CGMutablePath = CGMutablePath()
    // Then draw the path elements.
    if elementCount > 0 {
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

}  // NSBezierPath (BezierPathQuartzUtilities)

let kMarkDownPattern:String! = "((\\*{1,2}|\\^|~{1,2})|((?<=\\b)_{1,2})|<(b|strong|i|em|u|sup|sub|s)>)(.+?)(\\2|\\3(?=\\b)|<\\/\\4>)"
let kRubyPattern:String! = "(\u{FFF9}\\s*)(\\S+?)(\\s*\u{FFFA}(.+?)\u{FFFB})"

fileprivate extension NSMutableAttributedString {

  func superscriptRange(_ range: NSRange) {
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

  func subscriptRange(_ range: NSRange) {
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

  func formatMarkDown() {
    if let regex = try? NSRegularExpression.init(pattern: kMarkDownPattern,
                                                 options: .useUnicodeWordBoundaries) {
      var offset: Int = 0
      regex.enumerateMatches(in: string,
                             options: .init(),
                             range: NSMakeRange(0, length),
                             using:{ (result: NSTextCheckingResult?,
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
            superscriptRange(adjusted.range(at: 5))
          } else if (tag == "~") || (tag == "<sub>") {
            subscriptRange(adjusted.range(at: 5))
          }
          deleteCharacters(in: adjusted.range(at: 6))
          deleteCharacters(in: adjusted.range(at: 1))
          offset -= adjusted.range(at: 6).length + adjusted.range(at: 1).length
        }
     })
     if offset != 0 { // repeat until no more nested markdown
       formatMarkDown()
     }
    }
  }

  func annotateRuby(inRange range: NSRange,
                    verticalOrientation isVertical: Boolean,
                    maximumLength maxLength: Double) -> Double {
    var rubyLineHeight: Double = 0.0
    if let regex = try? NSRegularExpression(pattern: kRubyPattern, options: .init()) {
      regex.enumerateMatches(in: string,
                             options: .init(),
                             range: range,
                             using: { (result: NSTextCheckingResult?,
                                       flags: NSRegularExpression.MatchingFlags,
                                       stop: UnsafeMutablePointer<ObjCBool>) in
        var baseRange: NSRange = (result!.range(at: 2))
        // no ruby annotation if the base string includes line breaks
        if attributedSubstring(from: NSMakeRange(0, NSMaxRange(baseRange))).size().width > maxLength - 0.1 {
          deleteCharacters(in: NSMakeRange(NSMaxRange(result!.range) - 1, 1))
          deleteCharacters(in: NSMakeRange(result!.range(at: 3).location, 1))
          deleteCharacters(in: NSMakeRange(result!.range(at: 1).location, 1))
        } else {
          // base string must use only one font so that all fall within one glyph run and
          // the ruby annotation is aligned with no duplicates
          var baseFont: NSFont! = attribute(NSAttributedString.Key.font, at: baseRange.location, effectiveRange:nil) as? NSFont
          baseFont = CTFontCreateForStringWithLanguage(baseFont as CTFont, mutableString as CFString, CFRangeMake(baseRange.location, baseRange.length), "zh" as CFString) as NSFont
          addAttribute(NSAttributedString.Key.font, value: baseFont!, range: baseRange)

          let rubyScale: Double = 0.5
          let rubyString: CFString = mutableString.substring(with: result!.range(at: 4)) as CFString
          let height: Double = isVertical ? (baseFont.vertical.ascender - baseFont.vertical.descender) : (baseFont.ascender - baseFont.descender)
          rubyLineHeight = max(rubyLineHeight, ceil(height * 0.5))
          let rubyText = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: Int(CTRubyPosition.count.rawValue))
          rubyText[Int(CTRubyPosition.before.rawValue)] = Unmanaged.passUnretained(rubyString)
          rubyText[Int(CTRubyPosition.after.rawValue)] = nil
          rubyText[Int(CTRubyPosition.interCharacter.rawValue)] = nil
          rubyText[Int(CTRubyPosition.inline.rawValue)] = nil
          let rubyAnnotation: CTRubyAnnotation = CTRubyAnnotationCreate(.distributeSpace, .none, rubyScale, rubyText)

          if #available(macOS 12.0, *) {
            addAttributes([kCTRubyAnnotationAttributeName as NSAttributedString.Key: rubyAnnotation], range: baseRange)
          } else {
            // use U+008B as placeholder for line-forward spaces in case ruby is wider than base
            replaceCharacters(in: NSMakeRange(NSMaxRange(baseRange), 0), with: String(format:"%C", 0x8B))
            addAttributes([kCTRubyAnnotationAttributeName as NSAttributedString.Key: rubyAnnotation,
                           NSAttributedString.Key.verticalGlyphForm: isVertical],
                          range: baseRange)
          }
        }
      })
      mutableString.replaceOccurrences(of: "[\u{FFF9}-\u{FFFB}]", with: "", options: .regularExpression, range: range)
    }
    return ceil(rubyLineHeight)
  }

}  // NSMutableAttributedString (NSMutableAttributedStringMarkDownFormatting)


fileprivate extension NSColorSpace {

  class func labColorSpace() -> NSColorSpace! {
    var whitePoint: [CGFloat] = [0.950489, 1.0, 1.088840]
    var blackPoint: [CGFloat] = [0.0, 0.0, 0.0]
    var range: [CGFloat] = [-127.0, 127.0, -127.0, 127.0]
    let colorSpaceLab: CGColorSpace = CGColorSpace(labWhitePoint: &whitePoint, blackPoint: &blackPoint, range: &range)!
    let labColorSpace: NSColorSpace = NSColorSpace(cgColorSpace: colorSpaceLab)!
    return labColorSpace
  }

}  // NSColorSpace (labColorSpace)


fileprivate extension NSColor {

  class func colorWithLabLuminance(luminance: Double, a: Double, b: Double, alpha: Double) -> NSColor {
    let lum: Double = max(min(luminance, 100.0), 0.0)
    let green_red: Double = max(min(a, 127.0), -127.0)
    let blue_yellow: Double = max(min(b, 127.0), -127.0)
    let opaque: Double = max(min(alpha, 1.0), 0.0)
    let components: [CGFloat] = [lum, green_red, blue_yellow, opaque]
    return NSColor(colorSpace: NSColorSpace.labColorSpace(), components: components, count: 4)
  }

  func getLuminance(luminance: inout Double, a: inout Double, b: inout Double, alpha: inout Double) {
    let labColor: NSColor = usingColorSpace(NSColorSpace.labColorSpace())!
    var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
    labColor.getComponents(&components)
    luminance = components[0] / 100.0
    a = components[1] / 127.0 // green-red
    b = components[2] / 127.0 // blue-yellow
    alpha = components[3]
  }

  func luminanceComponent() -> Double {
    let labColor: NSColor = usingColorSpace(NSColorSpace.labColorSpace())!
    var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
    labColor.getComponents(&components)
    return components[0] / 100.0
  }

  func invertLuminance(withAdjustment sign: Int) -> NSColor {
    let labColor: NSColor = usingColorSpace(NSColorSpace.labColorSpace())!
    var components: [CGFloat] = [0.0, 0.0, 0.0, 1.0]
    labColor.getComponents(&components)
    let isDark: Boolean = components[0] < 60
    if sign > 0 {
      components[0] = isDark ? 100.0 - components[0] * 2.0 / 3.0 : 150.0 - components[0] * 1.5
    } else if sign < 0 {
      components[0] = isDark ? 80.0 - components[0] / 3.0 : 135.0 - components[0] * 1.25
    } else {
      components[0] = isDark ? 90.0 - components[0] / 2.0 : 120.0 - components[0]
    }
    let invertedColor: NSColor = NSColor(colorSpace: NSColorSpace.labColorSpace(), components: components, count: 4)
    return invertedColor.usingColorSpace(colorSpace)!
  }

  // semantic colors
  class func secondaryTextColor() -> NSColor! {
    if #available(macOS 10.10, *) {
      return NSColor.secondaryLabelColor
    } else {
      return NSColor.disabledControlTextColor
    }
  }

  class func accentColor() -> NSColor! {
    if #available(macOS 10.14, *) {
      return NSColor.controlAccentColor
    } else {
      return NSColor(for: NSColor.currentControlTint)
    }
  }

}  // NSColor (colorWithLabColorSpace)

// MARK: - Color scheme and other user configurations

fileprivate enum SquirrelStatusMessageType {
  case mixed
  case short
  case long
}

fileprivate func blendColors(foreground: NSColor!, background: NSColor?) -> NSColor! {
  return foreground.blended(withFraction: kBlendedBackgroundColorFraction,
                            of: background ?? NSColor.lightGray)!.withAlphaComponent(foreground.alphaComponent)
}

fileprivate func getFontDescriptor(fullname: String!) -> NSFontDescriptor? {
  if fullname.isEmpty {
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
  if validFontDescriptors.count == 0 {
    return nil
  }
  let initialFontDescriptor: NSFontDescriptor! = validFontDescriptors[0]
  var fallbackDescriptors: [NSFontDescriptor]! = validFontDescriptors.suffix(validFontDescriptors.count - 1)
  fallbackDescriptors.append(NSFontDescriptor(name:"AppleColorEmoji", size:0.0))
  return initialFontDescriptor.addingAttributes([NSFontDescriptor.AttributeName.cascadeList : fallbackDescriptors as Any])
}

fileprivate func getLineHeight(font: NSFont!,
                               vertical: Boolean) -> Double {
  var lineHeight: Double = ceil(vertical ? font.vertical.ascender - font.vertical.descender : font.ascender - font.descender)
  let fallbackList: [NSFontDescriptor]! = font.fontDescriptor.fontAttributes[NSFontDescriptor.AttributeName.cascadeList] as? [NSFontDescriptor]
  for fallback: NSFontDescriptor in fallbackList {
    let fallbackFont: NSFont! = NSFont(descriptor: fallback, size: font.pointSize)
    lineHeight = max(lineHeight, ceil(vertical ? fallbackFont.vertical.ascender - fallbackFont.vertical.descender
                                               : fallbackFont.ascender - fallbackFont.descender))
  }
  return lineHeight
}

fileprivate class SquirrelTheme : NSObject {

  private var _backColor: NSColor!
  fileprivate var backColor: NSColor! {
    get { return _backColor }
  }
  private var _highlightedCandidateBackColor: NSColor?
  fileprivate var highlightedCandidateBackColor: NSColor? {
    get { return _highlightedCandidateBackColor }
  }
  private var _highlightedPreeditBackColor: NSColor?
  fileprivate var highlightedPreeditBackColor: NSColor? {
    get { return _highlightedPreeditBackColor }
  }
  private var _preeditBackColor: NSColor?
  fileprivate var preeditBackColor: NSColor? {
    get { return _preeditBackColor }
  }
  private var _borderColor: NSColor?
  fileprivate var borderColor: NSColor? {
    get { return _borderColor }
  }
  private var _backImage: NSImage?
  fileprivate var backImage: NSImage? {
    get { return _backImage }
  }
  private var _cornerRadius: Double
  fileprivate var cornerRadius: Double {
    get { return _cornerRadius }
  }
  private var _highlightedCornerRadius: Double
  fileprivate var highlightedCornerRadius: Double {
    get { return _highlightedCornerRadius }
  }
  private var _separatorWidth: Double
  fileprivate var separatorWidth: Double {
    get { return _separatorWidth }
  }
  private var _linespace: Double
  fileprivate var linespace: Double {
    get { return _linespace }
  }
  private var _preeditLinespace: Double
  fileprivate var preeditLinespace: Double {
    get { return _preeditLinespace }
  }
  private var _alpha: Double
  fileprivate var alpha: Double {
    get { return _alpha }
  }
  private var _translucency: Double
  fileprivate var translucency: Double {
    get { return _translucency }
  }
  private var _lineLength: Double
  fileprivate var lineLength: Double {
    get { return _lineLength }
  }
  private var _expanderWidth: Double = 0
  fileprivate var expanderWidth: Double {
    get { return _expanderWidth }
  }
  private var _borderInset: NSSize
  fileprivate var borderInset: NSSize {
    get { return _borderInset }
  }
  private var _showPaging: Boolean
  fileprivate var showPaging: Boolean {
    get { return _showPaging }
  }
  private var _rememberSize: Boolean
  fileprivate var rememberSize: Boolean {
    get { return _rememberSize }
  }
  private var _tabular: Boolean
  fileprivate var tabular: Boolean {
    get { return _tabular }
  }
  private var _linear: Boolean
  fileprivate var linear: Boolean {
    get { return _linear }
  }
  private var _vertical: Boolean
  fileprivate var vertical: Boolean {
    get { return _vertical }
  }
  private var _inlinePreedit: Boolean
  fileprivate var inlinePreedit: Boolean {
    get { return _inlinePreedit }
  }
  private var _inlineCandidate: Boolean
  fileprivate var inlineCandidate: Boolean {
    get { return _inlineCandidate }
  }
  private var _attrs: [NSAttributedString.Key : Any]
  fileprivate var attrs: [NSAttributedString.Key : Any] {
    get { return _attrs }
  }
  private var _highlightedAttrs: [NSAttributedString.Key : Any]
  fileprivate var highlightedAttrs: [NSAttributedString.Key : Any] {
    get { return _highlightedAttrs }
  }
  private var _labelAttrs: [NSAttributedString.Key : Any]
  fileprivate var labelAttrs: [NSAttributedString.Key : Any] {
    get { return _labelAttrs }
  }
  private var _labelHighlightedAttrs: [NSAttributedString.Key : Any]
  fileprivate var labelHighlightedAttrs: [NSAttributedString.Key : Any] {
    get { return _labelHighlightedAttrs }
  }
  private var _commentAttrs: [NSAttributedString.Key : Any]
  fileprivate var commentAttrs: [NSAttributedString.Key : Any] {
    get { return _commentAttrs }
  }
  private var _commentHighlightedAttrs: [NSAttributedString.Key : Any]
  fileprivate var commentHighlightedAttrs: [NSAttributedString.Key : Any] {
    get { return _commentHighlightedAttrs }
  }
  private var _preeditAttrs: [NSAttributedString.Key : Any]
  fileprivate  var preeditAttrs: [NSAttributedString.Key : Any] {
    get { return _preeditAttrs }
  }
  private var _preeditHighlightedAttrs: [NSAttributedString.Key : Any]
  fileprivate var preeditHighlightedAttrs: [NSAttributedString.Key : Any] {
    get { return _preeditHighlightedAttrs }
  }
  private var _pagingAttrs: [NSAttributedString.Key : Any]
  fileprivate var pagingAttrs: [NSAttributedString.Key : Any] {
    get { return _pagingAttrs }
  }
  private var _pagingHighlightedAttrs: [NSAttributedString.Key : Any]
  fileprivate var pagingHighlightedAttrs: [NSAttributedString.Key : Any] {
    get { return _pagingHighlightedAttrs }
  }
  private var _statusAttrs: [NSAttributedString.Key : Any]
  fileprivate var statusAttrs: [NSAttributedString.Key : Any] {
    get { return _statusAttrs }
  }
  private var _paragraphStyle: NSParagraphStyle
  fileprivate var paragraphStyle: NSParagraphStyle {
    get { return _paragraphStyle }
  }
  private var _preeditParagraphStyle: NSParagraphStyle
  fileprivate var preeditParagraphStyle: NSParagraphStyle {
    get { return _preeditParagraphStyle }
  }
  private var _pagingParagraphStyle: NSParagraphStyle
  fileprivate var pagingParagraphStyle: NSParagraphStyle {
    get { return _pagingParagraphStyle }
  }
  private var _statusParagraphStyle: NSParagraphStyle
  fileprivate var statusParagraphStyle: NSParagraphStyle {
    get { return _statusParagraphStyle }
  }
  private var _separator: NSAttributedString
  fileprivate var separator: NSAttributedString {
    get { return _separator }
  }
  private var _symbolDeleteFill: NSAttributedString?
  fileprivate var symbolDeleteFill: NSAttributedString? {
    get { return _symbolDeleteFill }
  }
  private var _symbolDeleteStroke: NSAttributedString?
  fileprivate var symbolDeleteStroke: NSAttributedString? {
    get { return _symbolDeleteStroke }
  }
  private var _symbolBackFill: NSAttributedString?
  fileprivate var symbolBackFill: NSAttributedString? {
    get { return _symbolBackFill }
  }
  private var _symbolBackStroke: NSAttributedString?
  fileprivate var symbolBackStroke: NSAttributedString? {
    get { return _symbolBackStroke }
  }
  private var _symbolForwardFill: NSAttributedString?
  fileprivate var symbolForwardFill: NSAttributedString? {
    get { return _symbolForwardFill }
  }
  private var _symbolForwardStroke: NSAttributedString?
  fileprivate var symbolForwardStroke: NSAttributedString? {
    get { return _symbolForwardStroke }
  }
  private var _symbolCompress: NSAttributedString?
  fileprivate var symbolCompress: NSAttributedString? {
    get { return _symbolCompress }
  }
  private var _symbolExpand: NSAttributedString?
  fileprivate var symbolExpand: NSAttributedString? {
    get { return _symbolExpand }
  }
  private var _symbolLock: NSAttributedString?
  fileprivate var symbolLock: NSAttributedString? {
    get { return _symbolLock }
  }
  private var _selectKeys: String
  fileprivate var selectKeys: String {
    get { return _selectKeys }
  }
  private var _candidateFormat: String
  fileprivate var candidateFormat: String {
    get { return _candidateFormat }
  }
  private var _labels: [String]
  fileprivate var labels: [String] {
    get { return _labels }
  }
  private var _candidateFormats: [NSAttributedString] = []
  fileprivate var candidateFormats: [NSAttributedString] {
    get { return _candidateFormats }
  }
  private var _candidateHighlightedFormats: [NSAttributedString] = []
  fileprivate var candidateHighlightedFormats: [NSAttributedString] {
    get { return _candidateHighlightedFormats }
  }
  private var _statusMessageType: SquirrelStatusMessageType
  fileprivate var statusMessageType: SquirrelStatusMessageType {
    get { return _statusMessageType }
  }
  private var _pageSize: Int
  fileprivate var pageSize: Int {
    get { return _pageSize }
  }

  override init() {
    let paragraphStyle:NSMutableParagraphStyle! = NSMutableParagraphStyle()
    paragraphStyle.alignment = .left
    // Use left-to-right marks to declare the default writing direction and prevent strong right-to-left
    // characters from setting the writing direction in case the label are direction-less symbols
    paragraphStyle.baseWritingDirection = .leftToRight

    let preeditParagraphStyle: NSMutableParagraphStyle! = paragraphStyle
    let pagingParagraphStyle: NSMutableParagraphStyle! = paragraphStyle
    let statusParagraphStyle: NSMutableParagraphStyle! = paragraphStyle

    preeditParagraphStyle.lineBreakMode = .byWordWrapping
    statusParagraphStyle.lineBreakMode = .byTruncatingTail

    let userFont: NSFont! = NSFont(descriptor: getFontDescriptor(fullname:NSFont.userFont(ofSize: 0.0)!.fontName)!,
                                   size: kDefaultFontSize)
    let userMonoFont: NSFont! = NSFont(descriptor: getFontDescriptor(fullname:NSFont.userFixedPitchFont(ofSize: 0.0)!.fontName)!,
                                       size: kDefaultFontSize)
    let monoDigitFont: NSFont! = NSFont.monospacedDigitSystemFont(ofSize: kDefaultFontSize, weight: .regular)

    var attrs: [NSAttributedString.Key : Any]! = [:]
    attrs[NSAttributedString.Key.foregroundColor] = NSColor.controlTextColor
    attrs[NSAttributedString.Key.font] = userFont
    // Use left-to-right embedding to prevent right-to-left text from changing the layout of the candidate.
    attrs[NSAttributedString.Key.writingDirection] = [0]

    var highlightedAttrs: [NSAttributedString.Key : Any]! = attrs
    highlightedAttrs[NSAttributedString.Key.foregroundColor] = NSColor.selectedMenuItemTextColor

    var labelAttrs: [NSAttributedString.Key : Any]! = attrs
    labelAttrs[NSAttributedString.Key.foregroundColor] = NSColor.accentColor()
    labelAttrs[NSAttributedString.Key.font] = userMonoFont

    var labelHighlightedAttrs: [NSAttributedString.Key : Any]! = labelAttrs
    labelHighlightedAttrs[NSAttributedString.Key.foregroundColor] = NSColor.alternateSelectedControlTextColor

    var commentAttrs: [NSAttributedString.Key : Any]! = [:]
    commentAttrs[NSAttributedString.Key.foregroundColor] = NSColor.secondaryTextColor()
    commentAttrs[NSAttributedString.Key.font] = userFont

    var commentHighlightedAttrs: [NSAttributedString.Key : Any]! = commentAttrs
    commentHighlightedAttrs[NSAttributedString.Key.foregroundColor] = NSColor.alternateSelectedControlTextColor

    var preeditAttrs: [NSAttributedString.Key : Any]! = [:]
    preeditAttrs[NSAttributedString.Key.foregroundColor] = NSColor.textColor
    preeditAttrs[NSAttributedString.Key.font] = userFont
    preeditAttrs[NSAttributedString.Key.ligature] = 0
    preeditAttrs[NSAttributedString.Key.paragraphStyle] = preeditParagraphStyle

    var preeditHighlightedAttrs: [NSAttributedString.Key : Any]! = [:]
    preeditHighlightedAttrs[NSAttributedString.Key.foregroundColor] = NSColor.selectedTextColor

    var pagingAttrs: [NSAttributedString.Key : Any]! = [:]
    pagingAttrs[NSAttributedString.Key.font] = monoDigitFont
    pagingAttrs[NSAttributedString.Key.foregroundColor] = NSColor.controlTextColor

    var pagingHighlightedAttrs: [NSAttributedString.Key : Any]! = pagingAttrs
    pagingHighlightedAttrs[NSAttributedString.Key.foregroundColor] = NSColor.selectedMenuItemTextColor

    var statusAttrs: [NSAttributedString.Key : Any]! = commentAttrs
    statusAttrs[NSAttributedString.Key.paragraphStyle] = statusParagraphStyle

    _attrs = attrs
    _highlightedAttrs = highlightedAttrs
    _labelAttrs = labelAttrs
    _labelHighlightedAttrs = labelHighlightedAttrs
    _commentAttrs = commentAttrs
    _commentHighlightedAttrs = commentHighlightedAttrs
    _preeditAttrs = preeditAttrs
    _preeditHighlightedAttrs = preeditHighlightedAttrs
    _pagingAttrs = pagingAttrs
    _pagingHighlightedAttrs = pagingHighlightedAttrs
    _statusAttrs = statusAttrs

    _backColor = NSColor.controlBackgroundColor
    _separator = NSAttributedString(string: kFullWidthSpace, attributes: [NSAttributedString.Key.font : userFont!])
    _separatorWidth = ceil(_separator.size().width)
    _cornerRadius = 10
    _highlightedCornerRadius = 0
    _linespace = 5
    _preeditLinespace = 10
    _alpha = 1
    _translucency = 0
    _lineLength = 0
    _borderInset = NSZeroSize
    _showPaging = false
    _rememberSize = false
    _tabular = false
    _linear = false
    _vertical = false
    _inlinePreedit = true
    _inlineCandidate = false

    _paragraphStyle = paragraphStyle
    _preeditParagraphStyle = preeditParagraphStyle
    _pagingParagraphStyle = pagingParagraphStyle
    _statusParagraphStyle = statusParagraphStyle

    _selectKeys = "12345"
    _labels = ["１", "２", "３", "４", "５"]
    _pageSize = 5
    _candidateFormat = kDefaultCandidateFormat
    _statusMessageType = .mixed

    super.init()
    updateCandidateFormats()
    updateSeperatorAndSymbolAttrs()
  }

  func setColors(backColor: NSColor!,
                 highlightedCandidateBackColor: NSColor?,
                 highlightedPreeditBackColor: NSColor?,
                 preeditBackColor: NSColor?,
                 borderColor: NSColor?,
                 backImage: NSImage?) {
    _backColor = backColor
    _highlightedCandidateBackColor = highlightedCandidateBackColor
    _highlightedPreeditBackColor = highlightedPreeditBackColor
    _preeditBackColor = preeditBackColor
    _borderColor = borderColor
    _backImage = backImage
  }

  func setScalars(cornerRadius: Double,
                  highlightedCornerRadius: Double,
                  separatorWidth: Double,
                  linespace: Double,
                  preeditLinespace: Double,
                  alpha: Double,
                  translucency: Double,
                  lineLength: Double,
                  borderInset: NSSize,
                  showPaging: Boolean,
                  rememberSize: Boolean,
                  tabular: Boolean,
                  linear: Boolean,
                  vertical: Boolean,
                  inlinePreedit: Boolean,
                  inlineCandidate: Boolean) {
    _cornerRadius = cornerRadius
    _highlightedCornerRadius = highlightedCornerRadius
    _separatorWidth = separatorWidth
    _linespace = linespace
    _preeditLinespace = preeditLinespace
    _alpha = alpha
    _translucency = translucency
    _lineLength = lineLength
    _borderInset = borderInset
    _showPaging = showPaging
    _rememberSize = rememberSize
    _tabular = tabular
    _linear = linear
    _vertical = vertical
    _inlinePreedit = inlinePreedit
    _inlineCandidate = inlineCandidate
  }

  func setAttributes(attrs: [NSAttributedString.Key : Any],
                     highlightedAttrs: [NSAttributedString.Key : Any],
                     labelAttrs: [NSAttributedString.Key : Any],
                     labelHighlightedAttrs: [NSAttributedString.Key : Any],
                     commentAttrs: [NSAttributedString.Key : Any],
                     commentHighlightedAttrs: [NSAttributedString.Key : Any],
                     preeditAttrs: [NSAttributedString.Key : Any],
                     preeditHighlightedAttrs: [NSAttributedString.Key : Any],
                     pagingAttrs: [NSAttributedString.Key : Any],
                     pagingHighlightedAttrs: [NSAttributedString.Key : Any],
                     statusAttrs: [NSAttributedString.Key : Any]) {
    _attrs = attrs
    _highlightedAttrs = highlightedAttrs
    _labelAttrs = labelAttrs
    _labelHighlightedAttrs = labelHighlightedAttrs
    _commentAttrs = commentAttrs
    _commentHighlightedAttrs = commentHighlightedAttrs
    _preeditAttrs = preeditAttrs
    _preeditHighlightedAttrs = preeditHighlightedAttrs
    _pagingAttrs = pagingAttrs
    _pagingHighlightedAttrs = pagingHighlightedAttrs
    _statusAttrs = statusAttrs
  }

  func updateSeperatorAndSymbolAttrs() {
    var sepAttrs: [NSAttributedString.Key : Any]! = _commentAttrs
    sepAttrs[NSAttributedString.Key.verticalGlyphForm] = false
    sepAttrs[NSAttributedString.Key.kern] = 0.0
    _separator = NSAttributedString(string: _linear ? (_tabular ? kFullWidthSpace + "\t" : kFullWidthSpace) : "\n",
                                    attributes: sepAttrs)

    // Symbols for function buttons
    let attmCharacter: String! = String(NSTextAttachment.character)

    let attmDeleteFill: NSTextAttachment! = NSTextAttachment()
    attmDeleteFill.image = NSImage(named: "Symbols/delete.backward.fill")
    var attrsDeleteFill: [NSAttributedString.Key : Any]! = _preeditAttrs
    attrsDeleteFill[NSAttributedString.Key.attachment] = attmDeleteFill
    attrsDeleteFill[NSAttributedString.Key.verticalGlyphForm] = false
    _symbolDeleteFill = NSAttributedString(string: attmCharacter, attributes: attrsDeleteFill)

    let attmDeleteStroke: NSTextAttachment! = NSTextAttachment()
    attmDeleteStroke.image = NSImage(named: "Symbols/delete.backward")
    var attrsDeleteStroke: [NSAttributedString.Key : Any]! = _preeditAttrs
    attrsDeleteStroke[NSAttributedString.Key.attachment] = attmDeleteStroke
    attrsDeleteStroke[NSAttributedString.Key.verticalGlyphForm] = false
    _symbolDeleteStroke = NSAttributedString(string: attmCharacter, attributes: attrsDeleteStroke)
    if _tabular {
      let attmCompress: NSTextAttachment! = NSTextAttachment()
      attmCompress.image = NSImage(named: "Symbols/chevron.up")
      var attrsCompress: [NSAttributedString.Key : Any]! = _pagingAttrs
      attrsCompress[NSAttributedString.Key.attachment] = attmCompress
      _symbolCompress = NSAttributedString(string: attmCharacter, attributes: attrsCompress)

      let attmExpand:NSTextAttachment! = NSTextAttachment()
      attmExpand.image = NSImage(named: "Symbols/chevron.down")
      var attrsExpand:[NSAttributedString.Key : Any]! = _pagingAttrs
      attrsExpand[NSAttributedString.Key.attachment] = attmExpand
      _symbolExpand = NSAttributedString(string: attmCharacter, attributes: attrsExpand)

      let attmLock: NSTextAttachment! = NSTextAttachment()
      attmLock.image = NSImage(named: String(format: "Symbols/lock%@.fill", _vertical ? ".vertical" : ""))
      var attrsLock: [NSAttributedString.Key : Any]! = _pagingAttrs
      attrsLock[NSAttributedString.Key.attachment] = attmLock
      _symbolLock = NSAttributedString(string: attmCharacter, attributes: attrsLock)

      _expanderWidth = max(max(ceil(_symbolCompress!.size().width), ceil(_symbolExpand!.size().width)),
                           ceil(_symbolLock!.size().width))
      let paragraphStyle: NSMutableParagraphStyle = _paragraphStyle as! NSMutableParagraphStyle
      paragraphStyle.tailIndent = -_expanderWidth
      _paragraphStyle = paragraphStyle as NSParagraphStyle
    } else if _showPaging {
      let attmBackFill: NSTextAttachment! = NSTextAttachment()
      attmBackFill.image = NSImage(named: String(format: "Symbols/chevron.%@.circle.fill", _linear ? "up" : "left"))
      var attrsBackFill: [NSAttributedString.Key : Any]! = _pagingAttrs
      attrsBackFill[NSAttributedString.Key.attachment] = attmBackFill
      _symbolBackFill = NSAttributedString(string: attmCharacter, attributes: attrsBackFill)

      let attmBackStroke:NSTextAttachment! = NSTextAttachment()
      attmBackStroke.image = NSImage(named: String(format: "Symbols/chevron.%@.circle", _linear ? "up" : "left"))
      var attrsBackStroke: [NSAttributedString.Key : Any]! = _pagingAttrs
      attrsBackStroke[NSAttributedString.Key.attachment] = attmBackStroke
      _symbolBackStroke = NSAttributedString(string: attmCharacter, attributes: attrsBackStroke)

      let attmForwardFill:NSTextAttachment! = NSTextAttachment()
      attmForwardFill.image = NSImage(named: String(format: "Symbols/chevron.%@.circle.fill", _linear ? "down" : "right"))
      var attrsForwardFill:[NSAttributedString.Key : Any]! = _pagingAttrs
      attrsForwardFill[NSAttributedString.Key.attachment] = attmForwardFill
      _symbolForwardFill = NSAttributedString(string: attmCharacter, attributes: attrsForwardFill)

      let attmForwardStroke: NSTextAttachment! = NSTextAttachment()
      attmForwardStroke.image = NSImage(named: String(format: "Symbols/chevron.%@.circle", _linear ? "down" : "right"))
      var attrsForwardStroke: [NSAttributedString.Key : Any]! = _pagingAttrs
      attrsForwardStroke[NSAttributedString.Key.attachment] = attmForwardStroke
      _symbolForwardStroke = NSAttributedString(string: attmCharacter, attributes: attrsForwardStroke)
    }
  }

  func setRulerStyles(paragraphStyle:NSParagraphStyle,
                      preeditParagraphStyle:NSParagraphStyle,
                      pagingParagraphStyle:NSParagraphStyle,
                      statusParagraphStyle:NSParagraphStyle) {
    _paragraphStyle = paragraphStyle
    _preeditParagraphStyle = preeditParagraphStyle
    _pagingParagraphStyle = pagingParagraphStyle
    _statusParagraphStyle = statusParagraphStyle
  }

  func setSelectKeys(_ selectKeys: String,
                     labels: [String],
                     directUpdate update: Boolean) {
    _selectKeys = selectKeys
    _labels = labels
    _pageSize = labels.count
    if update {
      updateCandidateFormats()
    }
  }

  func setCandidateFormat(_ candidateFormat: String) {
    _candidateFormat = candidateFormat;
    updateCandidateFormats()
    updateSeperatorAndSymbolAttrs()
  }

  func updateCandidateFormats() {
    // validate candidate format: must have enumerator '%c' before candidate '%@'
    var candidateFormat: String! = _candidateFormat
    var candidateRange: Range<String.Index>? = candidateFormat.range(of: "%@", options: .literal)
    if candidateRange == nil {
      candidateFormat += "%@"
    }
    var labelRange:Range<String.Index>? = candidateFormat.range(of: "%c", options: .literal)
    if labelRange == nil {
      candidateFormat = "%c" + candidateFormat
      labelRange = candidateFormat.range(of: "%c", options: .literal)
    }
    candidateRange = candidateFormat.range(of: "%@", options: .literal)
    if labelRange?.lowerBound ?? candidateFormat.startIndex >= candidateRange?.upperBound ?? candidateFormat.startIndex {
      candidateFormat = kDefaultCandidateFormat
    }
    var labels: [String] = _labels
    var enumRange: Range<String.Index>?
    let labelCharacters: CharacterSet! = CharacterSet.init(charactersIn: labels.joined())
    if CharacterSet.init(charactersIn: Unicode.Scalar(UInt16(0xFF10))!...Unicode.Scalar(UInt16(0xFF19))!).isSuperset(of: labelCharacters) { // ０１..９
      if candidateFormat.range(of: "%c\u{20E3}", options: .literal) != nil { // 1︎⃣..9︎⃣0︎⃣
        enumRange = candidateFormat.range(of: "%c\u{20E3}", options: .literal)
        for i in 0..<labels.count {
          let chars: [UTF16.CodeUnit] = [_labels[i].utf16.first! - 0xFF10 + 0x0030, 0xFE0E, 0x20E3]
          labels[i] = String(decodingCString: chars, as: UTF16.self)
        }
      } else if candidateFormat.range(of: "%c\u{20DD}", options: .literal) != nil { // ①..⑨⓪
        enumRange = candidateFormat.range(of: "%c\u{20DD}", options: .literal)
        for i in 0..<labels.count {
          let chars: [UTF16.CodeUnit] = [_labels[i].utf16.first! == 0xFF10 ? 0x24EA : _labels[i].utf16.first! - 0xFF11 + 0x2460]
          labels[i] = String(decodingCString: chars, as: UTF16.self)
        }
      } else if candidateFormat.range(of: "(%c)", options: .literal) != nil { // ⑴..⑼⑽
        enumRange = candidateFormat.range(of: "(%c)", options: .literal)
        for i in 0..<labels.count {
          let chars: [UTF16.CodeUnit] = [_labels[i].utf16.first! == 0xFF10 ? 0x247D : _labels[i].utf16.first! - 0xFF11 + 0x2474]
          labels[i] = String(decodingCString: chars, as: UTF16.self)
        }
      } else if candidateFormat.range(of: "%c.", options: .literal) != nil { // ⒈..⒐🄀
        enumRange = candidateFormat.range(of: "%c.", options: .literal)
        for i in 0..<labels.count {
          let chars: [UTF16.CodeUnit] = [_labels[i].utf16.first! == 0xFF10 ? 0xD83C : _labels[i].utf16.first! - 0xFF11 + 0x488,
                                         _labels[i].utf16.first! == 0xFF10 ? 0xDD00 : 0x0]
          labels[i] = String(decodingCString: chars, as: UTF16.self)
        }
      } else if candidateFormat.range(of: "%c,", options: .literal) != nil { // 🄂..🄊🄁
        enumRange = candidateFormat.range(of: "%c,", options: .literal)
        for i in 0..<labels.count {
          let chars: [UTF16.CodeUnit] = [0xD83C, _labels[i].utf16.first! - 0xFF10 + 0xDD01]
          labels[i] = String(decodingCString: chars, as: UTF16.self)
        }
      }
    } else if CharacterSet.init(charactersIn: Unicode.Scalar(UInt16(0xFF21))!...Unicode.Scalar(UInt16(0xFF3A))!).isSuperset(of: labelCharacters) { // Ａ..Ｚ
      if candidateFormat.range(of: "%c\u{20DD}", options: .literal) != nil { // Ⓐ..Ⓩ
        enumRange = candidateFormat.range(of: "%c\u{20DD}", options: .literal)
        for i in 0..<labels.count {
          let chars: [UTF16.CodeUnit] = [_labels[i].utf16.first! - 0xFF21 + 0x24B6]
          labels[i] = String(decodingCString: chars, as: UTF16.self)
        }
      } else if candidateFormat.range(of: "(%c)", options: .literal) != nil { // 🄐..🄩
        enumRange = candidateFormat.range(of: "(%c)", options: .literal)
        for i in 0..<labels.count {
          let chars: [UTF16.CodeUnit] = [0xD83C, _labels[i].utf16.first! - 0xFF21 + 0xDD10]
          labels[i] = String(decodingCString: chars, as: UTF16.self)
        }
      } else if candidateFormat.range(of: "%c\u{20DE}", options: .literal) != nil { // 🄰..🅉
        enumRange = candidateFormat.range(of: "%c\u{20DE}", options: .literal)
        for i in 0..<labels.count {
          let chars: [UTF16.CodeUnit] = [0xD83C, _labels[i].utf16.first! - 0xFF21 + 0xDD30]
          labels[i] = String(decodingCString: chars, as: UTF16.self)
        }
      }
    }
    if !(enumRange?.isEmpty ?? true) {
      candidateFormat.replaceSubrange(enumRange!, with: "%c")
      _candidateFormat = candidateFormat
      _labels = labels
    }
    // make sure label font can render all label strings
    let labelString: String! = labels.joined()
    let labelFont: NSFont! = _labelAttrs[NSAttributedString.Key.font] as? NSFont
    var substituteFont: NSFont! = CTFontCreateForString(labelFont as CTFont, labelString as CFString, CFRangeMake(0, labelString.count))
    if substituteFont.isNotEqual(to: labelFont) {
      let monoDigitAttrs: [NSFontDescriptor.AttributeName: Any] =
        [NSFontDescriptor.AttributeName.featureSettings:
          [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector],
           [NSFontDescriptor.FeatureKey.typeIdentifier: kTextSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kHalfWidthTextSelector]]]
      let substituteFontDescriptor: NSFontDescriptor = substituteFont.fontDescriptor.addingAttributes(monoDigitAttrs)
      substituteFont = NSFont.init(descriptor: substituteFontDescriptor, size: labelFont.pointSize)
      var labelAttrs:[NSAttributedString.Key: Any]! = _labelAttrs
      var labelHighlightedAttrs:[NSAttributedString.Key: Any]! = _labelHighlightedAttrs
      labelAttrs[NSAttributedString.Key.font] = substituteFont
      labelHighlightedAttrs[NSAttributedString.Key.font] = substituteFont
      _labelAttrs = labelAttrs
      _labelHighlightedAttrs = labelHighlightedAttrs
      if _linear {
        var pagingAttrs:[NSAttributedString.Key: Any]! = _pagingAttrs
        var pagingHighlightAttrs:[NSAttributedString.Key: Any]! = _pagingHighlightedAttrs
        pagingAttrs[NSAttributedString.Key.font] = substituteFont
        pagingHighlightAttrs[NSAttributedString.Key.font] = substituteFont
        _pagingAttrs = pagingAttrs
        _pagingHighlightedAttrs = pagingHighlightAttrs
      }
    }

    var rangeCandidate: NSRange = (candidateFormat as NSString).range(of: "%@", options: .literal)
    let rangeLabel: NSRange = NSMakeRange(0, rangeCandidate.location)
    var rangeComment: NSRange = NSMakeRange(NSMaxRange(rangeCandidate), candidateFormat.count - NSMaxRange(rangeCandidate))
    // parse markdown formats
    let format: NSMutableAttributedString! = NSMutableAttributedString(string: candidateFormat)
    let highlightedFormat: NSMutableAttributedString! = format
    format.addAttributes(_labelAttrs, range: rangeLabel)
    highlightedFormat.addAttributes(_labelHighlightedAttrs, range: rangeLabel)
    format.addAttributes(_attrs, range: rangeCandidate)
    highlightedFormat.addAttributes(_highlightedAttrs, range: rangeCandidate)
    if rangeComment.length > 0 {
      format.addAttributes(_commentAttrs, range: rangeComment)
      highlightedFormat.addAttributes(_commentHighlightedAttrs, range: rangeComment)
    }
    format.formatMarkDown()
    highlightedFormat.formatMarkDown()
    // add placeholder for comment '%s'
    rangeCandidate = format.mutableString.range(of: "%@", options: .literal)
    rangeComment = NSMakeRange(NSMaxRange(rangeCandidate), format.length - NSMaxRange(rangeCandidate))
    if rangeComment.length > 0 {
      format.replaceCharacters(in: rangeComment, with: kTipSpecifier + format.mutableString.substring(with: rangeComment))
      highlightedFormat.replaceCharacters(in: rangeComment, with: kTipSpecifier + format.mutableString.substring(with: rangeComment))
    } else {
      format.append(NSAttributedString(string: kTipSpecifier, attributes: _commentAttrs))
      highlightedFormat.append(NSAttributedString(string: kTipSpecifier, attributes: _commentHighlightedAttrs))
    }

    var candidateFormats: [NSAttributedString] = []
    var candidateHighlightedFormats: [NSAttributedString] = []
    let rangeEnum = format.mutableString.range(of:"%c", options:.literal)
    for label in labels {
      let newFormat: NSMutableAttributedString! = format
      let newHighlightedFormat: NSMutableAttributedString! = highlightedFormat
      newFormat.replaceCharacters(in: rangeEnum, with:label)
      newHighlightedFormat.replaceCharacters(in:rangeEnum, with:label)
      candidateFormats.append(newFormat)
      candidateHighlightedFormats.append(newHighlightedFormat)
    }
    _candidateFormats = candidateFormats
    _candidateHighlightedFormats = candidateHighlightedFormats
  }

  func setStatusMessageType(_ type: String?) {
    if (type == "long") {
      _statusMessageType = .long
    } else if (type == "short") {
      _statusMessageType = .short
    } else {
      _statusMessageType = .mixed
    }
  }
  func setAnnotationHeight(_ height:Double) {
    if height > 0.1 && _linespace < height * 2 {
      _linespace = height * 2
      let paragraphStyle: NSMutableParagraphStyle = _paragraphStyle as! NSMutableParagraphStyle
      paragraphStyle.paragraphSpacingBefore = height
      paragraphStyle.paragraphSpacing = height
      _paragraphStyle = paragraphStyle
    }
  }

}  // SquirrelTheme

// MARK: - Typesetting extensions for TextKit 1 (Mac OSX 10.9 to MacOS 11)

class SquirrelLayoutManager : NSLayoutManager, NSLayoutManagerDelegate {

  override func drawGlyphs(forGlyphRange glyphsToShow: NSRange,
                           at origin: NSPoint) {
//    let charRange: NSRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
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
        if attrs[kCTRubyAnnotationAttributeName as NSAttributedString.Key] != nil {
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
          if !verticalOrientation && (baselineClass == kCTBaselineClassIdeographicCentered as String || baselineClass == kCTBaselineClassMath as String) {
            let refFont: NSFont = (attrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] as! [String: Any])[kCTBaselineReferenceFont as String] as! NSFont
            offset.y += runFont.ascender * 0.5 + runFont.descender * 0.5 - refFont.ascender * 0.5 - refFont.descender * 0.5
          } else if verticalOrientation && runFont.pointSize < 24 && (runFont.fontName == "AppleColorEmoji") {
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

//    textStorage!.enumerateAttributes(
//      in: charRange,
//      options: [.longestEffectiveRangeNotRequired],
//      using: { (attrs: [NSAttributedString.Key : Any], range: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
//      let glyphRange: NSRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
//      let lineRect: NSRect = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true)
//      context.saveGState()
//      if attrs[kCTRubyAnnotationAttributeName as NSAttributedString.Key] != nil {
//        context.scaleBy(x: 1.0, y: -1.0)
//        var glyphIndex: Int = glyphRange.location
//        let line: CTLine = CTLineCreateWithAttributedString(textStorage!.attributedSubstring(from: range) as CFAttributedString)
//        let runs: CFArray = CTLineGetGlyphRuns(line)
//        for i in 0..<CFArrayGetCount(runs) {
//          let position: CGPoint = self.location(forGlyphAt: glyphIndex)
//          let run: CTRun = CFArrayGetValueAtIndex(runs, i) as! CTRun
//          let glyphCount: Int = CTRunGetGlyphCount(run)
//          var matrix: CGAffineTransform = CTRunGetTextMatrix(run)
//          var glyphOrigin: CGPoint = CGPointMake(origin.x + lineRect.origin.x + position.x, -origin.y - lineRect.origin.y - position.y)
//          glyphOrigin = textContainer.textView!.convertToBacking(glyphOrigin)
//          glyphOrigin.x = round(glyphOrigin.x)
//          glyphOrigin.y = round(glyphOrigin.y)
//          glyphOrigin = textContainer.textView!.convertFromBacking(glyphOrigin)
//          matrix.tx = glyphOrigin.x
//          matrix.ty = glyphOrigin.y
//          context.textMatrix = matrix
//          CTRunDraw(run, context, CFRangeMake(0, glyphCount))
//          glyphIndex += glyphCount
//        }
//      } else {
//        var position: NSPoint = self.location(forGlyphAt: glyphRange.location)
//        position.x += lineRect.origin.x
//        position.y += lineRect.origin.y
//        position = textContainer.textView!.convertToBacking(position)
//        position.x = round(position.x)
//        position.y = round(position.y)
//        position = textContainer.textView!.convertFromBacking(position)
//        let runFont: NSFont! = attrs[NSAttributedString.Key.font] as? NSFont
//        let baselineClass: String! = attrs[kCTBaselineClassAttributeName as NSAttributedString.Key] as? String
//        var offset: NSPoint = origin
//        if !verticalOrientation && (baselineClass == kCTBaselineClassIdeographicCentered as String || baselineClass == kCTBaselineClassMath as String) {
//          let refFont: NSFont! = (attrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] as? [String: Any])?[kCTBaselineReferenceFont as String] as? NSFont
//          offset.y += runFont.ascender * 0.5 + runFont.descender * 0.5 - refFont.ascender * 0.5 - refFont.descender * 0.5
//        } else if verticalOrientation && runFont.pointSize < 24 && (runFont.fontName == "AppleColorEmoji") {
//          let superscript: Int! = attrs[NSAttributedString.Key.superscript] as? Int
//          offset.x += runFont.capHeight - runFont.pointSize
//          offset.y += (runFont.capHeight - runFont.pointSize) * (superscript == 0 ? 0.25 : (superscript == 1 ? 0.5 / 0.55 : 0.0))
//        }
//        var glyphOrigin: NSPoint = textContainer.textView!.convertToBacking(NSMakePoint(position.x + offset.x, position.y + offset.y))
//        glyphOrigin = textContainer.textView!.convertFromBacking(NSMakePoint(round(glyphOrigin.x), round(glyphOrigin.y)))
//        super.drawGlyphs(forGlyphRange: glyphRange, at: NSMakePoint(glyphOrigin.x - position.x, glyphOrigin.y - position.y))
//      }
//      context.restoreGState()
//    })
//    context.clip(to: textContainer.textView!.superview!.bounds)
  }

  func layoutManager(_ layoutManager: NSLayoutManager,
                     shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                     lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                     baselineOffset: UnsafeMutablePointer<CGFloat>, 
                     in textContainer: NSTextContainer,
                     forGlyphRange glyphRange: NSRange) -> Boolean {
    let verticalOrientation: Boolean = textContainer.layoutOrientation == .vertical
    let charRange: NSRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange:nil)
    let refFont: NSFont = (layoutManager.textStorage!.attribute(kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key, at: charRange.location, effectiveRange: nil) as! Dictionary<CFString, Any>)[kCTBaselineReferenceFont] as! NSFont
    let rulerAttrs: NSParagraphStyle! = layoutManager.textStorage!.attribute(.paragraphStyle, at: charRange.location, effectiveRange: nil) as? NSParagraphStyle
    let lineHeightDelta: CGFloat = lineFragmentUsedRect.pointee.size.height - rulerAttrs.minimumLineHeight - rulerAttrs.lineSpacing
    if abs(lineHeightDelta) > 0.1 {
      lineFragmentUsedRect.pointee.size.height = round(lineFragmentUsedRect.pointee.size.height - lineHeightDelta)
      lineFragmentRect.pointee.size.height = round(lineFragmentRect.pointee.size.height - lineHeightDelta)
    }
    baselineOffset.pointee = floor(lineFragmentUsedRect.pointee.origin.y - lineFragmentRect.pointee.origin.y + rulerAttrs.minimumLineHeight * 0.5 + (verticalOrientation ? 0.0 : refFont.ascender * 0.5 + refFont.descender * 0.5))
    return true
  }

  func layoutManager(_ layoutManager: NSLayoutManager,
                     shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Boolean {
    return charIndex <= 1 || layoutManager.textStorage!.mutableString.character(at: charIndex - 1) != 0x9
  }

  func layoutManager(_ layoutManager: NSLayoutManager,
                     shouldUse action: NSLayoutManager.ControlCharacterAction,
                     forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
    if layoutManager.textStorage!.mutableString.character(at:charIndex) == 0x8B &&
        layoutManager.textStorage!.attribute(kCTRubyAnnotationAttributeName as NSAttributedString.Key, at: charIndex, effectiveRange: nil) != nil {
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
    if layoutManager.textStorage!.mutableString.character(at: charIndex) == 0x8B {
      var rubyRange: NSRange = NSMakeRange(NSNotFound, 0)
      if layoutManager.textStorage!.attribute(kCTRubyAnnotationAttributeName as NSAttributedString.Key, at: charIndex, effectiveRange: &rubyRange) != nil {
        let rubyString: NSAttributedString = layoutManager.textStorage!.attributedSubstring(from: rubyRange)
        let line: CTLine = CTLineCreateWithAttributedString(rubyString as CFAttributedString)
        let rubyRect: CGRect = CTLineGetBoundsWithOptions(line, .init())
        let baseSize: NSSize = rubyString.size()
        width = fdim(rubyRect.size.width, baseSize.width)
      }
    }
    return NSMakeRect(glyphPosition.x, 0.0, width, glyphPosition.y)
  }

}  // SquirrelLayoutManager

// MARK: - Typesetting extensions for TextKit 2 (MacOS 12 or higher)

@available(macOS 12.0, *)
class SquirrelTextLayoutFragment : NSTextLayoutFragment {

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
      var baseline: Double = NSMidY(lineRect)
      if !verticalOrientation {
        let refFont: NSFont = (lineFrag.attributedString.attribute(kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key, at: lineFrag.characterRange.location, effectiveRange: nil) as! Dictionary<CFString, Any>)[kCTBaselineReferenceFont] as! NSFont
        baseline += refFont.ascender * 0.5 + refFont.descender * 0.5
      }
      var renderOrigin: CGPoint = CGPointMake(NSMinX(lineRect) + lineFrag.glyphOrigin.x, floor(baseline) - lineFrag.glyphOrigin.y)
      let deviceOrigin: CGPoint = context.convertToDeviceSpace(renderOrigin)
      renderOrigin = context.convertToUserSpace(CGPointMake(round(deviceOrigin.x), round(deviceOrigin.y)))
      lineFrag.draw(at: renderOrigin, in:context)
    }
  }

}  // SquirrelTextLayoutFragment


@available(macOS 12.0, *)
class SquirrelTextLayoutManager : NSTextLayoutManager, NSTextLayoutManagerDelegate {

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                         shouldBreakLineBefore location: any NSTextLocation,
                         hyphenating: Boolean) -> Boolean {
    let contentStorage: NSTextContentStorage! = textLayoutManager.textContainer!.textView?.textContentStorage
    let charIndex: Int = contentStorage.offset(from: contentStorage.documentRange.location, to: location)
    return charIndex <= 1 || contentStorage.textStorage!.mutableString.character(at: charIndex - 1) != 0x9
  }

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                         textLayoutFragmentFor location: any NSTextLocation,
                         in textElement: NSTextElement) -> NSTextLayoutFragment {
    let textRange: NSTextRange! = NSTextRange(location: location, end: textElement.elementRange?.endLocation)
    return SquirrelTextLayoutFragment(textElement: textElement, range: textRange)
  }

}  // SquirrelTextLayoutManager

// MARK: - View behind text, containing drawings of backgrounds and highlights

fileprivate struct SquirrelTabularIndex {
  var index: Int
  var lineNum: Int
  var tabNum: Int
}

// Bezier cubic curve, which has continuous roundness
fileprivate func squirclePath(vertices: [NSPoint]?,
                              radius: Double) -> NSBezierPath? {
  if vertices?.isEmpty ?? true {
    return nil
  }
  let path: NSBezierPath! = NSBezierPath()
  var point: NSPoint = vertices!.last!
  var nextPoint: NSPoint = vertices!.first!
  var startPoint: NSPoint
  var endPoint: NSPoint
  var controlPoint1: NSPoint
  var controlPoint2: NSPoint
  var arcRadius: CGFloat
  var nextDiff: CGVector = CGVectorMake(nextPoint.x - point.x, nextPoint.y - point.y)
  var lastDiff: CGVector
  if abs(nextDiff.dx) >= abs(nextDiff.dy) {
    endPoint = NSMakePoint(point.x + nextDiff.dx * 0.5, nextPoint.y)
  } else {
    endPoint = NSMakePoint(nextPoint.x, point.y + nextDiff.dy * 0.5)
  }
  path.move(to: endPoint)
  for i in 0..<vertices!.count {
    lastDiff = nextDiff
    point = nextPoint
    nextPoint = vertices![(i + 1) % vertices!.count]
    nextDiff = CGVectorMake(nextPoint.x - point.x, nextPoint.y - point.y)
    if abs(nextDiff.dx) >= abs(nextDiff.dy) {
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

fileprivate func multilineRectVertices(leadingRect: NSRect,
                                       bodyRect: NSRect,
                                       trailingRect: NSRect) -> [NSPoint] {
  switch (((NSIsEmptyRect(leadingRect) ? 1 : 0) << 2) +
          ((NSIsEmptyRect(bodyRect) ? 1 : 0) << 1) +
          ((NSIsEmptyRect(trailingRect) ? 1 : 0) << 0)) {
  case 0b011:
    return rectVertices(leadingRect)
  case 0b110:
    return rectVertices(trailingRect)
  case 0b101:
    return rectVertices(bodyRect)
  case 0b001:
    let leadingVertices: [NSPoint] = rectVertices(leadingRect)
    let bodyVertices: [NSPoint] = rectVertices(bodyRect)
    return [leadingVertices[0], leadingVertices[1], bodyVertices[0],
            bodyVertices[1], bodyVertices[2], leadingVertices[3]]
  case 0b100:
    let bodyVertices: [NSPoint] = rectVertices(bodyRect)
    let trailingVertices: [NSPoint] = rectVertices(trailingRect)
    return [bodyVertices[0], trailingVertices[1], trailingVertices[2],
            trailingVertices[3], bodyVertices[2], bodyVertices[3]]
  case 0b010:
    if NSMinX(leadingRect) <= NSMaxX(trailingRect) {
      let leadingVertices: [NSPoint] = rectVertices(leadingRect)
      let trailingVertices: [NSPoint] = rectVertices(trailingRect)
      return [leadingVertices[0], leadingVertices[1], trailingVertices[0], trailingVertices[1],
              trailingVertices[2], trailingVertices[3], leadingVertices[2], leadingVertices[3]]
    } else {
      return []
    }
  case 0b000:
    let leadingVertices: [NSPoint] = rectVertices(leadingRect)
    let bodyVertices: [NSPoint] = rectVertices(bodyRect)
    let trailingVertices: [NSPoint] = rectVertices(trailingRect)
    return [leadingVertices[0], leadingVertices[1], bodyVertices[0], trailingVertices[1],
            trailingVertices[2], trailingVertices[3], bodyVertices[2], leadingVertices[3]]
  default:
    return []
  }
}

fileprivate func hooverColor(color: NSColor?,
                             appear: SquirrelAppear) -> NSColor? {
  if color == nil {
    return nil
  }
  if #available(macOS 10.14, *) {
    return color?.withSystemEffect(.rollover)
  } else {
    return appear == .darkAppear ? color!.highlight(withLevel: 0.3) : color!.shadow(withLevel: 0.3)
  }
}

fileprivate func disabledColor(color: NSColor?,
                               appear: SquirrelAppear) -> NSColor? {
  if color == nil {
    return nil
  }
  if #available(macOS 10.14, *) {
    return color?.withSystemEffect(.disabled)
  } else {
    return appear == .darkAppear ? color!.shadow(withLevel: 0.3) : color!.highlight(withLevel: 0.3)
  }
}

class SquirrelView : NSView {
  // Need flipped coordinate system, as required by textStorage
  private var _textView: NSTextView!
  var textView: NSTextView! {
    get { return _textView }
  }
  private var _textStorage: NSTextStorage!
  var textStorage: NSTextStorage! {
    get { return _textStorage }
  }
  fileprivate var currentTheme: SquirrelTheme! {
    get { return selectTheme(appear: appear()) }
  }
  private var _shape: CAShapeLayer!
  var shape: CAShapeLayer! {
    get { return _shape }
  }
  private var _tabularIndices: [SquirrelTabularIndex]! = []
  fileprivate var tabularIndices: [SquirrelTabularIndex]! {
    get { return _tabularIndices }
  }
  private var _candidateRanges: [NSRange]! = []
  var candidateRanges: [NSRange]! {
    get { return _candidateRanges }
  }
  private var _truncated: [Boolean]! = []
  var truncated: [Boolean]! {
    get { return _truncated }
  }
  private var _candidateRects: [NSRect]! = []
  var candidateRects: [NSRect]! {
    get { return _candidateRects }
  }
  private var _sectionRects: [NSRect]! = []
  var sectionRects: [NSRect]! {
    get { return _sectionRects }
  }
  private var _preeditBlock: NSRect = NSZeroRect
  var preeditBlock: NSRect {
    get { return _preeditBlock }
  }
  private var _candidateBlock: NSRect = NSZeroRect
  var candidateBlock: NSRect {
    get { return _candidateBlock }
  }
  private var _pagingBlock: NSRect = NSZeroRect
  var pagingBlock: NSRect {
    get { return _pagingBlock }
  }
  private var _deleteBackRect: NSRect = NSZeroRect
  var deleteBackRect: NSRect {
    get { return _deleteBackRect }
  }
  private var _expanderRect: NSRect = NSZeroRect
  var expanderRect: NSRect {
    get { return _expanderRect }
  }
  private var _pageUpRect: NSRect = NSZeroRect
  var pageUpRect: NSRect {
    get { return _pageUpRect }
  }
  private var _pageDownRect: NSRect = NSZeroRect
  var pageDownRect: NSRect {
    get { return _pageDownRect }
  }
  private var _functionButton: SquirrelIndex = .kVoidSymbol
  var functionButton: SquirrelIndex {
    get { return _functionButton }
  }
  private var _alignmentRectInsets: NSEdgeInsets = NSEdgeInsetsZero
  override var alignmentRectInsets: NSEdgeInsets {
    get { return _alignmentRectInsets }
  }
  private var _highlightedIndex: Int = NSNotFound
  var highlightedIndex: Int {
    get { return _highlightedIndex }
  }
  private var _preeditRange: NSRange = NSMakeRange(NSNotFound, 0)
  var preeditRange: NSRange {
    get { return _preeditRange }
  }
  private var _highlightedPreeditRange: NSRange = NSMakeRange(NSNotFound, 0)
  var highlightedPreeditRange: NSRange {
    get { return _highlightedPreeditRange }
  }
  private var _pagingRange: NSRange = NSMakeRange(NSNotFound, 0)
  var pagingRange: NSRange {
    get { return _pagingRange }
  }
  private var _expanded: Boolean = false
  var expanded: Boolean {
    get { return _expanded }
    set (expanded) { _expanded = expanded }
  }

  override var isFlipped: Boolean {
    get { return true }
  }

  override var wantsUpdateLayer: Boolean {
    get { return true }
  }

  func appear() -> SquirrelAppear {
    if #available(macOS 10.14, *) {
      let sel: Selector = NSSelectorFromString("viewEffectiveAppearance")
      let sourceAppearance: NSAppearance? = SquirrelInputController.currentController?.client()?.perform(sel) as? NSAppearance
      let effectAppearance: NSAppearance! = sourceAppearance != nil ? sourceAppearance : NSApp.effectiveAppearance
      if effectAppearance.bestMatch(from: [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua]) == NSAppearance.Name.darkAqua {
        return .darkAppear
      }
    }
    return .defaultAppear
  }

  fileprivate func selectTheme(appear: SquirrelAppear) -> SquirrelTheme! {
    let defaultTheme: SquirrelTheme! = SquirrelTheme()
    if #available(macOS 10.14, *) {
      let darkTheme: SquirrelTheme! = SquirrelTheme()
      return appear == .darkAppear ? darkTheme : defaultTheme
    } else {
      return defaultTheme
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.wantsLayer = true
    self.layer!.isGeometryFlipped = true
    self.layerContentsRedrawPolicy = .onSetNeedsDisplay

    if #available(macOS 12.0, *) {
      let textLayoutManager: SquirrelTextLayoutManager! = SquirrelTextLayoutManager()
      textLayoutManager.usesFontLeading = false
      textLayoutManager.usesHyphenation = false
      textLayoutManager.delegate = textLayoutManager
      let textContainer: NSTextContainer! = NSTextContainer(size: NSZeroSize)
      textContainer.lineFragmentPadding = 0
      textLayoutManager.textContainer = textContainer
      let contentStorage: NSTextContentStorage! = NSTextContentStorage()
      contentStorage.addTextLayoutManager(textLayoutManager)
      _textView = NSTextView(frame: frameRect, textContainer: textContainer)
      _textStorage = textView.textContentStorage!.textStorage!
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
    _textView.wantsLayer = false

    _shape = CAShapeLayer()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  @available(macOS 12.0, *)
  func getTextRange(fromCharRange charRange: NSRange) -> NSTextRange? {
    if charRange.location == NSNotFound {
      return nil
    } else {
      let contentStorage: NSTextContentStorage! = _textView.textContentStorage
      let start: NSTextLocation! = contentStorage.location(contentStorage.documentRange.location, offsetBy: charRange.location)
      let end: NSTextLocation! = contentStorage.location(start, offsetBy: charRange.length)
      return NSTextRange(location: start, end: end)
    }
  }

  @available(macOS 12.0, *)
  func getCharRange(fromTextRange textRange: NSTextRange?) -> NSRange {
    if textRange == nil {
      return NSMakeRange(NSNotFound, 0)
    } else {
      let contentStorage: NSTextContentStorage! = _textView.textContentStorage
      let location: Int = contentStorage.offset(from: contentStorage.documentRange.location, to: textRange!.location)
      let length: Int = contentStorage.offset(from: textRange!.location, to: textRange!.endLocation)
      return NSMakeRange(location, length)
    }
  }

  // Get the rectangle containing entire contents, expensive to calculate
  func contentRect() -> NSRect {
    if #available(macOS 12.0, *) {
      _textView.textLayoutManager!.ensureLayout(for: _textView.textContentStorage!.documentRange)
      return _textView.textLayoutManager!.usageBoundsForTextContainer
    } else {
      _textView.layoutManager!.ensureLayout(for: _textView.textContainer!)
      return _textView.layoutManager!.usedRect(for: _textView.textContainer!)
    }
  }

  // Get the rectangle containing the range of text, will first convert to glyph or text range, expensive to calculate
  func blockRect(forRange range: NSRange) -> NSRect {
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange! = getTextRange(fromCharRange: range)
      var blockRect: NSRect = NSZeroRect
      _textView.textLayoutManager!.enumerateTextSegments(
        in: textRange,
        type: .standard,
        options: .rangeNotRequired,
        using: { (segRange: NSTextRange?, segFrame: CGRect, baseline: CGFloat, textContainer: NSTextContainer) in
        blockRect = NSUnionRect(blockRect, segFrame)
        return true
      })
      return blockRect
    } else {
      let layoutManager: NSLayoutManager! = _textView.layoutManager
      let glyphRange: NSRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      var firstLineRange: NSRange = NSMakeRange(NSNotFound, 0)
      let firstLineRect: NSRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &firstLineRange)
      if NSMaxRange(glyphRange) <= NSMaxRange(firstLineRange) {
        let headX: CGFloat = layoutManager.location(forGlyphAt: glyphRange.location).x
        let tailX: CGFloat = NSMaxRange(glyphRange) < NSMaxRange(firstLineRange)
        ? layoutManager.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(firstLineRect)
        return NSMakeRect(NSMinX(firstLineRect) + headX,
                          NSMinY(firstLineRect),
                          tailX - headX,
                          NSHeight(firstLineRect))
      } else {
        let finalLineRect: NSRect = layoutManager.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphRange) - 1, effectiveRange: nil)
        let textContainer: NSRect = layoutManager.usedRect(for: layoutManager.textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil)!)
        return NSMakeRect(NSMinX(firstLineRect),
                          NSMinY(firstLineRect),
                          NSWidth(textContainer),
                          NSMaxY(finalLineRect) - NSMinY(firstLineRect))
      }
    }
  }

  // Calculate 3 boxes containing the text in range. leadingRect and trailingRect are incomplete line rectangle
  // bodyRect is the complete line fragment in the middle if the range spans no less than one full line
  func multilineRect(forRange charRange: NSRange,
                     leadingRect: NSRectPointer,
                     bodyRect: NSRectPointer,
                     trailingRect: NSRectPointer) {
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange! = getTextRange(fromCharRange: charRange)
      var leadingLineRect: NSRect = NSZeroRect
      var trailingLineRect: NSRect = NSZeroRect
      var leadingLineRange: NSTextRange!
      var trailingLineRange: NSTextRange!
      _textView.textLayoutManager!.enumerateTextSegments(
        in: textRange,
        type: .standard,
        options: .middleFragmentsExcluded,
        using: { (segRange: NSTextRange?, segFrame: CGRect, baseline: CGFloat, textContainer: NSTextContainer) in
        if !NSIsEmptyRect(segFrame) {
          if NSIsEmptyRect(leadingLineRect) || NSMinY(segFrame) < NSMaxY(leadingLineRect) {
            leadingLineRect = NSUnionRect(segFrame, leadingLineRect)
            leadingLineRange = leadingLineRange == nil ? segRange! : segRange!.union(leadingLineRange)
          } else {
            trailingLineRect = NSUnionRect(segFrame, trailingLineRect)
            trailingLineRange = trailingLineRange == nil ? segRange! : segRange!.union(trailingLineRange)
          }
        }
        return true
      })
      if NSIsEmptyRect(trailingLineRect) {
        bodyRect.pointee = leadingLineRect
      } else {
        let containerWidth: Double = contentRect().size.width
        leadingLineRect.size.width = containerWidth - NSMinX(leadingLineRect)
        if NSMaxX(trailingLineRect) == NSMaxX(leadingLineRect) {
          if NSMinX(leadingLineRect) == NSMinX(trailingLineRect) {
            bodyRect.pointee = NSUnionRect(leadingLineRect, trailingLineRect)
          } else {
            leadingRect.pointee = leadingLineRect
            bodyRect.pointee = NSMakeRect(0.0, NSMaxY(leadingLineRect),
                                          containerWidth, NSMaxY(trailingLineRect) - NSMaxY(leadingLineRect))
          }
        } else {
          trailingRect.pointee = trailingLineRect
          if NSMinX(leadingLineRect) == NSMinX(trailingLineRect) {
            bodyRect.pointee = NSMakeRect(0.0, NSMinY(leadingLineRect),
                                          containerWidth, NSMinY(trailingLineRect) - NSMinY(leadingLineRect))
          } else {
            leadingRect.pointee = leadingLineRect
            if !trailingLineRange.contains(leadingLineRange.endLocation) {
              bodyRect.pointee = NSMakeRect(0.0, NSMaxY(leadingLineRect),
                                            containerWidth, NSMinY(trailingLineRect) - NSMaxY(leadingLineRect))
            }
          }
        }
      }
    } else {
      let layoutManager: NSLayoutManager! = _textView.layoutManager
      let glyphRange: NSRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      var leadingLineRange: NSRange = NSMakeRange(NSNotFound, 0)
      let leadingLineRect: NSRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: &leadingLineRange)
      let headX: Double = layoutManager.location(forGlyphAt: glyphRange.location).x
      if NSMaxRange(leadingLineRange) >= NSMaxRange(glyphRange) {
        let tailX: Double = NSMaxRange(glyphRange) < NSMaxRange(leadingLineRange)
        ? layoutManager.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(leadingLineRect)
        bodyRect.pointee = NSMakeRect(headX, NSMinY(leadingLineRect), tailX - headX, NSHeight(leadingLineRect))
      } else {
        let containerWidth: Double = contentRect().size.width
        var trailingLineRange: NSRange = NSMakeRange(NSNotFound, 0)
        let trailingLineRect: NSRect = layoutManager.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphRange) - 1,
                                                                          effectiveRange:&trailingLineRange)
        let tailX: Double = NSMaxRange(glyphRange) < NSMaxRange(trailingLineRange)
        ? layoutManager.location(forGlyphAt: NSMaxRange(glyphRange)).x
        : NSWidth(trailingLineRect)
        if NSMaxRange(trailingLineRange) == NSMaxRange(glyphRange) {
          if glyphRange.location == leadingLineRange.location {
            bodyRect.pointee = NSMakeRect(0.0, NSMinY(leadingLineRect),
                                          containerWidth, NSMaxY(trailingLineRect) - NSMinY(leadingLineRect))
          } else {
            leadingRect.pointee = NSMakeRect(headX, NSMinY(leadingLineRect),
                                             containerWidth - headX, NSHeight(leadingLineRect))
            bodyRect.pointee = NSMakeRect(0.0, NSMaxY(leadingLineRect),
                                          containerWidth, NSMaxY(trailingLineRect) - NSMaxY(leadingLineRect))
          }
        } else {
          trailingRect.pointee = NSMakeRect(0.0, NSMinY(trailingLineRect), tailX, NSHeight(trailingLineRect))
          if glyphRange.location == leadingLineRange.location {
            bodyRect.pointee = NSMakeRect(0.0, NSMinY(leadingLineRect),
                                          containerWidth, NSMinY(trailingLineRect) - NSMinY(leadingLineRect))
          } else {
            leadingRect.pointee = NSMakeRect(headX, NSMinY(leadingLineRect),
                                             containerWidth - headX, NSHeight(leadingLineRect))
            if trailingLineRange.location > NSMaxRange(leadingLineRange) {
              bodyRect.pointee = NSMakeRect(0.0, NSMaxY(leadingLineRect),
                                            containerWidth, NSMinY(trailingLineRect) - NSMaxY(leadingLineRect))
            }
          }
        }
      }
    }
  }

  // Will triger - (void)updateLayer
  func drawView(withInsets alignmentRectInsets: NSEdgeInsets,
                candidateRanges: [NSRange],
                truncated: [Boolean],
                highlightedIndex: Int,
                preeditRange: NSRange,
                highlightedPreeditRange: NSRange,
                pagingRange: NSRange) {
    _alignmentRectInsets = alignmentRectInsets
    _candidateRanges = candidateRanges
    _truncated = truncated
    _highlightedIndex = highlightedIndex
    _preeditRange = preeditRange
    _highlightedPreeditRange = highlightedPreeditRange
    _pagingRange = pagingRange
    _functionButton = .kVoidSymbol
    // invalidate Rect beyond bound of textview to clear any out-of-bound drawing from last round
    setNeedsDisplay(self.bounds)
    _textView.setNeedsDisplay(self.bounds)
  }

  func set(preeditRange: NSRange,
           highlightedRange: NSRange) {
    if _preeditRange.length != preeditRange.length {
      for i in 0..<_candidateRanges.count {
        _candidateRanges[i].location += preeditRange.length - _preeditRange.length
      }
      if _pagingRange.location != NSNotFound {
        _pagingRange.location += preeditRange.length - _preeditRange.length
      }
    }
    _preeditRange = preeditRange
    _highlightedPreeditRange = highlightedRange
    setNeedsDisplay(_preeditBlock)
    _textView.setNeedsDisplay(_preeditBlock)
    let mirrorPreeditBlock: NSRect = NSOffsetRect(_preeditBlock, 0, NSHeight(self.bounds) - NSHeight(_preeditBlock) * 2)
    setNeedsDisplay(mirrorPreeditBlock)
    _textView.setNeedsDisplay(mirrorPreeditBlock)
  }

  func highlightCandidate(_ highlightedIndex: Int) {
    if _expanded {
      let prevActivePage: Int = _highlightedIndex / currentTheme.pageSize
      let newActivePage: Int = highlightedIndex / currentTheme.pageSize
      if newActivePage != prevActivePage {
        setNeedsDisplay(_sectionRects![prevActivePage])
        _textView.setNeedsDisplay(_sectionRects![prevActivePage])
      }
      setNeedsDisplay(_sectionRects![newActivePage])
      _textView.setNeedsDisplay(_sectionRects![newActivePage])
    } else {
      setNeedsDisplay(_candidateBlock)
      _textView.setNeedsDisplay(_candidateBlock)
    }
    _highlightedIndex = highlightedIndex
  }

  func highlightFunctionButton(_ functionButton: SquirrelIndex) {
    switch (functionButton) {
    case .kPageUpKey, .kHomeKey:
      setNeedsDisplay(_pageUpRect)
      _textView.setNeedsDisplay(_pageUpRect)
      break
    case .kPageDownKey, .kEndKey:
      setNeedsDisplay(_pageDownRect)
      _textView.setNeedsDisplay(_pageDownRect)
      break
    case .kBackSpaceKey, .kEscapeKey:
      setNeedsDisplay(_deleteBackRect)
      _textView.setNeedsDisplay(_deleteBackRect)
      break
    case .kExpandButton, .kCompressButton, .kLockButton:
      setNeedsDisplay(_expanderRect)
      _textView.setNeedsDisplay(_expanderRect)
      break
    default:
      break
    }
    _functionButton = functionButton
  }

  func getFunctionButtonLayer() -> CAShapeLayer! {
    var buttonColor: NSColor!
    var buttonRect: NSRect = NSZeroRect
    switch (_functionButton) {
    case .kPageUpKey:
      buttonColor = hooverColor(color: currentTheme.linear && !currentTheme.tabular
                                ? currentTheme.highlightedCandidateBackColor
                                : currentTheme.highlightedPreeditBackColor, appear: self.appear())
      buttonRect = _pageUpRect
      break
    case .kHomeKey:
      buttonColor = disabledColor(color: currentTheme.linear && !currentTheme.tabular
                                  ? currentTheme.highlightedCandidateBackColor
                                  : currentTheme.highlightedPreeditBackColor, appear: self.appear())
      buttonRect = _pageUpRect
      break
    case .kPageDownKey:
      buttonColor = hooverColor(color: currentTheme.linear && !currentTheme.tabular
                                ? currentTheme.highlightedCandidateBackColor
                                : currentTheme.highlightedPreeditBackColor, appear: self.appear())
      buttonRect = _pageDownRect
      break
    case .kEndKey:
      buttonColor = disabledColor(color: currentTheme.linear && !currentTheme.tabular
                                  ? currentTheme.highlightedCandidateBackColor
                                  : currentTheme.highlightedPreeditBackColor, appear: self.appear())
      buttonRect = _pageDownRect
      break
    case .kExpandButton, .kCompressButton, .kLockButton:
      buttonColor = hooverColor(color: currentTheme.highlightedPreeditBackColor, appear: self.appear())
      buttonRect = _expanderRect
      break
    case .kBackSpaceKey:
      buttonColor = hooverColor(color: currentTheme.highlightedPreeditBackColor, appear: self.appear())
      buttonRect = _deleteBackRect
      break
    case .kEscapeKey:
      buttonColor = disabledColor(color: currentTheme.highlightedPreeditBackColor, appear: self.appear())
      buttonRect = _deleteBackRect
      break
    default:
      return nil
    }
    if !NSIsEmptyRect(buttonRect) && (buttonColor != nil) {
      let cornerRadius: Double = min(currentTheme.highlightedCornerRadius, NSHeight(buttonRect) * 0.5)
      let buttonPath: NSBezierPath! = squirclePath(vertices: rectVertices(buttonRect), radius: cornerRadius)
      let functionButtonLayer: CAShapeLayer! = CAShapeLayer()
      functionButtonLayer.path = buttonPath.quartzPath()
      functionButtonLayer.fillColor = buttonColor.cgColor
      return functionButtonLayer
    }
    return nil
  }

  // All draws happen here
  override func updateLayer() {
    let panelRect: NSRect = bounds
    let backgroundRect: NSRect = backingAlignedRect(NSInsetRect(panelRect, currentTheme.borderInset.width,
                                                                currentTheme.borderInset.height),
                                                    options: .alignAllEdgesNearest)
    let outerCornerRadius: Double = min(currentTheme.cornerRadius, NSHeight(panelRect) * 0.5)
    let innerCornerRadius: Double = max(min(currentTheme.highlightedCornerRadius, NSHeight(backgroundRect) * 0.5),
                                        outerCornerRadius - min(currentTheme.borderInset.width, currentTheme.borderInset.height))
    let panelPath: NSBezierPath! = squirclePath(vertices: rectVertices(panelRect), radius: outerCornerRadius)
    let backgroundPath: NSBezierPath! = squirclePath(vertices: rectVertices(backgroundRect), radius: innerCornerRadius)
    let borderPath: NSBezierPath! = panelPath.copy() as? NSBezierPath
    borderPath.append(backgroundPath)

    var visibleRange:NSRange
    if #available(macOS 12.0, *) {
      visibleRange = getCharRange(fromTextRange: _textView.textLayoutManager!.textViewportLayoutController.viewportRange)
    } else {
      var containerGlyphRange: NSRange = NSMakeRange(NSNotFound, 0)
      _ = _textView.layoutManager!.textContainer(forGlyphAt: 0, effectiveRange: &containerGlyphRange)
      visibleRange = _textView.layoutManager!.characterRange(forGlyphRange: containerGlyphRange, actualGlyphRange: nil)
    }
    let preeditRange: NSRange = NSIntersectionRange(_preeditRange, visibleRange)
    var candidateBlockRange: NSRange
    if _candidateRanges.count > 0 {
      let endRange: NSRange = currentTheme.linear && _pagingRange.length > 0 ? _pagingRange : _candidateRanges.last!
      candidateBlockRange = NSIntersectionRange(NSUnionRange(_candidateRanges.first!, endRange), visibleRange)
    } else {
      candidateBlockRange = NSMakeRange(NSNotFound, 0)
    }
    let pagingRange: NSRange = NSIntersectionRange(_pagingRange, visibleRange)

    // Draw preedit Rect
    _preeditBlock = NSZeroRect
    _deleteBackRect = NSZeroRect
    var highlightedPreeditPath: NSBezierPath?
    if preeditRange.length > 0 {
      var innerBox: NSRect = blockRect(forRange: preeditRange)
      _preeditBlock = NSMakeRect(backgroundRect.origin.x,
                                 backgroundRect.origin.y,
                                 backgroundRect.size.width,
                                 innerBox.size.height + (candidateBlockRange.length > 0 ? currentTheme.preeditLinespace : 0.0))
      _preeditBlock = backingAlignedRect(_preeditBlock, options: .alignAllEdgesNearest)

      // Draw highlighted part of preedit text
      let highlightedPreeditRange: NSRange = NSIntersectionRange(_highlightedPreeditRange, visibleRange)
      let cornerRadius: Double = min(currentTheme.highlightedCornerRadius,
                                     currentTheme.preeditParagraphStyle.minimumLineHeight * 0.5)
      if highlightedPreeditRange.length > 0 && (currentTheme.highlightedPreeditBackColor != nil) {
        let kerning: Double = currentTheme.preeditAttrs[NSAttributedString.Key.kern] as! Double
        innerBox.origin.x += _alignmentRectInsets.left - kerning
        innerBox.size.width = backgroundRect.size.width - currentTheme.separatorWidth + kerning * 2
        innerBox.origin.y += _alignmentRectInsets.top
        innerBox = backingAlignedRect(innerBox, options: .alignAllEdgesNearest)
        var leadingRect: NSRect = NSZeroRect
        var bodyRect: NSRect = NSZeroRect
        var trailingRect: NSRect = NSZeroRect
        multilineRect(forRange: highlightedPreeditRange,
                      leadingRect: &leadingRect,
                      bodyRect: &bodyRect,
                      trailingRect: &trailingRect)
        if !NSIsEmptyRect(leadingRect) {
          leadingRect.origin.x += _alignmentRectInsets.left - kerning
          leadingRect.origin.y += _alignmentRectInsets.top
          leadingRect.size.width += kerning * 2
          leadingRect = backingAlignedRect(NSIntersectionRect(leadingRect, innerBox), options: .alignAllEdgesNearest)
        }
        if !NSIsEmptyRect(bodyRect) {
          bodyRect.origin.x += _alignmentRectInsets.left - kerning
          bodyRect.origin.y += _alignmentRectInsets.top
          bodyRect.size.width += kerning * 2
          bodyRect = backingAlignedRect(NSIntersectionRect(bodyRect, innerBox), options: .alignAllEdgesNearest)
        }
        if !NSIsEmptyRect(trailingRect) {
          trailingRect.origin.x += _alignmentRectInsets.left - kerning
          trailingRect.origin.y += _alignmentRectInsets.top
          trailingRect.size.width += kerning * 2
          trailingRect = backingAlignedRect(NSIntersectionRect(trailingRect, innerBox), options: .alignAllEdgesNearest)
        }

        // Handles the special case where containing boxes are separated
        if NSIsEmptyRect(bodyRect) && !NSIsEmptyRect(leadingRect) && !NSIsEmptyRect(trailingRect) &&
            NSMaxX(trailingRect) < NSMinX(leadingRect) {
          highlightedPreeditPath = squirclePath(vertices: rectVertices(leadingRect), radius: cornerRadius)
          highlightedPreeditPath!.append(squirclePath(vertices: rectVertices(trailingRect), radius: cornerRadius)!)
        } else {
          highlightedPreeditPath = squirclePath(vertices: multilineRectVertices(leadingRect: leadingRect, bodyRect: bodyRect, trailingRect: trailingRect), radius: cornerRadius)
        }
      }
      _deleteBackRect = blockRect(forRange: NSMakeRange(NSMaxRange(_preeditRange) - 1, 1))
      _deleteBackRect.size.width += floor(currentTheme.separatorWidth * 0.5)
      _deleteBackRect.origin.x = NSMaxX(backgroundRect) - NSWidth(_deleteBackRect)
      _deleteBackRect.origin.y += _alignmentRectInsets.top
      _deleteBackRect = backingAlignedRect(NSIntersectionRect(_deleteBackRect, _preeditBlock), options: .alignAllEdgesNearest)
    }

    
    // Draw candidate Rect
    _candidateBlock = NSZeroRect
    _candidateRects = []
    _sectionRects = []
    _tabularIndices = []
    var candidateBlockPath: NSBezierPath?, highlightedCandidatePath: NSBezierPath?
    var gridPath: NSBezierPath?, activePagePath: NSBezierPath?
    if candidateBlockRange.length > 0 {
      _candidateBlock = blockRect(forRange: candidateBlockRange)
      _candidateBlock.size.width = backgroundRect.size.width
      if currentTheme.tabular {
        _candidateBlock.size.width -= currentTheme.expanderWidth + currentTheme.separatorWidth
      }
      _candidateBlock.origin.x = backgroundRect.origin.x
      _candidateBlock.origin.y = preeditRange.length == 0 ? NSMinY(backgroundRect) : NSMaxY(_preeditBlock)
      if pagingRange.length == 0 || currentTheme.linear {
        _candidateBlock.size.height = NSMaxY(backgroundRect) - NSMinY(_candidateBlock)
      } else {
        _candidateBlock.size.height += currentTheme.linespace
      }
      _candidateBlock = backingAlignedRect(NSIntersectionRect(_candidateBlock, backgroundRect), options: .alignAllEdgesNearest)
      candidateBlockPath = squirclePath(vertices: rectVertices(_candidateBlock),
                                        radius: min(currentTheme.highlightedCornerRadius, NSHeight(_candidateBlock) * 0.5))

      // Draw candidate highlight rect
      let cornerRadius: Double = min(currentTheme.highlightedCornerRadius,
                                     currentTheme.paragraphStyle.minimumLineHeight * 0.5)
      if currentTheme.linear {
        var gridOriginY: Double = NSMinY(_candidateBlock)
        let tabInterval: Double = currentTheme.separatorWidth * 2
        var lineNum: Int = 0
        var sectionRect: NSRect = _candidateBlock
        if currentTheme.tabular {
          gridPath = NSBezierPath.init()
          sectionRect.size.height = 0
        }
        for i in 0..<_candidateRanges.count {
          let candidateRange: NSRange = NSIntersectionRange(_candidateRanges[i], visibleRange)
          if candidateRange.length == 0 {
            break
          }
          var leadingRect: NSRect = NSZeroRect
          var bodyRect: NSRect = NSZeroRect
          var trailingRect: NSRect = NSZeroRect
          multilineRect(forRange: candidateRange,
                        leadingRect:&leadingRect,
                        bodyRect:&bodyRect,
                        trailingRect:&trailingRect)
          if NSIsEmptyRect(leadingRect) {
            bodyRect.origin.y -= ceil(currentTheme.linespace * 0.5)
            bodyRect.size.height += ceil(currentTheme.linespace * 0.5)
          } else {
            leadingRect.origin.x += currentTheme.borderInset.width
            leadingRect.size.width += currentTheme.separatorWidth
            leadingRect.origin.y += _alignmentRectInsets.top - ceil(currentTheme.linespace * 0.5)
            leadingRect.size.height += ceil(currentTheme.linespace * 0.5)
            leadingRect = backingAlignedRect(NSIntersectionRect(leadingRect, _candidateBlock), options: .alignAllEdgesNearest)
          }
          if NSIsEmptyRect(trailingRect) {
            bodyRect.size.height += floor(currentTheme.linespace * 0.5)
          } else {
            trailingRect.origin.x += currentTheme.borderInset.width
            trailingRect.size.width += currentTheme.tabular ? 0.0 : currentTheme.separatorWidth
            trailingRect.origin.y += _alignmentRectInsets.top
            trailingRect.size.height += floor(currentTheme.linespace * 0.5)
            trailingRect = backingAlignedRect(NSIntersectionRect(trailingRect, _candidateBlock), options: .alignAllEdgesNearest)
          }
          if !NSIsEmptyRect(bodyRect) {
            bodyRect.origin.x += currentTheme.borderInset.width
            if _truncated[i] {
              bodyRect.size.width = NSMaxX(_candidateBlock) - NSMinX(bodyRect)
            } else {
              bodyRect.size.width += currentTheme.tabular && NSIsEmptyRect(trailingRect) ? 0.0 : currentTheme.separatorWidth
            }
            bodyRect.origin.y += _alignmentRectInsets.top
            bodyRect = backingAlignedRect(NSIntersectionRect(bodyRect, _candidateBlock), options: .alignAllEdgesNearest)
          }
          if currentTheme.tabular {
            if self.expanded {
              if i % currentTheme.pageSize == 0 {
                sectionRect.origin.y += NSHeight(sectionRect)
              } else if i % currentTheme.pageSize == currentTheme.pageSize - 1 {
                sectionRect.size.height = NSMaxY(NSIsEmptyRect(trailingRect) ? bodyRect : trailingRect) - NSMinY(sectionRect)
                let sec: Int = i / currentTheme.pageSize
                _sectionRects[sec] = sectionRect
                if sec == _highlightedIndex / currentTheme.pageSize {
                  activePagePath = squirclePath(vertices: rectVertices(sectionRect),
                                                radius: min(currentTheme.highlightedCornerRadius, NSHeight(sectionRect) * 0.5))
                }
              }
            }
            let bottomEdge: Double = NSMaxY(NSIsEmptyRect(trailingRect) ? bodyRect : trailingRect)
            if abs(bottomEdge - gridOriginY) > 2 {
              lineNum += i > 0 ? 1 : 0
              if abs(bottomEdge - NSMaxY(_candidateBlock)) > 2 { // horizontal border except for the last line
                gridPath!.move(to: NSMakePoint(NSMinX(_candidateBlock) + ceil(currentTheme.separatorWidth * 0.5), bottomEdge))
                gridPath!.line(to: NSMakePoint(NSMaxX(_candidateBlock) - floor(currentTheme.separatorWidth * 0.5), bottomEdge))
              }
              gridOriginY = bottomEdge
            }
            let headOrigin: CGPoint = (NSIsEmptyRect(leadingRect) ? bodyRect : leadingRect).origin
            let headTabColumn: Int = Int(round((headOrigin.x - _alignmentRectInsets.left) / tabInterval))
            if headOrigin.x > NSMinX(_candidateBlock) + currentTheme.separatorWidth { // vertical bar
              gridPath!.move(to: NSMakePoint(headOrigin.x, headOrigin.y + cornerRadius * 0.8))
              gridPath!.line(to: NSMakePoint(headOrigin.x, NSMaxY(NSIsEmptyRect(leadingRect) ? bodyRect : leadingRect) - cornerRadius * 0.8))
            }
            _tabularIndices[i] = SquirrelTabularIndex(index: i, lineNum: lineNum, tabNum: headTabColumn)
          }
          _candidateRects[i * 3] = leadingRect
          _candidateRects[i * 3 + 1] = bodyRect
          _candidateRects[i * 3 + 2] = trailingRect
        }
        let leadingRect: NSRect = _candidateRects[_highlightedIndex * 3]
        let bodyRect: NSRect = _candidateRects[_highlightedIndex * 3 + 1]
        let trailingRect: NSRect = _candidateRects[_highlightedIndex * 3 + 2]
        // Handles the special case where containing boxes are separated
        if !NSIsEmptyRect(leadingRect) && NSIsEmptyRect(bodyRect) && !NSIsEmptyRect(trailingRect) &&
            NSMaxX(trailingRect) < NSMinX(leadingRect) {
          highlightedCandidatePath = squirclePath(vertices: rectVertices(leadingRect), radius: cornerRadius)
          highlightedCandidatePath!.append(squirclePath(vertices: rectVertices(trailingRect), radius: cornerRadius)!)
        } else {
          let multilineVertices: [NSPoint] = multilineRectVertices(leadingRect: leadingRect, bodyRect: bodyRect, trailingRect: trailingRect)
          highlightedCandidatePath = squirclePath(vertices: multilineVertices, radius: cornerRadius)
        }
      } else { // stacked layout
        for i in 0..<_candidateRanges.count {
          let candidateRange: NSRange = NSIntersectionRange(_candidateRanges[i], visibleRange)
          if candidateRange.length == 0 {
            break
          }
          var candidateRect: NSRect = blockRect(forRange: candidateRange)
          candidateRect.size.width = backgroundRect.size.width
          candidateRect.origin.x = backgroundRect.origin.x
          candidateRect.origin.y += _alignmentRectInsets.top - ceil(currentTheme.linespace * 0.5)
          candidateRect.size.height += currentTheme.linespace
          candidateRect = backingAlignedRect(NSIntersectionRect(candidateRect, _candidateBlock), options: .alignAllEdgesNearest)
          _candidateRects[i] = candidateRect
        }
        highlightedCandidatePath = squirclePath(vertices: rectVertices(_candidateRects[_highlightedIndex]), radius: cornerRadius)
      }
    }

    // Draw paging Rect
    _pagingBlock = NSZeroRect
    _pageUpRect = NSZeroRect
    _pageDownRect = NSZeroRect
    _expanderRect = NSZeroRect
    var pageUpPath: NSBezierPath?, pageDownPath: NSBezierPath?
    if currentTheme.tabular && candidateBlockRange.length > 0 {
      _expanderRect = blockRect(forRange: NSMakeRange(_textStorage.length - 1, 1))
      _expanderRect.origin.x += currentTheme.borderInset.width
      _expanderRect.size.width = NSMaxX(backgroundRect) - NSMinX(_expanderRect)
      _expanderRect.size.height += currentTheme.linespace
      _expanderRect.origin.y += _alignmentRectInsets.top - ceil(currentTheme.linespace * 0.5)
      _expanderRect = self.backingAlignedRect(NSIntersectionRect(_expanderRect, backgroundRect), options: .alignAllEdgesNearest)
      if currentTheme.showPaging && _expanded && _tabularIndices.last!.lineNum > 0 {
        _pagingBlock = NSMakeRect(NSMaxX(_candidateBlock), NSMinY(_candidateBlock),
                                  NSMaxX(backgroundRect) - NSMaxX(_candidateBlock),
                                  NSMinY(_expanderRect) - NSMinY(_candidateBlock))
        let width: Double = fmin(currentTheme.paragraphStyle.minimumLineHeight, NSWidth(_pagingBlock))
        _pageUpRect = NSMakeRect(NSMidX(_pagingBlock) - width * 0.5, NSMidY(_pagingBlock) - width, width, width)
        _pageDownRect = NSMakeRect(NSMidX(_pagingBlock) - width * 0.5, NSMidY(_pagingBlock),  width, width)
        pageUpPath = NSBezierPath(ovalIn: NSInsetRect(_pageUpRect, width * 0.2, width * 0.2))
        pageUpPath!.move(to: NSMakePoint(NSMinX(_pageUpRect) + ceil(width * 0.325),
                                           NSMaxY(_pageUpRect) - ceil(width * 0.4)))
        pageUpPath!.line(to: NSMakePoint(NSMidX(_pageUpRect),
                                           NSMinY(_pageUpRect) + ceil(width * 0.4)))
        pageUpPath!.line(to: NSMakePoint(NSMaxX(_pageUpRect) - ceil(width * 0.325),
                                           NSMaxY(_pageUpRect) - ceil(width * 0.4)))
        pageDownPath = NSBezierPath(ovalIn: NSInsetRect(_pageDownRect, width * 0.2, width * 0.2))
        pageDownPath!.move(to: NSMakePoint(NSMinX(_pageDownRect) + ceil(width * 0.325),
                                             NSMinY(_pageDownRect) + ceil(width * 0.4)))
        pageDownPath!.line(to: NSMakePoint(NSMidX(_pageDownRect),
                                             NSMaxY(_pageDownRect) - ceil(width * 0.4)))
        pageDownPath!.line(to: NSMakePoint(NSMaxX(_pageDownRect) - ceil(width * 0.325),
                                             NSMinY(_pageDownRect) + ceil(width * 0.4)))
      }
    } else if pagingRange.length > 0 {
      _pageUpRect = blockRect(forRange: NSMakeRange(pagingRange.location, 1))
      _pageDownRect = blockRect(forRange: NSMakeRange(NSMaxRange(pagingRange) - 1, 1))
      _pageDownRect.origin.x += _alignmentRectInsets.left
      _pageDownRect.size.width += ceil(currentTheme.separatorWidth * 0.5)
      _pageDownRect.origin.y += _alignmentRectInsets.top
      _pageUpRect.origin.x += currentTheme.borderInset.width
      // bypass the bug of getting wrong glyph position when tab is presented
      _pageUpRect.size.width = NSWidth(_pageDownRect)
      _pageUpRect.origin.y += _alignmentRectInsets.top
      if currentTheme.linear {
        _pageUpRect.origin.y -= ceil(currentTheme.linespace * 0.5)
        _pageUpRect.size.height += currentTheme.linespace
        _pageDownRect.origin.y -= ceil(currentTheme.linespace * 0.5)
        _pageDownRect.size.height += currentTheme.linespace
        _pageUpRect = NSIntersectionRect(_pageUpRect, _candidateBlock)
        _pageDownRect = NSIntersectionRect(_pageDownRect, _candidateBlock)
      } else {
        _pagingBlock = NSMakeRect(NSMinX(backgroundRect),
                                  NSMaxY(_candidateBlock),
                                  NSWidth(backgroundRect),
                                  NSMaxY(backgroundRect) - NSMaxY(_candidateBlock))
        _pageUpRect = NSIntersectionRect(_pageUpRect, _pagingBlock)
        _pageDownRect = NSIntersectionRect(_pageDownRect, _pagingBlock)
      }
      _pageUpRect = self.backingAlignedRect(_pageUpRect, options: .alignAllEdgesNearest)
      _pageDownRect = self.backingAlignedRect(_pageDownRect, options: .alignAllEdgesNearest)
    }

    // Set layers
    _shape.path = panelPath.quartzPath()
    _shape.fillColor = NSColor.white.cgColor
    layer!.sublayers = nil
    // layers of large background elements
    let BackLayers = CALayer()
    let shapeLayer = CAShapeLayer()
    shapeLayer.path = panelPath.quartzPath()
    shapeLayer.fillColor = NSColor.white.cgColor
    BackLayers.mask = shapeLayer
    if #available(macOS 10.14, *) {
      BackLayers.opacity = Float(1.0 - currentTheme.translucency)
      BackLayers.allowsGroupOpacity = true
    }
    layer!.addSublayer(BackLayers)
    // background image (pattern style) layer
    if currentTheme.backImage!.isValid {
      let backImageLayer = CAShapeLayer()
      var transform:CGAffineTransform = currentTheme.vertical ? CGAffineTransformMakeRotation(.pi / 2)
      : CGAffineTransformIdentity
      transform = CGAffineTransformTranslate(transform, -backgroundRect.origin.x, -backgroundRect.origin.y)
      backImageLayer.path = backgroundPath.quartzPath()?.copy(using: &transform)
      backImageLayer.fillColor = NSColor(patternImage: currentTheme.backImage!).cgColor
      backImageLayer.setAffineTransform(CGAffineTransformInvert(transform))
      BackLayers.addSublayer(backImageLayer)
    }
    // background color layer
    let backColorLayer = CAShapeLayer()
    if (!NSIsEmptyRect(_preeditBlock) || !NSIsEmptyRect(_pagingBlock) ||
        !NSIsEmptyRect(_expanderRect)) && currentTheme.preeditBackColor != nil {
      if (candidateBlockPath != nil) {
        let nonCandidatePath: NSBezierPath! = backgroundPath.copy() as? NSBezierPath
        nonCandidatePath.append(candidateBlockPath!)
        backColorLayer.path = nonCandidatePath.quartzPath()
        backColorLayer.fillRule = .evenOdd
        backColorLayer.strokeColor = currentTheme.preeditBackColor!.cgColor
        backColorLayer.lineWidth = 0.5
        backColorLayer.fillColor = currentTheme.preeditBackColor!.cgColor
        BackLayers.addSublayer(backColorLayer)
        // candidate block's background color layer
        let candidateLayer = CAShapeLayer()
        candidateLayer.path = candidateBlockPath!.quartzPath()
        candidateLayer.fillColor = currentTheme.backColor!.cgColor
        BackLayers.addSublayer(candidateLayer)
      } else {
        backColorLayer.path = backgroundPath.quartzPath()
        backColorLayer.strokeColor = currentTheme.preeditBackColor!.cgColor
        backColorLayer.lineWidth = 0.5
        backColorLayer.fillColor = currentTheme.preeditBackColor!.cgColor
        BackLayers.addSublayer(backColorLayer)
      }
    } else {
      backColorLayer.path = backgroundPath.quartzPath()
      backColorLayer.strokeColor = currentTheme.backColor!.cgColor
      backColorLayer.lineWidth = 0.5
      backColorLayer.fillColor = currentTheme.backColor!.cgColor
      BackLayers.addSublayer(backColorLayer)
    }
    // border layer
    let borderLayer = CAShapeLayer()
    borderLayer.path = borderPath.quartzPath()
    borderLayer.fillRule = .evenOdd
    borderLayer.fillColor = (currentTheme.borderColor != nil ? currentTheme.borderColor : currentTheme.backColor)!.cgColor
    BackLayers.addSublayer(borderLayer)
    // layers of small highlighting elements
    let ForeLayers = CALayer()
    let maskLayer = CAShapeLayer()
    maskLayer.path = backgroundPath.quartzPath()
    maskLayer.fillColor = NSColor.white.cgColor
    ForeLayers.mask = maskLayer
    layer!.addSublayer(ForeLayers)
    // highlighted preedit layer
    if (highlightedPreeditPath != nil) && (currentTheme.highlightedPreeditBackColor != nil) {
      let highlightedPreeditLayer = CAShapeLayer()
      highlightedPreeditLayer.path = highlightedPreeditPath!.quartzPath()
      highlightedPreeditLayer.fillColor = currentTheme.highlightedPreeditBackColor!.cgColor
      ForeLayers.addSublayer(highlightedPreeditLayer)
    }
    // highlighted candidate layer
    if (highlightedCandidatePath != nil) && (currentTheme.highlightedCandidateBackColor != nil) {
      if (activePagePath != nil) {
        let activePageLayer:CAShapeLayer! = CAShapeLayer()
        activePageLayer.path = activePagePath!.quartzPath()
        activePageLayer.fillColor = (currentTheme.highlightedCandidateBackColor!.blended(withFraction: 0.8, of: currentTheme.backColor!.withAlphaComponent(1.0))!.withAlphaComponent(currentTheme.backColor!.alphaComponent)).cgColor
        BackLayers.addSublayer(activePageLayer)
      }
      let highlightedCandidateLayer:CAShapeLayer! = CAShapeLayer()
      highlightedCandidateLayer.path = highlightedCandidatePath!.quartzPath()
      highlightedCandidateLayer.fillColor = currentTheme.highlightedCandidateBackColor!.cgColor
      ForeLayers.addSublayer(highlightedCandidateLayer)
    }
    // function buttons (page up, page down, backspace) layer
    if _functionButton != .kVoidSymbol {
      let functionButtonLayer:CAShapeLayer! = self.getFunctionButtonLayer()
      if (functionButtonLayer != nil) {
        ForeLayers.addSublayer(functionButtonLayer)
      }
    }
    // grids (in candidate block) layer
    if (gridPath != nil) {
      let gridLayer:CAShapeLayer! = CAShapeLayer()
      gridLayer.path = gridPath!.quartzPath()
      gridLayer.lineWidth = 1.0
      gridLayer.strokeColor = (currentTheme.commentAttrs[NSAttributedString.Key.foregroundColor] as! NSColor).blended(withFraction: 0.0, of: currentTheme.backColor!)!.cgColor
      ForeLayers.addSublayer(gridLayer)
    }
    // paging buttons in expanded tabular layout
    if (pageUpPath != nil) && (pageDownPath != nil) {
      let pageUpLayer:CAShapeLayer! = CAShapeLayer()
      pageUpLayer.path = pageUpPath!.quartzPath()
      pageUpLayer.fillColor = NSColor.clear.cgColor
      pageUpLayer.lineWidth = ceil((currentTheme.pagingAttrs[NSAttributedString.Key.font] as! NSFont).pointSize * 0.05)
      let pageUpAttrs: NSDictionary! = (_functionButton == .kPageUpKey || _functionButton == .kHomeKey ? currentTheme.preeditHighlightedAttrs : currentTheme.preeditAttrs) as NSDictionary
      pageUpLayer.strokeColor = (pageUpAttrs[NSAttributedString.Key.foregroundColor] as! NSColor).cgColor
      ForeLayers.addSublayer(pageUpLayer)
      let pageDownLayer:CAShapeLayer! = CAShapeLayer()
      pageDownLayer.path = pageDownPath!.quartzPath()
      pageDownLayer.fillColor = NSColor.clear.cgColor
      pageDownLayer.lineWidth = ceil((currentTheme.pagingAttrs[NSAttributedString.Key.font] as! NSFont).pointSize * 0.05)
      let pageDownAttrs: NSDictionary! = (_functionButton == .kPageDownKey || _functionButton == .kEndKey ? currentTheme.preeditHighlightedAttrs : currentTheme.preeditAttrs) as NSDictionary
      pageDownLayer.strokeColor = (pageDownAttrs[NSAttributedString.Key.foregroundColor] as! NSColor).cgColor
      ForeLayers.addSublayer(pageDownLayer)
    }
    // logo at the beginning for status message
    if NSIsEmptyRect(_preeditBlock) && NSIsEmptyRect(_candidateBlock) {
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

  func getIndexFromMouseSpot(_ spot: NSPoint) -> Int {
    let point: NSPoint = convert(spot, from: nil)
    if NSMouseInRect(point, bounds, true) {
      if NSMouseInRect(point, _preeditBlock, true) {
        return NSMouseInRect(point, _deleteBackRect, true) ? SquirrelIndex.kBackSpaceKey.rawValue : SquirrelIndex.kCodeInputArea.rawValue
      }
      if NSMouseInRect(point, _expanderRect, true) {
        return SquirrelIndex.kExpandButton.rawValue
      }
      if NSMouseInRect(point, _pageUpRect, true) {
        return SquirrelIndex.kPageUpKey.rawValue
      }
      if NSMouseInRect(point, _pageDownRect, true) {
        return SquirrelIndex.kPageDownKey.rawValue
      }
      for i in 0..<_candidateRanges.count {
        if self.currentTheme.linear
            ? (NSMouseInRect(point, _candidateRects[i * 3], true) ||
               NSMouseInRect(point, _candidateRects[i * 3 + 1], true) ||
               NSMouseInRect(point, _candidateRects[i * 3 + 2], true))
            : NSMouseInRect(point, _candidateRects[i], true) {
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


class SquirrelToolTip : NSWindow {
  private var _backView: NSVisualEffectView!
  private var _textView: NSTextField!
  private var _displayTimer: Timer!
  var displayTimer: Timer! {
    get { return _displayTimer }
  }
  private var _hideTimer: Timer!
  var hideTimer: Timer! {
    get { return _hideTimer }
  }


  init() {
    super.init(contentRect: NSZeroRect,
               styleMask: .nonactivatingPanel,
               backing: .buffered,
               defer: true)
    backgroundColor = NSColor.clear
    isOpaque = true
    hasShadow = true
    let contentView = NSView()
    _backView = NSVisualEffectView()
    _backView.material = .toolTip
    contentView.addSubview(_backView)
    _textView = NSTextField()
    _textView.isBezeled = true
    _textView.bezelStyle = .squareBezel
    _textView.isSelectable = false
    contentView.addSubview(_textView)
    self.contentView = contentView
  }

  func show(withToolTip toolTip: String!, delay: Boolean) {
    if toolTip.count == 0 {
      hide()
      return
    }
    let panel: SquirrelPanel! = NSApp.SquirrelAppDelegate().panel
    level = panel.level + 1
    appearanceSource = panel

    _textView.stringValue = toolTip
    _textView.font = NSFont.toolTipsFont(ofSize: 0)
    _textView.textColor = NSColor.windowFrameTextColor
    _textView.sizeToFit()
    let contentSize: NSSize = _textView.fittingSize

    var spot: NSPoint = NSEvent.mouseLocation
    let cursor: NSCursor! = NSCursor.currentSystem
    spot.x += cursor.image.size.width - cursor.hotSpot.x
    spot.y -= cursor.image.size.height - cursor.hotSpot.y
    var windowRect: NSRect = NSMakeRect(spot.x, spot.y - contentSize.height,
                                       contentSize.width, contentSize.height)

    let screenRect: NSRect = panel.screen!.visibleFrame
    if NSMaxX(windowRect) > NSMaxX(screenRect) {
      windowRect.origin.x = NSMaxX(screenRect) - NSWidth(windowRect)
    }
    if NSMinY(windowRect) < NSMinY(screenRect) {
      windowRect.origin.y = NSMinY(screenRect)
    }
    setFrame(panel.screen!.backingAlignedRect(windowRect, options: .alignAllEdgesNearest),
             display: false)
    _textView.frame = self.contentView!.bounds
    _backView.frame = self.contentView!.bounds

    if _displayTimer.isValid {
      _displayTimer.invalidate()
    }
    if delay {
      _displayTimer = Timer.scheduledTimer(timeInterval: 3.0,
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
    if _hideTimer.isValid {
      _hideTimer.invalidate()
    }
    _hideTimer = Timer.scheduledTimer(timeInterval: 5.0,
                                      target: self,
                                      selector: #selector(delayedHide(_:)),
                                      userInfo: nil,
                                      repeats: false)
  }

  @objc func delayedHide(_ timer: Timer!) {
    hide()
  }

  func hide() {
    if _displayTimer.isValid {
      _displayTimer.invalidate()
      _displayTimer = nil
    }
    if _hideTimer.isValid {
      _hideTimer.invalidate()
      _hideTimer = nil
    }
    if self.isVisible {
      orderOut(nil)
    }
  }
}  // SquirrelToolTipView

// MARK: - Panel window, dealing with text content and mouse interactions

fileprivate func updateCandidateListLayout(isLinear: inout Boolean, isTabular: inout Boolean, config: SquirrelConfig!, prefix: String!) {
  let candidateListLayout: String! = config.getStringForOption(prefix + "/candidate_list_layout")
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
    let horizontal: Boolean? = config.getOptionalBoolForOption(prefix + "/horizontal")
    if (horizontal != nil) {
      isLinear = horizontal!
      isTabular = false
    }
  }
}

fileprivate func updateTextOrientation(isVertical: inout Boolean, config: SquirrelConfig!, prefix: String!) {
  let textOrientation: String? = config.getStringForOption(prefix + "/text_orientation")
  if (textOrientation == "horizontal") {
    isVertical = false
  } else if (textOrientation == "vertical") {
    isVertical = true
  } else {
    let vertical: Boolean? = config.getOptionalBoolForOption(prefix + "/vertical")
    if (vertical != nil) {
      isVertical = vertical!
    }
  }
}

// functions for post-retrieve processing
func positive(param: Double) -> Double { return max(0.0, param) }
func pos_round(param: Double) -> Double { return round(max(0.0, param)) }
func pos_ceil(param: Double) -> Double { return ceil(max(0.0, param)) }
func clamp_uni(param: Double) -> Double { return min(1.0, max(0.0, param)) }

class SquirrelPanel: NSPanel, NSWindowDelegate {

  private var _back: NSVisualEffectView?
  private var _toolTip: SquirrelToolTip!
  private var _view: SquirrelView!
  private var _screen: NSScreen! = .main
  override var screen: NSScreen? {
    get { return _screen }
  }
  private var _statusTimer: Timer?

  private var _maxSize: NSSize = NSZeroSize
  private var _textWidthLimit: Double = CGFLOAT_MAX
  private var _anchorOffset: Double = 0
  private var _initPosition: Boolean = true

  private var _indexRange: NSRange = NSMakeRange(0, 0)
  private var _highlightedIndex: Int = NSNotFound
  private var _functionButton: SquirrelIndex = .kVoidSymbol
  private var _caretPos: Int = NSNotFound
  private var _pageNum: Int = 0
  private var _sectionNum: Int = 0
  private var _caretAtHome: Boolean = false
  private var _finalPage: Boolean = false
  private var _locked: Boolean = false

  private var _scrollLocus: NSPoint = NSZeroPoint
  private var _cursorIndex: SquirrelIndex = .kVoidSymbol

  // Linear candidate list layout, as opposed to stacked candidate list layout.
  var linear: Boolean {
    get { return _view.currentTheme.linear }
  }
  // Tabular candidate list layout, initializes as tab-aligned linear layout,
  // expandable to stack 5 (3 for vertical) pages/sections of candidates
  var tabular: Boolean {
    get { return _view.currentTheme.tabular }
  }
  var locked: Boolean {
    get { return _locked }
  }
  var firstLine: Boolean {
    get { return _view.tabularIndices.isEmpty ? true : _view.tabularIndices[_highlightedIndex].lineNum == 0 }
  }
  var expanded: Boolean {
    get { return _view.expanded }
    set (expanded) {
      if _view.currentTheme.tabular && !_locked && _view.expanded != expanded {
        _view.expanded = expanded
        _sectionNum = 0
      }
    }
  }
  var sectionNum: Int {
    get { return _sectionNum }
    set (sectionNum) {
      if _view.currentTheme.tabular && _view.expanded && _sectionNum != sectionNum {
        let maxSections: Int = _view.currentTheme.vertical ? 2 : 4
        _sectionNum = sectionNum < 0 ? 0 : sectionNum > maxSections ? maxSections : sectionNum
      }
    }
  }
  // Vertical text orientation, as opposed to horizontal text orientation.
  var vertical: Boolean {
    get { return _view.currentTheme.vertical }
  }
  // Show preedit text inline.
  var inlinePreedit: Boolean {
    get { return _view.currentTheme.inlinePreedit }
  }
  // Show primary candidate inline
  var inlineCandidate: Boolean {
    get { return _view.currentTheme.inlineCandidate }
  }
  // Store switch options that change style (color theme) settings
  var optionSwitcher: SquirrelOptionSwitcher?
  // Status message before pop-up is displayed; nil before normal panel is displayed
  var statusMessage: String?
  // Store candidates and comments queried from rime
  var candidates: [String] = []
  var comments: [String] = []
  // position of the text input I-beam cursor on screen.
  var IbeamRect: NSRect = NSZeroRect
  var inputController: SquirrelInputController! {
    get { return SquirrelInputController.currentController }
  }

  init() {
    super.init(contentRect: IbeamRect,
               styleMask: [NSWindow.StyleMask.nonactivatingPanel, NSWindow.StyleMask.borderless],
               backing: .buffered,
               defer: true)
    self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow) - 100))
    self.alphaValue = 1.0
    self.hasShadow = false
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    self.delegate = self
    self.acceptsMouseMovedEvents = true

    let contentView: NSView! = NSView()
    _view = SquirrelView(frame: self.contentView?.bounds ?? NSZeroRect)
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
    self.contentView = contentView

    updateDisplayParameters()
    _toolTip = SquirrelToolTip()
  }

  private func setLock(_ locked: Boolean) {
    if _view.currentTheme.tabular && _locked != locked {
      _locked = locked
      let userConfig: SquirrelConfig! = SquirrelConfig()
      if userConfig.open(userConfig: "user") {
        _ = userConfig.setOption("var/option/_lock_tabular", withBool:locked)
        if locked {
          _ = userConfig.setOption("var/option/_expand_tabular", withBool:_view.expanded)
        }
      }
      userConfig.close()
    }
  }

  private func getLock() {
    if _view.currentTheme.tabular {
      let userConfig: SquirrelConfig! = SquirrelConfig()
      if userConfig.open(userConfig: "user") {
        _locked = userConfig.getBoolForOption("var/option/_lock_tabular")
        if _locked {
          _view.expanded = userConfig.getBoolForOption("var/option/_expand_tabular")
        }
      }
      userConfig.close()
      _sectionNum = 0
    }
  }

  func windowDidChangeBackingProperties(_ notification: Notification) {
    updateDisplayParameters()
  }

  func candidateIndexOnDirection(arrowKey: SquirrelIndex) -> Int {
    if !tabular || _indexRange.length == 0 || _highlightedIndex == NSNotFound {
      return NSNotFound
    }
    let pageSize: Int = _view.currentTheme.pageSize
    let currentTab: Int = _view.tabularIndices[_highlightedIndex].tabNum
    let currentLine: Int = _view.tabularIndices[_highlightedIndex].lineNum
    let finalLine: Int = _view.tabularIndices[_indexRange.length - 1].lineNum
    if arrowKey == (self.vertical ? .kLeftKey : .kDownKey) {
      if _highlightedIndex == _indexRange.length - 1 && _finalPage {
        return NSNotFound
      }
      if currentLine == finalLine && !_finalPage {
        return _highlightedIndex + pageSize + _indexRange.location
      }
      var newIndex: Int = _highlightedIndex + 1
      while  newIndex < _indexRange.length &&
              (_view.tabularIndices[newIndex].lineNum == currentLine ||
               (_view.tabularIndices[newIndex].lineNum == currentLine + 1 &&
                _view.tabularIndices[newIndex].tabNum <= currentTab)) {
        newIndex += 1
      }
      if newIndex != _indexRange.length || _finalPage {
        newIndex -= 1
      }
      return newIndex + _indexRange.location
    } else if arrowKey == (self.vertical ? .kRightKey : .kUpKey) {
      if currentLine == 0 {
        return _pageNum == 0 ? NSNotFound : pageSize * (_pageNum - _sectionNum) - 1
      }
      var newIndex: Int = _highlightedIndex - 1
      while newIndex > 0 &&
              (_view.tabularIndices[newIndex].lineNum == currentLine ||
               (_view.tabularIndices[newIndex].lineNum == currentLine - 1 &&
                _view.tabularIndices[newIndex].tabNum > currentTab)) {
        newIndex -= 1
      }
      return newIndex + _indexRange.location
    }
    return NSNotFound
  }

  // handle mouse interaction events
  override func sendEvent(_ event: NSEvent) {
    let theme: SquirrelTheme! = _view.currentTheme
    switch (event.type) {
    case .leftMouseDown:
      if event.clickCount == 1 && _cursorIndex == .kCodeInputArea {
        let spot:NSPoint = _view.textView.convert(mouseLocationOutsideOfEventStream, from: nil)
        let inputIndex: Int = _view.textView.characterIndexForInsertion(at: spot)
        if inputIndex == 0 {
          inputController.perform(action: .PROCESS, onIndex: .kHomeKey)
        } else if inputIndex < _caretPos {
          inputController.moveCursor(_caretPos, to: inputIndex,
                                       inlinePreedit: false, inlineCandidate: false)
        } else if inputIndex >= _view.preeditRange.length {
          inputController.perform(action: .PROCESS, onIndex: .kEndKey)
        } else if inputIndex > _caretPos + 1 {
          inputController.moveCursor(_caretPos, to: inputIndex - 1,
                                     inlinePreedit: false, inlineCandidate: false)
        }
      }
      break
    case .leftMouseUp:
      if event.clickCount == 1 && _cursorIndex.rawValue != NSNotFound {
        if _cursorIndex.rawValue == _highlightedIndex {
          inputController.perform(action: .SELECT, onIndex: SquirrelIndex(rawValue: _cursorIndex.rawValue + _indexRange.location)!)
        } else if _cursorIndex == _functionButton {
          if _cursorIndex == .kExpandButton {
            if _locked {
              setLock(false)
              _view.textStorage.replaceCharacters(in: NSMakeRange(_view.textStorage.length - 1, 1),
                                                  with: (_view.expanded ? theme.symbolCompress : theme.symbolExpand)!)
              _view.textView.setNeedsDisplay(_view.expanderRect)
            } else {
              expanded = !_view.expanded
              sectionNum = 0
            }
          }
          self.inputController.perform(action: .PROCESS, onIndex: _cursorIndex)
        }
      }
      break
    case .rightMouseUp:
      if event.clickCount == 1 && _cursorIndex.rawValue != NSNotFound {
        if _cursorIndex.rawValue == _highlightedIndex {
          inputController.perform(action: .DELETE, onIndex: SquirrelIndex(rawValue: _cursorIndex.rawValue + _indexRange.location)!)
        } else if _cursorIndex == _functionButton {
          switch (_functionButton) {
          case .kPageUpKey:
            inputController.perform(action: .PROCESS, onIndex: .kHomeKey)
            break
          case .kPageDownKey:
            inputController.perform(action: .PROCESS, onIndex: .kEndKey)
            break
          case .kExpandButton:
            setLock(!_locked)
            _view.textStorage.replaceCharacters(in: NSMakeRange(_view.textStorage.length - 1, 1),
                                                with: (_locked ? theme.symbolLock : _view.expanded ? theme.symbolCompress : theme.symbolExpand)!)
            _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                           value: theme.preeditHighlightedAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                           range: NSMakeRange(_view.textStorage.length - 1, 1))
            _view.textView.setNeedsDisplay(_view.expanderRect)
            inputController.perform(action: .PROCESS, onIndex: .kLockButton)
            break
          case .kBackSpaceKey:
            inputController.perform(action: .PROCESS, onIndex: .kEscapeKey)
            break
          default:
            break
          }
        }
      }
      break
    case .mouseMoved:
      if event.modifierFlags.contains(.control) {
        return
      }
      let noDelay: Boolean = event.modifierFlags.contains(.option)
      _cursorIndex = SquirrelIndex(rawValue: _view.getIndexFromMouseSpot(mouseLocationOutsideOfEventStream))!
      if _cursorIndex.rawValue != _highlightedIndex && _cursorIndex != _functionButton {
        _toolTip.hide()
      } else if noDelay {
        _toolTip.displayTimer.fire()
      }
      if _cursorIndex.rawValue >= 0 && _cursorIndex.rawValue < _indexRange.length && _highlightedIndex != _cursorIndex.rawValue {
        highlightFunctionButton(.kVoidSymbol, delayToolTip: !noDelay)
        if noDelay {
          _toolTip.show(withToolTip: NSLocalizedString("candidate", comment: ""), delay: !noDelay)
        }
        sectionNum = _cursorIndex.rawValue / theme.pageSize
        inputController.perform(action: .HIGHLIGHT, onIndex: SquirrelIndex(rawValue: _cursorIndex.rawValue + _indexRange.location)!)
      } else if (_cursorIndex == .kPageUpKey || _cursorIndex == .kPageDownKey || _cursorIndex == .kExpandButton ||
                 _cursorIndex == .kBackSpaceKey) && _functionButton != _cursorIndex {
        highlightFunctionButton(_cursorIndex, delayToolTip: !noDelay)
      }
      break
    case .mouseExited:
      _toolTip.displayTimer.invalidate()
      break
    case .leftMouseDragged:
      // reset the remember_size references after moving the panel
      _maxSize = NSZeroSize
      performDrag(with: event)
      break
    case .scrollWheel:
      let rulerStyle: NSParagraphStyle! = theme.attrs[NSAttributedString.Key.paragraphStyle] as? NSParagraphStyle
      let scrollThreshold: Double = rulerStyle.minimumLineHeight + rulerStyle.lineSpacing
      if event.phase == .began {
        _scrollLocus = NSZeroPoint
      } else if event.phase == .changed && !_scrollLocus.x.isNaN && !_scrollLocus.y.isNaN {
        // determine scrolling direction by confining to sectors within ±30º of any axis
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * sqrt(3.0) {
          _scrollLocus.x += event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 10)
        } else if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) * sqrt(3.0) {
          _scrollLocus.y += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        }
        // compare accumulated locus length against threshold and limit paging to max once
        if _scrollLocus.x > scrollThreshold {
          self.inputController.perform(action: .PROCESS, onIndex: theme.vertical ? .kPageDownKey : .kPageUpKey)
          _scrollLocus = NSMakePoint(.nan, .nan)
        } else if _scrollLocus.y > scrollThreshold {
          self.inputController.perform(action: .PROCESS, onIndex: .kPageUpKey)
          _scrollLocus = NSMakePoint(.nan, .nan)
        } else if _scrollLocus.x < -scrollThreshold {
          self.inputController.perform(action: .PROCESS, onIndex: theme.vertical ? .kPageUpKey : .kPageDownKey)
          _scrollLocus = NSMakePoint(.nan, .nan)
        } else if _scrollLocus.y < -scrollThreshold {
          self.inputController.perform(action: .PROCESS, onIndex: .kPageDownKey)
          _scrollLocus = NSMakePoint(.nan, .nan)
        }
      }
      break
    default:
      super.sendEvent(event)
      break
    }
  }

  func highlightCandidate(_ highlightedIndex: Int) {
    let theme: SquirrelTheme! = _view.currentTheme
    let prevHighlightedIndex: Int = _highlightedIndex
    let prevSectionNum: Int = prevHighlightedIndex / theme.pageSize
    _highlightedIndex = highlightedIndex
    sectionNum = highlightedIndex / theme.pageSize
    // apply new foreground colors
    for i in 0..<theme.pageSize {
      let prevIndex: Int = i + prevSectionNum * theme.pageSize
      if (_sectionNum != prevSectionNum || prevIndex == prevHighlightedIndex) && prevIndex < _indexRange.length {
        let prevRange: NSRange = _view.candidateRanges[prevIndex]
        let prevString: String = _view.textStorage.mutableString.substring(with: prevRange)
        let prevTextRange: NSRange = NSRange(prevString.range(of: candidates[prevIndex + _indexRange.location])!, in: prevString)
        let labelColor: NSColor! = (theme.labelAttrs[NSAttributedString.Key.foregroundColor] as! NSColor).blended(withFraction: prevIndex == prevHighlightedIndex && _sectionNum == prevSectionNum ? 0.0 : 0.5, of: NSColor.clear)
        _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                       value: labelColor!,
                                       range: NSMakeRange(prevRange.location, prevTextRange.location))
        if prevIndex == prevHighlightedIndex {
          _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                         value: theme.attrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                         range: NSMakeRange(prevRange.location + prevTextRange.location,
                                                            prevTextRange.length))
          _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                         value: theme.commentAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                         range: NSMakeRange(prevRange.location + NSMaxRange(prevTextRange),
                                                            prevRange.length - NSMaxRange(prevTextRange)))
        }
      }
      let newIndex: Int = i + _sectionNum * theme.pageSize
      if (_sectionNum != prevSectionNum || newIndex == _highlightedIndex) && newIndex < _indexRange.length {
        let newRange: NSRange = _view.candidateRanges[newIndex]
        let newString: String = _view.textStorage.mutableString.substring(with: newRange)
        let newTextRange: NSRange = NSRange(newString.range(of: candidates[newIndex + _indexRange.location])!, in: newString)
        let labelColor: NSColor! = (newIndex == _highlightedIndex ? theme.labelHighlightedAttrs : theme.labelAttrs)[NSAttributedString.Key.foregroundColor] as? NSColor
        _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                       value: labelColor!,
                                       range: NSMakeRange(newRange.location, newTextRange.location))
        let textColor: NSColor! = (newIndex == _highlightedIndex ? theme.highlightedAttrs : theme.attrs)[NSAttributedString.Key.foregroundColor] as? NSColor
        _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                       value: textColor!,
                                       range: NSMakeRange(newRange.location + newTextRange.location, newTextRange.length))
        let commentColor: NSColor! = (newIndex == _highlightedIndex ? theme.commentHighlightedAttrs : theme.commentAttrs)[NSAttributedString.Key.foregroundColor] as? NSColor
        _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                       value: commentColor!,
                                       range: NSMakeRange(newRange.location + NSMaxRange(newTextRange),
                                                          newRange.length - NSMaxRange(newTextRange)))
      }
    }
    _view.highlightCandidate(_highlightedIndex)
    self.displayIfNeeded()
  }

  func highlightFunctionButton(_ functionButton: SquirrelIndex, delayToolTip delay: Boolean) {
    if _functionButton == functionButton {
      return
    }
    let theme: SquirrelTheme! = _view.currentTheme
    switch (_functionButton) {
    case .kPageUpKey:
      if !theme.tabular {
        _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                       value: theme.pagingAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                       range: NSMakeRange(_view.pagingRange.location, 1))
      }
      break
    case .kPageDownKey:
      if !theme.tabular {
        _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                       value: theme.pagingAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                       range: NSMakeRange(NSMaxRange(_view.pagingRange) - 1, 1))
      }
      break
    case .kExpandButton:
      _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                     value: theme.preeditAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                     range: NSMakeRange(_view.textStorage.length - 1, 1))
      break
    case .kBackSpaceKey:
      _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                     value: theme.preeditAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                     range: NSMakeRange(NSMaxRange(_view.preeditRange) - 1, 1))
      break
    default:
      break
    }
    _functionButton = functionButton
    var newFunctionButton: SquirrelIndex = .kVoidSymbol
    switch (functionButton) {
    case .kPageUpKey:
      if !theme.tabular {
        _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                       value: theme.pagingHighlightedAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                       range: NSMakeRange(_view.pagingRange.location, 1))
      }
      newFunctionButton = _pageNum == 0 ? .kHomeKey : .kPageUpKey
      _toolTip.show(withToolTip: NSLocalizedString(_pageNum == 0 ? "home" : "page_up", comment: ""), delay: delay)
      break
    case .kPageDownKey:
      if !theme.tabular {
        _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                       value: theme.pagingHighlightedAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                       range: NSMakeRange(NSMaxRange(_view.pagingRange) - 1, 1))
      }
      newFunctionButton = _finalPage ? .kEndKey : .kPageDownKey
      _toolTip.show(withToolTip: NSLocalizedString(_finalPage ? "end" : "page_down", comment: ""), delay: delay)
      break
    case .kExpandButton:
      _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                     value: theme.preeditHighlightedAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                     range: NSMakeRange(_view.textStorage.length - 1, 1))
      newFunctionButton = _locked ? .kLockButton : _view.expanded ? .kCompressButton : .kExpandButton
      _toolTip.show(withToolTip: NSLocalizedString(_locked ? "unlock" : _view.expanded ? "compress" : "expand", comment:""), delay: delay)
      break
    case .kBackSpaceKey:
      _view.textStorage.addAttribute(NSAttributedString.Key.foregroundColor,
                                     value: theme.preeditHighlightedAttrs[NSAttributedString.Key.foregroundColor] as! NSColor,
                                     range: NSMakeRange(NSMaxRange(_view.preeditRange) - 1, 1))
      newFunctionButton = _caretAtHome ? .kEscapeKey : .kBackSpaceKey
      _toolTip.show(withToolTip: NSLocalizedString(_caretAtHome ? "escape" : "delete", comment: ""), delay: delay)
      break
    default:
      break
    }
    _view.highlightFunctionButton(newFunctionButton)
    self.displayIfNeeded()
  }

  func updateScreen() {
    for scrn in NSScreen.screens {
      if NSPointInRect(IbeamRect.origin, scrn.frame) {
        _screen = scrn
        return
      }
    }
    _screen = NSScreen.main
  }

  func updateDisplayParameters() {
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

    let textWidthRatio: Double = min(0.8, 1.0 / (theme.vertical ? 4 : 3) + (theme.attrs[NSAttributedString.Key.font] as! NSFont).pointSize / 144.0)
    _textWidthLimit = (theme.vertical ? NSHeight(screenRect) : NSWidth(screenRect)) * textWidthRatio - theme.separatorWidth - theme.borderInset.width * 2
    if theme.lineLength > 0 {
      _textWidthLimit = fmin(theme.lineLength, _textWidthLimit)
    }
    if theme.tabular {
      let tabInterval:Double = theme.separatorWidth * 2
      _textWidthLimit = floor(_textWidthLimit / tabInterval) * tabInterval + theme.expanderWidth
    }
    let textHeightLimit:Double = (theme.vertical ? NSWidth(screenRect) : NSHeight(screenRect)) * 0.8 -
    theme.borderInset.height * 2 - (theme.inlinePreedit ? ceil(theme.linespace * 0.5) : 0.0) -
    (theme.linear || !theme.showPaging ? floor(theme.linespace * 0.5) : 0.0)
    _view.textView.textContainer!.size = NSMakeSize(_textWidthLimit, textHeightLimit)

    // resize background image, if any
    if theme.backImage!.isValid {
      let widthLimit:Double = _textWidthLimit + theme.separatorWidth
      let backImageSize:NSSize = theme.backImage!.size
      theme.backImage!.resizingMode = .stretch
      theme.backImage!.size = theme.vertical
      ? NSMakeSize(backImageSize.width / backImageSize.height * widthLimit, widthLimit)
      : NSMakeSize(widthLimit, backImageSize.height / backImageSize.width * widthLimit)
    }
  }

  // Get the window size, it will be the dirtyRect in SquirrelView.drawRect
  func show() {
    if #available(macOS 10.14, *) {
      let appearanceName: NSAppearance.Name = _view.appear() == .darkAppear ? .darkAqua : .aqua
      let requestedAppearance: NSAppearance = NSAppearance.init(named: appearanceName)!
      if appearance != requestedAppearance {
        appearance = requestedAppearance
      }
    }

    //Break line if the text is too long, based on screen size.
    let theme: SquirrelTheme = _view.currentTheme
    let textContainer: NSTextContainer = _view.textView.textContainer!
    let insets: NSEdgeInsets = _view.alignmentRectInsets
    let textWidthRatio: CGFloat = min(0.8, 1.0 / (theme.vertical ? 4 : 3) + (theme.attrs[NSAttributedString.Key.font] as! NSFont).pointSize / 144.0)
    let screenRect: NSRect = _screen.visibleFrame

    // the sweep direction of the client app changes the behavior of adjusting Squirrel panel position
    let sweepVertical: Boolean = NSWidth(IbeamRect) > NSHeight(IbeamRect)
    let contentRect: NSRect = _view.contentRect()
    var maxContentRect: NSRect = contentRect
    // fixed line length (text width), but not applicable to status message
    if theme.lineLength > 0 && statusMessage == nil {
      maxContentRect.size.width = _textWidthLimit
    }
    // remember panel size (fix the top leading anchor of the panel in screen coordiantes)
    // but only when the text would expand on the side of upstream (i.e. towards the beginning of text)
    if theme.rememberSize && statusMessage == nil {
      if theme.lineLength == 0 && (theme.vertical
                                   ? (sweepVertical ? (NSMinY(IbeamRect) - fmax(NSWidth(maxContentRect), _maxSize.width) - insets.right < NSMinY(screenRect))
                                      : (NSMinY(IbeamRect) - kOffsetGap - NSHeight(screenRect) * textWidthRatio - insets.left - insets.right < NSMinY(screenRect)))
                                   : (sweepVertical ? (NSMinX(IbeamRect) - kOffsetGap - NSWidth(screenRect) * textWidthRatio - insets.left - insets.right >= NSMinX(screenRect))
                                      : (NSMaxX(IbeamRect) + fmax(NSWidth(maxContentRect), _maxSize.width) + insets.right > NSMaxX(screenRect)))) {
        if NSWidth(maxContentRect) >= _maxSize.width {
          _maxSize.width = NSWidth(maxContentRect)
        } else {
          let textHeightLimit:Double = (theme.vertical ? NSWidth(screenRect) : NSHeight(screenRect)) * 0.8 - insets.top - insets.bottom
          maxContentRect.size.width = _maxSize.width
          textContainer.size = NSMakeSize(_maxSize.width, textHeightLimit)
        }
      }
      let textHeight:Double = fmax(NSHeight(maxContentRect), _maxSize.height) + insets.top + insets.bottom
      if theme.vertical ? (NSMinX(IbeamRect) - textHeight - (sweepVertical ? kOffsetGap : 0) < NSMinX(screenRect))
          : (NSMinY(IbeamRect) - textHeight - (sweepVertical ? 0 : kOffsetGap) < NSMinY(screenRect)) {
        if NSHeight(maxContentRect) >= _maxSize.height {
          _maxSize.height = NSHeight(maxContentRect)
        } else {
          maxContentRect.size.height = _maxSize.height
        }
      }
    }

    var windowRect: NSRect = NSZeroRect
    if statusMessage != nil { // following system UI, middle-align status message with cursor
      _initPosition = true
      if theme.vertical {
        windowRect.size.width = NSHeight(maxContentRect) + insets.top + insets.bottom
        windowRect.size.height = NSWidth(maxContentRect) + insets.left + insets.right
      } else {
        windowRect.size.width = NSWidth(maxContentRect) + insets.left + insets.right
        windowRect.size.height = NSHeight(maxContentRect) + insets.top + insets.bottom
      }
      if sweepVertical { // vertically centre-align (MidY) in screen coordinates
        windowRect.origin.x = NSMinX(IbeamRect) - kOffsetGap - NSWidth(windowRect)
        windowRect.origin.y = NSMidY(IbeamRect) - NSHeight(windowRect) * 0.5
      } else { // horizontally centre-align (MidX) in screen coordinates
        windowRect.origin.x = NSMidX(IbeamRect) - NSWidth(windowRect) * 0.5
        windowRect.origin.y = NSMinY(IbeamRect) - kOffsetGap - NSHeight(windowRect)
      }
    } else {
      if theme.vertical { // anchor is the top right corner in screen coordinates (MaxX, MaxY)
        windowRect = NSMakeRect(NSMaxX(frame) - NSHeight(maxContentRect) - insets.top - insets.bottom,
                                NSMaxY(frame) - NSWidth(maxContentRect) - insets.left - insets.right,
                                NSHeight(maxContentRect) + insets.top + insets.bottom,
                                NSWidth(maxContentRect) + insets.left + insets.right)
        _initPosition = _initPosition || NSIntersectsRect(windowRect, IbeamRect)
        if _initPosition {
          if !sweepVertical {
            // To avoid jumping up and down while typing, use the lower screen when typing on upper, and vice versa
            if NSMinY(IbeamRect) - kOffsetGap - NSHeight(screenRect) * textWidthRatio - insets.left - insets.right < NSMinY(screenRect) {
              windowRect.origin.y = NSMaxY(IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.y = NSMinY(IbeamRect) - kOffsetGap - NSHeight(windowRect)
            }
            // Make the right edge of candidate block fixed at the left of cursor
            windowRect.origin.x = NSMinX(IbeamRect) + insets.top - NSWidth(windowRect)
          } else {
            if NSMinX(IbeamRect) - kOffsetGap - NSWidth(windowRect) < NSMinX(screenRect) {
              windowRect.origin.x = NSMaxX(IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.x = NSMinX(IbeamRect) - kOffsetGap - NSWidth(windowRect)
            }
            windowRect.origin.y = NSMinY(IbeamRect) + insets.left - NSHeight(windowRect)
          }
        }
      } else { // anchor is the top left corner in screen coordinates (MinX, MaxY)
        windowRect = NSMakeRect(NSMinX(frame),
                                NSMaxY(frame) - NSHeight(maxContentRect) - insets.top - insets.bottom,
                                NSWidth(maxContentRect) + insets.left + insets.right,
                                NSHeight(maxContentRect) + insets.top + insets.bottom)
        _initPosition = _initPosition || NSIntersectsRect(windowRect, IbeamRect)
        if _initPosition {
          if sweepVertical {
            // To avoid jumping left and right while typing, use the lefter screen when typing on righter, and vice versa
            if NSMinX(IbeamRect) - kOffsetGap - NSWidth(screenRect) * textWidthRatio - insets.left - insets.right >= NSMinX(screenRect) {
              windowRect.origin.x = NSMinX(IbeamRect) - kOffsetGap - NSWidth(windowRect)
            } else {
              windowRect.origin.x = NSMaxX(IbeamRect) + kOffsetGap
            }
            windowRect.origin.y = NSMinY(IbeamRect) + insets.top - NSHeight(windowRect)
          } else {
            if NSMinY(IbeamRect) - kOffsetGap - NSHeight(windowRect) < NSMinY(screenRect) {
              windowRect.origin.y = NSMaxY(IbeamRect) + kOffsetGap
            } else {
              windowRect.origin.y = NSMinY(IbeamRect) - kOffsetGap - NSHeight(windowRect)
            }
            windowRect.origin.x = NSMaxX(IbeamRect) - insets.left
          }
        }
      }
    }

    if _view.preeditRange.length > 0 {
      if _initPosition {
        _anchorOffset = 0
      }
      if theme.vertical != sweepVertical {
        let anchorOffset: Double = NSHeight(_view .blockRect(forRange: _view.preeditRange))
        if theme.vertical {
          windowRect.origin.x += anchorOffset - _anchorOffset
        } else {
          windowRect.origin.y += anchorOffset - _anchorOffset
        }
        _anchorOffset = anchorOffset
      }
    }
    if NSMaxX(windowRect) > NSMaxX(screenRect) {
      windowRect.origin.x = (_initPosition && sweepVertical ? fmin(NSMinX(IbeamRect) - kOffsetGap, NSMaxX(screenRect)) : NSMaxX(screenRect)) - NSWidth(windowRect)
    }
    if NSMinX(windowRect) < NSMinX(screenRect) {
      windowRect.origin.x = _initPosition && sweepVertical ? fmax(NSMaxX(IbeamRect) + kOffsetGap, NSMinX(screenRect)) : NSMinX(screenRect)
    }
    if NSMinY(windowRect) < NSMinY(screenRect) {
      windowRect.origin.y = _initPosition && !sweepVertical ? fmax(NSMaxY(IbeamRect) + kOffsetGap, NSMinY(screenRect)) : NSMinY(screenRect)
    }
    if NSMaxY(windowRect) > NSMaxY(screenRect) {
      windowRect.origin.y = (_initPosition && !sweepVertical ? fmin(NSMinY(IbeamRect) - kOffsetGap, NSMaxY(screenRect)) : NSMaxY(screenRect)) - NSHeight(windowRect)
    }

    if theme.vertical {
      windowRect.origin.x += NSHeight(maxContentRect) - NSHeight(contentRect)
      windowRect.size.width -= NSHeight(maxContentRect) - NSHeight(contentRect)
    } else {
      windowRect.origin.y += NSHeight(maxContentRect) - NSHeight(contentRect)
      windowRect.size.height -= NSHeight(maxContentRect) - NSHeight(contentRect)
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
      if theme.translucency > 0.001 {
        _back!.frame = viewRect
        _back!.isHidden = false
      } else {
        _back!.isHidden = true
      }
    }
    alphaValue = theme.alpha
    orderFront(nil)
    // reset to initial position after showing status message
    _initPosition = statusMessage != nil
    // voila !
  }

  func hide() {
    if _statusTimer?.isValid ?? false {
      _statusTimer!.invalidate()
      _statusTimer = nil
    }
    _toolTip.hide()
    self.orderOut(nil)
    _maxSize = NSZeroSize
    _initPosition = true
    expanded = false
    sectionNum = 0
  }

  func shouldBreakLine(inside range: NSRange) -> Boolean {
    let theme: SquirrelTheme! = _view.currentTheme
    _view.textStorage.fixFontAttribute(in: range)
    let maxTextWidth:Double = _textWidthLimit - (theme.tabular ? theme.expanderWidth : 0.0)
    var lineCount: Int = 0
    if #available(macOS 12.0, *) {
      let textRange:NSTextRange! = _view.getTextRange(fromCharRange: range)
      _view.textView.textLayoutManager!.enumerateTextSegments(
        in: textRange,
        type: .standard,
        options: .rangeNotRequired,
        using: { (segRange: NSTextRange?, segFrame: CGRect, baseline: CGFloat, textContainer:NSTextContainer) in
          var endEdge: Double = ceil(NSMaxX(segFrame))
          if theme.tabular {
            endEdge = ceil((endEdge + theme.separatorWidth) / (theme.separatorWidth * 2)) * theme.separatorWidth * 2
          }
          lineCount += endEdge > maxTextWidth - 0.1 ? 2 : 1
          return lineCount <= 1
      })
    } else {
      let glyphRange: NSRange = _view.textView.layoutManager!.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      _view.textView.layoutManager!.enumerateLineFragments(
        forGlyphRange: glyphRange,
        using: { (rect: NSRect, usedRect: NSRect, textContainer: NSTextContainer,
                  lineRange: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
        var endEdge:Double = ceil(NSMaxX(usedRect))
        if theme.tabular {
          endEdge = ceil((endEdge + theme.separatorWidth) / (theme.separatorWidth * 2)) * theme.separatorWidth * 2
        }
        lineCount += endEdge > maxTextWidth - 0.1 ? 2 : 1
      })
    }
    return lineCount > 1
  }

  func shouldUseTab(in range: NSRange, maxLineLength: inout Double) -> Boolean {
    let theme:SquirrelTheme! = _view.currentTheme
    _view.textStorage.fixFontAttribute(in: range)
    if theme.lineLength > 0.1 {
      maxLineLength = max(_textWidthLimit, _maxSize.width)
      return true
    }
    var rangeEndEdge: Double = 0
    var containerWidth: Double
    if #available(macOS 12.0, *) {
      let textRange: NSTextRange! = _view.getTextRange(fromCharRange: range)
      let layoutManager:NSTextLayoutManager! = _view.textView.textLayoutManager
      layoutManager.enumerateTextSegments(
        in: textRange,
        type: .standard,
        options: .rangeNotRequired,
        using: { (segRange: NSTextRange?, segFrame: CGRect, baseline: CGFloat, textContainer: NSTextContainer) in
        rangeEndEdge = ceil(NSMaxX(segFrame))
        return true
      })
      containerWidth = ceil(NSMaxX(layoutManager.usageBoundsForTextContainer))
    } else {
      let layoutManager: NSLayoutManager! = _view.textView.layoutManager
      let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
      rangeEndEdge = ceil(NSMaxX(layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)))
      containerWidth = ceil(NSMaxX(layoutManager.usedRect(for: _view.textView.textContainer!)))
    }
    if theme.tabular {
      containerWidth = ceil((containerWidth - theme.expanderWidth) / (theme.separatorWidth * 2)) *
      theme.separatorWidth * 2 + theme.expanderWidth
    }
    maxLineLength = max(maxLineLength, max(min(containerWidth, _textWidthLimit), _maxSize.width))
    return maxLineLength > rangeEndEdge - 0.1
  }

  func getPageNumString(_ pageNum: Int) -> NSMutableAttributedString! {
    let theme: SquirrelTheme! = _view.currentTheme
    if !theme.vertical {
      return NSMutableAttributedString(string:String(format:" %lu ", pageNum + 1),
                                       attributes:theme.pagingAttrs)
    }
    let pageNumString: NSAttributedString! = NSAttributedString(string: String(format:"%lu", pageNum + 1),
                                                                attributes: theme.pagingAttrs)
    let font: NSFont! = theme.pagingAttrs[NSAttributedString.Key.font] as? NSFont
    let height: Double = ceil(font.ascender - font.descender)
    let width: Double = max(height, pageNumString.size().width)
    let pageNumImage: NSImage! = NSImage(
      size: NSMakeSize(height, width), flipped:true,
      drawingHandler:{ (dstRect: NSRect) in
        let context:CGContext = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.translateBy(x: NSWidth(dstRect) * 0.5, y: NSHeight(dstRect) * 0.5)
        context.rotate(by: -.pi / 2)
        let origin: CGPoint = CGPointMake(0 - pageNumString.size().width / width * NSHeight(dstRect) * 0.5, 0 - NSWidth(dstRect) * 0.5)
        pageNumString.draw(at: origin)
        context.restoreGState()
        return true
    })
    pageNumImage.resizingMode = .stretch
    pageNumImage.size = NSMakeSize(height, height)
    let pageNumAttm: NSTextAttachment! = NSTextAttachment()
    pageNumAttm.image = pageNumImage
    pageNumAttm.bounds = NSMakeRect(0, font.descender, height, height)
    let attmString: NSMutableAttributedString! = NSMutableAttributedString(string: String(format:" %C ", unichar(NSTextAttachment.character)), attributes: theme.pagingAttrs)
    attmString.addAttribute(NSAttributedString.Key.attachment,
                            value: pageNumAttm!,
                            range: NSMakeRange(1, 1))
    return attmString
  }

  // Main function to add attributes to text output from librime
  func showPreedit(_ preedit: String?,
                   selRange: NSRange,
                   caretPos: Int,
                   candidateIndices indexRange: NSRange,
                   highlightedIndex: Int,
                   pageNum: Int,
                   finalPage: Boolean,
                   didCompose: Boolean) {
    if !NSIntersectsRect(IbeamRect, _screen.frame) {
      self.updateScreen()
      self.updateDisplayParameters()
    }
    let updateCandidates: Boolean = didCompose || !NSEqualRanges(_indexRange, indexRange)
    _caretAtHome = caretPos == NSNotFound || (caretPos == selRange.location && selRange.location == 1)
    _caretPos = caretPos
    _pageNum = pageNum
    _finalPage = finalPage
    _functionButton = .kVoidSymbol
    if indexRange.length > 0 || !(preedit?.isEmpty ?? true) {
      statusMessage = nil
      if _statusTimer?.isValid ?? false {
        _statusTimer!.invalidate()
        _statusTimer = nil
      }
    } else {
      if statusMessage != nil {
        showStatus(message: statusMessage)
        statusMessage = nil
      } else if !(_statusTimer?.isValid ?? false) {
        hide()
      }
      return
    }

    let theme: SquirrelTheme! = _view.currentTheme
    let text: NSTextStorage! = _view.textStorage
    var candidateRanges: [NSRange] = []
    var truncated: [Boolean] = []
    if updateCandidates {
      text.setAttributedString(NSAttributedString.init())
      if theme.lineLength > 0.1 {
        _maxSize.width = min(theme.lineLength, _textWidthLimit)
      }
      _indexRange = indexRange
      _highlightedIndex = highlightedIndex
    } else {
      candidateRanges = _view.candidateRanges
      truncated = _view.truncated
    }
    var preeditRange: NSRange = NSMakeRange(NSNotFound, 0)
    var highlightedPreeditRange: NSRange = NSMakeRange(NSNotFound, 0)
    var pagingRange: NSRange = NSMakeRange(NSNotFound, 0)

    var candidateBlockStart: Int
    var lineStart: Int
    var paragraphStyleCandidate:NSMutableParagraphStyle!
    let tabInterval: CGFloat = theme.separatorWidth * 2
    let textWidthLimit: CGFloat = _textWidthLimit - (theme.tabular ? theme.separatorWidth + theme.expanderWidth : 0.0)
    var maxLineLength: Double = 0.0

    // preedit
    if (preedit != nil) {
      let preeditLine: NSMutableAttributedString! = NSMutableAttributedString.init(string: preedit!, attributes: theme.preeditAttrs)
      preeditLine.mutableString.append(updateCandidates ? kFullWidthSpace : "\t")
      if selRange.length > 0 {
        preeditLine.addAttributes(theme.preeditHighlightedAttrs, range: selRange)
        highlightedPreeditRange = selRange
        let kerning: Double = theme.preeditAttrs[NSAttributedString.Key.kern] as! Double
        if selRange.location > 0 {
          preeditLine.addAttribute(NSAttributedString.Key.kern,
                                   value: kerning * 2,
                                   range: NSMakeRange(selRange.location - 1, 1))
        }
        if NSMaxRange(selRange) < preedit!.count {
          preeditLine.addAttribute(NSAttributedString.Key.kern,
                                   value: kerning * 2,
                                   range: NSMakeRange(NSMaxRange(selRange) - 1, 1))
        }
      }
      preeditLine.append(_caretAtHome ? theme.symbolDeleteStroke! : theme.symbolDeleteFill!)
      // force caret to be rendered sideways, instead of uprights, in vertical orientation
      if theme.vertical && caretPos != NSNotFound {
        preeditLine.addAttribute(NSAttributedString.Key.verticalGlyphForm,
                                 value: false,
                                 range: NSMakeRange(caretPos - (caretPos < NSMaxRange(selRange) ? 1 : 0), 1))
      }
      preeditRange = NSMakeRange(0, preeditLine.length)
      if updateCandidates {
        text.append(preeditLine)
        if indexRange.length > 0 {
          text.append(NSAttributedString(string: "\n", attributes: theme.preeditAttrs))
        } else {
          sectionNum = 0
        }
      } else {
        let rulerStyle: NSParagraphStyle! = text.attribute(NSAttributedString.Key.paragraphStyle,
                                                           at: 0, effectiveRange: nil) as? NSParagraphStyle
        preeditLine.addAttribute(NSAttributedString.Key.paragraphStyle,
                                 value: rulerStyle!,
                                 range: NSMakeRange(0, preeditLine.length))
        text.replaceCharacters(in: _view.preeditRange, with: preeditLine)
        _view.set(preeditRange: preeditRange, highlightedRange: selRange)
      }
    }

    if !updateCandidates {
      highlightCandidate(highlightedIndex)
      return
    }

    // candidate items
    if indexRange.length > 0 {
      candidateBlockStart = text.length
      lineStart = text.length
      if theme.linear {
        paragraphStyleCandidate = theme.paragraphStyle as? NSMutableParagraphStyle
      }
      for idx in 0..<indexRange.length {
        let col: Int = idx % theme.pageSize
        // attributed labels are already included in candidateFormats
        let item: NSMutableAttributedString! = (idx == highlightedIndex ? theme.candidateHighlightedFormats[col] : theme.candidateFormats[col]) as? NSMutableAttributedString
        let candidateField: NSRange = item.mutableString.range(of: "%@")
        // get the label size for indent
        let labelRange: NSRange = NSMakeRange(0, candidateField.location)
        let labelWidth: Double = theme.linear ? 0.0 : ceil(item.attributedSubstring(from: labelRange).size().width)
        // hide labels in non-highlighted pages (no selection keys)
        if idx / theme.pageSize != _sectionNum {
          item.addAttribute(NSAttributedString.Key.foregroundColor,
                            value: (theme.labelAttrs[NSAttributedString.Key.foregroundColor] as! NSColor).blended(withFraction: 0.5, of: NSColor.clear)!,
                            range: labelRange)
        }
        // plug in candidate texts and comments into the template
        item.replaceCharacters(in: candidateField, with: candidates[idx + indexRange.location])

        let commentField: NSRange = item.mutableString.range(of: kTipSpecifier)
        if comments[idx + indexRange.location].count > 0 {
          item.replaceCharacters(in: commentField, with: " " + (comments[idx + indexRange.location]))
        } else {
          item.deleteCharacters(in: commentField)
        }

        item.formatMarkDown()
        let annotationHeight: Double = item.annotateRuby(inRange: NSMakeRange(0, item.length),
                                                         verticalOrientation: theme.vertical,
                                                         maximumLength: _textWidthLimit)
        if annotationHeight * 2 > theme.linespace {
          setAnnotationHeight(annotationHeight)
          paragraphStyleCandidate = theme.paragraphStyle as? NSMutableParagraphStyle
          text.enumerateAttribute(.paragraphStyle,
                                  in: NSMakeRange(candidateBlockStart, text.length - candidateBlockStart),
                                  options: [.longestEffectiveRangeNotRequired])
          { (rulerStyle: Any?, range: NSRange, stop: UnsafeMutablePointer<ObjCBool>) in
            let style: NSMutableParagraphStyle! = rulerStyle as? NSMutableParagraphStyle
            style.paragraphSpacing = annotationHeight
            style.paragraphSpacingBefore = annotationHeight
            text.addAttribute(NSAttributedString.Key.paragraphStyle, value: style!, range: range)
          }
        }
        if comments[idx + indexRange.location].count > 0 &&
            item.mutableString.hasSuffix(" ") {
          item.deleteCharacters(in: NSMakeRange(item.length - 1, 1))
        }
        if !theme.linear {
          paragraphStyleCandidate = theme.paragraphStyle as? NSMutableParagraphStyle
          paragraphStyleCandidate.headIndent = labelWidth
        }
        item.addAttribute(NSAttributedString.Key.paragraphStyle,
                          value: paragraphStyleCandidate!, range: NSMakeRange(0, item.length))

        // determine if the line is too wide and line break is needed, based on screen size.
        if lineStart != text.length {
          let separatorStart: Int = text.length
          // separator: linear = "　"; tabular = "　\t"; stacked = "\n"
          let separator: NSAttributedString! = theme.separator
          text.append(separator)
          text.append(item)
          if theme.linear && (col == 0 || ceil(item.size().width) > textWidthLimit ||
                              shouldBreakLine(inside: NSMakeRange(lineStart, text.length - lineStart))) {
            let replaceRange: NSRange = theme.tabular ? NSMakeRange(separatorStart + separator.length, 0) : NSMakeRange(separatorStart, 1)
            text.replaceCharacters(in: replaceRange, with: "\n")
            lineStart = separatorStart + (theme.tabular ? 3 : 1)
          }
          if theme.tabular {
            candidateRanges[idx - 1].length += 2
          }
        } else { // at the start of a new line, no need to determine line break
          text.append(item)
        }
        // for linear layout, middle-truncate candidates that are longer than one line
        if theme.linear && ceil(item.size().width) > textWidthLimit {
          if idx < indexRange.length - 1 || (theme.showPaging && !theme.tabular) {
            text.append(NSAttributedString(string: "\n", attributes: theme.commentAttrs))
          }
          let paragraphStyleTruncating: NSMutableParagraphStyle! = theme.paragraphStyle as? NSMutableParagraphStyle
          paragraphStyleTruncating.lineBreakMode = .byTruncatingMiddle
          text.addAttribute(NSAttributedString.Key.paragraphStyle,
                            value: paragraphStyleTruncating!,
                            range: NSMakeRange(lineStart, item.length))
          truncated[idx] = true
          candidateRanges[idx] = NSMakeRange(lineStart, text.length - lineStart)
          lineStart = text.length
        } else {
          truncated[idx] = false
          candidateRanges[idx] = NSMakeRange(text.length - item.length, item.length)
        }
      }

      // paging indication
      if theme.tabular {
        text.append(theme.separator)
        candidateRanges[indexRange.length - 1].length += 2
        let pagingStart: Int = text.length
        let expander: NSAttributedString! = _locked ? theme.symbolLock : _view.expanded ? theme.symbolCompress : theme.symbolExpand
        text.append(expander)
        paragraphStyleCandidate = theme.paragraphStyle as? NSMutableParagraphStyle
        if shouldUseTab(in: NSMakeRange(pagingStart - 2, 3), maxLineLength: &maxLineLength) {
          text.replaceCharacters(in: NSMakeRange(pagingStart, 0), with:"\t")
          paragraphStyleCandidate.tabStops = []
          let candidateEndPosition: Double = NSMaxX(_view.blockRect(forRange: NSMakeRange(lineStart, pagingStart - 1 - lineStart)))
          let numTabs: Int = Int(ceil(candidateEndPosition / tabInterval))
          for i in 1...numTabs {
            paragraphStyleCandidate.addTabStop(NSTextTab(textAlignment: .left, location: CGFloat(i) * tabInterval, options: [:]))
          }
          paragraphStyleCandidate.addTabStop(NSTextTab(textAlignment: .left, location: maxLineLength - theme.expanderWidth, options: [:]))
        }
        paragraphStyleCandidate.tailIndent = 0.0
        text.addAttribute(NSAttributedString.Key.paragraphStyle,
                          value: paragraphStyleCandidate!,
                          range: NSMakeRange(lineStart, text.length - lineStart))
      } else if theme.showPaging {
        let paging:NSMutableAttributedString! = getPageNumString(_pageNum)
        paging.insert(_pageNum > 0 ? theme.symbolBackFill! : theme.symbolBackStroke!, at: 0)
        paging.append(_finalPage ? theme.symbolForwardStroke! : theme.symbolForwardFill!)
        text.append(theme.separator)
        var pagingStart: Int = text.length
        text.append(paging)
        if theme.linear {
          if shouldBreakLine(inside: NSMakeRange(lineStart, text.length - lineStart)) {
            text.replaceCharacters(in: NSMakeRange(pagingStart - 1, 0), with: "\n")
            lineStart = pagingStart
            pagingStart += 1
          }
          if shouldUseTab(in: NSMakeRange(pagingStart, paging.length), maxLineLength: &maxLineLength) || lineStart != candidateBlockStart {
            text.replaceCharacters(in: NSMakeRange(pagingStart - 1, 1), with: "\t")
            paragraphStyleCandidate = theme.paragraphStyle as? NSMutableParagraphStyle
            paragraphStyleCandidate.tabStops = [NSTextTab(textAlignment: .right, location: maxLineLength, options: [:])]
          }
          text.addAttribute(NSAttributedString.Key.paragraphStyle,
                            value: paragraphStyleCandidate!,
                            range: NSMakeRange(lineStart, text.length - lineStart))
        } else {
          let paragraphStylePaging: NSMutableParagraphStyle! = theme.pagingParagraphStyle as? NSMutableParagraphStyle
          if shouldUseTab(in: NSMakeRange(pagingStart, paging.length), maxLineLength: &maxLineLength) {
            text.replaceCharacters(in: NSMakeRange(pagingStart + 1, 1), with: "\t")
            text.replaceCharacters(in: NSMakeRange(pagingStart + paging.length - 2, 1), with: "\t")
            paragraphStylePaging.tabStops = [NSTextTab(textAlignment: .center, location: maxLineLength * 0.5, options: [:]),
                                             NSTextTab(textAlignment: .right, location: maxLineLength, options: [:])]
          }
          text.addAttribute(NSAttributedString.Key.paragraphStyle, value: paragraphStylePaging!, range: NSMakeRange(pagingStart, paging.length))
        }
        pagingRange = NSMakeRange(text.length - paging.length, paging.length)
      }
    }

    // right-align the backward delete symbol
    if (preedit != nil) && shouldUseTab(in: NSMakeRange(preeditRange.length - 2, 2), maxLineLength: &maxLineLength) {
      text.replaceCharacters(in: NSMakeRange(preeditRange.length - 2, 1), with: "\t")
      let paragraphStylePreedit:NSMutableParagraphStyle! = theme.preeditParagraphStyle as? NSMutableParagraphStyle
      paragraphStylePreedit.tabStops = [NSTextTab(textAlignment: .right, location: maxLineLength, options: [:])]
      text.addAttribute(NSAttributedString.Key.paragraphStyle, value: paragraphStylePreedit!, range: preeditRange)
    }

    // text done!
    text.ensureAttributesAreFixed(in: NSMakeRange(0, text.length))
    let topMargin: Double = preedit != nil ? 0.0 : ceil(theme.linespace * 0.5)
    let bottomMargin: Double = indexRange.length > 0 && (theme.linear || !theme.showPaging) ? floor(theme.linespace * 0.5) : 0.0
    let insets: NSEdgeInsets = NSEdgeInsetsMake(theme.borderInset.height + topMargin,
                                                theme.borderInset.width + ceil(theme.separatorWidth * 0.5),
                                                theme.borderInset.height + bottomMargin,
                                                theme.borderInset.width + floor(theme.separatorWidth * 0.5))

    animationBehavior = caretPos == NSNotFound ? .utilityWindow : .default
    _view.drawView(withInsets: insets,
                   candidateRanges: candidateRanges,
                   truncated: truncated,
                   highlightedIndex: highlightedIndex,
                   preeditRange: preeditRange,
                   highlightedPreeditRange: highlightedPreeditRange,
                   pagingRange: pagingRange)
    show()
  }

  func updateStatus(long: String?, short: String?) {
    switch (_view.currentTheme.statusMessageType) {
    case .mixed:
      statusMessage = short != nil ? short : long
      break
    case .long:
      statusMessage = long
      break
    case .short:
      statusMessage = short != nil ? short : long != nil ? String(long![long!.rangeOfComposedCharacterSequence(at: long!.startIndex)]) : nil
      break
    }
  }

  func showStatus(message:String!) {
    let theme:SquirrelTheme! = _view.currentTheme

    let text:NSTextStorage! = _view.textStorage
    text.setAttributedString(NSAttributedString(string: String(format:"%@ %@", kFullWidthSpace, message),
                                                attributes: theme.statusAttrs))

    text.ensureAttributesAreFixed(in: NSMakeRange(0, text.length))
    let insets:NSEdgeInsets = NSEdgeInsetsMake(theme.borderInset.height,
                                               theme.borderInset.width + ceil(theme.separatorWidth * 0.5),
                                               theme.borderInset.height,
                                               theme.borderInset.width + floor(theme.separatorWidth * 0.5))

    // disable remember_size and fixed line_length for status messages
    _initPosition = true
    _maxSize = NSZeroSize
    if _statusTimer?.isValid ?? false {
      _statusTimer!.invalidate()
    }
    animationBehavior = .utilityWindow
    _view.drawView(withInsets: insets,
                   candidateRanges: [],
                   truncated: [],
                   highlightedIndex: NSNotFound,
                   preeditRange: NSMakeRange(NSNotFound, 0),
                   highlightedPreeditRange: NSMakeRange(NSNotFound, 0),
                   pagingRange: NSMakeRange(NSNotFound, 0))
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

  func setAnnotationHeight(_ height: Double) {
    _view.selectTheme(appear: .defaultAppear).setAnnotationHeight(height)
    if #available(macOS 10.14, *) {
      _view.selectTheme(appear: .darkAppear).setAnnotationHeight(height)
    }
  }

  func loadLabelConfig(_ config: SquirrelConfig!, directUpdate update: Boolean) {
    let theme: SquirrelTheme! = _view.selectTheme(appear: .defaultAppear)
    SquirrelPanel.updateTheme(theme, withLabelConfig: config, directUpdate: update)
    if #available(macOS 10.14, *) {
      let darkTheme: SquirrelTheme! = _view.selectTheme(appear: .darkAppear)
      SquirrelPanel.updateTheme(darkTheme, withLabelConfig: config, directUpdate: update)
    }
    if update {
      updateDisplayParameters()
    }
  }

  private class func updateTheme(_ theme: SquirrelTheme!, withLabelConfig config: SquirrelConfig!, directUpdate update: Boolean) {
    let menuSize: Int = config.getIntForOption("menu/page_size") > 0 ? config.getIntForOption("menu/page_size") : 5
    var labels: [String]!
    var selectKeys: String? = config.getStringForOption("menu/alternative_select_keys")
    let selectLabels: [String]? = config.getListForOption("menu/alternative_select_labels")
    if selectLabels?.count ?? 0 > 0 {
      for i in 0..<menuSize {
        labels[i] = selectLabels![i]
      }
    }
    if (selectKeys != nil) {
      if selectLabels?.count ?? 0 == 0 {
        let keyCaps: String! = selectKeys?.uppercased().applyingTransform(.fullwidthToHalfwidth, reverse: true)
        for i in 0..<menuSize {
          labels[i] = String(keyCaps[Range(NSMakeRange(i, 1), in: keyCaps)!])
        }
      }
    } else {
      selectKeys = String("1234567890".prefix(menuSize))
      if selectLabels?.count ?? 0 == 0 {
        let numerals: String! = selectKeys!.applyingTransform(.fullwidthToHalfwidth, reverse:true)
        for i in 0..<menuSize {
          labels[i] = String(numerals[Range(NSMakeRange(i, 1), in: numerals)!])
        }
      }
    }
    theme.setSelectKeys(selectKeys!, labels: labels, directUpdate: update)
  }

  func loadConfig(_ config: SquirrelConfig!) {
    let styleOptions: Set<String>! = Set((optionSwitcher?.optionStates())!)
    let defaultTheme: SquirrelTheme! = _view.selectTheme(appear: .defaultAppear)
    SquirrelPanel.updateTheme(defaultTheme, withConfig: config, styleOptions: styleOptions, forAppearance: .defaultAppear)
    if #available(macOS 10.14, *) {
      let darkTheme: SquirrelTheme! = _view.selectTheme(appear: .darkAppear)
      SquirrelPanel.updateTheme(darkTheme, withConfig: config, styleOptions: styleOptions, forAppearance: .darkAppear)
    }
    getLock()
    updateDisplayParameters()
  }

  private class func updateTheme(_ theme: SquirrelTheme, withConfig config: SquirrelConfig, styleOptions: Set<String>, forAppearance appear: SquirrelAppear) {
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
    var alpha: Double? = config.getOptionalDoubleForOption("style/alpha", applyConstraint: clamp_uni)
    var translucency: Double? = config.getOptionalDoubleForOption("style/translucency", applyConstraint: clamp_uni)
    var cornerRadius: Double? = config.getOptionalDoubleForOption("style/corner_radius", applyConstraint: positive)
    var highlightedCornerRadius: Double? = config.getOptionalDoubleForOption("style/hilited_corner_radius", applyConstraint: positive)
    var borderHeight: Double? = config.getOptionalDoubleForOption("style/border_height", applyConstraint: pos_ceil)
    var borderWidth: Double? = config.getOptionalDoubleForOption("style/border_width", applyConstraint: pos_ceil)
    var lineSpacing: Double? = config.getOptionalDoubleForOption("style/line_spacing", applyConstraint: pos_round)
    var spacing: Double? = config.getOptionalDoubleForOption("style/spacing", applyConstraint: pos_round)
    var baseOffset: Double? = config.getOptionalDoubleForOption("style/base_offset")
    var lineLength: Double? = config.getOptionalDoubleForOption("style/line_length")
    // CHROMATICS
    var backColor: NSColor?
    var borderColor: NSColor?
    var preeditBackColor: NSColor?
    var textColor: NSColor?
    var candidateTextColor: NSColor?
    var commentTextColor: NSColor?
    var candidateLabelColor: NSColor?
    var highlightedBackColor: NSColor?
    var highlightedTextColor: NSColor?
    var highlightedCandidateBackColor: NSColor?
    var highlightedCandidateTextColor: NSColor?
    var highlightedCommentTextColor: NSColor?
    var highlightedCandidateLabelColor: NSColor?
    var backImage: NSImage?

    var colorScheme: String?
    if appear == .darkAppear {
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
    if !isNative {
      configPrefixes.insert("preset_color_schemes/" + colorScheme!, at: 0)
    }

    // get color scheme and then check possible overrides from styleSwitcher
    for prefix in configPrefixes {
      // CHROMATICS override
      config.colorSpace = config.getStringForOption(prefix + "/color_space") ?? config.colorSpace
      backColor = config.getColorForOption(prefix + "/back_color") ?? backColor
      borderColor = config.getColorForOption(prefix + "/border_color") ?? borderColor
      preeditBackColor = config.getColorForOption(prefix + "/preedit_back_color") ?? preeditBackColor
      textColor = config.getColorForOption(prefix + "/text_color") ?? textColor
      candidateTextColor = config.getColorForOption(prefix + "/candidate_text_color") ?? candidateTextColor
      commentTextColor = config.getColorForOption(prefix + "/comment_text_color") ?? commentTextColor
      candidateLabelColor = config.getColorForOption(prefix + "/label_color") ?? candidateLabelColor
      highlightedBackColor = config.getColorForOption(prefix + "/hilited_back_color") ?? highlightedBackColor
      highlightedTextColor = config.getColorForOption(prefix + "/hilited_text_color") ?? highlightedTextColor
      highlightedCandidateBackColor = config.getColorForOption(prefix + "/hilited_candidate_back_color") ?? highlightedCandidateBackColor
      highlightedCandidateTextColor = config.getColorForOption(prefix + "/hilited_candidate_text_color") ?? highlightedCandidateTextColor
      highlightedCommentTextColor = config.getColorForOption(prefix + "/hilited_comment_text_color") ?? highlightedCommentTextColor
      // for backward compatibility, 'label_hilited_color' and 'hilited_candidate_label_color' are both valid
      highlightedCandidateLabelColor = config.getColorForOption(prefix + "/label_hilited_color") ?? config.getColorForOption(prefix + "/hilited_candidate_label_color") ?? highlightedCandidateLabelColor
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
      alpha = config.getOptionalDoubleForOption(prefix + "/alpha", applyConstraint: clamp_uni) ?? alpha
      translucency = config.getOptionalDoubleForOption(prefix + "/translucency", applyConstraint: clamp_uni) ?? translucency
      cornerRadius = config.getOptionalDoubleForOption(prefix + "/corner_radius", applyConstraint: positive) ?? cornerRadius
      highlightedCornerRadius = config.getOptionalDoubleForOption(prefix + "/hilited_corner_radius", applyConstraint: positive) ?? highlightedCornerRadius
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
    let monoDigitAttrs: [NSFontDescriptor.AttributeName: Any] =
      [NSFontDescriptor.AttributeName.featureSettings:
        [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
          NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector],
         [NSFontDescriptor.FeatureKey.typeIdentifier: kTextSpacingType,
          NSFontDescriptor.FeatureKey.selectorIdentifier: kHalfWidthTextSelector]]]

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
    let separatorWidth: Double = ceil(kFullWidthSpace.size(withAttributes: [NSAttributedString.Key.font : commentFont!]).width)
    spacing = spacing ?? 0
    lineSpacing = lineSpacing ?? 0

    let preeditParagraphStyle: NSMutableParagraphStyle! = theme.preeditParagraphStyle as? NSMutableParagraphStyle
    preeditParagraphStyle.minimumLineHeight = fontHeight
    preeditParagraphStyle.maximumLineHeight = fontHeight
    preeditParagraphStyle.paragraphSpacing = spacing!
    preeditParagraphStyle.tabStops = []

    let paragraphStyle: NSMutableParagraphStyle! = theme.paragraphStyle as? NSMutableParagraphStyle
    paragraphStyle.minimumLineHeight = lineHeight
    paragraphStyle.maximumLineHeight = lineHeight
    paragraphStyle.paragraphSpacingBefore = ceil(lineSpacing! * 0.5)
    paragraphStyle.paragraphSpacing = floor(lineSpacing! * 0.5)
    paragraphStyle.tabStops = []
    paragraphStyle.defaultTabInterval = separatorWidth * 2

    let pagingParagraphStyle: NSMutableParagraphStyle! = theme.pagingParagraphStyle as? NSMutableParagraphStyle
    pagingParagraphStyle.minimumLineHeight = ceil(pagingFont.ascender - pagingFont.descender)
    pagingParagraphStyle.maximumLineHeight = ceil(pagingFont.ascender - pagingFont.descender)
    pagingParagraphStyle.tabStops = []

    let statusParagraphStyle: NSMutableParagraphStyle! = theme.statusParagraphStyle as? NSMutableParagraphStyle
    statusParagraphStyle.minimumLineHeight = commentFontHeight
    statusParagraphStyle.maximumLineHeight = commentFontHeight

    var attrs: [NSAttributedString.Key: Any] = theme.attrs
    var highlightedAttrs: [NSAttributedString.Key : Any] = theme.highlightedAttrs
    var labelAttrs: [NSAttributedString.Key : Any] = theme.labelAttrs
    var labelHighlightedAttrs: [NSAttributedString.Key : Any] = theme.labelHighlightedAttrs
    var commentAttrs: [NSAttributedString.Key : Any] = theme.commentAttrs
    var commentHighlightedAttrs: [NSAttributedString.Key : Any] = theme.commentHighlightedAttrs
    var preeditAttrs: [NSAttributedString.Key : Any] = theme.preeditAttrs
    var preeditHighlightedAttrs: [NSAttributedString.Key : Any] = theme.preeditHighlightedAttrs
    var pagingAttrs: [NSAttributedString.Key : Any] = theme.pagingAttrs
    var pagingHighlightedAttrs: [NSAttributedString.Key : Any] = theme.pagingHighlightedAttrs
    var statusAttrs: [NSAttributedString.Key : Any] = theme.statusAttrs
    attrs[NSAttributedString.Key.font] = font
    highlightedAttrs[NSAttributedString.Key.font] = font
    labelAttrs[NSAttributedString.Key.font] = labelFont
    labelHighlightedAttrs[NSAttributedString.Key.font] = labelFont
    commentAttrs[NSAttributedString.Key.font] = commentFont
    commentHighlightedAttrs[NSAttributedString.Key.font] = commentFont
    preeditAttrs[NSAttributedString.Key.font] = font
    preeditHighlightedAttrs[NSAttributedString.Key.font] = font
    pagingAttrs[NSAttributedString.Key.font] = linear ? labelFont : pagingFont
    pagingHighlightedAttrs[NSAttributedString.Key.font] = linear ? labelFont : pagingFont
    statusAttrs[NSAttributedString.Key.font] = commentFont

    let zhFont: NSFont! = CTFontCreateUIFontForLanguage(.system, fontSize!, "zh" as CFString)
    let zhCommentFont: NSFont! = NSFont.init(descriptor: zhFont.fontDescriptor, size: commentFontSize!)
    let maxFontSize: Double = max(fontSize!, max(commentFontSize!, labelFontSize!))
    let refFont: NSFont! = NSFont.init(descriptor: zhFont.fontDescriptor, size: maxFontSize)

    attrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    highlightedAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    labelAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    labelHighlightedAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    commentAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    commentHighlightedAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? refFont.vertical : refFont]
    preeditAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? zhFont.vertical : zhFont]
    preeditHighlightedAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? zhFont.vertical : zhFont]
    pagingAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: linear ? (vertical ? refFont.vertical : refFont) : pagingFont]
    pagingHighlightedAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: linear ? (vertical ? refFont.vertical : refFont) : pagingFont]
    statusAttrs[kCTBaselineReferenceInfoAttributeName as NSAttributedString.Key] =
      [kCTBaselineReferenceFont: vertical ? zhCommentFont.vertical : zhCommentFont]

    attrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    highlightedAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    labelAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] = kCTBaselineClassIdeographicCentered
    labelHighlightedAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] = kCTBaselineClassIdeographicCentered
    commentAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman
    commentHighlightedAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman;
    preeditAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman;
    preeditHighlightedAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman;
    statusAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] =
      vertical ? kCTBaselineClassIdeographicCentered : kCTBaselineClassRoman;
    pagingAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] = kCTBaselineClassIdeographicCentered;
    pagingHighlightedAttrs[kCTBaselineClassAttributeName as NSAttributedString.Key] = kCTBaselineClassIdeographicCentered;

    baseOffset = baseOffset ?? 0
    attrs[NSAttributedString.Key.baselineOffset] = baseOffset
    highlightedAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    labelAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    labelHighlightedAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    commentAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    commentHighlightedAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    preeditAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    preeditHighlightedAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    pagingAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    pagingHighlightedAttrs[NSAttributedString.Key.baselineOffset] = baseOffset
    statusAttrs[NSAttributedString.Key.baselineOffset] = baseOffset

    attrs[NSAttributedString.Key.kern] = ceil(lineHeight * 0.05)
    highlightedAttrs[NSAttributedString.Key.kern] = ceil(lineHeight * 0.05)
    commentAttrs[NSAttributedString.Key.kern] = ceil(lineHeight * 0.05)
    commentHighlightedAttrs[NSAttributedString.Key.kern] = ceil(lineHeight * 0.05)
    preeditAttrs[NSAttributedString.Key.kern] = ceil(fontHeight * 0.05)
    preeditHighlightedAttrs[NSAttributedString.Key.kern] = ceil(fontHeight * 0.05)
    statusAttrs[NSAttributedString.Key.kern] = ceil(commentFontHeight * 0.05)

    preeditAttrs[NSAttributedString.Key.paragraphStyle] = preeditParagraphStyle
    preeditHighlightedAttrs[NSAttributedString.Key.paragraphStyle] = preeditParagraphStyle
    statusAttrs[NSAttributedString.Key.paragraphStyle] = statusParagraphStyle

    labelAttrs[NSAttributedString.Key.verticalGlyphForm] = vertical
    labelHighlightedAttrs[NSAttributedString.Key.verticalGlyphForm] = vertical
    pagingAttrs[NSAttributedString.Key.verticalGlyphForm] = false
    pagingHighlightedAttrs[NSAttributedString.Key.verticalGlyphForm] = false

    // CHROMATICS refinement
    translucency = translucency ?? 0.0
    if #available(macOS 10.14, *) {
      if translucency! > 0.001 && !isNative && backColor != nil &&
          (appear == .darkAppear ? backColor!.luminanceComponent() > 0.65 : backColor!.luminanceComponent() < 0.55) {
        backColor = backColor?.invertLuminance(withAdjustment: 0)
        borderColor = borderColor?.invertLuminance(withAdjustment: 0)
        preeditBackColor = preeditBackColor?.invertLuminance(withAdjustment: 0)
        textColor = textColor?.invertLuminance(withAdjustment: 0)
        candidateTextColor = candidateTextColor?.invertLuminance(withAdjustment: 0)
        commentTextColor = commentTextColor?.invertLuminance(withAdjustment: 0)
        candidateLabelColor = candidateLabelColor?.invertLuminance(withAdjustment: 0)
        highlightedBackColor = highlightedBackColor?.invertLuminance(withAdjustment: -1)
        highlightedTextColor = highlightedTextColor?.invertLuminance(withAdjustment: 1)
        highlightedCandidateBackColor = highlightedCandidateBackColor?.invertLuminance(withAdjustment: -1)
        highlightedCandidateTextColor = highlightedCandidateTextColor?.invertLuminance(withAdjustment: 1)
        highlightedCommentTextColor = highlightedCommentTextColor?.invertLuminance(withAdjustment: 1)
        highlightedCandidateLabelColor = highlightedCandidateLabelColor?.invertLuminance(withAdjustment: 1)
      }
    }

    backColor = backColor ?? NSColor.controlBackgroundColor
    borderColor = borderColor ?? (isNative ? NSColor.gridColor : nil)
    preeditBackColor = preeditBackColor ?? (isNative ? NSColor.windowBackgroundColor : nil)
    textColor = textColor ?? NSColor.textColor
    candidateTextColor = candidateTextColor ?? NSColor.controlTextColor
    commentTextColor = commentTextColor ?? NSColor.secondaryTextColor()
    candidateLabelColor = candidateLabelColor ?? (isNative ? NSColor.accentColor() : blendColors(foreground: candidateTextColor, background: backColor))
    highlightedBackColor = highlightedBackColor ?? (isNative ? NSColor.selectedTextBackgroundColor : nil)
    highlightedTextColor = highlightedTextColor ?? NSColor.selectedTextColor
    highlightedCandidateBackColor = highlightedCandidateBackColor ?? (isNative ? NSColor.selectedContentBackgroundColor : nil)
    highlightedCandidateTextColor = highlightedCandidateTextColor ?? NSColor.selectedMenuItemTextColor
    highlightedCommentTextColor = highlightedCommentTextColor ?? NSColor.alternateSelectedControlTextColor
    highlightedCandidateLabelColor = highlightedCandidateLabelColor ?? (isNative ? NSColor.alternateSelectedControlTextColor : blendColors(foreground: highlightedCandidateTextColor, background: highlightedCandidateBackColor))

    attrs[NSAttributedString.Key.foregroundColor] = candidateTextColor
    highlightedAttrs[NSAttributedString.Key.foregroundColor] = highlightedCandidateTextColor
    labelAttrs[NSAttributedString.Key.foregroundColor] = candidateLabelColor
    labelHighlightedAttrs[NSAttributedString.Key.foregroundColor] = highlightedCandidateLabelColor
    commentAttrs[NSAttributedString.Key.foregroundColor] = commentTextColor
    commentHighlightedAttrs[NSAttributedString.Key.foregroundColor] = highlightedCommentTextColor
    preeditAttrs[NSAttributedString.Key.foregroundColor] = textColor
    preeditHighlightedAttrs[NSAttributedString.Key.foregroundColor] = highlightedTextColor
    pagingAttrs[NSAttributedString.Key.foregroundColor] = linear && !tabular ? candidateLabelColor : textColor
    pagingHighlightedAttrs[NSAttributedString.Key.foregroundColor] = linear && !tabular ? highlightedCandidateLabelColor : highlightedTextColor
    statusAttrs[NSAttributedString.Key.foregroundColor] = commentTextColor

    let borderInset: NSSize = vertical ? NSMakeSize(borderHeight ?? 0, borderWidth ?? 0)
                                       : NSMakeSize(borderWidth ?? 0, borderHeight ?? 0)
    lineLength = lineLength != nil && lineLength! > 0.1 ? max(ceil(lineLength!), separatorWidth * 5) : 0

    theme.setScalars(cornerRadius: min(cornerRadius ?? 0, lineHeight * 0.5),
                     highlightedCornerRadius: min(highlightedCornerRadius ?? 0, lineHeight * 0.5),
                     separatorWidth: separatorWidth,
                     linespace: lineSpacing!,
                     preeditLinespace: spacing!,
                     alpha: alpha ?? 1.0,
                     translucency: translucency!,
                     lineLength: lineLength!,
                     borderInset: borderInset,
                     showPaging: showPaging ?? false,
                     rememberSize: rememberSize ?? false,
                     tabular: tabular,
                     linear: linear,
                     vertical: vertical,
                     inlinePreedit: inlinePreedit ?? false,
                     inlineCandidate: inlineCandidate ?? false)

    theme.setAttributes(attrs: attrs,
                        highlightedAttrs: highlightedAttrs,
                        labelAttrs: labelAttrs,
                        labelHighlightedAttrs: labelHighlightedAttrs,
                        commentAttrs: commentAttrs,
                        commentHighlightedAttrs: commentHighlightedAttrs,
                        preeditAttrs: preeditAttrs,
                        preeditHighlightedAttrs: preeditHighlightedAttrs,
                        pagingAttrs: pagingAttrs,
                        pagingHighlightedAttrs: pagingHighlightedAttrs,
                        statusAttrs: statusAttrs)

    theme.setRulerStyles(paragraphStyle: paragraphStyle,
                         preeditParagraphStyle: preeditParagraphStyle,
                         pagingParagraphStyle: pagingParagraphStyle,
                         statusParagraphStyle: statusParagraphStyle)

    theme.setColors(backColor: backColor,
                    highlightedCandidateBackColor: highlightedCandidateBackColor,
                    highlightedPreeditBackColor: highlightedBackColor,
                    preeditBackColor: preeditBackColor,
                    borderColor: borderColor,
                    backImage: backImage)

    theme.setCandidateFormat(candidateFormat ?? kDefaultCandidateFormat)
    theme.setStatusMessageType(statusMessageType)
  }
}  // SquirrelPanel

