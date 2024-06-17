#import "SquirrelPanel.hh"

#import "SquirrelApplicationDelegate.hh"
#import "SquirrelConfig.hh"
#import <QuartzCore/QuartzCore.h>

static NSString* const kDefaultCandidateFormat = @"%c. %@ %s";
static NSString* const kControlCharacterSizeAttributeName = @"ControlCharacterSize";
static const NSTimeInterval kShowStatusDuration = 2.0;
static const CGFloat kBlendedBackgroundColorFraction = 0.2;
static const CGFloat kDefaultFontSize = 24;
static const CGFloat kOffsetGap = 5;

static void rectVertices(NSRect rect, NSPointArray vertices) {
  vertices[0] = rect.origin;
  vertices[1] = NSMakePoint(rect.origin.x, rect.origin.y + rect.size.height);
  vertices[2] = NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height);
  vertices[3] = NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y);
}

typedef struct SquirrelTextPolygon {
  NSRect head, body, tail;

  inline NSPoint origin() {
    return (NSIsEmptyRect(head) ? body : head).origin;
  }
  inline CGFloat minY() {
    return NSMinY(NSIsEmptyRect(head) ? body : head);
  }
  inline CGFloat maxY() {
    return NSMaxY(NSIsEmptyRect(tail) ? body : tail);
  }
  inline BOOL separated() {
    return !NSIsEmptyRect(head) && NSIsEmptyRect(body) &&
    !NSIsEmptyRect(tail) && NSMaxX(tail) < nexttoward(NSMinX(head), -INFINITY);
  }
  inline BOOL mouseInPolygon(NSPoint point, BOOL flipped) {
    return (!NSIsEmptyRect(body) && NSMouseInRect(point, body, flipped)) ||
           (!NSIsEmptyRect(head) && NSMouseInRect(point, head, flipped)) ||
           (!NSIsEmptyRect(tail) && NSMouseInRect(point, tail, flipped));
  }
  void getVertices(NSPointArray vertices) {
    switch ((NSIsEmptyRect(head) << 2) | (NSIsEmptyRect(body) << 1) | (NSIsEmptyRect(tail) << 0)) {
      case 0b011:
        rectVertices(head, vertices);
        break;
      case 0b110:
        rectVertices(tail, vertices);
        break;
      case 0b101:
        rectVertices(body, vertices);
        break;
      case 0b001: {
        NSPoint headVertices[4], bodyVertices[4];
        rectVertices(head, headVertices);
        rectVertices(body, bodyVertices);
        vertices[0] = headVertices[0];
        vertices[1] = headVertices[1];
        vertices[2] = bodyVertices[0];
        vertices[3] = bodyVertices[1];
        vertices[4] = bodyVertices[2];
        vertices[5] = headVertices[3];
      } break;
      case 0b100: {
        NSPoint bodyVertices[4], tailVertices[4];
        rectVertices(body, bodyVertices);
        rectVertices(tail, tailVertices);
        vertices[0] = bodyVertices[0];
        vertices[1] = tailVertices[1];
        vertices[2] = tailVertices[2];
        vertices[3] = tailVertices[3];
        vertices[4] = bodyVertices[2];
        vertices[5] = bodyVertices[3];
      } break;
      case 0b010:
        if (NSMinX(head) <= NSMaxX(tail)) {
          NSPoint headVertices[4], tailVertices[4];
          rectVertices(head, headVertices);
          rectVertices(tail, tailVertices);
          vertices[0] = headVertices[0];
          vertices[1] = headVertices[1];
          vertices[2] = tailVertices[0];
          vertices[3] = tailVertices[1];
          vertices[4] = tailVertices[2];
          vertices[5] = tailVertices[3];
          vertices[6] = headVertices[2];
          vertices[7] = headVertices[3];
        } else {
          vertices = NULL;
        } break;
      case 0b000: {
        NSPoint headVertices[4], bodyVertices[4], tailVertices[4];
        rectVertices(head, headVertices);
        rectVertices(body, bodyVertices);
        rectVertices(tail, tailVertices);
        vertices[0] = headVertices[0];
        vertices[1] = headVertices[1];
        vertices[2] = bodyVertices[0];
        vertices[3] = tailVertices[1];
        vertices[4] = tailVertices[2];
        vertices[5] = tailVertices[3];
        vertices[6] = bodyVertices[2];
        vertices[7] = headVertices[3];
      } break;
      default:
        vertices = NULL;
        break;
    }
  }

} SquirrelTextPolygon;


NS_HEADER_AUDIT_BEGIN(nullability, sendability)

__attribute__((objc_direct_members))
@interface NSCharacterSet (FullWidthCharacterSets)
@property(nonatomic, readonly, copy, nonnull, class) NSCharacterSet *fullWidthDigitCharacterSet;
@property(nonatomic, readonly, copy, nonnull, class) NSCharacterSet *fullWidthLatinCapitalCharacterSet;
@end

__attribute__((objc_direct_members))
@interface NSAffineTransform (NSCGAffinTransformConversion)
@property(nonatomic, readonly) CGAffineTransform transformMatrix;
@end

__attribute__((objc_direct_members))
@interface NSBezierPath (BezierPathQuartzUtilities)
@property(nonatomic, readonly, nullable) CGPathRef quartzPath;
@end

__attribute__((objc_direct_members))
@interface NSColor (semanticColors)
@property(nonatomic, readonly, strong, nonnull) NSColor* hooverColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* disabledColor;
@end

typedef NS_CLOSED_ENUM(NSInteger, ColorInversionExtent) {
  kStandardColorInversion = 0,
  kAugmentedColorInversion = 1,
  kModerateColorInversion = -1
};

__attribute__((objc_direct_members))
@interface NSColor (NSColorWithLabColorSpace)
@property(nonatomic, readonly) CGFloat lStarComponent; // Luminance
@property(nonatomic, readonly) CGFloat aStarComponent; // Green-Red
@property(nonatomic, readonly) CGFloat bStarComponent; // Blue-Yellow
@end

typedef NS_CLOSED_ENUM(BOOL, SquirrelStyle) {
  kDefaultStyle = NO,
  kLightStyle = NO,
  kDarkStyle = YES
};

typedef NS_CLOSED_ENUM(NSUInteger, SquirrelStatusMessageType) {
  kStatusMessageTypeMixed = 0,
  kStatusMessageTypeShort = 1,
  kStatusMessageTypeLong = 2
};

typedef NS_CLOSED_ENUM(NSUInteger, SquirrelContentBlock) {
  kPreeditBlock,
  kLinearCandidateBlock,
  kStackedCandidateBlock,
  kPagingBlock,
  kStatusBlock
};

__attribute__((objc_direct_members))
@interface NSFlippedView : NSView
@end


@interface SquirrelTextContainer : NSTextContainer

@property(nonatomic, weak, nullable, direct) NSParagraphStyle* defaultParagraphStyle;
@property(nonatomic, direct) SquirrelContentBlock contentBlock;
@property(nonatomic) NSTextLayoutOrientation layoutOrientation;

- (NSRect)layoutText __attribute__((objc_direct));

@end


__attribute__((objc_direct_members))
@interface SquirrelTextView : NSTextView
@property(nonatomic, strong, nonnull) SquirrelTextContainer* container;
@property(nonatomic) SquirrelContentBlock contentBlock;

- (instancetype _Nonnull)initWithContentBlock:(SquirrelContentBlock)contentBlock
                                      storage:(NSTextStorage* _Nonnull)textStorage;
- (NSTextRange* _Nullable)textRangeFromCharRange:(NSRange)charRange API_AVAILABLE(macos(12.0));
- (NSRange)charRangeFromTextRange:(NSTextRange* _Nullable)textRange API_AVAILABLE(macos(12.0));
- (NSRect)layoutText;
- (NSRect)blockRectForRange:(NSRange)charRange;
- (SquirrelTextPolygon)textPolygonForRange:(NSRange)charRange;
@end

__attribute__((objc_direct_members))
@interface SquirrelTheme : NSObject

@property(nonatomic, readonly, strong, nonnull, class) SquirrelTheme* lightTheme;
@property(nonatomic, readonly, strong, nonnull, class) API_AVAILABLE(macos(10.14)) SquirrelTheme* darkTheme;
@property(nonatomic, readonly, strong, nonnull, class) SquirrelTheme* currentTheme;
@property(nonatomic, class) SquirrelStyle currentStyle;

@property(nonatomic, readonly, strong, nonnull) NSColor* backColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* preeditForeColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* textForeColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* commentForeColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* labelForeColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* hilitedPreeditForeColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* hilitedTextForeColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* hilitedCommentForeColor;
@property(nonatomic, readonly, strong, nonnull) NSColor* hilitedLabelForeColor;
@property(nonatomic, readonly, strong, nullable) NSColor* dimmedLabelForeColor;
@property(nonatomic, readonly, strong, nullable) NSColor* hilitedCandidateBackColor;
@property(nonatomic, readonly, strong, nullable) NSColor* hilitedPreeditBackColor;
@property(nonatomic, readonly, strong, nullable) NSColor* candidateBackColor;
@property(nonatomic, readonly, strong, nullable) NSColor* preeditBackColor;
@property(nonatomic, readonly, strong, nullable) NSColor* borderColor;
@property(nonatomic, readonly, strong, nullable) NSImage* backImage;

@property(nonatomic, readonly) NSSize borderInsets;
@property(nonatomic, readonly) CGFloat cornerRadius;
@property(nonatomic, readonly) CGFloat hilitedCornerRadius;
@property(nonatomic, readonly) CGFloat fullWidth;
@property(nonatomic, readonly) CGFloat lineSpacing;
@property(nonatomic, readonly) CGFloat preeditSpacing;
@property(nonatomic, readonly) CGFloat opacity;
@property(nonatomic, readonly) CGFloat lineLength;
@property(nonatomic, readonly) CGFloat shadowSize;
@property(nonatomic, readonly) float translucency;
@property(nonatomic, readonly) BOOL stackColors;
@property(nonatomic, readonly) BOOL showPaging;
@property(nonatomic, readonly) BOOL rememberSize;
@property(nonatomic, readonly) BOOL tabular;
@property(nonatomic, readonly) BOOL linear;
@property(nonatomic, readonly) BOOL vertical;
@property(nonatomic, readonly) BOOL inlinePreedit;
@property(nonatomic, readonly) BOOL inlineCandidate;

@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSAttributedStringKey, id>* textAttrs;
@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSAttributedStringKey, id>* labelAttrs;
@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSAttributedStringKey, id>* commentAttrs;
@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSAttributedStringKey, id>* preeditAttrs;
@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSAttributedStringKey, id>* pagingAttrs;
@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSAttributedStringKey, id>* statusAttrs;
@property(nonatomic, readonly, strong, nonnull) NSParagraphStyle* candidateParagraphStyle;
@property(nonatomic, readonly, strong, nonnull) NSParagraphStyle* preeditParagraphStyle;
@property(nonatomic, readonly, strong, nonnull) NSParagraphStyle* statusParagraphStyle;
@property(nonatomic, readonly, strong, nonnull) NSParagraphStyle* pagingParagraphStyle;
@property(nonatomic, readonly, strong, nullable) NSParagraphStyle* truncatedParagraphStyle;

@property(nonatomic, readonly, strong, nonnull) NSAttributedString* separator;
@property(nonatomic, readonly, strong, nonnull) NSAttributedString* symbolDeleteFill;
@property(nonatomic, readonly, strong, nonnull) NSAttributedString* symbolDeleteStroke;
@property(nonatomic, readonly, strong, nullable) NSAttributedString* symbolBackFill;
@property(nonatomic, readonly, strong, nullable) NSAttributedString* symbolBackStroke;
@property(nonatomic, readonly, strong, nullable) NSAttributedString* symbolForwardFill;
@property(nonatomic, readonly, strong, nullable) NSAttributedString* symbolForwardStroke;
@property(nonatomic, readonly, strong, nullable) NSAttributedString* symbolCompress;
@property(nonatomic, readonly, strong, nullable) NSAttributedString* symbolExpand;
@property(nonatomic, readonly, strong, nullable) NSAttributedString* symbolLock;

@property(nonatomic, readonly, strong, nonnull) NSArray<NSString*>* rawLabels;
@property(nonatomic, readonly, strong, nullable) NSArray<NSString*>* labels;
@property(nonatomic, readonly, strong, nonnull) NSAttributedString* candidateTemplate;
@property(nonatomic, readonly, strong, nonnull) NSAttributedString* candidateHilitedTemplate;
@property(nonatomic, readonly, strong, nullable) NSAttributedString* candidateDimmedTemplate;
@property(nonatomic, readonly, strong, nonnull) NSString* selectKeys;
@property(nonatomic, readonly, strong, nonnull) NSString* rawCandidateFormat;
@property(nonatomic, readonly, strong, nullable) NSString* candidateFormat;
@property(nonatomic, readonly, strong, nonnull) NSString* scriptVariant;
@property(nonatomic, readonly) SquirrelStatusMessageType statusMessageType;
@property(nonatomic, readonly) NSUInteger pageSize;
@property(nonatomic, readonly) SquirrelStyle style;

- (instancetype _Nonnull)initWithStyle:(SquirrelStyle)style NS_DESIGNATED_INITIALIZER;
- (void)updateLabelsWithConfig:(SquirrelConfig* _Nonnull)config
                  directUpdate:(BOOL)update;
- (void)updateSelectKeys:(NSString* _Nonnull)selectKeys
                  labels:(NSArray<NSString*>* _Nonnull)rawLabels
            directUpdate:(BOOL)update;
- (void)updateCandidateFormat:(NSString* _Nonnull)rawCandidateFormat;
- (void)updateStatusMessageType:(NSString* _Nullable)type;
- (void)updateWithConfig:(SquirrelConfig* _Nonnull)config
            styleOptions:(NSSet<NSString*>* _Nonnull)styleOptions
           scriptVariant:(NSString* _Nonnull)scriptVariant;
- (void)setAnnotationHeight:(CGFloat)height;
- (void)updateScriptVariant:(NSString* _Nonnull)scriptVariant;
@end

__attribute__((objc_direct_members))
@interface SquirrelLayoutManager : NSLayoutManager <NSLayoutManagerDelegate>
@end

__attribute__((objc_direct_members)) API_AVAILABLE(macos(12.0))
@interface SquirrelTextLayoutFragment : NSTextLayoutFragment<NSTextLayoutOrientationProvider>
@end

__attribute__((objc_direct_members)) API_AVAILABLE(macos(12.0))
@interface SquirrelTextLayoutManager : NSTextLayoutManager <NSTextLayoutManagerDelegate>
@end

NS_HEADER_AUDIT_END(nullability, sendability)


@implementation NSCharacterSet (FullWidthCharacterSets)

+ (NSCharacterSet *)fullWidthDigitCharacterSet {
  return [self characterSetWithRange:NSMakeRange(0xFF10, 10)];
}

+ (NSCharacterSet *)fullWidthLatinCapitalCharacterSet {
  return [self characterSetWithRange:NSMakeRange(0xFF21, 26)];
}

@end  // NSCharacterSet (FullWidthCharacterSets)


@implementation NSAffineTransform (NSCGAffinTransformConversion)

- (CGAffineTransform)transformMatrix {
  NSAffineTransformStruct matrix = self.transformStruct;
  return CGAffineTransformMake(matrix.m11, matrix.m12, matrix.m21, matrix.m22, matrix.tX, matrix.tY);
}

@end  // NSAffinTransform (NSCGAffinTransformConversion)


@implementation NSBezierPath (BezierPathQuartzUtilities)

- (CGPathRef)quartzPath {
  if (@available(macOS 14.0, *))
    return self.CGPath;
  // Then draw the path elements.
  if (NSInteger numElements = self.elementCount; numElements > 0) {
    CGMutablePathRef path = CGPathCreateMutable();
    NSPoint points[3];
    for (NSInteger i = 0; i < numElements; i++) {
      switch ([self elementAtIndex:i associatedPoints:points]) {
        case NSBezierPathElementMoveTo:
          CGPathMoveToPoint(path, NULL, points[0].x, points[0].y);
          break;
        case NSBezierPathElementLineTo:
          CGPathAddLineToPoint(path, NULL, points[0].x, points[0].y);
          break;
        case NSBezierPathElementCurveTo:
          CGPathAddCurveToPoint(path, NULL, points[0].x, points[0].y, points[1].x, points[1].y, points[2].x, points[2].y);
          break;
        case NSBezierPathElementQuadraticCurveTo:
          CGPathAddQuadCurveToPoint(path, NULL, points[0].x, points[0].y, points[1].x, points[1].y);
          break;
        case NSBezierPathElementClosePath:
          CGPathCloseSubpath(path);
          break;
      }
    }
    CGPathRef immutablePath = CGPathCreateCopy(path);
    CGPathRelease(path);
    return (CGPathRef)CFAutorelease(immutablePath);
  }
  return NULL;
}

// Bezier squircle curves, whose rounded corners are smooth (continously differentiable)
+ (NSBezierPath*)squirclePathWithVertices:(NSPointArray)vertices
                                    count:(NSUInteger)numVertex
                             cornerRadius:(CGFloat)cornerRadius {
  if (vertices == NULL || (numVertex != 4 && numVertex != 6 && numVertex != 8))
    return nil;
  NSBezierPath* path = self.bezierPath;
  // Always start from the topleft origin going along y axis
  NSPoint vertex = vertices[numVertex - 1];
  NSPoint nextVertex = vertices[0];
  CGVector nextDiff = CGVectorMake(nextVertex.x - vertex.x, nextVertex.y - vertex.y);
  CGVector lastDiff;
  CGFloat arcRadius;
  NSPoint startPoint;
  NSPoint endPoint = NSMakePoint(vertex.x + nextDiff.dx * 0.5, vertex.y);
  [path moveToPoint:endPoint];
  for (NSUInteger i = 0; i < numVertex; ++i) {
    lastDiff = nextDiff;
    vertex = nextVertex;
    nextVertex = vertices[(i + 1) % numVertex];
    nextDiff = CGVectorMake(nextVertex.x - vertex.x, nextVertex.y - vertex.y);
    if (fabs(nextDiff.dx) >= fabs(nextDiff.dy)) {
      arcRadius = floor(fmin(fabs(cornerRadius), fmin(fabs(nextDiff.dx), fabs(lastDiff.dy)) * 0.5));
      startPoint = NSMakePoint(vertex.x, vertex.y - copysign(arcRadius, lastDiff.dy));
      endPoint = NSMakePoint(vertex.x + copysign(arcRadius, nextDiff.dx), vertex.y);
    } else {
      arcRadius = floor(fmin(fabs(cornerRadius), fmin(fabs(nextDiff.dy), fabs(lastDiff.dx)) * 0.5));
      startPoint = NSMakePoint(vertex.x - copysign(arcRadius, lastDiff.dx), vertex.y);
      endPoint = NSMakePoint(vertex.x, vertex.y + copysign(arcRadius, nextDiff.dy));
    }
    [path lineToPoint:startPoint];
    [path curveToPoint:endPoint controlPoint1:vertex controlPoint2:vertex];
  }
  [path closePath];
  return path;
}

+ (NSBezierPath*)squirclePathForRect:(NSRect)rect
                        cornerRadius:(CGFloat)cornerRadius {
  NSPoint vertices[4];
  rectVertices(rect, vertices);
  return [self squirclePathWithVertices:vertices count:4
                           cornerRadius:cornerRadius];
}

+ (NSBezierPath*)squirclePathForPolygon:(SquirrelTextPolygon)polygon
                           cornerRadius:(CGFloat)cornerRadius {
  NSBezierPath* path;
  if (polygon.separated()) {
    NSPoint headVertices[4], tailVertices[4];
    rectVertices(polygon.head, headVertices);
    rectVertices(polygon.tail, tailVertices);
    path = [self squirclePathWithVertices:headVertices count:4
                             cornerRadius:cornerRadius];
    [path appendBezierPath:[self squirclePathWithVertices:tailVertices count:4
                                             cornerRadius:cornerRadius]];
  } else {
    NSUInteger numVertex = clamp((NSIsEmptyRect(polygon.head) ? 0 : 4UL) +
                                 (NSIsEmptyRect(polygon.body) ? 0 : 2UL) +
                                 (NSIsEmptyRect(polygon.tail) ? 0 : 4UL), 4UL, 8UL);
    NSPoint vertices[numVertex];
    polygon.getVertices(vertices);
    path = [self squirclePathWithVertices:vertices count:numVertex
                             cornerRadius:cornerRadius];
  }
  return path;
}

@end  // NSBezierPath (BezierPathQuartzUtilities)


__attribute__((objc_direct_members))
@implementation NSFontDescriptor (NSFontDescriptorWithFallbackFonts)

static NSArray<NSDictionary<NSFontDescriptorFeatureKey, NSNumber*>*>* const features =
  @[@{NSFontFeatureTypeIdentifierKey: @(kVerticalSubstitutionType),
      NSFontFeatureSelectorIdentifierKey: @(kSubstituteVerticalFormsOnSelector)},
    @{NSFontFeatureTypeIdentifierKey: @(kCJKVerticalRomanPlacementType),
      NSFontFeatureSelectorIdentifierKey: @(kCJKVerticalRomanCenteredSelector)},
    @{NSFontFeatureTypeIdentifierKey: @(kRubyKanaType),
      NSFontFeatureSelectorIdentifierKey: @(kRubyKanaOffSelector)}];

+ (NSFontDescriptor*)createWithFullname:(NSString*)fullname {
  if (fullname.length == 0)
    return nil;
  NSArray<NSString*>* fontNames = [fullname componentsSeparatedByString:@","];
  NSMutableArray<NSFontDescriptor*>* validFontDescriptors =
  [NSMutableArray.alloc initWithCapacity:fontNames.count];
  for (NSString* fontName in fontNames) {
    if (NSFont* font = [NSFont fontWithName:[fontName stringByTrimmingCharactersInSet:
                                             NSCharacterSet.whitespaceAndNewlineCharacterSet]
                                       size:0.0]) {
      /* If the font name is not valid, NSFontDescriptor will still create something for us.
       However, when we draw the actual text, Squirrel will crash if there is any font descriptor
       with invalid font name. */
      NSFontDescriptor* fontDescriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:
                                          @{NSFontFeatureSettingsAttribute: features}];
      NSFontDescriptor* UIFontDescriptor = [fontDescriptor fontDescriptorWithSymbolicTraits:
                                            NSFontDescriptorTraitUIOptimized];
      [validFontDescriptors addObject:[NSFont fontWithDescriptor:UIFontDescriptor size:0.0] != nil ?
                                      UIFontDescriptor : fontDescriptor];
    }
  }
  if (validFontDescriptors.count == 0)
    return nil;
  NSFontDescriptor* initialFontDescriptor = validFontDescriptors[0];
  NSFontDescriptor* emojiFontDescriptor =
    [[self fontDescriptorWithName:@"AppleColorEmoji" size:0.0]
     fontDescriptorByAddingAttributes:@{NSFontFeatureSettingsAttribute: features}];
  NSArray<NSFontDescriptor*>* fallbackDescriptors =
    [[validFontDescriptors subarrayWithRange:NSMakeRange(1, validFontDescriptors.count - 1)]
     arrayByAddingObject:emojiFontDescriptor];
  return [initialFontDescriptor fontDescriptorByAddingAttributes:
          @{NSFontCascadeListAttribute: fallbackDescriptors}];
}

@end  // NSFontDescriptor (NSFontDescriptorWithFallbackFonts)


__attribute__((objc_direct_members))
@implementation NSFont (NSFontGetLineHeight)

- (CGFloat)lineHeightAsVerticalFont:(BOOL)vertical {
  NSFont* font = vertical ? self.verticalFont : self;
  CGFloat lineHeight = ceil(font.ascender - font.descender);
  NSArray<NSFontDescriptor*>* fallbackList =
  [font.fontDescriptor objectForKey:NSFontCascadeListAttribute];
  for (NSFontDescriptor* fallback in fallbackList) {
    NSFont* fallbackFont = [NSFont fontWithDescriptor:fallback
                                                 size:font.pointSize];
    if (vertical)
      fallbackFont = fallbackFont.verticalFont;
    lineHeight = fmax(lineHeight, ceil(fallbackFont.ascender - fallbackFont.descender));
  }
  return lineHeight;
}

@end  // NSFont (NSFontGetLineHeight)


__attribute__((objc_direct_members))
@implementation NSMutableAttributedString (NSMutableAttributedStringMarkDownFormatting)

- (void)superscriptionRange:(NSRange)range {
  [self enumerateAttribute:NSFontAttributeName
                   inRange:range
                   options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired
                usingBlock:^(NSFont* _Nullable value, NSRange subRange, BOOL* _Nonnull stop) {
    NSFont* font = [NSFont fontWithDescriptor:value.fontDescriptor
                                         size:floor(value.pointSize * 0.55)];
    [self addAttributes:@{NSFontAttributeName: font,
                          NSSuperscriptAttributeName: @1}
                  range:subRange];
  }];
}

- (void)subscriptionRange:(NSRange)range {
  [self enumerateAttribute:NSFontAttributeName
                   inRange:range
                   options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired
                usingBlock:^(NSFont* _Nullable value, NSRange subRange, BOOL* _Nonnull stop) {
    NSFont* font = [NSFont fontWithDescriptor:value.fontDescriptor
                                         size:floor(value.pointSize * 0.55)];
    [self addAttributes:@{NSFontAttributeName: font,
                          NSSuperscriptAttributeName: @-1}
                  range:subRange];
  }];
}

static NSRegularExpression* const kMarkDownRegex =
  [NSRegularExpression.alloc
   initWithPattern:@"((\\*{1,2}|\\^|~{1,2})|((?<=\\b)_{1,2})|<(b|strong|i|em|u|sup|sub|s)>)(.+?)(\\2|\\3(?=\\b)|<\\/\\4>)"
   options:NSRegularExpressionUseUnicodeWordBoundaries error:nil];

- (void)formatMarkDown {
  NSInteger __block offset = 0;
  [kMarkDownRegex enumerateMatchesInString:self.mutableString options:0 range:NSMakeRange(0, self.length)
                                usingBlock:^(NSTextCheckingResult* _Nullable result, NSMatchingFlags flags, BOOL* _Nonnull stop) {
    result = [result resultByAdjustingRangesWithOffset:offset];
    NSString* tag = [self.mutableString substringWithRange:[result rangeAtIndex:1]];
    if ([tag isEqualToString:@"**"] || [tag isEqualToString:@"__"] ||
        [tag isEqualToString:@"<b>"] || [tag isEqualToString:@"<strong>"])
      [self applyFontTraits:NSBoldFontMask
                      range:[result rangeAtIndex:5]];
    else if ([tag isEqualToString:@"*"] || [tag isEqualToString:@"_"] ||
             [tag isEqualToString:@"<i>"] || [tag isEqualToString:@"<em>"])
      [self applyFontTraits:NSItalicFontMask
                      range:[result rangeAtIndex:5]];
    else if ([tag isEqualToString:@"<u>"])
      [self addAttribute:NSUnderlineStyleAttributeName
                   value:@(NSUnderlineStyleSingle)
                   range:[result rangeAtIndex:5]];
    else if ([tag isEqualToString:@"~~"] || [tag isEqualToString:@"<s>"])
      [self addAttribute:NSStrikethroughStyleAttributeName
                   value:@(NSUnderlineStyleSingle)
                   range:[result rangeAtIndex:5]];
    else if ([tag isEqualToString:@"^"] || [tag isEqualToString:@"<sup>"])
      [self superscriptionRange:[result rangeAtIndex:5]];
    else if ([tag isEqualToString:@"~"] || [tag isEqualToString:@"<sub>"])
      [self subscriptionRange:[result rangeAtIndex:5]];

    [self deleteCharactersInRange:[result rangeAtIndex:6]];
    [self deleteCharactersInRange:[result rangeAtIndex:1]];
    offset -= [result rangeAtIndex:6].length + [result rangeAtIndex:1].length;
  }];
  if (offset != 0) // repeat until no more nested markdown
    [self formatMarkDown];
}

static NSRegularExpression* const kRubyRegex =
  [NSRegularExpression.alloc initWithPattern:@"(\\x{FFF9}\\s*)(\\S+?)(\\s*\\x{FFFA}(.+?)\\x{FFFB})"
                                     options:0 error:nil];

- (CGFloat)annotateRubyInRange:(NSRange)range
           verticalOrientation:(BOOL)isVertical
                 maximumLength:(CGFloat)maxLength
                 scriptVariant:(NSString*)scriptVariant {
  CGFloat __block rubyLineHeight;
  [kRubyRegex enumerateMatchesInString:self.mutableString options:0 range:range
                            usingBlock:^(NSTextCheckingResult* _Nullable result, NSMatchingFlags flags, BOOL* _Nonnull stop) {
    NSRange baseRange = [result rangeAtIndex:2];
    // no ruby annotation if the base string includes line breaks
    if ([self attributedSubstringFromRange:NSMakeRange(0, NSMaxRange(baseRange))].size.width > nexttoward(maxLength, -INFINITY)) {
      [self deleteCharactersInRange:NSMakeRange(NSMaxRange(result.range) - 1, 1)];
      [self deleteCharactersInRange:NSMakeRange([result rangeAtIndex:3].location, 1)];
      [self deleteCharactersInRange:NSMakeRange([result rangeAtIndex:1].location, 1)];
    } else {
      // base string must use only one font so that all fall within one glyph run
      // and the ruby annotation is aligned with no duplicates
      NSFont* baseFont = [self attribute:NSFontAttributeName
                                 atIndex:baseRange.location
                          effectiveRange:NULL];
      NSString* baseString = [self.mutableString substringWithRange:baseRange];
      baseFont = CFBridgingRelease(CTFontCreateForStringWithLanguage((CTFontRef)baseFont, (CFStringRef)baseString,
                                                                     CFRangeMake(0, (CFIndex)baseRange.length),
                                                                     (CFStringRef)scriptVariant));
      NSString* rubyString = [self.mutableString substringWithRange:[result rangeAtIndex:4]];
      NSFont* rubyFont = [NSFont fontWithDescriptor:baseFont.fontDescriptor
                                               size:baseFont.pointSize * 0.5];
      rubyLineHeight = [rubyFont lineHeightAsVerticalFont:isVertical];
      CFStringRef rubyText[kCTRubyPositionCount] = {(__bridge CFStringRef)rubyString, NULL, NULL, NULL};
      CTRubyAnnotationRef rubyAnnotation = CTRubyAnnotationCreate(kCTRubyAlignmentDistributeSpace,
                                                                  kCTRubyOverhangNone, 0.5, rubyText);
      [self addAttributes:@{NSFontAttributeName: baseFont,
                            NSVerticalGlyphFormAttributeName: @(isVertical)}
                    range:result.range];

      if (@available(macOS 12.0, *))  {
        [self deleteCharactersInRange:[result rangeAtIndex:3]];
      } else {  // use U+008B as placeholder for line-forward spaces in case ruby is wider than base
        NSSize baseSize = [self attributedSubstringFromRange:baseRange].size;
        CGFloat rubyWidth = [self attributedSubstringFromRange:[result rangeAtIndex:4]].size.width * 0.5;
        [self deleteCharactersInRange:[result rangeAtIndex:3]];
        [self replaceCharactersInRange:NSMakeRange(NSMaxRange(baseRange), 0)
                            withString:[NSString stringWithFormat:@"%C", 0x8B]];
        [self addAttribute:kControlCharacterSizeAttributeName
                     value:[NSValue valueWithSize:NSMakeSize(fdim(ceil(rubyWidth), floor(baseSize.width)), baseSize.height)]
                     range:NSMakeRange(NSMaxRange(baseRange), 1)];
      }
      [self addAttribute:(id)kCTRubyAnnotationAttributeName
                   value:CFBridgingRelease(rubyAnnotation)
                   range:baseRange];
      [self deleteCharactersInRange:[result rangeAtIndex:1]];
    }
  }];
  [self.mutableString replaceOccurrencesOfString:@"(.)?[\\x{FFF9}-\\x{FFFB}]"
                                      withString:@"$1"
                                         options:NSRegularExpressionSearch
                                           range:NSMakeRange(0, self.length)];
  return ceil(rubyLineHeight);
}

@end  // NSMutableAttributedString (NSMutableAttributedStringMarkDownFormatting)


__attribute__((objc_direct_members))
@implementation NSAttributedString (NSAttributedStringHorizontalInVerticalForms)

- (NSAttributedString*)attributedStringHorizontalInVerticalForms {
  NSMutableDictionary<NSAttributedStringKey, id>* attrs =
    [[self attributesAtIndex:0 effectiveRange:NULL] mutableCopy];
  NSFont* font = attrs[NSFontAttributeName];
  NSAttributedString* attrString =
    [NSAttributedString.alloc initWithString:self.string
                                  attributes:[self fontAttributesInRange:NSMakeRange(0, self.length)]];
  CGFloat stringWidth = ceil(attrString.size.width);
  CGFloat height = ceil(attrString.size.height);
  CGFloat width = fmax(height, stringWidth);
  NSImage* image = [NSImage imageWithSize:NSMakeSize(height, height) flipped:YES
                           drawingHandler:^BOOL(NSRect dstRect) {
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform* transform = NSAffineTransform.transform;
    [transform scaleXBy:1.0 yBy:height / width];
    [transform translateXBy:ceil(height * 0.5) yBy:ceil(width * 0.5)];
    [transform rotateByDegrees:-90.0];
    [transform concat];
    [attrString drawWithRect:NSMakeRect(-ceil(stringWidth * 0.5), -ceil(height * 0.5), stringWidth, height)
                     options:NSStringDrawingUsesLineFragmentOrigin];
    [NSGraphicsContext restoreGraphicsState];
    return YES;
  }];
  NSTextAttachment* attm = NSTextAttachment.alloc.init;
  attm.image = image;
  attm.bounds = NSMakeRect(0, ceil(font.descender), height, height);
  attrs[NSAttachmentAttributeName] = attm;
  return [NSAttributedString.alloc initWithString:
          [NSString stringWithCharacters:(unichar[]){NSAttachmentCharacter} length:1]
                                       attributes:attrs];
}

@end  // NSAttributedString (NSAttributedStringHorizontalInVerticalForms)


__attribute__((objc_direct_members))
@implementation NSColorSpace (labColorSpace)

+ (NSColorSpace*)labColorSpace {
  static NSColorSpace* labColorSpace;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    const CGFloat whitePoint[3] = {0.950489, 1.0, 1.088840};
    const CGFloat blackPoint[3] = {0.0, 0.0, 0.0};
    const CGFloat range[4] = {-127.0, 127.0, -127.0, 127.0};
    labColorSpace = [self.alloc initWithCGColorSpace:(CGColorSpaceRef)
                     CFAutorelease(CGColorSpaceCreateLab(whitePoint, blackPoint, range))];
  });
  return labColorSpace;
}

@end  // NSColorSpace (labColorSpace)


@implementation NSColor (semanticColors)

- (NSColor*)hooverColor {
  if (@available(macOS 10.14, *)) {
    return [self colorWithSystemEffect:NSColorSystemEffectRollover];
  } else {
    return [NSAppearance.currentAppearance.name isEqualToString:NSAppearanceNameVibrantDark] ?
            [self highlightWithLevel:0.3] : [self shadowWithLevel:0.3];
  }
}

- (NSColor*)disabledColor {
  if (@available(macOS 10.14, *)) {
    return [self colorWithSystemEffect:NSColorSystemEffectDisabled];
  } else {
    return [NSAppearance.currentAppearance.name isEqualToString:NSAppearanceNameVibrantDark] ?
            [self shadowWithLevel:0.3] : [self highlightWithLevel:0.3];
  }
}

@end  // NSColor (semanticColors)


@implementation NSColor (NSColorWithLabColorSpace)

+ (NSColor*)colorWithLabLStar:(CGFloat)lStar
                        aStar:(CGFloat)aStar
                        bStar:(CGFloat)bStar
                        alpha:(CGFloat)alpha {
  CGFloat components[4];
  components[0] = clamp(lStar, 0.0, 100.0); // luminance
  components[1] = clamp(aStar, -127.0, 127.0); // green-red
  components[2] = clamp(bStar, -127.0, 127.0); // blue-yellow
  components[3] = clamp(alpha, 0.0, 1.0);
  return [self colorWithColorSpace:NSColorSpace.labColorSpace
                        components:components count:4];
}

- (void)getLStar:(CGFloat*)lStar
           aStar:(CGFloat*)aStar
           bStar:(CGFloat*)bStar
           alpha:(CGFloat*)alpha {
  static CGFloat components[4] = {0.0, 0.0, 0.0, 1.0};
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [[[self colorUsingType:NSColorTypeComponentBased]
      colorUsingColorSpace:NSColorSpace.labColorSpace]
     getComponents:components];
    components[0] /= 100.0;
    components[1] /= 127.0;
    components[2] /= 127.0;
  });
  if (lStar != NULL) *lStar = components[0];
  if (aStar != NULL) *aStar = components[1];
  if (bStar != NULL) *bStar = components[2];
  if (alpha != NULL) *alpha = components[3];
}

- (CGFloat)lStarComponent {
  CGFloat lStarComponent;
  [self getLStar:&lStarComponent aStar:NULL bStar:NULL alpha:NULL];
  return lStarComponent;
}

- (CGFloat)aStarComponent {
  CGFloat aStarComponent;
  [self getLStar:NULL aStar:&aStarComponent bStar:NULL alpha:NULL];
  return aStarComponent;
}

- (CGFloat)bStarComponent {
  CGFloat bStarComponent;
  [self getLStar:NULL aStar:NULL bStar:&bStarComponent alpha:NULL];
  return bStarComponent;
}

- (NSColor*)colorByInvertingLuminanceToExtent:(ColorInversionExtent)extent {
  if (NSColor* componentBased = [self colorUsingType:NSColorTypeComponentBased]) {
    CGFloat components[4] = {0.0, 0.0, 0.0, 1.0};
    [[componentBased colorUsingColorSpace:NSColorSpace.labColorSpace] getComponents:components];
    switch (extent) {
      case kAugmentedColorInversion:
        components[0] = 100.0 - components[0];
        break;
      case kModerateColorInversion:
        components[0] = 80.0 - components[0] * 0.6;
        break;
      case kStandardColorInversion:
        components[0] = 90.0 - components[0] * 0.8;
        break;
    }
    NSColor* invertedColor = [NSColor colorWithColorSpace:NSColorSpace.labColorSpace
                                               components:components count:4];
    return [invertedColor colorUsingColorSpace:componentBased.colorSpace];
  }
  return self;
}

@end  // NSColor (colorWithLabColorSpace)


#pragma mark - Color scheme and other user configurations

@implementation SquirrelTheme

static inline NSColor* blendColors(NSColor* foregroundColor, NSColor* backgroundColor) {
  return [[foregroundColor blendedColorWithFraction:kBlendedBackgroundColorFraction
                                            ofColor:backgroundColor ? : NSColor.lightGrayColor]
          colorWithAlphaComponent:foregroundColor.alphaComponent];
}

static SquirrelTheme* _lightTheme =
  [SquirrelTheme.alloc initWithStyle:kLightStyle];
static SquirrelTheme* _darkTheme API_AVAILABLE(macos(10.14)) =
  [SquirrelTheme.alloc initWithStyle:kDarkStyle];
static SquirrelStyle _currentStyle = kLightStyle;

+ (SquirrelTheme*)lightTheme { return _lightTheme; }
+ (SquirrelTheme*)darkTheme API_AVAILABLE(macos(10.14)) { return _darkTheme; }
+ (SquirrelTheme *)currentTheme {
  if (@available(macOS 10.14, *)) {
    if (_currentStyle == kDarkStyle)
      return _darkTheme;
  }
  return _lightTheme;
}
+ (void)setCurrentStyle:(SquirrelStyle)currentStyle { _currentStyle = currentStyle; }
+ (SquirrelStyle)currentStyle { return _currentStyle; }

- (instancetype)initWithStyle:(SquirrelStyle)style {
  if (self = [super init]) {
    _style = style;
    _selectKeys = @"12345";
    _rawLabels = @[@"１", @"２", @"３", @"４", @"５"];
    _pageSize = 5UL;
    _rawCandidateFormat = kDefaultCandidateFormat;
    _scriptVariant = @"zh";

    NSMutableParagraphStyle* candidateParagraphStyle = NSMutableParagraphStyle.alloc.init;
    candidateParagraphStyle.alignment = NSTextAlignmentLeft;
    candidateParagraphStyle.lineBreakStrategy = NSLineBreakStrategyNone;
    // Use left-to-right marks to declare the default writing direction and prevent strong right-to-left
    // characters from setting the writing direction in case the label are direction-less symbols
    candidateParagraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
    NSMutableParagraphStyle* preeditParagraphStyle = candidateParagraphStyle.mutableCopy;
    NSMutableParagraphStyle* pagingParagraphStyle = candidateParagraphStyle.mutableCopy;
    NSMutableParagraphStyle* statusParagraphStyle = candidateParagraphStyle.mutableCopy;
    candidateParagraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    preeditParagraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    statusParagraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSFontDescriptor* userFontDesc = [NSFontDescriptor createWithFullname:
                                      [NSFont userFontOfSize:0.0].fontName];
    NSFontDescriptor* monoFontDesc = [NSFontDescriptor createWithFullname:
                                      [NSFont userFixedPitchFontOfSize:0.0].fontName];
    NSFont* userFont = [NSFont fontWithDescriptor:userFontDesc size:kDefaultFontSize];
    NSFont* userMonoFont = [NSFont fontWithDescriptor:monoFontDesc size:kDefaultFontSize];
    NSFont* monoDigitFont = [NSFont monospacedDigitSystemFontOfSize:kDefaultFontSize
                                                             weight:NSFontWeightRegular];

    NSMutableDictionary<NSAttributedStringKey, id>* textAttrs = NSMutableDictionary.alloc.init;
    textAttrs[NSForegroundColorAttributeName] = NSColor.controlTextColor;
    textAttrs[NSFontAttributeName] = userFont;
    textAttrs[NSKernAttributeName] = @0;
    // Use left-to-right embedding to prevent right-to-left text from changing the layout of the candidate.
    textAttrs[NSWritingDirectionAttributeName] = @[@0];
    textAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;

    NSMutableDictionary<NSAttributedStringKey, id>* labelAttrs = textAttrs.mutableCopy;
    labelAttrs[NSForegroundColorAttributeName] = NSColor.secondaryLabelColor;
    labelAttrs[NSFontAttributeName] = userMonoFont;
    labelAttrs[NSKernAttributeName] = @0;
    labelAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;

    NSMutableDictionary<NSAttributedStringKey, id>* commentAttrs = NSMutableDictionary.alloc.init;
    commentAttrs[NSForegroundColorAttributeName] = NSColor.secondaryLabelColor;
    commentAttrs[NSFontAttributeName] = userFont;
    commentAttrs[NSKernAttributeName] = @0;
    commentAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;

    NSMutableDictionary<NSAttributedStringKey, id>* preeditAttrs = NSMutableDictionary.alloc.init;
    preeditAttrs[NSForegroundColorAttributeName] = NSColor.textColor;
    preeditAttrs[NSFontAttributeName] = userFont;
    preeditAttrs[NSLigatureAttributeName] = @0;
    preeditAttrs[NSParagraphStyleAttributeName] = preeditParagraphStyle;

    NSMutableDictionary<NSAttributedStringKey, id>* pagingAttrs = NSMutableDictionary.alloc.init;
    pagingAttrs[NSFontAttributeName] = monoDigitFont;
    pagingAttrs[NSForegroundColorAttributeName] = NSColor.textColor;
    pagingAttrs[NSParagraphStyleAttributeName] = pagingParagraphStyle;

    NSMutableDictionary<NSAttributedStringKey, id>* statusAttrs = commentAttrs.mutableCopy;
    statusAttrs[NSParagraphStyleAttributeName] = statusParagraphStyle;

    _textAttrs = textAttrs;
    _labelAttrs = labelAttrs;
    _commentAttrs = commentAttrs;
    _preeditAttrs = preeditAttrs;
    _pagingAttrs = pagingAttrs;
    _statusAttrs = statusAttrs;
    _candidateParagraphStyle = candidateParagraphStyle;
    _preeditParagraphStyle = preeditParagraphStyle;
    _pagingParagraphStyle = pagingParagraphStyle;
    _statusParagraphStyle = statusParagraphStyle;

    _backColor = NSColor.controlBackgroundColor;
    _preeditForeColor = NSColor.textColor;
    _textForeColor = NSColor.controlTextColor;
    _commentForeColor = NSColor.secondaryLabelColor;
    _labelForeColor = NSColor.secondaryLabelColor;
    _hilitedPreeditForeColor = NSColor.selectedTextColor;
    _hilitedTextForeColor = NSColor.selectedMenuItemTextColor;
    _hilitedCommentForeColor = NSColor.alternateSelectedControlTextColor;
    _hilitedLabelForeColor = NSColor.alternateSelectedControlTextColor;

    CGGlyph glyphs[1];
    CTFontGetGlyphsForCharacters((__bridge CTFontRef)userFont, (unichar[1]){0x3000}, glyphs, 1);
    _fullWidth = ceil([kFullWidthSpace sizeWithAttributes:@{NSFontAttributeName: userFont}].width);
    [self updateCandidatetemplates];
    [self updateSeperatorAndSymbolAttrs];
  }
  return self;
}

- (instancetype)init {
  return [self initWithStyle:kDefaultStyle];
}

- (void)updateSeperatorAndSymbolAttrs {
  NSMutableDictionary<NSAttributedStringKey, id>* sepAttrs = _commentAttrs.mutableCopy;
  sepAttrs[NSVerticalGlyphFormAttributeName] = @NO;
  _separator = [NSAttributedString.alloc initWithString:
                _linear ? (_tabular ? @"\u3000\t\x1D" : @"\u3000\x1D") : @"\n"
                                             attributes:sepAttrs];
  // Symbols for function buttons
  NSString* attmCharacter = [NSString stringWithCharacters:
                             (unichar[1]){NSAttachmentCharacter} length:1];

  NSTextAttachment* attmDeleteFill = NSTextAttachment.alloc.init;
  attmDeleteFill.image = [NSImage imageNamed:@"Symbols/delete.backward.fill"];
  NSMutableDictionary<NSAttributedStringKey, id>* attrsDeleteFill = _preeditAttrs.mutableCopy;
  attrsDeleteFill[NSAttachmentAttributeName] = attmDeleteFill;
  attrsDeleteFill[NSVerticalGlyphFormAttributeName] = @NO;
  _symbolDeleteFill = [NSAttributedString.alloc initWithString:attmCharacter
                                                    attributes:attrsDeleteFill];

  NSTextAttachment* attmDeleteStroke = NSTextAttachment.alloc.init;
  attmDeleteStroke.image = [NSImage imageNamed:@"Symbols/delete.backward"];
  NSMutableDictionary<NSAttributedStringKey, id>* attrsDeleteStroke = _preeditAttrs.mutableCopy;
  attrsDeleteStroke[NSAttachmentAttributeName] = attmDeleteStroke;
  attrsDeleteStroke[NSVerticalGlyphFormAttributeName] = @NO;
  _symbolDeleteStroke = [NSAttributedString.alloc initWithString:attmCharacter
                                                      attributes:attrsDeleteStroke];
  if (_tabular) {
    NSTextAttachment* attmCompress = NSTextAttachment.alloc.init;
    attmCompress.image = [NSImage imageNamed:@"Symbols/rectangle.compress.vertical"];
    NSMutableDictionary<NSAttributedStringKey, id>* attrsCompress = _pagingAttrs.mutableCopy;
    attrsCompress[NSAttachmentAttributeName] = attmCompress;
    _symbolCompress = [NSAttributedString.alloc initWithString:attmCharacter
                                                    attributes:attrsCompress];

    NSTextAttachment* attmExpand = NSTextAttachment.alloc.init;
    attmExpand.image = [NSImage imageNamed:@"Symbols/rectangle.expand.vertical"];
    NSMutableDictionary<NSAttributedStringKey, id>* attrsExpand = _pagingAttrs.mutableCopy;
    attrsExpand[NSAttachmentAttributeName] = attmExpand;
    _symbolExpand = [NSAttributedString.alloc initWithString:attmCharacter
                                                  attributes:attrsExpand];

    NSTextAttachment* attmLock = NSTextAttachment.alloc.init;
    attmLock.image = [NSImage imageNamed:[NSString stringWithFormat:
                      @"Symbols/lock%@.fill", _vertical ? @".vertical" : @""]];
    NSMutableDictionary<NSAttributedStringKey, id>* attrsLock = _pagingAttrs.mutableCopy;
    attrsLock[NSAttachmentAttributeName] = attmLock;
    _symbolLock = [NSAttributedString.alloc initWithString:attmCharacter
                                                attributes:attrsLock];
  } else {
    _symbolCompress = nil;
    _symbolExpand = nil;
    _symbolLock = nil;
  }
  if (_showPaging) {
    NSTextAttachment* attmBackFill = NSTextAttachment.alloc.init;
    attmBackFill.image = [NSImage imageNamed:[NSString stringWithFormat:
                          @"Symbols/chevron.%@.circle.fill", _linear ? @"up" : @"left"]];
    NSMutableDictionary<NSAttributedStringKey, id>* attrsBackFill = _pagingAttrs.mutableCopy;
    attrsBackFill[NSAttachmentAttributeName] = attmBackFill;
    _symbolBackFill = [NSAttributedString.alloc initWithString:attmCharacter
                                                    attributes:attrsBackFill];

    NSTextAttachment* attmBackStroke = NSTextAttachment.alloc.init;
    attmBackStroke.image = [NSImage imageNamed:[NSString stringWithFormat:
                            @"Symbols/chevron.%@.circle", _linear ? @"up" : @"left"]];
    NSMutableDictionary<NSAttributedStringKey, id>* attrsBackStroke = _pagingAttrs.mutableCopy;
    attrsBackStroke[NSAttachmentAttributeName] = attmBackStroke;
    _symbolBackStroke = [NSAttributedString.alloc initWithString:attmCharacter
                                                      attributes:attrsBackStroke];

    NSTextAttachment* attmForwardFill = NSTextAttachment.alloc.init;
    attmForwardFill.image = [NSImage imageNamed:[NSString stringWithFormat:
                             @"Symbols/chevron.%@.circle.fill", _linear ? @"down" : @"right"]];
    NSMutableDictionary<NSAttributedStringKey, id>* attrsForwardFill = _pagingAttrs.mutableCopy;
    attrsForwardFill[NSAttachmentAttributeName] = attmForwardFill;
    _symbolForwardFill = [NSAttributedString.alloc initWithString:attmCharacter
                                                       attributes:attrsForwardFill];

    NSTextAttachment* attmForwardStroke = NSTextAttachment.alloc.init;
    attmForwardStroke.image = [NSImage imageNamed:[NSString stringWithFormat:
                               @"Symbols/chevron.%@.circle", _linear ? @"down" : @"right"]];
    NSMutableDictionary<NSAttributedStringKey, id>* attrsForwardStroke = _pagingAttrs.mutableCopy;
    attrsForwardStroke[NSAttachmentAttributeName] = attmForwardStroke;
    _symbolForwardStroke = [NSAttributedString.alloc initWithString:attmCharacter
                                                         attributes:attrsForwardStroke];
  } else {
    _symbolBackFill = nil;
    _symbolBackStroke = nil;
    _symbolForwardFill = nil;
    _symbolForwardStroke = nil;
  }
}

- (void)updateLabelsWithConfig:(SquirrelConfig*)config
                  directUpdate:(BOOL)update {
  NSUInteger menuSize = (NSUInteger)[config intValueForOption:@"menu/page_size"] ? : 5;
  NSString* selectKeys = [([config stringForOption:@"menu/alternative_select_keys"] ? : @"1234567890") substringToIndex:menuSize];
  NSArray<NSString*>* selectLabels = [config listForOption:@"menu/alternative_select_labels"];
  NSMutableArray<NSString*>* rawLabels = [NSMutableArray.alloc initWithCapacity:menuSize];
  if (selectLabels == nil) {
    NSString* labelString = [selectKeys.uppercaseString
                             stringByApplyingTransform:NSStringTransformFullwidthToHalfwidth
                             reverse:YES];
    for (NSUInteger i = 0; i < menuSize; ++i) {
      rawLabels[i] = [labelString substringWithRange:NSMakeRange(i, 1)];
    }
  } else {
    for (NSUInteger i = 0; i < menuSize; ++i) {
      rawLabels[i] = selectLabels[i];
    }
  }
  [self updateSelectKeys:selectKeys labels:rawLabels directUpdate:update];
}

- (void)updateSelectKeys:(NSString*)selectKeys
                  labels:(NSArray<NSString*>*)rawLabels
            directUpdate:(BOOL)update {
  if ([_selectKeys isEqualToString:selectKeys] && [_rawLabels isEqualToArray:rawLabels])
    return;

  _selectKeys = selectKeys;
  _rawLabels = rawLabels;
  _pageSize = rawLabels.count;
  _labels = nil;

  if (update)
    [self updateCandidatetemplates];
}

- (void)updateCandidateFormat:(NSString*)rawCandidateFormat {
  if (![_rawCandidateFormat isEqualToString:rawCandidateFormat]) {
    _rawCandidateFormat = rawCandidateFormat;
    _candidateFormat = nil;
  }
  [self updateCandidatetemplates];
  [self updateSeperatorAndSymbolAttrs];
}

- (void)updateCandidatetemplates {
  if (_candidateFormat.length == 0 || _labels.count == 0) {
    // validate candidate format: must have enumerator '%c' before candidate '%@'
    NSMutableString* candidateFormat = _rawCandidateFormat.mutableCopy;
    NSRange textRange = [candidateFormat rangeOfString:@"%@" options:NSLiteralSearch];
    if (textRange.length == 0)
      [candidateFormat appendString:@"%@"];
    NSRange labelRange = [candidateFormat rangeOfString:@"%c" options:NSLiteralSearch];
    if (labelRange.length == 0) {
      [candidateFormat insertString:@"%c" atIndex:0];
      labelRange = [candidateFormat rangeOfString:@"%c" options:NSLiteralSearch];
    }
    textRange = [candidateFormat rangeOfString:@"%@" options:NSLiteralSearch];
    if (labelRange.location > textRange.location)
      candidateFormat.string = kDefaultCandidateFormat;
    textRange = [candidateFormat rangeOfString:@"(\\x{FFF9})?%@" options:NSRegularExpressionSearch];
    NSRange commentRange = NSMakeRange(NSMaxRange(textRange), candidateFormat.length - NSMaxRange(textRange));
    if (commentRange.length == 0 || ![[candidateFormat substringWithRange:commentRange] containsString:@"%s"])
      [candidateFormat insertString:@"%s" atIndex:commentRange.location];
    if (!_linear)
      [candidateFormat insertString:@"\t" atIndex:textRange.location];
    _candidateFormat = candidateFormat;

    NSMutableArray<NSString*>* labels = _rawLabels.mutableCopy;
    NSRange enumRange = NSMakeRange(0, 0);
    NSCharacterSet* labelCharacters = [NSCharacterSet characterSetWithCharactersInString:
                                       [labels componentsJoinedByString:@""]];
    if ([NSCharacterSet.fullWidthDigitCharacterSet isSupersetOfSet:labelCharacters]) {  // ０１..９
      if ((enumRange = [candidateFormat rangeOfString:@"%c\u20E3"
                        options:NSLiteralSearch]).length > 0) {  // 1︎⃣...9︎⃣0︎⃣
        for (NSUInteger i = 0; i < labels.count; ++i)
          labels[i] = [NSString stringWithFormat:@"%C\uFE0E\u20E3",
                       (unichar)([labels[i] characterAtIndex:0] - 0xFF10 + 0x0030)];
      } else if ((enumRange = [candidateFormat rangeOfString:@"%c\u20DD"
                               options:NSLiteralSearch]).length > 0) {  // ①...⑨⓪
        for (NSUInteger i = 0; i < labels.count; ++i)
          labels[i] = [NSString stringWithFormat:@"%C",
                       (unichar)([labels[i] characterAtIndex:0] == 0xFF10 ? 0x24EA :
                                 [labels[i] characterAtIndex:0] - 0xFF11 + 0x2460)];
      } else if ((enumRange = [candidateFormat rangeOfString:@"(%c)"
                               options:NSLiteralSearch]).length > 0) {  // ⑴...⑼⑽
        for (NSUInteger i = 0; i < labels.count; ++i)
          labels[i] = [NSString stringWithFormat:@"%C",
                       (unichar)([labels[i] characterAtIndex:0] == 0xFF10 ? 0x247D :
                                 [labels[i] characterAtIndex:0] - 0xFF11 + 0x2474)];
      } else if ((enumRange = [candidateFormat rangeOfString:@"%c."
                               options:NSLiteralSearch]).length > 0) {  // ⒈...⒐🄀
        for (NSUInteger i = 0; i < labels.count; ++i)
          labels[i] = [labels[i] characterAtIndex:0] == 0xFF10 ? @"\U0001F100" :
                      [NSString stringWithFormat:@"%C", (unichar)([labels[i] characterAtIndex:0] - 0xFF11 + 0x2488)];
      } else if ((enumRange = [candidateFormat rangeOfString:@"%c,"
                               options:NSLiteralSearch]).length > 0) {  // 🄂...🄊🄁
        for (NSUInteger i = 0; i < labels.count; ++i)
          labels[i] = [NSString stringWithFormat:@"%S",
                       (const unichar[2]){0xD83C, (unichar)([labels[i] characterAtIndex:0] - 0xFF10 + 0xDD01)}];
      }
    } else if ([NSCharacterSet.fullWidthLatinCapitalCharacterSet isSupersetOfSet:labelCharacters]) {  // Ａ..Ｚ
      if ((enumRange = [candidateFormat rangeOfString:@"%c\u20DD"
                        options:NSLiteralSearch]).length > 0) {  // Ⓐ...Ⓩ
        for (NSUInteger i = 0; i < labels.count; ++i)
          labels[i] = [NSString stringWithFormat:@"%C",
                       (unichar)([labels[i] characterAtIndex:0] - 0xFF21 + 0x24B6)];
      } else if ((enumRange = [candidateFormat rangeOfString:@"(%c)"
                               options:NSLiteralSearch]).length > 0) {  // 🄐...🄩
        for (NSUInteger i = 0; i < labels.count; ++i)
          labels[i] = [NSString stringWithFormat:@"%S",
                       (const unichar[2]){0xD83C, (unichar)([labels[i] characterAtIndex:0] - 0xFF21 + 0xDD10)}];
      } else if ((enumRange = [candidateFormat rangeOfString:@"%c\u20DE"
                               options:NSLiteralSearch]).length > 0) {  // 🄰...🅉
        for (NSUInteger i = 0; i < labels.count; ++i)
          labels[i] = [NSString stringWithFormat:@"%S",
                       (const unichar[2]){0xD83C, (unichar)([labels[i] characterAtIndex:0] - 0xFF21 + 0xDD30)}];
      }
    }
    if (enumRange.length > 0)
      [candidateFormat replaceCharactersInRange:enumRange withString:@"%c"];
    _labels = labels;
  }

  // make sure label font can render all label strings
  NSMutableDictionary<NSAttributedStringKey, id>* textAttrs = _textAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* commentAttrs = _commentAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* labelAttrs = _labelAttrs.mutableCopy;
  NSString* labelString = [_rawLabels componentsJoinedByString:@""];
  NSFont* labelFont = labelAttrs[NSFontAttributeName];
  NSFont* substituteFont = CFBridgingRelease(CTFontCreateForString((CTFontRef)labelFont,
                            (CFStringRef)labelString, CFRangeMake(0, (CFIndex)labelString.length)));
  if ([substituteFont isNotEqualTo:labelFont])
    labelAttrs[NSFontAttributeName] = CFBridgingRelease(CTFontCreateForString((CTFontRef)substituteFont,
                                        (CFStringRef)labelString, CFRangeMake(0, (CFIndex)labelString.length)));

  // parse markdown formats
  NSMutableAttributedString* candidateTemplate = [NSMutableAttributedString.alloc initWithString:_candidateFormat];
  NSRange textRange = [candidateTemplate.mutableString rangeOfString:@"(\\x{FFF9})?%@" options:NSRegularExpressionSearch];
  NSRange labelRange = NSMakeRange(0, textRange.location);
  NSRange commentRange = NSMakeRange(NSMaxRange(textRange), candidateTemplate.length - NSMaxRange(textRange));
  [candidateTemplate setAttributes:labelAttrs range:labelRange];
  [candidateTemplate setAttributes:textAttrs range:textRange];
  [candidateTemplate setAttributes:commentAttrs range:commentRange];
  [candidateTemplate formatMarkDown];
  textRange = [candidateTemplate.mutableString rangeOfString:@"(\\x{FFF9})?%@" options:NSRegularExpressionSearch];
  labelRange = NSMakeRange(0, textRange.location);
  commentRange = NSMakeRange(NSMaxRange(textRange), candidateTemplate.length - NSMaxRange(textRange));

  // for stacked layout, calculate head indent
  NSMutableParagraphStyle* candidateParagraphStyle = _candidateParagraphStyle.mutableCopy;
  if (!_linear) {
    NSRange enumRange = [candidateTemplate.mutableString rangeOfString:@"%c" options:NSLiteralSearch];
    NSTextStorage* textStorage = NSTextStorage.alloc.init;
    SquirrelTextView* textView = [SquirrelTextView.alloc initWithContentBlock:kStackedCandidateBlock storage:textStorage];
    textView.layoutOrientation = _vertical ? NSTextLayoutOrientationVertical : NSTextLayoutOrientationHorizontal;
    for (NSString* label in _labels) {
      NSMutableAttributedString* labelString = [candidateTemplate attributedSubstringFromRange:NSMakeRange(0, labelRange.length - 1)].mutableCopy;
      [labelString replaceCharactersInRange:enumRange withString:label];
      [textStorage appendAttributedString:labelString];
      [textStorage appendAttributedString:[NSAttributedString.alloc initWithString:@"\n"]];
    }
    CGFloat indent = floor(NSMaxX(textView.layoutText)) + 1.0;
    candidateParagraphStyle.tabStops = @[[NSTextTab.alloc initWithTextAlignment:NSTextAlignmentLeft
                                                                       location:indent
                                                                        options:@{}]];
    candidateParagraphStyle.headIndent = indent;
    _candidateParagraphStyle = candidateParagraphStyle;
    _truncatedParagraphStyle = nil;
  } else {
    candidateParagraphStyle.tabStops = @[];
    candidateParagraphStyle.headIndent = 0.0;
    _candidateParagraphStyle = candidateParagraphStyle;
    NSMutableParagraphStyle* truncatedParagraphStyle = candidateParagraphStyle.mutableCopy;
    truncatedParagraphStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    truncatedParagraphStyle.tighteningFactorForTruncation = 0.0;
    _truncatedParagraphStyle = truncatedParagraphStyle;
  }

  textAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;
  commentAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;
  labelAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;
  _textAttrs = textAttrs;
  _commentAttrs = commentAttrs;
  _labelAttrs = labelAttrs;

  [candidateTemplate addAttribute:NSParagraphStyleAttributeName
                            value:candidateParagraphStyle
                            range:NSMakeRange(0, candidateTemplate.length)];
  _candidateTemplate = candidateTemplate;

  NSMutableAttributedString* candidateHilitedTemplate = candidateTemplate.mutableCopy;
  [candidateHilitedTemplate addAttribute:NSForegroundColorAttributeName
                                   value:_hilitedLabelForeColor
                                   range:labelRange];
  [candidateHilitedTemplate addAttribute:NSForegroundColorAttributeName
                                   value:_hilitedTextForeColor
                                   range:textRange];
  [candidateHilitedTemplate addAttribute:NSForegroundColorAttributeName
                                   value:_hilitedCommentForeColor
                                   range:commentRange];
  _candidateHilitedTemplate = candidateHilitedTemplate;

  if (_tabular) {
    NSMutableAttributedString* candidateDimmedTemplate = candidateTemplate.mutableCopy;
    [candidateDimmedTemplate addAttribute:NSForegroundColorAttributeName
                                    value:_dimmedLabelForeColor
                                    range:labelRange];
    _candidateDimmedTemplate = candidateDimmedTemplate;
  } else {
    _candidateDimmedTemplate = nil;
  }
}

- (void)updateStatusMessageType:(NSString*)type {
  if ([@"long" caseInsensitiveCompare:type] == NSOrderedSame)
    _statusMessageType = kStatusMessageTypeLong;
  else if ([@"short" caseInsensitiveCompare:type] == NSOrderedSame)
    _statusMessageType = kStatusMessageTypeShort;
  else
    _statusMessageType = kStatusMessageTypeMixed;
}

static void updateCandidateListLayout(BOOL* isLinear, BOOL* isTabular,
                                      SquirrelConfig* config, NSString* prefix) {
  NSString* candidateListLayout = [config stringForOption:[prefix append:@"/candidate_list_layout"]];
  if ([@"stacked" caseInsensitiveCompare:candidateListLayout] == NSOrderedSame) {
    *isLinear = NO;
    *isTabular = NO;
  } else if ([@"linear" caseInsensitiveCompare:candidateListLayout] == NSOrderedSame) {
    *isLinear = YES;
    *isTabular = NO;
  } else if ([@"tabular" caseInsensitiveCompare:candidateListLayout] == NSOrderedSame) {
    // `tabular` is a derived layout of `linear`; tabular implies linear
    *isLinear = YES;
    *isTabular = YES;
  } else if (NSNumber* horizontal = [config nullableBoolForOption:[prefix append:@"/horizontal"]]) {
    // Deprecated. Not to be confused with text_orientation: horizontal
    *isLinear = horizontal.boolValue;
    *isTabular = NO;
  }
}

static void updateTextOrientation(BOOL* isVertical, SquirrelConfig* config, NSString* prefix) {
  NSString* textOrientation = [config stringForOption:[prefix append:@"/text_orientation"]];
  if ([@"horizontal" caseInsensitiveCompare:textOrientation] == NSOrderedSame)
    *isVertical = NO;
  else if ([@"vertical" caseInsensitiveCompare:textOrientation] == NSOrderedSame)
    *isVertical = YES;
  else if (NSNumber* vertical = [config nullableBoolForOption:[prefix append:@"/vertical"]])
    *isVertical = vertical.boolValue;
}

// functions for post-retrieve processing
static inline double positive(double param) { return param > 0.0 ? param : 0.0; }
static inline double pos_round(double param) { return param > 0.0 ? round(param) : 0.0; }
static inline double pos_ceil(double param) { return param > 0.0 ? ceil(param) : 0.0; }
static inline double clamp_uni(double param) { return param > 0.0 ? (param < 1.0 ? param : 1.0) : 0.0; }

template <typename T> static inline void update(T* __strong* existing, T* newValue) {
  if (newValue != nil)
    *existing = newValue;
}

static NSArray<NSDictionary<NSFontDescriptorFeatureKey, NSNumber*>*>* monoDigitFeatures =
  @[@{NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
      NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)},
    @{NSFontFeatureTypeIdentifierKey: @(kTextSpacingType),
      NSFontFeatureSelectorIdentifierKey: @(kHalfWidthTextSelector)}];

- (void)updateWithConfig:(SquirrelConfig*)config
            styleOptions:(NSSet<NSString*>*)styleOptions
           scriptVariant:(NSString*)scriptVariant {
  /* INTERFACE */
  BOOL linear = NO;
  BOOL tabular = NO;
  BOOL vertical = NO;
  updateCandidateListLayout(&linear, &tabular, config, @"style");
  updateTextOrientation(&vertical, config, @"style");
  NSNumber* inlinePreedit = [config nullableBoolForOption:@"style/inline_preedit"];
  NSNumber* inlineCandidate = [config nullableBoolForOption:@"style/inline_candidate"];
  NSNumber* showPaging = [config nullableBoolForOption:@"style/show_paging"];
  NSNumber* rememberSize = [config nullableBoolForOption:@"style/remember_size" alias:@"memorize_size"];
  NSString* statusMessageType = [config stringForOption:@"style/status_message_type"];
  NSString* rawCandidateFormat = [config stringForOption:@"style/candidate_format"];
  /* TYPOGRAPHY */
  NSString* fontName = [config stringForOption:@"style/font_face"];
  NSNumber* fontSize = [config nullableDoubleForOption:@"style/font_point" constraint:pos_round];
  NSString* labelFontName = [config stringForOption:@"style/label_font_face"];
  NSNumber* labelFontSize = [config nullableDoubleForOption:@"style/label_font_point" constraint:pos_round];
  NSString* commentFontName = [config stringForOption:@"style/comment_font_face"];
  NSNumber* commentFontSize = [config nullableDoubleForOption:@"style/comment_font_point" constraint:pos_round];
  NSNumber* opacity = [config nullableDoubleForOption:@"style/opacity" alias:@"alpha" constraint:clamp_uni];
  NSNumber* translucency = [config nullableDoubleForOption:@"style/translucency" constraint:clamp_uni];
  NSNumber* stackColors = [config nullableBoolForOption:@"style/stack_colors" alias:@"mutual_exclusive"];
  NSNumber* cornerRadius = [config nullableDoubleForOption:@"style/corner_radius" constraint:positive];
  NSNumber* hilitedCornerRadius = [config nullableDoubleForOption:@"style/hilited_corner_radius" constraint:positive];
  NSNumber* borderHeight = [config nullableDoubleForOption:@"style/border_height" constraint:pos_ceil];
  NSNumber* borderWidth = [config nullableDoubleForOption:@"style/border_width" constraint:pos_ceil];
  NSNumber* lineSpacing = [config nullableDoubleForOption:@"style/line_spacing" constraint:pos_round];
  NSNumber* spacing = [config nullableDoubleForOption:@"style/spacing" constraint:pos_round];
  NSNumber* baseOffset = [config nullableDoubleForOption:@"style/base_offset"];
  NSNumber* lineLength = [config nullableDoubleForOption:@"style/line_length"];
  NSNumber* shadowSize = [config nullableDoubleForOption:@"style/shadow_size" constraint:positive];
  /* CHROMATICS */
  NSColor* backColor;
  NSColor* borderColor;
  NSColor* preeditBackColor;
  NSColor* preeditForeColor;
  NSColor* candidateBackColor;
  NSColor* textForeColor;
  NSColor* commentForeColor;
  NSColor* labelForeColor;
  NSColor* hilitedPreeditBackColor;
  NSColor* hilitedPreeditForeColor;
  NSColor* hilitedCandidateBackColor;
  NSColor* hilitedTextForeColor;
  NSColor* hilitedCommentForeColor;
  NSColor* hilitedLabelForeColor;
  NSImage* backImage;

  NSString* colorScheme;
  if (_style == kDarkStyle) {
    for (NSString* option in styleOptions) {
      if ((colorScheme = [config stringForOption:
                          [NSString stringWithFormat:@"style/%@/color_scheme_dark", option]]) != nil)
        break;
    }
    colorScheme = colorScheme ? : [config stringForOption:@"style/color_scheme_dark"];
  }
  if (colorScheme == nil) {
    for (NSString* option in styleOptions) {
      if ((colorScheme = [config stringForOption:
                          [NSString stringWithFormat:@"style/%@/color_scheme", option]]) != nil)
        break;
    }
    colorScheme = colorScheme ? : [config stringForOption:@"style/color_scheme"];
  }
  BOOL isNative = !colorScheme || [@"native" caseInsensitiveCompare:colorScheme] == NSOrderedSame;
  NSArray<NSString*>* configPrefixes = [@"style/" stringsByAppendingPaths:styleOptions.allObjects];
  if (!isNative)
    configPrefixes = [[NSArray arrayWithObject:[@"preset_color_schemes/" append:colorScheme]]
                      arrayByAddingObjectsFromArray:configPrefixes];

  // get color scheme and then check possible overrides from styleSwitcher
  for (NSString* prefix in configPrefixes) {
    /* CHROMATICS override */
    if (NSString* colorSpace = [config stringForOption:[prefix append:@"/color_space"]])
      config.colorSpace = colorSpace;
    update(&backColor, [config colorForOption:[prefix append:@"/back_color"]]);
    update(&borderColor, [config colorForOption:[prefix append:@"/border_color"]]);
    update(&preeditBackColor, [config colorForOption:[prefix append:@"/preedit_back_color"]]);
    update(&preeditForeColor, [config colorForOption:[prefix append:@"/text_color"]]);
    update(&candidateBackColor, [config colorForOption:[prefix append:@"/candidate_back_color"]]);
    update(&textForeColor, [config colorForOption:[prefix append:@"/candidate_text_color"]]);
    update(&commentForeColor, [config colorForOption:[prefix append:@"/comment_text_color"]]);
    update(&labelForeColor, [config colorForOption:[prefix append:@"/label_color"]]);
    update(&hilitedPreeditBackColor, [config colorForOption:[prefix append:@"/hilited_back_color"]]);
    update(&hilitedPreeditForeColor, [config colorForOption:[prefix append:@"/hilited_text_color"]]);
    update(&hilitedCandidateBackColor, [config colorForOption:[prefix append:@"/hilited_candidate_back_color"]]);
    update(&hilitedTextForeColor, [config colorForOption:[prefix append:@"/hilited_candidate_text_color"]]);
    update(&hilitedCommentForeColor, [config colorForOption:[prefix append:@"/hilited_comment_text_color"]]);
    // for backward compatibility, 'label_hilited_color' and 'hilited_candidate_label_color' are both valid
    update(&hilitedLabelForeColor, [config colorForOption:[prefix append:@"/label_hilited_color"] alias:@"hilited_candidate_label_color"]);
    update(&backImage, [config imageForOption:[prefix append:@"/back_image"]]);

    // the following per-color-scheme configurations, if exist, will
    // override configurations with the same name under the global 'style' section
    /* INTERFACE override */
    updateCandidateListLayout(&linear, &tabular, config, prefix);
    updateTextOrientation(&vertical, config, prefix);
    update(&inlinePreedit, [config nullableBoolForOption:[prefix append:@"/inline_preedit"]]);
    update(&inlineCandidate, [config nullableBoolForOption:[prefix append:@"/inline_candidate"]]);
    update(&showPaging, [config nullableBoolForOption:[prefix append:@"/show_paging"]]);
    update(&rememberSize, [config nullableBoolForOption:[prefix append:@"/remember_size"] alias:@"memorize_size"]);
    update(&statusMessageType, [config stringForOption:[prefix append:@"/status_message_type"]]);
    update(&rawCandidateFormat, [config stringForOption:[prefix append:@"/candidate_format"]]);
    /* TYPOGRAPHY override */
    update(&fontName, [config stringForOption:[prefix append:@"/font_face"]]);
    update(&fontSize, [config nullableDoubleForOption:[prefix append:@"/font_point"] constraint:pos_round]);
    update(&labelFontName, [config stringForOption:[prefix append:@"/label_font_face"]]);
    update(&labelFontSize, [config nullableDoubleForOption:[prefix append:@"/label_font_point"] constraint:pos_round]);
    update(&commentFontName, [config stringForOption:[prefix append:@"/comment_font_face"]]);
    update(&commentFontSize, [config nullableDoubleForOption:[prefix append:@"/comment_font_point"] constraint:pos_round]);
    update(&opacity, [config nullableDoubleForOption:[prefix append:@"/opacity"] alias:@"alpha" constraint:clamp_uni]);
    update(&translucency, [config nullableDoubleForOption:[prefix append:@"/translucency"] constraint:clamp_uni]);
    update(&stackColors, [config nullableBoolForOption:[prefix append:@"/stack_colors"] alias:@"mutual_exclusive"]);
    update(&cornerRadius, [config nullableDoubleForOption:[prefix append:@"/corner_radius"] constraint:positive]);
    update(&hilitedCornerRadius, [config nullableDoubleForOption:[prefix append:@"/hilited_corner_radius"] constraint:positive]);
    update(&borderHeight, [config nullableDoubleForOption:[prefix append:@"/border_height"] constraint:pos_ceil]);
    update(&borderWidth, [config nullableDoubleForOption:[prefix append:@"/border_width"] constraint:pos_ceil]);
    update(&lineSpacing, [config nullableDoubleForOption:[prefix append:@"/line_spacing"] constraint:pos_round]);
    update(&spacing, [config nullableDoubleForOption:[prefix append:@"/spacing"] constraint:pos_round]);
    update(&baseOffset, [config nullableDoubleForOption:[prefix append:@"/base_offset"]]);
    update(&lineLength, [config nullableDoubleForOption:[prefix append:@"/line_length"]]);
    update(&shadowSize, [config nullableDoubleForOption:[prefix append:@"/shadow_size"] constraint:positive]);
  }

  /* FORMAT reset */
  rawCandidateFormat = rawCandidateFormat ? : kDefaultCandidateFormat;
  if (_linear != linear)
    _candidateFormat = @"";  // reset format after switching between linear and stacked

  /* TYPOGRAPHY refinement */
  fontSize = fontSize ? : @(kDefaultFontSize);
  labelFontSize = labelFontSize ? : fontSize;
  commentFontSize = commentFontSize ? : fontSize;

  NSFontDescriptor* fontDescriptor = [NSFontDescriptor createWithFullname:fontName] ? :
  [NSFontDescriptor createWithFullname:[NSFont userFontOfSize:0].fontName];
  NSFont* font = [NSFont fontWithDescriptor:fontDescriptor
                                       size:fontSize.doubleValue];
  NSFontDescriptor* labelFontDescriptor = [([NSFontDescriptor createWithFullname:labelFontName] ? : fontDescriptor)
                                           fontDescriptorByAddingAttributes:@{NSFontFeatureSettingsAttribute: monoDigitFeatures}];
  NSFont* labelFont = [NSFont fontWithDescriptor:labelFontDescriptor
                                            size:labelFontSize.doubleValue];
  NSFont* commentFont = [NSFont fontWithDescriptor:[NSFontDescriptor createWithFullname:commentFontName] ? : fontDescriptor
                                              size:commentFontSize.doubleValue];
  NSFont* systemFont = [NSFont systemFontOfSize:labelFontSize.doubleValue];
  NSFontDescriptor* pagingFontDescriptor = [labelFont.fontDescriptor fontDescriptorByAddingAttributes:
                                            @{NSFontCascadeListAttribute: @[systemFont.fontDescriptor]}];
  NSFont* pagingFont = [NSFont fontWithDescriptor:pagingFontDescriptor
                                             size:labelFontSize.doubleValue];

  CGFloat fontHeight = [font lineHeightAsVerticalFont:vertical];
  CGFloat labelFontHeight = [labelFont lineHeightAsVerticalFont:vertical];
  CGFloat commentFontHeight = [commentFont lineHeightAsVerticalFont:vertical];
  CGFloat pagingFontHeight = [pagingFont lineHeightAsVerticalFont:NO];
  CGFloat lineHeight = fmax(fontHeight, fmax(labelFontHeight, commentFontHeight));
  CGFloat fullWidth = ceil([kFullWidthSpace sizeWithAttributes:@{NSFontAttributeName: commentFont}].width);

  NSMutableParagraphStyle* candidateParagraphStyle = _candidateParagraphStyle.mutableCopy;
  candidateParagraphStyle.minimumLineHeight = lineHeight;
  candidateParagraphStyle.maximumLineHeight = lineHeight;
  candidateParagraphStyle.paragraphSpacingBefore = linear ? 0.0 : floor(lineSpacing.doubleValue * 0.5);
  candidateParagraphStyle.paragraphSpacing = linear ? 0.0 : ceil(lineSpacing.doubleValue * 0.5);
  candidateParagraphStyle.lineSpacing = linear ? lineSpacing.doubleValue : 0.0;
  candidateParagraphStyle.tabStops = @[];
  candidateParagraphStyle.defaultTabInterval = fullWidth * 2;

  NSMutableParagraphStyle* preeditParagraphStyle = _preeditParagraphStyle.mutableCopy;
  preeditParagraphStyle.minimumLineHeight = fontHeight;
  preeditParagraphStyle.maximumLineHeight = fontHeight;
  preeditParagraphStyle.tabStops = @[];

  NSMutableParagraphStyle* pagingParagraphStyle = _pagingParagraphStyle.mutableCopy;
  pagingParagraphStyle.minimumLineHeight = pagingFontHeight;
  pagingParagraphStyle.maximumLineHeight = pagingFontHeight;
  pagingParagraphStyle.tabStops = @[];

  NSMutableParagraphStyle* statusParagraphStyle = _statusParagraphStyle.mutableCopy;
  statusParagraphStyle.minimumLineHeight = commentFontHeight;
  statusParagraphStyle.maximumLineHeight = commentFontHeight;

  NSMutableDictionary<NSAttributedStringKey, id>* textAttrs = _textAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* labelAttrs = _labelAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* commentAttrs = _commentAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* preeditAttrs = _preeditAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* pagingAttrs = _pagingAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* statusAttrs = _statusAttrs.mutableCopy;

  textAttrs[NSFontAttributeName] = font;
  labelAttrs[NSFontAttributeName] = labelFont;
  commentAttrs[NSFontAttributeName] = commentFont;
  preeditAttrs[NSFontAttributeName] = font;
  pagingAttrs[NSFontAttributeName] = pagingFont;
  statusAttrs[NSFontAttributeName] = commentFont;
  textAttrs[NSKernAttributeName] = vertical ? @(0.1 * fontSize.doubleValue) : @(0.0);
  labelAttrs[NSKernAttributeName] = vertical ? @(0.1 * labelFontSize.doubleValue) : @(0.0);
  commentAttrs[NSKernAttributeName] = vertical ? @(0.1 * commentFontSize.doubleValue) : @(0.0);

  NSFont* zhFont = CFBridgingRelease(CTFontCreateUIFontForLanguage
                    (kCTFontUIFontSystem, fontSize.doubleValue, (CFStringRef)scriptVariant));
  NSFont* zhCommentFont = [NSFont fontWithDescriptor:zhFont.fontDescriptor
                                                size:commentFontSize.doubleValue];
  CGFloat maxFontSize = fmax(fontSize.doubleValue, fmax(commentFontSize.doubleValue,
                                                        labelFontSize.doubleValue));
  NSFont* refFont = [NSFont fontWithDescriptor:zhFont.fontDescriptor
                                          size:maxFontSize];
  if (vertical) {
    zhFont = zhFont.verticalFont;
    zhCommentFont = zhCommentFont.verticalFont;
    refFont = refFont.verticalFont;
  }
  NSDictionary* baselineRefInfo =
    @{(id)kCTBaselineReferenceFont : refFont,
      (id)kCTBaselineClassIdeographicCentered : @(vertical ? 0.0 : (refFont.ascender + refFont.descender) * 0.5),
      (id)kCTBaselineClassRoman : @(vertical ? - (refFont.ascender + refFont.descender) * 0.5 : 0.0),
      (id)kCTBaselineClassIdeographicLow : @(vertical ? (refFont.descender - refFont.ascender) * 0.5 : refFont.descender)};

  textAttrs[(id)kCTBaselineReferenceInfoAttributeName] = baselineRefInfo;
  labelAttrs[(id)kCTBaselineReferenceInfoAttributeName] = baselineRefInfo;
  commentAttrs[(id)kCTBaselineReferenceInfoAttributeName] = baselineRefInfo;
  preeditAttrs[(id)kCTBaselineReferenceInfoAttributeName] = @{(id)kCTBaselineReferenceFont : zhFont};
  pagingAttrs[(id)kCTBaselineReferenceInfoAttributeName] = @{(id)kCTBaselineReferenceFont : systemFont};
  statusAttrs[(id)kCTBaselineReferenceInfoAttributeName] = @{(id)kCTBaselineReferenceFont : zhCommentFont};

  textAttrs[(id)kCTBaselineClassAttributeName] =
    vertical ? (id)kCTBaselineClassIdeographicCentered : (id)kCTBaselineClassRoman;
  labelAttrs[(id)kCTBaselineClassAttributeName] = (id)kCTBaselineClassIdeographicCentered;
  commentAttrs[(id)kCTBaselineClassAttributeName] =
    vertical ? (id)kCTBaselineClassIdeographicCentered : (id)kCTBaselineClassRoman;
  preeditAttrs[(id)kCTBaselineClassAttributeName] =
    vertical ? (id)kCTBaselineClassIdeographicCentered : (id)kCTBaselineClassRoman;
  statusAttrs[(id)kCTBaselineClassAttributeName] =
    vertical ? (id)kCTBaselineClassIdeographicCentered : (id)kCTBaselineClassRoman;
  pagingAttrs[(id)kCTBaselineClassAttributeName] = (id)kCTBaselineClassRoman;

  textAttrs[(id)kCTLanguageAttributeName] = scriptVariant;
  labelAttrs[(id)kCTLanguageAttributeName] = scriptVariant;
  commentAttrs[(id)kCTLanguageAttributeName] = scriptVariant;
  preeditAttrs[(id)kCTLanguageAttributeName] = scriptVariant;
  statusAttrs[(id)kCTLanguageAttributeName] = scriptVariant;

  textAttrs[NSBaselineOffsetAttributeName] = baseOffset;
  labelAttrs[NSBaselineOffsetAttributeName] = baseOffset;
  commentAttrs[NSBaselineOffsetAttributeName] = baseOffset;
  preeditAttrs[NSBaselineOffsetAttributeName] = baseOffset;
  pagingAttrs[NSBaselineOffsetAttributeName] = baseOffset;
  statusAttrs[NSBaselineOffsetAttributeName] = baseOffset;

  preeditAttrs[NSParagraphStyleAttributeName] = preeditParagraphStyle;
  pagingAttrs[NSParagraphStyleAttributeName] = pagingParagraphStyle;
  statusAttrs[NSParagraphStyleAttributeName] = statusParagraphStyle;
  pagingAttrs[NSVerticalGlyphFormAttributeName] = @NO;

  /*** CHROMATICS refinement ***/
  if (@available(macOS 10.14, *)) {
    if (isnormal(translucency.floatValue) && !isNative && backColor != nil &&
        (_style == kDarkStyle ? backColor.lStarComponent > 0.6 : backColor.lStarComponent < 0.4)) {
      backColor = [backColor colorByInvertingLuminanceToExtent:kStandardColorInversion];
      borderColor = [borderColor colorByInvertingLuminanceToExtent:kStandardColorInversion];
      preeditBackColor = [preeditBackColor colorByInvertingLuminanceToExtent:kStandardColorInversion];
      preeditForeColor = [preeditForeColor colorByInvertingLuminanceToExtent:kStandardColorInversion];
      candidateBackColor = [candidateBackColor colorByInvertingLuminanceToExtent:kStandardColorInversion];
      textForeColor = [textForeColor colorByInvertingLuminanceToExtent:kStandardColorInversion];
      commentForeColor = [commentForeColor colorByInvertingLuminanceToExtent:kStandardColorInversion];
      labelForeColor = [labelForeColor colorByInvertingLuminanceToExtent:kStandardColorInversion];
      hilitedPreeditBackColor = [hilitedPreeditBackColor colorByInvertingLuminanceToExtent:kModerateColorInversion];
      hilitedPreeditForeColor = [hilitedPreeditForeColor colorByInvertingLuminanceToExtent:kAugmentedColorInversion];
      hilitedCandidateBackColor = [hilitedCandidateBackColor colorByInvertingLuminanceToExtent:kModerateColorInversion];
      hilitedTextForeColor = [hilitedTextForeColor colorByInvertingLuminanceToExtent:kAugmentedColorInversion];
      hilitedCommentForeColor = [hilitedCommentForeColor colorByInvertingLuminanceToExtent:kAugmentedColorInversion];
      hilitedLabelForeColor = [hilitedLabelForeColor colorByInvertingLuminanceToExtent:kAugmentedColorInversion];
    }
  }

  backColor = backColor ? : NSColor.controlBackgroundColor;
  borderColor = borderColor ? : isNative ? NSColor.gridColor : nil;
  preeditBackColor = preeditBackColor ? : isNative ? NSColor.windowBackgroundColor : nil;
  preeditForeColor = preeditForeColor ? : NSColor.textColor;
  textForeColor = textForeColor ? : NSColor.controlTextColor;
  commentForeColor = commentForeColor ? : NSColor.secondaryLabelColor;
  labelForeColor = labelForeColor ? : isNative ? NSColor.secondaryLabelColor : blendColors(textForeColor, backColor);
  hilitedPreeditBackColor = hilitedPreeditBackColor ? : isNative ? NSColor.selectedTextBackgroundColor : nil;
  hilitedPreeditForeColor = hilitedPreeditForeColor ? : NSColor.selectedTextColor;
  hilitedCandidateBackColor = hilitedCandidateBackColor ? : isNative ? NSColor.selectedContentBackgroundColor : nil;
  hilitedTextForeColor = hilitedTextForeColor ? : NSColor.selectedMenuItemTextColor;
  hilitedCommentForeColor = hilitedCommentForeColor ? : NSColor.alternateSelectedControlTextColor;
  hilitedLabelForeColor = hilitedLabelForeColor ? : isNative ? NSColor.alternateSelectedControlTextColor :
    blendColors(hilitedTextForeColor, hilitedCandidateBackColor);

  textAttrs[NSForegroundColorAttributeName] = textForeColor;
  labelAttrs[NSForegroundColorAttributeName] = labelForeColor;
  commentAttrs[NSForegroundColorAttributeName] = commentForeColor;
  preeditAttrs[NSForegroundColorAttributeName] = preeditForeColor;
  pagingAttrs[NSForegroundColorAttributeName] = preeditForeColor;
  statusAttrs[NSForegroundColorAttributeName] = commentForeColor;

  _borderInsets = vertical ? NSMakeSize(borderHeight.doubleValue, borderWidth.doubleValue)
                           : NSMakeSize(borderWidth.doubleValue, borderHeight.doubleValue);
  _cornerRadius = fmin(cornerRadius.doubleValue, lineHeight * 0.5);
  _hilitedCornerRadius = fmin(hilitedCornerRadius.doubleValue, lineHeight * 0.5);
  _fullWidth = fullWidth;
  _lineSpacing = lineSpacing.doubleValue;
  _preeditSpacing = spacing.doubleValue;
  _opacity = opacity ? opacity.doubleValue : 1.0;
  _lineLength = isnormal(lineLength.doubleValue) ? fmax(ceil(lineLength.doubleValue), fullWidth * 5) : 0.0;
  _shadowSize = shadowSize.doubleValue;
  _translucency = translucency.floatValue;
  _stackColors = stackColors.boolValue;
  _showPaging = showPaging.boolValue;
  _rememberSize = rememberSize.boolValue;
  _tabular = tabular;
  _linear = linear;
  _vertical = vertical;
  _inlinePreedit = inlinePreedit.boolValue;
  _inlineCandidate = inlineCandidate.boolValue;

  _textAttrs = textAttrs;
  _commentAttrs = commentAttrs;
  _labelAttrs = labelAttrs;
  _preeditAttrs = preeditAttrs;
  _pagingAttrs = pagingAttrs;
  _statusAttrs = statusAttrs;

  _candidateParagraphStyle = candidateParagraphStyle;
  _preeditParagraphStyle = preeditParagraphStyle;
  _pagingParagraphStyle = pagingParagraphStyle;
  _statusParagraphStyle = statusParagraphStyle;

  _backImage = backImage;
  _backColor = backColor;
  _borderColor = borderColor;
  _preeditBackColor = preeditBackColor;
  _preeditForeColor = preeditForeColor;
  _candidateBackColor = candidateBackColor;
  _textForeColor = textForeColor;
  _commentForeColor = commentForeColor;
  _labelForeColor = labelForeColor;
  _hilitedPreeditBackColor = hilitedPreeditBackColor;
  _hilitedPreeditForeColor = hilitedPreeditForeColor;
  _hilitedCandidateBackColor = hilitedCandidateBackColor;
  _hilitedTextForeColor = hilitedTextForeColor;
  _hilitedCommentForeColor = hilitedCommentForeColor;
  _hilitedLabelForeColor = hilitedLabelForeColor;
  _dimmedLabelForeColor = tabular ? [labelForeColor colorWithAlphaComponent:
                                     labelForeColor.alphaComponent * 0.2] : nil;
  _scriptVariant = scriptVariant;

  [self updateStatusMessageType:statusMessageType];
  [self updateCandidateFormat:rawCandidateFormat];
  [self updateSeperatorAndSymbolAttrs];

}

- (void)setAnnotationHeight:(CGFloat)height {
  if (isnormal(height) && _lineSpacing < height * 2) {
    _lineSpacing = height * 2;
    NSMutableParagraphStyle* candidateParagraphStyle = _candidateParagraphStyle.mutableCopy;
    if (_linear) {
      candidateParagraphStyle.lineSpacing = height * 2;
      NSMutableParagraphStyle* truncatedParagraphStyle = candidateParagraphStyle.mutableCopy;
      truncatedParagraphStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
      truncatedParagraphStyle.tighteningFactorForTruncation = 0.0;
      _truncatedParagraphStyle = truncatedParagraphStyle;
    } else {
      candidateParagraphStyle.paragraphSpacingBefore = height;
      candidateParagraphStyle.paragraphSpacing = height;
    }
    _candidateParagraphStyle = candidateParagraphStyle;

    NSMutableDictionary<NSAttributedStringKey, id>* textAttrs = _textAttrs.mutableCopy;
    NSMutableDictionary<NSAttributedStringKey, id>* commentAttrs = _commentAttrs.mutableCopy;
    NSMutableDictionary<NSAttributedStringKey, id>* labelAttrs = _labelAttrs.mutableCopy;
    textAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;
    commentAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;
    labelAttrs[NSParagraphStyleAttributeName] = candidateParagraphStyle;
    _textAttrs = textAttrs;
    _commentAttrs = commentAttrs;
    _labelAttrs = labelAttrs;

    NSMutableAttributedString* candidateTemplate = _candidateTemplate.mutableCopy;
    [candidateTemplate addAttribute:NSParagraphStyleAttributeName
                              value:candidateParagraphStyle
                              range:NSMakeRange(0, candidateTemplate.length)];
    _candidateTemplate = candidateTemplate;
    NSMutableAttributedString* candidateHilitedTemplate = _candidateHilitedTemplate.mutableCopy;
    [candidateHilitedTemplate addAttribute:NSParagraphStyleAttributeName
                                     value:candidateParagraphStyle
                                     range:NSMakeRange(0, candidateHilitedTemplate.length)];
    _candidateHilitedTemplate = candidateHilitedTemplate;
    if (_tabular) {
      NSMutableAttributedString* candidateDimmedTemplate = _candidateDimmedTemplate.mutableCopy;
      [candidateDimmedTemplate addAttribute:NSParagraphStyleAttributeName
                                      value:candidateParagraphStyle
                                      range:NSMakeRange(0, candidateDimmedTemplate.length)];
      _candidateDimmedTemplate = candidateDimmedTemplate;
    }
  }
}

- (void)updateScriptVariant:(NSString*)scriptVariant {
  if ([scriptVariant isEqualToString:_scriptVariant])
    return;
  _scriptVariant = scriptVariant;

  NSMutableDictionary<NSAttributedStringKey, id>* textAttrs = _textAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* labelAttrs = _labelAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* commentAttrs = _commentAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* preeditAttrs = _preeditAttrs.mutableCopy;
  NSMutableDictionary<NSAttributedStringKey, id>* statusAttrs = _statusAttrs.mutableCopy;

  CGFloat fontSize = [textAttrs[NSFontAttributeName] pointSize];
  CGFloat commentFontSize = [commentAttrs[NSFontAttributeName] pointSize];
  CGFloat labelFontSize = [labelAttrs[NSFontAttributeName] pointSize];
  NSFont* zhFont = CFBridgingRelease(CTFontCreateUIFontForLanguage
                                     (kCTFontUIFontSystem, fontSize, (CFStringRef)scriptVariant));
  NSFont* zhCommentFont = [NSFont fontWithDescriptor:zhFont.fontDescriptor
                                                size:commentFontSize];
  CGFloat maxFontSize = fmax(fontSize, fmax(commentFontSize, labelFontSize));
  NSFont* refFont = [NSFont fontWithDescriptor:zhFont.fontDescriptor
                                          size:maxFontSize];
  if (_vertical) {
    zhFont = zhFont.verticalFont;
    zhCommentFont = zhCommentFont.verticalFont;
    refFont = refFont.verticalFont;
  }
  NSDictionary* baselineRefInfo =
    @{(id)kCTBaselineReferenceFont : refFont,
      (id)kCTBaselineClassIdeographicCentered : @(_vertical ? 0.0 : (refFont.ascender + refFont.descender) * 0.5),
      (id)kCTBaselineClassRoman : @(_vertical ? - (refFont.ascender + refFont.descender) * 0.5 : 0.0),
      (id)kCTBaselineClassIdeographicLow : @(_vertical ? (refFont.descender - refFont.ascender) * 0.5 : refFont.descender)};

  textAttrs[(id)kCTBaselineReferenceInfoAttributeName] = baselineRefInfo;
  labelAttrs[(id)kCTBaselineReferenceInfoAttributeName] = baselineRefInfo;
  commentAttrs[(id)kCTBaselineReferenceInfoAttributeName] = baselineRefInfo;
  preeditAttrs[(id)kCTBaselineReferenceInfoAttributeName] = @{(id)kCTBaselineReferenceFont : zhFont};
  statusAttrs[(id)kCTBaselineReferenceInfoAttributeName] = @{(id)kCTBaselineReferenceFont : zhCommentFont};

  textAttrs[(id)kCTLanguageAttributeName] = scriptVariant;
  labelAttrs[(id)kCTLanguageAttributeName] = scriptVariant;
  commentAttrs[(id)kCTLanguageAttributeName] = scriptVariant;
  preeditAttrs[(id)kCTLanguageAttributeName] = scriptVariant;
  statusAttrs[(id)kCTLanguageAttributeName] = scriptVariant;

  _textAttrs = textAttrs;
  _labelAttrs = labelAttrs;
  _commentAttrs = commentAttrs;
  _preeditAttrs = preeditAttrs;
  _statusAttrs = statusAttrs;

  NSMutableAttributedString* candidateTemplate = _candidateTemplate.mutableCopy;
  NSRange templateRange = NSMakeRange(0, candidateTemplate.length);
  [candidateTemplate addAttribute:(id)kCTBaselineReferenceInfoAttributeName value:baselineRefInfo range:templateRange];
  [candidateTemplate addAttribute:(id)kCTLanguageAttributeName value:scriptVariant range:templateRange];
  _candidateTemplate = candidateTemplate;

  NSMutableAttributedString* candidateHilitedTemplate = candidateTemplate.mutableCopy;
  [candidateHilitedTemplate addAttribute:(id)kCTBaselineReferenceInfoAttributeName value:baselineRefInfo range:templateRange];
  [candidateHilitedTemplate addAttribute:(id)kCTLanguageAttributeName value:scriptVariant range:templateRange];
  _candidateHilitedTemplate = candidateHilitedTemplate;

  if (_tabular) {
    NSMutableAttributedString* candidateDimmedTemplate = candidateTemplate.mutableCopy;
    [candidateDimmedTemplate addAttribute:(id)kCTBaselineReferenceInfoAttributeName value:baselineRefInfo range:templateRange];
    [candidateDimmedTemplate addAttribute:(id)kCTLanguageAttributeName value:scriptVariant range:templateRange];
    _candidateDimmedTemplate = candidateDimmedTemplate;
  }
}

@end  // SquirrelTheme


#pragma mark - Auxiliary structs and views

typedef struct SquirrelTabularIndex {
  NSUInteger index;
  NSUInteger lineNum;
  NSUInteger tabNum;
} SquirrelTabularIndex;

/* location and length (of candidate) are relative to the textStorage
 text/comment marks the start of text/comment relative to the candidate */
typedef struct SquirrelCandidateInfo {
  NSUInteger location;
  NSUInteger length;
  NSUInteger text;
  NSUInteger comment;
  NSUInteger idx;
  NSUInteger col;
  BOOL truncated;
  inline NSUInteger maxRange() {
    return location + length;
  }
  inline NSRange candidateRange() {
    return NSMakeRange(location, length);
  }
  inline NSRange labelRange() {
    return NSMakeRange(location, text);
  }
  inline NSRange textRange() {
    return NSMakeRange(location + text, comment - text);
  }
  inline NSRange commentRange() {
    return NSMakeRange(location + comment, length - comment);
  }
} SquirrelCandidateInfo;


#pragma mark - Typesetting extensions for TextKit 1 (Mac OSX 10.9 to MacOS 11)

@implementation SquirrelLayoutManager

- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow
                        atPoint:(NSPoint)origin {
  NSTextContainer* textContainer = [self textContainerForGlyphAtIndex:glyphsToShow.location
                                                       effectiveRange:NULL
                                              withoutAdditionalLayout:YES];
  NSPoint containerOrigin = NSMakePoint(origin.x - textContainer.textView.textContainerOrigin.x,
                                        origin.y - textContainer.textView.textContainerOrigin.y);
  BOOL verticalOrientation = textContainer.layoutOrientation == NSTextLayoutOrientationVertical;
  CGContextRef context = NSGraphicsContext.currentContext.CGContext;
  CGContextResetClip(context);
  [self enumerateLineFragmentsForGlyphRange:glyphsToShow
                                 usingBlock:^(NSRect lineRect, NSRect lineUsedRect, NSTextContainer * _Nonnull container,
                                              NSRange lineRange, BOOL * _Nonnull flag) {
    NSRange charRange = [self characterRangeForGlyphRange:lineRange actualGlyphRange:NULL];
    [self.textStorage enumerateAttributesInRange:charRange
                                         options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired
                                      usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs,
                                                   NSRange runRange, BOOL * _Nonnull stop) {
      NSRange runGlyphRange = [self glyphRangeForCharacterRange:runRange actualCharacterRange:NULL];
      NSFont* runFont = attrs[NSFontAttributeName];
      if (attrs[(id)kCTRubyAnnotationAttributeName] != nil ||
          (verticalOrientation && [runFont.fontName isEqualToString:@"AppleColorEmoji"] && runFont.pointSize < 24)) {
        CGContextSaveGState(context);
        CGContextScaleCTM(context, 1.0, -1.0);
        CGPoint position = [self locationForGlyphAtIndex:runGlyphRange.location];
        position.x += lineRect.origin.x + containerOrigin.x;
        position.y += lineRect.origin.y + containerOrigin.y;
        CTLineRef line;
        if (attrs[(id)kCTRubyAnnotationAttributeName] == nil) {
          NSMutableAttributedString* subString = [self.textStorage attributedSubstringFromRange:runRange].mutableCopy;
          [subString addAttribute:NSVerticalGlyphFormAttributeName value:@1 range:NSMakeRange(0, runRange.length)];
          line = CTLineCreateWithAttributedString((CFAttributedStringRef)subString);
          if (NSInteger superscript = [attrs[NSSuperscriptAttributeName] integerValue] != 0)
            position.y -= runFont.descender + superscript * 0.5;
        } else {
          line = CTLineCreateWithAttributedString
            ((CFAttributedStringRef)[self.textStorage attributedSubstringFromRange:runRange]);
        }
        CFArrayRef runs = CTLineGetGlyphRuns((CTLineRef)CFAutorelease(line));
        for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
          CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
          CGAffineTransform matrix = CTRunGetTextMatrix(run);
          CGPoint glyphOrigin = CGContextConvertPointToDeviceSpace(context, position);
          glyphOrigin = CGContextConvertPointToUserSpace(context, CGPointMake(ceil(glyphOrigin.x), ceil(glyphOrigin.y)));
          matrix.tx = glyphOrigin.x;
          matrix.ty = -glyphOrigin.y;
          CGContextSetTextMatrix(context, matrix);
          CTRunDraw(run, context, CFRangeMake(0, 0));
          if (i < CFArrayGetCount(runs) - 1)
            position.x += CTRunGetTypographicBounds(run, CFRangeMake(0, 0), NULL, NULL, NULL);
        }
        CGContextRestoreGState(context);
      } else {
        NSPoint glyphOrigin = containerOrigin;
        if (!verticalOrientation) {
          NSFont* refFont = attrs[(id)kCTBaselineReferenceInfoAttributeName][(id)kCTBaselineReferenceFont];
          glyphOrigin.y += (runFont.ascender + runFont.descender - refFont.ascender - refFont.descender) * 0.5;
        }
        glyphOrigin = CGContextConvertPointToDeviceSpace(context, glyphOrigin);
        glyphOrigin = CGContextConvertPointToUserSpace(context, NSMakePoint(ceil(glyphOrigin.x), ceil(glyphOrigin.y)));
        [super drawGlyphsForGlyphRange:runGlyphRange atPoint:glyphOrigin];
      }
    }];
  }];
}

- (BOOL)      layoutManager:(NSLayoutManager*)layoutManager
  shouldSetLineFragmentRect:(inout NSRect*)lineFragmentRect
       lineFragmentUsedRect:(inout NSRect*)lineFragmentUsedRect
             baselineOffset:(inout CGFloat*)baselineOffset
            inTextContainer:(NSTextContainer*)textContainer
              forGlyphRange:(NSRange)glyphRange {
  NSParagraphStyle* defaultParagraphStyle = ((SquirrelTextContainer*)textContainer).defaultParagraphStyle;
  if (defaultParagraphStyle == nil)
    return NO;

  BOOL didModify = NO;
  BOOL verticalOrientation = textContainer.layoutOrientation == NSTextLayoutOrientationVertical;
  NSRange charRange = [layoutManager characterRangeForGlyphRange:glyphRange
                                                actualGlyphRange:NULL];
  CGFloat lineHeight = defaultParagraphStyle.minimumLineHeight;
  CGFloat baseline = lineHeight * 0.5;
  if (!verticalOrientation) {
    NSFont* refFont = [layoutManager.textStorage
                       attribute:(id)kCTBaselineReferenceInfoAttributeName
                       atIndex:charRange.location
                       effectiveRange:NULL][(id)kCTBaselineReferenceFont];
    baseline += (refFont.ascender + refFont.descender) * 0.5;
  }
  CGFloat newBaselineOffset = round(lineFragmentUsedRect->origin.y - lineFragmentRect->origin.y + baseline);
  if (isnormal(*baselineOffset - newBaselineOffset)) {
    *baselineOffset = newBaselineOffset;
    didModify = YES;
  }
  return didModify;
}

- (BOOL)                        layoutManager:(NSLayoutManager*)layoutManager
  shouldBreakLineByWordBeforeCharacterAtIndex:(NSUInteger)charIndex {
  if (charIndex <= 1)
    return YES;

  unichar charBeforeIndex = [layoutManager.textStorage.mutableString
                             characterAtIndex:charIndex - 1];
  SquirrelContentBlock contentBlock = ((SquirrelTextContainer*)layoutManager.textContainers.firstObject).contentBlock;
  return contentBlock == kLinearCandidateBlock ? charBeforeIndex == 0x1D
                                               : charBeforeIndex != '\t';
}

- (NSControlCharacterAction)layoutManager:(NSLayoutManager*)layoutManager
                          shouldUseAction:(NSControlCharacterAction)action
               forControlCharacterAtIndex:(NSUInteger)charIndex {
  if (charIndex > 0 && [layoutManager.textStorage.mutableString
                        characterAtIndex:charIndex] == 0x8B &&
      [layoutManager.textStorage attribute:(id)kCTRubyAnnotationAttributeName
                                   atIndex:charIndex - 1
                            effectiveRange:NULL]) {
    return NSControlCharacterActionWhitespace;
  }
  return action;
}

- (NSRect)            layoutManager:(NSLayoutManager*)layoutManager
  boundingBoxForControlGlyphAtIndex:(NSUInteger)glyphIndex
                   forTextContainer:(NSTextContainer*)textContainer
               proposedLineFragment:(NSRect)proposedRect
                      glyphPosition:(NSPoint)glyphPosition
                     characterIndex:(NSUInteger)charIndex {
  NSRect rect = {glyphPosition, NSZeroSize};
  if ([layoutManager.textStorage.mutableString characterAtIndex:charIndex] == 0x8B) {
    if (NSValue* controlCharacterSize = [layoutManager.textStorage attribute:kControlCharacterSizeAttributeName atIndex:charIndex effectiveRange:NULL])
      rect.size = controlCharacterSize.sizeValue;
  }
  return rect;
}

@end  // SquirrelLayoutManager


#pragma mark - Typesetting extensions for TextKit 2 (MacOS 12 or higher)

@implementation SquirrelTextLayoutFragment

- (NSTextLayoutOrientation)layoutOrientation {
  return self.textLayoutManager.textContainer.layoutOrientation;
}

- (CGRect)renderingSurfaceBounds {
  CGRect bounds = super.renderingSurfaceBounds;
  if (self.state == NSTextLayoutFragmentStateLayoutAvailable) {
    SquirrelTextLayoutManager* textLayoutManager = (SquirrelTextLayoutManager*)self.textLayoutManager;
    SquirrelTextContainer* textContainer = (SquirrelTextContainer*)textLayoutManager.textContainer;
    if (textContainer.contentBlock == kLinearCandidateBlock || textContainer.contentBlock == kStackedCandidateBlock) {
      NSParagraphStyle* defaultParagraphStyle = textContainer.defaultParagraphStyle;
      if ([self.rangeInElement.location isEqual:textLayoutManager.documentRange.location]) {
        CGFloat spacing = textContainer.contentBlock == kStackedCandidateBlock ?
          defaultParagraphStyle.paragraphSpacingBefore : floor(defaultParagraphStyle.lineSpacing * 0.5);
        bounds.origin.y -= spacing;
        bounds.size.height += spacing;
      }
      if ([self.rangeInElement.endLocation isEqual:textLayoutManager.documentRange.endLocation]) {
        bounds.size.height += textContainer.contentBlock == kStackedCandidateBlock ?
          defaultParagraphStyle.paragraphSpacing : ceil(defaultParagraphStyle.lineSpacing * 0.5);
      }
    }
  }
  return bounds;
}

- (void)drawAtPoint:(CGPoint)point
          inContext:(CGContextRef)context {
  NSPoint origin = point;
  if (@available(macOS 14.0, *)) {
  } else {  // in macOS 12 and 13, textLineFragments.typographicBouonds are in textContainer coordinates
    origin.x -= self.layoutFragmentFrame.origin.x;
    origin.y -= self.layoutFragmentFrame.origin.y;
  }
  CGContextResetClip(context);
  for (NSTextLineFragment* lineFrag in self.textLineFragments) {
    CGRect lineRect = CGRectOffset(lineFrag.typographicBounds, origin.x, origin.y);
    CGFloat baseline = CGRectGetMidY(lineRect);
    if (self.layoutOrientation == NSTextLayoutOrientationHorizontal) {
      NSFont* refFont = [lineFrag.attributedString
                         attribute:(id)kCTBaselineReferenceInfoAttributeName
                         atIndex:lineFrag.characterRange.location
                         effectiveRange:NULL][(id)kCTBaselineReferenceFont];
      baseline += (refFont.ascender + refFont.descender) * 0.5;
    }
    CGPoint renderOrigin = CGPointMake(NSMinX(lineRect) + lineFrag.glyphOrigin.x,
                                       round(baseline) - lineFrag.glyphOrigin.y);
    renderOrigin = CGContextConvertPointToDeviceSpace(context, renderOrigin);
    renderOrigin = CGContextConvertPointToUserSpace(context, CGPointMake(ceil(renderOrigin.x),
                                                                         ceil(renderOrigin.y)));
    [lineFrag drawAtPoint:renderOrigin inContext:context];
  }
}

@end  // SquirrelTextLayoutFragment


@implementation SquirrelTextLayoutManager

- (BOOL)      textLayoutManager:(NSTextLayoutManager*)textLayoutManager
  shouldBreakLineBeforeLocation:(id<NSTextLocation>)location
                    hyphenating:(BOOL)hyphenating {
  NSTextContentStorage* contentStorage = (NSTextContentStorage*)textLayoutManager.textContentManager;
  NSUInteger charIndex = (NSUInteger)[contentStorage
                                      offsetFromLocation:contentStorage.documentRange.location
                                      toLocation:location];
  if (charIndex <= 1)
    return YES;

  unichar charBeforeIndex = [contentStorage.textStorage.mutableString
                             characterAtIndex:charIndex - 1];
  SquirrelContentBlock contentBlock = ((SquirrelTextContainer*)textLayoutManager.textContainer).contentBlock;
  return contentBlock == kLinearCandidateBlock ? charBeforeIndex == 0x1D
                                               : charBeforeIndex != '\t';
}

- (NSTextLayoutFragment*)textLayoutManager:(NSTextLayoutManager*)textLayoutManager
             textLayoutFragmentForLocation:(id<NSTextLocation>)location
                             inTextElement:(NSTextElement*)textElement {
  NSTextRange* textRange = [NSTextRange.alloc
                            initWithLocation:location
                            endLocation:textElement.elementRange.endLocation];
  return [SquirrelTextLayoutFragment.alloc initWithTextElement:textElement
                                                         range:textRange];
}

@end  // SquirrelTextLayoutManager


#pragma mark - Views of texts and views behind texts (backgrounds and highlights)

@implementation NSFlippedView

- (BOOL)isFlipped {
  return YES;
}

@end


@implementation SquirrelTextContainer {
  NSTextLayoutOrientation _layoutOrientation;
}

@synthesize layoutOrientation = _layoutOrientation;

- (instancetype)initWithContentBlock:(SquirrelContentBlock)contentBlock
                             storage:(NSTextStorage*)textStorage {
  if (self = [super initWithSize:NSZeroSize]) {
    self.contentBlock = contentBlock;
    self.lineFragmentPadding = 0;
    if (@available(macOS 12.0, *)) {
      SquirrelTextLayoutManager* textLayoutManager = SquirrelTextLayoutManager.alloc.init;
      textLayoutManager.usesFontLeading = NO;
      textLayoutManager.usesHyphenation = NO;
      textLayoutManager.delegate = textLayoutManager;
      textLayoutManager.textContainer = self;
      NSTextContentStorage* contentStorage = NSTextContentStorage.alloc.init;
      [contentStorage addTextLayoutManager:textLayoutManager];
      contentStorage.textStorage = textStorage;
    } else {
      SquirrelLayoutManager* layoutManager = SquirrelLayoutManager.alloc.init;
      layoutManager.backgroundLayoutEnabled = YES;
      layoutManager.usesFontLeading = NO;
      layoutManager.typesetterBehavior = NSTypesetterLatestBehavior;
      layoutManager.delegate = layoutManager;
      [layoutManager addTextContainer:self];
      [textStorage addLayoutManager:layoutManager];
    }
  }
  return self;
}

- (NSRect)layoutText {
  NSRect rect;
  if (@available(macOS 12.0, *)) {
    [self.textLayoutManager ensureLayoutForRange:self.textLayoutManager.documentRange];
    rect = self.textLayoutManager.usageBoundsForTextContainer;
  } else {
    [self.layoutManager ensureLayoutForTextContainer:self];
    rect = [self.layoutManager usedRectForTextContainer:self];
  }
  return NSIntegralRectWithOptions(rect, NSAlignMinXNearest | NSAlignMinYNearest | NSAlignWidthOutward | NSAlignHeightOutward);
}

@end  // SquirrelTextContainer


@implementation SquirrelTextView

- (SquirrelContentBlock)contentBlock {
  return _container.contentBlock;
}

- (void)setContentBlock:(SquirrelContentBlock)contentBlock {
  _container.contentBlock = contentBlock;
}

- (NSParagraphStyle*)defaultParagraphStyle {
  return _container.defaultParagraphStyle;
}

- (void)setDefaultParagraphStyle:(NSParagraphStyle*)defaultParagraphStyle {
  _container.defaultParagraphStyle = defaultParagraphStyle;
}

- (instancetype)initWithContentBlock:(SquirrelContentBlock)contentBlock
                             storage:(NSTextStorage*)textStorage {
  SquirrelTextContainer* container = [SquirrelTextContainer.alloc initWithContentBlock:contentBlock storage:textStorage];
  if (self = [super initWithFrame:NSZeroRect textContainer:container]) {
    self.container = container;
    self.drawsBackground = NO;
    self.selectable = NO;
    self.wantsLayer = NO;
    self.clipsToBounds = NO;
  }
  return self;
}

- (NSTextLayoutOrientation)layoutOrientation {
  return _container.layoutOrientation;
}

- (void)setLayoutOrientation:(NSTextLayoutOrientation)orientation {
  [super setLayoutOrientation:orientation];
  _container.layoutOrientation = orientation;
}

- (NSTextRange*)textRangeFromCharRange:(NSRange)charRange {
  if (charRange.location == NSNotFound)
    return nil;

  NSTextContentStorage* storage = self.textContentStorage;
  id<NSTextLocation> startLocation =
    [storage locationFromLocation:storage.documentRange.location
                       withOffset:(NSInteger)charRange.location];
  id<NSTextLocation> endLocation =
    [storage locationFromLocation:startLocation
                       withOffset:(NSInteger)charRange.length];
  return [NSTextRange.alloc initWithLocation:startLocation
                                 endLocation:endLocation];
}

- (NSRange)charRangeFromTextRange:(NSTextRange*)textRange {
  if (textRange == nil)
    return NSMakeRange(NSNotFound, 0);

  NSTextContentStorage* storage = self.textContentStorage;
  NSInteger location = [storage offsetFromLocation:storage.documentRange.location
                                        toLocation:textRange.location];
  NSInteger length = [storage offsetFromLocation:textRange.location
                                      toLocation:textRange.endLocation];
  return NSMakeRange((NSUInteger)location, (NSUInteger)length);
}

- (NSRect)layoutText {
  return _container.layoutText;
}

// Get the rectangle containing the range of text
- (NSRect)blockRectForRange:(NSRange)charRange {
  if (charRange.location == NSNotFound)
    return NSZeroRect;
  if (@available(macOS 12.0, *)) {
    NSTextRange* textRange = [self textRangeFromCharRange:charRange];
    NSRect __block firstLineRect = NSZeroRect;
    NSRect __block finalLineRect = NSZeroRect;
    [self.textLayoutManager
     enumerateTextSegmentsInRange:textRange
     type:NSTextLayoutManagerSegmentTypeStandard
     options:NSTextLayoutManagerSegmentOptionsRangeNotRequired
     usingBlock:^BOOL(NSTextRange* _Nullable segRange, CGRect segFrame,
                      CGFloat baseline, NSTextContainer* _Nonnull textContainer) {
      if (!CGRectIsEmpty(segFrame)) {
        if (NSIsEmptyRect(firstLineRect) || CGRectGetMinY(segFrame) < nexttoward(NSMaxY(firstLineRect), -INFINITY))
          firstLineRect = NSUnionRect(segFrame, firstLineRect);
        else
          finalLineRect = NSUnionRect(segFrame, finalLineRect);
      }
      return YES;
    }];

    if (self.contentBlock == kLinearCandidateBlock && isnormal(self.defaultParagraphStyle.lineSpacing)) {
      firstLineRect.size.height += self.defaultParagraphStyle.lineSpacing;
      if (!NSIsEmptyRect(finalLineRect))
        finalLineRect.size.height += self.defaultParagraphStyle.lineSpacing;
    }

    if (NSIsEmptyRect(finalLineRect)) {
      return firstLineRect;
    } else {
      CGFloat containerWidth = NSWidth(self.textLayoutManager.usageBoundsForTextContainer);
      return NSMakeRect(0.0, NSMinY(firstLineRect), containerWidth,
                        NSMaxY(finalLineRect) - NSMinY(firstLineRect));
    }
  } else {
    NSRange glyphRange = [self.layoutManager glyphRangeForCharacterRange:charRange
                                                    actualCharacterRange:NULL];
    NSRange firstLineRange = NSMakeRange(NSNotFound, 0);
    NSRect firstLineRect = [self.layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphRange.location
                                                                    effectiveRange:&firstLineRange];
    if (NSMaxRange(glyphRange) <= NSMaxRange(firstLineRange)) {
      CGFloat leading = [self.layoutManager locationForGlyphAtIndex:glyphRange.location].x;
      CGFloat trailing = NSMaxRange(glyphRange) < NSMaxRange(firstLineRange) ?
        [self.layoutManager locationForGlyphAtIndex:NSMaxRange(glyphRange)].x : NSMaxX(firstLineRect);
      CGFloat height = NSHeight(firstLineRect);
      if (self.contentBlock == kLinearCandidateBlock &&
          NSMaxRange(firstLineRange) == self.layoutManager.numberOfGlyphs &&
          isnormal(self.defaultParagraphStyle.lineSpacing))
        height += self.defaultParagraphStyle.lineSpacing;
      return NSMakeRect(NSMinX(firstLineRect) + leading, NSMinY(firstLineRect), trailing - leading, height);
    } else {
      NSRange finalLineRange = NSMakeRange(NSNotFound, 0);
      NSRect finalLineRect = [self.layoutManager lineFragmentUsedRectForGlyphAtIndex:NSMaxRange(glyphRange) - 1
                                                                      effectiveRange:&finalLineRange];
      CGFloat containerWidth = NSWidth([self.layoutManager usedRectForTextContainer:self.textContainer]);
      CGFloat height = NSMaxY(finalLineRect) - NSMinY(firstLineRect);
      if (self.contentBlock == kLinearCandidateBlock &&
          NSMaxRange(finalLineRange) == self.layoutManager.numberOfGlyphs &&
          isnormal(self.defaultParagraphStyle.lineSpacing))
        height += self.defaultParagraphStyle.lineSpacing;
      return NSMakeRect(0.0, NSMinY(firstLineRect), containerWidth, height);
    }
  }
}

/** Calculate 3 rectangles enclosing the text in range. `textPolygon.head` & `.tail` are incomplete line fragments
    `textPolygon.body` is the complete line fragment in the middle if the range spans no less than one full line */
- (SquirrelTextPolygon)textPolygonForRange:(NSRange)charRange {
  SquirrelTextPolygon textPolygon =
    {.head = NSZeroRect, .body = NSZeroRect, .tail = NSZeroRect};
  if (charRange.location == NSNotFound)
    return textPolygon;
  if (@available(macOS 12.0, *)) {
    NSTextRange* textRange = [self textRangeFromCharRange:charRange];
    NSRect __block headLineRect = NSZeroRect;
    NSRect __block tailLineRect = NSZeroRect;
    NSTextRange* __block headLineRange;
    NSTextRange* __block tailLineRange;
    [self.textLayoutManager
     enumerateTextSegmentsInRange:textRange
     type:NSTextLayoutManagerSegmentTypeStandard
     options:NSTextLayoutManagerSegmentOptionsMiddleFragmentsExcluded
     usingBlock:^BOOL(NSTextRange* _Nullable segRange, CGRect segFrame,
                      CGFloat baseline, NSTextContainer* _Nonnull textContainer) {
      if (!CGRectIsEmpty(segFrame)) {
        if (NSIsEmptyRect(headLineRect) || CGRectGetMinY(segFrame) < nexttoward(NSMaxY(headLineRect), -INFINITY)) {
          headLineRect = NSUnionRect(segFrame, headLineRect);
          headLineRange = [headLineRange textRangeByFormingUnionWithTextRange:segRange];
        } else {
          tailLineRect = NSUnionRect(segFrame, tailLineRect);
          tailLineRange = [tailLineRange textRangeByFormingUnionWithTextRange:segRange];
        }
      }
      return YES;
    }];
    if (self.contentBlock == kLinearCandidateBlock && isnormal(self.defaultParagraphStyle.lineSpacing)) {
      headLineRect.size.height += self.defaultParagraphStyle.lineSpacing;
      if (!NSIsEmptyRect(tailLineRect))
        tailLineRect.size.height += self.defaultParagraphStyle.lineSpacing;
    }

    if (NSIsEmptyRect(tailLineRect)) {
      textPolygon.body = headLineRect;
    } else {
      CGFloat containerWidth = NSWidth(self.textLayoutManager.usageBoundsForTextContainer);
      headLineRect.size.width = containerWidth - NSMinX(headLineRect);
      if (fabs(NSMaxX(tailLineRect) - NSMaxX(headLineRect)) < 1) {
        if (fabs(NSMinX(headLineRect) - NSMinX(tailLineRect)) < 1) {
          textPolygon.body = NSUnionRect(headLineRect, tailLineRect);
        } else {
          textPolygon.head = headLineRect;
          textPolygon.body = NSMakeRect(0.0, NSMaxY(headLineRect), containerWidth,
                                        NSMaxY(tailLineRect) - NSMaxY(headLineRect));
        }
      } else {
        textPolygon.tail = tailLineRect;
        if (fabs(NSMinX(headLineRect) - NSMinX(tailLineRect)) < 1) {
          textPolygon.body = NSMakeRect(0.0, NSMinY(headLineRect), containerWidth,
                                        NSMinY(tailLineRect) - NSMinY(headLineRect));
        } else {
          textPolygon.head = headLineRect;
          if (![tailLineRange containsLocation:headLineRange.endLocation])
            textPolygon.body = NSMakeRect(0.0, NSMaxY(headLineRect), containerWidth,
                                          NSMinY(tailLineRect) - NSMaxY(headLineRect));
        }
      }
    }
  } else {
    NSRange glyphRange = [self.layoutManager glyphRangeForCharacterRange:charRange
                                                    actualCharacterRange:NULL];
    NSRange headLineRange = NSMakeRange(NSNotFound, 0);
    NSRect headLineRect = [self.layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphRange.location
                                                                   effectiveRange:&headLineRange];
    CGFloat leading = [self.layoutManager locationForGlyphAtIndex:glyphRange.location].x;
    if (NSMaxRange(headLineRange) >= NSMaxRange(glyphRange)) {
      CGFloat trailing = NSMaxRange(glyphRange) < NSMaxRange(headLineRange) ?
        [self.layoutManager locationForGlyphAtIndex:NSMaxRange(glyphRange)].x : NSMaxX(headLineRect);
      CGFloat height = NSHeight(headLineRect);
      if (self.contentBlock == kLinearCandidateBlock &&
          NSMaxRange(headLineRange) == self.layoutManager.numberOfGlyphs &&
          isnormal(self.defaultParagraphStyle.lineSpacing))
        height += self.defaultParagraphStyle.lineSpacing;
      textPolygon.body = NSMakeRect(leading, NSMinY(headLineRect), trailing - leading, height);
    } else {
      CGFloat containerWidth = NSWidth([self.layoutManager usedRectForTextContainer:self.textContainer]);
      NSRange tailLineRange = NSMakeRange(NSNotFound, 0);
      NSRect tailLineRect = [self.layoutManager lineFragmentUsedRectForGlyphAtIndex:NSMaxRange(glyphRange) - 1
                                                                     effectiveRange:&tailLineRange];
      if (self.contentBlock == kLinearCandidateBlock &&
          NSMaxRange(tailLineRange) == self.layoutManager.numberOfGlyphs &&
          isnormal(self.defaultParagraphStyle.lineSpacing))
        tailLineRect.size.height += self.defaultParagraphStyle.lineSpacing;
      CGFloat trailing = NSMaxRange(glyphRange) < NSMaxRange(tailLineRange) ?
        [self.layoutManager locationForGlyphAtIndex:NSMaxRange(glyphRange)].x : NSMaxX(tailLineRect);
      if (NSMaxRange(tailLineRange) == NSMaxRange(glyphRange)) {
        if (glyphRange.location == headLineRange.location) {
          textPolygon.body = NSMakeRect(0.0, NSMinY(headLineRect), containerWidth,
                                        NSMaxY(tailLineRect) - NSMinY(headLineRect));
        } else {
          textPolygon.head = NSMakeRect(leading, NSMinY(headLineRect),
                                        containerWidth - leading, NSHeight(headLineRect));
          textPolygon.body = NSMakeRect(0.0, NSMaxY(headLineRect), containerWidth,
                                        NSMaxY(tailLineRect) - NSMaxY(headLineRect));
        }
      } else {
        textPolygon.tail = NSMakeRect(0.0, NSMinY(tailLineRect),
                                      trailing, NSHeight(tailLineRect));
        if (glyphRange.location == headLineRange.location) {
          textPolygon.body = NSMakeRect(0.0, NSMinY(headLineRect), containerWidth,
                                        NSMinY(tailLineRect) - NSMinY(headLineRect));
        } else {
          textPolygon.head = NSMakeRect(leading, NSMinY(headLineRect),
                                        containerWidth - leading, NSHeight(headLineRect));
          if (tailLineRange.location > NSMaxRange(headLineRange))
            textPolygon.body = NSMakeRect(0.0, NSMaxY(headLineRect), containerWidth,
                                          NSMinY(tailLineRect) - NSMaxY(headLineRect));
        }
      }
    }
  }
  return textPolygon;
}

@end  // SquirrelTextView


NS_HEADER_AUDIT_BEGIN(nullability, sendability)
__attribute__((objc_direct_members))
@interface SquirrelView : NSView

@property(nonatomic, readonly, strong, nonnull) SquirrelTextView* candidateView;
@property(nonatomic, readonly, strong, nonnull) SquirrelTextView* preeditView;
@property(nonatomic, readonly, strong, nonnull) SquirrelTextView* pagingView;
@property(nonatomic, readonly, strong, nonnull) SquirrelTextView* statusView;
@property(nonatomic, readonly, strong, nonnull) NSScrollView* scrollView;
@property(nonatomic, readonly, strong, nonnull) NSFlippedView* documentView;
@property(nonatomic, readonly, strong, nonnull) NSTextStorage* candidateContents;
@property(nonatomic, readonly, strong, nonnull) NSTextStorage* preeditContents;
@property(nonatomic, readonly, strong, nonnull) NSTextStorage* pagingContents;
@property(nonatomic, readonly, strong, nonnull) NSTextStorage* statusContents;
@property(nonatomic, readonly, strong, nonnull) API_AVAILABLE(macos(10.14)) CAShapeLayer* shape;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* backImageLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* backColorLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* borderLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* documentLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* activePageLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* gridLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* nonHilitedCandidateLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* hilitedCandidateLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* clipLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* hilitedPreeditLayer;
@property(nonatomic, readonly, strong, nonnull) CAShapeLayer* functionButtonLayer;
@property(nonatomic, readonly, strong, nonnull) CALayer* logoLayer;
@property(nonatomic, readonly, nullable) SquirrelTabularIndex* tabularIndices;
@property(nonatomic, readonly, nullable) SquirrelTextPolygon* candidatePolygons;
@property(nonatomic, readonly, nullable) NSRectArray sectionRects;
@property(nonatomic, readonly, nullable) SquirrelCandidateInfo* candidateInfos;
@property(nonatomic, readonly) NSRect contentRect;
@property(nonatomic, readonly) NSRect documentRect;
@property(nonatomic, readonly) NSRect preeditRect;
@property(nonatomic, readonly) NSRect clipRect;
@property(nonatomic, readonly) NSRect pagingRect;
@property(nonatomic, readonly) NSRect deleteBackRect;
@property(nonatomic, readonly) NSRect expanderRect;
@property(nonatomic, readonly) NSRect pageUpRect;
@property(nonatomic, readonly) NSRect pageDownRect;
@property(nonatomic, readonly) CGFloat clippedHeight;
@property(nonatomic, readonly) SquirrelIndex functionButton;
@property(nonatomic, readonly) NSUInteger candidateCount;
@property(nonatomic, readonly) NSUInteger hilitedCandidate;
@property(nonatomic, readonly) NSRange hilitedPreeditRange;
@property(nonatomic, readonly) SquirrelStyle style;
@property(nonatomic) BOOL expanded;

- (void)estimateBoundsOnScreen:(NSRect)screen
                   withPreedit:(BOOL)hasPreedit
                    candidates:(SquirrelCandidateInfo* _Nullable)candidateInfos
                         count:(NSUInteger)candidateCount
                        paging:(BOOL)hasPaging;
- (void)layoutContents;
- (void)drawViewWithHilitedCandidate:(NSUInteger)hilitedCandidate
                 hilitedPreeditRange:(NSRange)hilitedPreeditRange;
- (void)setHilitedPreeditRange:(NSRange)hilitedPreeditRange;
- (void)highlightCandidate:(NSUInteger)hilitedCandidate;
- (void)highlightFunctionButton:(SquirrelIndex)functionButton;
- (SquirrelIndex)indexForMouseSpot:(NSPoint)spot;

@end
NS_HEADER_AUDIT_END(nullability, sendability)

@implementation SquirrelView

// Need flipped coordinate system, consistent with textView and textContainer
- (BOOL)isFlipped { return YES; }

- (BOOL)wantsUpdateLayer { return YES; }

- (void)setStyle:(SquirrelStyle)style {
  if (@available(macOS 10.14, *)) {
    if (_style != style) {
      _style = style;
      _scrollView.scrollerKnobStyle = style == kDarkStyle ? NSScrollerKnobStyleLight : NSScrollerKnobStyleDark;
      SquirrelTheme.currentStyle = style;
    }
  }
}

- (instancetype)init {
  if (self = [super init]) {
    _candidateContents = NSTextStorage.alloc.init;
    _preeditContents = NSTextStorage.alloc.init;
    _pagingContents = NSTextStorage.alloc.init;
    _statusContents = NSTextStorage.alloc.init;
    _candidateView = [SquirrelTextView.alloc initWithContentBlock:kStackedCandidateBlock storage:_candidateContents];
    _preeditView = [SquirrelTextView.alloc initWithContentBlock:kPreeditBlock storage:_preeditContents];
    _pagingView = [SquirrelTextView.alloc initWithContentBlock:kPagingBlock storage:_pagingContents];
    _statusView = [SquirrelTextView.alloc initWithContentBlock:kStatusBlock storage:_statusContents];

    _documentView = NSFlippedView.alloc.init;
    _documentView.wantsLayer = YES;
    _documentView.layer.geometryFlipped = YES;
    _documentView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    _documentView.autoresizesSubviews = NO;
    [_documentView addSubview:_candidateView];
    _scrollView = NSScrollView.alloc.init;
    _scrollView.documentView = _documentView;
    _scrollView.drawsBackground = NO;
    _scrollView.automaticallyAdjustsContentInsets = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.scrollerStyle = NSScrollerStyleOverlay;
    _scrollView.scrollerKnobStyle = NSScrollerKnobStyleDark;
    _scrollView.wantsLayer = YES;
    _scrollView.layer.geometryFlipped = YES;
    _scrollView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;

    _style = kDefaultStyle;
    if (@available(macOS 10.14, *)) {
      _shape = CAShapeLayer.alloc.init;
      _shape.fillColor = CGColorGetConstantColor(kCGColorWhite);
    }
    self.wantsLayer = YES;
    self.layer.geometryFlipped = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;

    _backImageLayer = CAShapeLayer.alloc.init;
    _backColorLayer = CAShapeLayer.alloc.init;
    _hilitedPreeditLayer = CAShapeLayer.alloc.init;
    _functionButtonLayer = CAShapeLayer.alloc.init;
    _logoLayer = CALayer.alloc.init;
    _borderLayer = CAShapeLayer.alloc.init;
    _backColorLayer.fillRule = kCAFillRuleEvenOdd;
    _borderLayer.fillRule = kCAFillRuleEvenOdd;
    _backImageLayer.actions = @{@"transform": NSNull.null};
    self.layer.actions = @{@"sublayers": NSNull.null};
    [self.layer addSublayer:_backImageLayer];
    [self.layer addSublayer:_backColorLayer];
    [self.layer addSublayer:_hilitedPreeditLayer];
    [self.layer addSublayer:_functionButtonLayer];
    [self.layer addSublayer:_logoLayer];
    [self.layer addSublayer:_borderLayer];

    _documentLayer = CAShapeLayer.alloc.init;
    _activePageLayer = CAShapeLayer.alloc.init;
    _gridLayer = CAShapeLayer.alloc.init;
    _clipLayer = CAShapeLayer.alloc.init;
    _nonHilitedCandidateLayer = CAShapeLayer.alloc.init;
    _hilitedCandidateLayer = CAShapeLayer.alloc.init;
    _documentLayer.allowsGroupOpacity = YES;
    _documentLayer.fillRule = kCAFillRuleEvenOdd;
    _activePageLayer.fillRule = kCAFillRuleEvenOdd;
    _gridLayer.lineCap = kCALineCapRound;
    _gridLayer.lineWidth = 1.0;
    _clipLayer.fillColor = CGColorGetConstantColor(kCGColorWhite);
    _documentView.layer.actions = @{@"sublayers": NSNull.null};
    [_documentView.layer addSublayer:_documentLayer];
    [_documentLayer addSublayer:_activePageLayer];
    [_documentView.layer addSublayer:_gridLayer];
    [_documentView.layer addSublayer:_nonHilitedCandidateLayer];
    [_documentView.layer addSublayer:_hilitedCandidateLayer];
    _scrollView.layer.mask = _clipLayer;
  }
  return self;
}

static BOOL anyTruncated(SquirrelCandidateInfo* array, NSUInteger count) {
  for (NSUInteger i = 0; i < count; ++i)
    if (array[i].truncated)
      return YES;
  return NO;
}

- (void)estimateBoundsOnScreen:(NSRect)screen
                   withPreedit:(BOOL)hasPreedit
                    candidates:(SquirrelCandidateInfo*)candidateInfos
                         count:(NSUInteger)candidateCount
                        paging:(BOOL)hasPaging {
  _candidateInfos = candidateInfos;
  _candidateCount = candidateCount;
  _preeditView.hidden = !hasPreedit;
  _scrollView.hidden = candidateCount == 0;
  _pagingView.hidden = !hasPaging;
  _statusView.hidden = hasPreedit || candidateCount > 0;

  // layout textviews and get their sizes
  _preeditRect = NSZeroRect;
  _documentRect = NSZeroRect; // in textView's own coordinates
  _clipRect = NSZeroRect;
  _pagingRect = NSZeroRect;
  _clippedHeight = 0.0;
  if (!hasPreedit && candidateCount == 0) {  // status
    _contentRect = _statusView.layoutText;
    return;
  }
  if (hasPreedit) {
    _preeditRect = _preeditView.layoutText;
    _contentRect = _preeditRect;
  }
  if (candidateCount > 0) {
    _documentRect = _candidateView.layoutText;
    _documentRect.size.height += SquirrelTheme.currentTheme.lineSpacing;
    if (SquirrelTheme.currentTheme.linear && !anyTruncated(candidateInfos, candidateCount))
      _documentRect.size.width -= SquirrelTheme.currentTheme.fullWidth;
    _clipRect = _documentRect;
    if (hasPreedit) {
      _clipRect.origin.y = NSMaxY(_preeditRect) + SquirrelTheme.currentTheme.preeditSpacing;
      _contentRect = NSUnionRect(_preeditRect, _clipRect);
    } else {
      _contentRect = _clipRect;
    }
    _clipRect.size.width += SquirrelTheme.currentTheme.fullWidth;
    if (hasPaging) {
      _pagingRect = _pagingView.layoutText;
      _pagingRect.origin.y = NSMaxY(_clipRect);
      _contentRect = NSUnionRect(_contentRect, _pagingRect);
    }
  } else {
    return;
  }
  // clip candidate block if it has too many lines
  CGFloat maxHeight = (SquirrelTheme.currentTheme.vertical ? NSWidth(screen) : NSHeight(screen)) * 0.5 -
                       SquirrelTheme.currentTheme.borderInsets.height * 2;
  _clippedHeight = fdim(ceil(NSHeight(_contentRect)), ceil(maxHeight));
  _contentRect.size.height -= _clippedHeight;
  _clipRect.size.height -= _clippedHeight;
  _scrollView.verticalScroller.knobProportion = NSHeight(_clipRect) / NSHeight(_documentRect);
}

// Get the rectangle containing entire contents
- (void)layoutContents {
  NSPoint origin = NSMakePoint(SquirrelTheme.currentTheme.borderInsets.width,
                               SquirrelTheme.currentTheme.borderInsets.height);
  if (!_statusView.hidden) {  // status
    _contentRect.origin = NSMakePoint(origin.x + ceil(SquirrelTheme.currentTheme.fullWidth * 0.5),
                                      origin.y);
    return;
  }
  if (!_preeditView.hidden) {
    _preeditRect = _preeditView.layoutText;
    _preeditRect.size.width += SquirrelTheme.currentTheme.fullWidth;
    _preeditRect.origin = origin;
    _contentRect = _preeditRect;
  }
  if (!_scrollView.hidden) {
    if (!_preeditView.hidden) {
      _clipRect.origin.x = origin.x;
      _clipRect.origin.y = NSMaxY(_preeditRect) + SquirrelTheme.currentTheme.preeditSpacing;
      _contentRect = NSUnionRect(_preeditRect, _clipRect);
    } else {
      _clipRect.origin = origin;
      _contentRect = _clipRect;
    }
    if (!_pagingView.hidden) {
      _pagingRect = _pagingView.layoutText;
      _pagingRect.size.width += SquirrelTheme.currentTheme.fullWidth;
      _pagingRect.origin.x = origin.x;
      _pagingRect.origin.y = NSMaxY(_clipRect);
      _contentRect = NSUnionRect(_contentRect, _pagingRect);
    }
  }
  _contentRect.size.width -= SquirrelTheme.currentTheme.fullWidth;
  _contentRect.origin.x += ceil(SquirrelTheme.currentTheme.fullWidth * 0.5);
}

// Will triger `- (void)updateLayer`
- (void)drawViewWithHilitedCandidate:(NSUInteger)hilitedCandidate
                 hilitedPreeditRange:(NSRange)hilitedPreeditRange {
  _hilitedCandidate = hilitedCandidate;
  _hilitedPreeditRange = hilitedPreeditRange;
  _functionButton = kVoidSymbol;
  self.needsDisplayInRect = self.bounds;
  if (!_statusView.hidden) {
    _statusView.needsDisplayInRect = _statusView.bounds;
  } else {
    if (!_preeditView.hidden)
      _preeditView.needsDisplayInRect = _preeditView.bounds;
    if (!_scrollView.hidden)
      _candidateView.needsDisplayInRect = [_documentView convertRect:_documentView.bounds
                                                              toView:_candidateView];
    if (!_pagingView.hidden)
      _pagingView.needsDisplayInRect = _pagingView.bounds;
  }
  [self layoutContents];
}

- (void)setHilitedPreeditRange:(NSRange)hilitedPreeditRange {
  _hilitedPreeditRange = hilitedPreeditRange;
  self.needsDisplayInRect = _preeditRect;
  _preeditView.needsDisplayInRect = _preeditView.bounds;
  [self layoutContents];
}

- (void)highlightCandidate:(NSUInteger)hilitedCandidate {
  if (_expanded) {
    NSUInteger priorActivePage = _hilitedCandidate / SquirrelTheme.currentTheme.pageSize;
    NSUInteger newActivePage = hilitedCandidate / SquirrelTheme.currentTheme.pageSize;
    if (newActivePage != priorActivePage) {
      self.needsDisplayInRect = [_documentView convertRect:_sectionRects[priorActivePage]
                                                    toView:self];
      _candidateView.needsDisplayInRect = [_documentView convertRect:_sectionRects[priorActivePage]
                                                              toView:_candidateView];
    }
    self.needsDisplayInRect = [_documentView convertRect:_sectionRects[newActivePage]
                                                  toView:self];
    _candidateView.needsDisplayInRect = [_documentView convertRect:_sectionRects[newActivePage]
                                                            toView:_candidateView];
  } else {
    self.needsDisplayInRect = _clipRect;
    _candidateView.needsDisplayInRect = [_documentView convertRect:_documentView.bounds
                                                            toView:_candidateView];
  }
  _hilitedCandidate = hilitedCandidate;
  [self unclipHighlightedCandidate];
}

- (void)unclipHighlightedCandidate {
  if (!isnormal(_clippedHeight))
    return;
  if (_expanded) {
    NSUInteger activePage = _hilitedCandidate / SquirrelTheme.currentTheme.pageSize;
    if (NSMinY(_sectionRects[activePage]) < nexttoward(NSMinY(_scrollView.documentVisibleRect), -INFINITY)) {
      NSPoint origin = _scrollView.contentView.bounds.origin;
      origin.y -= NSMinY(_scrollView.documentVisibleRect) - NSMinY(_sectionRects[activePage]);
      [_scrollView.contentView scrollToPoint:origin];
      _scrollView.verticalScroller.doubleValue = NSMinY(_scrollView.documentVisibleRect) / _clippedHeight;
    } else if (NSMaxY(_sectionRects[activePage]) > nexttoward(NSMaxY(_scrollView.documentVisibleRect), INFINITY)) {
      NSPoint origin = _scrollView.contentView.bounds.origin;
      origin.y += NSMaxY(_sectionRects[activePage]) - NSMaxY(_scrollView.documentVisibleRect);
      [_scrollView.contentView scrollToPoint:origin];
      _scrollView.verticalScroller.doubleValue = NSMinY(_scrollView.documentVisibleRect) / _clippedHeight;
    }
  } else {
    if (NSMinY(_scrollView.documentVisibleRect) > nexttoward(_candidatePolygons[_hilitedCandidate].minY(), INFINITY)) {
      NSPoint origin = _scrollView.contentView.bounds.origin;
      origin.y -= NSMinY(_scrollView.documentVisibleRect) - _candidatePolygons[_hilitedCandidate].minY();
      [_scrollView.contentView scrollToPoint:origin];
      _scrollView.verticalScroller.doubleValue = NSMinY(_scrollView.documentVisibleRect) / _clippedHeight;
    } else if (NSMaxY(_scrollView.documentVisibleRect) < nexttoward(_candidatePolygons[_hilitedCandidate].maxY(), -INFINITY)) {
      NSPoint origin = _scrollView.contentView.bounds.origin;
      origin.y += _candidatePolygons[_hilitedCandidate].maxY() - NSMaxY(_scrollView.documentVisibleRect);
      [_scrollView.contentView scrollToPoint:origin];
      _scrollView.verticalScroller.doubleValue = NSMinY(_scrollView.documentVisibleRect) / _clippedHeight;
    }
  }
}

- (void)highlightFunctionButton:(SquirrelIndex)functionButton {
  for (SquirrelIndex index : (SquirrelIndex[2]){_functionButton, functionButton}) {
    switch (index) {
      case kBackSpaceKey:
      case kEscapeKey:
        self.needsDisplayInRect = _deleteBackRect;
        [_preeditView setNeedsDisplayInRect:[self convertRect:_deleteBackRect toView:_preeditView]
                      avoidAdditionalLayout:YES];
        break;
      case kPageUpKey:
      case kHomeKey:
        self.needsDisplayInRect = _pageUpRect;
        [_pagingView setNeedsDisplayInRect:[self convertRect:_pageUpRect toView:_pagingView]
                     avoidAdditionalLayout:YES];
        break;
      case kPageDownKey:
      case kEndKey:
        self.needsDisplayInRect = _pageDownRect;
        [_pagingView setNeedsDisplayInRect:[self convertRect:_pageDownRect toView:_pagingView]
                     avoidAdditionalLayout:YES];
        break;
      case kExpandButton:
      case kCompressButton:
      case kLockButton:
        self.needsDisplayInRect = _expanderRect;
        [_pagingView setNeedsDisplayInRect:[self convertRect:_expanderRect toView:_pagingView]
                     avoidAdditionalLayout:YES];
        break;
      default:
        break;
    }
  }
  _functionButton = functionButton;
}

- (NSBezierPath*)updateFunctionButtonLayer {
  NSColor* buttonColor;
  NSRect buttonRect = NSZeroRect;
  switch (_functionButton) {
    case kPageUpKey:
      buttonColor = SquirrelTheme.currentTheme.hilitedPreeditBackColor.hooverColor;
      buttonRect = _pageUpRect;
      break;
    case kHomeKey:
      buttonColor = SquirrelTheme.currentTheme.hilitedPreeditBackColor.disabledColor;
      buttonRect = _pageUpRect;
      break;
    case kPageDownKey:
      buttonColor = SquirrelTheme.currentTheme.hilitedPreeditBackColor.hooverColor;
      buttonRect = _pageDownRect;
      break;
    case kEndKey:
      buttonColor = SquirrelTheme.currentTheme.hilitedPreeditBackColor.disabledColor;
      buttonRect = _pageDownRect;
      break;
    case kExpandButton:
    case kCompressButton:
    case kLockButton:
      buttonColor = SquirrelTheme.currentTheme.hilitedPreeditBackColor.hooverColor;
      buttonRect = _expanderRect;
      break;
    case kBackSpaceKey:
      buttonColor = SquirrelTheme.currentTheme.hilitedPreeditBackColor.hooverColor;
      buttonRect = _deleteBackRect;
      break;
    case kEscapeKey:
      buttonColor = SquirrelTheme.currentTheme.hilitedPreeditBackColor.disabledColor;
      buttonRect = _deleteBackRect;
      break;
    default:
      break;
  }
  if (!NSIsEmptyRect(buttonRect) && buttonColor) {
    CGFloat cornerRadius = fmin(SquirrelTheme.currentTheme.hilitedCornerRadius, NSHeight(buttonRect) * 0.5);
    NSBezierPath* buttonPath = [NSBezierPath squirclePathForRect:buttonRect cornerRadius:cornerRadius];
    _functionButtonLayer.path = buttonPath.quartzPath;
    _functionButtonLayer.fillColor = buttonColor.CGColor;
    if (isnormal(SquirrelTheme.currentTheme.shadowSize)) {
      _functionButtonLayer.shadowOffset = CGSizeMake(SquirrelTheme.currentTheme.shadowSize, SquirrelTheme.currentTheme.shadowSize);
      _functionButtonLayer.shadowOpacity = 1.0;
      _functionButtonLayer.shadowColor = [buttonColor shadowWithLevel:0.7].CGColor;
    } else {
      _functionButtonLayer.shadowOpacity = 0.0;
    }
    _functionButtonLayer.hidden = NO;
    return buttonPath;
  } else {
    _functionButtonLayer.hidden = YES;
    return nil;
  }
}

// All draws happen here
- (void)updateLayer {
  SquirrelTheme* theme = SquirrelTheme.currentTheme;
  NSRect panelRect = self.bounds;
  NSRect backgroundRect = NSInsetRect(panelRect, theme.borderInsets.width,
                                                 theme.borderInsets.height);
  backgroundRect = [self backingAlignedRect:backgroundRect options:NSAlignAllEdgesNearest];
  CGFloat hilitedCornerRadius = fmin(theme.hilitedCornerRadius,
                                     theme.candidateParagraphStyle.minimumLineHeight * 0.5);

  /* Preedit */
  _deleteBackRect = NSZeroRect;
  NSBezierPath* hilitedPreeditPath;
  if (!_preeditView.hidden) {
    _preeditRect.origin = backgroundRect.origin;
    _preeditRect.size.width = NSWidth(backgroundRect);
    _preeditRect = [self backingAlignedRect:_preeditRect options:NSAlignAllEdgesNearest];
    // Draw the highlighted part of preedit text
    if (_hilitedPreeditRange.length > 0 && theme.hilitedPreeditBackColor) {
      CGFloat padding = ceil(theme.preeditParagraphStyle.minimumLineHeight * 0.05);
      NSRect innerBox = _preeditRect;
      innerBox.origin.x += ceil(theme.fullWidth * 0.5) - padding;
      innerBox.size.width = NSWidth(backgroundRect) - theme.fullWidth + padding * 2;
      innerBox = [self backingAlignedRect:innerBox options:NSAlignAllEdgesNearest];
      SquirrelTextPolygon textPolygon = [_preeditView textPolygonForRange:_hilitedPreeditRange];
      if (!NSIsEmptyRect(textPolygon.head)) {
        textPolygon.head.origin.x += theme.borderInsets.width + ceil(theme.fullWidth * 0.5) - padding;
        textPolygon.head.origin.y += theme.borderInsets.height;
        textPolygon.head.size.width += padding * 2;
        textPolygon.head = [self backingAlignedRect:NSIntersectionRect(textPolygon.head, innerBox)
                                            options:NSAlignAllEdgesNearest];
      }
      if (!NSIsEmptyRect(textPolygon.body)) {
        textPolygon.body.origin.x += theme.borderInsets.width + ceil(theme.fullWidth * 0.5) - padding;
        textPolygon.body.origin.y += theme.borderInsets.height;
        textPolygon.body.size.width += padding;
        if (!NSIsEmptyRect(textPolygon.tail) ||
            NSMaxRange(_hilitedPreeditRange) + 2 == _preeditContents.length)
          textPolygon.body.size.width += padding;
        if (NSMaxX(textPolygon.body) > NSMaxX(innerBox) - 2)
          textPolygon.body.size.width = NSMaxX(innerBox) - NSMinX(textPolygon.body);
        textPolygon.body = [self backingAlignedRect:NSIntersectionRect(textPolygon.body, innerBox)
                                            options:NSAlignAllEdgesNearest];
      }
      if (!NSIsEmptyRect(textPolygon.tail)) {
        textPolygon.tail.origin.x += theme.borderInsets.width + ceil(theme.fullWidth * 0.5) - padding;
        textPolygon.tail.origin.y += theme.borderInsets.height;
        textPolygon.tail.size.width += padding;
        if (NSMaxRange(_hilitedPreeditRange) + 2 == _preeditContents.length)
          textPolygon.tail.size.width += padding;
        textPolygon.tail = [self backingAlignedRect:NSIntersectionRect(textPolygon.tail, innerBox)
                                            options:NSAlignAllEdgesNearest];
      }
      CGFloat cornerRadius = fmin(hilitedCornerRadius, fabs([theme.preeditAttrs[NSFontAttributeName] descender]));
      hilitedPreeditPath = [NSBezierPath squirclePathForPolygon:textPolygon cornerRadius:cornerRadius];
    }
    _deleteBackRect = [_preeditView blockRectForRange:NSMakeRange(_preeditContents.length - 1, 1)];
    _deleteBackRect.size.width += theme.fullWidth;
    _deleteBackRect.origin.x = NSMaxX(_preeditRect) - NSWidth(_deleteBackRect);
    _deleteBackRect.origin.y = NSMaxY(_preeditRect) - NSHeight(_deleteBackRect);
    _deleteBackRect = [self backingAlignedRect:NSIntersectionRect(_deleteBackRect, _preeditRect)
                                       options:NSAlignAllEdgesNearest];
  }

  /* Candidates (in documentView coordinates, except for `clipRect`) */
  _candidatePolygons = new SquirrelTextPolygon[_candidateCount];
  _sectionRects = new NSRect[theme.tabular ? _candidateCount / theme.pageSize + 1 : 0];
  _tabularIndices = new SquirrelTabularIndex[theme.tabular ? _candidateCount : 0];
  NSBezierPath* clipPath;
  NSBezierPath* documentPath;
  NSBezierPath* gridPath;
  if (!_scrollView.hidden) {
    _clipRect.size.width = NSWidth(backgroundRect);
    _clipRect = [self backingAlignedRect:NSIntersectionRect(_clipRect, backgroundRect)
                                 options:NSAlignAllEdgesNearest];
    _documentRect.size.width = NSWidth(backgroundRect);
    _documentRect = [_documentView backingAlignedRect:_documentRect
                                              options:NSAlignAllEdgesNearest];
    clipPath = [NSBezierPath squirclePathForRect:_clipRect cornerRadius:hilitedCornerRadius];
    documentPath = [NSBezierPath squirclePathForRect:_documentRect cornerRadius:hilitedCornerRadius];
    // Store candidate enclosing polygons and draw the ones highlighted
    if (theme.linear) {  // linear layout
      CGFloat gridOriginY;
      CGFloat tabInterval;
      NSUInteger lineNum = 0;
      NSRect sectionRect = _documentRect;
      if (theme.tabular) {
        gridPath = NSBezierPath.bezierPath;
        gridOriginY = NSMinY(_documentRect);
        tabInterval = theme.fullWidth * 2;
        sectionRect.size.height = 0;
      }
      for (NSUInteger i = 0; i < _candidateCount; ++i) {
        SquirrelTextPolygon candidatePolygon = [_candidateView textPolygonForRange:_candidateInfos[i].candidateRange()];
        if (!NSIsEmptyRect(candidatePolygon.head)) {
          candidatePolygon.head.size.width += theme.fullWidth;
          candidatePolygon.head = [_documentView backingAlignedRect:NSIntersectionRect(candidatePolygon.head, _documentRect)
                                                            options:NSAlignAllEdgesNearest];
        }
        if (!NSIsEmptyRect(candidatePolygon.tail))
          candidatePolygon.tail = [_documentView backingAlignedRect:NSIntersectionRect(candidatePolygon.tail, _documentRect)
                                                            options:NSAlignAllEdgesNearest];
        if (!NSIsEmptyRect(candidatePolygon.body)) {
          if (_candidateInfos[i].truncated)
            candidatePolygon.body.size.width = NSWidth(_documentRect);
          else if (!NSIsEmptyRect(candidatePolygon.tail))
            candidatePolygon.body.size.width += theme.fullWidth;
          else if (NSMaxX(candidatePolygon.body) > NSMaxX(_documentRect) - 2)
            candidatePolygon.body.size.width = NSMaxX(_documentRect) - NSMinX(candidatePolygon.body);
          candidatePolygon.body = [_documentView backingAlignedRect:NSIntersectionRect(candidatePolygon.body, _documentRect)
                                                            options:NSAlignAllEdgesNearest];
        }
        if (theme.tabular) {
          if (_expanded) {
            if (_candidateInfos[i].col == 0)
              sectionRect.origin.y = ceil(NSMaxY(sectionRect));
            if (_candidateInfos[i].col == theme.pageSize - 1 || i == _candidateCount - 1) {
              sectionRect.size.height = ceil(candidatePolygon.maxY()) - NSMinY(sectionRect);
              NSUInteger sec = i / theme.pageSize;
              _sectionRects[sec] = sectionRect;
            }
          }
          CGFloat bottomEdge = candidatePolygon.maxY();
          if (fabs(bottomEdge - gridOriginY) > 2) {
             lineNum += i > 0 ? 1 : 0;
            // horizontal border except for the last line
            if (bottomEdge < NSMaxY(_documentRect) - 2) {
              [gridPath moveToPoint:NSMakePoint(theme.fullWidth * 0.5, bottomEdge)];
              [gridPath lineToPoint:NSMakePoint(NSMaxX(_documentRect) - theme.fullWidth * 0.5, bottomEdge)];
            }
            gridOriginY = bottomEdge;
          }
          NSPoint leadOrigin = candidatePolygon.origin();
          NSUInteger leadTabColumn = (NSUInteger)round((leadOrigin.x - NSMinX(_documentRect)) / tabInterval);
          _tabularIndices[i] = (SquirrelTabularIndex){.index = i, .lineNum = lineNum, .tabNum = leadTabColumn};
        }
        _candidatePolygons[i] = candidatePolygon;
      }
    } else {  // stacked layout
      for (NSUInteger i = 0; i < _candidateCount; ++i) {
        NSRect candidateRect = [_candidateView blockRectForRange:_candidateInfos[i].candidateRange()];
        candidateRect.size.width = NSWidth(_documentRect);
        candidateRect.size.height += theme.lineSpacing;
        candidateRect = [_documentView backingAlignedRect:NSIntersectionRect(candidateRect, _documentRect)
                                                  options:NSAlignAllEdgesNearest];
        _candidatePolygons[i] = (SquirrelTextPolygon){NSZeroRect, candidateRect, NSZeroRect};
      }
    }
  }

  /* Paging */
  _pageUpRect = NSZeroRect;
  _pageDownRect = NSZeroRect;
  _expanderRect = NSZeroRect;
  if (!_pagingView.hidden) {
    if (theme.linear)
      _pagingRect.origin.x = NSMaxX(backgroundRect) - NSWidth(_pagingRect);
    else
      _pagingRect.size.width = NSWidth(backgroundRect);
    _pagingRect = [self backingAlignedRect:NSIntersectionRect(_pagingRect, backgroundRect)
                                   options:NSAlignAllEdgesNearest];
    if (theme.showPaging) {
      _pageUpRect = NSOffsetRect([_pagingView blockRectForRange:NSMakeRange(0, 1)],
                                 NSMinX(_pagingRect), NSMinY(_pagingRect));
      _pageDownRect = NSOffsetRect([_pagingView blockRectForRange:NSMakeRange(_pagingContents.length - 1, 1)],
                                   NSMinX(_pagingRect), NSMinY(_pagingRect));
      _pageDownRect.size.width += theme.fullWidth;
      // bypass the bug of getting wrong glyph position when tab is presented
      _pageUpRect.size = _pageDownRect.size;
      _pageUpRect = [self backingAlignedRect:NSIntersectionRect(_pageUpRect, _pagingRect)
                                     options:NSAlignAllEdgesNearest];
      _pageDownRect = [self backingAlignedRect:NSIntersectionRect(_pageDownRect, _pagingRect)
                                       options:NSAlignAllEdgesNearest];
    }
    if (theme.tabular) {
      _expanderRect = NSOffsetRect([_pagingView blockRectForRange:NSMakeRange(_pagingContents.length / 2, 1)],
                                   NSMinX(_pagingRect), NSMinY(_pagingRect));
      _expanderRect.size.width += theme.fullWidth;
      _expanderRect = [self backingAlignedRect:NSIntersectionRect(_expanderRect, _pagingRect)
                                       options:NSAlignAllEdgesNearest];
    }
  }

  /* Border */
  CGFloat outerCornerRadius = fmin(theme.cornerRadius, NSHeight(panelRect) * 0.5);
  CGFloat innerCornerRadius = clamp(hilitedCornerRadius,
                                    outerCornerRadius - fmin(theme.borderInsets.width, theme.borderInsets.height),
                                    NSHeight(backgroundRect) * 0.5);
  NSBezierPath* panelPath;
  NSBezierPath* backgroundPath;
  if (!theme.linear || _pagingView.hidden) {
    panelPath = [NSBezierPath squirclePathForRect:panelRect cornerRadius:outerCornerRadius];
    backgroundPath = [NSBezierPath squirclePathForRect:backgroundRect cornerRadius:innerCornerRadius];
  } else {
    NSRect mainPanelRect = panelRect;
    mainPanelRect.size.height -= NSHeight(_pagingRect);
    NSRect tailPanelRect = NSInsetRect(NSOffsetRect(_pagingRect, 0, theme.borderInsets.height),
                                       -theme.borderInsets.width, 0);
    panelPath = [NSBezierPath squirclePathForPolygon:(SquirrelTextPolygon){mainPanelRect, tailPanelRect, NSZeroRect}
                                        cornerRadius:outerCornerRadius];
    NSRect mainBackgroundRect = backgroundRect;
    mainBackgroundRect.size.height -= NSHeight(_pagingRect);
    backgroundPath = [NSBezierPath squirclePathForPolygon:(SquirrelTextPolygon){mainBackgroundRect, _pagingRect, NSZeroRect}
                                             cornerRadius:innerCornerRadius];
  }
  NSBezierPath* borderPath = panelPath.copy;
  [borderPath appendBezierPath:backgroundPath];

  NSAffineTransform* flip = NSAffineTransform.transform;
  [flip translateXBy:0 yBy:NSHeight(panelRect)];
  [flip scaleXBy:1 yBy:-1];
  NSBezierPath* shapePath = [flip transformBezierPath:panelPath];

  /* Draw into layers */
  if (@available(macOS 10.14, *))
    _shape.path = shapePath.quartzPath;
  // highlighted preedit layer
  if (hilitedPreeditPath != nil && theme.hilitedPreeditBackColor != nil) {
    _hilitedPreeditLayer.path = hilitedPreeditPath.quartzPath;
    _hilitedPreeditLayer.fillColor = theme.hilitedPreeditBackColor.CGColor;
    _hilitedPreeditLayer.hidden = NO;
  } else {
    _hilitedPreeditLayer.hidden = YES;
  }
  // highlighted candidate layer
  if (!_scrollView.hidden) {
    _clipLayer.path = [NSBezierPath squirclePathForRect:_scrollView.bounds cornerRadius:hilitedCornerRadius].quartzPath;
    NSBezierPath* activePagePath;
    if (_expanded) {
      NSRect activePageRect = _sectionRects[_hilitedCandidate / theme.pageSize];
      activePagePath = [NSBezierPath squirclePathForRect:activePageRect cornerRadius:hilitedCornerRadius];
      [documentPath appendBezierPath:activePagePath];
    }
    if (theme.candidateBackColor != nil) {
      NSBezierPath* nonHilitedCandidatePath = NSBezierPath.bezierPath;
      BOOL stackColors = theme.stackColors && theme.candidateBackColor.alphaComponent < nexttoward(1.0, 0.0);
      for (NSUInteger i = 0; i < _candidateCount; ++i) {
        if (i != _hilitedCandidate) {
          NSBezierPath* candidatePath = theme.linear
          ? [NSBezierPath squirclePathForPolygon:_candidatePolygons[i] cornerRadius:hilitedCornerRadius]
          : [NSBezierPath squirclePathForRect:_candidatePolygons[i].body cornerRadius:hilitedCornerRadius];
          [nonHilitedCandidatePath appendBezierPath:candidatePath];
          if (stackColors)
            [(_expanded && i / theme.pageSize == _hilitedCandidate / theme.pageSize
              ? activePagePath : documentPath) appendBezierPath:candidatePath];
        }
      }
      _nonHilitedCandidateLayer.path = nonHilitedCandidatePath.quartzPath;
      _nonHilitedCandidateLayer.fillColor = theme.candidateBackColor.CGColor;
      _nonHilitedCandidateLayer.hidden = NO;
    } else {
      _nonHilitedCandidateLayer.hidden = YES;
    }
    if (_hilitedCandidate != NSNotFound && theme.hilitedCandidateBackColor != nil) {
      NSBezierPath* hilitedCandidatePath = theme.linear
      ? [NSBezierPath squirclePathForPolygon:_candidatePolygons[_hilitedCandidate] cornerRadius:hilitedCornerRadius]
      : [NSBezierPath squirclePathForRect:_candidatePolygons[_hilitedCandidate].body cornerRadius:hilitedCornerRadius];
      if (theme.stackColors && theme.hilitedCandidateBackColor.alphaComponent < nexttoward(1.0, 0.0))
        [(_expanded ? activePagePath : documentPath) appendBezierPath:hilitedCandidatePath];
      _hilitedCandidateLayer.path = hilitedCandidatePath.quartzPath;
      _hilitedCandidateLayer.fillColor = theme.hilitedCandidateBackColor.CGColor;
      _hilitedCandidateLayer.hidden = NO;
      if (isnormal(theme.shadowSize)) {
        _hilitedCandidateLayer.shadowOffset = CGSizeMake(theme.shadowSize, theme.shadowSize);
        _hilitedCandidateLayer.shadowOpacity = 1.0;
        _hilitedCandidateLayer.shadowColor = [theme.hilitedCandidateBackColor shadowWithLevel:0.7].CGColor;
      } else {
        _hilitedCandidateLayer.shadowOpacity = 0.0;
      }
    } else {
      _hilitedCandidateLayer.hidden = YES;
    }
    if (_expanded) {
      _activePageLayer.path = activePagePath.quartzPath;
      _activePageLayer.fillColor = theme.backColor.hooverColor.CGColor;
      _activePageLayer.hidden = NO;
    } else {
      _activePageLayer.hidden = YES;
    }
    _documentLayer.path = documentPath.quartzPath;
    _documentLayer.fillColor = theme.backColor.CGColor;
    if (gridPath != nil) {
      _gridLayer.path = gridPath.quartzPath;
      _gridLayer.strokeColor = [theme.commentForeColor
                                blendedColorWithFraction:0.8
                                ofColor:theme.backColor].CGColor;
      _gridLayer.hidden = NO;
    } else {
      _gridLayer.hidden = YES;
    }
  }
  // function buttons (page up, page down, backspace) layer
  NSBezierPath* functionButtonPath;
  if (_functionButton != kVoidSymbol)
    functionButtonPath = [self updateFunctionButtonLayer];
  else
    _functionButtonLayer.hidden = YES;
  // logo at the beginning for status message
  if (!_statusView.hidden) {
    _logoLayer.contentsScale = [_logoLayer.contents recommendedLayerContentsScale:
                                self.window.backingScaleFactor];
    _logoLayer.hidden = NO;
  } else {
    _logoLayer.hidden = YES;
  }
  // background image (pattern style) layer
  if (theme.backImage != nil && theme.backImage.valid) {
    NSAffineTransform* transform = NSAffineTransform.transform;
    if (theme.vertical)
      [transform rotateByDegrees:90.0];
    [transform translateXBy:-NSMinX(backgroundRect) yBy:-NSMinY(backgroundRect)];
    _backImageLayer.path = [transform transformBezierPath:backgroundPath].quartzPath;
    _backImageLayer.affineTransform = CGAffineTransformInvert(transform.transformMatrix);
    _backImageLayer.hidden = NO;
  } else {
    _backImageLayer.hidden = YES;
  }
  // background color layer
  if (!_statusView.hidden || !NSIsEmptyRect(_preeditRect) || !NSIsEmptyRect(_pagingRect)) {
    if (clipPath != nil) {
      NSBezierPath* nonCandidatePath = backgroundPath.copy;
      [nonCandidatePath appendBezierPath:clipPath];
      if (theme.stackColors && theme.hilitedPreeditBackColor != nil &&
          theme.hilitedPreeditBackColor.alphaComponent < nexttoward(1.0, 0.0)) {
        if (hilitedPreeditPath != nil)
          [nonCandidatePath appendBezierPath:hilitedPreeditPath];
        if (functionButtonPath != nil)
          [nonCandidatePath appendBezierPath:functionButtonPath];
      }
      _backColorLayer.path = nonCandidatePath.quartzPath;
    } else {
      _backColorLayer.path = backgroundPath.quartzPath;
    }
    _backColorLayer.fillColor = (theme.preeditBackColor ? : theme.backColor).CGColor;
    _backColorLayer.hidden = NO;
  } else {
    _backColorLayer.hidden = YES;
  }
  // border layer
  _borderLayer.path = borderPath.quartzPath;
  _borderLayer.fillColor = (theme.borderColor ? : theme.backColor).CGColor;

  [self unclipHighlightedCandidate];
}

- (SquirrelIndex)indexForMouseSpot:(NSPoint)spot {
  if (NSMouseInRect(spot, self.bounds, YES)) {
    if (NSMouseInRect(spot, _preeditRect, YES))
      return NSMouseInRect(spot, _deleteBackRect, YES) ? kBackSpaceKey : kCodeInputArea;
    if (NSMouseInRect(spot, _expanderRect, YES))
      return kExpandButton;
    if (NSMouseInRect(spot, _pageUpRect, YES))
      return kPageUpKey;
    if (NSMouseInRect(spot, _pageDownRect, YES))
      return kPageDownKey;
    if (NSMouseInRect(spot, _clipRect, YES)) {
      spot = [self convertPoint:spot toView:_documentView];
      for (NSUInteger i = 0; i < _candidateCount; ++i) {
        if (_candidatePolygons[i].mouseInPolygon(spot, YES))
          return (SquirrelIndex)i;
      }
    }
  }
  return kVoidSymbol;
}

@end  // SquirrelView


NS_HEADER_AUDIT_BEGIN(nullability, sendability)
/** In order to put SquirrelPanel above client app windows,
    SquirrelPanel needs to be assigned a window level higher
    than `kCGHelpWindowLevelKey` that the system tooltips use.
    This class makes system-alike tooltips above SquirrelPanel */
@interface SquirrelToolTip : NSWindow

typedef NS_CLOSED_ENUM(NSInteger, SquirrelDisplayType) {
  kDisplayNow, kDisplayDelayed, kDisplayOnRequest, kDisplayNone
};

@property(nonatomic, readonly, direct) BOOL empty;

- (void)showToolTip:(NSString* _Nullable)toolTip
            display:(SquirrelDisplayType)display __attribute__((objc_direct));
- (void)delayedShow:(NSTimer* _Nonnull)timer;
- (void)delayedHide:(NSTimer* _Nonnull)timer;
- (void)hide __attribute__((objc_direct));
- (void)show __attribute__((objc_direct));
- (void)clear __attribute__((objc_direct));

@end
NS_HEADER_AUDIT_END(nullability, sendability)

@implementation SquirrelToolTip {
  NSVisualEffectView* _backView;
  NSTextField* _textView;
  NSTimer* _showTimer;
  NSTimer* _hideTimer;
}

- (instancetype)init {
  if (self = [super initWithContentRect:NSZeroRect
                              styleMask:NSWindowStyleMaskNonactivatingPanel
                                backing:NSBackingStoreBuffered
                                  defer:YES]) {
    self.backgroundColor = NSColor.clearColor;
    self.opaque = YES;
    self.hasShadow = YES;
    NSView* contentView = NSView.alloc.init;
    if (@available(macOS 10.14, *)) {
      _backView = NSVisualEffectView.alloc.init;
      _backView.material = NSVisualEffectMaterialToolTip;
      [contentView addSubview:_backView];
      _textView = NSTextField.alloc.init;
      _textView.bezeled = YES;
      _textView.bezelStyle = NSTextFieldSquareBezel;
      _textView.selectable = NO;
      _textView.usesSingleLineMode = NO;
      _textView.lineBreakMode = NSLineBreakByWordWrapping;
    }
    [contentView addSubview:_textView];
    self.contentView = contentView;
    _empty = YES;
  }
  return self;
}

- (void)showToolTip:(NSString*)toolTip
            display:(SquirrelDisplayType)display {
  if (display == kDisplayNone || toolTip.length == 0) {
    [self clear];
    return;
  }
  SquirrelPanel* panel = NSApp.SquirrelAppDelegate.panel;
  self.level = panel.level + 1;

  _empty = NO;
  _textView.stringValue = toolTip;
  _textView.preferredMaxLayoutWidth = NSWidth(panel.screen.visibleFrame) * 0.25;
  _textView.font = [NSFont toolTipsFontOfSize:0];
  _textView.textColor = NSColor.windowFrameTextColor;
  [_textView sizeToFit];
  NSSize contentSize = _textView.fittingSize;
  contentSize.width += 3;
  contentSize.height += 3;

  NSPoint spot = NSEvent.mouseLocation;
  NSCursor* cursor = NSCursor.currentSystemCursor;
  spot.x += cursor.image.size.width - cursor.hotSpot.x;
  spot.y -= cursor.image.size.height - cursor.hotSpot.y;
  NSRect windowRect = NSMakeRect(spot.x, spot.y - contentSize.height,
                                 contentSize.width, contentSize.height);

  NSRect screenRect = panel.screen.visibleFrame;
  if (NSMaxX(windowRect) > nexttoward(NSMaxX(screenRect), -INFINITY))
    windowRect.origin.x = NSMaxX(screenRect) - NSWidth(windowRect);
  if (NSMinY(windowRect) < nexttoward(NSMinY(screenRect), INFINITY))
    windowRect.origin.y = NSMinY(screenRect);
  windowRect = [panel.screen backingAlignedRect:windowRect
                                        options:NSAlignAllEdgesNearest];
  [self setFrame:windowRect display:NO];
  _textView.frame = self.contentView.bounds;
  _backView.frame = self.contentView.bounds;

  if (_showTimer.valid) {
    [_showTimer invalidate];
    _showTimer = nil;
  }
  switch (display) {
    case kDisplayNow:
      [self show];
      break;
    case kDisplayDelayed:
      _showTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                    target:self
                                                  selector:@selector(delayedShow:)
                                                  userInfo:nil
                                                   repeats:NO];
      break;
    default:
      break;
  }
}

- (void)delayedShow:(NSTimer*)timer {
  [self show];
}

- (void)show {
  if (_empty)
    return;
  if (_showTimer.valid) {
    [_showTimer invalidate];
    _showTimer = nil;
  }
  [self display];
  [self orderFrontRegardless];
  if (_hideTimer.valid)
    [_hideTimer invalidate];
  _hideTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                target:self
                                              selector:@selector(delayedHide:)
                                              userInfo:nil
                                               repeats:NO];
}

- (void)delayedHide:(NSTimer*)timer {
  [self hide];
}

- (void)hide {
  if (_showTimer.valid) {
    [_showTimer invalidate];
    _showTimer = nil;
  }
  if (_hideTimer.valid) {
    [_hideTimer invalidate];
    _hideTimer = nil;
  }
  if (self.visible)
    [self orderOut:nil];
}

- (void)clear {
  _empty = YES;
  _textView.stringValue = @"";
  [self hide];
}

@end  // SquirrelToolTipView


#pragma mark - Panel window, dealing with text content and mouse interactions

@implementation SquirrelPanel {
  SquirrelInputController* __weak _inputController;
  // Squirrel panel layouts
  NSVisualEffectView* _back;
  SquirrelToolTip* _toolTip;
  SquirrelView* _view;
  NSScreen* _screen;
  NSTimer* _statusTimer;
  NSSize _maxSizeAttained;
  CGFloat _textWidthLimit;
  CGFloat _anchorOffset;
  BOOL _initPosition;
  BOOL _needsRedraw;
  // Rime contents and actions
  NSString* _statusMessage;
  NSRange _indexRange;
  NSUInteger _hilitedCandidate;
  NSUInteger _functionButton;
  NSUInteger _caretPos;
  NSUInteger _pageNum;
  BOOL _finalPage;
}

@dynamic screen;

- (BOOL)linear {
  return SquirrelTheme.currentTheme.linear;
}

- (BOOL)tabular {
  return SquirrelTheme.currentTheme.tabular;
}

- (BOOL)vertical {
  return SquirrelTheme.currentTheme.vertical;
}

- (BOOL)inlinePreedit {
  return SquirrelTheme.currentTheme.inlinePreedit;
}

- (BOOL)inlineCandidate {
  return SquirrelTheme.currentTheme.inlineCandidate;
}

- (BOOL)firstLine {
  return _view.tabularIndices ? _view.tabularIndices[_hilitedCandidate].lineNum == 0 : YES;
}

- (BOOL)expanded {
  return _view.expanded;
}

- (void)setExpanded:(BOOL)expanded {
  if (SquirrelTheme.currentTheme.tabular && !_locked && _view.expanded != expanded) {
    _view.expanded = expanded;
    _sectionNum = 0;
    _needsRedraw = YES;
  }
}

- (void)setSectionNum:(NSUInteger)sectionNum {
  if (SquirrelTheme.currentTheme.tabular && _view.expanded && _sectionNum != sectionNum)
    _sectionNum = clamp(sectionNum, 0UL, SquirrelTheme.currentTheme.vertical ? 2UL : 4UL);
}

- (void)setLocked:(BOOL)locked {
  if (SquirrelTheme.currentTheme.tabular && _locked != locked) {
    _locked = locked;
    SquirrelConfig* userConfig = SquirrelConfig.alloc.init;
    if ([userConfig openUserConfig:@"user"]) {
      [userConfig setOption:@"var/option/_lock_tabular" withBool:locked];
      if (locked)
        [userConfig setOption:@"var/option/_expand_tabular" withBool:_view.expanded];
    }
    [userConfig close];
  }
}

- (void)getLocked __attribute__((objc_direct)) {
  if (SquirrelTheme.currentTheme.tabular) {
    SquirrelConfig* userConfig = SquirrelConfig.alloc.init;
    if ([userConfig openUserConfig:@"user"]) {
      _locked = [userConfig boolValueForOption:@"var/option/_lock_tabular"];
      if (_locked)
        _view.expanded = [userConfig boolValueForOption:@"var/option/_expand_tabular"];
    }
    [userConfig close];
    _sectionNum = 0;
  }
}

- (void)setIbeamRect:(NSRect)IbeamRect {
  if (NSEqualRects(_IbeamRect, IbeamRect))
    return;
  _IbeamRect = IbeamRect;
  _needsRedraw = YES;
  if (NSEqualRects(IbeamRect, NSZeroRect)) {
    _initPosition = YES;
  } else if (!NSIntersectsRect(_screen.frame, IbeamRect) && !NSContainsRect(_screen.frame, IbeamRect)) {
    [self willChangeValueForKey:@"screen"];
    [self updateScreen];
    [self didChangeValueForKey:@"screen"];
    [self updateDisplayParameters];
  }
}

- (BOOL)hasStatusMessage {
  return _statusMessage != nil;
}

- (void)windowDidChangeBackingProperties:(NSNotification*)notification {
  if ([notification.object isMemberOfClass:SquirrelPanel.class]) {
    SquirrelPanel* panel = notification.object;
    [panel updateDisplayParameters];
  }
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id>*)change
                       context:(void*)context {
  if ([object isKindOfClass:SquirrelInputController.class] &&
      [keyPath isEqualToString:@"viewEffectiveAppearance"]) {
    _inputController = object;
    if (@available(macOS 10.14, *)) {
      NSAppearance* clientAppearance = change[NSKeyValueChangeNewKey];
      NSAppearanceName appearName = [clientAppearance bestMatchFromAppearancesWithNames:
                                     @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
      SquirrelStyle style = [appearName isEqualToString:
                             NSAppearanceNameDarkAqua] ? kDarkStyle : kDefaultStyle;
      if (style != _view.style) {
        _view.style = style;
        self.appearance = [NSAppearance appearanceNamed:appearName];
        _view.needsDisplay = YES;
        [self display];
      }
    }
  } else {
    [super observeValueForKeyPath:keyPath
                         ofObject:object
                           change:change
                          context:context];
  }
}

- (instancetype)init {
  if (self = [super initWithContentRect:_IbeamRect
                              styleMask:NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskBorderless
                                backing:NSBackingStoreBuffered
                                  defer:YES]) {
    self.level = CGWindowLevelForKey(kCGCursorWindowLevelKey) - 100;
    self.hasShadow = NO;
    self.opaque = NO;
    self.backgroundColor = NSColor.clearColor;
    self.delegate = self;
    self.acceptsMouseMovedEvents = YES;
    self.displaysWhenScreenProfileChanges = YES;
    self.worksWhenModal = YES;

    NSFlippedView* contentView = NSFlippedView.alloc.init;
    contentView.autoresizesSubviews = NO;
    _view = SquirrelView.alloc.init;
    _toolTip = SquirrelToolTip.alloc.init;
    if (@available(macOS 10.14, *)) {
      _toolTip.appearanceSource = self;
      _back = NSVisualEffectView.alloc.init;
      _back.blendingMode = NSVisualEffectBlendingModeBehindWindow;
      _back.material = NSVisualEffectMaterialHUDWindow;
      _back.state = NSVisualEffectStateActive;
      _back.emphasized = YES;
      _back.wantsLayer = YES;
      _back.layer.mask = _view.shape;
      [contentView addSubview:_back];
    }
    [contentView addSubview:_view];
    [contentView addSubview:_view.statusView];
    [contentView addSubview:_view.preeditView];
    [contentView addSubview:_view.scrollView];
    [contentView addSubview:_view.pagingView];
    self.contentView = contentView;

    self.optionSwitcher = SquirrelOptionSwitcher.alloc.init;
    self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [self updateDisplayParameters];
  }
  return self;
}

- (void)updateDisplayParameters __attribute__((objc_direct)) {
  // repositioning the panel window
  _initPosition = YES;
  _maxSizeAttained = NSZeroSize;

  NSTextLayoutOrientation orientation = SquirrelTheme.currentTheme.vertical ? NSTextLayoutOrientationVertical : NSTextLayoutOrientationHorizontal;
  _view.candidateView.layoutOrientation = orientation;
  _view.preeditView.layoutOrientation = orientation;
  _view.pagingView.layoutOrientation = orientation;
  _view.statusView.layoutOrientation = orientation;
  // rotate the view, the core in vertical mode!
  self.contentView.boundsRotation = SquirrelTheme.currentTheme.vertical ? 90.0 : 0.0;
  _view.candidateView.boundsRotation = 0.0;
  _view.preeditView.boundsRotation = 0.0;
  _view.pagingView.boundsRotation = 0.0;
  _view.statusView.boundsRotation = 0.0;
  _view.candidateView.boundsOrigin = NSZeroPoint;
  _view.preeditView.boundsOrigin = NSZeroPoint;
  _view.pagingView.boundsOrigin = NSZeroPoint;
  _view.statusView.boundsOrigin = NSZeroPoint;

  _view.scrollView.lineScroll = SquirrelTheme.currentTheme.candidateParagraphStyle.minimumLineHeight;
  _view.candidateView.contentBlock = SquirrelTheme.currentTheme.linear ? kLinearCandidateBlock : kStackedCandidateBlock;
  _view.candidateView.defaultParagraphStyle = SquirrelTheme.currentTheme.candidateParagraphStyle;
  _view.preeditView.defaultParagraphStyle = SquirrelTheme.currentTheme.preeditParagraphStyle;
  _view.pagingView.defaultParagraphStyle = SquirrelTheme.currentTheme.pagingParagraphStyle;
  _view.statusView.defaultParagraphStyle = SquirrelTheme.currentTheme.statusParagraphStyle;

  // size limits on textContainer
  NSRect screenRect = _screen.visibleFrame;
  CGFloat textWidthRatio = fmin(0.8, 1.0 / (SquirrelTheme.currentTheme.vertical ? 4 : 3) +
                                [SquirrelTheme.currentTheme.textAttrs[NSFontAttributeName] pointSize] / 144.0);
  _textWidthLimit = ceil((SquirrelTheme.currentTheme.vertical ? NSHeight(screenRect) : NSWidth(screenRect)) * textWidthRatio -
                         SquirrelTheme.currentTheme.borderInsets.width * 2 - SquirrelTheme.currentTheme.fullWidth);
  if (isnormal(SquirrelTheme.currentTheme.lineLength) && SquirrelTheme.currentTheme.lineLength < _textWidthLimit)
    _textWidthLimit = SquirrelTheme.currentTheme.lineLength;
  if (SquirrelTheme.currentTheme.tabular)
    _textWidthLimit = floor(_textWidthLimit / (SquirrelTheme.currentTheme.fullWidth * 2)) * (SquirrelTheme.currentTheme.fullWidth * 2);

  _view.candidateView.textContainer.size = NSMakeSize(_textWidthLimit, CGFLOAT_MAX);
  _view.preeditView.textContainer.size = NSMakeSize(_textWidthLimit, CGFLOAT_MAX);
  _view.pagingView.textContainer.size = NSMakeSize(_textWidthLimit, CGFLOAT_MAX);
  _view.statusView.textContainer.size = NSMakeSize(_textWidthLimit, CGFLOAT_MAX);

  // color, opacity and transluecency
  self.alphaValue = SquirrelTheme.currentTheme.opacity;
  // resize logo and background image, if any
  CGFloat statusHeight = SquirrelTheme.currentTheme.statusParagraphStyle.minimumLineHeight;
  NSRect logoRect = NSMakeRect(SquirrelTheme.currentTheme.borderInsets.width,
                               SquirrelTheme.currentTheme.borderInsets.height, statusHeight, statusHeight);
  _view.logoLayer.frame = NSInsetRect(logoRect, -0.1 * statusHeight, -0.1 * statusHeight);
  NSImage* logoImage = [NSImage imageNamed:NSImageNameApplicationIcon];
  logoImage.size = logoRect.size;
  _view.logoLayer.contents = logoImage;
  _view.logoLayer.affineTransform = SquirrelTheme.currentTheme.vertical ?
    CGAffineTransformMakeRotation(-M_PI_2) : CGAffineTransformIdentity;
  if (NSImage* backImage = SquirrelTheme.currentTheme.backImage; backImage.valid) {
    CGFloat widthLimit = _textWidthLimit + SquirrelTheme.currentTheme.fullWidth;
    backImage.resizingMode = NSImageResizingModeStretch;
    backImage.size = SquirrelTheme.currentTheme.vertical
    ? NSMakeSize(backImage.size.width / backImage.size.height * widthLimit, widthLimit)
    : NSMakeSize(widthLimit, backImage.size.height / backImage.size.width * widthLimit);
    _view.backImageLayer.fillColor = [NSColor colorWithPatternImage:backImage].CGColor;
  }
  if (@available(macOS 10.14, *)) {
    _back.hidden = isfinite(SquirrelTheme.currentTheme.translucency) && !isnormal(SquirrelTheme.currentTheme.translucency);
    _view.backImageLayer.opacity = 1.0f - SquirrelTheme.currentTheme.translucency;
    _view.backColorLayer.opacity = 1.0f - SquirrelTheme.currentTheme.translucency;
    _view.borderLayer.opacity = 1.0f - SquirrelTheme.currentTheme.translucency;
    _view.documentLayer.opacity = 1.0f - SquirrelTheme.currentTheme.translucency;
  }
  if (self.isVisible && _view.statusView.hidden) {
    [self showPreedit:[_view.preeditContents.string substringToIndex:fmax(0UL, _view.preeditContents.length - 2)]
             selRange:_view.hilitedPreeditRange
             caretPos:_caretPos
     candidateIndices:_indexRange
     hilitedCandidate:_hilitedCandidate
              pageNum:_pageNum
            finalPage:_finalPage
           didCompose:YES];
  }
}

- (NSUInteger)candidateIndexOnDirection:(SquirrelIndex)arrowKey {
  if (!SquirrelTheme.currentTheme.tabular || _indexRange.length == 0 || _hilitedCandidate == NSNotFound)
    return NSNotFound;
  NSUInteger currentTab = _view.tabularIndices[_hilitedCandidate].tabNum;
  NSUInteger currentLine = _view.tabularIndices[_hilitedCandidate].lineNum;
  NSUInteger finalLine = _view.tabularIndices[_indexRange.length - 1].lineNum;
  if (arrowKey == (SquirrelTheme.currentTheme.vertical ? kLeftKey : kDownKey)) {
    if (_hilitedCandidate == _indexRange.length - 1 && _finalPage)
      return NSNotFound;
    if (currentLine == finalLine && !_finalPage)
      return NSMaxRange(_indexRange);

    NSUInteger newIndex = _hilitedCandidate + 1;
    while (newIndex < _indexRange.length &&
           (_view.tabularIndices[newIndex].lineNum == currentLine ||
            (_view.tabularIndices[newIndex].lineNum == currentLine + 1 &&
             _view.tabularIndices[newIndex].tabNum <= currentTab)))
      ++newIndex;
    if (newIndex != _indexRange.length || _finalPage)
      --newIndex;

    return newIndex + _indexRange.location;
  } else if (arrowKey == (SquirrelTheme.currentTheme.vertical ? kRightKey : kUpKey)) {
    if (currentLine == 0)
      return _pageNum == 0 ? NSNotFound : _indexRange.location - 1;

    NSUInteger newIndex = _hilitedCandidate - 1;
    while (newIndex > 0 &&
           (_view.tabularIndices[newIndex].lineNum == currentLine ||
            (_view.tabularIndices[newIndex].lineNum == currentLine - 1 &&
             _view.tabularIndices[newIndex].tabNum > currentTab)))
      --newIndex;

    return newIndex + _indexRange.location;
  }
  return NSNotFound;
}

// handle mouse interaction events
- (void)sendEvent:(NSEvent*)event {
  static SquirrelIndex cursorIndex = kVoidSymbol;
  switch (event.type) {
    case NSEventTypeLeftMouseDown:
      if (event.clickCount == 1 && cursorIndex == kCodeInputArea && _caretPos != NSNotFound) {
        NSPoint spot = [_view.preeditView convertPoint:self.mouseLocationOutsideOfEventStream
                                              fromView:nil];
        NSUInteger inputIndex = [_view.preeditView characterIndexForInsertionAtPoint:spot];
        if (inputIndex == 0)
          [_inputController performAction:kPROCESS onIndex:kHomeKey];
        else if (inputIndex < _caretPos)
          [_inputController moveCursor:_caretPos toPosition:inputIndex
                         inlinePreedit:NO inlineCandidate:NO];
        else if (inputIndex >= _view.preeditContents.length - 2)
          [_inputController performAction:kPROCESS onIndex:kEndKey];
        else if (inputIndex > _caretPos + 1)
          [_inputController moveCursor:_caretPos toPosition:inputIndex - 1
                         inlinePreedit:NO inlineCandidate:NO];
      }
      break;
    case NSEventTypeLeftMouseUp:
      if (event.clickCount == 1 && cursorIndex != kVoidSymbol) {
        if (cursorIndex == _hilitedCandidate) {
          [_inputController performAction:kSELECT
                                  onIndex:(SquirrelIndex)(cursorIndex + _indexRange.location)];
        } else if (cursorIndex == _functionButton) {
          if (cursorIndex == kExpandButton) {
            if (_locked) {
              self.locked = NO;
              [_view.pagingContents
               replaceCharactersInRange:NSMakeRange(_view.pagingContents.length / 2, 1)
               withAttributedString:_view.expanded ? SquirrelTheme.currentTheme.symbolCompress : SquirrelTheme.currentTheme.symbolExpand];
              _view.pagingView.needsDisplayInRect = [_view convertRect:_view.expanderRect
                                                                toView:_view.pagingView];
            } else {
              self.expanded = !_view.expanded;
              self.sectionNum = 0;
            }
          }
          [_inputController performAction:kPROCESS onIndex:cursorIndex];
        }
      }
      break;
    case NSEventTypeRightMouseUp:
      if (event.clickCount == 1 && cursorIndex != kVoidSymbol) {
        if (cursorIndex == _hilitedCandidate) {
          [_inputController performAction:kDELETE
                                  onIndex:(SquirrelIndex)(cursorIndex + _indexRange.location)];
        } else if (cursorIndex == _functionButton) {
          switch (_functionButton) {
            case kPageUpKey:
              [_inputController performAction:kPROCESS onIndex:kHomeKey];
              break;
            case kPageDownKey:
              [_inputController performAction:kPROCESS onIndex:kEndKey];
              break;
            case kExpandButton:
              self.locked = !_locked;
              [_view.pagingContents
               replaceCharactersInRange:NSMakeRange(_view.pagingContents.length / 2, 1)
               withAttributedString:_locked ? SquirrelTheme.currentTheme.symbolLock : _view.expanded
                 ? SquirrelTheme.currentTheme.symbolCompress : SquirrelTheme.currentTheme.symbolExpand];
              [_view.pagingContents addAttribute:NSForegroundColorAttributeName
                                           value:SquirrelTheme.currentTheme.hilitedPreeditForeColor
                                           range:NSMakeRange(_view.pagingContents.length / 2, 1)];
              [_view.pagingView setNeedsDisplayInRect:[_view convertRect:_view.expanderRect
                                                                  toView:_view.pagingView]
                                avoidAdditionalLayout:YES];
              [_inputController performAction:kPROCESS onIndex:kLockButton];
              break;
            case kBackSpaceKey:
              [_inputController performAction:kPROCESS onIndex:kEscapeKey];
              break;
          }
        }
      }
      break;
    case NSEventTypeMouseMoved: {
      if ((event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagControl)
        return;
      BOOL noDelay = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagOption;
      cursorIndex = [_view indexForMouseSpot:
                     [_view convertPoint:self.mouseLocationOutsideOfEventStream fromView:nil]];
      if (cursorIndex != _hilitedCandidate && cursorIndex != _functionButton)
        [_toolTip clear];
      else if (noDelay)
        [_toolTip show];

      if (cursorIndex >= 0 && cursorIndex < _indexRange.length && _hilitedCandidate != cursorIndex) {
        [self highlightFunctionButton:kVoidSymbol displayToolTip:kDisplayNone];
        if (SquirrelTheme.currentTheme.linear && _view.candidateInfos[cursorIndex].truncated)
          [_toolTip showToolTip:[_view.candidateContents.mutableString substringWithRange:
                                 _view.candidateInfos[cursorIndex].candidateRange()]
                        display:kDisplayNow];
        else
          [_toolTip showToolTip:[NSBundle.mainBundle localizedStringForKey:@"candidate" value:nil table:@"Tooltips"]
                        display:kDisplayOnRequest];

        self.sectionNum = cursorIndex / SquirrelTheme.currentTheme.pageSize;
        [_inputController performAction:kHIGHLIGHT
                                onIndex:(SquirrelIndex)(cursorIndex + _indexRange.location)];
      } else if ((cursorIndex == kPageUpKey || cursorIndex == kPageDownKey || cursorIndex == kExpandButton ||
                  cursorIndex == kBackSpaceKey) && _functionButton != cursorIndex) {
        [self highlightFunctionButton:cursorIndex displayToolTip:noDelay ? kDisplayNow : kDisplayDelayed];
      }
    } break;
    case NSEventTypeMouseExited:
      cursorIndex = kVoidSymbol;
      [_toolTip clear];
      break;
    case NSEventTypeLeftMouseDragged:
      // reset the `remember_size` references after moving the panel
      _maxSizeAttained = NSZeroSize;
      [self performWindowDragWithEvent:event];
      break;
    case NSEventTypeScrollWheel: {
      CGFloat scrollThreshold = _view.scrollView.lineScroll;
      static NSPoint scrollLocus;
      static BOOL scrollByLine;
      if (event.phase == NSEventPhaseBegan) {
        scrollLocus = NSZeroPoint;
        scrollByLine = NO;
      } else if ((event.phase == NSEventPhaseNone || event.momentumPhase == NSEventPhaseNone) &&
                 isfinite(scrollLocus.x) && isfinite(scrollLocus.y)) {
        CGFloat scrollDistance = 0.0;
        // determine scrolling direction by confining to sectors within ±30º of any axis
        if (fabs(event.scrollingDeltaX) > fabs(event.scrollingDeltaY) * sqrt(3.0)) {
          scrollDistance = event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : scrollThreshold);
          scrollLocus.x += scrollDistance;
        } else if (fabs(event.scrollingDeltaY) > fabs(event.scrollingDeltaX) * sqrt(3.0)) {
          scrollDistance = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : scrollThreshold);
          scrollLocus.y += scrollDistance;
        }
        // compare accumulated locus length against threshold and limit paging to max once
        if (scrollLocus.x > scrollThreshold) {
          if (SquirrelTheme.currentTheme.vertical &&
              NSMaxY(_view.scrollView.documentVisibleRect) < nexttoward(NSMaxY(_view.documentRect), -INFINITY)) {
            scrollByLine = YES;
            NSPoint origin = _view.scrollView.contentView.bounds.origin;
            origin.y += fmin(scrollDistance,
                             NSMaxY(_view.documentRect) - NSMaxY(_view.scrollView.documentVisibleRect));
            [_view.scrollView.contentView scrollToPoint:origin];
            _view.scrollView.verticalScroller.doubleValue = NSMinY(_view.scrollView.documentVisibleRect) / _view.clippedHeight;
          } else if (!scrollByLine) {
            [_inputController performAction:kPROCESS
                                    onIndex:(SquirrelTheme.currentTheme.vertical ? kPageDownKey : kPageUpKey)];
            scrollLocus = NSMakePoint(INFINITY, INFINITY);
          }
        } else if (scrollLocus.y > scrollThreshold) {
          if (NSMinY(_view.scrollView.documentVisibleRect) > nexttoward(NSMinY(_view.documentRect), INFINITY)) {
            scrollByLine = YES;
            NSPoint origin = _view.scrollView.contentView.bounds.origin;
            origin.y -= fmin(scrollDistance,
                             NSMinY(_view.scrollView.documentVisibleRect) - NSMinY(_view.documentRect));
            [_view.scrollView.contentView scrollToPoint:origin];
            _view.scrollView.verticalScroller.doubleValue = NSMinY(_view.scrollView.documentVisibleRect) / _view.clippedHeight;
          } else if (!scrollByLine) {
            [_inputController performAction:kPROCESS onIndex:kPageUpKey];
            scrollLocus = NSMakePoint(INFINITY, INFINITY);
          }
        } else if (scrollLocus.x < -scrollThreshold) {
          if (SquirrelTheme.currentTheme.vertical &&
              NSMinY(_view.scrollView.documentVisibleRect) > nexttoward(NSMinY(_view.documentRect), INFINITY)) {
            scrollByLine = YES;
            NSPoint origin = _view.scrollView.contentView.bounds.origin;
            origin.y += fmax(scrollDistance,
                             NSMinY(_view.documentRect) - NSMinY(_view.scrollView.documentVisibleRect));
            [_view.scrollView.contentView scrollToPoint:origin];
            _view.scrollView.verticalScroller.doubleValue = NSMinY(_view.scrollView.documentVisibleRect) / _view.clippedHeight;
          } else if (!scrollByLine) {
            [_inputController performAction:kPROCESS
                                    onIndex:(SquirrelTheme.currentTheme.vertical ? kPageUpKey : kPageDownKey)];
            scrollLocus = NSMakePoint(INFINITY, INFINITY);
          }
        } else if (scrollLocus.y < -scrollThreshold) {
          if (NSMaxY(_view.scrollView.documentVisibleRect) < nexttoward(NSMaxY(_view.documentRect), -INFINITY)) {
            scrollByLine = YES;
            NSPoint origin = _view.scrollView.contentView.bounds.origin;
            origin.y -= fmax(scrollDistance,
                             NSMaxY(_view.scrollView.documentVisibleRect) - NSMaxY(_view.documentRect));
            [_view.scrollView.contentView scrollToPoint:origin];
            _view.scrollView.verticalScroller.doubleValue = NSMinY(_view.scrollView.documentVisibleRect) / _view.clippedHeight;
          } else if (!scrollByLine) {
            [_inputController performAction:kPROCESS onIndex:kPageDownKey];
            scrollLocus = NSMakePoint(INFINITY, INFINITY);
          }
        }
      }
    } break;
    default:
      [super sendEvent:event];
      break;
  }
}

- (BOOL)showToolTip {
  if (!_toolTip.empty) {
    [_toolTip show];
    return YES;
  }
  return NO;
}

- (void)highlightCandidate:(NSUInteger)hilitedCandidate __attribute__((objc_direct)) {
  NSUInteger priorHilitedCandidate = _hilitedCandidate;
  NSUInteger priorSectionNum = priorHilitedCandidate / SquirrelTheme.currentTheme.pageSize;
  _hilitedCandidate = hilitedCandidate;
  self.sectionNum = hilitedCandidate / SquirrelTheme.currentTheme.pageSize;
  // apply new foreground colors
  for (NSUInteger i = 0; i < SquirrelTheme.currentTheme.pageSize; ++i) {
    NSUInteger priorCandidate = i + priorSectionNum * SquirrelTheme.currentTheme.pageSize;
    if ((_sectionNum != priorSectionNum || priorCandidate == priorHilitedCandidate) &&
        priorCandidate < _indexRange.length) {
      SquirrelCandidateInfo priorRange = _view.candidateInfos[priorCandidate];
      NSColor* labelColor = priorCandidate == priorHilitedCandidate && _sectionNum == priorSectionNum ?
        SquirrelTheme.currentTheme.labelForeColor : SquirrelTheme.currentTheme.dimmedLabelForeColor;
      [_view.candidateContents addAttribute:NSForegroundColorAttributeName
                                      value:labelColor
                                      range:priorRange.labelRange()];
      if (priorCandidate == priorHilitedCandidate) {
        [_view.candidateContents addAttribute:NSForegroundColorAttributeName
                                        value:SquirrelTheme.currentTheme.textForeColor
                                        range:priorRange.textRange()];
        [_view.candidateContents addAttribute:NSForegroundColorAttributeName
                                        value:SquirrelTheme.currentTheme.commentForeColor
                                        range:priorRange.commentRange()];
      }
    }
    NSUInteger newCandidate = i + _sectionNum * SquirrelTheme.currentTheme.pageSize;
    if ((_sectionNum != priorSectionNum || newCandidate == hilitedCandidate) &&
        newCandidate < _indexRange.length) {
      SquirrelCandidateInfo newRange = _view.candidateInfos[newCandidate];
      NSColor* labelColor = newCandidate == hilitedCandidate ?
        SquirrelTheme.currentTheme.hilitedLabelForeColor : SquirrelTheme.currentTheme.labelForeColor;
      [_view.candidateContents addAttribute:NSForegroundColorAttributeName
                                      value:labelColor
                                      range:newRange.labelRange()];
      if (newCandidate == hilitedCandidate) {
        [_view.candidateContents addAttribute:NSForegroundColorAttributeName
                                        value:SquirrelTheme.currentTheme.hilitedTextForeColor
                                        range:newRange.textRange()];
        [_view.candidateContents addAttribute:NSForegroundColorAttributeName
                                        value:SquirrelTheme.currentTheme.hilitedCommentForeColor
                                        range:newRange.commentRange()];
      }
    }
  }
  [_view highlightCandidate:hilitedCandidate];
}

- (void)highlightFunctionButton:(SquirrelIndex)functionButton
                 displayToolTip:(SquirrelDisplayType)display __attribute__((objc_direct)) {
  if (_functionButton == functionButton)
    return;
  switch (_functionButton) {
    case kPageUpKey:
      [_view.pagingContents addAttribute:NSForegroundColorAttributeName
                                   value:SquirrelTheme.currentTheme.preeditForeColor
                                   range:NSMakeRange(0, 1)];
      break;
    case kPageDownKey:
      [_view.pagingContents addAttribute:NSForegroundColorAttributeName
                                   value:SquirrelTheme.currentTheme.preeditForeColor
                                   range:NSMakeRange(_view.pagingContents.length - 1, 1)];
      break;
    case kExpandButton:
      [_view.pagingContents addAttribute:NSForegroundColorAttributeName
                                   value:SquirrelTheme.currentTheme.preeditForeColor
                                   range:NSMakeRange(_view.pagingContents.length / 2, 1)];
      break;
    case kBackSpaceKey:
      [_view.preeditContents addAttribute:NSForegroundColorAttributeName
                                    value:SquirrelTheme.currentTheme.preeditForeColor
                                    range:NSMakeRange(_view.preeditContents.length - 1, 1)];
      break;
  }
  _functionButton = functionButton;
  switch (_functionButton) {
    case kPageUpKey:
      [_view.pagingContents addAttribute:NSForegroundColorAttributeName
                                   value:SquirrelTheme.currentTheme.hilitedPreeditForeColor
                                   range:NSMakeRange(0, 1)];
      functionButton = _pageNum == 0 ? kHomeKey : kPageUpKey;
      break;
    case kPageDownKey:
      [_view.pagingContents addAttribute:NSForegroundColorAttributeName
                                   value:SquirrelTheme.currentTheme.hilitedPreeditForeColor
                                   range:NSMakeRange(_view.pagingContents.length - 1, 1)];
      functionButton = _finalPage ? kEndKey : kPageDownKey;
      break;
    case kExpandButton:
      [_view.pagingContents addAttribute:NSForegroundColorAttributeName
                                   value:SquirrelTheme.currentTheme.hilitedPreeditForeColor
                                   range:NSMakeRange(_view.pagingContents.length / 2, 1)];
      functionButton = _locked ? kLockButton : _view.expanded ? kCompressButton : kExpandButton;
      break;
    case kBackSpaceKey:
      [_view.preeditContents addAttribute:NSForegroundColorAttributeName
                                    value:SquirrelTheme.currentTheme.hilitedPreeditForeColor
                                    range:NSMakeRange(_view.preeditContents.length - 1, 1)];
      functionButton = _caretPos == NSNotFound || _caretPos == 0 ? kEscapeKey : kBackSpaceKey;
      break;
  }
  NSString* toolTipKey;
  switch (functionButton) {
    case kHomeKey: toolTipKey = @"home"; break;
    case kPageUpKey: toolTipKey = @"page_up"; break;
    case kEndKey: toolTipKey = @"end"; break;
    case kPageDownKey: toolTipKey = @"page_down"; break;
    case kLockButton: toolTipKey = @"unlock"; break;
    case kCompressButton: toolTipKey = @"compress"; break;
    case kExpandButton: toolTipKey = @"expand"; break;
    case kEscapeKey: toolTipKey = @"escape"; break;
    case kBackSpaceKey: toolTipKey = @"delete"; break;
    default: toolTipKey = nil; break;
  }
  if (toolTipKey != nil)
    [_toolTip showToolTip:[NSBundle.mainBundle localizedStringForKey:toolTipKey
                                                               value:nil
                                                               table:@"Tooltips"]
                  display:display];
  [_view highlightFunctionButton:functionButton];
  [self displayIfNeeded];
}

- (void)updateScreen __attribute__((objc_direct)) {
  for (NSScreen* screen in NSScreen.screens) {
    if (NSPointInRect(_IbeamRect.origin, screen.frame)) {
      _screen = screen;
      return;
    }
  }
  _screen = NSScreen.mainScreen;
}

// Get the window size, it will be the dirtyRect in SquirrelView.drawRect
- (void)show __attribute__((objc_direct)) {
  if (!_needsRedraw && !_initPosition) {
    self.visible ? [self update] : [self orderFront:nil];
    return;
  }
  //Break line if the text is too long, based on screen size.
  SquirrelTheme* theme = SquirrelTheme.currentTheme;
  NSSize border = theme.borderInsets;
  CGFloat textWidthRatio = fmin(0.8, 1.0 / (theme.vertical ? 4 : 3) +
                                     [theme.textAttrs[NSFontAttributeName] pointSize] / 144.0);
  NSRect screenRect = _screen.visibleFrame;

  // the sweep direction of the client app changes the behavior of adjusting squirrel panel position
  BOOL sweepVertical = NSWidth(_IbeamRect) > NSHeight(_IbeamRect);
  NSRect contentRect = _view.contentRect;
  // fixed line length (text width), but not applicable to status message
  if (isnormal(theme.lineLength) && _statusMessage == nil)
    contentRect.size.width = _textWidthLimit;
  // remember panel size (fix the top leading anchor of the panel in screen coordiantes)
  // but only when the text would expand on the side of upstream (i.e. towards the beginning of text)
  if (theme.rememberSize && _view.statusView.hidden) {
    if (isfinite(theme.lineLength) && !isnormal(theme.lineLength)) {
      BOOL attained = theme.vertical
        ? sweepVertical ? (NSMinY(_IbeamRect) - fmax(NSWidth(contentRect), _maxSizeAttained.width)
                           - border.width - floor(theme.fullWidth * 0.5) < nexttoward(NSMinY(screenRect), INFINITY))
                        : (NSMinY(_IbeamRect) - kOffsetGap - NSHeight(screenRect) * textWidthRatio
                           - border.width * 2 - theme.fullWidth < nexttoward(NSMinY(screenRect), INFINITY))
        : sweepVertical ? (NSMinX(_IbeamRect) - kOffsetGap - NSWidth(screenRect) * textWidthRatio
                           - border.width * 2 - theme.fullWidth > nexttoward(NSMinX(screenRect), INFINITY))
                        : (NSMaxX(_IbeamRect) + fmax(NSWidth(contentRect), _maxSizeAttained.width)
                           + border.width + floor(theme.fullWidth * 0.5) > nexttoward(NSMaxX(screenRect), -INFINITY));
      if (attained) {
        if (NSWidth(contentRect) > nexttoward(_maxSizeAttained.width, INFINITY))
          _maxSizeAttained.width = NSWidth(contentRect);
        else
          contentRect.size.width = _maxSizeAttained.width;
      }
    }
    CGFloat textHeight = fmax(NSHeight(contentRect), _maxSizeAttained.height) + border.height * 2;
    if (theme.vertical ? (NSMinX(_IbeamRect) - textHeight - (sweepVertical ? kOffsetGap : 0) < nexttoward(NSMinX(screenRect), INFINITY))
                       : (NSMinY(_IbeamRect) - textHeight - (sweepVertical ? 0 : kOffsetGap) < nexttoward(NSMinY(screenRect), INFINITY))) {
      if (NSHeight(contentRect) > nexttoward(_maxSizeAttained.height, INFINITY))
        _maxSizeAttained.height = NSHeight(contentRect);
      else
        contentRect.size.height = _maxSizeAttained.height;
    }
  }

  NSRect windowRect;
  if (_statusMessage != nil) { 
    // following system UI, middle-align status message with cursor
    _initPosition = YES;
    windowRect.size = theme.vertical ? NSMakeSize(NSHeight(contentRect) + border.height * 2,
                                                  NSWidth(contentRect) + border.width * 2 + theme.fullWidth)
                                     : NSMakeSize(NSWidth(contentRect) + border.width * 2 + theme.fullWidth,
                                                  NSHeight(contentRect) + border.height * 2);
    // vertically/horizontally centre-align (midY/midX) in screen coordinates
    windowRect.origin = sweepVertical ? NSMakePoint(NSMinX(_IbeamRect) - kOffsetGap - NSWidth(windowRect),
                                                    NSMidY(_IbeamRect) - NSHeight(windowRect) * 0.5)
                                      : NSMakePoint(NSMidX(_IbeamRect) - NSWidth(windowRect) * 0.5,
                                                    NSMinY(_IbeamRect) - kOffsetGap - NSHeight(windowRect));
  } else {
    if (theme.vertical) {
      // anchor is the top right corner in screen coordinates (MaxX, MaxY)
      windowRect = NSMakeRect(NSMaxX(self.frame) - NSHeight(contentRect) - border.height * 2,
                              NSMaxY(self.frame) - NSWidth(contentRect) - border.width * 2 - theme.fullWidth,
                              NSHeight(contentRect) + border.height * 2,
                              NSWidth(contentRect) + border.width * 2 + theme.fullWidth);
      _initPosition |= NSIntersectsRect(windowRect, _IbeamRect) || NSContainsRect(windowRect, _IbeamRect) ||
                       (!NSContainsRect(screenRect, windowRect) && !NSIntersectsRect(screenRect, windowRect));
      if (_initPosition) {
        if (!sweepVertical) {
          // To avoid jumping up and down while typing, use the lower screen when typing on upper, and vice versa
          BOOL isOnLower = NSMinY(_IbeamRect) - kOffsetGap - NSHeight(screenRect) * textWidthRatio -
                             border.width * 2 - theme.fullWidth < nexttoward(NSMinY(screenRect), INFINITY);
          windowRect.origin.y = isOnLower ? NSMaxY(_IbeamRect) + kOffsetGap
                                          : NSMinY(_IbeamRect) - kOffsetGap - NSHeight(windowRect);
          // Make the right edge of candidate block fixed at the left of cursor
          windowRect.origin.x = NSMinX(_IbeamRect) + border.height - NSWidth(windowRect);
        } else {
          BOOL isOnLefter = NSMinX(_IbeamRect) - kOffsetGap - NSWidth(windowRect) < nexttoward(NSMinX(screenRect), INFINITY);
          windowRect.origin.x = isOnLefter ? NSMaxX(_IbeamRect) + kOffsetGap
                                           : NSMinX(_IbeamRect) - kOffsetGap - NSWidth(windowRect);
          windowRect.origin.y = NSMinY(_IbeamRect) + border.width + ceil(theme.fullWidth * 0.5) - NSHeight(windowRect);
        }
      }
    } else {
      // anchor is the top left corner in screen coordinates (MinX, MaxY)
      windowRect = NSMakeRect(NSMinX(self.frame),
                              NSMaxY(self.frame) - NSHeight(contentRect) - border.height * 2,
                              NSWidth(contentRect) + border.width * 2 + theme.fullWidth,
                              NSHeight(contentRect) + border.height * 2);
      _initPosition |= NSIntersectsRect(windowRect, _IbeamRect) || NSContainsRect(windowRect, _IbeamRect) ||
                       (!NSContainsRect(screenRect, windowRect) && !NSIntersectsRect(screenRect, windowRect));
      if (_initPosition) {
        if (sweepVertical) {
          // To avoid jumping left and right while typing, use the lefter screen when typing on righter, and vice versa
          BOOL isOnLefter = NSMinX(_IbeamRect) - kOffsetGap - NSWidth(screenRect) * textWidthRatio -
                              border.width * 2 - theme.fullWidth > nexttoward(NSMinX(screenRect), INFINITY);
          windowRect.origin.x = isOnLefter ? NSMinX(_IbeamRect) - kOffsetGap - NSWidth(windowRect)
                                           : NSMaxX(_IbeamRect) + kOffsetGap;
          windowRect.origin.y = NSMinY(_IbeamRect) + border.height - NSHeight(windowRect);
        } else {
          BOOL isOnLower = NSMinY(_IbeamRect) - kOffsetGap - NSHeight(windowRect) < nexttoward(NSMinY(screenRect), INFINITY);
          windowRect.origin.y = isOnLower ? NSMaxY(_IbeamRect) + kOffsetGap
                                          : NSMinY(_IbeamRect) - kOffsetGap - NSHeight(windowRect);
          windowRect.origin.x = NSMaxX(_IbeamRect) - border.width - ceil(theme.fullWidth * 0.5);
        }
      }
    }
  }

  if (!_view.preeditView.hidden) {
    if (_initPosition)
      _anchorOffset = 0.0;
    if (theme.vertical != sweepVertical) {
      CGFloat anchorOffset = NSHeight(_view.preeditRect);
      if (theme.vertical)
        windowRect.origin.x += anchorOffset - _anchorOffset;
      else
        windowRect.origin.y += anchorOffset - _anchorOffset;
      _anchorOffset = anchorOffset;
    }
  }

  if (NSMaxX(windowRect) > nexttoward(NSMaxX(screenRect), -INFINITY))
    windowRect.origin.x = (_initPosition && sweepVertical ? fmin(NSMinX(_IbeamRect) - kOffsetGap, NSMaxX(screenRect)) :
                           NSMaxX(screenRect)) - NSWidth(windowRect);
  if (NSMinX(windowRect) < nexttoward(NSMinX(screenRect), INFINITY))
    windowRect.origin.x = _initPosition && sweepVertical ?
      fmax(NSMaxX(_IbeamRect) + kOffsetGap, NSMinX(screenRect)) : NSMinX(screenRect);
  if (NSMinY(windowRect) < nexttoward(NSMinY(screenRect), INFINITY))
    windowRect.origin.y = _initPosition && !sweepVertical ?
      fmax(NSMaxY(_IbeamRect) + kOffsetGap, NSMinY(screenRect)) : NSMinY(screenRect);
  if (NSMaxY(windowRect) > nexttoward(NSMaxY(screenRect), -INFINITY))
    windowRect.origin.y = (_initPosition && !sweepVertical ? fmin(NSMinY(_IbeamRect) - kOffsetGap, NSMaxY(screenRect)) :
                           NSMaxY(screenRect)) - NSHeight(windowRect);

  if (theme.vertical) {
    windowRect.origin.x += NSHeight(contentRect) - NSHeight(_view.contentRect);
    windowRect.size.width -= NSHeight(contentRect) - NSHeight(_view.contentRect);
  } else {
    windowRect.origin.y += NSHeight(contentRect) - NSHeight(_view.contentRect);
    windowRect.size.height -= NSHeight(contentRect) - NSHeight(_view.contentRect);
  }
  windowRect = [_screen backingAlignedRect:NSIntersectionRect(windowRect, screenRect)
                                   options:NSAlignAllEdgesNearest];
  [self setFrame:windowRect display:YES];

  self.contentView.boundsOrigin = theme.vertical ? NSMakePoint(-NSWidth(windowRect), 0.0) : NSZeroPoint;
  NSRect viewRect = NSIntegralRectWithOptions(self.contentView.bounds, NSAlignAllEdgesNearest);
  _view.frame = viewRect;
  if (!_view.statusView.hidden) {
    _view.statusView.frame = NSMakeRect(NSMinX(viewRect) + border.width + ceil(theme.fullWidth * 0.5),
                                        NSMinY(viewRect) + border.height,
                                        NSWidth(viewRect) - border.width * 2 - theme.fullWidth,
                                        NSHeight(viewRect) - border.height * 2);
  }
  if (!_view.preeditView.hidden) {
    _view.preeditView.frame = NSMakeRect(NSMinX(viewRect) + border.width + ceil(theme.fullWidth * 0.5),
                                         NSMinY(viewRect) + border.height,
                                         NSWidth(viewRect) - border.width * 2 - theme.fullWidth,
                                         NSHeight(_view.preeditRect));
  }
  if (!_view.pagingView.hidden) {
    CGFloat leadOrigin = theme.linear ? NSMaxX(viewRect) - NSWidth(_view.pagingRect) - border.width + ceil(theme.fullWidth * 0.5)
                                      : NSMinX(viewRect) + border.width + ceil(theme.fullWidth * 0.5);
    _view.pagingView.frame = NSMakeRect(leadOrigin,
                                        NSMaxY(viewRect) - border.height - NSHeight(_view.pagingRect),
                                        (theme.linear ? NSWidth(_view.pagingRect) : NSWidth(viewRect) - border.width * 2) - theme.fullWidth,
                                        NSHeight(_view.pagingRect));
  }
  if (!_view.scrollView.hidden) {
    _view.scrollView.frame = NSMakeRect(NSMinX(viewRect) + border.width,
                                        NSMinY(viewRect) + NSMinY(_view.clipRect),
                                        NSWidth(viewRect) - border.width * 2,
                                        NSHeight(_view.clipRect));
    _view.documentView.frame = NSMakeRect(0.0, 0.0, NSWidth(viewRect) - border.width * 2, NSHeight(_view.documentRect));
    _view.candidateView.frame = NSMakeRect(ceil(theme.fullWidth * 0.5),
                                           floor(theme.lineSpacing * 0.5),
                                           NSWidth(viewRect) - border.width * 2 - theme.fullWidth,
                                           NSHeight(_view.documentRect) - theme.lineSpacing);
  }
  if (!_back.hidden)
    _back.frame = viewRect;
  [self orderFront:nil];
  // reset to initial position after showing status message
  _initPosition = !_view.statusView.hidden;
  _needsRedraw = NO;
  // voila !
}

- (void)hide {
  if (_statusTimer.valid) {
    [_statusTimer invalidate];
    _statusTimer = nil;
  }
  [_toolTip hide];
  [self orderOut:nil];
  _maxSizeAttained = NSZeroSize;
  self.IbeamRect = NSZeroRect;
  self.expanded = NO;
  self.sectionNum = 0;
}

// Main function to add attributes to text output from librime
- (void)showPreedit:(NSString*)preedit
           selRange:(NSRange)selRange
           caretPos:(NSUInteger)caretPos
   candidateIndices:(NSRange)indexRange
   hilitedCandidate:(NSUInteger)hilitedCandidate
            pageNum:(NSUInteger)pageNum
          finalPage:(BOOL)finalPage
         didCompose:(BOOL)didCompose {
  BOOL updateCandidates = didCompose || !NSEqualRanges(_indexRange, indexRange);
  _caretPos = caretPos;
  _pageNum = pageNum;
  _finalPage = finalPage;
  _functionButton = kVoidSymbol;
  if (indexRange.length > 0 || preedit.length > 0) {
    _statusMessage = nil;
    if (_view.statusContents.length > 0) {
      [_view.statusContents deleteCharactersInRange:
       NSMakeRange(0, _view.statusContents.length)];
    }
    if (_statusTimer.valid) {
      [_statusTimer invalidate];
      _statusTimer = nil;
    }
  } else {
    if (_statusMessage != nil) {
      [self showStatus:_statusMessage];
      _statusMessage = nil;
    } else if (!_statusTimer.valid) {
      [self hide];
    }
    return;
  }

  SquirrelTheme* theme = SquirrelTheme.currentTheme;
  NSParagraphStyle* rulerAttrsPreedit;
  NSSize priorSize = _view.candidateCount > 0 || !_view.preeditView.hidden ? _view.contentRect.size : NSZeroSize;
  if ((indexRange.length == 0 || !updateCandidates) &&
      preedit.length > 0 && !_view.preeditView.hidden) {
    rulerAttrsPreedit = [_view.preeditContents attribute:NSParagraphStyleAttributeName
                                                 atIndex:0
                                          effectiveRange:NULL];
  }
  SquirrelCandidateInfo* candidateInfos;
  if (updateCandidates) {
    [_view.candidateContents deleteCharactersInRange:NSMakeRange(0, _view.candidateContents.length)];
    if (isnormal(theme.lineLength))
      _maxSizeAttained.width = fmin(theme.lineLength, _textWidthLimit);
    _indexRange = indexRange;
    _hilitedCandidate = hilitedCandidate;
    candidateInfos = new SquirrelCandidateInfo[indexRange.length];
  }

  // preedit
  if (preedit.length > 0) {
    _view.preeditContents.attributedString = [NSAttributedString.alloc
                                              initWithString:preedit
                                              attributes:theme.preeditAttrs];
    [_view.preeditContents.mutableString appendString:rulerAttrsPreedit ? @"\t" : kFullWidthSpace];
    if (selRange.length > 0) {
      [_view.preeditContents addAttribute:NSForegroundColorAttributeName
                                    value:theme.hilitedPreeditForeColor
                                    range:selRange];
      NSNumber* padding = @(ceil(theme.preeditParagraphStyle.minimumLineHeight * 0.05));
      if (selRange.location > 0)
        [_view.preeditContents addAttribute:NSKernAttributeName
                                      value:padding
                                      range:NSMakeRange(selRange.location - 1, 1)];
      if (NSMaxRange(selRange) < _view.preeditContents.length - 1)
        [_view.preeditContents addAttribute:NSKernAttributeName
                                      value:padding
                                      range:NSMakeRange(NSMaxRange(selRange) - 1, 1)];
    }
    [_view.preeditContents appendAttributedString:caretPos == NSNotFound || caretPos == 0 ?
     theme.symbolDeleteStroke : theme.symbolDeleteFill];
    // force caret to be rendered sideways, instead of uprights, in vertical orientation
    if (theme.vertical && caretPos != NSNotFound)
      [_view.preeditContents addAttribute:NSVerticalGlyphFormAttributeName value:@NO
                                    range:NSMakeRange(caretPos, 1)];
    if (rulerAttrsPreedit != nil)
      [_view.preeditContents addAttribute:NSParagraphStyleAttributeName
                                    value:rulerAttrsPreedit
                                    range:NSMakeRange(0, _view.preeditContents.length)];

    if (updateCandidates && indexRange.length == 0) {
      self.sectionNum = 0;
      goto AdjustAlignment;
    } else {
      [_view setHilitedPreeditRange:selRange];
    }
  } else if (_view.preeditContents.length > 0) {
    [_view.preeditContents deleteCharactersInRange:
     NSMakeRange(0, _view.preeditContents.length)];
  }

  if (!updateCandidates) {
    if (_hilitedCandidate != hilitedCandidate)
      [self highlightCandidate:hilitedCandidate];
    NSSize newSize = _view.contentRect.size;
    _needsRedraw |= !NSEqualSizes(priorSize, newSize);
    [self show];
    return;
  }

  // candidate items
  for (NSUInteger idx = 0; idx < indexRange.length; ++idx) {
    NSUInteger col = idx % theme.pageSize;
    NSMutableAttributedString* candidate = idx / theme.pageSize != _sectionNum
    ? theme.candidateDimmedTemplate.mutableCopy : idx == hilitedCandidate
    ? theme.candidateHilitedTemplate.mutableCopy : theme.candidateTemplate.mutableCopy;
    // plug in enumerator, candidate text and comment into the template
    NSRange enumRange = [candidate.mutableString rangeOfString:@"%c"];
    [candidate replaceCharactersInRange:enumRange withString:theme.rawLabels[col]];

    NSRange textRange = [candidate.mutableString rangeOfString:@"%@"];
    NSString* text = _inputController.candidateTexts[idx + indexRange.location];
    [candidate replaceCharactersInRange:textRange withString:text];

    NSRange commentRange = [candidate.mutableString rangeOfString:@"%s"];
    NSString* comment = _inputController.candidateComments[idx + indexRange.location];
    if (comment.length > 0)
      [candidate replaceCharactersInRange:commentRange withString:[@"\u00A0" append:comment]];
    else
      [candidate deleteCharactersInRange:commentRange];
    // parse markdown and ruby annotation
    [candidate formatMarkDown];
    CGFloat annotationHeight = [candidate annotateRubyInRange:NSMakeRange(0, candidate.length)
                                          verticalOrientation:theme.vertical
                                                maximumLength:_textWidthLimit
                                                scriptVariant:_optionSwitcher.currentScriptVariant];
    if (annotationHeight * 2 > theme.lineSpacing) {
      [self updateAnnotationHeight:annotationHeight];
      [candidate addAttribute:NSParagraphStyleAttributeName
                        value:theme.candidateParagraphStyle
                        range:NSMakeRange(0, candidate.length)];
      if (idx > 0) {
        if (theme.linear) {
          BOOL truncated = candidateInfos[0].truncated;
          NSUInteger location = candidateInfos[0].location;
          for (NSUInteger i = 1; i <= idx; ++i) {
            if (i == idx || candidateInfos[i].truncated != truncated) {
              [_view.candidateContents addAttribute:NSParagraphStyleAttributeName
                                              value:truncated ? theme.truncatedParagraphStyle
                                                              : theme.candidateParagraphStyle
                                              range:NSMakeRange(location, candidateInfos[i - 1].maxRange() - location)];
              if (i < idx) {
                truncated = candidateInfos[i].truncated;
                location = candidateInfos[i].location;
              }
            }
          }
        } else {
          [_view.candidateContents addAttribute:NSParagraphStyleAttributeName
                                          value:theme.candidateParagraphStyle
                                          range:NSMakeRange(0, _view.candidateContents.length)];
        }
      }
    }
    // store final in-candidate locations of label, text, and comment
    textRange = [candidate.mutableString rangeOfString:text];

    if (idx > 0 && col == 0 && theme.linear && !candidateInfos[idx - 1].truncated)
      [_view.candidateContents.mutableString appendString:@"\n"];
    NSUInteger candidateStart = _view.candidateContents.length;
    SquirrelCandidateInfo info = {.location = candidateStart, .text = textRange.location,
                                  .comment = NSMaxRange(textRange), .idx = idx, .col = col};
    [_view.candidateContents appendAttributedString:candidate];
    // for linear layout, middle-truncate candidates that are longer than one line
    if (theme.linear && NSWidth([_view.candidateView blockRectForRange:NSMakeRange(candidateStart, candidate.length)]) >
        _textWidthLimit - theme.fullWidth * (theme.tabular ? 3 : 2)) {
      if (col > 0 && !candidateInfos[idx - 1].truncated)
        [_view.candidateContents.mutableString insertString:@"\n" atIndex:candidateStart++];
      info.length = _view.candidateContents.length - candidateStart;
      info.truncated = YES;
      candidateInfos[idx] = info;
      if (idx < indexRange.length - 1)
        [_view.candidateContents.mutableString appendString:@"\n"];
      [_view.candidateContents addAttribute:NSParagraphStyleAttributeName
                                      value:theme.truncatedParagraphStyle
                                      range:NSMakeRange(candidateStart, _view.candidateContents.length - candidateStart)];
    } else {
      // separator: linear = "\u3000\x1D"; tabular = "\u3000\t\x1D"; stacked = "\n"
      if (theme.linear || idx < indexRange.length - 1)
        [_view.candidateContents appendAttributedString:theme.separator];
      info.length = candidate.length + (theme.tabular ? 3 : theme.linear ? 2: 0);
      info.truncated = NO;
      candidateInfos[idx] = info;
    }
  }

  // paging indication
  if (theme.tabular || theme.showPaging) {
    if (theme.tabular) {
      _view.pagingContents.attributedString = _locked ? theme.symbolLock : _view.expanded
        ? theme.symbolCompress : theme.symbolExpand;
    } else {
      NSAttributedString* pageNumString = [NSAttributedString.alloc
                                           initWithString:[NSString stringWithFormat:@"%lu", pageNum + 1]
                                           attributes:theme.pagingAttrs];
      _view.pagingContents.attributedString = theme.vertical ?
        pageNumString.attributedStringHorizontalInVerticalForms : pageNumString;
    }
    if (theme.showPaging) {
      [_view.pagingContents insertAttributedString:_pageNum > 0 ? theme.symbolBackFill : theme.symbolBackStroke
                                           atIndex:0];
      [_view.pagingContents.mutableString insertString:kFullWidthSpace atIndex:1];
      [_view.pagingContents.mutableString appendString:kFullWidthSpace];
      [_view.pagingContents appendAttributedString:_finalPage ? theme.symbolForwardStroke : theme.symbolForwardFill];
    }
  } else if (_view.pagingContents.length > 0) {
    [_view.pagingContents deleteCharactersInRange:
     NSMakeRange(0, _view.pagingContents.length)];
  }

AdjustAlignment:
  [_view estimateBoundsOnScreen:_screen.visibleFrame
                    withPreedit:preedit.length > 0
                     candidates:candidateInfos
                          count:indexRange.length
                         paging:indexRange.length > 0 && (theme.tabular || theme.showPaging)];
  CGFloat textWidth = clamp(NSWidth(_view.contentRect), _maxSizeAttained.width, _textWidthLimit);
  // right-align the backward delete symbol
  if (preedit.length > 0 &&
      (rulerAttrsPreedit == nil || rulerAttrsPreedit.tabStops[0].location < nexttoward(textWidth, 0.0))) {
    if (rulerAttrsPreedit == nil)
      [_view.preeditContents replaceCharactersInRange:NSMakeRange(_view.preeditContents.length - 2, 1)
                                           withString:@"\t"];
    NSMutableParagraphStyle* rulerAttrs = theme.preeditParagraphStyle.mutableCopy;
    rulerAttrs.tabStops = @[[NSTextTab.alloc initWithTextAlignment:NSTextAlignmentRight
                                                          location:textWidth
                                                           options:@{}]];
    [_view.preeditContents addAttribute:NSParagraphStyleAttributeName
                                  value:rulerAttrs
                                  range:NSMakeRange(0, _view.preeditContents.length)];
  }
  if (!theme.linear && theme.showPaging) {
    NSMutableParagraphStyle* rulerAttrsPaging = theme.pagingParagraphStyle.mutableCopy;
    [_view.pagingContents replaceCharactersInRange:NSMakeRange(1, 1)
                                        withString:@"\t"];
    [_view.pagingContents replaceCharactersInRange:NSMakeRange(_view.pagingContents.length - 2, 1)
                                        withString:@"\t"];
    rulerAttrsPaging.tabStops = @[[NSTextTab.alloc initWithTextAlignment:NSTextAlignmentCenter
                                                                location:textWidth * 0.5
                                                                 options:@{}],
                                  [NSTextTab.alloc initWithTextAlignment:NSTextAlignmentRight
                                                                location:textWidth
                                                                 options:@{}]];
    [_view.pagingContents addAttribute:NSParagraphStyleAttributeName
                                 value:rulerAttrsPaging
                                 range:NSMakeRange(0, _view.pagingContents.length)];
  }

  self.animationBehavior = NSWindowAnimationBehaviorDefault;
  [_view drawViewWithHilitedCandidate:hilitedCandidate
                  hilitedPreeditRange:selRange];
  NSSize newSize = _view.contentRect.size;
  _needsRedraw |= !NSEqualSizes(priorSize, newSize);
  [self show];
}

- (void)updateStatusLong:(NSString*)messageLong
             statusShort:(NSString*)messageShort {
  switch (SquirrelTheme.currentTheme.statusMessageType) {
    case kStatusMessageTypeMixed:
      _statusMessage = messageShort ? : messageLong;
      break;
    case kStatusMessageTypeLong:
      _statusMessage = messageLong;
      break;
    case kStatusMessageTypeShort:
      _statusMessage = messageShort ? : messageLong ?
                       [messageLong substringWithRange:
                        [messageLong rangeOfComposedCharacterSequenceAtIndex:0]] : nil;
      break;
  }
}

- (void)showStatus:(NSString*)message __attribute__((objc_direct)) {
  NSSize priorSize = !_view.statusView.hidden ? _view.contentRect.size : NSZeroSize;

  [_view.candidateContents deleteCharactersInRange:NSMakeRange(0, _view.candidateContents.length)];
  [_view.preeditContents deleteCharactersInRange:NSMakeRange(0, _view.preeditContents.length)];
  [_view.pagingContents deleteCharactersInRange:NSMakeRange(0, _view.pagingContents.length)];

  _view.statusContents.attributedString =
    [NSAttributedString.alloc initWithString:[NSString stringWithFormat:@"\u3000\u2002%@", message]
                                  attributes:SquirrelTheme.currentTheme.statusAttrs];
  [_view estimateBoundsOnScreen:_screen.visibleFrame
                    withPreedit:NO
                     candidates:NULL
                          count:0
                         paging:NO];

  // disable remember_size and fixed line_length for status messages
  _maxSizeAttained = NSZeroSize;
  if (_statusTimer.valid)
    [_statusTimer invalidate];
  self.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;
  [_view drawViewWithHilitedCandidate:NSNotFound
                  hilitedPreeditRange:NSMakeRange(NSNotFound, 0)];
  NSSize newSize = _view.contentRect.size;
  _needsRedraw |= !NSEqualSizes(priorSize, newSize);
  [self show];
  _statusTimer = [NSTimer scheduledTimerWithTimeInterval:kShowStatusDuration
                                                  target:self
                                                selector:@selector(hideStatus:)
                                                userInfo:nil
                                                 repeats:NO];
}

- (void)hideStatus:(NSTimer*)timer {
  [self hide];
}

- (void)updateAnnotationHeight:(CGFloat)height __attribute__((objc_direct)) {
  [SquirrelTheme.lightTheme setAnnotationHeight:height];
  if (@available(macOS 10.14, *))
    [SquirrelTheme.darkTheme setAnnotationHeight:height];
  _view.candidateView.defaultParagraphStyle = SquirrelTheme.currentTheme.candidateParagraphStyle;
}

- (void)loadLabelConfig:(SquirrelConfig*)config
           directUpdate:(BOOL)update {
  [SquirrelTheme.lightTheme updateLabelsWithConfig:config
                                      directUpdate:update];
  if (@available(macOS 10.14, *))
    [SquirrelTheme.darkTheme updateLabelsWithConfig:config
                                       directUpdate:update];
  if (update)
    [self updateDisplayParameters];
}

- (void)loadConfig:(SquirrelConfig*)config {
  [SquirrelTheme.lightTheme updateWithConfig:config
                                styleOptions:_optionSwitcher.optionStates
                               scriptVariant:_optionSwitcher.currentScriptVariant];
  if (@available(macOS 10.14, *))
    [SquirrelTheme.darkTheme updateWithConfig:config
                                 styleOptions:_optionSwitcher.optionStates
                                scriptVariant:_optionSwitcher.currentScriptVariant];
  [self getLocked];
  [self updateDisplayParameters];
}

- (void)updateScriptVariant {
  [SquirrelTheme.lightTheme updateScriptVariant:_optionSwitcher.currentScriptVariant];
  if (@available(macOS 10.14, *))
    [SquirrelTheme.darkTheme updateScriptVariant:_optionSwitcher.currentScriptVariant];
}

@end  // SquirrelPanel
