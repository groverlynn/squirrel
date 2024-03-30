import AppKit
import Carbon

struct RimeModifier: OptionSet {
  let rawValue: Int32

  static let kShiftMask = RimeModifier(rawValue: 1 << 0)
  static let kLockMask = RimeModifier(rawValue: 1 << 1)
  static let kControlMask = RimeModifier(rawValue: 1 << 2)
  static let kMod1Mask = RimeModifier(rawValue: 1 << 3)
  static let kAltMask = kMod1Mask
  static let kMod2Mask = RimeModifier(rawValue: 1 << 4)
  static let kMod3Mask = RimeModifier(rawValue: 1 << 5)
  static let kMod4Mask = RimeModifier(rawValue: 1 << 6)
  static let kMod5Mask = RimeModifier(rawValue: 1 << 7)
  static let kButton1Mask = RimeModifier(rawValue: 1 << 8)
  static let kButton2Mask = RimeModifier(rawValue: 1 << 9)
  static let kButton3Mask = RimeModifier(rawValue: 1 << 10)
  static let kButton4Mask = RimeModifier(rawValue: 1 << 11)
  static let kButton5Mask = RimeModifier(rawValue: 1 << 12)
  /* ibus :) mask */
  static let kHandledMask = RimeModifier(rawValue: 1 << 24)
  static let kForwardMask = RimeModifier(rawValue: 1 << 25)
  static let kIgnoredMask = kForwardMask

  static let kSuperMask = RimeModifier(rawValue: 1 << 26)
  static let kHyperMask = RimeModifier(rawValue: 1 << 27)
  static let kMetaMask = RimeModifier(rawValue: 1 << 28)

  static let kReleaseMask = RimeModifier(rawValue: 1 << 30)
  static let kModifierMask = RimeModifier(rawValue: 0x5f001fff)
}

func get_rime_modifiers(_ modifiers: NSEvent.ModifierFlags) -> RimeModifier {
  var ret: RimeModifier = .init()

  if (modifiers.contains(.shift)) {
    ret.insert(.kShiftMask)
  }
  if (modifiers.contains(.capsLock)) {
    ret.insert(.kLockMask)
  }
  if (modifiers.contains(.control)) {
    ret.insert(.kControlMask)
  }
  if (modifiers.contains(.option)) {
    ret.insert(.kAltMask)
  }
  if (modifiers.contains(.command)) {
    ret.insert(.kSuperMask)
  }
  if (modifiers.contains(.function)) {
    ret.insert(.kHyperMask)
  }

  return ret
}


// pc keyboard

let kVK_PC_Application: Int = 0x6e
let kVK_PC_BS: Int = 0x33
let kVK_PC_Del: Int = 0x75
let kVK_PC_Insert: Int = 0x72
let kVK_PC_KeypadNumLock: Int = 0x47
let kVK_PC_Pause: Int = 0x71
let kVK_PC_Power: Int = 0x7f
let kVK_PC_PrintScreen: Int = 0x69
let kVK_PC_ScrollLock: Int = 0x6b

let keycode_mappings = [
  // modifiers
  kVK_CapsLock: XK_Caps_Lock,
  kVK_Command: XK_Super_L, // XK_Meta_L?
  kVK_RightCommand: XK_Super_R, // XK_Meta_R?
  kVK_Control: XK_Control_L,
  kVK_RightControl: XK_Control_R,
  kVK_Function: XK_Hyper_L,
  kVK_Option: XK_Alt_L,
  kVK_RightOption: XK_Alt_R,
  kVK_Shift: XK_Shift_L,
  kVK_RightShift: XK_Shift_R,

  // special
  kVK_Delete: XK_BackSpace,
  //OSX_VK_ENTER_POWERBOOK -> ?
  kVK_Escape: XK_Escape,
  kVK_ForwardDelete: XK_Delete,
  //kVK_Help： XK_Help, // the same keycode as kVK_PC_INSERT
  kVK_Return: XK_Return,
  kVK_Space: XK_space,
  kVK_Tab: XK_Tab,

  // function
  kVK_F1: XK_F1,
  kVK_F2: XK_F2,
  kVK_F3: XK_F3,
  kVK_F4: XK_F4,
  kVK_F5: XK_F5,
  kVK_F6: XK_F6,
  kVK_F7: XK_F7,
  kVK_F8: XK_F8,
  kVK_F9: XK_F9,
  kVK_F10: XK_F10,
  kVK_F11: XK_F11,
  kVK_F12: XK_F12,
  kVK_F13: XK_F13,
  kVK_F14: XK_F14,
  kVK_F15: XK_F15,
  kVK_F16: XK_F16,
  kVK_F17: XK_F17,
  kVK_F18: XK_F18,
  kVK_F19: XK_F19,
  kVK_F20: XK_F20,

  // cursor
  kVK_UpArrow: XK_Up,
  kVK_DownArrow: XK_Down,
  kVK_LeftArrow: XK_Left,
  kVK_RightArrow: XK_Right,
  kVK_PageUp: XK_Page_Up,
  kVK_PageDown: XK_Page_Down,
  kVK_Home: XK_Home,
  kVK_End: XK_End,

  // keypad
  kVK_ANSI_Keypad0: XK_KP_0,
  kVK_ANSI_Keypad1: XK_KP_1,
  kVK_ANSI_Keypad2: XK_KP_2,
  kVK_ANSI_Keypad3: XK_KP_3,
  kVK_ANSI_Keypad4: XK_KP_4,
  kVK_ANSI_Keypad5: XK_KP_5,
  kVK_ANSI_Keypad6: XK_KP_6,
  kVK_ANSI_Keypad7: XK_KP_7,
  kVK_ANSI_Keypad8: XK_KP_8,
  kVK_ANSI_Keypad9: XK_KP_9,
  kVK_ANSI_KeypadEnter: XK_KP_Enter,
  kVK_ANSI_KeypadClear: XK_Clear,
  kVK_ANSI_KeypadDecimal: XK_KP_Decimal,
  kVK_ANSI_KeypadEquals: XK_KP_Equal,
  kVK_ANSI_KeypadMinus: XK_KP_Subtract,
  kVK_ANSI_KeypadMultiply: XK_KP_Multiply,
  kVK_ANSI_KeypadPlus: XK_KP_Add,
  kVK_ANSI_KeypadDivide: XK_KP_Divide,

  // pc keyboard
  kVK_PC_Application: XK_Menu,
  kVK_PC_Insert: XK_Insert,
  //kVK_PC_Keypad_NumLock: XK_Num_Lock, // the same keycode as kVK_ANSI_KeypadClear
  kVK_PC_Pause: XK_Pause,
  //OSX_VK_PC_Power -> ?
  kVK_PC_PrintScreen: XK_Print,
  kVK_PC_ScrollLock: XK_Scroll_Lock,

  // JIS keyboard
  kVK_JIS_KeypadComma: XK_KP_Separator,
  kVK_JIS_Eisu: XK_Eisu_toggle,
  kVK_JIS_Kana: XK_Kana_Shift
]

let keychar_mappings = [
  // ASCII control characters
  NSEnterCharacter: XK_KP_Enter,
  NSBackspaceCharacter: XK_BackSpace,
  NSTabCharacter: XK_Tab,
  NSNewlineCharacter: XK_Linefeed,
  NSCarriageReturnCharacter: XK_Return,
  NSBackTabCharacter: XK_ISO_Left_Tab,
  NSDeleteCharacter: XK_Delete,
  // Nagivator key characters
  NSUpArrowFunctionKey: XK_Up,
  NSDownArrowFunctionKey: XK_Down,
  NSLeftArrowFunctionKey: XK_Left,
  NSRightArrowFunctionKey: XK_Right,
  // Function key characters
  NSF1FunctionKey: XK_F1,
  NSF2FunctionKey: XK_F2,
  NSF3FunctionKey: XK_F3,
  NSF4FunctionKey: XK_F4,
  NSF5FunctionKey: XK_F5,
  NSF6FunctionKey: XK_F6,
  NSF7FunctionKey: XK_F7,
  NSF8FunctionKey: XK_F8,
  NSF9FunctionKey: XK_F9,
  NSF10FunctionKey: XK_F10,
  NSF11FunctionKey: XK_F11,
  NSF12FunctionKey: XK_F12,
  NSF13FunctionKey: XK_F13,
  NSF14FunctionKey: XK_F14,
  NSF15FunctionKey: XK_F15,
  NSF16FunctionKey: XK_F16,
  NSF17FunctionKey: XK_F17,
  NSF18FunctionKey: XK_F18,
  NSF19FunctionKey: XK_F19,
  NSF20FunctionKey: XK_F20,
  NSF21FunctionKey: XK_F21,
  NSF22FunctionKey: XK_F22,
  NSF23FunctionKey: XK_F23,
  NSF24FunctionKey: XK_F24,
  NSF25FunctionKey: XK_F25,
  NSF26FunctionKey: XK_F26,
  NSF27FunctionKey: XK_F27,
  NSF28FunctionKey: XK_F28,
  NSF29FunctionKey: XK_F29,
  NSF30FunctionKey: XK_F30,
  NSF31FunctionKey: XK_F31,
  NSF32FunctionKey: XK_F32,
  NSF33FunctionKey: XK_F33,
  NSF34FunctionKey: XK_F34,
  NSF35FunctionKey: XK_F35,
  // Misc functional key characters
  NSInsertFunctionKey: XK_Insert,
  NSDeleteFunctionKey: XK_Delete,
  NSHomeFunctionKey: XK_Home,
  NSBeginFunctionKey: XK_Begin,
  NSEndFunctionKey: XK_End,
  NSPageUpFunctionKey: XK_Page_Up,
  NSPageDownFunctionKey: XK_Page_Down,
  NSScrollLockFunctionKey: XK_Scroll_Lock,
  NSPauseFunctionKey: XK_Pause,
  NSSysReqFunctionKey: XK_Sys_Req,
  NSBreakFunctionKey: XK_Break,
  NSStopFunctionKey: XK_Cancel,
  NSMenuFunctionKey: XK_Menu,
  NSPrintFunctionKey: XK_Print,
  NSClearLineFunctionKey: XK_Clear,
  NSClearDisplayFunctionKey: XK_Num_Lock,
  NSSelectFunctionKey: XK_Select,
  NSExecuteFunctionKey: XK_Execute,
  NSUndoFunctionKey: XK_Undo,
  NSRedoFunctionKey: XK_Redo,
  NSFindFunctionKey: XK_Find,
  NSHelpFunctionKey: XK_Help,
  NSModeSwitchFunctionKey: XK_Mode_switch
]

func get_rime_keycode(keycode: Int, keychar: Int, shift: Boolean, caps: Boolean) -> Int32 {
  if let rime_keycode = keycode_mappings[keycode] {
    return rime_keycode
  }

  // NOTE: IBus/Rime use different keycodes for uppercase/lowercase letters.
  if (keychar >= Int(("a" as Character).asciiValue!) &&
      keychar <= Int(("z" as Character).asciiValue!) && (shift != caps)) {
    // lowercase -> Uppercase
    return Int32(keychar) + Int32(("A" as Character).asciiValue! - ("a" as Character).asciiValue!)
  }

  if keychar >= 0x20 && keychar <= 0x7e {
    return Int32(keychar)
  }

  if let rime_keychar = keychar_mappings[keychar] {
    return Int32(rime_keychar)
  }

  return XK_VoidSymbol
}
