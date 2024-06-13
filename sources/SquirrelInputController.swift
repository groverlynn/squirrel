import InputMethodKit
import IOKit

final class SquirrelInputController: IMKInputController {
  // class variables
  nonisolated(unsafe) static private(set) weak var current: SquirrelInputController?
  nonisolated(unsafe) static private var currentApp: String = ""
  nonisolated(unsafe) static private var asciiMode: Bool?
  nonisolated(unsafe) static var keyboardLayout: String?
  nonisolated(unsafe) static var goodOldCapsLock: Bool = false
  nonisolated(unsafe) static var chordDuration: TimeInterval = 0.1
  nonisolated(unsafe) static var isCurrentInputMethod: Bool = false
  // private
  private var inlineString: NSMutableAttributedString?
  private var originalString: String?
  private var composedString: String?
  private var schemaId: String = ""
  private var selSegment: Range<Int> = 0 ..< 0
  private var inlineSelRange: Range<Int> = 0 ..< 0
  private var inlineCaretPos: Int = 0
  private var converted: Int = 0
  private var currentIndex: Int?
  private var lastModifiers: NSEvent.ModifierFlags = []
  private var lastEventCount: CUnsignedInt = 0
  private var keyLayout: UnsafePointer<UCKeyboardLayout>?
  private var deadKeyState: UInt32 = 0
  private var inlinePreedit: Bool = false
  private var inlineCandidate: Bool = false
  private var showingSwitcherMenu: Bool = false
  private var showingInitialStatus: Bool = false
  private var hasStatusMessage: Bool { @MainActor get { SquirrelApp.delegate.panel.statusMessage != nil } }
  private var isVertical: Bool { SquirrelTheme.current.isVertical }
  private var isLinear: Bool { SquirrelTheme.current.isLinear }
  private var isTabular: Bool { SquirrelTheme.current.isTabular }
  private(set) var session: RimeSessionId = 0
  // app-specific options
  private var appOptions: SquirrelAppOptions = .init()
  private var inlinePlaceholder: Bool = false
  private var panellessCommitFix: Bool = false
  private var inlineOffset: Double = .zero
  // for chord-typing
  private var chordTimer: Timer?
  private var chordKeyCombos: [(keycode: RimeKeyCode, modifiers: RimeModifiers)] = []
  // contents and appearance
  private(set) var candidateTexts: [String] = []
  private(set) var candidateComments: [String] = []
  @available(macOS 10.14, *) private var style: SquirrelStyle {
    let clientAppearance: NSAppearance = client().perform(NSSelectorFromString("viewEffectiveAppearance"))?.takeUnretainedValue() as? NSAppearance ?? .current
    return clientAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }
  private var candidateIndices: Range<Int> = 0 ..< 0
  private var isVisible: Bool { @MainActor get { SquirrelApp.delegate.panel.isVisible } }
  private var isFirstLine: Bool { @MainActor get { SquirrelApp.delegate.panel.isFirstLine } }
  private var isLocked: Bool { @MainActor get { SquirrelApp.delegate.panel.isLocked } }
  private var isExpanded: Bool {
    @MainActor get { SquirrelApp.delegate.panel.isExpanded }
    set { MainActor.assumeIsolated { SquirrelApp.delegate.panel.isExpanded = newValue } }
  }
  private var sectionNum: Int {
    @MainActor get { SquirrelApp.delegate.panel.sectionNum }
    set { MainActor.assumeIsolated { SquirrelApp.delegate.panel.sectionNum = newValue } }
  }
  private var IbeamRect: NSRect {
    @MainActor get { SquirrelApp.delegate.panel.IbeamRect }
    set { MainActor.assumeIsolated { SquirrelApp.delegate.panel.IbeamRect = newValue } }
  }

  static private let keylayoutRegex: NSRegularExpression = try! .init(pattern: "\\w+(\\.\\w+){3,}")
  override func activateServer(_ sender: Any!) {
    // print("activateServer:")
    super.activateServer(sender)
    lastModifiers = []
    lastEventCount = 0
    candidateTexts = []
    candidateComments = []
    Self.current = self
    IbeamRect = .zero
    createSession()
    switch Self.keyboardLayout {
    case .none, "last", "": break
    case "default": client().overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
    case let k?: client().overrideKeyboard(withKeyboardNamed: Self.keylayoutRegex.numberOfMatches(in: k, range: NSRange(location: 0, length: k.length)) > 0 ? k : "com.apple.keylayout." + k)
    }
    let uchr: CFData = bridge(ptr: TISGetInputSourceProperty(TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue(), kTISPropertyUnicodeKeyLayoutData), as: CFData.self)
    keyLayout = Data(referencing: uchr).withUnsafeBytes { $0.bindMemory(to: UCKeyboardLayout.self).baseAddress }

    if !Self.isCurrentInputMethod {
      Self.isCurrentInputMethod = true
      if SquirrelApp.delegate.showNotifications == .always {
        showInitialStatus()
      }
    }
  }

  override func deactivateServer(_ sender: Any!) {
    // print("deactivateServer:")
    let asciiMode: Bool = RimeApi.get_option(session, "ascii_mode")
    Self.asciiMode = asciiMode
    commitComposition(sender)
    destroySession()
    super.deactivateServer(sender)
  }

  override func recognizedEvents(_ sender: Any!) -> Int {
    return Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged, .leftMouseDown]).rawValue)
  }

/** - Receive incoming event:
      - Return `true` to indicate the the key input was received and dealt with.
        Key processing will not continue in that case. In other words,
        the system will not deliver a key-down event to the application.
      - Returning `false` means the original key down will be passed on to the client. */
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    autoreleasepool {
      guard let event = event else { return false }
      if session == 0 || !RimeApi.find_session(session) {
        createSession()
        if session == 0 { return false }
      }
      var handled: Bool = false
      let modifiers: NSEvent.ModifierFlags = event.modifierFlags
      var rimeModifiers: RimeModifiers = .init(macModifiers: modifiers)

      switch event.type {
      case .flagsChanged:
        guard lastModifiers != modifiers else { return true }
        // print("FLAGSCHANGED client: \(sender!), modifiers: 0x\(modifiers.rawValue)")
        let keyCode: Int = Int(event.cgEvent!.getIntegerValueField(.keyboardEventKeycode))
        let rimeKeycode: RimeKeyCode = .init(macKeyCode: keyCode)
        let eventCountTypes: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let eventCount: CUnsignedInt = eventCountTypes.map({ CGEventSource.counterForEventType(.combinedSessionState, eventType: $0) }).reduce(0, +)
        lastModifiers = modifiers
        switch keyCode {
        case kVK_CapsLock:
          if !Self.goodOldCapsLock {
            updateCapsLockLEDState(targetState: false)
            if RimeApi.get_option(session, "ascii_mode") {
              rimeModifiers.insert(.Lock)
            } else {
              rimeModifiers.remove(.Lock)
            }
          } else {
            rimeModifiers.formSymmetricDifference(.Lock)
            if #available(macOS 14.0, *) {  // avoid overlapping with capslock accessory view
              IbeamRect = .zero
            }
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
          if modifiers == .option, MainActor.assumeIsolated({ SquirrelApp.delegate.panel.showToolTip() }) {
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
        if handled || hasStatusMessage {
          rimeUpdate()
          handled |= true
        }
        lastEventCount = eventCount
      case .keyDown:
        if deadKeyState != 0 || server().lastKeyEventWasDeadKey() {
          if !(composedString?.isEmpty ?? true) { commitComposition(sender) }
          var length: Int = 0
          let string: UnsafeMutablePointer<unichar> = UnsafeMutablePointer<unichar>.allocate(capacity: 8)
          var status: OSStatus = UCKeyTranslate(keyLayout, event.keyCode, UInt16(kUCKeyActionDown), EventModifiers(macModifiers: modifiers).rawValue, UInt32(LMGetKbdType()), 0, &deadKeyState, 8, &length, string)
          if length == 0 && deadKeyState != 0 {
            var state: UInt32 = deadKeyState
            status = UCKeyTranslate(keyLayout, event.keyCode, UInt16(kUCKeyActionDown), EventModifiers(macModifiers: modifiers).rawValue, UInt32(LMGetKbdType()), 0, &state, 8, &length, string)
            if length > 0 && status == noErr {
              showInlineString(String(utf16CodeUnits: string, count: length), withSelRange: 0 ..< length, caretPos: length)
            }
          } else if length > 0 && status == noErr {
            commitString(String(utf16CodeUnits: string, count: length))
            deadKeyState = 0
          }
          return true
        }
        let keyCode: Int = Int(event.keyCode)
        // print("KEYDOWN client: \(sender), modifiers: \(modifiers), keyCode: \(keyCode)")
        // translate osx keyevents to rime keyevents
        var rimeKeyCode: RimeKeyCode = .init(macKeyCode: keyCode)
        if rimeKeyCode == .XK_VoidSymbol {
          let keyChars: String = modifiers.contains(.shift) && modifiers.isDisjoint(with: [.control, .option]) ? event.characters! : event.charactersIgnoringModifiers!
          rimeKeyCode = RimeKeyCode(keychar: keyChars[0], shift: modifiers.contains(.shift), caps: modifiers.contains(.capsLock))
        } else if Set<Int>(0x60 ... 0xFF).union([0x40, 0x47, 0x4F, 0x50]).contains(keyCode) {
          // revert non-modifier function keys' FunctionKeyMask (FwdDel, Navigations, F1..F19)
          rimeModifiers.remove(.Hyper)
        }
        if rimeKeyCode != .XK_VoidSymbol {
          handled = processKey(rimeKeyCode, modifiers: rimeModifiers)
          if handled {
            rimeUpdate()
          } else if panellessCommitFix, client().markedRange().length > 0 {
            if Set<RimeKeyCode>(.XK_Home ... .XK_KP_Delete).union(.XK_BackSpace ... .XK_Escape).union([.XK_Delete]).contains(rimeKeyCode) {
              showPlaceholder("")
            } else if modifiers.isDisjoint(with: [.control, .command]), !event.characters!.isEmpty {
              showPlaceholder(nil)
              client().insertText(event.characters, replacementRange: NSRange(location: NSNotFound, length: 0))
              return true
            }
          } else if !(composedString?.isEmpty ?? true) {
            commitComposition(sender)
            return false
          }
        }
      default: break
      }
      return handled
    }
  }

  private func updateCapsLockLEDState(targetState: Bool) {
    let ioService: IOAlignment = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(kIOHIDSystemClass))
    var ioConnect: IOAlignment = 0
    IOServiceOpen(ioService, mach_host_self(), CUnsignedInt(kIOHIDParamConnectType), &ioConnect)
    var currentState: Bool = false
    IOHIDGetModifierLockState(ioConnect, CInt(kIOHIDCapsLockState), &currentState)
    if currentState != targetState {
      IOHIDSetModifierLockState(ioConnect, CInt(kIOHIDCapsLockState), targetState)
    }
    IOServiceClose(ioConnect)
  }

  override func mouseDown(onCharacterIndex index: Int, coordinate point: NSPoint, withModifier flags: Int, continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!, client sender: Any!) -> Bool {
    keepTracking.pointee = false
    guard inlinePreedit || inlineCandidate, let composedString = composedString, !composedString.isEmpty, inlineCaretPos != index, NSEvent.ModifierFlags.KeyEventFlags(flags).isEmpty else { return false }
    let markedRange: NSRange = client().markedRange()
    let head: NSPoint = client().attributes(forCharacterIndex: 0, lineHeightRectangle: nil)["IMKBaseline"] as! NSPoint
    let tail: NSPoint = client().attributes(forCharacterIndex: markedRange.length - 1, lineHeightRectangle: nil)["IMKBaseline"] as! NSPoint
    if point.x > tail.x.nextUp || index >= markedRange.length {
      if inlineCandidate, !inlinePreedit { return false }
      perform(action: .Process, onIndex: .EndKey)
    } else if point.x < head.x.nextDown || index <= 0 {
      perform(action: .Process, onIndex: .HomeKey)
    } else {
      moveCursor(inlineCaretPos, to: index, inlinePreedit: inlinePreedit, inlineCandidate: inlineCandidate)
    }
    return true
  }

  private func processKey(_ keycode: RimeKeyCode, modifiers: RimeModifiers) -> Bool {
    let isNavigatorInTabular: Bool = isTabular && modifiers.isEmpty && isVisible && (isVertical ? Set([.XK_Left, .XK_KP_Left, .XK_Right, .XK_KP_Right]).contains(keycode) : Set([.XK_Up, .XK_KP_Up, .XK_Down, .XK_KP_Down]).contains(keycode))
    if isNavigatorInTabular {
      var keycode: RimeKeyCode = keycode
      if .XK_KP_Left ... .XK_KP_Down ~= keycode {
        keycode = keycode - .XK_KP_Left + .XK_Left
      }
      if let newIndex: Int = MainActor.assumeIsolated({ SquirrelApp.delegate.panel.candidateIndex(onDirection: SquirrelIndex(keycode)!) }) {
        if !isLocked, !isExpanded, keycode == (isVertical ? .XK_Left : .XK_Down) {
          isExpanded = true
        }
        _ = RimeApi.highlight_candidate(session, newIndex)
        return true
      } else if !isLocked, isExpanded, sectionNum == 0, keycode == (isVertical ? .XK_Right : .XK_Up) {
        isExpanded = false
        return true
      }
    }

    let handled: Bool = RimeApi.process_key(session, keycode.rawValue, modifiers.rawValue)
    // print("rime_keycode: \(rime_keycode), rime_modifiers: \(rime_modifiers), handled = \(handled)")
    if !handled {
      let isVimBackInCommandMode: Bool = keycode == .XK_Escape || (modifiers.contains(.Control) && Set([.XK_c, .XK_C, .XK_bracketleft]).contains(keycode))
      if isVimBackInCommandMode, RimeApi.get_option(session, "vim_mode"), !RimeApi.get_option(session, "ascii_mode") {
        cancelComposition()
        RimeApi.set_option(session, "ascii_mode", true)
        // print("turned Chinese mode off in vim-like editor's command mode")
        return true
      }
    }

    // Simulate key-ups for every interesting key-down for chord-typing.
    if handled {
      let isChordingKey: Bool = Set<RimeKeyCode>(.XK_space ... .XK_asciitilde).union([.XK_Control_L, .XK_Control_R, .XK_Alt_L, .XK_Alt_R, .XK_Shift_L, .XK_Shift_R]).contains(keycode)
      if isChordingKey, RimeApi.get_option(session, "_chord_typing") {
        updateChord(keycode, modifiers: modifiers)
      } else if modifiers.isDisjoint(with: .Release) { // non-chording key pressed
        clearChord()
      }
    }

    return handled
  }

  func moveCursor(_ cursorPosition: Int, to targetPosition: Int, inlinePreedit: Bool, inlineCandidate: Bool) {
    autoreleasepool {
      let composition: String = !inlinePreedit && !inlineCandidate ? composedString! : inlineString!.string
      var ctx: RimeContext_stdbool = RimeStructInit()
      if cursorPosition > targetPosition {
        let targetPrefix: String = composition[..<targetPosition].replacingOccurrences(of: " ", with: "")
        var prefix: String = composition[..<cursorPosition].replacingOccurrences(of: " ", with: "")

        let noneConverted: Bool = originalString!.hasSuffix(composition[targetPosition...].replacingOccurrences(of: " ", with: ""))
        while targetPrefix.length < prefix.length {
          let byChar: Bool = noneConverted && !prefix[targetPrefix.length...].contains(" ")
          _ = RimeApi.process_key(session, isVertical ? (byChar ? RimeKeyCode.XK_KP_Up.rawValue : RimeKeyCode.XK_Up.rawValue) : (byChar ? RimeKeyCode.XK_KP_Left.rawValue : RimeKeyCode.XK_Left.rawValue), 0)
          _ = RimeApi.get_context(session, &ctx)
          if inlineCandidate {
            let length: CInt = ctx.composition.cursor_pos < ctx.composition.sel_end ? ctx.composition.cursor_pos : CInt(strlen(ctx.commit_text_preview)) - (inlinePreedit ? 0 : ctx.composition.cursor_pos - ctx.composition.sel_end)
            prefix = ctx.commit_text_preview == nil ? "" : String(cString: ctx.commit_text_preview)[..<length].replacingOccurrences(of: " ", with: "")
          } else {
            prefix = ctx.composition.preedit == nil ? "" : String(cString: ctx.composition.preedit)[..<ctx.composition.cursor_pos].replacingOccurrences(of: " ", with: "")
          }
          _ = RimeApi.free_context(&ctx)
        }
      } else if cursorPosition < targetPosition {
        let targetSuffix: String = composition[targetPosition...].replacingOccurrences(of: " ", with: "")
        var suffix: String = composition[cursorPosition...].replacingOccurrences(of: " ", with: "")
        while targetSuffix.length < suffix.length {
          _ = RimeApi.process_key(session, isVertical ? RimeKeyCode.XK_Down.rawValue : RimeKeyCode.XK_Right.rawValue, 0)
          _ = RimeApi.get_context(session, &ctx)
          suffix = ctx.composition.preedit == nil ? "" : String(cString: ctx.composition.preedit + Int(ctx.composition.cursor_pos) + (!inlinePreedit && !inlineCandidate ? 3 : 0)).replacingOccurrences(of: " ", with: "")
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
    case .Process:
      switch index {
      case .BackSpaceKey ... .EndKey: handled = RimeApi.process_key(session, CInt(index.rawValue), 0)
      case .ExpandButton ... .LockButton: handled = true; currentIndex = nil
      default: break
      }
    case .Select: handled = RimeApi.select_candidate(session, index.rawValue)
    case .Highlight: handled = RimeApi.highlight_candidate(session, index.rawValue); currentIndex = nil
    case .Delete: handled = RimeApi.delete_candidate(session, index.rawValue)
    }
    if handled { rimeUpdate() }
  }

  private func updateChord(_ keycode: RimeKeyCode, modifiers: RimeModifiers) {
    // print("update chord: {\(_chord)} << \(keycode)")
    guard !chordKeyCombos.contains(where: { $0.keycode == keycode }), chordKeyCombos.count < 50 else { return }  // you are cheating. only one human typist (fingers <= 10) is supported.
    chordKeyCombos.append((keycode: keycode, modifiers: modifiers))
    // reset timer
    chordTimer?.invalidate()
    chordTimer = .scheduledTimer(timeInterval: Self.chordDuration, target: self, selector: #selector(onChordTimer(_:)), userInfo: nil, repeats: false)
  }

  @objc private func onChordTimer(_ timer: Timer) {
    // chord release triggered by timer
    guard !chordKeyCombos.isEmpty, session != 0 else { return }
    if !chordKeyCombos.filter({ RimeApi.process_key(session, $0.keycode.rawValue, $0.modifiers.union(.Release).rawValue) }).isEmpty {
      rimeUpdate()
    }
    chordKeyCombos = []
  }

  private func clearChord() {
    chordKeyCombos = []
    chordTimer?.invalidate()
  }

  private func showInitialStatus() {
    var status: RimeStatus_stdbool = RimeStructInit()
    guard session != 0, RimeApi.get_status(session, &status) else { return }
    let schemaName: String = .init(cString: status.schema_name ?? status.schema_id)
    var options: [String] = []
    if let asciiMode: String = getLabel(option: "ascii_mode", state: status.is_ascii_mode) {
      options.append(asciiMode)
    }
    if let fullShape: String = getLabel(option: "full_shape", state: status.is_full_shape) {
      options.append(fullShape)
    }
    if let asciiPunct: String = getLabel(option: "ascii_punct", state: status.is_ascii_punct) {
      options.append(asciiPunct)
    }
    _ = RimeApi.free_status(&status)
    let foldedOptions: String = options.isEmpty ? schemaName : schemaName + " ￨ " + options.joined(separator: " ")

    MainActor.assumeIsolated { SquirrelApp.delegate.panel.updateStatus(long: foldedOptions, short: schemaName) }
    if #available(macOS 14.0, *) { showingInitialStatus = true }
    rimeUpdate()
  }

  private func getLabel(option: UnsafePointer<CChar>, state: Bool) -> String? {
    let labelShort: RimeStringSlice = RimeApi.get_state_label_abbreviated(session, option, state, true)
    if labelShort.str != nil, labelShort.length >= strlen(labelShort.str) {
      return String(cString: labelShort.str)
    } else {
      let labelLong: RimeStringSlice = RimeApi.get_state_label_abbreviated(session, option, state, false)
      let label: String? = labelLong.str == nil ? nil : String(cString: labelLong.str)
      return label == nil ? nil : String(label!.first!)
    }
  }

  override func commitComposition(_ sender: Any!) {
    // print("commitComposition:")
    if session != 0 {
      _ = RimeApi.commit_composition(session)
      var commit: RimeCommit = RimeStructInit()
      if RimeApi.get_commit(session, &commit) {
        commitString(String(cString: commit.text))
      }
      _ = RimeApi.free_commit(&commit)
    }
    hidePalettes()
  }

  private func clearBuffer() {
    IbeamRect = .zero
    inlineString = nil
    originalString = nil
    composedString = nil
    deadKeyState = 0
  }

  // Though we specify AppDelegate as the menu action receiver, Inputcontroller
  // is the one that actually receives the event. Here we relay these messages.
  @objc private func showSwitcher(_ sender: Any?) {
    SquirrelApp.delegate.showSwitcher(session)
    rimeUpdate()
  }

  @objc private func deploy(_ sender: Any?) {
    SquirrelApp.delegate.deploy(sender)
  }

  @objc private func syncUserData(_ sender: Any?) {
    SquirrelApp.delegate.syncUserData(sender)
  }

  @objc private func configure(_ sender: Any?) {
    SquirrelApp.delegate.configure(sender)
  }

  @objc private func openWiki(_ sender: Any?) {
    SquirrelApp.delegate.openWiki(sender)
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    SquirrelApp.delegate.checkForUpdates(sender)
  }

  @objc private func openLogFolder(_ sender: Any?) {
    SquirrelApp.delegate.openLogFolder(sender)
  }

  override func menu() -> NSMenu {
    return SquirrelApp.delegate.menu
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
    MainActor.assumeIsolated { SquirrelApp.delegate.panel.hide() }
    super.hidePalettes()
  }

  override func selectionRange() -> NSRange { return .init(location: inlineCaretPos, length: 0) }

  override func replacementRange() -> NSRange { return .init(location: NSNotFound, length: 0) }

  private func commitString(_ string: Any!) {
    // print("commitString:")
    client().insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
    clearBuffer()
  }

  override func cancelComposition() {
    commitString(originalString)
    hidePalettes()
    if session != 0 { RimeApi.clear_composition(session) }
  }

  override func updateComposition() {
    client().setMarkedText(inlineString ?? "", selectionRange: NSRange(location: inlineCaretPos, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  private func showPlaceholder(_ placeholder: String?) {
    let attrs: [NSAttributedString.Key : Any] = mark(forStyle: kTSMHiliteSelectedRawText, at: NSRange(location: 0, length: placeholder?.length ?? 1)) as! [NSAttributedString.Key : Any]
    inlineString = NSMutableAttributedString(string: placeholder ?? "█", attributes: attrs)
    inlineCaretPos = 0
    updateComposition()
  }

  private func showInlineString(_ string: String, withSelRange selRange: Range<Int>, caretPos: Int) {
    // print("showPreeditString: '\(preedit)'")
    if caretPos == inlineCaretPos, selRange == inlineSelRange, string == inlineString?.string { return }
    inlineSelRange = selRange
    inlineCaretPos = caretPos
    // print("selRange = \(selRange), caretPos = \(caretPos)")
    let attrs: [NSAttributedString.Key : Any] = mark(forStyle: kTSMHiliteRawText, at: NSRange(location: 0, length: string.length)) as! [NSAttributedString.Key : Any]
    inlineString = NSMutableAttributedString(string: string, attributes: attrs)
    if selRange.lowerBound > 0 {
      inlineString?.addAttributes(mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: selRange.lowerBound)) as! [NSAttributedString.Key : Any], range: NSRange(location: 0, length: selRange.lowerBound))
    }
    if selRange.lowerBound < caretPos {
      inlineString?.addAttributes(mark(forStyle: kTSMHiliteSelectedRawText, at: NSRange(selRange)) as! [NSAttributedString.Key : Any], range: NSRange(selRange))
    }
    updateComposition()
  }

  private func showPanel(withPreedit preedit: String, selRange: NSRange, caretPos: Int?, candidateIndices: Range<Int>, highlightedCandidate: Int?, pageNum: Int, isLastPage: Bool, didCompose: Bool) {
    // print("showPanelWithPreedit:...:")
    if IbeamRect == .zero {
      var Ibeam: NSRect = .zero
      if inlinePreedit || inlineCandidate || inlinePlaceholder || client().selectedRange().length > 0 {
        client().attributes(forCharacterIndex: 0, lineHeightRectangle: &Ibeam)
      }
      if Ibeam.isEmpty {
        let selectedRange: NSRange = client().selectedRange()
        if selectedRange.length == 0 {
          // activate inline session, in e.g. table cells, by fake inputs
          showPlaceholder(" ")
          client().attributes(forCharacterIndex: 0, lineHeightRectangle: &Ibeam)
          showPlaceholder("")
        } else {
          Ibeam = client().firstRect(forCharacterRange: NSRange(location: selectedRange.location, length: 1), actualRange: nil)
        }
      }
      let sweepVertical: Bool = Ibeam.width > Ibeam.height
      if inlineOffset.isNormal {
        Ibeam = Ibeam.offsetBy(dx: sweepVertical ? inlineOffset : .zero, dy: sweepVertical ? .zero : inlineOffset)
      }
      // avoid overlapping with cursor effects view
      if #available(macOS 14.0, *), (Self.goodOldCapsLock && lastModifiers.contains(.capsLock)) || (showingInitialStatus && preedit.isEmpty && candidateIndices.isEmpty) {
        let screenRect: NSRect = NSScreen.main!.visibleFrame
        var capslockAccessory: NSRect = sweepVertical ? .init(x: Ibeam.minX - 30, y: Ibeam.minY, width: 27, height: Ibeam.height) : .init(x: Ibeam.minX, y: Ibeam.minY - 26, width: Ibeam.width, height: 23)
        if sweepVertical {
          if capslockAccessory.minX < screenRect.minX.nextUp {
            capslockAccessory.origin.x = screenRect.minX
          }
          if capslockAccessory.maxX > screenRect.maxX.nextDown {
            capslockAccessory.origin.x = screenRect.maxX - capslockAccessory.width
          }
        } else {
          if capslockAccessory.minY < screenRect.minY.nextUp {
            capslockAccessory.origin.y = screenRect.maxY + 3
          }
          if capslockAccessory.maxY > screenRect.maxY.nextDown {
            capslockAccessory.origin.y = screenRect.maxY - capslockAccessory.height
          }
        }
        Ibeam = Ibeam.union(capslockAccessory)
      }
      IbeamRect = Ibeam
      if #available(macOS 10.14, *) {
        let newStyle = style
        MainActor.assumeIsolated { SquirrelApp.delegate.panel.style = newStyle }
      }
    }
    self.candidateIndices = candidateIndices
    MainActor.assumeIsolated { SquirrelApp.delegate.panel.showPanel(withPreedit: preedit, selRange: selRange, caretPos: caretPos, candidateIndices: candidateIndices, highlightedCandidate: highlightedCandidate, pageNum: pageNum, isLastPage: isLastPage, didCompose: didCompose) }
    if #available(macOS 14.0, *), showingInitialStatus {
      IbeamRect = .zero
      showingInitialStatus = false
    }
  }

  // MARK: Functions communicating with Rime

  func createSession() {
    let app: String = client().bundleIdentifier()
    // print("createSession: \(app)")
    schemaId = MainActor.assumeIsolated({ SquirrelApp.delegate.panel.optionSwitcher.schemaId })
    session = RimeApi.create_session()
    guard session != 0 else { return }
    // retrieve app-specific options
    let config: SquirrelConfig = .init(.base)
    appOptions = config.appOptions(for: app)
    config.close()
    RimeApi.set_option(session, "_linear", isLinear)
    RimeApi.set_option(session, "_vertical", isVertical)

    inlinePreedit = (SquirrelTheme.current.inlinePreedit && !appOptions["no_inline"]) || appOptions["inline"]
    inlineCandidate = SquirrelTheme.current.inlineCandidate && !appOptions["no_inline"]
    RimeApi.set_option(session, "soft_cursor", !inlinePreedit)
    panellessCommitFix = appOptions["panelless_commit_fix"]
    inlinePlaceholder = appOptions["inline_placeholder"]
    inlineOffset = appOptions["inline_offset"]
    // restore ascii mode if client app has not changed

    if app == Self.currentApp, let asciiMode = Self.asciiMode, asciiMode != RimeApi.get_option(session, "ascii_mode") {
      RimeApi.set_option(session, "ascii_mode", asciiMode)
    }
    Self.currentApp = app
    Self.asciiMode = nil
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
    guard RimeApi.get_commit(session, &commit) else { return false }
    let commitText: String = .init(cString: commit.text)
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

  private func rimeUpdate() {
    // print("rimeUpdate")
    let didCommit: Bool = rimeConsumeCommittedText()
    var didCompose: Bool = didCommit

    var status: RimeStatus_stdbool = RimeStructInit()
    if RimeApi.get_status(session, &status) {
      // enable schema specific ui style
      if strcmp(schemaId, status.schema_id) != 0 {
        schemaId = String(cString: status.schema_id)
        showingSwitcherMenu = RimeApi.get_option(session, "dumb")
        if !showingSwitcherMenu {
          SquirrelApp.delegate.loadSchemaSpecificLabels(schemaId: schemaId)
          SquirrelApp.delegate.loadSchemaSpecificSettings(schemaId: schemaId)
          // with linear candidate list, arrow keys may behave differently.
          if isLinear != RimeApi.get_option(session, "_linear") {
            RimeApi.set_option(session, "_linear", isLinear)
          }
          // with vertical text, arrow keys may behave differently.
          if isVertical != RimeApi.get_option(session, "_vertical") {
            RimeApi.set_option(session, "_vertical", isVertical)
          }
          // inline preedit
          inlinePreedit = (SquirrelTheme.current.inlinePreedit && !appOptions["no_inline"]) || appOptions["inline"]
          inlineCandidate = SquirrelTheme.current.inlineCandidate && !appOptions["no_inline"]
          // if not inline, embed soft cursor in preedit string
          RimeApi.set_option(session, "soft_cursor", !inlinePreedit)
        } else {
          SquirrelApp.delegate.loadSchemaSpecificLabels(schemaId: "")
        }
        didCompose = true
      }
      _ = RimeApi.free_status(&status)
    }

    var ctx: RimeContext_stdbool = RimeStructInit()
    if RimeApi.get_context(session, &ctx) {
      // update preedit text
      let preedit: UnsafeMutablePointer<CChar>! = ctx.composition.preedit
      let preeditText: String = preedit == nil ? "" : String(cString: preedit)

      // update raw input
      let raw_input: UnsafePointer<CChar>? = RimeApi.get_input(session)
      let originalString: String = raw_input == nil ? "" : String(cString: raw_input!)
      didCompose |= originalString != self.originalString
      self.originalString = originalString

      // update composed string
      if preedit == nil || showingSwitcherMenu {
        composedString = ""
      } else if !inlinePreedit { // remove soft cursor
        composedString = preeditText[..<ctx.composition.cursor_pos] + preeditText[(ctx.composition.cursor_pos + 3)...]
      } else {
        composedString = preeditText
      }

      let start: Int = preeditText.UniCharIndex(CCharIndex: ctx.composition.sel_start)
      let end: Int = preeditText.UniCharIndex(CCharIndex: ctx.composition.sel_end)
      let caretPos: Int = preeditText.UniCharIndex(CCharIndex: ctx.composition.cursor_pos)
      let length: Int = preeditText.UniCharIndex(CCharIndex: ctx.composition.length)
      let numCandidates: Int = Int(ctx.menu.num_candidates)
      let pageNum: Int = Int(ctx.menu.page_no)
      let pageSize: Int = Int(ctx.menu.page_size)
      var hilitedCandidate: Int? = numCandidates == 0 ? nil : Int(ctx.menu.highlighted_candidate_index)
      let isLastPage: Bool = ctx.menu.is_last_page

      // selected segment, with locations in terms of raw input
      var suffixLength: Int = preeditText[start...].replacingOccurrences(of: " ", with: "").length
      let selLength: Int = preeditText[start ..< end].replacingOccurrences(of: " ", with: "").length
      if !inlinePreedit, end ..< length ~= caretPos { // subtract length of soft cursor
        suffixLength -= 1
      }
      let selSegment: Range<Int> = self.originalString == nil ? 0 ..< 0 : (self.originalString!.length - suffixLength - selLength) ..< (self.originalString!.length - suffixLength)
      didCompose |= selSegment.lowerBound != self.selSegment.lowerBound || (selSegment.count != self.selSegment.count && hilitedCandidate == 0 && pageNum == 0)
      self.selSegment = selSegment
      // update `expanded` and `sectionNum` variables in tabular layout
      // already processed the action if `currentIndex` == nil
      if isTabular, !hasStatusMessage {
        if numCandidates == 0 || didCompose {
          sectionNum = 0
        } else if currentIndex != nil {
          let currentPageNum: Int = currentIndex! / pageSize
          if !isLocked, isExpanded, isFirstLine, pageNum == 0, hilitedCandidate == 0, currentIndex == 0 {
            isExpanded = false
          } else if !isLocked, !isExpanded, pageNum > currentPageNum {
            isExpanded = true
          }
          if isExpanded, pageNum > currentPageNum, sectionNum < (isVertical ? 2 : 4) {
            sectionNum = min(sectionNum + pageNum - currentPageNum, (isLastPage ? 4 : 3) - (isVertical ? 2 : 0))
          } else if isExpanded, pageNum < currentPageNum, sectionNum > 0 {
            sectionNum = max(sectionNum + pageNum - currentPageNum, pageNum == 0 ? 0 : 1)
          }
        }
        hilitedCandidate? += pageSize * sectionNum
      }
      let extraCandidates: Int = isExpanded ? (isLastPage ? sectionNum : (isVertical ? 2 : 4)) * pageSize : 0
      let indexStart: Int = (pageNum - sectionNum) * pageSize
      var indexRange: Range<Int> = indexStart ..< indexStart + numCandidates + extraCandidates
      currentIndex = hilitedCandidate == nil ? nil : hilitedCandidate! + indexStart

      if showingSwitcherMenu {
        if inlinePlaceholder { updateComposition() }
      } else if inlineCandidate {
        let candidatePreview: UnsafeMutablePointer<CChar>! = ctx.commit_text_preview
        var candidatePreviewText: String = candidatePreview == nil ? "" : String(cString: candidatePreview)
        if inlinePreedit {
          if end <= caretPos, caretPos < length {
            candidatePreviewText += preeditText[caretPos...]
          }
          if !didCommit || !candidatePreviewText.isEmpty {
            showInlineString(candidatePreviewText, withSelRange: start ..< candidatePreviewText.length - (length - end), caretPos: caretPos < end ? caretPos : candidatePreviewText.length - (length - caretPos))
          }
        } else { // preedit includes the soft cursor
          if end < caretPos, caretPos <= length {
            candidatePreviewText = candidatePreviewText[..<(candidatePreviewText.length - (caretPos - end))]
          } else if caretPos < end, end < length {
            candidatePreviewText = candidatePreviewText[..<(candidatePreviewText.length - (length - end))]
          }
          if !didCommit || !candidatePreviewText.isEmpty {
            showInlineString(candidatePreviewText, withSelRange: start ..< candidatePreviewText.length, caretPos: caretPos < end ? caretPos : candidatePreviewText.length)
          }
        }
      } else {
        if inlinePreedit {
          if inlinePlaceholder, preeditText.isEmpty, numCandidates > 0 {
            showPlaceholder(.fullWidthSpace)
          } else if !didCommit || !preeditText.isEmpty {
            showInlineString(preeditText, withSelRange: start ..< end, caretPos: caretPos)
          }
        } else {
          if inlinePlaceholder, preedit != nil {
            showPlaceholder(.fullWidthSpace)
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
        var iterator: RimeCandidateListIterator = .init()
        if RimeApi.candidate_list_from_index(session, &iterator, CInt(index)) {
          while index < endIndex, RimeApi.candidate_list_next(&iterator) {
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
      endIndex = indexRange.upperBound
      if index < endIndex {
        var iterator: RimeCandidateListIterator = .init()
        if RimeApi.candidate_list_from_index(session, &iterator, CInt(index)) {
          while index < endIndex, RimeApi.candidate_list_next(&iterator) {
            updateCandidate(iterator.candidate, at: index)
            index += 1
          }
          RimeApi.candidate_list_end(&iterator)
          indexRange = indexRange.lowerBound ..< index
        }
      }
      // remove old candidates that were not overwritted, if any, subscripted from index
      updateCandidate(nil, at: index)

      showPanel(withPreedit: inlinePreedit && !showingSwitcherMenu ? "" : preeditText, selRange: NSRange(location: start, length: end - start), caretPos: showingSwitcherMenu ? nil : caretPos, candidateIndices: indexRange, highlightedCandidate: hilitedCandidate, pageNum: pageNum, isLastPage: isLastPage, didCompose: didCompose)
      _ = RimeApi.free_context(&ctx)
    }
  }

  private func updateCandidate(_ candidate: RimeCandidate?, at index: Int) {
    switch (candidate, index) {
    case (let candidate?, candidateTexts.count):
      candidateTexts.append(String(cString: candidate.text))
      candidateComments.append(candidate.comment == nil ? "" : String(cString: candidate.comment))
    case (let candidate?, 0 ..< candidateTexts.count):
      if strcmp(candidate.text, candidateTexts[index]) != 0 {
        candidateTexts[index] = String(cString: candidate.text)
      }
      if strcmp(candidate.comment, candidateComments[index]) != 0 {
        candidateComments[index] = candidate.comment == nil ? "" : String(cString: candidate.comment)
      }
    case (.none, 0 ... candidateTexts.count):
      candidateTexts.removeSubrange(index...)
      candidateComments.removeSubrange(index...)
    default: break
    }
  }
}  // SquirrelInputController

extension NSEvent.ModifierFlags {
  static func KeyEventFlags(_ flags: Int) -> Self { .init(rawValue: UInt(flags)).intersection(.deviceIndependentFlagsMask) }
}

enum SquirrelAction: Sendable {
  case Process, Select, Highlight, Delete
}

enum SquirrelIndex: RawRepresentable, Sendable, Strideable, Hashable {
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

  init?(_ keyCode: RimeKeyCode) {
    self.init(rawValue: Int(keyCode.rawValue))
  }

  var rawValue: Int {
    return switch self {
    case .Ordinal(let num): num
    case .BackSpaceKey: 0xFF08
    case .EscapeKey: 0xFF1B
    case .CodeInputArea: 0xFF37
    case .HomeKey: 0xFF50
    case .LeftKey: 0xFF51
    case .UpKey: 0xFF52
    case .RightKey: 0xFF53
    case .DownKey: 0xFF54
    case .PageUpKey: 0xFF55
    case .PageDownKey: 0xFF56
    case .EndKey: 0xFF57
    case .ExpandButton: 0xFF04
    case .CompressButton: 0xFF05
    case .LockButton: 0xFF06
    case .VoidSymbol: 0xFFFFFF
    }
  }
  var isOrdinal: Bool { 0x0 ... 0xFFF ~= rawValue }

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  static func > (lhs: Self, rhs: Self) -> Bool { lhs.rawValue > rhs.rawValue }
  static func <= (lhs: Self, rhs: Self) -> Bool { lhs.rawValue <= rhs.rawValue }
  static func >= (lhs: Self, rhs: Self) -> Bool { lhs.rawValue >= rhs.rawValue }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
  static func != (lhs: Self, rhs: Self) -> Bool { lhs.rawValue != rhs.rawValue }
  static func < (lhs: Self, rhs: Int) -> Bool { lhs.rawValue < rhs }
  static func > (lhs: Self, rhs: Int) -> Bool { lhs.rawValue > rhs }
  static func <= (lhs: Self, rhs: Int) -> Bool { lhs.rawValue <= rhs }
  static func >= (lhs: Self, rhs: Int) -> Bool { lhs.rawValue >= rhs }
  static func == (lhs: Self, rhs: Int!) -> Bool { lhs.rawValue == (rhs ?? 0xFFFFFF) }
  static func != (lhs: Self, rhs: Int!) -> Bool { lhs.rawValue != (rhs ?? 0xFFFFFF) }
  static func + (lhs: Self, rhs: Int) -> Self {
    guard lhs.isOrdinal, let result: Self = .init(rawValue: lhs.rawValue + rhs), result.isOrdinal else { return .VoidSymbol }
    return result
  }

  typealias Stride = Int
  func distance(to other: SquirrelIndex) -> Int { other.rawValue - rawValue }
  func advanced(by n: Int) -> SquirrelIndex { .init(rawValue: rawValue + n) ?? .VoidSymbol }
}  // SquirrelIndex

extension Bool {
  static func |= (lhs: inout Bool, rhs: Bool) { if !lhs, rhs { lhs = true } }
  static func &= (lhs: inout Bool, rhs: Bool) { if lhs, !rhs { lhs = false } }
}
