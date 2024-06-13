import InputMethodKit
import IOKit

final class SquirrelInputController: IMKInputController {
  // class variables
  weak static var currentController: SquirrelInputController?
  private static var currentApp: String = ""
  private static var asciiMode: Bool? = nil
  static var chordDuration: TimeInterval = 0
  // private
  private var inlineString: NSMutableAttributedString?
  private var originalString: String?
  private var composedString: String?
  private var schemaId: String = ""
  private var selSegment: Range<Int> = 0 ..< 0
  private var candidateIndices: Range<Int> = 0 ..< 0
  private var inlineSelRange: Range<Int> = 0 ..< 0
  private var inlineCaretPos: Int = 0
  private var converted: Int = 0
  private var currentIndex: Int?
  private var lastModifiers: NSEvent.ModifierFlags = []
  private var lastEventCount: UInt32 = 0
  private var session: RimeSessionId = 0
  private var inlinePreedit: Bool = false
  private var inlineCandidate: Bool = false
  private var goodOldCapsLock: Bool = false
  private var showingSwitcherMenu: Bool = false
  // app-specific options
  private var appOptions = SquirrelAppOptions()
  private var inlinePlaceholder: Bool = false
  private var panellessCommitFix: Bool = false
  private var inlineOffset: Int = 0
  // for chord-typing
  private var chordTimer: Timer?
  private var chordKeyCombos: [(keycode: RimeKeycode, modifiers: RimeModifiers)] = []
  // public
  private(set) var candidateTexts: [String] = []
  private(set) var candidateComments: [String] = []
  // KVO
  @objc dynamic var viewEffectiveAppearance: NSAppearance {
    let sel: Selector = NSSelectorFromString("viewEffectiveAppearance")
    let sourceAppearance: NSAppearance? = client().perform(sel)?.takeUnretainedValue() as? NSAppearance
    return sourceAppearance ?? NSApp.effectiveAppearance
  }

  private var observation: NSKeyValueObservation?
  // constants
  private let kFullWidthSpace: String = "　"
  private let kNumKeyRollOver: Int = 50

  static func updateCurrentController(_ controller: SquirrelInputController) {
    currentController = controller
    NSApp.SquirrelAppDelegate.panel.inputController = controller
    NSApp.SquirrelAppDelegate.panel.IbeamRect = .zero
    let appearanceName: NSAppearance.Name = controller.viewEffectiveAppearance.bestMatch(from: [.aqua, .darkAqua])!
    let style: SquirrelStyle = appearanceName == .darkAqua ? .dark : .light
    NSApp.SquirrelAppDelegate.panel.style = style
  }

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    // print("init(server:delegate:client:)")
    super.init(server: server, delegate: delegate, client: inputClient)
    observation = observe(\.viewEffectiveAppearance, options: [.new, .initial]) { object, change in
      let appearanceName: NSAppearance.Name = change.newValue!.bestMatch(from: [.aqua, .darkAqua])!
      let style: SquirrelStyle = appearanceName == .darkAqua ? .dark : .light
      NSApp.SquirrelAppDelegate.panel.style = style
    }
    createSession()
  }

  override func activateServer(_ sender: Any!) {
    // print("activateServer:")
    Self.updateCurrentController(self)
    let baseConfig = SquirrelConfig("squirrel")
    if let keyboardLayout: String = baseConfig.string(forOption: "keyboard_layout") {
      if keyboardLayout.caseInsensitiveCompare("last") == .orderedSame || keyboardLayout.isEmpty {
        // do nothing
      } else if keyboardLayout.caseInsensitiveCompare("default") == .orderedSame {
        client().overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
      } else if !keyboardLayout.hasPrefix("com.apple.keylayout.") {
        client().overrideKeyboard(withKeyboardNamed: "com.apple.keylayout." + keyboardLayout)
      }
    }
    baseConfig.close()

    let defaultConfig = SquirrelConfig("default")
    if defaultConfig.hasSection("ascii_composer") {
      goodOldCapsLock = defaultConfig.boolValue(forOption: "ascii_composer/good_old_caps_lock")
    }
    defaultConfig.close()
    if !NSApp.SquirrelAppDelegate.isCurrentInputMethod {
      NSApp.SquirrelAppDelegate.isCurrentInputMethod = true
      if NSApp.SquirrelAppDelegate.showNotifications == .always {
        showInitialStatus()
      }
    }
    lastModifiers = []
    lastEventCount = 0
    super.activateServer(sender)
  }

  override func deactivateServer(_ sender: Any!) {
    // print("deactivateServer:")
    Self.asciiMode = RimeApi.get_option(session, "ascii_mode")
    commitComposition(sender)
    super.deactivateServer(sender)
  }

  /* Receive incoming event
   Return `true` to indicate the the key input was received and dealt with.
   Key processing will not continue in that case.  In other words the
   system will not deliver a key down event to the application.
   Returning `false` means the original key down will be passed on to the client. */
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    autoreleasepool {
      if session == 0 || !RimeApi.find_session(session) {
        createSession()
        guard session != 0 else { return false }
      }
      var handled: Bool = false
      let modifiers: NSEvent.ModifierFlags = event.modifierFlags
      var rimeModifiers = RimeModifiers(macModifiers: modifiers)
      let keyCode = Int(event.cgEvent!.getIntegerValueField(.keyboardEventKeycode))

      switch event.type {
      case .flagsChanged:
        if lastModifiers == modifiers { return true }
        // print("FLAGSCHANGED client: \(sender!), modifiers: 0x\(modifiers.rawValue)")
        let rimeKeycode = RimeKeycode(macKeycode: keyCode)
        let eventCountTypes: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let eventCount = eventCountTypes.reduce(0) { $0 + CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
        lastModifiers = modifiers
        switch keyCode {
        case kVK_CapsLock:
          if !goodOldCapsLock {
            updateCapsLockLEDState(targetState: false)
            if RimeApi.get_option(session, "ascii_mode") {
              rimeModifiers.insert(.Lock)
            } else {
              rimeModifiers.subtract(.Lock)
            }
          } else {
            rimeModifiers.formSymmetricDifference(.Lock)
          }
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
        case kVK_Shift, kVK_RightShift:
          if !modifiers.contains(.shift) { rimeModifiers.insert(.Release) }
          if eventCount - lastEventCount != 1 { rimeModifiers.insert(.Ignored) }
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
        case kVK_Control, kVK_RightControl:
          if !modifiers.contains(.control) { rimeModifiers.insert(.Release) }
          if eventCount - lastEventCount != 1 { rimeModifiers.insert(.Ignored) }
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
        case kVK_Option, kVK_RightOption:
          if modifiers == .option && NSApp.SquirrelAppDelegate.panel.showToolTip() {
            lastEventCount = eventCount
            return true
          }
          if !modifiers.contains(.option) { rimeModifiers.insert(.Release) }
          if eventCount - lastEventCount != 1 { rimeModifiers.insert(.Ignored) }
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
        case kVK_Function:
          if !modifiers.contains(.function) { rimeModifiers.insert(.Release) }
          if eventCount - lastEventCount != 1 { rimeModifiers.insert(.Ignored) }
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
        case kVK_Command, kVK_RightCommand:
          if !modifiers.contains(.command) { rimeModifiers.insert(.Release) }
          if eventCount - lastEventCount != 1 { rimeModifiers.insert(.Ignored) }
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
        default:
          return false
        }
        if NSApp.SquirrelAppDelegate.panel.hasStatusMessage || handled {
          rimeUpdate()
          handled = true
        }
        lastEventCount = eventCount
      case .keyDown:
        // print("KEYDOWN client: \(sender), modifiers: \(modifiers), keyCode: \(keyCode)")
        // translate osx keyevents to rime keyevents
        var rime_keycode = RimeKeycode(macKeycode: keyCode)
        if rime_keycode == .XK_VoidSymbol {
          let keyChars: String = (modifiers.contains(.shift) && modifiers.isDisjoint(with: [.control, .option]) ? event.characters! : event.charactersIgnoringModifiers!).precomposedStringWithCanonicalMapping
          rime_keycode = RimeKeycode(keychar: keyChars.utf16[keyChars.utf16.startIndex], shift: modifiers.contains(.shift), caps: modifiers.contains(.capsLock))
        } else if (0x60 <= keyCode && keyCode <= 0xFF) || keyCode == 0x50 || keyCode == 0x4F || keyCode == 0x47 || keyCode == 0x40 {
          // revert non-modifier function keys' FunctionKeyMask (FwdDel, Navigations, F1..F19)
          rimeModifiers.subtract(.Hyper)
        }
        if rime_keycode != .XK_VoidSymbol {
          handled = processKey(rime_keycode, modifiers: rimeModifiers)
          if handled {
            rimeUpdate()
          } else if panellessCommitFix && client().markedRange().length > 0 {
            if rime_keycode == .XK_Delete || (rime_keycode >= .XK_Home && rime_keycode <= .XK_KP_Delete) || (rime_keycode >= .XK_BackSpace && rime_keycode <= .XK_Escape) {
              showPlaceholder("")
            } else if modifiers.isDisjoint(with: [.control, .command]) && !event.characters!.isEmpty {
              showPlaceholder(nil)
              client().insertText(event.characters, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
              return true
            }
          }
        }
      default: break
      }
      return handled
    }
  }

  override func mouseDown(onCharacterIndex index: Int, coordinate point: NSPoint, withModifier flags: Int, continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!, client sender: Any!) -> Bool {
    keepTracking.pointee = false
    guard inlinePreedit || inlineCandidate, let composed = composedString, !composed.isEmpty, inlineCaretPos != index, NSEvent.ModifierFlags(rawValue: UInt(flags)).intersection(.deviceIndependentFlagsMask).isEmpty else { return false }
    let markedRange: NSRange = client().markedRange()
    let head: NSPoint = (client().attributes(forCharacterIndex: 0, lineHeightRectangle: nil)["IMKBaseline"] as! NSValue).pointValue
    let tail: NSPoint = (client().attributes(forCharacterIndex: markedRange.length - 1, lineHeightRectangle: nil)["IMKBaseline"] as! NSValue).pointValue
    if point.x > tail.x || index >= markedRange.length {
      if inlineCandidate && !inlinePreedit { return false }
      perform(action: .PROCESS, onIndex: .EndKey)
    } else if point.x < head.x || index <= 0 {
      perform(action: .PROCESS, onIndex: .HomeKey)
    } else {
      moveCursor(inlineCaretPos, to: index, inlinePreedit: inlinePreedit, inlineCandidate: inlineCandidate)
    }
    return true
  }

  private func processKey(_ keycode: RimeKeycode, modifiers: RimeModifiers) -> Bool {
    let panel = NSApp.SquirrelAppDelegate.panel
    // with linear candidate list, arrow keys may behave differently.
    let isLinear = panel.isLinear
    if isLinear != RimeApi.get_option(session, "_linear") {
      RimeApi.set_option(session, "_linear", isLinear)
    }
    // with vertical text, arrow keys may behave differently.
    let isVertical = panel.isVertical
    if isVertical != RimeApi.get_option(session, "_vertical") {
      RimeApi.set_option(session, "_vertical", isVertical)
    }

    let isNavigatorInTabular = panel.isTabular && modifiers.isEmpty && panel.isVisible && (isVertical ? keycode == .XK_Left || keycode == .XK_KP_Left || keycode == .XK_Right || keycode == .XK_KP_Right : keycode == .XK_Up || keycode == .XK_KP_Up || keycode == .XK_Down || keycode == .XK_KP_Down)
    if isNavigatorInTabular {
      var keycode: RimeKeycode = keycode
      if keycode >= .XK_KP_Left && keycode <= .XK_KP_Down {
        keycode = keycode - .XK_KP_Left + .XK_Left
      }
      if let newIndex = panel.candidateIndex(onDirection: SquirrelIndex(rawValue: Int(keycode.rawValue))!) {
        if !panel.isLocked && !panel.isExpanded && keycode == (isVertical ? .XK_Left : .XK_Down) {
          panel.isExpanded = true
        }
        _ = RimeApi.highlight_candidate(session, newIndex)
        return true
      } else if !panel.isLocked && panel.isExpanded && panel.sectionNum == 0 && keycode == (isVertical ? .XK_Right : .XK_Up) {
        panel.isExpanded = false
        return true
      }
    }

    let handled = RimeApi.process_key(session, keycode.rawValue, modifiers.rawValue)
    // print("rime_keycode: \(rime_keycode), rime_modifiers: \(rime_modifiers), handled = \(handled)")
    if !handled {
      let isVimBackInCommandMode: Bool = keycode == .XK_Escape || (modifiers.contains(.Control) && (keycode == .XK_c || keycode == .XK_C || keycode == .XK_bracketleft))
      if isVimBackInCommandMode && RimeApi.get_option(session, "vim_mode") &&
        !RimeApi.get_option(session, "ascii_mode") {
        cancelComposition()
        RimeApi.set_option(session, "ascii_mode", true)
        // print("turned Chinese mode off in vim-like editor's command mode")
        return true
      }
    }

    // Simulate key-ups for every interesting key-down for chord-typing.
    if handled {
      let isChordingKey = (keycode >= .XK_space && keycode <= .XK_asciitilde) || keycode == .XK_Control_L || keycode == .XK_Control_R || keycode == .XK_Alt_L || keycode == .XK_Alt_R || keycode == .XK_Shift_L || keycode == .XK_Shift_R
      if isChordingKey && RimeApi.get_option(session, "_chord_typing") {
        updateChord(keycode, modifiers: modifiers)
      } else if modifiers.isDisjoint(with: .Release) {
        // non-chording key pressed
        clearChord()
      }
    }

    return handled
  }

  func moveCursor(_ cursorPosition: Int, to targetPosition: Int, inlinePreedit: Bool, inlineCandidate: Bool) {
    let isVertical: Bool = NSApp.SquirrelAppDelegate.panel.isVertical
    autoreleasepool {
      let composition: String = !inlinePreedit && !inlineCandidate ? composedString! : inlineString!.string
      var ctx: RimeContext_stdbool = RimeStructInit()
      if cursorPosition > targetPosition {
        let targetRange = ..<composition.utf16.index(composition.utf16.startIndex, offsetBy: targetPosition)
        let targetPrefix = String(composition.utf16[targetRange])!.replacingOccurrences(of: " ", with: "")
        let range = ..<composition.utf16.index(composition.utf16.startIndex, offsetBy: cursorPosition)
        var prefix = String(composition.utf16[range])!.replacingOccurrences(of: " ", with: "")

        let noneConverted: Bool = originalString!.hasSuffix(composition[composition.index(composition.startIndex, offsetBy: targetPosition)...].replacingOccurrences(of: " ", with: ""))
        while targetPrefix.utf16.count < prefix.utf16.count {
          let byChar: Bool = noneConverted && !String(prefix.utf16[targetPrefix.utf16.endIndex...])!.contains(" ")
          _ = RimeApi.process_key(session, isVertical ? (byChar ? RimeKeycode.XK_KP_Up.rawValue : RimeKeycode.XK_Up.rawValue) : (byChar ? RimeKeycode.XK_KP_Left.rawValue : RimeKeycode.XK_Left.rawValue), 0)
          _ = RimeApi.get_context(session, &ctx)
          if inlineCandidate {
            let length = ctx.composition.cursor_pos < ctx.composition.sel_end ? Int(ctx.composition.cursor_pos) : strlen(ctx.commit_text_preview) - Int(inlinePreedit ? 0 : ctx.composition.cursor_pos - ctx.composition.sel_end)
            prefix = ctx.commit_text_preview == nil ? "" : String(cString: ctx.commit_text_preview!)
            prefix = String(prefix.utf8[..<prefix.utf8.index(prefix.utf8.startIndex, offsetBy: length)])!.replacingOccurrences(of: " ", with: "")
          } else {
            prefix = ctx.composition.preedit == nil ? "" : String(cString: ctx.composition.preedit!)
            prefix = String(prefix.utf8[..<prefix.utf8.index(prefix.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos))])!.replacingOccurrences(of: " ", with: "")
          }
          _ = RimeApi.free_context(&ctx)
        }
      } else if cursorPosition < targetPosition {
        let targetRange = composition.utf16.index(composition.utf16.startIndex, offsetBy: targetPosition)...
        let targetSuffix = String(composition.utf16[targetRange])!.replacingOccurrences(of: " ", with: "")
        let range = composition.utf16.index(composition.utf16.startIndex, offsetBy: targetPosition) ..< composition.utf16.endIndex
        var suffix = String(composition.utf16[range])!.replacingOccurrences(of: " ", with: "")
        while targetSuffix.utf16.count < suffix.utf16.count {
          _ = RimeApi.process_key(session, isVertical ? RimeKeycode.XK_Down.rawValue : RimeKeycode.XK_Right.rawValue, 0)
          _ = RimeApi.get_context(session, &ctx)
          suffix = ctx.composition.preedit == nil ? "" : String(cString: ctx.composition.preedit! + Int(ctx.composition.cursor_pos) + (!inlinePreedit && !inlineCandidate ? 3 : 0)).replacingOccurrences(of: " ", with: "")
          _ = RimeApi.free_context(&ctx)
        }
      }
      rimeUpdate()
    }
  }

  func perform(action: SquirrelAction, onIndex index: SquirrelIndex) {
    // print("perform action: \(action) on index: \(index)")
    var handled: Bool = false
    switch action {
    case .PROCESS:
      if index.rawValue >= 0xFF08 && index.rawValue <= 0xFFFF {
        handled = RimeApi.process_key(session, CInt(index.rawValue), 0)
      } else if index >= .ExpandButton && index <= .LockButton {
        handled = true
        currentIndex = nil
      }
    case .SELECT:
      handled = RimeApi.select_candidate(session, index.rawValue)
    case .HIGHLIGHT:
      handled = RimeApi.highlight_candidate(session, index.rawValue)
      currentIndex = nil
    case .DELETE:
      handled = RimeApi.delete_candidate(session, index.rawValue)
    }
    if handled {
      rimeUpdate()
    }
  }

  private func onChordTimer() {
    // chord release triggered by timer
    var processed_keys: Int = 0
    if !chordKeyCombos.isEmpty && session != 0 {
      chordKeyCombos.forEach { if RimeApi.process_key(session, $0.keycode.rawValue, $0.modifiers.union(.Release).rawValue) { processed_keys += 1 } }
    }
    clearChord()
    if processed_keys > 0 {
      rimeUpdate()
    }
  }

  private func updateChord(_ keycode: RimeKeycode, modifiers: RimeModifiers) {
    // print("update chord: {\(_chord)} << \(keycode)")
    chordKeyCombos.forEach { if $0.keycode == keycode { return } }
    // you are cheating. only one human typist (fingers <= 10) is supported.
    if chordKeyCombos.count >= kNumKeyRollOver { return }
    chordKeyCombos.append((keycode: keycode, modifiers: modifiers))
    // reset timer
    chordTimer?.invalidate()
    chordTimer = Timer.scheduledTimer(withTimeInterval: Self.chordDuration, repeats: false) { _ in self.onChordTimer() }
  }

  private func clearChord() {
    chordKeyCombos = []
    chordTimer?.invalidate()
  }

  override func recognizedEvents(_ sender: Any!) -> Int {
    // print("recognizedEvents:")
    return Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged, .leftMouseDown]).rawValue)
  }

  private func showInitialStatus() {
    var status: RimeStatus_stdbool = RimeStructInit()
    guard session != 0 && RimeApi.get_status(session, &status) else { return }
    schemaId = String(cString: status.schema_id)
    let schemaName = status.schema_name == nil ? schemaId : String(cString: status.schema_name!)
    var options: [String] = []
    if let asciiMode = getOptionLabel(session: session, option: "ascii_mode", state: status.is_ascii_mode) {
      options.append(asciiMode)
    }
    if let fullShape = getOptionLabel(session: session, option: "full_shape", state: status.is_full_shape) {
      options.append(fullShape)
    }
    if let asciiPunct = getOptionLabel(session: session, option: "ascii_punct", state: status.is_ascii_punct) {
      options.append(asciiPunct)
    }
    _ = RimeApi.free_status(&status)
    let foldedOptions = options.isEmpty ? schemaName : schemaName + "｜" + options.joined(separator: " ")

    NSApp.SquirrelAppDelegate.panel.updateStatus(long: foldedOptions, short: schemaName)
    if #available(macOS 14.0, *) {
      lastModifiers.insert(.help)
    }
    rimeUpdate()
  }

  override func commitComposition(_ sender: Any!) {
    // print("commitComposition:")
    commitString(composedString(sender))
    if session != 0 { RimeApi.clear_composition(session) }
    hidePalettes()
  }

  private func clearBuffer() {
    NSApp.SquirrelAppDelegate.panel.IbeamRect = .zero
    inlineString = nil
    originalString = nil
    composedString = nil
  }

  // Though we specify AppDelegate as the menu action receiver, Inputcontroller
  // is the one that actually receives the event. Here we relay these messages.
  @objc private func showSwitcher(_ sender: Any?) {
    NSApp.SquirrelAppDelegate.showSwitcher(session)
    rimeUpdate()
  }

  @objc private func deploy(_ sender: Any?) {
    NSApp.SquirrelAppDelegate.deploy(sender)
  }

  @objc private func syncUserData(_ sender: Any?) {
    NSApp.SquirrelAppDelegate.syncUserData(sender)
  }

  @objc private func configure(_ sender: Any?) {
    NSApp.SquirrelAppDelegate.configure(sender)
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    NSApp.SquirrelAppDelegate.checkForUpdates(sender)
  }

  @objc private func openWiki(_ sender: Any?) {
    NSApp.SquirrelAppDelegate.openWiki(sender)
  }

  @objc private func openLogFolder(_ sender: Any?) {
    NSApp.SquirrelAppDelegate.openLogFolder(sender)
  }

  override func menu() -> NSMenu {
    return NSApp.SquirrelAppDelegate.menu
  }

  override func originalString(_ sender: Any!) -> NSAttributedString! {
    return NSAttributedString(string: originalString ?? "")
  }

  override func composedString(_ sender: Any!) -> Any! {
    return composedString?.replacingOccurrences(of: " ", with: "") ?? ""
  }

  override func candidates(_ sender: Any!) -> [Any]! {
    return Array(candidateTexts[candidateIndices])
  }

  override func hidePalettes() {
    NSApp.SquirrelAppDelegate.panel.hide()
    super.hidePalettes()
  }

  deinit {
    // print("deinit")
    destroySession()
    clearBuffer()
  }

  override func selectionRange() -> NSRange {
    return NSRange(location: inlineCaretPos, length: 0)
  }

  override func replacementRange() -> NSRange {
    return NSRange(location: NSNotFound, length: NSNotFound)
  }

  private func commitString(_ string: Any!) {
    // print("commitString:")
    client().insertText(string, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    clearBuffer()
  }

  override func cancelComposition() {
    commitString(originalString(client))
    hidePalettes()
    if session != 0 { RimeApi.clear_composition(session) }
  }

  override func updateComposition() {
    client().setMarkedText(inlineString, selectionRange: NSRange(location: inlineCaretPos, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
  }

  private func showPlaceholder(_ placeholder: String?) {
    let attrs = mark(forStyle: kTSMHiliteSelectedRawText, at: NSRange(location: 0, length: placeholder?.utf16.count ?? 1)) as! [NSAttributedString.Key: Any]
    inlineString = NSMutableAttributedString(string: placeholder ?? "█", attributes: attrs)
    inlineCaretPos = 0
    updateComposition()
  }

  private func showInlineString(_ string: String, withSelRange selRange: Range<Int>, caretPos: Int) {
    // print("showPreeditString: '\(preedit)'")
    if caretPos == inlineCaretPos && selRange == inlineSelRange && string == inlineString?.string {
      return
    }
    inlineSelRange = selRange
    inlineCaretPos = caretPos
    // print("selRange = \(selRange), caretPos = \(caretPos)")
    let attrs = mark(forStyle: kTSMHiliteRawText, at: NSRange(location: 0, length: string.utf16.count)) as! [NSAttributedString.Key: Any]
    inlineString = NSMutableAttributedString(string: string, attributes: attrs)
    if selRange.lowerBound > 0 {
      inlineString?.addAttributes(mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: selRange.lowerBound)) as! [NSAttributedString.Key: Any], range: NSRange(location: 0, length: selRange.lowerBound))
    }
    if selRange.lowerBound < caretPos {
      inlineString?.addAttributes(mark(forStyle: kTSMHiliteSelectedRawText, at: NSRange(selRange)) as! [NSAttributedString.Key: Any], range: NSRange(selRange))
    }
    updateComposition()
  }

  private func getIbeamRect() -> NSRect {
    var IbeamRect: NSRect = .zero
    client().attributes(forCharacterIndex: 0, lineHeightRectangle: &IbeamRect)
    if IbeamRect.isEmpty && inlineString?.length == 0 {
      if client().selectedRange().length == 0 {
        // activate inline session, in e.g. table cells, by fake inputs
        client().setMarkedText(" ", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        client().attributes(forCharacterIndex: 0, lineHeightRectangle: &IbeamRect)
        client().setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
      } else {
        client().attributes(forCharacterIndex: client().selectedRange().location, lineHeightRectangle: &IbeamRect)
      }
    }
    if IbeamRect.isEmpty {
      return NSRect(origin: NSEvent.mouseLocation, size: .zero)
    }
    if IbeamRect.width > IbeamRect.height {
      IbeamRect.origin.x += CGFloat(inlineOffset)
    } else {
      IbeamRect.origin.y += CGFloat(inlineOffset)
    }
    if #available(macOS 14.0, *) { // avoid overlapping with cursor effects view
      if (goodOldCapsLock && lastModifiers.contains(.capsLock)) || lastModifiers.contains(.help) {
        lastModifiers.subtract(.help)
        var screenRect: NSRect = NSScreen.main?.frame ?? .zero
        guard !IbeamRect.intersects(screenRect) else { return IbeamRect}
        screenRect = NSScreen.main?.visibleFrame ?? .zero
        if IbeamRect.width > IbeamRect.height {
          var capslockAccessory = NSRect(x: IbeamRect.minX - 30, y: IbeamRect.minY, width: 27, height: IbeamRect.height)
          if capslockAccessory.minX < screenRect.minX {
            capslockAccessory.origin.x = screenRect.minX
          }
          if capslockAccessory.maxX > screenRect.maxX {
            capslockAccessory.origin.x = screenRect.maxX - capslockAccessory.width
          }
          IbeamRect = IbeamRect.union(capslockAccessory)
        } else {
          var capslockAccessory = NSRect(x: IbeamRect.minX, y: IbeamRect.minY - 26, width: IbeamRect.width, height: 23)
          if capslockAccessory.minY < screenRect.minY {
            capslockAccessory.origin.y = screenRect.maxY + 3
          }
          if capslockAccessory.maxY > screenRect.maxY {
            capslockAccessory.origin.y = screenRect.maxY - capslockAccessory.height
          }
          IbeamRect = IbeamRect.union(capslockAccessory)
        }
      }
    }
    return IbeamRect
  }

  private func showPanel(withPreedit preedit: String, selRange: NSRange, caretPos: Int?, candidateIndices: Range<Int>, highlightedCandidate: Int?, pageNum: Int, isLastPage: Bool, didCompose: Bool) {
    // print("showPanelWithPreedit:...:")
    let panel: SquirrelPanel! = NSApp.SquirrelAppDelegate.panel
    panel.IbeamRect = getIbeamRect()
    if panel.IbeamRect.isEmpty && panel.hasStatusMessage {
      panel.updateStatus(long: nil, short: nil)
    } else {
      panel.showPanel(withPreedit: preedit, selRange: selRange, caretPos: caretPos, candidateIndices: candidateIndices, highlightedCandidate: highlightedCandidate, pageNum: pageNum, isLastPage: isLastPage, didCompose: didCompose)
    }
  }

  // MARK: Private functions

  private func createSession() {
    let app: String = client().bundleIdentifier()
    // print("createSession: \(app)")
    session = RimeApi.create_session()
    let panel = NSApp.SquirrelAppDelegate.panel
    schemaId = panel.optionSwitcher.schemaId
    guard session != 0 else { return }
    let config = SquirrelConfig("squirrel")
    appOptions = config.appOptions(forApp: app)
    config.close()
    inlinePreedit = (panel.inlinePreedit && !appOptions.boolValue(forOption: "no_inline")) || appOptions.boolValue(forOption: "inline")
    inlineCandidate = panel.inlineCandidate && !appOptions.boolValue(forOption: "no_inline")
    panellessCommitFix = appOptions.boolValue(forOption: "panelless_commit_fix")
    inlinePlaceholder = appOptions.boolValue(forOption: "inline_placeholder")
    inlineOffset = appOptions.intValue(forOption: "inline_offset")
    if let asciiMode = Self.asciiMode, app == Self.currentApp {
      RimeApi.set_option(session, "ascii_mode", asciiMode)
    }
    Self.currentApp = app
    Self.asciiMode = nil
    rimeUpdate()
  }

  private func destroySession() {
    // print("destroySession:")
    if session != 0 {
      _ = RimeApi.destroy_session(session)
      session = 0
    }
    clearChord()
  }

  private func rimeConsumeCommittedText() -> Bool {
    var commit: RimeCommit = RimeStructInit()
    if RimeApi.get_commit(session, &commit) {
      let commitText = String(cString: commit.text!)
      if panellessCommitFix {
        showPlaceholder(commitText)
        commitString(commitText)
        showPlaceholder(commitText.utf8.count == 1 ? "" : nil)
      } else {
        commitString(commitText)
        showPlaceholder("")
      }
      _ = RimeApi.free_commit(&commit)
      return true
    }
    return false
  }

  private func rimeUpdate() {
    // print("rimeUpdate")
    let didCommit: Bool = rimeConsumeCommittedText()
    var didCompose: Bool = didCommit

    let panel = NSApp.SquirrelAppDelegate.panel
    var status: RimeStatus_stdbool = RimeStructInit()
    if RimeApi.get_status(session, &status) {
      // enable schema specific ui style
      if schemaId.isEmpty || strcmp(schemaId, status.schema_id) != 0 {
        schemaId = String(cString: status.schema_id)
        showingSwitcherMenu = RimeApi.get_option(session, "dumb")
        if !showingSwitcherMenu {
          NSApp.SquirrelAppDelegate.loadSchemaSpecificLabels(schemaId: schemaId)
          NSApp.SquirrelAppDelegate.loadSchemaSpecificSettings(schemaId: schemaId, withRimeSession: session)
          // inline preedit
          inlinePreedit = (panel.inlinePreedit && !appOptions.boolValue(forOption: "no_inline")) || appOptions.boolValue(forOption: "inline")
          inlineCandidate = panel.inlineCandidate && !appOptions.boolValue(forOption: "no_inline")
          // if not inline, embed soft cursor in preedit string
          RimeApi.set_option(session, "soft_cursor", !inlinePreedit)
        } else {
          NSApp.SquirrelAppDelegate.loadSchemaSpecificLabels(schemaId: "")
        }
        didCompose = true
      }
      _ = RimeApi.free_status(&status)
    }

    var ctx: RimeContext_stdbool = RimeStructInit()
    if RimeApi.get_context(session, &ctx) {
      let showingStatus: Bool = panel.hasStatusMessage
      // update preedit text
      let preedit: UnsafeMutablePointer<CChar>? = ctx.composition.preedit
      let preeditText = preedit == nil ? "" : String(cString: preedit!)

      // update raw input
      let raw_input: UnsafePointer<CChar>? = RimeApi.get_input(session)
      let originalString = raw_input == nil ? "" : String(cString: raw_input!)
      didCompose |= originalString != self.originalString
      self.originalString = originalString

      // update composed string
      if preedit == nil || showingSwitcherMenu {
        composedString = ""
      } else if !inlinePreedit { // remove soft cursor
        let prefixRange = ..<preeditText.utf8.index(preeditText.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos))
        let suffixRange = preeditText.utf8.index(preeditText.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos) + 3)...
        composedString = String(preeditText.utf8[prefixRange])! + String(preeditText.utf8[suffixRange])!
      } else {
        composedString = preeditText
      }

      let start: Int = preeditText.unicharIndex(charIndex: ctx.composition.sel_start)
      let end: Int = preeditText.unicharIndex(charIndex: ctx.composition.sel_end)
      let caretPos: Int = preeditText.unicharIndex(charIndex: ctx.composition.cursor_pos)
      let length: Int = preeditText.unicharIndex(charIndex: ctx.composition.length)
      let numCandidates: Int = Int(ctx.menu.num_candidates)
      let pageNum: Int = Int(ctx.menu.page_no)
      let pageSize: Int = Int(ctx.menu.page_size)
      var hilitedCandidate: Int? = numCandidates == 0 ? nil : Int(ctx.menu.highlighted_candidate_index)
      let isLastPage: Bool = ctx.menu.is_last_page

      // selected segment, with locations in terms of raw input
      let unicharStart = preeditText.utf16.index(preeditText.utf16.startIndex, offsetBy: start)
      let unicharEnd = preeditText.utf16.index(preeditText.utf16.startIndex, offsetBy: end)
      var suffixLength = String(preeditText.utf16[unicharEnd...])?.replacingOccurrences(of: " ", with: "").utf16.count ?? 0
      let selLength = String(preeditText.utf16[unicharStart ..< unicharEnd])?.replacingOccurrences(of: " ", with: "").utf16.count ?? 0
      if !inlinePreedit && caretPos < length && caretPos >= end { // subtract length of soft cursor
        suffixLength -= 1
      }
      let selSegment: Range<Int> = self.originalString == nil ? 0 ..< 0 : self.originalString!.utf16.count - suffixLength - selLength ..< self.originalString!.utf16.count - suffixLength
      didCompose |= selSegment.lowerBound != self.selSegment.lowerBound || (selSegment.count != self.selSegment.count && hilitedCandidate == 0 && pageNum == 0)
      self.selSegment = selSegment
      // update `expanded` and `sectionNum` variables in tabular layout
      // already processed the action if `currentIndex` == nil
      if panel.isTabular && !showingStatus {
        if numCandidates == 0 || didCompose {
          panel.sectionNum = 0
        } else if currentIndex != nil {
          let currentPageNum: Int = currentIndex! / pageSize
          if !panel.isLocked && panel.isExpanded && panel.isFirstLine && pageNum == 0 && hilitedCandidate == 0 && currentIndex == 0 {
            panel.isExpanded = false
          } else if !panel.isLocked && !panel.isExpanded && pageNum > currentPageNum {
            panel.isExpanded = true
          }
          if panel.isExpanded && pageNum > currentPageNum && panel.sectionNum < (panel.isVertical ? 2 : 4) {
            panel.sectionNum = min(panel.sectionNum + pageNum - currentPageNum, (isLastPage ? 4 : 3) - (panel.isVertical ? 2 : 0))
          } else if panel.isExpanded && pageNum < currentPageNum && panel.sectionNum > 0 {
            panel.sectionNum = max(panel.sectionNum + pageNum - currentPageNum, pageNum == 0 ? 0 : 1)
          }
        }
        hilitedCandidate = hilitedCandidate == nil ? nil : hilitedCandidate! + pageSize * panel.sectionNum
      }
      let extraCandidates: Int = panel.isExpanded ? (isLastPage ? panel.sectionNum : (panel.isVertical ? 2 : 4)) * pageSize : 0
      let indexStart: Int = (pageNum - panel.sectionNum) * pageSize
      candidateIndices = indexStart ..< indexStart + numCandidates + extraCandidates
      currentIndex = hilitedCandidate == nil ? nil : hilitedCandidate! + indexStart

      if showingSwitcherMenu {
        if inlinePlaceholder { updateComposition() }
      } else if inlineCandidate {
        let candidatePreview: UnsafeMutablePointer<CChar>? = ctx.commit_text_preview
        var candidatePreviewText = candidatePreview == nil ? "" : String(cString: candidatePreview!)
        if inlinePreedit {
          if end <= caretPos && caretPos < length {
            candidatePreviewText += String(preeditText[String.Index(utf16Offset: caretPos, in: preeditText)...])
          }
          if !didCommit || !candidatePreviewText.isEmpty {
            showInlineString(candidatePreviewText, withSelRange: start ..< candidatePreviewText.utf16.count - (length - end), caretPos: caretPos < end ? caretPos : candidatePreviewText.utf16.count - (length - caretPos))
          }
        } else { // preedit includes the soft cursor
          if end < caretPos && caretPos <= length {
            let endIndex = String.Index(utf16Offset: candidatePreviewText.utf16.count - (caretPos - end), in: candidatePreviewText)
            candidatePreviewText = String(candidatePreviewText.utf16[..<endIndex])!
          } else if caretPos < end && end < length {
            let endIndex = String.Index(utf16Offset: candidatePreviewText.utf16.count - (length - end), in: candidatePreviewText)
            candidatePreviewText = String(candidatePreviewText.utf16[..<endIndex])!
          }
          if !didCommit || !candidatePreviewText.isEmpty {
            showInlineString(candidatePreviewText, withSelRange: start ..< candidatePreviewText.utf16.count, caretPos: caretPos < end ? caretPos : candidatePreviewText.utf16.count)
          }
        }
      } else {
        if inlinePreedit {
          if inlinePlaceholder && preeditText.isEmpty && numCandidates > 0 {
            showPlaceholder(kFullWidthSpace)
          } else if !didCommit || !preeditText.isEmpty {
            showInlineString(preeditText, withSelRange: start ..< end, caretPos: caretPos)
          }
        } else {
          if inlinePlaceholder && preedit != nil {
            showPlaceholder(kFullWidthSpace)
          } else if !didCommit || preedit != nil {
            showInlineString("", withSelRange: 0 ..< 0, caretPos: 0)
          }
        }
      }
      // cache candidates
      if didCompose || numCandidates == 0 {
        candidateTexts.removeAll()
        candidateComments.removeAll()
      }
      var index: Int = candidateTexts.count
      var endIndex: Int = pageSize * pageNum
      // cache candidates
      if index < endIndex {
        var iterator = RimeCandidateListIterator()
        if RimeApi.candidate_list_from_index(session, &iterator, CInt(index)) {
          while index < endIndex && RimeApi.candidate_list_next(&iterator) {
            updateCandidate(iterator.candidate, at: index)
            index += 1
          }
          RimeApi.candidate_list_end(&iterator)
        }
      }
      if index < pageSize * pageNum + numCandidates {
        for i in 0 ..< numCandidates {
          updateCandidate(ctx.menu.candidates[i], at: index)
          index += 1
        }
      }
      endIndex = candidateIndices.upperBound
      if index < endIndex {
        var iterator = RimeCandidateListIterator()
        if RimeApi.candidate_list_from_index(session, &iterator, CInt(index)) {
          while index < endIndex && RimeApi.candidate_list_next(&iterator) {
            updateCandidate(iterator.candidate, at: index)
            index += 1
          }
          RimeApi.candidate_list_end(&iterator)
          candidateIndices = candidateIndices.lowerBound ..< index
        }
      }
      // remove old candidates that were not overwritted, if any, subscripted from index
      updateCandidate(nil, at: index)

      showPanel(withPreedit: inlinePreedit && !showingSwitcherMenu ? "" : preeditText, selRange: NSRange(location: start, length: end - start), caretPos: showingSwitcherMenu ? nil : caretPos, candidateIndices: candidateIndices, highlightedCandidate: hilitedCandidate, pageNum: pageNum, isLastPage: isLastPage, didCompose: didCompose)
      _ = RimeApi.free_context(&ctx)
    }
  }

  private func updateCandidate(_ candidate: RimeCandidate?, at index: Int) {
    if candidate == nil || index > candidateTexts.count {
      if index < candidateTexts.count {
        let remove: Range<Int> = index ..< candidateTexts.count
        candidateTexts.removeSubrange(remove)
        candidateComments.removeSubrange(remove)
      }
      return
    }
    let text = String(cString: candidate!.text)
    let comment = candidate!.comment == nil ? "" : String(cString: candidate!.comment!)
    if index == candidateTexts.count {
      candidateTexts.append(text)
      candidateComments.append(comment)
    } else {
      if text != candidateTexts[index] {
        candidateTexts[index] = text
      }
      if comment != candidateComments[index] {
        candidateComments[index] = comment
      }
    }
  }
}  // SquirrelInputController

private func updateCapsLockLEDState(targetState: Bool) {
  let ioService: io_service_t = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(kIOHIDSystemClass))
  var ioConnect: io_connect_t = 0
  IOServiceOpen(ioService, mach_task_self_, UInt32(kIOHIDParamConnectType), &ioConnect)
  var currentState: Bool = false
  IOHIDGetModifierLockState(ioConnect, CInt(kIOHIDCapsLockState), &currentState)
  if currentState != targetState {
    IOHIDSetModifierLockState(ioConnect, CInt(kIOHIDCapsLockState), targetState)
  }
  IOServiceClose(ioConnect)
}

private func getOptionLabel(session: RimeSessionId, option: UnsafePointer<CChar>, state: Bool) -> String? {
  let labelShort: RimeStringSlice = RimeApi.get_state_label_abbreviated(session, option, state, true)
  if (labelShort.str != nil) && labelShort.length >= strlen(labelShort.str) {
    return String(cString: labelShort.str!)
  } else {
    let labelLong: RimeStringSlice = RimeApi.get_state_label_abbreviated(session, option, state, false)
    let label: String? = labelLong.str == nil ? nil : String(cString: labelLong.str!)
    return label == nil ? nil : String(label![label!.rangeOfComposedCharacterSequence(at: label!.startIndex)])
  }
}

@frozen enum SquirrelAction: Sendable {
  case PROCESS, SELECT, HIGHLIGHT, DELETE
}

enum SquirrelIndex: RawRepresentable, Sendable {
  // 0, 1, 2 ... are ordinal digits, used as (int) indices
  case Ordinal(Int)
  // 0xFFXX are rime keycodes (as function keys), for paging etc.
  case BackSpaceKey
  case EscapeKey
  case CodeInputArea
  case HomeKey
  case LeftKey
  case UpKey
  case RightKey
  case DownKey
  case PageUpKey
  case PageDownKey
  case EndKey
  case ExpandButton
  case CompressButton
  case LockButton
  case VoidSymbol

  init?(rawValue: Int) {
    switch rawValue {
    case 0x0 ... 0xFFF: self = .Ordinal(rawValue)
    case 0xFF08: self = .BackSpaceKey
    case 0xFF1B: self = .EscapeKey
    case 0xFF37: self = .CodeInputArea
    case 0xFF50: self = .HomeKey
    case 0xFF51: self = .LeftKey
    case 0xFF52: self = .UpKey
    case 0xFF53: self = .RightKey
    case 0xFF54: self = .DownKey
    case 0xFF55: self = .PageUpKey
    case 0xFF56: self = .PageDownKey
    case 0xFF57: self = .EndKey
    case 0xFF04: self = .ExpandButton
    case 0xFF05: self = .CompressButton
    case 0xFF06: self = .LockButton
    case 0xFFFFFF: self = .VoidSymbol
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case let .Ordinal(num): return num
    case .BackSpaceKey: return 0xFF08
    case .EscapeKey: return 0xFF1B
    case .CodeInputArea: return 0xFF37
    case .HomeKey: return 0xFF50
    case .LeftKey: return 0xFF51
    case .UpKey: return 0xFF52
    case .RightKey: return 0xFF53
    case .DownKey: return 0xFF54
    case .PageUpKey: return 0xFF55
    case .PageDownKey: return 0xFF56
    case .EndKey: return 0xFF57
    case .ExpandButton: return 0xFF04
    case .CompressButton: return 0xFF05
    case .LockButton: return 0xFF06
    case .VoidSymbol: return 0xFFFFFF
    }
  }

  @inlinable static func < (lhs: Self, rhs: Self) -> Bool { return lhs.rawValue < rhs.rawValue }
  @inlinable static func > (lhs: Self, rhs: Self) -> Bool { return lhs.rawValue > rhs.rawValue }
  @inlinable static func <= (lhs: Self, rhs: Self) -> Bool { return lhs.rawValue <= rhs.rawValue }
  @inlinable static func >= (lhs: Self, rhs: Self) -> Bool { return lhs.rawValue >= rhs.rawValue }
  @inlinable static func == (lhs: Self, rhs: Self) -> Bool { return lhs.rawValue == rhs.rawValue }
  @inlinable static func != (lhs: Self, rhs: Self) -> Bool { return lhs.rawValue != rhs.rawValue }
  @inlinable static func < (lhs: Self, rhs: Int) -> Bool { return lhs.rawValue < rhs }
  @inlinable static func > (lhs: Self, rhs: Int) -> Bool { return lhs.rawValue > rhs }
  @inlinable static func <= (lhs: Self, rhs: Int) -> Bool { return lhs.rawValue <= rhs }
  @inlinable static func >= (lhs: Self, rhs: Int) -> Bool { return lhs.rawValue >= rhs }
  @inlinable static func == (lhs: Self, rhs: Int!) -> Bool { return lhs.rawValue == (rhs ?? 0xFFFFFF) }
  @inlinable static func != (lhs: Self, rhs: Int!) -> Bool { return lhs.rawValue != (rhs ?? 0xFFFFFF) }
  static func + (lhs: Self, rhs: Int) -> Self {
    if lhs.rawValue >= 0x0 && lhs.rawValue <= 0xFFF {
      let result = lhs.rawValue + rhs
      if result >= 0x0 && result <= 0xFFF { return .Ordinal(result) }
    }
    return .VoidSymbol
  }
}  // SquirrelIndex

extension Bool {
  @inlinable static func |= (lhs: inout Bool, rhs: Bool) { lhs = lhs || rhs }
}
