#import "SquirrelPanel.h"

#import "SquirrelConfig.h"
#import <QuartzCore/QuartzCore.h>

@implementation NSBezierPath (BezierPathQuartzUtilities)
// This method works only in OS X v10.2 and later.
- (CGPathRef)quartzPath {
  if (@available(macOS 14.0, *)) {
    return self.CGPath;
  } else {
    // Need to begin a path here.
    CGPathRef immutablePath = NULL;
    // Then draw the path elements.
    NSUInteger numElements = self.elementCount;
    if (numElements > 0) {
      CGMutablePathRef path = CGPathCreateMutable();
      NSPoint points[3];
      BOOL didClosePath = YES;
      for (NSUInteger i = 0; i < numElements; i++) {
        switch ([self elementAtIndex:i associatedPoints:points]) {
          case NSMoveToBezierPathElement:
            CGPathMoveToPoint(path, NULL, points[0].x, points[0].y);
            break;
          case NSLineToBezierPathElement:
            CGPathAddLineToPoint(path, NULL, points[0].x, points[0].y);
            didClosePath = NO;
            break;
          case NSCurveToBezierPathElement:
            CGPathAddCurveToPoint(path, NULL, points[0].x, points[0].y,
                                  points[1].x, points[1].y,
                                  points[2].x, points[2].y);
            didClosePath = NO;
            break;
          case NSBezierPathElementQuadraticCurveTo:
            CGPathAddQuadCurveToPoint(path, NULL, points[0].x, points[0].y,
                                      points[1].x, points[1].y);
            didClosePath = NO;
            break;
          case NSClosePathBezierPathElement:
            CGPathCloseSubpath(path);
            didClosePath = YES;
            break;
        }
      }
     // Be sure the path is closed or Quartz may not do valid hit detection.
      if (!didClosePath) {
        CGPathCloseSubpath(path);
      }
      immutablePath = CFAutorelease(CGPathCreateCopy(path));
      CGPathRelease(path);
    }
    return immutablePath;
  }
}
@end

static const CGFloat kOffsetHeight = 5;
static const CGFloat kDefaultFontSize = 24;
static const CGFloat kBlendedBackgroundColorFraction = 1.0 / 5;
static const NSTimeInterval kShowStatusDuration = 1.2;
static NSString *const kDefaultCandidateFormat = @"%c %@";

@interface SquirrelTheme : NSObject

@property(nonatomic, assign) BOOL native;

@property(nonatomic, strong, readonly) NSColor *backgroundColor;
@property(nonatomic, strong, readonly) NSColor *backgroundImage;
@property(nonatomic, strong, readonly) NSColor *highlightedStripColor;
@property(nonatomic, strong, readonly) NSColor *highlightedPreeditColor;
@property(nonatomic, strong, readonly) NSColor *preeditBackgroundColor;
@property(nonatomic, strong, readonly) NSColor *borderColor;

@property(nonatomic, readonly) CGFloat cornerRadius;
@property(nonatomic, readonly) CGFloat hilitedCornerRadius;
@property(nonatomic, readonly) NSSize edgeInset;
@property(nonatomic, readonly) CGFloat linespace;
@property(nonatomic, readonly) CGFloat preeditLinespace;
@property(nonatomic, readonly) CGFloat alpha;
@property(nonatomic, readonly) CGFloat translucency;
@property(nonatomic, readonly) CGFloat lineLength;
@property(nonatomic, readonly) BOOL showPaging;
@property(nonatomic, readonly) BOOL rememberSize;
@property(nonatomic, readonly) BOOL linear;
@property(nonatomic, readonly) BOOL vertical;
@property(nonatomic, readonly) BOOL inlinePreedit;
@property(nonatomic, readonly) BOOL inlineCandidate;

@property(nonatomic, strong, readonly) NSDictionary *attrs;
@property(nonatomic, strong, readonly) NSDictionary *highlightedAttrs;
@property(nonatomic, strong, readonly) NSDictionary *labelAttrs;
@property(nonatomic, strong, readonly) NSDictionary *labelHighlightedAttrs;
@property(nonatomic, strong, readonly) NSDictionary *commentAttrs;
@property(nonatomic, strong, readonly) NSDictionary *commentHighlightedAttrs;
@property(nonatomic, strong, readonly) NSDictionary *preeditAttrs;
@property(nonatomic, strong, readonly) NSDictionary *preeditHighlightedAttrs;
@property(nonatomic, strong, readonly) NSDictionary *pagingAttrs;
@property(nonatomic, strong, readonly) NSDictionary *pagingHighlightedAttrs;
@property(nonatomic, strong, readonly) NSDictionary *statusAttrs;
@property(nonatomic, strong, readonly) NSParagraphStyle *paragraphStyle;
@property(nonatomic, strong, readonly) NSParagraphStyle *preeditParagraphStyle;
@property(nonatomic, strong, readonly) NSParagraphStyle *pagingParagraphStyle;
@property(nonatomic, strong, readonly) NSParagraphStyle *statusParagraphStyle;

@property(nonatomic, strong, readonly) NSAttributedString *symbolBackFill;
@property(nonatomic, strong, readonly) NSAttributedString *symbolBackStroke;
@property(nonatomic, strong, readonly) NSAttributedString *symbolForwardFill;
@property(nonatomic, strong, readonly) NSAttributedString *symbolForwardStroke;

@property(nonatomic, strong, readonly) NSString *prefixLabelFormat;
@property(nonatomic, strong, readonly) NSString *suffixLabelFormat;
@property(nonatomic, strong, readonly) NSString *statusMessageType;

- (void)setCandidateFormat:(NSString *)candidateFormat;
- (void)setStatusMessageType:(NSString *)statusMessageType;

- (void)setBackgroundColor:(NSColor *)backgroundColor
           backgroundImage:(NSColor *)backgroundImage
     highlightedStripColor:(NSColor *)highlightedStripColor
   highlightedPreeditColor:(NSColor *)highlightedPreeditColor
    preeditBackgroundColor:(NSColor *)preeditBackgroundColor
               borderColor:(NSColor *)borderColor;

- (void)setCornerRadius:(CGFloat)cornerRadius
    hilitedCornerRadius:(CGFloat)hilitedCornerRadius
              edgeInset:(NSSize)edgeInset
              linespace:(CGFloat)linespace
       preeditLinespace:(CGFloat)preeditLinespace
                  alpha:(CGFloat)alpha
           translucency:(CGFloat)translucency
             lineLength:(CGFloat)lineLength
             showPaging:(BOOL)showPaging
           rememberSize:(BOOL)rememberSize
                 linear:(BOOL)linear
               vertical:(BOOL)vertical
          inlinePreedit:(BOOL)inlinePreedit
        inlineCandidate:(BOOL)inlineCandidate;

- (void)         setAttrs:(NSMutableDictionary *)attrs
         highlightedAttrs:(NSMutableDictionary *)highlightedAttrs
               labelAttrs:(NSMutableDictionary *)labelAttrs
    labelHighlightedAttrs:(NSMutableDictionary *)labelHighlightedAttrs
             commentAttrs:(NSMutableDictionary *)commentAttrs
  commentHighlightedAttrs:(NSMutableDictionary *)commentHighlightedAttrs
             preeditAttrs:(NSMutableDictionary *)preeditAttrs
  preeditHighlightedAttrs:(NSMutableDictionary *)preeditHighlightedAttrs
              pagingAttrs:(NSMutableDictionary *)pagingAttrs
   pagingHighlightedAttrs:(NSMutableDictionary *)pagingHighlightedAttrs
              statusAttrs:(NSMutableDictionary *)statusAttrs;

- (void)setParagraphStyle:(NSParagraphStyle *)paragraphStyle
    preeditParagraphStyle:(NSParagraphStyle *)preeditParagraphStyle
     pagingParagraphStyle:(NSParagraphStyle *)pagingParagraphStyle
     statusParagraphStyle:(NSParagraphStyle *)statusParagraphStyle;

@end

@implementation SquirrelTheme

- (void)setCandidateFormat:(NSString *)candidateFormat {
  // in the candiate format, everything other than '%@' is considered part of the label
  NSRange candidateRange = [candidateFormat rangeOfString:@"%@"];
  if (candidateRange.location == NSNotFound) {
    _prefixLabelFormat = candidateFormat;
    _suffixLabelFormat = nil;
    return;
  }
  if (candidateRange.location > 0) {
    // everything before '%@' is prefix label
    NSRange prefixLabelRange = NSMakeRange(0, candidateRange.location);
    _prefixLabelFormat = [candidateFormat substringWithRange:prefixLabelRange];
  } else {
    _prefixLabelFormat = nil;
  }
  if (NSMaxRange(candidateRange) < candidateFormat.length) {
    // everything after '%@' is suffix label
    NSRange suffixLabelRange = NSMakeRange(NSMaxRange(candidateRange),
                                           candidateFormat.length - NSMaxRange(candidateRange));
    _suffixLabelFormat = [candidateFormat substringWithRange:suffixLabelRange];
  } else {
    // '%@' is at the end, so suffix label does not exist
    _suffixLabelFormat = nil;
  }
}

- (void)setStatusMessageType:(NSString *)type {
  if ([type isEqualToString:@"long"] || [type isEqualToString:@"short"] || [type isEqualToString:@"mix"]) {
    _statusMessageType = type;
  } else {
    _statusMessageType = @"mix";
  }
}

- (void)setBackgroundColor:(NSColor *)backgroundColor
           backgroundImage:(NSColor *)backgroundImage
     highlightedStripColor:(NSColor *)highlightedStripColor
   highlightedPreeditColor:(NSColor *)highlightedPreeditColor
    preeditBackgroundColor:(NSColor *)preeditBackgroundColor
               borderColor:(NSColor *)borderColor {
  _backgroundColor = backgroundColor;
  _backgroundImage = backgroundImage;
  _highlightedStripColor = highlightedStripColor;
  _highlightedPreeditColor = highlightedPreeditColor;
  _preeditBackgroundColor = preeditBackgroundColor;
  _borderColor = borderColor;
}

- (void)setCornerRadius:(CGFloat)cornerRadius
    hilitedCornerRadius:(CGFloat)hilitedCornerRadius
              edgeInset:(NSSize)edgeInset
              linespace:(CGFloat)linespace
       preeditLinespace:(CGFloat)preeditLinespace
                  alpha:(CGFloat)alpha
           translucency:(CGFloat)translucency
             lineLength:(CGFloat)lineLength
             showPaging:(BOOL)showPaging
           rememberSize:(BOOL)rememberSize
                 linear:(BOOL)linear
               vertical:(BOOL)vertical
          inlinePreedit:(BOOL)inlinePreedit
        inlineCandidate:(BOOL)inlineCandidate {
  _cornerRadius = cornerRadius;
  _hilitedCornerRadius = hilitedCornerRadius;
  _edgeInset = edgeInset;
  _linespace = linespace;
  _preeditLinespace = preeditLinespace;
  _alpha = alpha;
  _translucency = translucency;
  _lineLength = lineLength;
  _showPaging = showPaging;
  _rememberSize = rememberSize;
  _linear = linear;
  _vertical = vertical;
  _inlinePreedit = inlinePreedit;
  _inlineCandidate = inlineCandidate;
}

- (void)         setAttrs:(NSMutableDictionary *)attrs
         highlightedAttrs:(NSMutableDictionary *)highlightedAttrs
               labelAttrs:(NSMutableDictionary *)labelAttrs
    labelHighlightedAttrs:(NSMutableDictionary *)labelHighlightedAttrs
             commentAttrs:(NSMutableDictionary *)commentAttrs
  commentHighlightedAttrs:(NSMutableDictionary *)commentHighlightedAttrs
             preeditAttrs:(NSMutableDictionary *)preeditAttrs
  preeditHighlightedAttrs:(NSMutableDictionary *)preeditHighlightedAttrs
              pagingAttrs:(NSMutableDictionary *)pagingAttrs
   pagingHighlightedAttrs:(NSMutableDictionary *)pagingHighlightedAttrs
              statusAttrs:(NSMutableDictionary *)statusAttrs {
  _attrs = attrs;
  _highlightedAttrs = highlightedAttrs;
  _labelAttrs = labelAttrs;
  _labelHighlightedAttrs = labelHighlightedAttrs;
  _commentAttrs = commentAttrs;
  _commentHighlightedAttrs = commentHighlightedAttrs;
  _preeditAttrs = preeditAttrs;
  _preeditHighlightedAttrs = preeditHighlightedAttrs;
  _pagingAttrs = pagingAttrs;
  _pagingHighlightedAttrs = pagingHighlightedAttrs;
  _statusAttrs = statusAttrs;
  NSMutableDictionary *symbolAttrs = [pagingAttrs mutableCopy];
  if (@available(macOS 12.0, *)) {
    symbolAttrs[NSVerticalGlyphFormAttributeName] = @(_vertical && _linear);

    _symbolBackFill = [[NSAttributedString alloc]
                       initWithString:(_vertical && _linear ? @"􀁧" : @"􀁫") attributes:symbolAttrs];
    _symbolBackStroke = [[NSAttributedString alloc]
                         initWithString:(_vertical && _linear ? @"􀁦" : @"􀁪") attributes:symbolAttrs];
    _symbolForwardFill = [[NSAttributedString alloc]
                          initWithString:(_vertical && _linear ? @"􀁩" : @"􀁭") attributes:symbolAttrs];
    _symbolForwardStroke = [[NSAttributedString alloc]
                            initWithString:(_vertical && _linear ? @"􀁨" : @"􀁬") attributes:symbolAttrs];
  } else {
    NSFont *symbolFont = [NSFont fontWithDescriptor:[[NSFontDescriptor fontDescriptorWithName:@"AppleSymbols" size:0.0]
                                                     fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitUIOptimized]
                                               size:[labelAttrs[NSFontAttributeName] pointSize]];
    symbolAttrs[NSFontAttributeName] = symbolFont;

    NSMutableDictionary *symbolAttrsBackFill = [symbolAttrs mutableCopy];
    symbolAttrsBackFill[NSGlyphInfoAttributeName] = [NSGlyphInfo glyphInfoWithGlyphName:@"gid4966" forFont:symbolFont baseString:@"◀\uFE0E"];
    _symbolBackFill = [[NSAttributedString alloc] initWithString:@"◀\uFE0E" attributes:symbolAttrsBackFill];

    NSMutableDictionary *symbolAttrsBackStroke = [symbolAttrs mutableCopy];
    symbolAttrsBackStroke[NSGlyphInfoAttributeName] = [NSGlyphInfo glyphInfoWithGlyphName:@"gid4969" forFont:symbolFont baseString:@"◁\uFE0E"];
    _symbolBackStroke = [[NSAttributedString alloc] initWithString:@"◁\uFE0E" attributes:symbolAttrsBackStroke];

    NSMutableDictionary *symbolAttrsForwardFill = [symbolAttrs mutableCopy];
    symbolAttrsForwardFill[NSGlyphInfoAttributeName] = [NSGlyphInfo glyphInfoWithGlyphName:@"gid4967" forFont:symbolFont baseString:@"▶\uFE0E"];
    _symbolForwardFill = [[NSAttributedString alloc] initWithString:@"▶\uFE0E" attributes:symbolAttrsForwardFill];

    NSMutableDictionary *symbolAttrsForwardStroke = [symbolAttrs mutableCopy];
    symbolAttrsForwardStroke[NSGlyphInfoAttributeName] = [NSGlyphInfo glyphInfoWithGlyphName:@"gid4968" forFont:symbolFont baseString:@"▷\uFE0E"];
    _symbolForwardStroke = [[NSAttributedString alloc] initWithString:@"▷\uFE0E" attributes:symbolAttrsForwardStroke];
  }
}

- (void)setParagraphStyle:(NSParagraphStyle *)paragraphStyle
    preeditParagraphStyle:(NSParagraphStyle *)preeditParagraphStyle
     pagingParagraphStyle:(NSParagraphStyle *)pagingParagraphStyle
     statusParagraphStyle:(NSParagraphStyle *)statusParagraphStyle {
  _paragraphStyle = paragraphStyle;
  _preeditParagraphStyle = preeditParagraphStyle;
  _pagingParagraphStyle = pagingParagraphStyle;
  _statusParagraphStyle = statusParagraphStyle;
}

@end

@interface SquirrelView : NSView

@property(nonatomic, readonly) NSTextView *textView;
@property(nonatomic, readonly) NSTextStorage *textStorage;
@property(nonatomic, readonly) NSEdgeInsets insets;
@property(nonatomic, readonly) NSArray<NSValue *> *candidateRanges;
@property(nonatomic, readonly) NSUInteger highlightedIndex;
@property(nonatomic, readonly) NSRange preeditRange;
@property(nonatomic, readonly) NSRange highlightedPreeditRange;
@property(nonatomic, readonly) NSRange pagingRange;
@property(nonatomic, readonly) NSRect contentRect;
@property(nonatomic, readonly) NSMutableArray<NSBezierPath *> *candidatePaths;
@property(nonatomic, readonly) NSMutableArray<NSBezierPath *> *pagingPaths;
@property(nonatomic, readonly) NSUInteger pagingButton;
@property(nonatomic, readonly) BOOL isDark;
@property(nonatomic, strong, readonly) SquirrelTheme *currentTheme;
@property(nonatomic, assign) CGFloat separatorWidth;
@property(nonatomic, readonly) CAShapeLayer *shape;
@property(nonatomic, getter = isFlipped, readonly) BOOL flipped;
@property(nonatomic, readonly) BOOL wantsUpdateLayer;

- (void) drawViewWithInsets:(NSEdgeInsets)insets
            candidateRanges:(NSArray<NSValue *> *)candidateRanges
           highlightedIndex:(NSUInteger)highlightedIndex
               preeditRange:(NSRange)preeditRange
    highlightedPreeditRange:(NSRange)highlightedPreeditRange
                pagingRange:(NSRange)pagingRange
               pagingButton:(NSUInteger)pagingButton;
- (NSRect)contentRectForRange:(NSRange)range;

@end

@implementation SquirrelView

SquirrelTheme *_defaultTheme;
SquirrelTheme *_darkTheme;

// Need flipped coordinate system, as required by textStorage
- (BOOL)isFlipped {
  return YES;
}

- (BOOL)wantsUpdateLayer {
  return YES;
}

- (BOOL)isDark {
  if (@available(macOS 10.14, *)) {
    if ([NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)allowsVibrancy {
  return YES;
}

- (SquirrelTheme *)selectTheme:(BOOL)isDark {
  return isDark ? _darkTheme : _defaultTheme;
}

- (SquirrelTheme *)currentTheme {
  return [self selectTheme:self.isDark];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
    self.layer.geometryFlipped = YES;
    self.layer.masksToBounds = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
  }

  if (@available(macOS 12.0, *)) {
    NSTextLayoutManager *textLayoutManager = [[NSTextLayoutManager alloc] init];
    textLayoutManager.usesFontLeading = NO;
    NSTextContainer *textContainer = [[NSTextContainer alloc]
                                      initWithSize:NSMakeSize(NSViewWidthSizable, CGFLOAT_MAX)];
    textLayoutManager.textContainer = textContainer;
    NSTextContentStorage *contentStorage = [[NSTextContentStorage alloc] init];
    [contentStorage addTextLayoutManager:textLayoutManager];
    _textView = [[NSTextView alloc] initWithFrame:frameRect
                                    textContainer:textLayoutManager.textContainer];
    _textStorage = _textView.textContentStorage.textStorage;
  } else {
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    layoutManager.backgroundLayoutEnabled = YES;
    layoutManager.usesFontLeading = NO;
    layoutManager.typesetterBehavior = NSTypesetterLatestBehavior;
    NSTextContainer *textContainer = [[NSTextContainer alloc]
                                      initWithContainerSize:NSMakeSize(NSViewWidthSizable, CGFLOAT_MAX)];
    [layoutManager addTextContainer:textContainer];
    _textStorage = [[NSTextStorage alloc] init];
    [_textStorage addLayoutManager:layoutManager];
    _textView = [[NSTextView alloc] initWithFrame:frameRect
                                    textContainer:textContainer];
  }
  _textView.drawsBackground = NO;
  _textView.editable = NO;
  _textView.selectable = NO;
  _textView.wantsLayer = NO;

  _defaultTheme = [[SquirrelTheme alloc] init];
  _shape = [[CAShapeLayer alloc] init];
  if (@available(macOS 10.14, *)) {
    _darkTheme = [[SquirrelTheme alloc] init];
  }
  return self;
}

- (NSTextRange *)getTextRangeFromRange:(NSRange)range API_AVAILABLE(macos(12.0)) {
  if (range.location == NSNotFound) {
    return nil;
  } else {
    NSTextContentStorage *contentStorage = _textView.textContentStorage;
    id<NSTextLocation> startLocation = [contentStorage locationFromLocation:contentStorage.documentRange.location withOffset:range.location];
    id<NSTextLocation> endLocation = [contentStorage locationFromLocation:startLocation withOffset:range.length];
    return [[NSTextRange alloc] initWithLocation:startLocation endLocation:endLocation];
  }
}


// Get the rectangle containing entire contents, expensive to calculate
- (NSRect)contentRect {
  if (@available(macOS 12.0, *)) {
    [_textView.textLayoutManager ensureLayoutForRange:_textView.textContentStorage.documentRange];
    NSRect rect = [_textView.textLayoutManager usageBoundsForTextContainer];
    if (@available(macOS 14.0, *)) { // lineFragments no longer include Paddings as of macOS 14
      rect = NSInsetRect(rect, -_textView.textContainer.lineFragmentPadding, 0);
    }
    return rect;
  } else {
    [_textView.layoutManager ensureLayoutForTextContainer:_textView.textContainer];
    return [_textView.layoutManager usedRectForTextContainer:_textView.textContainer];
  }
}

// Get the rectangle containing the range of text, will first convert to glyph or text range, expensive to calculate
- (NSRect)contentRectForRange:(NSRange)range {
  if (@available(macOS 12.0, *)) {
    NSTextRange *textRange = [self getTextRangeFromRange:range];
    __block NSRect contentRect = NSZeroRect;
    [_textView.textLayoutManager
     enumerateTextSegmentsInRange:textRange
     type:NSTextLayoutManagerSegmentTypeStandard
     options:NSTextLayoutManagerSegmentOptionsRangeNotRequired
     usingBlock:^(NSTextRange *segRange, CGRect segFrame, CGFloat baseline, NSTextContainer *textContainer) {
      contentRect = NSUnionRect(contentRect, segFrame);
      return YES;
    }];
    CGFloat lineSpacing = [[_textStorage attribute:NSParagraphStyleAttributeName atIndex:NSMaxRange(range)-1 effectiveRange:NULL] lineSpacing];
    contentRect.size.height += lineSpacing;
    return contentRect;
  } else {
    NSTextContainer *textContainer = _textView.textContainer;
    NSLayoutManager *layoutManager = _textView.layoutManager;
    NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:range
                                               actualCharacterRange:NULL];
    NSRange firstLineRange = NSMakeRange(NSNotFound, 0);
    NSRect firstLineRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphRange.location
                                                               effectiveRange:&firstLineRange];
    if (NSMaxRange(glyphRange) <= NSMaxRange(firstLineRange)) {
      CGFloat startX = [layoutManager locationForGlyphAtIndex:glyphRange.location].x;
      CGFloat endX = NSMaxRange(glyphRange) < NSMaxRange(firstLineRange)
        ? [layoutManager locationForGlyphAtIndex:NSMaxRange(glyphRange)].x
        : NSWidth(firstLineRect) - textContainer.lineFragmentPadding;
      return NSMakeRect(NSMinX(firstLineRect) + startX, NSMinY(firstLineRect),
                        endX - startX, NSHeight(firstLineRect));
    } else {
      NSRect finalLineRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:NSMaxRange(glyphRange)-1
                                                                 effectiveRange:NULL];
      return NSMakeRect(textContainer.lineFragmentPadding, NSMinY(firstLineRect),
                        textContainer.size.width - textContainer.lineFragmentPadding * 2,
                        NSMaxY(finalLineRect) - NSMinY(firstLineRect));
    }
  }
}

// Will triger - (void)drawRect:(NSRect)dirtyRect
- (void) drawViewWithInsets:(NSEdgeInsets)insets
            candidateRanges:(NSArray<NSValue *> *)candidateRanges
           highlightedIndex:(NSUInteger)highlightedIndex
               preeditRange:(NSRange)preeditRange
    highlightedPreeditRange:(NSRange)highlightedPreeditRange
                pagingRange:(NSRange)pagingRange
               pagingButton:(NSUInteger)pagingButton {
  _insets = insets;
  _candidateRanges = candidateRanges;
  _highlightedIndex = highlightedIndex;
  _preeditRange = preeditRange;
  _highlightedPreeditRange = highlightedPreeditRange;
  _pagingRange = pagingRange;
  _pagingButton = pagingButton;
  _candidatePaths = [[NSMutableArray alloc] initWithCapacity:candidateRanges.count];
  _pagingPaths = [[NSMutableArray alloc] initWithCapacity:pagingRange.length > 0 ? 2 : 0];
  self.needsDisplay = YES;
}

// Bezier cubic curve, which has continuous roundness
NSBezierPath * drawRoundedPolygon(NSArray<NSValue *> *vertex, CGFloat radius) {
  NSBezierPath *path = [NSBezierPath bezierPath];
  if (vertex.count < 1) {
    return path;
  }
  NSPoint previousPoint = vertex.lastObject.pointValue;
  NSPoint point = vertex.firstObject.pointValue;
  NSPoint nextPoint;
  NSPoint startPoint;
  NSPoint endPoint = previousPoint;
  CGFloat arcRadius;
  CGVector diff = CGVectorMake(point.x - previousPoint.x, point.y - previousPoint.y);
  if (ABS(diff.dx) >= ABS(diff.dy)) {
    endPoint.x += diff.dx / 2;
    endPoint.y = point.y;
  } else {
    endPoint.y += diff.dy / 2;
    endPoint.x = point.x;
  }
  [path moveToPoint:endPoint];
  for (NSUInteger i = 0; i < vertex.count; ++i) {
    startPoint = endPoint;
    point = vertex[i].pointValue;
    nextPoint = vertex[(i + 1) % vertex.count].pointValue;
    arcRadius = MIN(radius, MAX(ABS(point.x - startPoint.x), ABS(point.y - startPoint.y)));
    endPoint = point;
    diff = CGVectorMake(nextPoint.x - point.x, nextPoint.y - point.y);
    if (ABS(diff.dx) > ABS(diff.dy)) {
      endPoint.x += diff.dx / 2;
      arcRadius = MIN(arcRadius, ABS(diff.dx) / 2);
      endPoint.y = nextPoint.y;
      point.y = nextPoint.y;
    } else {
      endPoint.y += diff.dy / 2;
      arcRadius = MIN(arcRadius, ABS(diff.dy) / 2);
      endPoint.x = nextPoint.x;
      point.x = nextPoint.x;
    }
    [path appendBezierPathWithArcFromPoint:point toPoint:endPoint radius:arcRadius];
  }
  [path closePath];
  return path;
}

NSArray<NSValue *> * rectVertex(NSRect rect) {
  return @[@(rect.origin),
           @(NSMakePoint(rect.origin.x, rect.origin.y + rect.size.height)),
           @(NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height)),
           @(NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y))];
}

BOOL nearEmptyRect(NSRect rect) {
  return NSHeight(rect) * NSWidth(rect) < 1;
}

// Calculate 3 boxes containing the text in range. leadingRect and trailingRect are incomplete line rectangle
// bodyRect is the complete line fragment in the middle if the range spans no less than one full line
- (void)multilineRectForRange:(NSRange)charRange leadingRect:(NSRectPointer)leadingRect bodyRect:(NSRectPointer)bodyRect trailingRect:(NSRectPointer)trailingRect {
  if (@available(macOS 12.0, *)) {
    NSTextRange *textRange = [self getTextRangeFromRange:charRange];
    CGFloat lineSpacing = [[_textStorage attribute:NSParagraphStyleAttributeName atIndex:charRange.location effectiveRange:NULL] lineSpacing];
    NSMutableArray<NSValue *> *lineRects = [[NSMutableArray alloc] initWithCapacity:2];
    NSMutableArray<NSTextRange *> *lineRanges = [[NSMutableArray alloc] initWithCapacity:2];
    [_textView.textLayoutManager
     enumerateTextSegmentsInRange:textRange
     type:NSTextLayoutManagerSegmentTypeStandard
     options:NSTextLayoutManagerSegmentOptionsMiddleFragmentsExcluded
     usingBlock:^(NSTextRange *segRange, CGRect segFrame, CGFloat baseline, NSTextContainer *textContainer) {
      if (!nearEmptyRect(segFrame)) {
        segFrame.size.height += lineSpacing;
        [lineRects addObject:[NSValue valueWithRect:segFrame]];
        [lineRanges addObject:segRange];
      }
      return YES;
    }];
    if (lineRects.count == 1) {
      *bodyRect = lineRects[0].rectValue;
    } else {
      CGFloat rightEdge = _textView.textContainer.size.width - _textView.textContainer.lineFragmentPadding;
      NSRect leadingLineRect = lineRects.firstObject.rectValue;
      leadingLineRect.size.width = rightEdge - NSMinX(leadingLineRect);
      NSRect trailingLineRect = lineRects.lastObject.rectValue;
      CGFloat leftEdge = _textView.textContainer.lineFragmentPadding;
      if (NSMaxX(trailingLineRect) == NSMaxX(leadingLineRect)) {
        if (NSMinX(leadingLineRect) == NSMinX(trailingLineRect)) {
          *bodyRect = NSUnionRect(leadingLineRect, trailingLineRect);
        } else {
          *leadingRect = leadingLineRect;
          *bodyRect = NSMakeRect(leftEdge, NSMaxY(leadingLineRect), rightEdge - leftEdge,
                                 NSMaxY(trailingLineRect) - NSMaxY(leadingLineRect));
        }
      } else {
        *trailingRect = trailingLineRect;
        if (NSMinX(leadingLineRect) == NSMinX(trailingLineRect)) {
          *bodyRect = NSMakeRect(leftEdge, NSMinY(leadingLineRect), rightEdge - leftEdge,
                                 NSMinY(trailingLineRect) - NSMinY(leadingLineRect));
        } else {
          *leadingRect = leadingLineRect;
          if (lineRanges.lastObject.location > lineRanges.firstObject.endLocation) {
            *bodyRect = NSMakeRect(leftEdge, NSMaxY(leadingLineRect), rightEdge - leftEdge,
                                   NSMinY(trailingLineRect) - NSMaxY(leadingLineRect));
          }
        }
      }
    }
  } else {
    NSLayoutManager *layoutManager = _textView.layoutManager;
    NSTextContainer *textContainer = _textView.textContainer;
    NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange
                                               actualCharacterRange:NULL];
    NSRange leadingLineRange = NSMakeRange(NSNotFound, 0);
    NSRect leadingLineRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphRange.location
                                                                 effectiveRange:&leadingLineRange];
    CGFloat startX = [layoutManager locationForGlyphAtIndex:glyphRange.location].x;
    if (NSMaxRange(leadingLineRange) >= NSMaxRange(glyphRange)) {
      CGFloat endX = NSMaxRange(glyphRange) < NSMaxRange(leadingLineRange)
        ? [layoutManager locationForGlyphAtIndex:NSMaxRange(glyphRange)].x
        : NSWidth(leadingLineRect) - textContainer.lineFragmentPadding;
      *bodyRect = NSMakeRect(startX, NSMinY(leadingLineRect),
                             endX - startX, NSHeight(leadingLineRect));
    } else {
      CGFloat rightEdge = textContainer.size.width - textContainer.lineFragmentPadding;
      NSRange trailingLineRange = NSMakeRange(NSNotFound, 0);
      NSRect trailingLineRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:NSMaxRange(glyphRange) - 1
                                                                    effectiveRange:&trailingLineRange];
      CGFloat endX = NSMaxRange(glyphRange) < NSMaxRange(trailingLineRange)
        ? [layoutManager locationForGlyphAtIndex:NSMaxRange(glyphRange)].x
        : NSWidth(trailingLineRect) - textContainer.lineFragmentPadding;
      CGFloat leftEdge = textContainer.lineFragmentPadding;
      if (NSMaxRange(trailingLineRange) == NSMaxRange(glyphRange)) {
        if (glyphRange.location == leadingLineRange.location) {
          *bodyRect = NSMakeRect(leftEdge, NSMinY(leadingLineRect), rightEdge - leftEdge,
                                 NSMaxY(trailingLineRect) - NSMinY(leadingLineRect));
        } else {
          *leadingRect = NSMakeRect(startX, NSMinY(leadingLineRect),
                                    rightEdge - startX, NSHeight(leadingLineRect));
          *bodyRect = NSMakeRect(leftEdge, NSMaxY(leadingLineRect), rightEdge - leftEdge,
                                 NSMaxY(trailingLineRect) - NSMaxY(leadingLineRect));
        }
      } else {
        *trailingRect = NSMakeRect(leftEdge, NSMinY(trailingLineRect),
                                   endX - leftEdge, NSHeight(trailingLineRect));
        if (glyphRange.location == leadingLineRange.location) {
          *bodyRect = NSMakeRect(leftEdge, NSMinY(leadingLineRect), rightEdge - leftEdge,
                                 NSMinY(trailingLineRect) - NSMinY(leadingLineRect));
        } else {
          *leadingRect = NSMakeRect(startX, NSMinY(leadingLineRect),
                                    rightEdge - startX, NSHeight(leadingLineRect));
          if (trailingLineRange.location > NSMaxRange(leadingLineRange)) {
            *bodyRect = NSMakeRect(leftEdge, NSMaxY(leadingLineRect), rightEdge - leftEdge,
                                   NSMinY(trailingLineRect) - NSMaxY(leadingLineRect));
          }
        }
      }
    }
  }
}

// Based on the 3 boxes from multilineRectForRange, calculate the vertex of the polygon containing the text in range
NSArray<NSValue *> * multilineRectVertex(NSRect leadingRect, NSRect bodyRect, NSRect trailingRect) {
  if (nearEmptyRect(bodyRect) && !nearEmptyRect(leadingRect) && nearEmptyRect(trailingRect)) {
    return rectVertex(leadingRect);
  } else if (nearEmptyRect(bodyRect) && nearEmptyRect(leadingRect) && !nearEmptyRect(trailingRect)) {
    return rectVertex(trailingRect);
  } else if (nearEmptyRect(leadingRect) && nearEmptyRect(trailingRect) && !nearEmptyRect(bodyRect)) {
    return rectVertex(bodyRect);
  } else if (nearEmptyRect(trailingRect) && !nearEmptyRect(bodyRect)) {
    NSArray<NSValue *> *leadingVertex = rectVertex(leadingRect);
    NSArray<NSValue *> *bodyVertex = rectVertex(bodyRect);
    return @[leadingVertex[0], leadingVertex[1], bodyVertex[0], bodyVertex[1], bodyVertex[2], leadingVertex[3]];
  } else if (nearEmptyRect(leadingRect) && !nearEmptyRect(bodyRect)) {
    NSArray<NSValue *> *trailingVertex = rectVertex(trailingRect);
    NSArray<NSValue *> *bodyVertex = rectVertex(bodyRect);
    return @[bodyVertex[0], trailingVertex[1], trailingVertex[2], trailingVertex[3], bodyVertex[2], bodyVertex[3]];
  } else if (!nearEmptyRect(leadingRect) && !nearEmptyRect(trailingRect) &&
             nearEmptyRect(bodyRect) && NSMaxX(leadingRect) > NSMinX(trailingRect)) {
    NSArray<NSValue *> *leadingVertex = rectVertex(leadingRect);
    NSArray<NSValue *> *trailingVertex = rectVertex(trailingRect);
    return @[leadingVertex[0], leadingVertex[1], trailingVertex[0], trailingVertex[1],
             trailingVertex[2], trailingVertex[3], leadingVertex[2], leadingVertex[3]];
  } else if (!nearEmptyRect(leadingRect) && !nearEmptyRect(trailingRect) && !nearEmptyRect(bodyRect)) {
    NSArray<NSValue *> *leadingVertex = rectVertex(leadingRect);
    NSArray<NSValue *> *bodyVertex = rectVertex(bodyRect);
    NSArray<NSValue *> *trailingVertex = rectVertex(trailingRect);
    return @[leadingVertex[0], leadingVertex[1], bodyVertex[0], trailingVertex[1],
             trailingVertex[2], trailingVertex[3], bodyVertex[2], leadingVertex[3]];
  } else {
    return @[];
  }
}

NSColor * hooverColor(NSColor *color, BOOL darkTheme) {
  if (@available(macOS 10.14, *)) {
    return [color colorWithSystemEffect:NSColorSystemEffectRollover];
  }
  if (darkTheme) {
    return [color highlightWithLevel:0.3];
  } else {
    return [color shadowWithLevel:0.3];
  }
}

NSColor * disabledColor(NSColor *color, BOOL darkTheme) {
  if (@available(macOS 10.14, *)) {
    return [color colorWithSystemEffect:NSColorSystemEffectDisabled];
  }
  if (darkTheme) {
    return [color shadowWithLevel:0.3];
  } else {
    return [color highlightWithLevel:0.3];
  }
}

// All draws happen here
- (void)updateLayer {
  NSBezierPath *backgroundPath;
  NSBezierPath *borderPath;
  NSBezierPath *textContainerPath;
  NSBezierPath *highlightedPath;
  NSBezierPath *highlightedPreeditPath;
  NSBezierPath *candidateBlockPath;
  NSBezierPath *pageUpPath;
  NSBezierPath *pageDownPath;

  SquirrelTheme *theme = self.currentTheme;
  NSRect backgroundRect = self.bounds;
  NSRect textContainerRect = NSInsetRect(backgroundRect, theme.edgeInset.width, theme.edgeInset.height);
  CGFloat linePadding = _textView.textContainer.lineFragmentPadding;

  NSRange visibleRange;
  if (@available(macOS 12.0, *)) {
    visibleRange = NSMakeRange(0, _textStorage.length);
  } else {
    NSRange containerGlyphRange = {NSNotFound, 0};
    [_textView.layoutManager textContainerForGlyphAtIndex:0 effectiveRange:&containerGlyphRange];
    visibleRange = [_textView.layoutManager characterRangeForGlyphRange:containerGlyphRange actualGlyphRange:NULL];
  }
  NSRange preeditRange = NSIntersectionRange(_preeditRange, visibleRange);
  NSRange candidateBlockRange = NSIntersectionRange(NSUnionRange(_candidateRanges.firstObject.rangeValue, theme.linear && _pagingRange.length > 0 ? _pagingRange : _candidateRanges.lastObject.rangeValue), visibleRange);
  NSRange pagingRange = NSIntersectionRange(_pagingRange, visibleRange);

  NSRect preeditRect = NSZeroRect;
  NSRect candidateBlockRect = NSZeroRect;
  NSRect pagingLineRect = NSZeroRect;
  if (preeditRange.length > 0) {
    preeditRect = [self contentRectForRange:preeditRange];
    if (candidateBlockRange.length > 0) {
      preeditRect.size.height += theme.preeditLinespace;
    }
  }
  if (candidateBlockRange.length > 0) {
    candidateBlockRect = NSInsetRect([self contentRectForRange:candidateBlockRange], 0.0, -theme.linespace/2);
    if (preeditRange.length == 0) {
      candidateBlockRect.origin.y += theme.linespace/2;
    }
  }
  if (!theme.linear && pagingRange.length > 0) {
    pagingLineRect = [self contentRectForRange:pagingRange];
    pagingLineRect.origin.y -= theme.pagingParagraphStyle.paragraphSpacingBefore;
    pagingLineRect.size.height += theme.pagingParagraphStyle.paragraphSpacingBefore;
  }

  [NSBezierPath setDefaultLineWidth:0];
  // Draw preedit Rect
  if (preeditRange.length > 0) {
    preeditRect.size.width = textContainerRect.size.width;
    preeditRect.origin = textContainerRect.origin;
    // Draw highlighted part of preedit text
    NSRange highlightedPreeditRange = NSIntersectionRange(_highlightedPreeditRange, visibleRange);
    if (highlightedPreeditRange.length > 0 && theme.highlightedPreeditColor != nil) {
      NSRect innerBox = NSInsetRect(preeditRect, linePadding, 0);
      if (candidateBlockRange.length > 0) {
        innerBox.size.height -= theme.preeditLinespace;
      }
      NSRect leadingRect = NSZeroRect;
      NSRect bodyRect = NSZeroRect;
      NSRect trailingRect = NSZeroRect;
      [self multilineRectForRange:highlightedPreeditRange leadingRect:&leadingRect bodyRect:&bodyRect trailingRect:&trailingRect];
      leadingRect = nearEmptyRect(leadingRect) ? NSZeroRect
        : NSIntersectionRect(NSOffsetRect(leadingRect, textContainerRect.origin.x, textContainerRect.origin.y), innerBox);
      bodyRect = nearEmptyRect(bodyRect) ? NSZeroRect
        : NSIntersectionRect(NSOffsetRect(bodyRect, textContainerRect.origin.x, textContainerRect.origin.y), innerBox);
      trailingRect = nearEmptyRect(trailingRect) ? NSZeroRect
        : NSIntersectionRect(NSOffsetRect(trailingRect, textContainerRect.origin.x, textContainerRect.origin.y), innerBox);
      NSArray<NSValue *> *highlightedPreeditPoints;
      NSArray<NSValue *> *highlightedPreeditPoints2;
      // Handles the special case where containing boxes are separated
      if (NSIsEmptyRect(bodyRect) && !NSIsEmptyRect(leadingRect) && !NSIsEmptyRect(trailingRect)
          && NSMaxX(trailingRect) < NSMinX(leadingRect)) {
        highlightedPreeditPoints = rectVertex(leadingRect);
        highlightedPreeditPoints2 = rectVertex(trailingRect);
      } else {
        highlightedPreeditPoints = multilineRectVertex(leadingRect, bodyRect, trailingRect);
      }
      highlightedPreeditPath = drawRoundedPolygon(highlightedPreeditPoints, MIN(theme.hilitedCornerRadius, theme.preeditParagraphStyle.maximumLineHeight/3));
      if (highlightedPreeditPoints2.count > 0) {
        [highlightedPreeditPath appendBezierPath:drawRoundedPolygon(highlightedPreeditPoints2, MIN(theme.hilitedCornerRadius, theme.preeditParagraphStyle.maximumLineHeight/3))];
      }
    }
  }

  // Draw candidate Rect
  if (candidateBlockRange.length > 0) {
    candidateBlockRect.size.width = textContainerRect.size.width;
    candidateBlockRect.origin.x = textContainerRect.origin.x;
    candidateBlockRect.origin.y += textContainerRect.origin.y;
    candidateBlockRect = NSIntersectionRect(candidateBlockRect, textContainerRect);
    candidateBlockPath = drawRoundedPolygon(rectVertex(candidateBlockRect), theme.hilitedCornerRadius);

    // Draw candidate highlight rect
    for (NSUInteger i = 0; i < _candidateRanges.count; ++i) {
      NSRange candidateRange = NSIntersectionRange([_candidateRanges[i] rangeValue], visibleRange);
      if (candidateRange.length == 0) {
        break;
      }
      if (theme.linear) {
        NSRect leadingRect = NSZeroRect;
        NSRect bodyRect = NSZeroRect;
        NSRect trailingRect = NSZeroRect;
        [self multilineRectForRange:candidateRange leadingRect:&leadingRect bodyRect:&bodyRect trailingRect:&trailingRect];
        leadingRect = nearEmptyRect(leadingRect) ? NSZeroRect
          : NSInsetRect(NSOffsetRect(leadingRect, textContainerRect.origin.x, textContainerRect.origin.y), -MIN(_separatorWidth / 2, linePadding), 0);
        bodyRect = nearEmptyRect(bodyRect) ? NSZeroRect
          : NSInsetRect(NSOffsetRect(bodyRect, textContainerRect.origin.x, textContainerRect.origin.y), -MIN(_separatorWidth / 2, linePadding), 0);
        trailingRect = nearEmptyRect(trailingRect) ? NSZeroRect
          : NSInsetRect(NSOffsetRect(trailingRect, textContainerRect.origin.x, textContainerRect.origin.y), -MIN(_separatorWidth / 2, linePadding), 0);
        if (preeditRange.length == 0) {
          leadingRect.origin.y += theme.linespace / 2;
          bodyRect.origin.y += theme.linespace / 2;
          trailingRect.origin.y += theme.linespace / 2;
        }
        if (!NSIsEmptyRect(leadingRect)) {
          leadingRect.origin.y -= theme.linespace / 2;
          leadingRect.size.height += theme.linespace / 2;
          leadingRect = NSIntersectionRect(leadingRect, candidateBlockRect);
        }
        if (!NSIsEmptyRect(trailingRect)) {
          trailingRect.size.height += theme.linespace / 2;
          trailingRect = NSIntersectionRect(trailingRect, candidateBlockRect);
        }
        if (!NSIsEmptyRect(bodyRect)) {
          if (NSIsEmptyRect(leadingRect)) {
            bodyRect.origin.y -= theme.linespace / 2;
            bodyRect.size.height += theme.linespace / 2;
          }
          if (NSIsEmptyRect(trailingRect)) {
            bodyRect.size.height += theme.linespace / 2;
          }
          bodyRect = NSIntersectionRect(bodyRect, candidateBlockRect);
        }
        NSArray<NSValue *> *candidatePoints;
        NSArray<NSValue *> *candidatePoints2;
        // Handles the special case where containing boxes are separated
        if (NSIsEmptyRect(bodyRect) && !NSIsEmptyRect(leadingRect) &&
            !NSIsEmptyRect(trailingRect) && NSMaxX(trailingRect) < NSMinX(leadingRect)) {
          candidatePoints = rectVertex(leadingRect);
          candidatePoints2 = rectVertex(trailingRect);
        } else {
          candidatePoints = multilineRectVertex(leadingRect, bodyRect, trailingRect);
        }
        NSBezierPath *candidatePath = drawRoundedPolygon(candidatePoints, theme.hilitedCornerRadius);
        if (candidatePoints2.count > 0) {
          [candidatePath appendBezierPath:drawRoundedPolygon(candidatePoints2, theme.hilitedCornerRadius)];
        }
        _candidatePaths[i] = candidatePath;
      } else {
        NSRect candidateRect = NSInsetRect([self contentRectForRange:candidateRange], 0.0, -theme.linespace / 2);
        candidateRect.size.width = textContainerRect.size.width;
        candidateRect.origin.x = textContainerRect.origin.x;
        candidateRect.origin.y += textContainerRect.origin.y;
        if (preeditRange.length == 0) {
          candidateRect.origin.y += theme.linespace / 2;
        }
        candidateRect = NSIntersectionRect(candidateRect, candidateBlockRect);
        NSArray<NSValue *> *candidatePoints = rectVertex(candidateRect);
        NSBezierPath *candidatePath = drawRoundedPolygon(candidatePoints, theme.hilitedCornerRadius);
        _candidatePaths[i] = candidatePath;
      }
    }
  }

  // Draw paging Rect
  if (pagingRange.length > 0) {
    CGFloat buttonPadding = theme.linear ? MIN(_separatorWidth / 2, linePadding) : linePadding;
    NSRect pageDownRect = NSOffsetRect([self contentRectForRange:NSMakeRange(NSMaxRange(pagingRange) - 2, 2)],
                                       textContainerRect.origin.x, textContainerRect.origin.y);
    pageDownRect.size.width += buttonPadding;
    NSRect pageUpRect = NSOffsetRect([self contentRectForRange:NSMakeRange(pagingRange.location, 2)],
                                     textContainerRect.origin.x, textContainerRect.origin.y);
    pageUpRect.origin.x -= buttonPadding;
    pageUpRect.size.width = NSWidth(pageDownRect); // bypass the bug of getting wrong glyph position when tab is presented
    if (theme.linear) {
      pageDownRect = NSInsetRect(pageDownRect, 0.0, -theme.linespace / 2);
      pageUpRect = NSInsetRect(pageUpRect, 0.0, -theme.linespace / 2);
    }
    if (preeditRange.length == 0) {
      pageDownRect = NSOffsetRect(pageDownRect, 0.0, theme.linespace / 2);
      pageUpRect = NSOffsetRect(pageUpRect, 0.0, theme.linespace / 2);
    }
    pageDownRect = NSIntersectionRect(pageDownRect, textContainerRect);
    pageUpRect = NSIntersectionRect(pageUpRect, textContainerRect);
    pageDownPath = drawRoundedPolygon(rectVertex(pageDownRect),
                                      MIN(theme.hilitedCornerRadius, MIN(NSWidth(pageDownRect), NSHeight(pageDownRect))/3));
    pageUpPath = drawRoundedPolygon(rectVertex(pageUpRect),
                                    MIN(theme.hilitedCornerRadius, MIN(NSWidth(pageUpRect), NSHeight(pageUpRect))/3));
    _pagingPaths[0] = pageUpPath;
    _pagingPaths[1] = pageDownPath;
  }

  // Draw borders
  backgroundPath = drawRoundedPolygon(rectVertex(backgroundRect),
                                      MIN(theme.cornerRadius, NSHeight(backgroundRect)/3));
  textContainerPath = drawRoundedPolygon(rectVertex(textContainerRect),
                                         MIN(theme.hilitedCornerRadius, NSHeight(textContainerRect)/3));
  if (theme.edgeInset.width > 0 || theme.edgeInset.height > 0) {
    borderPath = [backgroundPath copy];
    [borderPath appendBezierPath:textContainerPath];
    borderPath.windingRule = NSEvenOddWindingRule;
  }

  // set layers
  _shape.path = [backgroundPath quartzPath];
  _shape.fillColor = [[NSColor whiteColor] CGColor];
  _shape.cornerRadius = MIN(theme.cornerRadius, NSHeight(backgroundRect)/3);
  CAShapeLayer *textContainerLayer = [[CAShapeLayer alloc] init];
  textContainerLayer.path = [textContainerPath quartzPath];
  textContainerLayer.fillColor = [[NSColor whiteColor] CGColor];
  textContainerLayer.cornerRadius = MIN(theme.hilitedCornerRadius, NSHeight(textContainerRect)/3);
  [self.layer setSublayers:nil];
  self.layer.cornerRadius = MIN(theme.cornerRadius, NSHeight(backgroundRect)/3);
  CALayer *panelLayer = [[CALayer alloc] init];
  [self.layer addSublayer:panelLayer];
  if (theme.backgroundImage) {
    CAShapeLayer *backgroundImageLayer = [[CAShapeLayer alloc] init];
    if (theme.vertical) {
      const CGAffineTransform rotate = CGAffineTransformMakeRotation(-M_PI/2);
      backgroundImageLayer.path = CGPathCreateCopyByTransformingPath([textContainerPath quartzPath], &rotate);
      backgroundImageLayer.fillColor = [theme.backgroundImage CGColor];
      [backgroundImageLayer setAffineTransform:CGAffineTransformMakeRotation(M_PI/2)];
    } else {
      backgroundImageLayer.path = [textContainerPath quartzPath];
      backgroundImageLayer.fillColor = [theme.backgroundImage CGColor];
    }
    backgroundImageLayer.cornerRadius = MIN(theme.cornerRadius, NSHeight(backgroundRect)/3);
    [panelLayer addSublayer:backgroundImageLayer];
  }
  CAShapeLayer *backgroundLayer = [[CAShapeLayer alloc] init];
  backgroundLayer.path = [textContainerPath quartzPath];
  backgroundLayer.fillColor = [theme.backgroundColor CGColor];
  backgroundLayer.cornerRadius = MIN(theme.cornerRadius, NSHeight(backgroundRect)/3);
  [panelLayer addSublayer:backgroundLayer];
  if (theme.preeditBackgroundColor &&
      (preeditRange.length > 0 || !NSIsEmptyRect(pagingLineRect))) {
    backgroundLayer.fillColor = [theme.preeditBackgroundColor CGColor];
    if (!candidateBlockPath.empty) {
      [textContainerPath appendBezierPath:candidateBlockPath];
      textContainerPath.windingRule = NSEvenOddWindingRule;
      backgroundLayer.path = [textContainerPath quartzPath];
      backgroundLayer.fillRule = kCAFillRuleEvenOdd;
      CAShapeLayer *candidateLayer = [[CAShapeLayer alloc] init];
      candidateLayer.path = [candidateBlockPath quartzPath];
      candidateLayer.fillColor = [theme.backgroundColor CGColor];
      [panelLayer addSublayer:candidateLayer];
    }
  }
  if (@available(macOS 10.14, *)) {
    if (theme.translucency > 0) {
      panelLayer.opacity = 1.0 - theme.translucency;
    }
  }
  if (_highlightedIndex < _candidatePaths.count && theme.highlightedStripColor) {
    CAShapeLayer *highlightedLayer = [[CAShapeLayer alloc] init];
    highlightedPath = _candidatePaths[_highlightedIndex];
    highlightedLayer.path = [highlightedPath quartzPath];
    highlightedLayer.fillColor = [theme.highlightedStripColor CGColor];
    CAShapeLayer *candidateMaskLayer = [[CAShapeLayer alloc] init];
    candidateMaskLayer.path = [candidateBlockPath quartzPath];
    candidateMaskLayer.fillColor = [[NSColor whiteColor] CGColor];
    highlightedLayer.mask = candidateMaskLayer;
    [self.layer addSublayer:highlightedLayer];
  }
  NSColor *buttonColor = theme.linear ? theme.highlightedStripColor : theme.highlightedPreeditColor;
  if (pagingRange.length > 0 && buttonColor) {
    CAShapeLayer *pagingLayer = [[CAShapeLayer alloc] init];
    switch (_pagingButton) {
      case NSPageUpFunctionKey: {
        pagingLayer.path = [pageUpPath quartzPath];
        pagingLayer.fillColor = [hooverColor(buttonColor, self.isDark) CGColor];
      } break;
      case NSBeginFunctionKey: {
        pagingLayer.path = [pageUpPath quartzPath];
        pagingLayer.fillColor = [disabledColor(buttonColor, self.isDark) CGColor];
      } break;
      case NSPageDownFunctionKey: {
        pagingLayer.path = [pageDownPath quartzPath];
        pagingLayer.fillColor = [hooverColor(buttonColor, self.isDark) CGColor];
      } break;
      case NSEndFunctionKey: {
        pagingLayer.path = [pageDownPath quartzPath];
        pagingLayer.fillColor = [disabledColor(buttonColor, self.isDark) CGColor];
      } break;
    }
    pagingLayer.mask = textContainerLayer;
    [self.layer addSublayer:pagingLayer];
  }
  if (theme.highlightedPreeditColor) {
    if (!highlightedPreeditPath.empty) {
      CAShapeLayer *highlightedPreeditLayer = [[CAShapeLayer alloc] init];
      highlightedPreeditLayer.path = [highlightedPreeditPath quartzPath];
      highlightedPreeditLayer.fillColor = [theme.highlightedPreeditColor CGColor];
      highlightedPreeditLayer.mask = textContainerLayer;
      [self.layer addSublayer:highlightedPreeditLayer];
    }
  }
  if (theme.borderColor && !borderPath.empty) {
    CAShapeLayer *borderLayer = [[CAShapeLayer alloc] init];
    borderLayer.path = [borderPath quartzPath];
    borderLayer.fillColor = [theme.borderColor CGColor];
    borderLayer.fillRule = kCAFillRuleEvenOdd;
    [panelLayer addSublayer:borderLayer];
  }
}

- (BOOL)convertClickSpot:(NSPoint)spot toIndex:(NSUInteger *)index {
  if (NSPointInRect(spot, self.bounds)) {
    if (_pagingPaths.count > 0) {
      if ([_pagingPaths[0] containsPoint:spot]) {
        *index = NSPageUpFunctionKey; // borrow function-key unicode for readability
        return YES;
      }
      if ([_pagingPaths[1] containsPoint:spot]) {
        *index = NSPageDownFunctionKey; // borrow function-key unicode for readability
        return YES;
      }
    }
    for (NSUInteger i = 0; i < _candidatePaths.count; ++i) {
      if ([_candidatePaths[i] containsPoint:spot]) {
        *index = i;
        return YES;
      }
    }
  }
  return NO;
}

@end

@implementation SquirrelPanel {
  SquirrelView *_view;
  NSVisualEffectView *_back;

  NSScreen *_screen;
  NSSize _maxSize;
  CGFloat _textWidthLimit;

  NSString *_preedit;
  NSRange _selRange;
  NSUInteger _caretPos;
  NSArray *_candidates;
  NSArray *_comments;
  NSArray *_labels;
  NSUInteger _index;
  NSUInteger _pageNum;
  NSUInteger _turnPage;
  BOOL _lastPage;
  BOOL _mouseDown;
  NSPoint _scrollLocus;

  NSString *_statusMessage;
  NSTimer *_statusTimer;
}

- (BOOL)isFloatingPanel {
  return YES;
}

- (BOOL)linear {
  return _view.currentTheme.linear;
}

- (BOOL)vertical {
  return _view.currentTheme.vertical;
}

- (BOOL)inlinePreedit {
  return _view.currentTheme.inlinePreedit;
}

- (BOOL)inlineCandidate {
  return _view.currentTheme.inlineCandidate;
}

+ (NSColor *)secondaryTextColor {
  if (@available(macOS 10.10, *)) {
    return [NSColor secondaryLabelColor];
  } else {
    return [NSColor disabledControlTextColor];
  }
}

+ (NSColor *)accentColor {
  if (@available(macOS 10.14, *)) {
    return [NSColor controlAccentColor];
  } else {
    return [NSColor colorForControlTint:[[self class] currentControlTint]];
  }
}

- (void)initializeUIStyleForDarkMode:(BOOL)isDark {
  SquirrelTheme *theme = [_view selectTheme:isDark];
  theme.native = YES;
  theme.candidateFormat = kDefaultCandidateFormat;

  NSColor *secondaryTextColor = [[self class] secondaryTextColor];
  NSColor *accentColor = [[self class] accentColor];
  NSFont *userFont = [NSFont fontWithDescriptor:getFontDescriptor([NSFont userFontOfSize:0.0].fontName)
                                           size:kDefaultFontSize];
  NSFont *userMonoFont = [NSFont fontWithDescriptor:getFontDescriptor([NSFont userFixedPitchFontOfSize:0.0].fontName)
                                               size:kDefaultFontSize];
  NSMutableDictionary *defaultAttrs = [[NSMutableDictionary alloc] init];
  defaultAttrs[NSStrokeWidthAttributeName] = @(-1.0);

  NSMutableDictionary *attrs = [defaultAttrs mutableCopy];
  attrs[NSForegroundColorAttributeName] = [NSColor controlTextColor];
  attrs[NSFontAttributeName] = userFont;

  NSMutableDictionary *highlightedAttrs = [defaultAttrs mutableCopy];
  highlightedAttrs[NSForegroundColorAttributeName] = [NSColor selectedMenuItemTextColor];
  highlightedAttrs[NSFontAttributeName] = userFont;

  NSMutableDictionary *labelAttrs = [attrs mutableCopy];
  labelAttrs[NSForegroundColorAttributeName] = accentColor;
  labelAttrs[NSFontAttributeName] = userMonoFont;

  NSMutableDictionary *labelHighlightedAttrs = [highlightedAttrs mutableCopy];
  labelHighlightedAttrs[NSForegroundColorAttributeName] = [NSColor alternateSelectedControlTextColor];
  labelHighlightedAttrs[NSFontAttributeName] = userMonoFont;

  NSMutableDictionary *commentAttrs = [defaultAttrs mutableCopy];
  commentAttrs[NSForegroundColorAttributeName] = secondaryTextColor;
  commentAttrs[NSFontAttributeName] = userFont;

  NSMutableDictionary *commentHighlightedAttrs = [defaultAttrs mutableCopy];
  commentHighlightedAttrs[NSForegroundColorAttributeName] = [NSColor alternateSelectedControlTextColor];
  commentHighlightedAttrs[NSFontAttributeName] = userFont;

  NSMutableDictionary *preeditAttrs = [defaultAttrs mutableCopy];
  preeditAttrs[NSForegroundColorAttributeName] = [NSColor textColor];
  preeditAttrs[NSFontAttributeName] = userFont;
  preeditAttrs[NSLigatureAttributeName] = @(0);

  NSMutableDictionary *preeditHighlightedAttrs = [defaultAttrs mutableCopy];
  preeditHighlightedAttrs[NSForegroundColorAttributeName] = [NSColor selectedTextColor];
  preeditHighlightedAttrs[NSFontAttributeName] = userFont;
  preeditHighlightedAttrs[NSLigatureAttributeName] = @(0);

  NSMutableDictionary *pagingAttrs = [defaultAttrs mutableCopy];
  pagingAttrs[NSForegroundColorAttributeName] = theme.linear ? accentColor : [NSColor controlTextColor];

  NSMutableDictionary *pagingHighlightedAttrs = [defaultAttrs mutableCopy];
  pagingHighlightedAttrs[NSForegroundColorAttributeName] = theme.linear
    ? [NSColor alternateSelectedControlTextColor] : [NSColor selectedMenuItemTextColor];

  NSMutableParagraphStyle *preeditParagraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
  NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
  NSMutableParagraphStyle *pagingParagraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
  NSMutableParagraphStyle *statusParagraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];

  preeditParagraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
  preeditParagraphStyle.alignment = NSTextAlignmentLeft;
  paragraphStyle.alignment = NSTextAlignmentLeft;
  pagingParagraphStyle.alignment = NSTextAlignmentLeft;
  statusParagraphStyle.alignment = NSTextAlignmentLeft;

  // Use left-to-right marks to declare the default writing direction and prevent strong right-to-left
  // characters from setting the writing direction in case the label are direction-less symbols
  preeditParagraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
  paragraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
  pagingParagraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
  statusParagraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;

  NSMutableDictionary *statusAttrs = [commentAttrs mutableCopy];
  statusAttrs[NSParagraphStyleAttributeName] = statusParagraphStyle;

  preeditAttrs[NSParagraphStyleAttributeName] = preeditParagraphStyle;
  preeditHighlightedAttrs[NSParagraphStyleAttributeName] = preeditParagraphStyle;

  [theme           setAttrs:attrs
           highlightedAttrs:highlightedAttrs
                 labelAttrs:labelAttrs
      labelHighlightedAttrs:labelHighlightedAttrs
               commentAttrs:commentAttrs
    commentHighlightedAttrs:commentHighlightedAttrs
               preeditAttrs:preeditAttrs
    preeditHighlightedAttrs:preeditHighlightedAttrs
                pagingAttrs:pagingAttrs
     pagingHighlightedAttrs:pagingHighlightedAttrs
                statusAttrs:statusAttrs];
  [theme setParagraphStyle:paragraphStyle
     preeditParagraphStyle:preeditParagraphStyle
      pagingParagraphStyle:pagingParagraphStyle
      statusParagraphStyle:statusParagraphStyle];
}

- (instancetype)init {
  self = [super initWithContentRect:_position
                          styleMask:NSWindowStyleMaskNonactivatingPanel|NSWindowStyleMaskBorderless
                            backing:NSBackingStoreBuffered
                              defer:YES];

  if (self) {
    self.alphaValue = 1.0;
    // _window.level = NSScreenSaverWindowLevel + 1;
    // ^ May fix visibility issue in fullscreen games.
    self.level = kCGCursorWindowLevel - 10;
    self.hasShadow = NO;
    self.opaque = NO;
    self.displaysWhenScreenProfileChanges = YES;
    self.backgroundColor = [NSColor clearColor];
    NSView *contentView = [[NSView alloc] init];
    _view = [[SquirrelView alloc] initWithFrame:self.contentView.bounds];
    if (@available(macOS 10.14, *)) {
      _back = [[NSVisualEffectView alloc] init];
      _back.blendingMode = NSVisualEffectBlendingModeBehindWindow;
      _back.material = NSVisualEffectMaterialHUDWindow;
      _back.state = NSVisualEffectStateActive;
      _back.wantsLayer = YES;
      _back.layer.mask = _view.shape;
      [contentView addSubview:_back];
    }
    [contentView addSubview:_view];
    [contentView addSubview:_view.textView];

    self.contentView = contentView;
    [self initializeUIStyleForDarkMode:NO];
    if (@available(macOS 10.14, *)) {
      [self initializeUIStyleForDarkMode:YES];
    }
    _maxSize = NSZeroSize;
  }
  return self;
}

- (void)sendEvent:(NSEvent *)event {
  switch (event.type) {
    case NSEventTypeLeftMouseDown:
    case NSEventTypeRightMouseDown: {
      NSPoint spot = [_view convertPoint:self.mouseLocationOutsideOfEventStream
                                fromView:nil];
      NSUInteger cursorIndex = NSNotFound;
      if ([_view convertClickSpot:spot toIndex:&cursorIndex]) {
        if ((cursorIndex >= 0 && cursorIndex < _candidates.count) ||
            cursorIndex == NSPageUpFunctionKey || cursorIndex == NSPageDownFunctionKey) {
          _index = cursorIndex;
          _mouseDown = YES;
        }
      }
    } break;
    case NSEventTypeLeftMouseUp: {
      NSPoint spot = [_view convertPoint:self.mouseLocationOutsideOfEventStream
                                fromView:nil];
      NSUInteger cursorIndex = NSNotFound;
      if (_mouseDown && [_view convertClickSpot:spot toIndex:&cursorIndex]) {
        if (cursorIndex == _index || cursorIndex == _turnPage) {
          [_inputController perform:kSELECT onIndex:cursorIndex];
        }
      }
      _mouseDown = NO;
    } break;
    case NSEventTypeRightMouseUp: {
      NSPoint spot = [_view convertPoint:self.mouseLocationOutsideOfEventStream
                                fromView:nil];
      NSUInteger cursorIndex = NSNotFound;
      if (_mouseDown && [_view convertClickSpot:spot toIndex:&cursorIndex]) {
        if (cursorIndex == _index && (cursorIndex >= 0 && cursorIndex < _candidates.count)) {
          [_inputController perform:kDELETE onIndex:cursorIndex];
        }
      }
      _mouseDown = NO;
    } break;
    case NSEventTypeMouseEntered: {
      self.acceptsMouseMovedEvents = YES;
    } break;
    case NSEventTypeMouseExited: {
      self.acceptsMouseMovedEvents = NO;
    } break;
    case NSEventTypeMouseMoved: {
      NSPoint spot = [_view convertPoint:self.mouseLocationOutsideOfEventStream
                                fromView:nil];
      NSUInteger cursorIndex = NSNotFound;
      if ([_view convertClickSpot:spot toIndex:&cursorIndex]) {
        if (cursorIndex >= 0 && cursorIndex < _candidates.count && _index != cursorIndex) {
          [_inputController perform:kCHOOSE onIndex:cursorIndex];
          _index = cursorIndex;
          [self showPreedit:_preedit selRange:_selRange caretPos:_caretPos candidates:_candidates comments:_comments labels:_labels highlighted:cursorIndex pageNum:_pageNum lastPage:_lastPage turnPage:NSNotFound update:NO];
        } else if ((cursorIndex == NSPageUpFunctionKey || cursorIndex == NSPageDownFunctionKey) && _turnPage != cursorIndex) {
          _turnPage = cursorIndex;
          [self showPreedit:_preedit selRange:_selRange caretPos:_caretPos candidates:_candidates comments:_comments labels:_labels highlighted:_index pageNum:_pageNum lastPage:_lastPage turnPage:cursorIndex update:NO];
        }
      }
    } break;
    case NSEventTypeLeftMouseDragged: {
      _mouseDown = NO;
      [self performWindowDragWithEvent:event];
    } break;
    case NSEventTypeScrollWheel: {
      SquirrelTheme *theme = _view.currentTheme;
      CGFloat scrollThreshold = [theme.attrs[NSParagraphStyleAttributeName] maximumLineHeight] + [theme.attrs[NSParagraphStyleAttributeName] lineSpacing];
      if (event.phase == NSEventPhaseBegan) {
        _scrollLocus = NSZeroPoint;
      } else if ((event.phase == NSEventPhaseNone || event.momentumPhase == NSEventPhaseNone) &&
                 _scrollLocus.x != NSNotFound && _scrollLocus.y != NSNotFound) {
        // determine scrolling direction by confining to sectors within ±30º of any axis
        if (ABS(event.scrollingDeltaX) > ABS(event.scrollingDeltaY) * sqrt(3)) {
          _scrollLocus.x += event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 10);
        } else if (ABS(event.scrollingDeltaY) > ABS(event.scrollingDeltaX) * sqrt(3)) {
          _scrollLocus.y += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10);
        }
        // compare accumulated locus length against threshold and limit paging to max once
        if (_scrollLocus.x > scrollThreshold) {
          [_inputController perform:kSELECT onIndex:(theme.vertical ? NSPageDownFunctionKey : NSPageUpFunctionKey)];
          _scrollLocus = NSMakePoint(NSNotFound, NSNotFound);
        } else if (_scrollLocus.y > scrollThreshold) {
          [_inputController perform:kSELECT onIndex:NSPageUpFunctionKey];
          _scrollLocus = NSMakePoint(NSNotFound, NSNotFound);
        } else if (_scrollLocus.x < -scrollThreshold) {
          [_inputController perform:kSELECT onIndex:(theme.vertical ? NSPageUpFunctionKey : NSPageDownFunctionKey)];
          _scrollLocus = NSMakePoint(NSNotFound, NSNotFound);
        } else if (_scrollLocus.y < -scrollThreshold) {
          [_inputController perform:kSELECT onIndex:NSPageDownFunctionKey];
          _scrollLocus = NSMakePoint(NSNotFound, NSNotFound);
        }
      }
    } break;
    default:
      break;
  }
  [super sendEvent:event];
}

- (void)getCurrentScreen {
  // get current screen
  _screen = [NSScreen mainScreen];
  NSArray *screens = [NSScreen screens];
  for (NSUInteger i = 0; i < screens.count; ++i) {
    if (NSPointInRect(_position.origin, [screens[i] frame])) {
      _screen = screens[i];
      break;
    }
  }
}

- (void)getTextWidthLimit {
  SquirrelTheme *theme = _view.currentTheme;
  [self getCurrentScreen];
  NSRect screenRect = _screen.visibleFrame;
  CGFloat textWidthRatio = MIN(1.0, 1.0 / (theme.vertical ? 4 : 3) + [theme.attrs[NSFontAttributeName] pointSize] / 144.0);
  _textWidthLimit = floor((theme.vertical ? NSHeight(screenRect) : NSWidth(screenRect)) * textWidthRatio - (theme.hilitedCornerRadius + theme.edgeInset.width) * 2);
  if (theme.lineLength > 0) {
    _textWidthLimit = MIN(floor(theme.lineLength), _textWidthLimit);
  }
  CGFloat textHeightLimit = (theme.vertical ? NSWidth(screenRect) : NSHeight(screenRect)) * textWidthRatio - theme.edgeInset.height * 2;
  _view.textView.textContainer.size = NSMakeSize(_textWidthLimit + theme.hilitedCornerRadius * 2, textHeightLimit);
}

// Get the window size, it will be the dirtyRect in SquirrelView.drawRect
- (void)show {
  SquirrelTheme *theme = _view.currentTheme;

  if (@available(macOS 10.14, *)) {
    NSAppearance *requestedAppearance = [NSAppearance appearanceNamed:(_view.isDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
    if (self.appearance != requestedAppearance) {
      self.appearance = requestedAppearance;
    }
  }

  //Break line if the text is too long, based on screen size.
  NSTextContainer *textContainer = _view.textView.textContainer;
  CGFloat linePadding = textContainer.lineFragmentPadding;
  NSEdgeInsets insets = _view.insets;
  CGFloat textWidthRatio = MIN(1.0, 1.0 / (theme.vertical ? 4 : 3) + [theme.attrs[NSFontAttributeName] pointSize] / 144.0);
  NSRect screenRect = _screen.visibleFrame;
  CGFloat textHeightLimit = (theme.vertical ? NSWidth(screenRect) : NSHeight(screenRect)) * textWidthRatio - insets.top - insets.bottom;

  // the sweep direction of the client app changes the behavior of adjusting squirrel panel position
  BOOL sweepVertical = NSWidth(_position) > NSHeight(_position);
  NSRect contentRect = _view.contentRect;
  NSRect maxContentRect = NSInsetRect(contentRect, linePadding, 0);
  if (theme.lineLength > 0) { // fixed line length / text width
    if (_maxSize.width > 0) { // not applicable to status message where maxSize is set to 0
      maxContentRect.size.width = _textWidthLimit;
    }
  }
  if (theme.rememberSize) { // remember panel size (fix the top leading anchor of the panel in screen coordiantes)
    if ((theme.vertical ? (NSMinY(_position) - NSMinY(screenRect) <= NSHeight(screenRect) * textWidthRatio + kOffsetHeight)
         : (sweepVertical ? (NSMinX(_position) - NSMinX(screenRect) > NSWidth(screenRect) * textWidthRatio + kOffsetHeight)
            : (NSMinX(_position) + MAX(NSWidth(maxContentRect), _maxSize.width) + linePadding + insets.right > NSMaxX(screenRect)))) &&
        theme.lineLength == 0) {
      if (NSWidth(maxContentRect) >= _maxSize.width) {
        _maxSize.width = NSWidth(maxContentRect);
      } else {
        maxContentRect.size.width = _maxSize.width;
        [textContainer setSize:NSMakeSize(_maxSize.width + linePadding * 2, textHeightLimit)];
      }
    }
    if (theme.vertical ? (NSMinX(_position) - NSMinX(screenRect) < MAX(NSHeight(maxContentRect), _maxSize.height) + insets.top + insets.bottom + (sweepVertical ? kOffsetHeight : 0))
        : (NSMinY(_position) - NSMinY(screenRect) < MAX(NSHeight(maxContentRect), _maxSize.height) + insets.top + insets.bottom + (sweepVertical ? 0 : kOffsetHeight))) {
      if (NSHeight(maxContentRect) >= _maxSize.height) {
        _maxSize.height = NSHeight(maxContentRect);
      } else {
        maxContentRect.size.height = _maxSize.height;
        [textContainer setSize:NSMakeSize(_textWidthLimit + linePadding * 2, _maxSize.height)];
      }
    }
  }

  NSRect windowRect;
  if (theme.vertical) {
    windowRect.size = NSMakeSize(NSHeight(maxContentRect) + insets.top + insets.bottom,
                                 NSWidth(maxContentRect) + linePadding * 2 + insets.left + insets.right);
    // To avoid jumping up and down while typing, use the lower screen when typing on upper, and vice versa
    if (NSMinY(_position) - NSMinY(screenRect) > NSHeight(screenRect) * textWidthRatio + kOffsetHeight) {
      windowRect.origin.y = NSMinY(_position) + (sweepVertical ? insets.left + linePadding : -kOffsetHeight) - NSHeight(windowRect);
    } else {
      windowRect.origin.y = NSMaxY(_position) + (sweepVertical ? 0 : kOffsetHeight);
    }
    // Make the right edge of candidate block fixed at the left of cursor
    windowRect.origin.x = NSMinX(_position) - (sweepVertical ? kOffsetHeight : 0) - NSWidth(windowRect);
    if (!sweepVertical && _view.preeditRange.length > 0) {
      NSRect preeditRect = [_view contentRectForRange:_view.preeditRange];
      windowRect.origin.x += NSHeight(preeditRect) + insets.top;
    }
  } else {
    windowRect.size = NSMakeSize(NSWidth(maxContentRect) + linePadding * 2 + insets.left + insets.right,
                                 NSHeight(maxContentRect) + insets.top + insets.bottom);
    if (sweepVertical) {
      // To avoid jumping left and right while typing, use the lefter screen when typing on righter, and vice versa
      if (NSMinX(_position) - NSMinX(screenRect) > NSWidth(screenRect) * textWidthRatio + kOffsetHeight) {
        windowRect.origin.x = NSMinX(_position) - kOffsetHeight - NSWidth(windowRect);
      } else {
        windowRect.origin.x = NSMaxX(_position) + kOffsetHeight;
      }
      windowRect.origin.y = NSMinY(_position) - NSHeight(windowRect);
    } else {
      windowRect.origin = NSMakePoint(NSMinX(_position) - insets.left - linePadding,
                                      NSMinY(_position) - kOffsetHeight - NSHeight(windowRect));
    }
  }

  if (NSMaxX(windowRect) > NSMaxX(screenRect)) {
    windowRect.origin.x = (sweepVertical ? NSMinX(_position) - kOffsetHeight : NSMaxX(screenRect)) - NSWidth(windowRect);
  }
  if (NSMinX(windowRect) < NSMinX(screenRect)) {
    windowRect.origin.x = sweepVertical ? NSMaxX(_position) + kOffsetHeight : NSMinX(screenRect);
  }
  if (NSMinY(windowRect) < NSMinY(screenRect)) {
    windowRect.origin.y = sweepVertical ? NSMinY(screenRect) : NSMaxY(_position) + kOffsetHeight;
  }
  if (NSMaxY(windowRect) > NSMaxY(screenRect)) {
    windowRect.origin.y = (sweepVertical ? NSMaxY(screenRect) : NSMinY(_position) - kOffsetHeight) - NSHeight(windowRect);
  }

  if (theme.vertical) {
    windowRect.origin.x += NSHeight(maxContentRect) - NSHeight(contentRect);
    windowRect.size.width -= NSHeight(maxContentRect) - NSHeight(contentRect);
  } else {
    windowRect.origin.y += NSHeight(maxContentRect) - NSHeight(contentRect);
    windowRect.size.height -= NSHeight(maxContentRect) - NSHeight(contentRect);
  }

  // rotate the view, the core in vertical mode!
  if (theme.vertical) {
    [self setFrame:[_screen backingAlignedRect:windowRect options:NSAlignMaxXOutward|NSAlignMaxYInward|NSAlignWidthNearest|NSAlignHeightNearest] display:YES];
    [self.contentView setBoundsRotation:-90.0];
    [self.contentView setBoundsOrigin:NSMakePoint(0.0, NSWidth(windowRect))];
  } else {
    [self setFrame:[_screen backingAlignedRect:windowRect options:NSAlignMinXInward|NSAlignMaxYInward|NSAlignWidthNearest|NSAlignHeightNearest] display:YES];
    [self.contentView setBoundsRotation:0.0];
    [self.contentView setBoundsOrigin:NSZeroPoint];
  }
  NSRect frameRect = self.contentView.bounds;
  NSRect textFrameRect = NSMakeRect(NSMinX(frameRect) + insets.left, NSMinY(frameRect) + insets.bottom,
                                    NSWidth(frameRect) - insets.left - insets.right,
                                    NSHeight(frameRect) - insets.top - insets.bottom);
  [_view.textView setBoundsRotation:0.0];
  [_view setBoundsOrigin:NSZeroPoint];
  [_view.textView setBoundsOrigin:NSZeroPoint];
  [_view setFrame:frameRect];
  [_view.textView setFrame:textFrameRect];

  CGFloat translucency = theme.translucency;
  if (@available(macOS 10.14, *)) {
    if (translucency > 0) {
      [_back setFrame:frameRect];
      [_back setAppearance:NSApp.effectiveAppearance];
      [_back setHidden:NO];
    } else {
      [_back setHidden:YES];
    }
  }
  [self setAlphaValue:theme.alpha];
  [self orderFront:nil];
  // voila !
}

- (void)hide {
  if (_statusTimer) {
    [_statusTimer invalidate];
    _statusTimer = nil;
  }
  [self orderOut:nil];
  _maxSize = NSZeroSize;
}

- (void)setLayoutForRange:(NSRange)charRange
        withReferenceFont:(NSFont *)refFont
           paragraphStyle:(NSParagraphStyle *)style {
  BOOL verticalLayout = _view.currentTheme.vertical;
  CGFloat refFontHeight = refFont.ascender - refFont.descender;
  CGFloat lineHeight = MAX(style.lineHeightMultiple > 0 ? refFontHeight * style.lineHeightMultiple : refFontHeight,
                           style.minimumLineHeight);
  lineHeight = style.maximumLineHeight > 0 ? MIN(lineHeight, style.maximumLineHeight) : lineHeight;
  if (@available(macOS 12.0, *)) {
    NSUInteger i = charRange.location;
    NSRange runRange = NSMakeRange(i, 0);
    while (i < NSMaxRange(charRange)) {
      CGFloat baselineOffset = [[_view.textStorage attribute:NSBaselineOffsetAttributeName atIndex:i effectiveRange:&runRange] doubleValue];
      [_view.textStorage addAttribute:NSBaselineOffsetAttributeName value:@(baselineOffset + lineHeight/2 - refFontHeight/2) range:runRange];
      i = NSMaxRange(runRange);
    }
  } else {
    NSLayoutManager *layoutManager = _view.textView.layoutManager;
    NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
    NSUInteger i = glyphRange.location;
    NSRange lineRange = NSMakeRange(i, 0);
    while (i < NSMaxRange(glyphRange)) {
      NSRect rect = [layoutManager lineFragmentRectForGlyphAtIndex:i effectiveRange:&lineRange];
      NSRect usedRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:i effectiveRange:NULL];
      CGFloat alignment = usedRect.origin.y - rect.origin.y + (verticalLayout ? lineHeight / 2 : lineHeight/2 + refFont.descender + refFontHeight/2);
      // typesetting glyphs
      NSRange fontRunRange = NSMakeRange(NSNotFound, 0);
      NSUInteger j = lineRange.location;
      while (j < NSMaxRange(lineRange)) {
        NSPoint runGlyphPosition = [layoutManager locationForGlyphAtIndex:j];
        NSUInteger runCharLocation = [layoutManager characterIndexForGlyphAtIndex:j];
        NSFont *runFont = [_view.textStorage attribute:NSFontAttributeName atIndex:runCharLocation effectiveRange:&fontRunRange];
        NSFont *systemFont = [NSFont systemFontOfSize:runFont.pointSize];
        NSNumber *baselineOffset = [_view.textStorage attribute:NSBaselineOffsetAttributeName atIndex:runCharLocation effectiveRange:NULL];
        CGFloat offset = baselineOffset ? baselineOffset.doubleValue : 0.0;
        NSRange fontRunGlyphRange = [layoutManager glyphRangeForCharacterRange:fontRunRange actualCharacterRange:NULL];
        NSRange runRange = NSIntersectionRange(NSMakeRange(j, NSMaxRange(fontRunGlyphRange)-j), [layoutManager rangeOfNominallySpacedGlyphsContainingIndex:j]);
        if (verticalLayout) {
          NSNumber *verticalGlyph = [_view.textStorage attribute:NSVerticalGlyphFormAttributeName atIndex:runCharLocation effectiveRange:NULL];
          if (verticalGlyph ? verticalGlyph.boolValue : YES) {
            runFont = runFont.verticalFont;
            systemFont = systemFont.verticalFont;
          }
        }
        CGFloat runBaseline = runFont.ascender;
        CGFloat runFontHeight = runFont.ascender - runFont.descender;
        CGFloat systemFontHeight = systemFont.ascender - systemFont.descender;
        if (verticalLayout) {
          runGlyphPosition.y = alignment - offset + runBaseline - runFontHeight/2 + round(MAX(0.0, runFontHeight - systemFontHeight) / 3);
          if (runFont.vertical) {
            runGlyphPosition.x += round(MAX(0.0, runFontHeight - systemFontHeight) * 2/3);
          }
        } else {
          runGlyphPosition.y = alignment - offset;
        }
        [layoutManager setLocation:NSMakePoint(round(runGlyphPosition.x), round(runGlyphPosition.y)) forStartOfGlyphRange:runRange];
        j = NSMaxRange(runRange);
      }
      i = NSMaxRange(lineRange);
    }
  }
}

- (BOOL)shouldBreakLineWithRange:(NSRange)range {
  if (@available(macOS 12.0, *)) {
    NSTextRange *textRange = [_view getTextRangeFromRange:range];
    NSUInteger __block lineCount = 0;
    [_view.textView.textLayoutManager
     enumerateTextSegmentsInRange:textRange
     type:NSTextLayoutManagerSegmentTypeStandard
     options:NSTextLayoutManagerSegmentOptionsRangeNotRequired
     usingBlock:^(NSTextRange *segRange, CGRect segFrame, CGFloat baseline, NSTextContainer *textContainer) {
      ++lineCount;
      return YES;
    }];
    return lineCount > 1;
  } else {
    NSRange glyphRange = [_view.textView.layoutManager glyphRangeForCharacterRange:range
                                                              actualCharacterRange:NULL];
    NSUInteger loc = glyphRange.location;
    NSRange lineRange = NSMakeRange(loc, 0);
    NSUInteger lineCount = 0;
    while (loc < NSMaxRange(glyphRange)) {
      [_view.textView.layoutManager lineFragmentRectForGlyphAtIndex:loc
                                                     effectiveRange:&lineRange];
      ++lineCount;
      loc = NSMaxRange(lineRange);
    }
    return lineCount > 1;
  }
}

- (BOOL)shouldUseTabsInRange:(NSRange)range maxLineLength:(CGFloat *)maxLineLength{
  if (@available(macOS 12.0, *)) {
    NSTextRange *textRange = [_view getTextRangeFromRange:range];
    CGFloat __block rangeEdge;
    [_view.textView.textLayoutManager
     enumerateTextSegmentsInRange:textRange
     type:NSTextLayoutManagerSegmentTypeStandard
     options:NSTextLayoutManagerSegmentOptionsRangeNotRequired
     usingBlock:^(NSTextRange *segRange, CGRect segFrame, CGFloat baseline, NSTextContainer *textContainer) {
      rangeEdge = NSMaxX(segFrame);
      return YES;
    }];
    NSRect container;
    if (@available(macOS 14.0, *)) {
      container = [_view.textView.textLayoutManager usageBoundsForTextContainer];
    } else {
      container = NSInsetRect([_view.textView.textLayoutManager usageBoundsForTextContainer],
                              _view.textView.textContainer.lineFragmentPadding, 0);
    }
    *maxLineLength = MAX(MIN(_textWidthLimit, ceil(NSWidth(container))), _maxSize.width);
    return NSMinX(container) + *maxLineLength > rangeEdge;
  } else {
    NSUInteger glyphIndex = [_view.textView.layoutManager glyphIndexForCharacterAtIndex:range.location];
    CGFloat rangeEdge = NSMaxX([_view.textView.layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphIndex effectiveRange:NULL]);
    NSRect container = NSInsetRect([_view.textView.layoutManager usedRectForTextContainer:_view.textView.textContainer],
                                   _view.textView.textContainer.lineFragmentPadding, 0);
    *maxLineLength = MAX(MIN(_textWidthLimit, ceil(NSWidth(container))), _maxSize.width);
    return NSMinX(container) + *maxLineLength > rangeEdge;
  }
}

// Main function to add attributes to text output from librime
- (void)showPreedit:(NSString *)preedit
           selRange:(NSRange)selRange
           caretPos:(NSUInteger)caretPos
         candidates:(NSArray *)candidates
           comments:(NSArray *)comments
             labels:(NSArray *)labels
        highlighted:(NSUInteger)index
            pageNum:(NSUInteger)pageNum
           lastPage:(BOOL)lastPage
           turnPage:(NSUInteger)turnPage
             update:(BOOL)update {
  if (update) {
    _preedit = preedit;
    _selRange = selRange;
    _caretPos = caretPos;
    _candidates = candidates;
    _comments = comments;
    _labels = labels;
    _index = index;
    _pageNum = pageNum;
    _lastPage = lastPage;
  }
  NSUInteger numCandidates = candidates.count;
  if (numCandidates == 0) {
    _index = index = NSNotFound;
  }

  _turnPage = turnPage;
  if (_turnPage == NSPageUpFunctionKey) {
    turnPage = pageNum ? NSPageUpFunctionKey : NSBeginFunctionKey;
  } else if (_turnPage == NSPageDownFunctionKey) {
    turnPage = lastPage ? NSEndFunctionKey : NSPageDownFunctionKey;
  }

  if (numCandidates > 0 || (preedit && preedit.length)) {
    _statusMessage = nil;
    if (_statusTimer) {
      [_statusTimer invalidate];
      _statusTimer = nil;
    }
  } else {
    if (_statusMessage) {
      [self showStatus:_statusMessage];
      _statusMessage = nil;
    } else if (!_statusTimer) {
      [self hide];
    }
    return;
  }

  SquirrelTheme *theme = _view.currentTheme;
  _view.textView.layoutOrientation = theme.vertical ? NSTextLayoutOrientationVertical : NSTextLayoutOrientationHorizontal;
  _view.textView.textContainer.lineFragmentPadding = theme.hilitedCornerRadius;
  [self getTextWidthLimit];
  if (theme.lineLength > 0) {
    _maxSize.width = MIN(floor(theme.lineLength), _textWidthLimit);
  }
  NSEdgeInsets insets = NSEdgeInsetsMake(theme.edgeInset.height + theme.linespace / 2, theme.edgeInset.width,
                                         theme.edgeInset.height + theme.linespace / 2, theme.edgeInset.width);

  NSTextStorage *text = _view.textStorage;
  [text setAttributedString:[[NSMutableAttributedString alloc] init]];
  NSRange preeditRange = NSMakeRange(NSNotFound, 0);
  NSRange highlightedPreeditRange = NSMakeRange(NSNotFound, 0);
  // preedit
  if (preedit) {
    NSMutableAttributedString *preeditLine = [[NSMutableAttributedString alloc] init];
    if (selRange.location > 0) {
      [preeditLine appendAttributedString:[[NSAttributedString alloc]
                                           initWithString:[preedit substringToIndex:selRange.location]
                                               attributes:theme.preeditAttrs]];
    }
    if (selRange.length > 0) {
      NSUInteger highlightedPreeditStart = preeditLine.length;
      [preeditLine appendAttributedString:[[NSAttributedString alloc]
                                           initWithString:[preedit substringWithRange:selRange]
                                               attributes:theme.preeditHighlightedAttrs]];
      highlightedPreeditRange = NSMakeRange(highlightedPreeditStart,
                                            preeditLine.length - highlightedPreeditStart);
    }
    if (NSMaxRange(selRange) < preedit.length) {
      [preeditLine appendAttributedString:[[NSAttributedString alloc]
                                           initWithString:[preedit substringFromIndex:NSMaxRange(selRange)]
                                               attributes:theme.preeditAttrs]];
    }
    // force caret to be rendered horizontally in vertical layout
    if (caretPos != NSNotFound) {
      [preeditLine addAttribute:NSVerticalGlyphFormAttributeName
                          value:@NO
                          range:NSMakeRange(caretPos - (caretPos < NSMaxRange(selRange)), 1)];
    }
    preeditRange = NSMakeRange(0, preeditLine.length);
    [text appendAttributedString:preeditLine];
    if (numCandidates > 0) {
      [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:theme.preeditAttrs]];
    } else {
      insets.bottom = theme.edgeInset.height;
    }
    insets.top = theme.edgeInset.height;
  }

  // separator
  NSMutableAttributedString *sep = [[NSMutableAttributedString alloc] initWithString:@"　" attributes:theme.attrs];
  _view.separatorWidth = theme.linear ? sep.size.width : 0.0;

  // candidate items
  NSUInteger candidateBlockStart = text.length;
  NSMutableArray<NSValue *> *candidateRanges = [[NSMutableArray alloc] initWithCapacity:numCandidates];
  NSUInteger lineStart = text.length;
  NSRange separatorRange = NSMakeRange(NSNotFound, 0);
  for (NSUInteger i = 0; i < candidates.count; ++i) {
    NSMutableAttributedString *item = [[NSMutableAttributedString alloc] init];
    NSDictionary *attrs = (i == index) ? theme.highlightedAttrs : theme.attrs;
    NSDictionary *labelAttrs = (i == index) ? theme.labelHighlightedAttrs : theme.labelAttrs;
    NSDictionary *commentAttrs = (i == index) ? theme.commentHighlightedAttrs : theme.commentAttrs;
    CGFloat labelWidth = 0.0;

    if (theme.prefixLabelFormat != nil) {
      NSString *labelFormat = [theme.prefixLabelFormat stringByReplacingOccurrencesOfString:@"%c" withString:@"%@"];
      NSString *prefixLabelString = [NSString stringWithFormat:labelFormat, labels[i]];
      [item appendAttributedString:[[NSAttributedString alloc]
                                    initWithString:prefixLabelString
                                        attributes:labelAttrs]];
      if (!theme.linear) { // get the label size for indent
        labelWidth = item.size.width;
      }
    }

    NSUInteger candidateStart = item.length;
    NSString *candidate = candidates[i];
    [item appendAttributedString:[[NSAttributedString alloc]
                                  initWithString:candidate
                                      attributes:attrs]];
    // Use left-to-right embedding to prevent right-to-left text from changing the layout of the candidate.
    [item addAttribute:NSWritingDirectionAttributeName
                 value:@[@0]
                 range:NSMakeRange(candidateStart, item.length - candidateStart)];

    if (i < comments.count && [comments[i] length] != 0) {
      NSString *comment = [@" " stringByAppendingString:comments[i]];
      [item appendAttributedString:[[NSAttributedString alloc]
                                    initWithString:comment
                                        attributes:commentAttrs]];
    }

    if (theme.suffixLabelFormat != nil) {
      NSString *labelFormat = [theme.suffixLabelFormat stringByReplacingOccurrencesOfString:@"%c" withString:@"%@"];
      NSString *suffixLabelString = [NSString stringWithFormat:labelFormat, labels[i]];
      [item appendAttributedString:[[NSAttributedString alloc]
                                    initWithString:suffixLabelString
                                        attributes:labelAttrs]];
    }

    NSMutableParagraphStyle *paragraphStyleCandidate = [theme.paragraphStyle mutableCopy];
    if (!theme.linear) {
      paragraphStyleCandidate.headIndent = labelWidth;
    }
    [item addAttribute:NSParagraphStyleAttributeName
                 value:paragraphStyleCandidate
                 range:NSMakeRange(0, item.length)];
    // determine if the line is too wide and line break is needed, based on screen size.
    NSString *separatorString = theme.linear ? @"　" : @"\n";
    if (i > 0) {
      NSUInteger separatorStart = text.length;
      NSMutableAttributedString *separator = [[NSMutableAttributedString alloc]
                                              initWithString:separatorString
                                              attributes:theme.attrs];
      [separator addAttribute:NSVerticalGlyphFormAttributeName
                        value:@NO
                        range:NSMakeRange(0, separator.length)];
      separatorRange = NSMakeRange(separatorStart, separator.length);
      [text appendAttributedString:separator];
      [text appendAttributedString:item];
      if (theme.linear && [self shouldBreakLineWithRange:NSMakeRange(lineStart, text.length - lineStart)]) {
        [text replaceCharactersInRange:separatorRange withString:@"\n"];
        lineStart = separatorStart + 1;
        separatorRange = NSMakeRange(NSNotFound, 0);
      }
    } else {
      [text appendAttributedString:item];
    }
    [candidateRanges addObject:[NSValue valueWithRange:NSMakeRange(text.length - item.length, item.length)]];
  }

  // paging indication
  NSRange pagingRange = NSMakeRange(NSNotFound, 0);
  if (numCandidates > 0 && theme.showPaging) {
    NSMutableAttributedString *paging = [[NSMutableAttributedString alloc] init];

    NSMutableAttributedString *pageUpString = [[NSMutableAttributedString alloc] initWithAttributedString:(pageNum > 0 ? theme.symbolBackFill : theme.symbolBackStroke)];
    if (_turnPage == NSPageUpFunctionKey) {
      [pageUpString addAttributes:theme.pagingHighlightedAttrs
                            range:NSMakeRange(0, pageUpString.length)];
    }
    [paging appendAttributedString:pageUpString];

    [paging appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %lu ", pageNum + 1] attributes:theme.pagingAttrs]];

    NSMutableAttributedString *pageDownString = [[NSMutableAttributedString alloc] initWithAttributedString:(lastPage ? theme.symbolForwardStroke : theme.symbolForwardFill)];
    if (_turnPage == NSPageDownFunctionKey) {
      [pageDownString addAttributes:theme.pagingHighlightedAttrs
                              range:NSMakeRange(0, pageDownString.length)];
    }
    [paging appendAttributedString:pageDownString];

    [text appendAttributedString:[[NSAttributedString alloc]
                                  initWithString:theme.linear ? @"　" : @"\n"
                                      attributes:theme.attrs]];
    NSUInteger pagingStart = text.length;
    CGFloat maxLineLength;
    if (theme.linear) {
      [text appendAttributedString:paging];
      if ([self shouldBreakLineWithRange:NSMakeRange(lineStart, text.length - lineStart)]) {
        if (separatorRange.length > 0) {
          [text replaceCharactersInRange:separatorRange withString:@"\n"];
        } else {
          [text insertAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:theme.attrs] atIndex:pagingStart-1];
          pagingStart += 1;
        }
      }
      NSMutableParagraphStyle *paragraphStylePaging = [theme.paragraphStyle mutableCopy];
      if ([self shouldUseTabsInRange:NSMakeRange(pagingStart, text.length - pagingStart) maxLineLength:&maxLineLength]) {
        [text replaceCharactersInRange:NSMakeRange(pagingStart-1, 1) withString:@"\t"];
        paragraphStylePaging.tabStops = @[[[NSTextTab alloc] initWithType:NSRightTabStopType location:maxLineLength]];
      }
      [text addAttribute:NSParagraphStyleAttributeName
                   value:paragraphStylePaging
                   range:NSMakeRange(candidateBlockStart, text.length - candidateBlockStart)];
    } else {
      NSMutableParagraphStyle *paragraphStylePaging = [theme.pagingParagraphStyle mutableCopy];
      if ([self shouldUseTabsInRange:NSMakeRange(pagingStart, paging.length) maxLineLength:&maxLineLength]) {
        [paging replaceCharactersInRange:NSMakeRange(pageUpString.length, 1) withString:@"\t"];
        [paging replaceCharactersInRange:NSMakeRange(paging.length - pageDownString.length - 1, 1) withString:@"\t"];
        paragraphStylePaging.tabStops = @[[[NSTextTab alloc] initWithType:NSCenterTabStopType location:maxLineLength/2],
                                          [[NSTextTab alloc] initWithType:NSRightTabStopType location:maxLineLength]];
      }
      [paging addAttribute:NSParagraphStyleAttributeName
                     value:paragraphStylePaging
                     range:NSMakeRange(0, paging.length)];
      [text appendAttributedString:paging];
      insets.bottom = theme.edgeInset.height;
    }
    pagingRange = NSMakeRange(text.length - paging.length, paging.length);
  }

  [text fixAttributesInRange:NSMakeRange(0, text.length)];
  if (preedit) {
    [self setLayoutForRange:preeditRange
          withReferenceFont:(theme.vertical ? [theme.attrs[NSFontAttributeName] verticalFont] : theme.attrs[NSFontAttributeName])
             paragraphStyle:theme.preeditParagraphStyle];
  }
  if (numCandidates > 0) {
    NSRange candidateBlockRange = NSMakeRange(candidateBlockStart, (!theme.linear && pagingRange.length > 0 ? pagingRange.location : text.length) - candidateBlockStart);
    [self setLayoutForRange:candidateBlockRange
          withReferenceFont:(theme.vertical ? [theme.attrs[NSFontAttributeName] verticalFont] : theme.attrs[NSFontAttributeName])
             paragraphStyle:theme.paragraphStyle];
    if (!theme.linear && pagingRange.length > 0) {
      [self setLayoutForRange:pagingRange
            withReferenceFont:theme.pagingAttrs[NSFontAttributeName]
               paragraphStyle:theme.pagingParagraphStyle];
    }
  }

  // text done!
  [self setAnimationBehavior:caretPos == NSNotFound ? NSWindowAnimationBehaviorUtilityWindow : NSWindowAnimationBehaviorDefault];
  [_view drawViewWithInsets:insets
            candidateRanges:candidateRanges
           highlightedIndex:index
               preeditRange:preeditRange
    highlightedPreeditRange:highlightedPreeditRange
                pagingRange:pagingRange
               pagingButton:turnPage];
  [self show];
}

- (void)updateStatusLong:(NSString *)messageLong statusShort:(NSString *)messageShort {
  SquirrelTheme *theme = _view.currentTheme;
  if ([theme.statusMessageType isEqualToString:@"mix"]) {
    if (messageShort) {
      _statusMessage = messageShort;
    } else {
      _statusMessage = messageLong;
    }
  } else if ([theme.statusMessageType isEqualToString:@"long"]) {
    _statusMessage = messageLong;
  } else if ([theme.statusMessageType isEqualToString:@"short"]) {
    if (messageShort) {
      _statusMessage = messageShort;
    } else if (messageLong) {
      _statusMessage = [messageLong substringWithRange:[messageLong rangeOfComposedCharacterSequenceAtIndex:0]];
    }
  }
}

- (void)showStatus:(NSString *)message {
  [self getTextWidthLimit];
  SquirrelTheme *theme = _view.currentTheme;
  _maxSize = NSZeroSize; // disable remember_size and fixed line_length for status messages
  NSEdgeInsets insets = NSEdgeInsetsMake(theme.edgeInset.height, theme.edgeInset.width,
                                         theme.edgeInset.height, theme.edgeInset.width);
  _view.textView.layoutOrientation = theme.vertical ? NSTextLayoutOrientationVertical : NSTextLayoutOrientationHorizontal;
  _view.textView.textContainer.lineFragmentPadding = theme.hilitedCornerRadius;

  NSTextStorage *text = _view.textStorage;
  [text setAttributedString:[[NSMutableAttributedString alloc] init]];
  [text appendAttributedString:[[NSMutableAttributedString alloc] initWithString:message attributes:theme.statusAttrs]];

  [text fixAttributesInRange:NSMakeRange(0, text.length)];
  [self setLayoutForRange:NSMakeRange(0, text.length)
        withReferenceFont:(theme.vertical ? [theme.statusAttrs[NSFontAttributeName] verticalFont] : theme.statusAttrs[NSFontAttributeName])
           paragraphStyle:theme.statusParagraphStyle];

  if (_statusTimer) {
    [_statusTimer invalidate];
  }
  [self setAnimationBehavior:NSWindowAnimationBehaviorUtilityWindow];
  [_view drawViewWithInsets:insets
            candidateRanges:@[]
           highlightedIndex:NSNotFound
               preeditRange:NSMakeRange(NSNotFound, 0)
    highlightedPreeditRange:NSMakeRange(NSNotFound, 0)
                pagingRange:NSMakeRange(NSNotFound, 0)
               pagingButton:NSNotFound];
  [self show];
  _statusTimer = [NSTimer scheduledTimerWithTimeInterval:kShowStatusDuration
                                                  target:self
                                                selector:@selector(hideStatus:)
                                                userInfo:nil
                                                 repeats:NO];
}

- (void)hideStatus:(NSTimer *)timer {
  [self hide];
}

static inline NSColor * blendColors(NSColor *foregroundColor,
                                    NSColor *backgroundColor) {
  if (!backgroundColor) { // return foregroundColor;
    backgroundColor = [NSColor lightGrayColor];
  }
  return [[foregroundColor blendedColorWithFraction:kBlendedBackgroundColorFraction
                                            ofColor:backgroundColor]
          colorWithAlphaComponent:foregroundColor.alphaComponent];
}

static inline NSColor * inverseColor(NSColor *color) {
  if (color == nil) {
    return nil;
  } else {
    return [NSColor colorWithColorSpace:color.colorSpace
                                    hue:color.hueComponent
                             saturation:color.saturationComponent
                             brightness:1 - color.brightnessComponent
                                  alpha:color.alphaComponent];
  }
}

static NSFontDescriptor * getFontDescriptor(NSString *fullname) {
  if (fullname == nil) {
    return nil;
  }

  NSArray *fontNames = [fullname componentsSeparatedByString:@","];
  NSMutableArray *validFontDescriptors = [[NSMutableArray alloc] initWithCapacity:fontNames.count];
  for (__strong NSString *fontName in fontNames) {
    fontName = [fontName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([NSFont fontWithName:fontName size:0.0] != nil) {
      // If the font name is not valid, NSFontDescriptor will still create something for us.
      // However, when we draw the actual text, Squirrel will crash if there is any font descriptor
      // with invalid font name.
      NSFontDescriptor *fontDescriptor = [NSFontDescriptor fontDescriptorWithName:fontName size:0.0];
      NSFontDescriptor *UIFontDescriptor = [fontDescriptor fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitUIOptimized];
      [validFontDescriptors addObject:([NSFont fontWithDescriptor:UIFontDescriptor size:0.0] != nil ? UIFontDescriptor : fontDescriptor)];
    }
  }
  if (validFontDescriptors.count == 0) {
    return nil;
  }
  NSFontDescriptor *initialFontDescriptor = validFontDescriptors[0];
  CTFontRef systemFontRef = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0.0, (CFStringRef)@"zh");
  NSFontDescriptor *systemFontDescriptor = CFBridgingRelease(CTFontCopyFontDescriptor(systemFontRef));
  CFRelease(systemFontRef);
  NSFontDescriptor *emojiFontDescriptor = [NSFontDescriptor fontDescriptorWithName:@"AppleColorEmoji" size:0.0];
  NSArray *fallbackDescriptors = [[validFontDescriptors subarrayWithRange:NSMakeRange(1, validFontDescriptors.count - 1)]
                                  arrayByAddingObjectsFromArray:@[systemFontDescriptor, emojiFontDescriptor]];
  NSDictionary *attributes = @{NSFontCascadeListAttribute: fallbackDescriptors};
  return [initialFontDescriptor fontDescriptorByAddingAttributes:attributes];
}

static CGFloat getLineHeight(NSFont *font, BOOL vertical) {
  if (vertical) {
    font = font.verticalFont;
  }
  CGFloat lineHeight = font.ascender - font.descender;
  NSArray *fallbackList = [font.fontDescriptor objectForKey:NSFontCascadeListAttribute];
  for (NSFontDescriptor *fallback in fallbackList) {
    NSFont *fallbackFont = [NSFont fontWithDescriptor:fallback size:font.pointSize];
    if (vertical) {
      fallbackFont = fallbackFont.verticalFont;
    }
    lineHeight = MAX(lineHeight, fallbackFont.ascender - fallbackFont.descender);
  }
  return lineHeight;
}

static void updateCandidateListLayout(BOOL *isLinearCandidateList, SquirrelConfig *config, NSString *prefix) {
  NSString *candidateListLayout = [config getString:[prefix stringByAppendingString:@"/candidate_list_layout"]];
  if ([candidateListLayout isEqualToString:@"stacked"]) {
    *isLinearCandidateList = false;
  } else if ([candidateListLayout isEqualToString:@"linear"]) {
    *isLinearCandidateList = true;
  } else {
    // Deprecated. Not to be confused with text_orientation: horizontal
    NSNumber *horizontal = [config getOptionalBool:[prefix stringByAppendingString:@"/horizontal"]];
    if (horizontal) {
      *isLinearCandidateList = horizontal.boolValue;
    }
  }
}

static void updateTextOrientation(BOOL *isVerticalText, SquirrelConfig *config, NSString *prefix) {
  NSString *textOrientation = [config getString:[prefix stringByAppendingString:@"/text_orientation"]];
  if ([textOrientation isEqualToString:@"horizontal"]) {
    *isVerticalText = false;
  } else if ([textOrientation isEqualToString:@"vertical"]) {
    *isVerticalText = true;
  } else {
    NSNumber *vertical = [config getOptionalBool:[prefix stringByAppendingString:@"/vertical"]];
    if (vertical) {
      *isVerticalText = vertical.boolValue;
    }
  }
}

- (void)loadConfig:(SquirrelConfig *)config forDarkMode:(BOOL)isDark {
  SquirrelTheme *theme = [_view selectTheme:isDark];
  [[self class] updateTheme:theme withConfig:config forDarkMode:isDark];
}

+ (void)updateTheme:(SquirrelTheme *)theme withConfig:(SquirrelConfig *)config forDarkMode:(BOOL)isDark {
  BOOL linear = NO;
  BOOL vertical = NO;
  updateCandidateListLayout(&linear, config, @"style");
  updateTextOrientation(&vertical, config, @"style");
  BOOL inlinePreedit = [config getBool:@"style/inline_preedit"];
  BOOL inlineCandidate = [config getBool:@"style/inline_candidate"];
  BOOL showPaging = [config getBool:@"style/show_paging"];
  BOOL rememberSize = [config getBool:@"style/remember_size"];
  NSString *statusMessageType = [config getString:@"style/status_message_type"];
  NSString *candidateFormat = [config getString:@"style/candidate_format"];

  NSString *fontName = [config getString:@"style/font_face"];
  CGFloat fontSize = MAX([config getDouble:@"style/font_point"], 0.0);
  NSString *labelFontName = [config getString:@"style/label_font_face"];
  CGFloat labelFontSize = MAX([config getDouble:@"style/label_font_point"], 0.0);
  NSString *commentFontName = [config getString:@"style/comment_font_face"];
  CGFloat commentFontSize = MAX([config getDouble:@"style/comment_font_point"], 0.0);
  CGFloat alpha = MIN(MAX([config getDouble:@"style/alpha"], 0.0), 1.0);
  CGFloat translucency = MIN(MAX([config getDouble:@"style/translucency"], 0.0), 1.0);
  CGFloat cornerRadius = MAX([config getDouble:@"style/corner_radius"], 0.0);
  CGFloat hilitedCornerRadius = MAX([config getDouble:@"style/hilited_corner_radius"], 0.0);
  CGFloat borderHeight = MAX([config getDouble:@"style/border_height"], 0.0);
  CGFloat borderWidth = MAX([config getDouble:@"style/border_width"], 0.0);
  CGFloat lineSpacing = MAX([config getDouble:@"style/line_spacing"], 0.0);
  CGFloat spacing = MAX([config getDouble:@"style/spacing"], 0.0);
  CGFloat baseOffset = [config getDouble:@"style/base_offset"];
  CGFloat lineLength = MAX([config getDouble:@"style/line_length"], 0.0);

  NSColor *backgroundColor;
  NSColor *backgroundImage;
  NSColor *borderColor;
  NSColor *preeditBackgroundColor;
  NSColor *candidateLabelColor;
  NSColor *highlightedCandidateLabelColor;
  NSColor *textColor;
  NSColor *highlightedTextColor;
  NSColor *highlightedBackColor;
  NSColor *candidateTextColor;
  NSColor *highlightedCandidateTextColor;
  NSColor *highlightedCandidateBackColor;
  NSColor *commentTextColor;
  NSColor *highlightedCommentTextColor;

  NSString *colorScheme;
  if (isDark) {
    colorScheme = [config getString:@"style/color_scheme_dark"];
  }
  if (!colorScheme) {
    colorScheme = [config getString:@"style/color_scheme"];
  }
  BOOL isNative = !colorScheme || [colorScheme isEqualToString:@"native"];
  if (!isNative) {
    NSString *prefix = [@"preset_color_schemes/" stringByAppendingString:colorScheme];
    if (@available(macOS 10.12, *)) {
      config.colorSpace = [config getString:[prefix stringByAppendingString:@"/color_space"]];
    }
    backgroundColor = [config getColor:[prefix stringByAppendingString:@"/back_color"]];
    backgroundImage = [config getPattern:[prefix stringByAppendingString:@"/back_image"]];
    borderColor = [config getColor:[prefix stringByAppendingString:@"/border_color"]];
    preeditBackgroundColor = [config getColor:[prefix stringByAppendingString:@"/preedit_back_color"]];
    textColor = [config getColor:[prefix stringByAppendingString:@"/text_color"]];
    highlightedTextColor = [config getColor:[prefix stringByAppendingString:@"/hilited_text_color"]];
    if (highlightedTextColor == nil) {
      highlightedTextColor = textColor;
    }
    highlightedBackColor = [config getColor:[prefix stringByAppendingString:@"/hilited_back_color"]];
    candidateTextColor = [config getColor:[prefix stringByAppendingString:@"/candidate_text_color"]];
    if (candidateTextColor == nil) {
      // in non-inline mode, 'text_color' is for rendering preedit text.
      // if not otherwise specified, candidate text is also rendered in this color.
      candidateTextColor = textColor;
    }
    highlightedCandidateTextColor = [config getColor:[prefix stringByAppendingString:@"/hilited_candidate_text_color"]];
    if (highlightedCandidateTextColor == nil) {
      highlightedCandidateTextColor = highlightedTextColor;
    }
    highlightedCandidateBackColor = [config getColor:[prefix stringByAppendingString:@"/hilited_candidate_back_color"]];
    if (highlightedCandidateBackColor == nil) {
      highlightedCandidateBackColor = highlightedBackColor;
    }
    commentTextColor = [config getColor:[prefix stringByAppendingString:@"/comment_text_color"]];
    highlightedCommentTextColor = [config getColor:[prefix stringByAppendingString:@"/hilited_comment_text_color"]];

    // the following per-color-scheme configurations, if exist, will
    // override configurations with the same name under the global 'style' section

    updateCandidateListLayout(&linear, config, prefix);
    updateTextOrientation(&vertical, config, prefix);

    NSNumber *inlinePreeditOverridden = [config getOptionalBool:[prefix stringByAppendingString:@"/inline_preedit"]];
    if (inlinePreeditOverridden) {
      inlinePreedit = inlinePreeditOverridden.boolValue;
    }
    NSNumber *inlineCandidateOverridden = [config getOptionalBool:[prefix stringByAppendingString:@"/inline_candidate"]];
    if (inlineCandidateOverridden) {
      inlineCandidate = inlineCandidateOverridden.boolValue;
    }
    NSNumber *showPagingOverridden = [config getOptionalBool:[prefix stringByAppendingString:@"/show_paging"]];
    if (showPagingOverridden) {
      showPaging = showPagingOverridden.boolValue;
    }
    NSString *candidateFormatOverridden = [config getString:[prefix stringByAppendingString:@"/candidate_format"]];
    if (candidateFormatOverridden) {
      candidateFormat = candidateFormatOverridden;
    }
    NSString *fontNameOverridden = [config getString:[prefix stringByAppendingString:@"/font_face"]];
    if (fontNameOverridden) {
      fontName = fontNameOverridden;
    }
    NSNumber *fontSizeOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/font_point"]];
    if (fontSizeOverridden) {
      fontSize = MAX(fontSizeOverridden.doubleValue, 0.0);
    }
    NSString *labelFontNameOverridden = [config getString:[prefix stringByAppendingString:@"/label_font_face"]];
    if (labelFontNameOverridden) {
      labelFontName = labelFontNameOverridden;
    }
    NSNumber *labelFontSizeOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/label_font_point"]];
    if (labelFontSizeOverridden) {
      labelFontSize = MAX(labelFontSizeOverridden.doubleValue, 0.0);
    }
    NSString *commentFontNameOverridden = [config getString:[prefix stringByAppendingString:@"/comment_font_face"]];
    if (commentFontNameOverridden) {
      commentFontName = commentFontNameOverridden;
    }
    NSNumber *commentFontSizeOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/comment_font_point"]];
    if (commentFontSizeOverridden) {
      commentFontSize = MAX(commentFontSizeOverridden.doubleValue, 0.0);
    }
    NSColor *candidateLabelColorOverridden = [config getColor:[prefix stringByAppendingString:@"/label_color"]];
    if (candidateLabelColorOverridden) {
      candidateLabelColor = candidateLabelColorOverridden;
    }
    NSColor *highlightedCandidateLabelColorOverridden = [config getColor:[prefix stringByAppendingString:@"/label_hilited_color"]];
    if (highlightedCandidateLabelColorOverridden == nil) {
      // for backward compatibility, 'label_hilited_color' and 'hilited_candidate_label_color' are both valid
      highlightedCandidateLabelColorOverridden = [config getColor:[prefix stringByAppendingString:@"/hilited_candidate_label_color"]];
    }
    if (highlightedCandidateLabelColorOverridden) {
      highlightedCandidateLabelColor = highlightedCandidateLabelColorOverridden;
    }
    NSNumber *alphaOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/alpha"]];
    if (alphaOverridden) {
      alpha = MIN(MAX(alphaOverridden.doubleValue, 0.0), 1.0);
    }
    NSNumber *translucencyOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/translucency"]];
    if (translucencyOverridden) {
      translucency = MIN(MAX(translucencyOverridden.doubleValue, 0.0), 1.0);
    }
    NSNumber *cornerRadiusOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/corner_radius"]];
    if (cornerRadiusOverridden) {
      cornerRadius = MAX(cornerRadiusOverridden.doubleValue, 0.0);
    }
    NSNumber *hilitedCornerRadiusOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/hilited_corner_radius"]];
    if (hilitedCornerRadiusOverridden) {
      hilitedCornerRadius = MAX(hilitedCornerRadiusOverridden.doubleValue, 0.0);
    }
    NSNumber *borderHeightOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/border_height"]];
    if (borderHeightOverridden) {
      borderHeight = MAX(borderHeightOverridden.doubleValue, 0.0);
    }
    NSNumber *borderWidthOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/border_width"]];
    if (borderWidthOverridden) {
      borderWidth = MAX(borderWidthOverridden.doubleValue, 0.0);
    }
    NSNumber *lineSpacingOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/line_spacing"]];
    if (lineSpacingOverridden) {
      lineSpacing = MAX(lineSpacingOverridden.doubleValue, 0.0);
    }
    NSNumber *spacingOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/spacing"]];
    if (spacingOverridden) {
      spacing = MAX(spacingOverridden.doubleValue, 0.0);
    }
    NSNumber *baseOffsetOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/base_offset"]];
    if (baseOffsetOverridden) {
      baseOffset = baseOffsetOverridden.doubleValue;
    }
    NSNumber *lineLengthOverridden = [config getOptionalDouble:[prefix stringByAppendingString:@"/line_length"]];
    if (lineLengthOverridden) {
      lineLength = MAX(lineLengthOverridden.doubleValue, 0.0);
    }
  }

  fontSize = fontSize ? : kDefaultFontSize;
  labelFontSize = labelFontSize ? : fontSize;
  commentFontSize = commentFontSize ? : fontSize;

  NSFontDescriptor *fontDescriptor = getFontDescriptor(fontName);
  NSFont *font = [NSFont fontWithDescriptor:(fontDescriptor ? : getFontDescriptor([NSFont userFontOfSize:0.0].fontName))
                                       size:fontSize];

  NSFontDescriptor *labelFontDescriptor = getFontDescriptor(labelFontName);
  NSFont *labelFont = labelFontDescriptor ? [NSFont fontWithDescriptor:labelFontDescriptor size:labelFontSize]
    : (fontDescriptor ? [NSFont fontWithDescriptor:fontDescriptor size:labelFontSize]
       : [NSFont monospacedDigitSystemFontOfSize:labelFontSize weight:NSFontWeightRegular]);

  NSFontDescriptor *commentFontDescriptor = getFontDescriptor(commentFontName);
  NSFont *commentFont = [NSFont fontWithDescriptor:(commentFontDescriptor ? : fontDescriptor)
                                              size:commentFontSize];

  NSFont *pagingFont = [NSFont fontWithDescriptor:[[NSFontDescriptor fontDescriptorWithName:@"AppleSymbols" size:0.0]
                                                   fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitUIOptimized]
                                             size:labelFontSize];

  CGFloat fontHeight = getLineHeight(font, vertical);
  CGFloat labelFontHeight = getLineHeight(labelFont, vertical);
  CGFloat commentFontHeight = getLineHeight(commentFont, vertical);
  CGFloat lineHeight = MAX(fontHeight, MAX(labelFontHeight, commentFontHeight));

  NSMutableParagraphStyle *preeditParagraphStyle = [theme.preeditParagraphStyle mutableCopy];
  preeditParagraphStyle.minimumLineHeight = fontHeight;
  preeditParagraphStyle.maximumLineHeight = fontHeight;
  preeditParagraphStyle.paragraphSpacing = spacing;

  NSMutableParagraphStyle *paragraphStyle = [theme.paragraphStyle mutableCopy];
  paragraphStyle.minimumLineHeight = lineHeight;
  paragraphStyle.maximumLineHeight = lineHeight;
  paragraphStyle.paragraphSpacing = lineSpacing / 2;
  paragraphStyle.paragraphSpacingBefore = lineSpacing / 2;

  NSMutableParagraphStyle *pagingParagraphStyle = [theme.pagingParagraphStyle mutableCopy];
  pagingParagraphStyle.minimumLineHeight = pagingFont.ascender - pagingFont.descender;
  pagingParagraphStyle.maximumLineHeight = pagingFont.ascender - pagingFont.descender;
  pagingParagraphStyle.paragraphSpacingBefore = pagingFont.leading;

  NSMutableParagraphStyle *statusParagraphStyle = [theme.statusParagraphStyle mutableCopy];
  statusParagraphStyle.minimumLineHeight = commentFontHeight;
  statusParagraphStyle.maximumLineHeight = commentFontHeight;

  NSMutableDictionary *attrs = [theme.attrs mutableCopy];
  NSMutableDictionary *highlightedAttrs = [theme.highlightedAttrs mutableCopy];
  NSMutableDictionary *labelAttrs = [theme.labelAttrs mutableCopy];
  NSMutableDictionary *labelHighlightedAttrs = [theme.labelHighlightedAttrs mutableCopy];
  NSMutableDictionary *commentAttrs = [theme.commentAttrs mutableCopy];
  NSMutableDictionary *commentHighlightedAttrs = [theme.commentHighlightedAttrs mutableCopy];
  NSMutableDictionary *preeditAttrs = [theme.preeditAttrs mutableCopy];
  NSMutableDictionary *preeditHighlightedAttrs = [theme.preeditHighlightedAttrs mutableCopy];
  NSMutableDictionary *pagingAttrs = [theme.pagingAttrs mutableCopy];
  NSMutableDictionary *pagingHighlightedAttrs = [theme.pagingHighlightedAttrs mutableCopy];
  NSMutableDictionary *statusAttrs = [theme.statusAttrs mutableCopy];

  attrs[NSFontAttributeName] = font;
  highlightedAttrs[NSFontAttributeName] = font;
  labelAttrs[NSFontAttributeName] = labelFont;
  labelHighlightedAttrs[NSFontAttributeName] = labelFont;
  commentAttrs[NSFontAttributeName] = commentFont;
  commentHighlightedAttrs[NSFontAttributeName] = commentFont;
  preeditAttrs[NSFontAttributeName] = font;
  preeditHighlightedAttrs[NSFontAttributeName] = font;
  pagingAttrs[NSFontAttributeName] = linear ? labelFont : pagingFont;
  statusAttrs[NSFontAttributeName] = commentFont;

  CGFloat labelMidlineOffset = vertical ? 0.0 : font.ascender/2 + font.descender/2 - labelFont.ascender/2 - labelFont.descender/2;
  attrs[NSBaselineOffsetAttributeName] = @(baseOffset);
  highlightedAttrs[NSBaselineOffsetAttributeName] = @(baseOffset);
  labelAttrs[NSBaselineOffsetAttributeName] = @(baseOffset + labelMidlineOffset);
  labelHighlightedAttrs[NSBaselineOffsetAttributeName] = @(baseOffset + labelMidlineOffset);
  commentAttrs[NSBaselineOffsetAttributeName] = @(baseOffset);
  commentHighlightedAttrs[NSBaselineOffsetAttributeName] = @(baseOffset);
  preeditAttrs[NSBaselineOffsetAttributeName] = @(baseOffset);
  preeditHighlightedAttrs[NSBaselineOffsetAttributeName] = @(baseOffset);
  pagingAttrs[NSBaselineOffsetAttributeName] = @(baseOffset);
  statusAttrs[NSBaselineOffsetAttributeName] = @(baseOffset);

  NSColor *secondaryTextColor = [[self class] secondaryTextColor];
  NSColor *accentColor = [[self class] accentColor];

  if (@available(macOS 10.14, *)) {
    if (theme.translucency > 0 &&
        ((backgroundColor.brightnessComponent >= 0.5 && isDark) ||
         (backgroundColor.brightnessComponent < 0.5 && !isDark))) {
      backgroundColor = inverseColor(backgroundColor);
      borderColor = inverseColor(borderColor);
      preeditBackgroundColor = inverseColor(preeditBackgroundColor);
      candidateTextColor = inverseColor(candidateTextColor);
      highlightedCandidateTextColor = [inverseColor(highlightedCandidateTextColor) highlightWithLevel:highlightedCandidateTextColor.brightnessComponent];
      highlightedCandidateBackColor = [inverseColor(highlightedCandidateBackColor) shadowWithLevel:1 - highlightedCandidateBackColor.brightnessComponent];
      candidateLabelColor = inverseColor(candidateLabelColor);
      highlightedCandidateLabelColor = [inverseColor(highlightedCandidateLabelColor) highlightWithLevel:highlightedCandidateLabelColor.brightnessComponent];
      commentTextColor = inverseColor(commentTextColor);
      highlightedCommentTextColor = [inverseColor(highlightedCommentTextColor) highlightWithLevel:highlightedCommentTextColor.brightnessComponent];
      textColor = inverseColor(textColor);
      highlightedTextColor = [inverseColor(highlightedTextColor) highlightWithLevel:highlightedTextColor.brightnessComponent];
      highlightedBackColor = [inverseColor(highlightedBackColor) shadowWithLevel:1 - highlightedBackColor.brightnessComponent];
    }
  }

  backgroundColor = backgroundColor ? : [NSColor controlBackgroundColor];
  borderColor = borderColor ? : isNative ? [NSColor gridColor] : nil;
  preeditBackgroundColor = preeditBackgroundColor ? : isNative ? [NSColor windowBackgroundColor] : nil;
  candidateTextColor = candidateTextColor ? : [NSColor controlTextColor];
  highlightedCandidateTextColor = highlightedCandidateTextColor ? : [NSColor selectedMenuItemTextColor];
  highlightedCandidateBackColor = highlightedCandidateBackColor ? : isNative ? [NSColor alternateSelectedControlColor] : nil;
  candidateLabelColor = candidateLabelColor ? : isNative ? accentColor : blendColors(highlightedCandidateBackColor, highlightedCandidateTextColor);
  highlightedCandidateLabelColor = highlightedCandidateLabelColor ? : isNative ? [NSColor alternateSelectedControlTextColor] : blendColors(highlightedCandidateTextColor, highlightedCandidateBackColor);
  commentTextColor = commentTextColor ? : secondaryTextColor;
  highlightedCommentTextColor = highlightedCommentTextColor ? : [NSColor alternateSelectedControlTextColor];
  textColor = textColor ? textColor : [NSColor textColor];
  highlightedTextColor = highlightedTextColor ? : [NSColor selectedTextColor];
  highlightedBackColor = highlightedBackColor ? : isNative ? [NSColor selectedTextBackgroundColor] : nil;

  attrs[NSForegroundColorAttributeName] = candidateTextColor;
  highlightedAttrs[NSForegroundColorAttributeName] = highlightedCandidateTextColor;
  labelAttrs[NSForegroundColorAttributeName] = candidateLabelColor;
  labelHighlightedAttrs[NSForegroundColorAttributeName] = highlightedCandidateLabelColor;
  commentAttrs[NSForegroundColorAttributeName] = commentTextColor;
  commentHighlightedAttrs[NSForegroundColorAttributeName] = highlightedCommentTextColor;
  preeditAttrs[NSForegroundColorAttributeName] = textColor;
  preeditHighlightedAttrs[NSForegroundColorAttributeName] = highlightedTextColor;
  pagingAttrs[NSForegroundColorAttributeName] = linear ? candidateLabelColor : textColor;
  pagingHighlightedAttrs[NSForegroundColorAttributeName] = linear ? highlightedCandidateLabelColor : highlightedTextColor;
  statusAttrs[NSForegroundColorAttributeName] = commentTextColor;

  preeditAttrs[NSParagraphStyleAttributeName] = preeditParagraphStyle;
  preeditHighlightedAttrs[NSParagraphStyleAttributeName] = preeditParagraphStyle;
  statusAttrs[NSParagraphStyleAttributeName] = statusParagraphStyle;

  labelAttrs[NSVerticalGlyphFormAttributeName] = @(vertical);
  labelHighlightedAttrs[NSVerticalGlyphFormAttributeName] = @(vertical);
  pagingAttrs[NSVerticalGlyphFormAttributeName] = @(NO);

  NSSize edgeInset = vertical ? NSMakeSize(borderHeight, borderWidth) : NSMakeSize(borderWidth, borderHeight);

  [theme setCornerRadius:MIN(cornerRadius, lineHeight/2)
     hilitedCornerRadius:MIN(hilitedCornerRadius, lineHeight/3)
               edgeInset:edgeInset
               linespace:lineSpacing
        preeditLinespace:spacing
                   alpha:(alpha == 0 ? 1.0 : alpha)
            translucency:translucency
              lineLength:lineLength
              showPaging:showPaging
            rememberSize:rememberSize
                  linear:linear
                vertical:vertical
           inlinePreedit:inlinePreedit
         inlineCandidate:inlineCandidate];

  theme.native = isNative;
  [theme setCandidateFormat:candidateFormat ? candidateFormat : kDefaultCandidateFormat];
  [theme setStatusMessageType:statusMessageType];

  [theme           setAttrs:attrs
           highlightedAttrs:highlightedAttrs
                 labelAttrs:labelAttrs
      labelHighlightedAttrs:labelHighlightedAttrs
               commentAttrs:commentAttrs
    commentHighlightedAttrs:commentHighlightedAttrs
               preeditAttrs:preeditAttrs
    preeditHighlightedAttrs:preeditHighlightedAttrs
                pagingAttrs:pagingAttrs
     pagingHighlightedAttrs:pagingHighlightedAttrs
                statusAttrs:statusAttrs];

  [theme setParagraphStyle:paragraphStyle
     preeditParagraphStyle:preeditParagraphStyle
      pagingParagraphStyle:pagingParagraphStyle
      statusParagraphStyle:statusParagraphStyle];

  [theme setBackgroundColor:backgroundColor
            backgroundImage:backgroundImage
      highlightedStripColor:highlightedCandidateBackColor
    highlightedPreeditColor:highlightedBackColor
     preeditBackgroundColor:preeditBackgroundColor
                borderColor:borderColor];
}

@end
