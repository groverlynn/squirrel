#import <Cocoa/Cocoa.h>
#import "SquirrelInputController.hh"

@class SquirrelConfig;
@class SquirrelOptionSwitcher;

@interface SquirrelPanel : NSPanel <NSWindowDelegate>

// Show preedit text inline.
@property(nonatomic, readonly) BOOL inlinePreedit;
// Show primary candidate inline
@property(nonatomic, readonly) BOOL inlineCandidate;
// Vertical text orientation, as opposed to horizontal text orientation.
@property(nonatomic, readonly) BOOL vertical;
// Linear candidate list layout, as opposed to stacked candidate list layout.
@property(nonatomic, readonly) BOOL linear;
// Tabular candidate list layout, initializes as tab-aligned linear layout,
// expandable to stack 5 (3 for vertical) pages/sections of candidates
@property(nonatomic, readonly) BOOL tabular;
@property(nonatomic, readonly) BOOL locked;
@property(nonatomic, readonly) BOOL firstLine;
@property(nonatomic) BOOL expanded;
@property(nonatomic) NSUInteger sectionNum;
// position of the text input I-beam cursor on screen.
@property(nonatomic) NSRect IbeamRect;
@property(nonatomic, strong, readonly, nullable) NSScreen *screen;
@property(nonatomic, weak, readonly, nullable) SquirrelInputController *inputController;
// Status message before pop-up is displayed; nil before normal panel is displayed
@property(nonatomic, strong, readonly, nullable) NSString *statusMessage;
// Store switch options that change style (color theme) settings
@property(nonatomic, strong, nonnull) SquirrelOptionSwitcher *optionSwitcher;

// query
- (NSUInteger)candidateIndexOnDirection:(SquirrelIndex)arrowKey;
- (NSUInteger)numCachedCandidates;
// updating contents
- (void)setCandidateAtIndex:(NSUInteger)index
                   withText:(NSString * _Nullable)text
                    comment:(NSString * _Nullable)comment;
- (void)updateStatusLong:(NSString * _Nullable)messageLong
             statusShort:(NSString * _Nullable)messageShort;
// display
- (void)showPreedit:(NSString * _Nullable)preeditString
           selRange:(NSRange)selRange
           caretPos:(NSUInteger)caretPos
   candidateIndices:(NSRange)indexRange
   highlightedIndex:(NSUInteger)highlightedIndex
            pageNum:(NSUInteger)pageNum
          finalPage:(BOOL)finalPage
         didCompose:(BOOL)didCompose;
- (void)hide;
// settings
- (void)loadConfig:(SquirrelConfig * _Nonnull)config;
- (void)loadLabelConfig:(SquirrelConfig * _Nonnull)config
           directUpdate:(BOOL)update;
- (void)updateScriptVariant;

@end  // SquirrelPanel
