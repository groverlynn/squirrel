import AppKit
import Carbon
import InputMethodKit
import IOKit

let N_KEY_ROLL_OVER: Int = 50

enum SquirrelAction {
  case PROCESS, SELECT, HIGHLIGHT, DELETE
}

enum SquirrelIndex: Int {
  // 0, 1, 2 ... are ordinal digits, used as (int) indices
  // 0xFFXX are rime keycodes (as function keys), for paging etc.
  case kBackSpaceKey = 0xff08   // XK_BackSpace
  case kEscapeKey = 0xff1b      // XK_Escape
  case kCodeInputArea = 0xff37  // XK_Codeinput
  case kHomeKey = 0xff50        // XK_Home
  case kLeftKey = 0xff51        // XK_Left
  case kUpKey = 0xff52          // XK_Up
  case kRightKey = 0xff53       // XK_Right
  case kDownKey = 0xff54        // XK_Down
  case kPageUpKey = 0xff55      // XK_Page_Up
  case kPageDownKey = 0xff56    // XK_Page_Down
  case kEndKey = 0xff57         // XK_End
  case kExpandButton = 0xff04
  case kCompressButton = 0xff05
  case kLockButton = 0xff06
  case kVoidSymbol = 0xffffff   // XK_VoidSymbol
}

fileprivate func set_CapsLock_LED_state(target_state: CBool) {
  let ioService: io_service_t = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(kIOHIDSystemClass))
  var ioConnect: io_connect_t = 0
  IOServiceOpen(ioService, mach_task_self_, CUnsignedInt(kIOHIDParamConnectType), &ioConnect)
  var current_state: CBool = false
  IOHIDGetModifierLockState(ioConnect, CInt(kIOHIDCapsLockState), &current_state)
  if (current_state != target_state) {
    IOHIDSetModifierLockState(ioConnect, CInt(kIOHIDCapsLockState), target_state)
  }
  IOServiceClose(ioConnect)
}

fileprivate func getOptionLabel(session: RimeSessionId,
                                option: UnsafePointer<CChar>,
                                state: Bool) -> String? {
  let short_label: RimeStringSlice = rime_get_api().pointee.get_state_label_abbreviated(session, option, state, True)
  if ((short_label.str != nil) && short_label.length >= strlen(short_label.str)) {
    return String(cString: short_label.str)
  } else {
    let long_label: RimeStringSlice =
    rime_get_api().pointee.get_state_label_abbreviated(session, option, state, False)
    let label: String? = long_label.str != nil ? String(cString: long_label.str!) : nil
    return label != nil ? String(label![label!.rangeOfComposedCharacterSequence(at: label!.startIndex)]) : nil
  }
}

fileprivate func UTF8LengthToUTF16Length(str: String, length: Int) -> Int {
  return str.utf8.index(str.utf8.startIndex, offsetBy: length).utf16Offset(in: str)
}

class SquirrelInputController: IMKInputController {
  // class variables
  static var currentController: SquirrelInputController?
  private static var currentApp: String = ""
  private static var asciiMode: Bool = -1
  // private
  private var _preeditString: NSMutableAttributedString?
  private var _originalString: String?
  private var _composedString: String?
  private var _schemaId: String?
  private var _selRange: NSRange = NSMakeRange(0, 0)
  private var _candidateIndices: Range<Int> = 0..<0
  private var _inlineSelRange: NSRange = NSMakeRange(0, 0)
  private var _inlineCaretPos: Int = 0
  private var _converted: Int = 0
  private var _currentIndex: Int = 0
  private var _lastModifiers: NSEvent.ModifierFlags = []
  private var _lastEventCount: CUnsignedInt = 0
  private var _session: RimeSessionId = 0
  private var _inlinePreedit: Boolean = false
  private var _inlineCandidate: Boolean = false
  private var _goodOldCapsLock: Boolean = false
  private var _showingSwitcherMenu: Boolean = false
  // app-specific bug fix
  private var _inlinePlaceholder: Boolean = false
  private var _panellessCommitFix: Boolean = false
  private var _inlineOffset: Int = 0
  // for chord-typing
  private var _chordTimer: Timer?
  private var _chordDuration: TimeInterval = 0
  private var _chordKeyCodes: [CInt] = []
  private var _chordModifiers: [CInt] = []
  private var _chordKeyCount: Int = 0
  // public
  @objc dynamic var viewEffectiveAppearance: NSAppearance {
    get {
      let sel: Selector = NSSelectorFromString("viewEffectiveAppearance")
      let sourceAppearance: NSAppearance? = self.client()?.perform(sel) as? NSAppearance
      return sourceAppearance ?? NSApp.effectiveAppearance
    }
  }
  private var _candidateTexts: [String] = []
  var candidateTexts: [String] { get { return _candidateTexts } }
  private var _candidateComments: [String] = []
  var candidateComments: [String] { get { return _candidateComments } }

  class func setCurrentController(_ controller: SquirrelInputController) {
    currentController = controller
    NSApp.squirrelAppDelegate.panel?.IbeamRect = NSZeroRect
  }

  override class func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
    if (key == "viewEffectiveAppearance") {
      return Set(["client.viewEffectiveApperance"])
    } else {
      return super.keyPathsForValuesAffectingValue(forKey: key)
    }
  }

  override func activateServer(_ sender: Any!) {
    //NSLog(@"activateServer:")
    SquirrelInputController.setCurrentController(self)
    addObserver(NSApp.squirrelAppDelegate.panel!,
                forKeyPath: "viewEffectiveAppearance",
                options: [.new, .initial],
                context: nil)

    if let keyboardLayout: String = NSApp.squirrelAppDelegate.config?.getStringForOption("keyboard_layout") {
      if (keyboardLayout.caseInsensitiveCompare("last") == .orderedSame || keyboardLayout.isEmpty) {
        // do nothing
      } else if (keyboardLayout.caseInsensitiveCompare("default") == .orderedSame) {
        client().overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
      } else if (!keyboardLayout.hasPrefix("com.apple.keylayout.")) {
        client().overrideKeyboard(withKeyboardNamed:"com.apple.keylayout." + keyboardLayout)
      }
    }

    let defaultConfig: SquirrelConfig = SquirrelConfig()
    if (defaultConfig.open(withConfigId: "default") &&
        defaultConfig.hasSection("ascii_composer")) {
      _goodOldCapsLock = defaultConfig.getBoolForOption("ascii_composer/good_old_caps_lock")
    }
    defaultConfig.close()
    super.activateServer(sender)
  }

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
  //NSLog(@"initWithServer:delegate:client:")
    super.init(server: server, delegate: delegate, client: inputClient)
    createSession()
  }

  override func deactivateServer(_ sender: Any!) {
    //NSLog(@"deactivateServer:")
    commitComposition(sender)
    removeObserver(NSApp.squirrelAppDelegate.panel!,
                   forKeyPath: "viewEffectiveAppearance")
    SquirrelInputController.asciiMode = rime_get_api().pointee.get_option(_session, "ascii_mode")
    super.deactivateServer(sender)
  }

  /*!
   @method
   @abstract   Receive incoming event
   @discussion This method receives key events from the client application.
   */
  override func handle(_ event: NSEvent!, client sender: Any!) -> Boolean {
  // Return YES to indicate the the key input was received and dealt with.
  // Key processing will not continue in that case.  In other words the
  // system will not deliver a key down event to the application.
  // Returning NO means the original key down will be passed on to the client.
    return autoreleasepool {
      if (_session != 0 || !rime_get_api().pointee.find_session(_session).Bool) {
        createSession()
        if (_session != 0) {
          return false
        }
      }
      var handled: Boolean = false
      let modifiers: NSEvent.ModifierFlags = event.modifierFlags
      var rime_modifiers: RimeModifier = get_rime_modifiers(modifiers)
      let keyCode: Int = Int(event.cgEvent?.getIntegerValueField(.keyboardEventKeycode) ?? 0)

      switch (event.type) {
      case .flagsChanged:
        if (_lastModifiers == modifiers) {
          return true
        }
        //NSLog(@"FLAGSCHANGED client: %@, modifiers: 0x%lx", sender, modifiers)
        let rime_keycode: CInt = get_rime_keycode(keycode: keyCode, keychar: 0, shift: false, caps: false)
        let eventCount: CUnsignedInt = CGEventSource.counterForEventType(.combinedSessionState, eventType: .flagsChanged) +
                                       CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown) +
                                       CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown) +
                                       CGEventSource.counterForEventType(.combinedSessionState, eventType: .rightMouseDown) +
                                       CGEventSource.counterForEventType(.combinedSessionState, eventType: .otherMouseDown)
        _lastModifiers = modifiers
        switch (keyCode) {
        case kVK_CapsLock:
          if (!_goodOldCapsLock) {
            set_CapsLock_LED_state(target_state: false)
            if (rime_get_api().pointee.get_option(_session, "ascii_mode").Bool) {
              rime_modifiers.insert(.Lock)
            } else {
              rime_modifiers.remove(.Lock)
            }
          } else {
            rime_modifiers.formSymmetricDifference(.Lock)
          }
          handled = processKey(rime_keycode, modifiers: rime_modifiers.rawValue)
          break
        case kVK_Shift, kVK_RightShift:
          if (!modifiers.contains(.shift)) { rime_modifiers.insert(.Release) }
          if (eventCount - _lastEventCount != 1) { rime_modifiers.insert(.Ignored) }
          handled = processKey(rime_keycode, modifiers: rime_modifiers.rawValue)
          break
        case kVK_Control, kVK_RightControl:
          if (!modifiers.contains(.control)) { rime_modifiers.insert(.Release) }
          if (eventCount - _lastEventCount != 1) { rime_modifiers.insert(.Ignored) }
          handled = processKey(rime_keycode, modifiers: rime_modifiers.rawValue)
          break
        case kVK_Option, kVK_RightOption:
          if (!modifiers.contains(.option)) { rime_modifiers.insert(.Release) }
          if (eventCount - _lastEventCount != 1) { rime_modifiers.insert(.Ignored) }
          handled = processKey(rime_keycode, modifiers: rime_modifiers.rawValue)
          break
        case kVK_Function:
          if (!modifiers.contains(.function)) { rime_modifiers.insert(.Release) }
          if (eventCount - _lastEventCount != 1) { rime_modifiers.insert(.Ignored) }
          handled = processKey(rime_keycode, modifiers: rime_modifiers.rawValue)
          break
        case kVK_Command, kVK_RightCommand:
          if (!modifiers.contains(.command)) { rime_modifiers.insert(.Release) }
          if (eventCount - _lastEventCount != 1) { rime_modifiers.insert(.Ignored) }
          handled = processKey(rime_keycode, modifiers: rime_modifiers.rawValue)
          break
        default:
          break
        }
        if (NSApp.squirrelAppDelegate.panel?.statusMessage != nil || handled) {
          rimeUpdate()
          handled = true
        }
        _lastEventCount = eventCount
        break
      case .keyDown:
        let keyChars: String = modifiers.contains(.shift) && !modifiers.contains(.control) && !modifiers.contains(.option) ? event.characters! : event.charactersIgnoringModifiers!
        //NSLog(@"KEYDOWN client: %@, modifiers: 0x%lx, keyCode: %d, keyChars: [%@]",
        //      sender, modifiers, keyCode, keyChars)

        // translate osx keyevents to rime keyevents
        let rime_keycode: CInt = get_rime_keycode(keycode: keyCode, keychar: Int(keyChars.utf16.first!),
                                                  shift: modifiers.contains(.shift), caps: modifiers.contains(.capsLock))
        if (rime_keycode != XK_VoidSymbol) {
          // revert non-modifier function keys' FunctionKeyMask (FwdDel, Navigations, F1..F19)
          if ((keyCode <= 0xff && keyCode >= 0x60) || keyCode == 0x50 ||
              keyCode == 0x4f || keyCode == 0x47 || keyCode == 0x40) {
            rime_modifiers.formSymmetricDifference(.Hyper)
          }
          handled = processKey(rime_keycode, modifiers: rime_modifiers.rawValue)
          if (handled) {
            rimeUpdate()
          } else if (_panellessCommitFix && client().markedRange().length > 0) {
            if (rime_keycode == XK_Delete || (rime_keycode >= XK_Home && rime_keycode <= XK_KP_Delete) ||
                (rime_keycode >= XK_BackSpace && rime_keycode <= XK_Escape)) {
              showPlaceholder("")
            } else if (!modifiers.contains(.control) && !modifiers.contains(.command) && event.characters?.count ?? 0 > 0) {
              showPlaceholder(nil)
              client().insertText(event.characters, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
              return true
            }
          }
        }
        break
      default:
        break
      }
      return handled
    }
  }

  override func mouseDown(onCharacterIndex index: Int,
                          coordinate point: NSPoint,
                          withModifier flags: Int,
                          continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!,
                          client sender: Any!) -> Boolean {
    keepTracking.pointee = false
    if ((!_inlinePreedit && !_inlineCandidate) ||
        _composedString?.count == 0 || _inlineCaretPos == index ||
        (flags & Int(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)) != 0) {
      return false
    }
    let markedRange: NSRange = client().markedRange()
    let head: NSPoint = client().attributes(forCharacterIndex: 0, lineHeightRectangle: nil)["IMKBaseline"] as! NSPoint
    let tail: NSPoint = client().attributes(forCharacterIndex: markedRange.length - 1, lineHeightRectangle: nil)["IMKBaseline"] as! NSPoint
    if (point.x > tail.x || index >= markedRange.length) {
      if (_inlineCandidate && !_inlinePreedit) {
        return false
      }
      perform(action: .PROCESS, onIndex: .kEndKey)
    } else if (point.x < head.x || index <= 0) {
      perform(action: .PROCESS, onIndex: .kHomeKey)
    } else {
      moveCursor(_inlineCaretPos, to: index, inlinePreedit: _inlinePreedit, inlineCandidate: _inlineCandidate)
    }
    return true
  }

  private func processKey(_ rime_keycode: CInt, modifiers rime_modifiers: CInt) -> Boolean {
    let panel: SquirrelPanel! = NSApp.squirrelAppDelegate.panel
    // with linear candidate list, arrow keys may behave differently.
    let is_linear: Bool = panel.linear.Bool
    if (is_linear != rime_get_api().pointee.get_option(_session, "_linear")) {
      rime_get_api().pointee.set_option(_session, "_linear", is_linear)
    }
    // with vertical text, arrow keys may behave differently.
    let is_vertical: Bool = panel.vertical.Bool
    if (is_vertical != rime_get_api().pointee.get_option(_session, "_vertical")) {
      rime_get_api().pointee.set_option(_session, "_vertical", is_vertical)
    }

    if (panel.tabular && rime_modifiers == 0 && panel.isVisible &&
        (is_vertical.Bool ? rime_keycode == XK_Left || rime_keycode == XK_KP_Left ||
                            rime_keycode == XK_Right || rime_keycode == XK_KP_Right
                          : rime_keycode == XK_Up || rime_keycode == XK_KP_Up ||
                            rime_keycode == XK_Down || rime_keycode == XK_KP_Down)) {
      var keycode: CInt = rime_keycode
      if (rime_keycode >= XK_KP_Left && rime_keycode <= XK_KP_Down) {
        keycode = rime_keycode - XK_KP_Left + XK_Left
      }
      let newIndex: Int = panel.candidateIndexOnDirection(arrowKey: SquirrelIndex(rawValue: Int(keycode))!)
      if (newIndex != NSNotFound) {
        if (!panel.locked && !panel.expanded && keycode == (is_vertical.Bool ? XK_Left : XK_Down)) {
          panel.expanded = true
        }
        _ = rime_get_api().pointee.highlight_candidate(_session, newIndex)
        return true
      } else if (!panel.locked && panel.expanded && panel.sectionNum == 0 &&
                 rime_keycode == (is_vertical.Bool ? XK_Right : XK_Up)) {
        panel.expanded = false
        return true
      }
    }

    let handled: Boolean = rime_get_api().pointee.process_key(_session, rime_keycode, rime_modifiers).Bool
    //NSLog(@"rime_keycode: 0x%x, rime_modifiers: 0x%x, handled = %d", rime_keycode, rime_modifiers, handled)

    // TODO add special key event postprocessing here

    if (!handled) {
      let isVimBackInCommandMode: Boolean = rime_keycode == XK_Escape ||
      (((rime_modifiers & CInt(kControlMask.rawValue)) != 0) && (rime_keycode == XK_c ||
          rime_keycode == XK_C || rime_keycode == XK_bracketleft))
      if (isVimBackInCommandMode && rime_get_api().pointee.get_option(_session, "vim_mode").Bool &&
          !rime_get_api().pointee.get_option(_session, "ascii_mode").Bool) {
        cancelComposition()
        rime_get_api().pointee.set_option(_session, "ascii_mode", True)
        // NSLog(@"turned Chinese mode off in vim-like editor's command mode")
        return true
      }
    }

    // Simulate key-ups for every interesting key-down for chord-typing.
    if (handled) {
      let is_chording_key: Boolean = (rime_keycode >= XK_space && rime_keycode <= XK_asciitilde) ||
                                      rime_keycode == XK_Control_L || rime_keycode == XK_Control_R ||
                                      rime_keycode == XK_Alt_L || rime_keycode == XK_Alt_R ||
                                      rime_keycode == XK_Shift_L || rime_keycode == XK_Shift_R
      if (is_chording_key && rime_get_api().pointee.get_option(_session, "_chord_typing").Bool) {
        updateChord(rime_keycode, modifiers: rime_modifiers)
      } else if ((rime_modifiers & CInt(kReleaseMask.rawValue)) == 0) {
        // non-chording key pressed
        clearChord()
      }
    }

    return handled
  }

  func moveCursor(_ cursorPosition: Int, to targetPosition: Int,
                  inlinePreedit: Boolean, inlineCandidate: Boolean) {
    let vertical: Boolean = NSApp.squirrelAppDelegate.panel!.vertical
    autoreleasepool {
      let composition: String = !inlinePreedit && !inlineCandidate ? _composedString! : _preeditString!.string
      var ctx: RimeContext = RimeContext()
      if (cursorPosition > targetPosition) {
        let targetPrefix: String = String(composition[composition.startIndex..<composition.index(composition.startIndex, offsetBy: targetPosition)]).replacingOccurrences(of: " ", with: "")
        var prefix: String = String(composition[composition.startIndex..<composition.index(composition.startIndex, offsetBy: cursorPosition)]).replacingOccurrences(of: " ", with: "")
        while (targetPrefix.count < prefix.count) {
          _ = rime_get_api().pointee.process_key(_session, vertical ? XK_Up : XK_Left, CInt(kControlMask.rawValue))
          _ = rime_get_api().pointee.get_context(_session, &ctx)
          if (inlineCandidate) {
            let length: size_t = ctx.composition.cursor_pos < ctx.composition.sel_end ?
            size_t(ctx.composition.cursor_pos) : strlen(ctx.commit_text_preview) -
            (inlinePreedit ? 0 : size_t(ctx.composition.cursor_pos - ctx.composition.sel_end))
            let preview: String = String.init(utf8String: ctx.commit_text_preview)!
            prefix = String(preview[preview.startIndex..<preview.index(preview.startIndex, offsetBy: length)]).replacingOccurrences(of: " ", with: "")
          } else {
            let preedit: String = String.init(utf8String: ctx.composition.preedit)!
            prefix = String(preedit[preedit.startIndex..<preedit.index(preedit.startIndex, offsetBy: Int(ctx.composition.cursor_pos))]).replacingOccurrences(of: " ", with: "")
          }
          _ = rime_get_api().pointee.free_context(&ctx)
        }
      } else if (cursorPosition < targetPosition) {
        let targetSuffix: String = String(composition[composition.index(composition.startIndex, offsetBy: targetPosition)..<composition.endIndex]).replacingOccurrences(of: " ", with: "")
        var suffix: String = String(composition[composition.index(composition.startIndex, offsetBy: cursorPosition)..<composition.endIndex]).replacingOccurrences(of: " ", with: "")
        while (targetSuffix.count < suffix.count) {
          _ = rime_get_api().pointee.process_key(_session, vertical ? XK_Down : XK_Right, CInt(kControlMask.rawValue))
          _ = rime_get_api().pointee.get_context(_session, &ctx)
          let preedit: String = String.init(utf8String: ctx.composition.preedit)!
          suffix = String(preedit[preedit.index(preedit.startIndex, offsetBy: Int(ctx.composition.cursor_pos + (!inlinePreedit && !inlineCandidate ? 3 : 0)))..<preedit.endIndex]).replacingOccurrences(of: " ", with: "")
          _ = rime_get_api().pointee.free_context(&ctx)
        }
      }
      rimeUpdate()
    }
  }

  func perform(action: SquirrelAction, onIndex index: SquirrelIndex) {
    //NSLog(@"perform action: %lu on index: %lu", action, index)
    var handled: Boolean = false
    switch (action) {
    case .PROCESS:
      if (index.rawValue >= 0xff08 && index.rawValue <= 0xffff) {
        handled = rime_get_api().pointee.process_key(_session, CInt(index.rawValue), 0).Bool
      } else if (index.rawValue >= CInt(SquirrelIndex.kExpandButton.rawValue) && index.rawValue <= CInt(SquirrelIndex.kLockButton.rawValue)) {
        handled = true
        _currentIndex = NSNotFound
      }
      break
    case .SELECT:
      handled = rime_get_api().pointee.select_candidate(_session, index.rawValue).Bool
      break
    case .HIGHLIGHT:
      handled = rime_get_api().pointee.highlight_candidate(_session, index.rawValue).Bool
      _currentIndex = NSNotFound
      break
    case .DELETE:
      handled = rime_get_api().pointee.delete_candidate(_session, index.rawValue).Bool
      break
    }
    if (handled) {
      rimeUpdate()
    }
  }

  @objc private func onChordTimer(_ timer: Timer) {
    // chord release triggered by timer
    var processed_keys: CInt = 0
    if (_chordKeyCount != 0 && _session != 0) {
      // simulate key-ups
      for i in 0..<_chordKeyCount {
        if (rime_get_api().pointee.process_key(_session, _chordKeyCodes[i],
                                               (_chordModifiers[i] | CInt(kReleaseMask.rawValue))).Bool) {
          processed_keys += 1
        }
      }
    }
    clearChord()
    if (processed_keys > 0) {
      rimeUpdate()
    }
  }

  private func updateChord(_ keycode: CInt, modifiers: CInt) {
  //NSLog(@"update chord: {%s} << %x", _chord, keycode)
    for i in 0..<_chordKeyCount {
      if (_chordKeyCodes[i] == keycode) {
        return
      }
    }
    if (_chordKeyCount >= N_KEY_ROLL_OVER) {
      // you are cheating. only one human typist (fingers <= 10) is supported.
      return
    }
    _chordKeyCodes[_chordKeyCount] = keycode
    _chordModifiers[_chordKeyCount] = modifiers
    _chordKeyCount += 1
  // reset timer
    if (_chordTimer?.isValid ?? false) {
      _chordTimer!.invalidate()
    }

    let duration: Double! = NSApp.squirrelAppDelegate.config?.getDoubleForOption("chord_duration")
    _chordDuration = duration > 0 ? duration : 0.1
    _chordTimer = Timer.scheduledTimer(timeInterval: _chordDuration, target: self,
                                       selector: #selector(onChordTimer(_:)), userInfo: nil, repeats: false)
  }

  private func clearChord() {
    _chordKeyCount = 0
    if (_chordTimer?.isValid ?? false) {
      _chordTimer!.invalidate()
    }
  }

  override func recognizedEvents(_ sender: Any!) -> Int {
    //NSLog(@"recognizedEvents:")
    return Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged, .leftMouseDown]).rawValue)
  }

  private func showInitialStatus() {
    var status: RimeStatus = RimeStatus()
    if (_session != 0 && rime_get_api().pointee.get_status(_session, &status).Bool) {
      _schemaId = String(cString: status.schema_id)
      let schemaName: String = status.schema_name != nil ? String(cString: status.schema_name) : String(cString: status.schema_id)
      var options: [String] = []
      let asciiMode: String? = getOptionLabel(session: _session, option: "ascii_mode", state: status.is_ascii_mode)
      if (asciiMode != nil) {
        options.append(asciiMode!)
      }
      let fullShape: String? = getOptionLabel(session: _session, option: "full_shape", state: status.is_full_shape)
      if (fullShape != nil) {
        options.append(fullShape!)
      }
      let asciiPunct: String? = getOptionLabel(session: _session, option: "ascii_punct", state: status.is_ascii_punct)
      if (asciiPunct != nil) {
        options.append(asciiPunct!)
      }
      _ = rime_get_api().pointee.free_status(&status)
      let foldedOptions: String = options.count == 0 ? schemaName : String.init(format: "%@｜%@", schemaName, options.joined(separator: " "))

      NSApp.squirrelAppDelegate.panel?.updateStatus(long: foldedOptions, short: schemaName)
      if #available(macOS 14.0, *) {
        _lastModifiers.insert(.help)
      }
      showPanel(withPreedit: nil,
                selRange: NSMakeRange(0, 0),
                caretPos: NSNotFound,
                candidateIndices: 0..<0,
                highlightedIndex: NSNotFound,
                pageNum: NSNotFound,
                finalPage: false,
                didCompose: false)
    }
  }



  /*!
   @method
   @abstract   Called when a user action was taken that ends an input session.
   Typically triggered by the user selecting a new input method
   or keyboard layout.
   @discussion When this method is called your controller should send the
   current input buffer to the client via a call to
   insertText:replacementRange:.  Additionally, this is the time
   to clean up if that is necessary.
   */

  override func commitComposition(_ sender: Any!) {
    //NSLog(@"commitComposition:")
    commitString(composedString(sender))
    if (_session != 0) {
      rime_get_api().pointee.clear_composition(_session)
    }
    hidePalettes()
  }

  private func clearBuffer() {
    NSApp.squirrelAppDelegate.panel?.IbeamRect = NSZeroRect
    _preeditString = nil
    _originalString = nil
    _composedString = nil
  }

  // a piece of comment from SunPinyin's macos wrapper says:
  // > though we specified the showPrefPanel: in SunPinyinApplicationDelegate as the
  // > action receiver, the IMKInputController will actually receive the event.
  // so here we deliver messages to our responsible SquirrelApplicationDelegate
  @objc private func showSwitcher(_ sender: Any?) {
    NSApp.squirrelAppDelegate.showSwitcher(_session)
    rimeUpdate()
  }

  @objc private func deploy(_ sender: Any?) {
    NSApp.squirrelAppDelegate.deploy(sender)
  }

  @objc private func syncUserData(_ sender: Any?) {
    NSApp.squirrelAppDelegate.syncUserData(sender)
  }

  @objc private func configure(_ sender: Any?) {
    NSApp.squirrelAppDelegate.configure(sender)
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    NSApp.squirrelAppDelegate.updater?.perform(#selector(checkForUpdates(_:)), with: sender)
  }

  @objc private func openWiki(_ sender: Any?) {
    NSApp.squirrelAppDelegate.openWiki(sender)
  }

  @objc private func openLogFolder(_ sender: Any?) {
    NSApp.squirrelAppDelegate.openLogFolder(sender)
  }

  @objc override func menu() -> NSMenu {
    return NSApp.squirrelAppDelegate.menu!
  }

  override func originalString(_ sender: Any!) -> NSAttributedString! {
    return _originalString != nil ? NSAttributedString(string: _originalString!) : nil
  }

  override func composedString(_ sender: Any!) -> Any! {
    return _composedString?.replacingOccurrences(of: " ", with: "")
  }

  override func candidates(_ sender: Any!) -> [Any]! {
    return Array(_candidateTexts[_candidateIndices])
  }

  override func hidePalettes() {
    NSApp.squirrelAppDelegate.panel?.hide()
    super.hidePalettes()
  }

  deinit {
    //NSLog(@"dealloc")
    destroySession()
    clearBuffer()
  }

  override func selectionRange() -> NSRange {
    return NSMakeRange(_inlineCaretPos, 0)
  }

  override func replacementRange() -> NSRange {
    return NSMakeRange(NSNotFound, NSNotFound)
  }

  private func commitString(_ string: Any?) {
    //NSLog(@"commitString:")
    if (string != nil) {
      client().insertText(string, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }
    clearBuffer()
  }

  override func cancelComposition() {
    commitString(originalString(client))
    hidePalettes()
    if (_session != 0) {
      rime_get_api().pointee.clear_composition(_session)
    }
  }

  override func updateComposition() {
    client().setMarkedText(_preeditString, selectionRange: NSMakeRange(_inlineCaretPos, 0),
                           replacementRange: NSMakeRange(NSNotFound, NSNotFound))
  }

  private func showPlaceholder(_ placeholder: String?) {
    let attrs = mark(forStyle: kTSMHiliteSelectedRawText,
                     at: NSMakeRange(0, placeholder != nil ? placeholder!.count : 1)) as! [NSAttributedString.Key : Any]
    _preeditString = NSMutableAttributedString(string: placeholder ?? "█", attributes: attrs)
    _inlineCaretPos = 0
    updateComposition()
  }

  private func showPreeditString(_ preedit: String,
                                 selRange: NSRange,
                                 caretPos: Int) {
  //NSLog(@"showPreeditString: '%@'", preedit)
    if (preedit == (_preeditString?.string ?? "") as String &&
      NSEqualRanges(selRange, _inlineSelRange) && caretPos == _inlineCaretPos) {
      return
    }
    _inlineSelRange = selRange
    _inlineCaretPos = caretPos
  //NSLog(@"selRange.location = %ld, selRange.length = %ld, caretPos = %ld",
  //      range.location, range.length, pos)
    let attrs = mark(forStyle: kTSMHiliteRawText, at: NSMakeRange(0, preedit.count)) as! [NSAttributedString.Key : Any]
    _preeditString = NSMutableAttributedString(string: preedit, attributes: attrs)
    if (selRange.location > 0) {
      _preeditString!.addAttributes(mark(forStyle: kTSMHiliteConvertedText,
                                         at: NSMakeRange(0, selRange.location)) as! [NSAttributedString.Key : Any],
                                    range: NSMakeRange(0, selRange.location))
    }
    if (selRange.location < caretPos) {
      _preeditString!.addAttributes(mark(forStyle: kTSMHiliteSelectedRawText,
                                         at: selRange) as! [NSAttributedString.Key : Any],
                                    range: selRange)
    }
    updateComposition()
  }

  private func getIbeamRect() -> NSRect {
    var IbeamRect: NSRect = NSZeroRect
    client().attributes(forCharacterIndex: 0, lineHeightRectangle: &IbeamRect)
    if (NSEqualRects(IbeamRect, NSZeroRect) && _preeditString?.length == 0) {
      if (client().selectedRange().length == 0) {
        // activate inline session, in e.g. table cells, by fake inputs
        client().setMarkedText(" ", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        client().attributes(forCharacterIndex: 0, lineHeightRectangle: &IbeamRect)
        client().setMarkedText("", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
      } else {
        client().attributes(forCharacterIndex: client().selectedRange().location, lineHeightRectangle: &IbeamRect)
      }
    }
    if (NSIsEmptyRect(IbeamRect)) {
      return IbeamRect
    }
    if (NSWidth(IbeamRect) > NSHeight(IbeamRect)) {
      IbeamRect.origin.x += CGFloat(_inlineOffset)
    } else {
      IbeamRect.origin.y += CGFloat(_inlineOffset)
    }
    if #available(macOS 14.0, *) {  // avoid overlapping with cursor effects view
      if ((_goodOldCapsLock && _lastModifiers.contains(.capsLock)) ||
          _lastModifiers.contains(.help)) {
        _lastModifiers.remove(.help)
        var screenRect: NSRect = NSScreen.main?.frame ?? NSZeroRect
        if (NSIntersectsRect(IbeamRect, screenRect)) {
          screenRect = NSScreen.main?.visibleFrame ?? NSZeroRect
          if (NSWidth(IbeamRect) > NSHeight(IbeamRect)) {
            var capslockAccessory: NSRect = NSMakeRect(NSMinX(IbeamRect) - 30, NSMinY(IbeamRect),
                                                       27, NSHeight(IbeamRect))
            if (NSMinX(capslockAccessory) < NSMinX(screenRect)) {
              capslockAccessory.origin.x = NSMinX(screenRect)
            }
            if (NSMaxX(capslockAccessory) > NSMaxX(screenRect)) {
              capslockAccessory.origin.x = NSMaxX(screenRect) - NSWidth(capslockAccessory)
            }
            IbeamRect = NSUnionRect(IbeamRect, capslockAccessory)
          } else {
            var capslockAccessory: NSRect = NSMakeRect(NSMinX(IbeamRect), NSMinY(IbeamRect) - 26,
                                                       NSWidth(IbeamRect), 23)
            if (NSMinY(capslockAccessory) < NSMinY(screenRect)) {
              capslockAccessory.origin.y = NSMaxY(screenRect) + 3
            }
            if (NSMaxY(capslockAccessory) > NSMaxY(screenRect)) {
              capslockAccessory.origin.y = NSMaxY(screenRect) - NSHeight(capslockAccessory)
            }
            IbeamRect = NSUnionRect(IbeamRect, capslockAccessory)
          }
        }
      }
    }
    return IbeamRect
  }

  private func showPanel(withPreedit preedit: String?,
                         selRange: NSRange,
                         caretPos: Int,
                         candidateIndices: Range<Int>,
                         highlightedIndex: Int,
                         pageNum: Int,
                         finalPage: Boolean,
                         didCompose: Boolean) {
  //NSLog(@"showPanelWithPreedit:...:")
    let panel: SquirrelPanel! = NSApp.squirrelAppDelegate.panel
    panel.IbeamRect = getIbeamRect()
    if (NSIsEmptyRect(panel.IbeamRect) && panel.statusMessage?.count ?? 0 > 0) {
      panel.updateStatus(long:nil, short:nil)
    } else {
      panel.showPreedit(preedit,
                        selRange: selRange,
                        caretPos: caretPos,
                        candidateIndices: candidateIndices,
                        highlightedIndex: highlightedIndex,
                        pageNum: pageNum,
                        finalPage: finalPage,
                        didCompose: didCompose)
    }
  }

  // MARK - Private functions

  private func createSession() {
    let app: String = client().bundleIdentifier()
    //NSLog(@"createSession: %@", app)
    _session = rime_get_api().pointee.create_session()
    _schemaId = nil
    if (_session != 0) {
      let appOptions: SquirrelAppOptions = NSApp.squirrelAppDelegate.config!.getAppOptions(app)
      for (key, value) in appOptions {
        if (value is Boolean.Type) {
          let boolValue: Bool = (value as! Boolean).Bool
          //NSLog(@"set app option: %@ = %d", key, value)
          rime_get_api().pointee.set_option(_session, key.cString(using: String.Encoding.utf8), boolValue)
        }
      }
      _panellessCommitFix = appOptions["panelless_commit_fix"] as? Boolean ?? false
      _inlinePlaceholder = appOptions["inline_placeholder"] as? Boolean ?? false
      _inlineOffset = appOptions["inline_offset"] as? Int ?? 0
      if (app == SquirrelInputController.currentApp && SquirrelInputController.asciiMode >= 0) {
        rime_get_api().pointee.set_option(_session, "ascii_mode", SquirrelInputController.asciiMode)
      }
      SquirrelInputController.currentApp = app
      SquirrelInputController.asciiMode = -1
      _lastModifiers = []
      _lastEventCount = 0
      NSApp.squirrelAppDelegate.panel?.IbeamRect = NSZeroRect
      rimeUpdate()
    }
  }

  private func destroySession() {
    //NSLog(@"destroySession:")
    if (_session != 0) {
      _ = rime_get_api().pointee.destroy_session(_session)
      _session = 0
    }
    clearChord()
  }

  private func rimeConsumeCommittedText() -> Boolean {
    var commit: RimeCommit = RimeCommit()
    if (rime_get_api().pointee.get_commit(_session, &commit).Bool) {
      let commitText: String = String(cString: commit.text)
      if (_panellessCommitFix) {
        showPlaceholder(commitText)
        commitString(commitText)
        showPlaceholder(commitText.utf8.count == 1 ? "" : nil)
      } else {
        commitString(commitText)
        showPlaceholder("")
      }
      var _ = rime_get_api().pointee.free_commit(&commit)
      return true
    }
    return false
  }

  private func rimeUpdate() {
    //NSLog(@"rimeUpdate")
    let didCommit: Boolean = rimeConsumeCommittedText()
    var didCompose: Boolean = didCommit

    let panel: SquirrelPanel! = NSApp.squirrelAppDelegate.panel
    var status: RimeStatus = RimeStatus()
    if (rime_get_api().pointee.get_status(_session, &status).Bool) {
      // enable schema specific ui style
      if (_schemaId == nil || strcmp((_schemaId! as NSString).utf8String, status.schema_id) != 0) {
        _schemaId = String(cString: status.schema_id)
        _showingSwitcherMenu = rime_get_api().pointee.get_option(_session, "dumb").Bool
        if (!_showingSwitcherMenu) {
          NSApp.squirrelAppDelegate.loadSchemaSpecificLabels(schemaId: _schemaId!)
          NSApp.squirrelAppDelegate.loadSchemaSpecificSettings(schemaId: _schemaId!, withRimeSession: _session)
          // inline preedit
          _inlinePreedit = (panel.inlinePreedit && !rime_get_api().pointee.get_option(_session, "no_inline").Bool) ||
          rime_get_api().pointee.get_option(_session, "inline").Bool
          _inlineCandidate = panel.inlineCandidate && !rime_get_api().pointee.get_option(_session, "no_inline").Bool
          // if not inline, embed soft cursor in preedit string
          rime_get_api().pointee.set_option(_session, "soft_cursor", (!_inlinePreedit).Bool)
        } else {
          NSApp.squirrelAppDelegate.loadSchemaSpecificLabels(schemaId: "")
        }
        didCompose = true
      }
      _ = rime_get_api().pointee.free_status(&status)
    }

    var ctx: RimeContext = RimeContext()
    if (rime_get_api().pointee.get_context(_session, &ctx).Bool) {
      let showingStatus: Boolean = panel.statusMessage?.count ?? 0 > 0
      // update preedit text
      let preedit: UnsafeMutablePointer<CChar>? = ctx.composition.preedit
      let preeditText: String = preedit != nil ? String(cString: preedit!) : ""

      // update raw input
      let raw_input: UnsafePointer<CChar>? = rime_get_api().pointee.get_input(_session)
      let originalString: String = raw_input != nil ? String(cString: raw_input!) : ""
      didCompose = didCommit || originalString != _originalString
      _originalString = originalString

      // update composed string
      if (preedit == nil || _showingSwitcherMenu) {
        _composedString = ""
      } else if (!_inlinePreedit) { // remove soft cursor
        let cursorPos: size_t = size_t(ctx.composition.cursor_pos) -
        (ctx.composition.cursor_pos < ctx.composition.sel_end ? 3 : 0)
        _composedString = String(preeditText.utf8[preeditText.utf8.startIndex..<preeditText.utf8.index(preeditText.utf8.startIndex, offsetBy: cursorPos + 1)])! + String(preeditText.utf8[preeditText.utf8.index(preeditText.utf8.startIndex, offsetBy: cursorPos + 3)..<preeditText.utf8.endIndex])!
      } else {
        _composedString = String(cString: preedit!)
      }

      let start: Int = UTF8LengthToUTF16Length(str: preeditText, length: Int(ctx.composition.sel_start))
      let end: Int = UTF8LengthToUTF16Length(str: preeditText, length: Int(ctx.composition.sel_end))
      let caretPos: Int = UTF8LengthToUTF16Length(str: preeditText, length: Int(ctx.composition.cursor_pos))
      let length: Int = UTF8LengthToUTF16Length(str: preeditText, length: Int(ctx.composition.length))
      let numCandidates: Int = Int(ctx.menu.num_candidates)
      let pageNum: Int = Int(ctx.menu.page_no)
      let pageSize: Int = Int(ctx.menu.page_size)
      var highlightedIndex: Int = numCandidates == 0 ? NSNotFound : Int(ctx.menu.highlighted_candidate_index)
      let finalPage: Boolean = ctx.menu.is_last_page.Bool

      let selRange: NSRange = NSMakeRange(start, end - start)
      didCompose = didCompose || !NSEqualRanges(selRange, _selRange)
      _selRange = selRange
      // update expander and section status in tabular layout
      // already processed the action if _currentIndex == NSNotFound
      if (panel.tabular && !showingStatus) {
        if (numCandidates == 0 || didCompose) {
          panel.sectionNum = 0
        } else if (_currentIndex != NSNotFound) {
          let currentPageNum: Int = _currentIndex / pageSize
          if (!panel.locked && panel.expanded && panel.firstLine &&
              pageNum == 0 && highlightedIndex == 0 && _currentIndex == 0) {
            panel.expanded = false
          } else if (!panel.locked && !panel.expanded && pageNum > currentPageNum) {
            panel.expanded = true
          }
          if (panel.expanded && pageNum > currentPageNum &&
              panel.sectionNum < (panel.vertical ? 2 : 4)) {
            panel.sectionNum = min(panel.sectionNum + pageNum - currentPageNum,
                                   (finalPage ? 4 : 3) - (panel.vertical ? 2 : 0))
          } else if (panel.expanded && pageNum < currentPageNum &&
                     panel.sectionNum > 0) {
            panel.sectionNum = max(panel.sectionNum + pageNum - currentPageNum,
                                   pageNum == 0 ? 0 : 1)
          }
        }
        highlightedIndex += pageSize * panel.sectionNum
      }
      let extraCandidates: Int = panel.expanded && caretPos >= end ? (finalPage ? panel.sectionNum : (panel.vertical ? 2 : 4)) * pageSize : 0
      let indexStart: Int = (pageNum - panel.sectionNum) * pageSize
      _candidateIndices = indexStart..<(indexStart + numCandidates + extraCandidates)
      _currentIndex = highlightedIndex + indexStart

      if (showingStatus) {
        clearBuffer()
      } else if (_showingSwitcherMenu) {
        if (_inlinePlaceholder) {
          updateComposition()
        }
      } else if (_inlineCandidate) {
        let candidatePreview: UnsafeMutablePointer<CChar>? = ctx.commit_text_preview
        var candidatePreviewText = String(cString: candidatePreview ?? [0] as! UnsafeMutablePointer<CChar>)
        if (_inlinePreedit) {
          if (end <= caretPos && caretPos < length) {
            candidatePreviewText += preeditText[preeditText.index(preeditText.startIndex, offsetBy: caretPos)...]
          }
          if (!didCommit || candidatePreviewText.count > 0) {
            showPreeditString(candidatePreviewText, selRange: NSMakeRange(start, candidatePreviewText.count - (length - end) - start),
                              caretPos: caretPos < end ? caretPos : candidatePreviewText.count - (length - caretPos))
          }
        } else { // preedit includes the soft cursor
          if (end < caretPos && caretPos <= length) {
            candidatePreviewText = String(candidatePreviewText[..<candidatePreviewText.index(candidatePreviewText.startIndex, offsetBy: candidatePreviewText.count - (caretPos - end))])
          } else if (caretPos < end && end < length) {
            candidatePreviewText = String(candidatePreviewText[..<candidatePreviewText.index(candidatePreviewText.startIndex, offsetBy: candidatePreviewText.count - (length - end))])
          }
          if (!didCommit || candidatePreviewText.count > 0) {
            showPreeditString(candidatePreviewText,
                              selRange: NSMakeRange(start, candidatePreviewText.count - start),
                              caretPos: caretPos < end ? caretPos : candidatePreviewText.count)
          }
        }
      } else {
        if (_inlinePreedit && !_showingSwitcherMenu) {
          if (_inlinePlaceholder && preeditText.count == 0 && numCandidates > 0) {
            showPlaceholder(kFullWidthSpace)
          } else if (!didCommit || preeditText.count > 0) {
            showPreeditString(preeditText, selRange: NSMakeRange(start, end - start), caretPos: caretPos)
          }
        } else {
          if (_inlinePlaceholder && preedit != nil) {
            showPlaceholder(kFullWidthSpace)
          } else if (!didCommit || preedit != nil) {
            showPreeditString("", selRange: NSMakeRange(0, 0), caretPos: 0)
          }
        }
      }
      // overwrite old cached candidates (index = 0) OR continue cache more candidates
      if (didCompose || numCandidates == 0) {
        _candidateTexts.removeAll()
        _candidateComments.removeAll()
      }
      var index: Int = _candidateTexts.count
      // cache candidates
      if (index < pageSize * pageNum) {
        var iterator: RimeCandidateListIterator = RimeCandidateListIterator()
        if (rime_get_api().pointee.candidate_list_from_index(_session, &iterator, CInt(index)).Bool) {
          let endIndex: Int = pageSize * pageNum
          while (index < endIndex && rime_get_api().pointee.candidate_list_next(&iterator).Bool) {
            updateCandidate(iterator.candidate, atIndex: index)
            index += 1
          }
          rime_get_api().pointee.candidate_list_end(&iterator)
        }
      }
      if (index < pageSize * pageNum + numCandidates) {
        for i in 0..<numCandidates {
          updateCandidate(ctx.menu.candidates[i], atIndex: index)
          index += 1
        }
      }
      if (index < _candidateIndices.upperBound) {
        var iterator: RimeCandidateListIterator = RimeCandidateListIterator()
        if (rime_get_api().pointee.candidate_list_from_index(_session, &iterator, CInt(index)).Bool) {
          let endIndex: Int = pageSize * (pageNum + (panel.vertical ? 3 : 5) - panel.sectionNum)
          while (index < endIndex && rime_get_api().pointee.candidate_list_next(&iterator).Bool) {
            updateCandidate(iterator.candidate, atIndex: index)
             index += 1
          }
          rime_get_api().pointee.candidate_list_end(&iterator)
          _candidateIndices = _candidateIndices.lowerBound..<index
        }
      }
      // remove old candidates that were not overwritted, if any, subscripted from index
      updateCandidate(nil, atIndex: index)

      showPanel(withPreedit: _inlinePreedit && !_showingSwitcherMenu ? nil : preeditText,
                selRange: selRange,
                caretPos: _showingSwitcherMenu ? NSNotFound : caretPos,
                candidateIndices: _candidateIndices,
                highlightedIndex: highlightedIndex,
                pageNum: pageNum,
                finalPage: finalPage,
                didCompose: didCompose)
      _ = rime_get_api().pointee.free_context(&ctx)
    } else {
      hidePalettes()
      clearBuffer()
    }
  }

  private func updateCandidate(_ candidate: RimeCandidate?,
                               atIndex index: Int) {
    if (candidate == nil || index > _candidateTexts.count) {
      if (index < _candidateTexts.count) {
        let remove: Range<Int> = index..<_candidateTexts.count
        _candidateTexts.removeSubrange(remove)
        _candidateComments.removeSubrange(remove)
      }
      return;
    }
    if (index == _candidateTexts.count) {
      _candidateTexts.append(String(cString: candidate!.text))
      _candidateComments.append(String(cString: candidate!.comment))
    } else {
      if (strcmp(candidate!.text, _candidateTexts[index].cString(using: .utf8)) != 0) {
        _candidateTexts[index] = String(cString: candidate!.text)
      }
      if (strcmp(candidate!.comment ?? [0] as! UnsafeMutablePointer<CChar>,
                 _candidateComments[index].cString(using: .utf8)) != 0) {
        _candidateComments[index] = String(cString: candidate!.comment ?? [0] as! UnsafeMutablePointer<CChar>)
      }
    }
  }

}

