#import "SquirrelInputController.hh"

#import "SquirrelApplicationDelegate.hh"
#import "SquirrelConfig.hh"
#import "SquirrelPanel.hh"
#import "macos_keycode.hh"
#import <rime_api_stdbool.h>
#import <rime_api.h>
#import <rime/key_table.h>
#import <IOKit/hid/IOHIDLib.h>
#import <IOKit/hidsystem/IOHIDLib.h>

static const int N_KEY_ROLL_OVER = 50;

@implementation SquirrelInputController {
  NSMutableAttributedString* _inlineString;
  NSString* _originalString;
  NSString* _composedString;
  NSString* _schemaId;
  NSRange _selSegment;
  NSRange _candidateIndices;
  NSRange _inlineSelRange;
  NSUInteger _inlineCaretPos;
  NSUInteger _currentIndex;
  NSEventModifierFlags _lastModifiers;
  uint _lastEventCount;
  UCKeyboardLayout* _keyLayout;
  uint _deadKeyState;
  BOOL _inlinePreedit;
  BOOL _inlineCandidate;
  BOOL _showingSwitcherMenu;
  BOOL _showingInitialStatus;
  // app-specific options and bug fix
  SquirrelAppOptions* _appOptions;
  bool _inlinePlaceholder;
  bool _panellessCommitFix;
  double _inlineOffset;
  // for chord-typing
  NSTimer* _chordTimer;

  int _chordKeyCodes[N_KEY_ROLL_OVER];
  int _chordModifiers[N_KEY_ROLL_OVER];
  int _chordKeyCount;
}

static SquirrelInputController* __weak _currentController = nil;
static NSString* _currentApp;
static NSString* _keyboardLayout;
static NSTimeInterval _chordDuration = 0.1;
static int _asciiMode = -1;
static BOOL _goodOldCapsLock = NO;

+ (void)setCurrentController:(SquirrelInputController*)controller {
  _currentController = controller;
  NSApp.SquirrelAppDelegate.panel.IbeamRect = NSZeroRect;
}

+ (SquirrelInputController*)currentController {
  return _currentController;
}

+ (void)setChordDuration:(NSTimeInterval)duration {
  _chordDuration = duration;
}

+ (NSTimeInterval)chordDuration {
  return _chordDuration;
}

+ (void)setGoodOldCapsLock:(BOOL)goodOldCapsLock {
  _goodOldCapsLock = goodOldCapsLock;
}

+ (BOOL)goodOldCapsLock {
  return _goodOldCapsLock;
}

+ (NSString*)keyboardLayout {
  return _keyboardLayout;
}

+ (void)setKeyboardLayout:(NSString*)keyboardLayout {
  _keyboardLayout = keyboardLayout;
}

- (NSAppearance*)viewEffectiveAppearance {
  return [self.client performSelector:@selector(viewEffectiveAppearance)] ? : NSAppearance.currentAppearance;
}

+ (NSSet<NSString*>*)keyPathsForValuesAffectingViewEffectiveAppearance {
  return [NSSet setWithObjects:@"client.viewEffectiveAppearance", nil];
}

static NSRegularExpression* kLayoutRegex =
  [NSRegularExpression.alloc initWithPattern:@"\\w+(\\.\\w+){3,}" options:0 error:nil];

- (void)activateServer:(id)sender {
  // NSLog(@"activateServer:");
  [super activateServer:sender];
  _lastModifiers = 0;
  _lastEventCount = 0;
  _candidateTexts = NSMutableArray.alloc.init;
  _candidateComments = NSMutableArray.alloc.init;
  NSApp.SquirrelAppDelegate.panel.IbeamRect = NSZeroRect;
  self.class.currentController = self;
  [self addObserver:NSApp.SquirrelAppDelegate.panel
         forKeyPath:@"viewEffectiveAppearance"
            options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
            context:nil];
  [self createSession];

  if (_keyboardLayout.length == 0 || [@"last" caseInsensitiveCompare:_keyboardLayout] == NSOrderedSame) {
  } else if ([@"default" caseInsensitiveCompare:_keyboardLayout] == NSOrderedSame) {
    [sender overrideKeyboardWithKeyboardNamed:@"com.apple.keylayout.ABC"];
  } else if ([kLayoutRegex numberOfMatchesInString:_keyboardLayout options:0 range:NSMakeRange(0, _keyboardLayout.length)] > 0) {
    [sender overrideKeyboardWithKeyboardNamed:_keyboardLayout];
  } else {
    [sender overrideKeyboardWithKeyboardNamed:[@"com.apple.keylayout." append:_keyboardLayout]];
  }
  CFDataRef uchr = (CFDataRef)TISGetInputSourceProperty(TISCopyCurrentKeyboardLayoutInputSource(), kTISPropertyUnicodeKeyLayoutData);
  _keyLayout = (UCKeyboardLayout*)CFDataGetBytePtr(uchr);

  if (!NSApp.SquirrelAppDelegate.isCurrentInputMethod) {
    NSApp.SquirrelAppDelegate.isCurrentInputMethod = YES;
    if (NSApp.SquirrelAppDelegate.showNotifications == kShowNotificationsAlways)
      [self showInitialStatus];
  }
}

- (void)deactivateServer:(id)sender {
  // NSLog(@"deactivateServer:");
  _asciiMode = (int)rime_get_api_stdbool()->get_option(_session, "ascii_mode");
  [self commitComposition:sender];
  [self destroySession];
  [self removeObserver:NSApp.SquirrelAppDelegate.panel
            forKeyPath:@"viewEffectiveAppearance"];
  [super deactivateServer:sender];
}

- (NSUInteger)recognizedEvents:(id)sender {
  // NSLog(@"recognizedEvents:");
  return NSEventMaskKeyDown | NSEventMaskFlagsChanged | NSEventMaskLeftMouseDown;
}

/** - Receive incoming event:
      - Return `YES` to indicate the the key input was received and dealt with.
        Key processing will not continue in that case. In other words,
        the system will not deliver a key-down event to the application.
      - Returning `NO` means the original key down will be passed on to the client. */
- (BOOL)handleEvent:(NSEvent*)event
             client:(id)sender {
  BOOL handled = NO;

  @autoreleasepool {
    if (_session == 0 || !rime_get_api_stdbool()->find_session(_session)) {
      [self createSession];
      if (_session == 0)
        return NO;
    }
    NSEventModifierFlags modifiers = event.modifierFlags;
    int rime_modifiers = RimeModifiers(modifiers);
    ushort keyCode = (ushort)CGEventGetIntegerValueField(event.CGEvent, kCGKeyboardEventKeycode);

    switch (event.type) {
      case NSEventTypeFlagsChanged: {
        if (_lastModifiers == modifiers)
          return YES;
        // NSLog(@"FLAGSCHANGED client: %@, modifiers: 0x%lx", sender, modifiers);
        int release_mask = 0;
        int rime_keycode = RimeKeycode(keyCode);
        uint eventCount = CGEventSourceCounterForEventType(kCGEventSourceStateCombinedSessionState, kCGEventFlagsChanged) +
                          CGEventSourceCounterForEventType(kCGEventSourceStateCombinedSessionState, kCGEventKeyDown) +
                          CGEventSourceCounterForEventType(kCGEventSourceStateCombinedSessionState, kCGEventLeftMouseDown) +
                          CGEventSourceCounterForEventType(kCGEventSourceStateCombinedSessionState, kCGEventRightMouseDown) +
                          CGEventSourceCounterForEventType(kCGEventSourceStateCombinedSessionState, kCGEventOtherMouseDown);
        _lastModifiers = modifiers;
        switch (keyCode) {
          case kVK_CapsLock:
            if (!_goodOldCapsLock) {
              set_CapsLock_LED_state(false);
              bool ascii_mode = rime_get_api_stdbool()->get_option(_session, "ascii_mode");
              rime_modifiers = ascii_mode ? rime_modifiers | kLockMask : rime_modifiers & ~kLockMask;
            } else {
              rime_modifiers ^= kLockMask;
              // avoid overlapping with capslock accessory view
              if (@available(macOS 14.0, *))
                NSApp.SquirrelAppDelegate.panel.IbeamRect = NSZeroRect;
            }
            handled = [self processKey:rime_keycode modifiers:rime_modifiers];
            break;
          case kVK_Shift:
          case kVK_RightShift:
            release_mask = modifiers & NSEventModifierFlagShift ? 0 :
                           kReleaseMask | (eventCount - _lastEventCount == 1 ? 0 : kIgnoredMask);
            handled = [self processKey:rime_keycode modifiers:(rime_modifiers | release_mask)];
            break;
          case kVK_Control:
          case kVK_RightControl:
            release_mask = modifiers & NSEventModifierFlagControl ? 0 :
                           kReleaseMask | (eventCount - _lastEventCount == 1 ? 0 : kIgnoredMask);
            handled = [self processKey:rime_keycode modifiers:(rime_modifiers | release_mask)];
            break;
          case kVK_Option:
          case kVK_RightOption:
            if (modifiers == NSEventModifierFlagOption && NSApp.SquirrelAppDelegate.panel.showToolTip) {
              _lastEventCount = eventCount;
              return YES;
            }
            release_mask = modifiers & NSEventModifierFlagOption ? 0 :
                           kReleaseMask | (eventCount - _lastEventCount == 1 ? 0 : kIgnoredMask);
            handled = [self processKey:rime_keycode modifiers:(rime_modifiers | release_mask)];
            break;
          case kVK_Function:
            release_mask = modifiers & NSEventModifierFlagFunction ? 0 :
                           kReleaseMask | (eventCount - _lastEventCount == 1 ? 0 : kIgnoredMask);
            handled = [self processKey:rime_keycode modifiers:(rime_modifiers | release_mask)];
            break;
          case kVK_Command:
          case kVK_RightCommand:
            release_mask = modifiers & NSEventModifierFlagCommand ? 0 :
                           kReleaseMask | (eventCount - _lastEventCount == 1 ? 0 : kIgnoredMask);
            handled = [self processKey:rime_keycode modifiers:(rime_modifiers | release_mask)];
            break;
        }
        if (handled || NSApp.SquirrelAppDelegate.panel.hasStatusMessage) {
          [self rimeUpdate];
          handled |= YES;
        }
        _lastEventCount = eventCount;
      } break;
      case NSEventTypeKeyDown: {
        // NSLog(@"KEYDOWN client: %@, modifiers: 0x%lx, keyCode: %d", sender, modifiers, keyCode);
        // translate mac keydown events to rime keyevents
        if (_deadKeyState != 0 || self.server.lastKeyEventWasDeadKey) {
          if (_composedString.length > 0)
            [self commitComposition:sender];
          UniCharCount length = 0;
          UniChar string[8];
          OSStatus status = UCKeyTranslate(_keyLayout, keyCode, kUCKeyActionDown, modifierKeyState(modifiers),
                                           LMGetKbdType(), 0, &_deadKeyState, 8, &length, string);
          if (length == 0 && _deadKeyState != 0) {
            UInt32 state = _deadKeyState;
            status = UCKeyTranslate(_keyLayout, keyCode, kUCKeyActionDown, modifierKeyState(modifiers),
                                    LMGetKbdType(), 0, &state, 8, &length, string);
            if (length > 0 && status == noErr)
              [self showInlineString:[NSString stringWithCharacters:string length:length]
                        withSelRange:NSMakeRange(0, length) caretPos:length];
          } else if (length > 0 && status == noErr) {
            [self commitString:[NSString stringWithCharacters:string length:length]];
            _deadKeyState = 0;
          }
          return YES;
        }
        int rime_keycode = RimeKeycode(keyCode);
        if (rime_keycode == 0) {
          NSString* keyChars = ((modifiers & NSEventModifierFlagShift) &&
                                !(modifiers & (NSEventModifierFlagControl | NSEventModifierFlagOption))) ?
                               event.characters : event.charactersIgnoringModifiers;
          rime_keycode = RimeKeycode([keyChars characterAtIndex:0],
                                     (modifiers & NSEventModifierFlagShift) != 0,
                                     (modifiers & NSEventModifierFlagCapsLock) != 0);
        } else if ((0x60 <= keyCode && keyCode <= 0xFF) || keyCode == 0x50 ||
                   keyCode == 0x4F || keyCode == 0x47 || keyCode == 0x40) {
          // revert non-modifier function keys' FunctionKeyMask (FwdDel, Navigations, F1..F19)
          rime_modifiers &= ~kHyperMask;
        }
        if (rime_keycode != 0) {
          if ((handled = [self processKey:rime_keycode modifiers:rime_modifiers])) {
            [self rimeUpdate];
          } else if (_panellessCommitFix && self.client.markedRange.length > 0) {
            if (rime_keycode == XK_Delete || (rime_keycode >= XK_Home && rime_keycode <= XK_KP_Delete) ||
                (rime_keycode >= XK_BackSpace && rime_keycode <= XK_Escape)) {
              [self showPlaceholder:@""];
            } else if ((modifiers & (NSEventModifierFlagControl | NSEventModifierFlagCommand)) == 0 &&
                       event.characters.length > 0) {
              [self showPlaceholder:nil];
              [self.client insertText:event.characters
                     replacementRange:NSMakeRange(NSNotFound, 0)];
              return YES;
            }
          } else if (_composedString.length > 0) {
            [self commitComposition:sender];
            return NO;
          }
        }
      } break;
      default:
        break;
    }
  }
  return handled;
}

- (BOOL)mouseDownOnCharacterIndex:(NSUInteger)index
                       coordinate:(NSPoint)point
                     withModifier:(NSUInteger)flags
                 continueTracking:(BOOL*)keepTracking
                           client:(id)sender {
  *keepTracking = NO;
  if ((!_inlinePreedit && !_inlineCandidate) || _composedString.length == 0 ||
      _inlineCaretPos == index || (flags & NSEventModifierFlagDeviceIndependentFlagsMask) != 0)
    return NO;
  NSRange markedRange = [sender markedRange];
  NSPoint head = [[sender attributesForCharacterIndex:0
                                  lineHeightRectangle:NULL][@"IMKBaseline"] pointValue];
  NSPoint tail = [[sender attributesForCharacterIndex:markedRange.length - 1
                                  lineHeightRectangle:NULL][@"IMKBaseline"] pointValue];
  if (point.x > nexttoward(tail.x, INFINITY) || index >= markedRange.length) {
    if (_inlineCandidate && !_inlinePreedit)
      return NO;
    [self performAction:kPROCESS onIndex:kEndKey];
  } else if (point.x < nexttoward(head.x, -INFINITY) || index <= 0) {
    [self performAction:kPROCESS onIndex:kHomeKey];
  } else {
    [self moveCursor:_inlineCaretPos
          toPosition:index
       inlinePreedit:_inlinePreedit
     inlineCandidate:_inlineCandidate];
  }
  return YES;
}

static void set_CapsLock_LED_state(bool target_state) {
  io_service_t ioService = IOServiceGetMatchingService(kIOMasterPortDefault,
                            IOServiceMatching(kIOHIDSystemClass));
  io_connect_t ioConnect = 0;
  IOServiceOpen(ioService, mach_task_self_, kIOHIDParamConnectType, &ioConnect);
  bool current_state = false;
  IOHIDGetModifierLockState(ioConnect, kIOHIDCapsLockState, &current_state);
  if (current_state != target_state)
    IOHIDSetModifierLockState(ioConnect, kIOHIDCapsLockState, target_state);
  IOServiceClose(ioConnect);
}

- (BOOL)processKey:(int)rime_keycode
         modifiers:(int)rime_modifiers __attribute__((objc_direct)) {
  SquirrelPanel* panel = NSApp.SquirrelAppDelegate.panel;
  BOOL is_navigator_in_tabular = panel.tabular && !rime_modifiers && panel.visible &&
       (panel.vertical ? rime_keycode == XK_Left || rime_keycode == XK_KP_Left ||
                         rime_keycode == XK_Right || rime_keycode == XK_KP_Right
                       : rime_keycode == XK_Up || rime_keycode == XK_KP_Up ||
                         rime_keycode == XK_Down || rime_keycode == XK_KP_Down);
  if (is_navigator_in_tabular) {
    if (rime_keycode >= XK_KP_Left && rime_keycode <= XK_KP_Down)
      rime_keycode = rime_keycode - XK_KP_Left + XK_Left;

    NSUInteger newIndex = [panel candidateIndexOnDirection:(SquirrelIndex)rime_keycode];
    if (newIndex != NSNotFound) {
      if (!panel.locked && !panel.expanded && rime_keycode == (panel.vertical ? XK_Left : XK_Down))
         panel.expanded = YES;
      rime_get_api_stdbool()->highlight_candidate(_session, newIndex);
      return YES;
    } else if (!panel.locked && panel.expanded && panel.sectionNum == 0 &&
               rime_keycode == (panel.vertical ? XK_Right : XK_Up)) {
      panel.expanded = NO;
      return YES;
    }
  }

  bool handled = rime_get_api_stdbool()->process_key(_session, rime_keycode, rime_modifiers);
  // NSLog(@"rime_keycode: 0x%x, rime_modifiers: 0x%x, handled = %d", rime_keycode, rime_modifiers, handled);

  // TODO add special key event postprocessing here

  if (!handled) {
    BOOL is_vim_back_in_command_mode = rime_keycode == XK_Escape ||
          ((rime_modifiers & kControlMask) && (rime_keycode == XK_c ||
            rime_keycode == XK_C || rime_keycode == XK_bracketleft));
    if (is_vim_back_in_command_mode && rime_get_api_stdbool()->get_option(_session, "vim_mode") &&
        !rime_get_api_stdbool()->get_option(_session, "ascii_mode")) {
      [self cancelComposition];
      rime_get_api_stdbool()->set_option(_session, "ascii_mode", True);
      // NSLog(@"turned Chinese mode off in vim-like editor's command mode");
      return YES;
    }
  }

  // Simulate key-ups for every interesting key-down for chord-typing.
  if (handled) {
    BOOL is_chording_key = (rime_keycode >= XK_space && rime_keycode <= XK_asciitilde) ||
                            rime_keycode == XK_Control_L || rime_keycode == XK_Control_R ||
                            rime_keycode == XK_Alt_L || rime_keycode == XK_Alt_R ||
                            rime_keycode == XK_Shift_L || rime_keycode == XK_Shift_R;
    if (is_chording_key && rime_get_api_stdbool()->get_option(_session, "_chord_typing"))
      [self updateChord:rime_keycode modifiers:rime_modifiers];
    else if ((rime_modifiers & kReleaseMask) == 0) // non-chording key pressed
      [self clearChord];
  }

  return handled;
}

- (void)moveCursor:(NSUInteger)cursorPosition
        toPosition:(NSUInteger)targetPosition
     inlinePreedit:(BOOL)inlinePreedit
   inlineCandidate:(BOOL)inlineCandidate __attribute__((objc_direct)); {
  BOOL vertical = NSApp.SquirrelAppDelegate.panel.vertical;
  @autoreleasepool {
    NSString* composition = !inlinePreedit && !inlineCandidate ?
      _composedString : _inlineString.string;
    RIME_STRUCT(RimeContext_stdbool, ctx);
    if (cursorPosition > targetPosition) {
      NSString* targetPrefix = [[composition substringToIndex:targetPosition]
                                stringByReplacingOccurrencesOfString:@" "
                                withString:@""];
      NSString* prefix = [[composition substringToIndex:cursorPosition]
                          stringByReplacingOccurrencesOfString:@" "
                          withString:@""];
      BOOL noneConverted = [_originalString hasSuffix:[[composition substringFromIndex:targetPosition]
                                                       stringByReplacingOccurrencesOfString:@" " withString:@""]];
      while (targetPrefix.length < prefix.length) {
        BOOL byChar = noneConverted && ![[prefix substringFromIndex:targetPrefix.length] containsString:@" "];
        rime_get_api_stdbool()->process_key(_session, vertical ? (byChar ? XK_KP_Up : XK_Up) : (byChar ? XK_KP_Left : XK_Left), 0);
        rime_get_api_stdbool()->get_context(_session, &ctx);
        if (inlineCandidate) {
          int length = ctx.composition.cursor_pos < ctx.composition.sel_end ? ctx.composition.cursor_pos :
            (int)strlen(ctx.commit_text_preview) - (inlinePreedit ? 0 : ctx.composition.cursor_pos - ctx.composition.sel_end);
          prefix = [[NSString.alloc initWithBytes:ctx.commit_text_preview
                                           length:(NSUInteger)length
                                         encoding:NSUTF8StringEncoding]
                    stringByReplacingOccurrencesOfString:@" "
                    withString:@""];
        } else {
          prefix = [[NSString.alloc initWithBytes:ctx.composition.preedit
                                           length:(NSUInteger)ctx.composition.cursor_pos
                                         encoding:NSUTF8StringEncoding]
                    stringByReplacingOccurrencesOfString:@" "
                    withString:@""];
        }
        rime_get_api_stdbool()->free_context(&ctx);
      }
    } else if (cursorPosition < targetPosition) {
      NSString* targetSuffix = [[composition substringFromIndex:targetPosition]
                                stringByReplacingOccurrencesOfString:@" "
                                withString:@""];
      NSString* suffix = [[composition substringFromIndex:cursorPosition]
                          stringByReplacingOccurrencesOfString:@" "
                          withString:@""];
      while (targetSuffix.length < suffix.length) {
        rime_get_api_stdbool()->process_key(_session, vertical ? XK_Down : XK_Right, 0);
        rime_get_api_stdbool()->get_context(_session, &ctx);
        suffix = [@(ctx.composition.preedit + ctx.composition.cursor_pos + (!inlinePreedit && !inlineCandidate ? 3 : 0))
                  stringByReplacingOccurrencesOfString:@" "
                  withString:@""];
        rime_get_api_stdbool()->free_context(&ctx);
      }
    }
    [self rimeUpdate];
  }
}

- (void)performAction:(SquirrelAction)action
              onIndex:(SquirrelIndex)index __attribute__((objc_direct)) {
  // NSLog(@"perform action: %lu on index: %lu", action, index);
  bool handled = false;
  switch (action) {
    case kPROCESS:
      if (index >= 0xFF08 && index <= 0xFFFF) {
        handled = rime_get_api_stdbool()->process_key(_session, (int)index, 0);
      } else if (index >= kExpandButton && index <= kLockButton) {
        handled = true;
        _currentIndex = NSNotFound;
      }
      break;
    case kSELECT:
      handled = rime_get_api_stdbool()->select_candidate(_session, index);
      break;
    case kHIGHLIGHT:
      handled = rime_get_api_stdbool()->highlight_candidate(_session, index);
      _currentIndex = NSNotFound;
      break;
    case kDELETE:
      handled = rime_get_api_stdbool()->delete_candidate(_session, index);
      break;
  }
  if (handled)
    [self rimeUpdate];
}

- (void)onChordTimer:(NSTimer*)timer  {
  // chord release triggered by timer
  int processedKeyCount = 0;
  if (_chordKeyCount > 0 && _session != 0) {
    // simulate key-ups
    for (int i = 0; i < _chordKeyCount; ++i) {
      if (rime_get_api_stdbool()->process_key(_session, _chordKeyCodes[i], _chordModifiers[i] | kReleaseMask))
        ++processedKeyCount;
    }
  }
  [self clearChord];
  if (processedKeyCount > 0)
    [self rimeUpdate];
}

- (void)updateChord:(int)keycode
          modifiers:(int)modifiers __attribute__((objc_direct)) {
  // NSLog(@"update chord: {%s} << %x", _chord, keycode);
  for (int i = 0; i < _chordKeyCount; ++i) {
    if (_chordKeyCodes[i] == keycode)
      return;
  }
  // you are cheating. only one human typist (fingers <= 10) is supported.
  if (_chordKeyCount >= N_KEY_ROLL_OVER)
    return;
  _chordKeyCodes[_chordKeyCount] = keycode;
  _chordModifiers[_chordKeyCount] = modifiers;
  ++_chordKeyCount;
  // reset timer
  if (_chordTimer.valid)
    [_chordTimer invalidate];
  _chordTimer = [NSTimer scheduledTimerWithTimeInterval:_chordDuration
                                                 target:self
                                               selector:@selector(onChordTimer:)
                                               userInfo:nil
                                                repeats:NO];
}

- (void)clearChord __attribute__((objc_direct)) {
  _chordKeyCount = 0;
  if (_chordTimer.valid) {
    [_chordTimer invalidate];
    _chordTimer = nil;
  }
}

static NSString* getOptionLabel(RimeSessionId session, const char* option, bool state) {
  if (RimeStringSlice short_label = rime_get_api_stdbool()->get_state_label_abbreviated(session, option, state, true);
      short_label.str != NULL && short_label.length >= strlen(short_label.str)) {
    return @(short_label.str);
  } else {
    RimeStringSlice long_label = rime_get_api_stdbool()->get_state_label_abbreviated(session, option, state, false);
    NSString* label = long_label.str != NULL ? @(long_label.str) : nil;
    return [label substringWithRange:[label rangeOfComposedCharacterSequenceAtIndex:0]];
  }
}

- (void)showInitialStatus __attribute__((objc_direct)) {
  RIME_STRUCT(RimeStatus_stdbool, status);
  if (_session != 0 && rime_get_api_stdbool()->get_status(_session, &status)) {
    NSString* schemaName = @(status.schema_name ? : status.schema_id);
    NSMutableArray<NSString*>* options = [NSMutableArray.alloc initWithCapacity:3];
    if (NSString* asciiMode = getOptionLabel(_session, "ascii_mode", status.is_ascii_mode))
      [options addObject:asciiMode];
    if (NSString* fullShape = getOptionLabel(_session, "full_shape", status.is_full_shape))
      [options addObject:fullShape];
    if (NSString* asciiPunct = getOptionLabel(_session, "ascii_punct", status.is_ascii_punct))
      [options addObject:asciiPunct];
    rime_get_api_stdbool()->free_status(&status);
    NSString* foldedOptions = options.count == 0 ? schemaName :
      [NSString stringWithFormat:@"%@ ￨ %@", schemaName, [options componentsJoinedByString:@" "]];
    [NSApp.SquirrelAppDelegate.panel updateStatusLong:foldedOptions statusShort:schemaName];
    if (@available(macOS 14.0, *))
      _showingInitialStatus = YES;
    [self rimeUpdate];
  }
}

- (void)commitComposition:(id)sender {
  // NSLog(@"commitComposition:");
  if (_session != 0) {
    rime_get_api_stdbool()->commit_composition(_session);
    RIME_STRUCT(RimeCommit, commit);
    if (rime_get_api_stdbool()->get_commit(_session, &commit)) {
      [self commitString:@(commit.text)];
      rime_get_api_stdbool()->free_commit(&commit);
    }
  }
  [self hidePalettes];
}

- (void)clearBuffer __attribute__((objc_direct)) {
  NSApp.SquirrelAppDelegate.panel.IbeamRect = NSZeroRect;
  _inlineString = nil;
  _originalString = nil;
  _composedString = nil;
  _deadKeyState = 0;
}

// Though we specify AppDelegate as the menu action receiver, Inputcontroller
// is the one that actually receives the event. Here we relay these messages.
- (void)showSwitcher:(id)sender {
  [NSApp.SquirrelAppDelegate showSwitcher:@(_session)];
  [self rimeUpdate];
}

- (void)deploy:(id)sender {
  [NSApp.SquirrelAppDelegate deploy:sender];
}

- (void)syncUserData:(id)sender {
  [NSApp.SquirrelAppDelegate syncUserData:sender];
}

- (void)configure:(id)sender {
  [NSApp.SquirrelAppDelegate configure:sender];
}

- (void)checkForUpdates:(id)sender {
  [NSApp.SquirrelAppDelegate.updater performSelector:@selector(checkForUpdates:)
                                          withObject:sender];
}

- (void)openWiki:(id)sender {
  [NSApp.SquirrelAppDelegate openWiki:sender];
}

- (void)openLogFolder:(id)sender {
  [NSApp.SquirrelAppDelegate openLogFolder:sender];
}

- (NSMenu*)menu {
  return NSApp.SquirrelAppDelegate.menu;
}

- (NSAttributedString*)originalString:(id)sender {
  return [NSAttributedString.alloc initWithString:_originalString];
}

- (id)composedString:(id)sender {
  return [_composedString stringByReplacingOccurrencesOfString:@" "
                                                    withString:@""];
}

- (NSArray*)candidates:(id)sender {
  return [_candidateTexts subarrayWithRange:_candidateIndices];
}

- (void)hidePalettes {
  [NSApp.SquirrelAppDelegate.panel hide];
  [super hidePalettes];
}

- (NSRange)selectionRange {
  return NSMakeRange(_inlineCaretPos, 0);
}

- (NSRange)replacementRange {
  return NSMakeRange(NSNotFound, 0);
}

- (void)commitString:(id)string {
  // NSLog(@"commitString:");
  if (string != nil)
    [self.client insertText:string
           replacementRange:NSMakeRange(NSNotFound, 0)];
  [self clearBuffer];
}

- (void)cancelComposition {
  [self commitString:[self originalString:self.client]];
  [self hidePalettes];
  if (_session != 0)
    rime_get_api_stdbool()->clear_composition(_session);
}

- (void)updateComposition {
  [self.client setMarkedText:_inlineString ? : @""
              selectionRange:NSMakeRange(_inlineCaretPos, 0)
            replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)showPlaceholder:(NSString*)placeholder __attribute__((objc_direct)) {
  NSDictionary* attrs = [self markForStyle:kTSMHiliteSelectedRawText
                                   atRange:NSMakeRange(0, placeholder ? placeholder.length : 1)];
  _inlineString = [NSMutableAttributedString.alloc initWithString:placeholder ? : @"█"
                                                       attributes:attrs];
  _inlineCaretPos = 0;
  [self updateComposition];
}

- (void)showInlineString:(NSString*)inlineString
            withSelRange:(NSRange)selRange
                caretPos:(NSUInteger)caretPos __attribute__((objc_direct)) {
  // NSLog(@"showInlineString: '%@'", inlineString);
  if (caretPos == _inlineCaretPos && NSEqualRanges(selRange, _inlineSelRange) &&
      [inlineString isEqualToString:_inlineString.string])
    return;
  _inlineSelRange = selRange;
  _inlineCaretPos = caretPos;
  // NSLog(@"selRange.location = %ld, selRange.length = %ld; caretPos = %ld",
  //       range.location, range.length, pos);
  NSDictionary* attrs = [self markForStyle:kTSMHiliteRawText
                                   atRange:NSMakeRange(0, inlineString.length)];
  _inlineString = [NSMutableAttributedString.alloc initWithString:inlineString
                                                       attributes:attrs];
  if (selRange.location > 0)
    [_inlineString setAttributes:[self markForStyle:kTSMHiliteConvertedText
                                            atRange:NSMakeRange(0, selRange.location)]
                           range:NSMakeRange(0, selRange.location)];
  if (selRange.location < caretPos)
    [_inlineString setAttributes:[self markForStyle:kTSMHiliteSelectedRawText
                                            atRange:selRange]
                           range:selRange];
  [self updateComposition];
}

- (void)showPanelWithPreedit:(NSString*)preedit
                    selRange:(NSRange)selRange
                    caretPos:(NSUInteger)caretPos
            candidateIndices:(NSRange)candidateIndices
            hilitedCandidate:(NSUInteger)hilitedCandidate
                     pageNum:(NSUInteger)pageNum
                   finalPage:(BOOL)finalPage
                  didCompose:(BOOL)didCompose __attribute__((objc_direct)) {
  // NSLog(@"showPanelWithPreedit:...:");
  SquirrelPanel* panel = NSApp.SquirrelAppDelegate.panel;
  if (NSEqualRects(panel.IbeamRect, NSZeroRect)) {
    NSRect IbeamRect = NSZeroRect;
    NSRange selectedRange = self.client.selectedRange;
    if (_inlinePreedit || _inlineCandidate || _inlinePlaceholder || selectedRange.length > 0)
      [self.client attributesForCharacterIndex:0
                           lineHeightRectangle:&IbeamRect];
    if (NSIsEmptyRect(IbeamRect)) {
      if (selectedRange.length == 0) {
        // activate inline session, in e.g. table cells, by fake inputs
        [self showPlaceholder:@" "];
        [self.client attributesForCharacterIndex:0
                             lineHeightRectangle:&IbeamRect];
        [self showPlaceholder:@""];
      } else {
        IbeamRect = [self.client firstRectForCharacterRange:NSMakeRange(selectedRange.location, 1)
                                                actualRange:NULL];
      }
    }
    BOOL sweepVertical = NSWidth(IbeamRect) > NSHeight(IbeamRect);
    if (isnormal(_inlineOffset))
      IbeamRect = NSOffsetRect(IbeamRect, sweepVertical ? _inlineOffset : 0.0, sweepVertical ? 0.0 : _inlineOffset);
    if (@available(macOS 14.0, *)) {
      // avoid overlapping with cursor effects view
      if ((_goodOldCapsLock && (_lastModifiers & NSEventModifierFlagCapsLock) != 0) ||
          (_showingInitialStatus && preedit.length == 0 && candidateIndices.length == 0)) {
        NSRect screenRect = NSScreen.mainScreen.visibleFrame;
        NSRect capslockAccessory = sweepVertical ? NSMakeRect(NSMinX(IbeamRect) - 30, NSMinY(IbeamRect), 27, NSHeight(IbeamRect))
                                                 : NSMakeRect(NSMinX(IbeamRect), NSMinY(IbeamRect) - 26, NSWidth(IbeamRect), 23);
        if (sweepVertical) {
          if (NSMinX(capslockAccessory) < nexttoward(NSMinX(screenRect), INFINITY))
            capslockAccessory.origin.x = NSMinX(screenRect);
          if (NSMaxX(capslockAccessory) > nexttoward(NSMaxX(screenRect), -INFINITY))
            capslockAccessory.origin.x = NSMaxX(screenRect) - NSWidth(capslockAccessory);
        } else {
          if (NSMinY(capslockAccessory) < nexttoward(NSMinY(screenRect), INFINITY))
            capslockAccessory.origin.y = NSMaxY(screenRect) + 3;
          if (NSMaxY(capslockAccessory) > nexttoward(NSMaxY(screenRect), -INFINITY))
            capslockAccessory.origin.y = NSMaxY(screenRect) - NSHeight(capslockAccessory);
        }
        IbeamRect = NSUnionRect(IbeamRect, capslockAccessory);
      }
    }
    panel.IbeamRect = IbeamRect;
  }
  _candidateIndices = candidateIndices;
  [panel showPreedit:preedit
              selRange:selRange
              caretPos:caretPos
      candidateIndices:candidateIndices
      hilitedCandidate:hilitedCandidate
               pageNum:pageNum
             finalPage:finalPage
            didCompose:didCompose];
  if (@available(macOS 14.0, *)) {
    if (_showingInitialStatus) {
      panel.IbeamRect = NSZeroRect;
      _showingInitialStatus = NO;
    }
  }
}

#pragma mark - Private methods

- (void)createSession __attribute__((objc_direct)) {
  NSString* app = self.client.bundleIdentifier;
  // NSLog(@"createSession: %@", app);
  _session = rime_get_api_stdbool()->create_session();
  SquirrelPanel* panel = NSApp.SquirrelAppDelegate.panel;
  _schemaId = panel.optionSwitcher.schemaId.copy;
  if (_session != 0) {
    SquirrelConfig* config = [SquirrelConfig.alloc initWithType:@".base"];
    _appOptions = [config appOptionsForApp:app];
    [config close];
    rime_get_api_stdbool()->set_option(_session, "_linear", panel.linear);
    rime_get_api_stdbool()->set_option(_session, "_vertical", panel.vertical);
    _inlinePreedit = (panel.inlinePreedit && ![_appOptions boolValueForOption:@"no_inline"]) ||
                     [_appOptions boolValueForOption:@"inline"];
    _inlineCandidate = panel.inlineCandidate && ![_appOptions boolValueForOption:@"no_inline"];
    rime_get_api_stdbool()->set_option(_session, "soft_cursor", !_inlinePreedit);
    _panellessCommitFix = [_appOptions boolValueForOption:@"panelless_commit_fix"];
    _inlinePlaceholder = [_appOptions boolValueForOption:@"inline_placeholder"];
    _inlineOffset = [_appOptions intValueForOption:@"inline_offset"];
    // restore ascii mode if client app has not changed
    if ([app isEqualToString:_currentApp] && _asciiMode >= 0 &&
        _asciiMode != rime_get_api_stdbool()->get_option(_session, "ascii_mode"))
      rime_get_api_stdbool()->set_option(_session, "ascii_mode", _asciiMode);
    _currentApp = app;
    _asciiMode = -1;
    [self rimeUpdate];
  }
}

- (void)destroySession __attribute__((objc_direct)) {
  // NSLog(@"destroySession:");
  if (_session != 0) {
    rime_get_api_stdbool()->destroy_session(_session);
    _session = 0;
  }
  [self clearChord];
}

- (BOOL)rimeConsumeCommittedText __attribute__((objc_direct)) {
  RIME_STRUCT(RimeCommit, commit);
  if (rime_get_api_stdbool()->get_commit(_session, &commit)) {
    NSString* commitText = @(commit.text);
    if (_panellessCommitFix) {
      [self showPlaceholder:commitText];
      [self commitString:commitText];
      [self showPlaceholder:sizeof(commit.text) == 1 ? @"" : nil];
    } else {
      [self commitString:commitText];
      [self showPlaceholder:@""];
    }
    rime_get_api_stdbool()->free_commit(&commit);
    return YES;
  }
  return NO;
}

static inline NSUInteger UnicharCount(const char* cString, int length) {
  return [NSString.alloc initWithBytes:cString
                                length:(NSUInteger)length
                              encoding:NSUTF8StringEncoding].length;
}

- (void)rimeUpdate __attribute__((objc_direct)) {
  // NSLog(@"rimeUpdate");
  BOOL didCommit = self.rimeConsumeCommittedText;
  BOOL didCompose = didCommit;

  SquirrelPanel* panel = NSApp.SquirrelAppDelegate.panel;
  RIME_STRUCT(RimeStatus_stdbool, status);
  if (rime_get_api_stdbool()->get_status(_session, &status)) {
    // enable schema specific ui style
    if (strcmp(_schemaId.UTF8String, status.schema_id) != 0) {
      _schemaId = @(status.schema_id);
      _showingSwitcherMenu = rime_get_api_stdbool()->get_option(_session, "dumb");
      if (!_showingSwitcherMenu) {
        [NSApp.SquirrelAppDelegate loadSchemaSpecificLabels:_schemaId];
        [NSApp.SquirrelAppDelegate loadSchemaSpecificSettings:_schemaId];
        // with linear candidate list, arrow keys may behave differently.
        if (panel.linear != rime_get_api_stdbool()->get_option(_session, "_linear"))
          rime_get_api_stdbool()->set_option(_session, "_linear", panel.linear);
        // with vertical text, arrow keys may behave differently.
        if (panel.vertical != rime_get_api_stdbool()->get_option(_session, "_vertical"))
          rime_get_api_stdbool()->set_option(_session, "_vertical", panel.vertical);
        // inline preedit
        _inlinePreedit = (panel.inlinePreedit && ![_appOptions boolValueForOption:@"no_inline"]) ||
                         [_appOptions boolValueForOption:@"inline"];
        _inlineCandidate = panel.inlineCandidate && ![_appOptions boolValueForOption:@"no_inline"];
        // if not inline, embed soft cursor in preedit string
        rime_get_api_stdbool()->set_option(_session, "soft_cursor", !_inlinePreedit);
      } else {
        [NSApp.SquirrelAppDelegate loadSchemaSpecificLabels:@""];
      }
      didCompose = YES;
    }
    rime_get_api_stdbool()->free_status(&status);
  }

  RIME_STRUCT(RimeContext_stdbool, ctx);
  if (rime_get_api_stdbool()->get_context(_session, &ctx)) {
    // update preedit text
    const char* preedit = ctx.composition.preedit;
    NSString* preeditText = @(preedit ? : "");

    // update raw input
    NSString* originalString = @(rime_get_api_stdbool()->get_input(_session) ? : "");
    didCompose |= ![originalString isEqualToString:_originalString];
    _originalString = originalString;

    // update composed string
    if (preedit == NULL || _showingSwitcherMenu) {
      _composedString = @"";
    } else if (!_inlinePreedit) { // remove soft cursor
      char composed[strlen(preedit) - 2];
      strlcpy(composed, preedit, (size_t)ctx.composition.cursor_pos + 1);
      strlcat(composed, preedit + ctx.composition.cursor_pos + 3, strlen(preedit) - 2);
      _composedString = @(composed);
    } else {
      _composedString = @(preedit);
    }

    NSUInteger start = UnicharCount(preedit, ctx.composition.sel_start);
    NSUInteger end = UnicharCount(preedit, ctx.composition.sel_end);
    NSUInteger caretPos = UnicharCount(preedit, ctx.composition.cursor_pos);
    NSUInteger length = UnicharCount(preedit, ctx.composition.length);
    NSUInteger numCandidates = (NSUInteger)ctx.menu.num_candidates;
    NSUInteger pageNum = (NSUInteger)ctx.menu.page_no;
    NSUInteger pageSize = (NSUInteger)ctx.menu.page_size;
    NSUInteger hilitedCandidate = numCandidates == 0 ? NSNotFound : (NSUInteger)ctx.menu.highlighted_candidate_index;
    BOOL finalPage = (BOOL)ctx.menu.is_last_page;

    // selected segment, with locations in terms of raw input
    NSUInteger suffixLength = [[preeditText substringFromIndex:end]
                               stringByReplacingOccurrencesOfString:@" " withString:@""].length;
    NSUInteger selLength = [[preeditText substringWithRange:NSMakeRange(start, end - start)]
                            stringByReplacingOccurrencesOfString:@" " withString:@""].length;
    if (!_inlinePreedit && caretPos < length && caretPos >= end) // subtract length of soft cursor
      suffixLength -= 1;
    NSRange selSegment = NSMakeRange(originalString.length - suffixLength - selLength, selLength);
    didCompose |= _selSegment.location != selSegment.location ||
      (_selSegment.length != selSegment.length && hilitedCandidate == 0 && pageNum == 0);
    _selSegment = selSegment;
    // update `expanded` and `sectionNum` variables in tabular layout;
    // already processed the action if _currentIndex == NSNotFound
    if (panel.tabular && !panel.hasStatusMessage) {
      if (numCandidates == 0 || didCompose) {
        panel.sectionNum = 0;
      } else if (_currentIndex != NSNotFound) {
        NSUInteger currentPageNum = _currentIndex / pageSize;
        if (!panel.locked && panel.expanded && panel.firstLine &&
            pageNum == 0 && hilitedCandidate == 0 && _currentIndex == 0)
          panel.expanded = NO;
        else if (!panel.locked && !panel.expanded && pageNum > currentPageNum)
          panel.expanded = YES;

        if (panel.expanded && pageNum > currentPageNum && panel.sectionNum < (panel.vertical ? 2 : 4))
          panel.sectionNum = fmin(panel.sectionNum + pageNum - currentPageNum,
                                  (finalPage ? 4UL : 3UL) - (panel.vertical ? 2UL : 0UL));
        else if (panel.expanded && pageNum < currentPageNum && panel.sectionNum > 0)
          panel.sectionNum = fmax(panel.sectionNum + pageNum - currentPageNum,
                                  pageNum == 0 ? 0UL : 1UL);
      }
      hilitedCandidate += pageSize * panel.sectionNum;
    }
    NSUInteger extraCandidates = panel.expanded ?
      (finalPage ? panel.sectionNum : (panel.vertical ? 2 : 4)) * pageSize : 0;
    _candidateIndices = NSMakeRange((pageNum - panel.sectionNum) * pageSize, numCandidates + extraCandidates);
    _currentIndex = hilitedCandidate + _candidateIndices.location;

    if (_showingSwitcherMenu) {
      if (_inlinePlaceholder)
        [self updateComposition];
    } else if (_inlineCandidate) {
      NSString* candidatePreviewText = @(ctx.commit_text_preview ? : "");
      if (_inlinePreedit) {
        if (end <= caretPos && caretPos < length)
          candidatePreviewText = [candidatePreviewText append:[preeditText substringFromIndex:caretPos]];
        if (!didCommit || candidatePreviewText.length > 0)
          [self showInlineString:candidatePreviewText
                    withSelRange:NSMakeRange(start, candidatePreviewText.length - (length - end) - start)
                        caretPos:caretPos < end ? caretPos : candidatePreviewText.length - (length - caretPos)];
      } else { // preedit includes the soft cursor
        if (end < caretPos && caretPos <= length)
          candidatePreviewText = [candidatePreviewText substringToIndex:
                                  candidatePreviewText.length - (caretPos - end)];
        else if (caretPos < end && end < length)
          candidatePreviewText = [candidatePreviewText substringToIndex:
                                  candidatePreviewText.length - (length - end)];
        if (!didCommit || candidatePreviewText.length > 0)
          [self showInlineString:candidatePreviewText
                    withSelRange:NSMakeRange(start, candidatePreviewText.length - start)
                        caretPos:caretPos < end ? caretPos : candidatePreviewText.length];
      }
    } else {
      if (_inlinePreedit) {
        if (_inlinePlaceholder && preeditText.length == 0 && numCandidates > 0)
          [self showPlaceholder:kFullWidthSpace];
        else if (!didCommit || preeditText.length > 0)
          [self showInlineString:preeditText
                    withSelRange:NSMakeRange(start, end - start)
                        caretPos:caretPos];
      } else {
        if (_inlinePlaceholder && preedit != NULL)
          [self showPlaceholder:kFullWidthSpace];
        else if (!didCommit || preedit != NULL)
          [self showInlineString:@"" withSelRange:NSMakeRange(0, 0) caretPos:0];
      }
    }

    // cache candidates
    if (didCompose || numCandidates == 0) {
      [_candidateTexts removeAllObjects];
      [_candidateComments removeAllObjects];
    }
    NSUInteger index = _candidateTexts.count;
    NSUInteger endIndex = pageSize * pageNum;
    // cache candidates
    if (index < endIndex) {
      RimeCandidateListIterator iterator;
      if (rime_get_api_stdbool()->candidate_list_from_index(_session, &iterator, (int)index)) {
        while (index < endIndex && rime_get_api_stdbool()->candidate_list_next(&iterator))
          [self updateCandidate:&iterator.candidate atIndex:index++];
        rime_get_api_stdbool()->candidate_list_end(&iterator);
      }
    }
    if (index < pageSize * pageNum + numCandidates) {
      for (NSUInteger i = 0; i < numCandidates; ++i)
        [self updateCandidate:&ctx.menu.candidates[i] atIndex:index++];
    }
    endIndex = NSMaxRange(_candidateIndices);
    if (index < endIndex) {
      RimeCandidateListIterator iterator;
      if (rime_get_api_stdbool()->candidate_list_from_index(_session, &iterator, (int)index)) {
        while (index < endIndex && rime_get_api_stdbool()->candidate_list_next(&iterator)) {
          [self updateCandidate:&iterator.candidate atIndex:index++];
        }
        rime_get_api_stdbool()->candidate_list_end(&iterator);
        _candidateIndices.length -= endIndex - index;
      }
    }
    // remove old candidates that were not overwritted, if any, subscripted from index
    [self updateCandidate:NULL atIndex:index];

    [self showPanelWithPreedit:_inlinePreedit && !_showingSwitcherMenu ? nil : preeditText
                      selRange:NSMakeRange(start, end - start)
                      caretPos:_showingSwitcherMenu ? NSNotFound : caretPos
              candidateIndices:_candidateIndices
              hilitedCandidate:hilitedCandidate
                       pageNum:pageNum
                     finalPage:finalPage
                    didCompose:didCompose];
    rime_get_api_stdbool()->free_context(&ctx);
  }
}

- (void)updateCandidate:(RimeCandidate*)candidate
                atIndex:(NSUInteger)index __attribute__((objc_direct)) {
  if (candidate == NULL || index > _candidateTexts.count) {
    if (index < _candidateTexts.count) {
      NSRange remove = NSMakeRange(index, _candidateTexts.count - index);
      [_candidateTexts removeObjectsInRange:remove];
      [_candidateComments removeObjectsInRange:remove];
    }
    return;
  }
  if (index == _candidateTexts.count ||
      strcmp(candidate->text, _candidateTexts[index].UTF8String) != 0)
    _candidateTexts[index] = @(candidate->text);
  if (index == _candidateComments.count ||
      strcmp(candidate->comment ? : "", _candidateComments[index].UTF8String) != 0)
    _candidateComments[index] = @(candidate->comment ? : "");
}

@end  // SquirrelInputController
