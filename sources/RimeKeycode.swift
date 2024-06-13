import AppKit
import Carbon

// `modiferKeyState` for UCKeyTranslate, defined as
// ((EventRecord.modifiers) >> 8) & 0xFF;
struct EventModifiers: OptionSet, Sendable, Hashable {
  let rawValue: CUnsignedInt

  static let `cmdKey`: Self = .init(rawValue: 1 << 0)
  static let shiftKey: Self = .init(rawValue: 1 << 1)
  static let alphaLock: Self = .init(rawValue: 1 << 2)
  static let optionKey: Self = .init(rawValue: 1 << 3)
  static let controlKey: Self = .init(rawValue: 1 << 4)

  init(rawValue: CUnsignedInt) { self.rawValue = rawValue }

  init(macModifiers: NSEvent.ModifierFlags) {
    self.init()
    if macModifiers.contains(.command) { insert(.cmdKey) }
    if macModifiers.contains(.shift) { insert(.shiftKey) }
    if macModifiers.contains(.capsLock) { insert(.alphaLock) }
    if macModifiers.contains(.option) { insert(.optionKey) }
    if macModifiers.contains(.control) { insert(.controlKey) }
  }
}  // EventModifiers

struct RimeModifiers: OptionSet, Sendable, Hashable {
  let rawValue: CInt

  static let Shift: Self = .init(rawValue: 1 << 0)
  static let Lock: Self = .init(rawValue: 1 << 1)
  static let Control: Self = .init(rawValue: 1 << 2)
  static let Alt: Self = .init(rawValue: 1 << 3)
  static let Handled: Self = .init(rawValue: 1 << 24)
  static let Ignored: Self = .init(rawValue: 1 << 25)
  static let Super: Self = .init(rawValue: 1 << 26)
  static let Hyper: Self = .init(rawValue: 1 << 27)
  static let Meta: Self = .init(rawValue: 1 << 28)
  static let Release: Self = .init(rawValue: 1 << 30)
  static let ModifierMask: Self = .init(rawValue: 0x5F001FFF)

  init(rawValue: CInt) { self.rawValue = rawValue }

  init(macModifiers: NSEvent.ModifierFlags) {
    self.init()
    if macModifiers.contains(.shift) { insert(.Shift) }
    if macModifiers.contains(.capsLock) { insert(.Lock) }
    if macModifiers.contains(.control) { insert(.Control) }
    if macModifiers.contains(.option) { insert(.Alt) }
    if macModifiers.contains(.command) { insert(.Super) }
    if macModifiers.contains(.function) { insert(.Hyper) }
  }

  init?(name: String) {
    switch name {
    case "Shift": self = .Shift
    case "Lock": self = .Lock
    case "Control": self = .Control
    case "Alt": self = .Alt
    case "Super": self = .Super
    case "Hyper": self = .Hyper
    case "Meta": self = .Meta
    default: return nil
    }
  }
}  // RimeModifiers

// powerbook
public var kVK_Enter_Powerbook: Int { 0x34 }
// pc keyboard
public var kVK_PC_Application: Int { 0x6E }
public var kVK_PC_Power: Int { 0x7F }

enum RimeKeyCode: CInt, Sendable, Strideable, Hashable {
  case XK_VoidSymbol = 0xFFFFFF

  case XK_BackSpace = 0xFF08
  case XK_Tab = 0xFF09
  case XK_Linefeed = 0xFF0A
  case XK_Clear = 0xFF0B
  case XK_Return = 0xFF0D
  case XK_Pause = 0xFF13
  case XK_Scroll_Lock = 0xFF14
  case XK_Sys_Req = 0xFF15
  case XK_Escape = 0xFF1B
  case XK_Delete = 0xFFFF
  /* International & multi-key character composition */
  case XK_Multi_key = 0xFF20
  case XK_Codeinput = 0xFF37
  case XK_SingleCandidate = 0xFF3C
  case XK_MultipleCandidate = 0xFF3D
  case XK_PreviousCandidate = 0xFF3E
  /* Japanese keyboard support */
  case XK_Kanji = 0xFF21
  case XK_Muhenkan = 0xFF22
  case XK_Henkan = 0xFF23
  case XK_Romaji = 0xFF24
  case XK_Hiragana = 0xFF25
  case XK_Katakana = 0xFF26
  case XK_Hiragana_Katakana = 0xFF27
  case XK_Zenkaku = 0xFF28
  case XK_Hankaku = 0xFF29
  case XK_Zenkaku_Hankaku = 0xFF2A
  case XK_Touroku = 0xFF2B
  case XK_Massyo = 0xFF2C
  case XK_Kana_Lock = 0xFF2D
  case XK_Kana_Shift = 0xFF2E
  case XK_Eisu_Shift = 0xFF2F
  case XK_Eisu_toggle = 0xFF30
  /* Cursor control & motion */
  case XK_Home = 0xFF50
  case XK_Left = 0xFF51
  case XK_Up = 0xFF52
  case XK_Right = 0xFF53
  case XK_Down = 0xFF54
  case XK_Page_Up = 0xFF55
  case XK_Page_Down = 0xFF56
  case XK_End = 0xFF57
  case XK_Begin = 0xFF58
  /* Misc functions */
  case XK_Select = 0xFF60
  case XK_Print = 0xFF61
  case XK_Execute = 0xFF62
  case XK_Insert = 0xFF63
  case XK_Undo = 0xFF65
  case XK_Redo = 0xFF66
  case XK_Menu = 0xFF67
  case XK_Find = 0xFF68
  case XK_Cancel = 0xFF69
  case XK_Help = 0xFF6A
  case XK_Break = 0xFF6B
  case XK_Mode_switch = 0xFF7E
  case XK_Num_Lock = 0xFF7F
  /* Keypad functions, keypad numbers cleverly chosen to map to ASCII */
  case XK_KP_Space = 0xFF80
  case XK_KP_Tab = 0xFF89
  case XK_KP_Enter = 0xFF8D
  case XK_KP_F1 = 0xFF91
  case XK_KP_F2 = 0xFF92
  case XK_KP_F3 = 0xFF93
  case XK_KP_F4 = 0xFF94
  case XK_KP_Home = 0xFF95
  case XK_KP_Left = 0xFF96
  case XK_KP_Up = 0xFF97
  case XK_KP_Right = 0xFF98
  case XK_KP_Down = 0xFF99
  case XK_KP_Page_Up = 0xFF9A
  case XK_KP_Page_Down = 0xFF9B
  case XK_KP_End = 0xFF9C
  case XK_KP_Begin = 0xFF9D
  case XK_KP_Insert = 0xFF9E
  case XK_KP_Delete = 0xFF9F
  case XK_KP_Equal = 0xFFBD
  case XK_KP_Multiply = 0xFFAA
  case XK_KP_Add = 0xFFAB
  case XK_KP_Separator = 0xFFAC
  case XK_KP_Subtract = 0xFFAD
  case XK_KP_Decimal = 0xFFAE
  case XK_KP_Divide = 0xFFAF

  case XK_KP_0 = 0xFFB0
  case XK_KP_1 = 0xFFB1
  case XK_KP_2 = 0xFFB2
  case XK_KP_3 = 0xFFB3
  case XK_KP_4 = 0xFFB4
  case XK_KP_5 = 0xFFB5
  case XK_KP_6 = 0xFFB6
  case XK_KP_7 = 0xFFB7
  case XK_KP_8 = 0xFFB8
  case XK_KP_9 = 0xFFB9
  /* Auxiliary functions */
  case XK_F1 = 0xFFBE
  case XK_F2 = 0xFFBF
  case XK_F3 = 0xFFC0
  case XK_F4 = 0xFFC1
  case XK_F5 = 0xFFC2
  case XK_F6 = 0xFFC3
  case XK_F7 = 0xFFC4
  case XK_F8 = 0xFFC5
  case XK_F9 = 0xFFC6
  case XK_F10 = 0xFFC7
  case XK_F11 = 0xFFC8
  case XK_F12 = 0xFFC9
  case XK_F13 = 0xFFCA
  case XK_F14 = 0xFFCB
  case XK_F15 = 0xFFCC
  case XK_F16 = 0xFFCD
  case XK_F17 = 0xFFCE
  case XK_F18 = 0xFFCF
  case XK_F19 = 0xFFD0
  case XK_F20 = 0xFFD1
  case XK_F21 = 0xFFD2
  case XK_F22 = 0xFFD3
  case XK_F23 = 0xFFD4
  case XK_F24 = 0xFFD5
  case XK_F25 = 0xFFD6
  case XK_F26 = 0xFFD7
  case XK_F27 = 0xFFD8
  case XK_F28 = 0xFFD9
  case XK_F29 = 0xFFDA
  case XK_F30 = 0xFFDB
  case XK_F31 = 0xFFDC
  case XK_F32 = 0xFFDD
  case XK_F33 = 0xFFDE
  case XK_F34 = 0xFFDF
  case XK_F35 = 0xFFE0
  /* Modifiers */
  case XK_Shift_L = 0xFFE1
  case XK_Shift_R = 0xFFE2
  case XK_Control_L = 0xFFE3
  case XK_Control_R = 0xFFE4
  case XK_Caps_Lock = 0xFFE5
  case XK_Shift_Lock = 0xFFE6
  case XK_Meta_L = 0xFFE7
  case XK_Meta_R = 0xFFE8
  case XK_Alt_L = 0xFFE9
  case XK_Alt_R = 0xFFEA
  case XK_Super_L = 0xFFEB
  case XK_Super_R = 0xFFEC
  case XK_Hyper_L = 0xFFED
  case XK_Hyper_R = 0xFFEE
  /* ASCII */
  case XK_space = 0x0020
  case XK_exclam = 0x0021
  case XK_quotedbl = 0x0022
  case XK_numbersign = 0x0023
  case XK_dollar = 0x0024
  case XK_percent = 0x0025
  case XK_ampersand = 0x0026
  case XK_apostrophe = 0x0027
  case XK_parenleft = 0x0028
  case XK_parenright = 0x0029
  case XK_asterisk = 0x002A
  case XK_plus = 0x002B
  case XK_comma = 0x002C
  case XK_minus = 0x002D
  case XK_period = 0x002E
  case XK_slash = 0x002F
  case XK_0 = 0x0030
  case XK_1 = 0x0031
  case XK_2 = 0x0032
  case XK_3 = 0x0033
  case XK_4 = 0x0034
  case XK_5 = 0x0035
  case XK_6 = 0x0036
  case XK_7 = 0x0037
  case XK_8 = 0x0038
  case XK_9 = 0x0039
  case XK_colon = 0x003A
  case XK_semicolon = 0x003B
  case XK_less = 0x003C
  case XK_equal = 0x003D
  case XK_greater = 0x003E
  case XK_question = 0x003F
  case XK_at = 0x0040
  case XK_A = 0x0041
  case XK_B = 0x0042
  case XK_C = 0x0043
  case XK_D = 0x0044
  case XK_E = 0x0045
  case XK_F = 0x0046
  case XK_G = 0x0047
  case XK_H = 0x0048
  case XK_I = 0x0049
  case XK_J = 0x004A
  case XK_K = 0x004B
  case XK_L = 0x004C
  case XK_M = 0x004D
  case XK_N = 0x004E
  case XK_O = 0x004F
  case XK_P = 0x0050
  case XK_Q = 0x0051
  case XK_R = 0x0052
  case XK_S = 0x0053
  case XK_T = 0x0054
  case XK_U = 0x0055
  case XK_V = 0x0056
  case XK_W = 0x0057
  case XK_X = 0x0058
  case XK_Y = 0x0059
  case XK_Z = 0x005A
  case XK_bracketleft = 0x005B
  case XK_backslash = 0x005C
  case XK_bracketright = 0x005D
  case XK_asciicircum = 0x005E
  case XK_underscore = 0x005F
  case XK_grave = 0x0060
  case XK_a = 0x0061
  case XK_b = 0x0062
  case XK_c = 0x0063
  case XK_d = 0x0064
  case XK_e = 0x0065
  case XK_f = 0x0066
  case XK_g = 0x0067
  case XK_h = 0x0068
  case XK_i = 0x0069
  case XK_j = 0x006A
  case XK_k = 0x006B
  case XK_l = 0x006C
  case XK_m = 0x006D
  case XK_n = 0x006E
  case XK_o = 0x006F
  case XK_p = 0x0070
  case XK_q = 0x0071
  case XK_r = 0x0072
  case XK_s = 0x0073
  case XK_t = 0x0074
  case XK_u = 0x0075
  case XK_v = 0x0076
  case XK_w = 0x0077
  case XK_x = 0x0078
  case XK_y = 0x0079
  case XK_z = 0x007A
  case XK_braceleft = 0x007B
  case XK_bar = 0x007C
  case XK_braceright = 0x007D
  case XK_asciitilde = 0x007E
  /* Latin-1 */
  case XK_nobreakspace = 0x00A0
  case XK_exclamdown = 0x00A1
  case XK_cent = 0x00A2
  case XK_sterling = 0x00A3
  case XK_currency = 0x00A4
  case XK_yen = 0x00A5
  case XK_brokenbar = 0x00A6
  case XK_section = 0x00A7
  case XK_diaeresis = 0x00A8
  case XK_copyright = 0x00A9
  case XK_ordfeminine = 0x00AA
  case XK_guillemotleft = 0x00AB
  case XK_notsign = 0x00AC
  case XK_hyphen = 0x00AD
  case XK_registered = 0x00AE
  case XK_macron = 0x00AF
  case XK_degree = 0x00B0
  case XK_plusminus = 0x00B1
  case XK_twosuperior = 0x00B2
  case XK_threesuperior = 0x00B3
  case XK_acute = 0x00B4
  case XK_mu = 0x00B5
  case XK_paragraph = 0x00B6
  case XK_periodcentered = 0x00B7
  case XK_cedilla = 0x00B8
  case XK_onesuperior = 0x00B9
  case XK_masculine = 0x00BA
  case XK_guillemotright = 0x00BB
  case XK_onequarter = 0x00BC
  case XK_onehalf = 0x00BD
  case XK_threequarters = 0x00BE
  case XK_questiondown = 0x00BF
  case XK_Agrave = 0x00C0
  case XK_Aacute = 0x00C1
  case XK_Acircumflex = 0x00C2
  case XK_Atilde = 0x00C3
  case XK_Adiaeresis = 0x00C4
  case XK_Aring = 0x00C5
  case XK_AE = 0x00C6
  case XK_Ccedilla = 0x00C7
  case XK_Egrave = 0x00C8
  case XK_Eacute = 0x00C9
  case XK_Ecircumflex = 0x00CA
  case XK_Ediaeresis = 0x00CB
  case XK_Igrave = 0x00CC
  case XK_Iacute = 0x00CD
  case XK_Icircumflex = 0x00CE
  case XK_Idiaeresis = 0x00CF
  case XK_ETH = 0x00D0
  case XK_Ntilde = 0x00D1
  case XK_Ograve = 0x00D2
  case XK_Oacute = 0x00D3
  case XK_Ocircumflex = 0x00D4
  case XK_Otilde = 0x00D5
  case XK_Odiaeresis = 0x00D6
  case XK_multiply = 0x00D7
  case XK_Oslash = 0x00D8
  case XK_Ugrave = 0x00D9
  case XK_Uacute = 0x00DA
  case XK_Ucircumflex = 0x00DB
  case XK_Udiaeresis = 0x00DC
  case XK_Yacute = 0x00DD
  case XK_THORN = 0x00DE
  case XK_ssharp = 0x00DF
  case XK_agrave = 0x00E0
  case XK_aacute = 0x00E1
  case XK_acircumflex = 0x00E2
  case XK_atilde = 0x00E3
  case XK_adiaeresis = 0x00E4
  case XK_aring = 0x00E5
  case XK_ae = 0x00E6
  case XK_ccedilla = 0x00E7
  case XK_egrave = 0x00E8
  case XK_eacute = 0x00E9
  case XK_ecircumflex = 0x00EA
  case XK_ediaeresis = 0x00EB
  case XK_igrave = 0x00EC
  case XK_iacute = 0x00ED
  case XK_icircumflex = 0x00EE
  case XK_idiaeresis = 0x00EF
  case XK_eth = 0x00F0
  case XK_ntilde = 0x00F1
  case XK_ograve = 0x00F2
  case XK_oacute = 0x00F3
  case XK_ocircumflex = 0x00F4
  case XK_otilde = 0x00F5
  case XK_odiaeresis = 0x00F6
  case XK_division = 0x00F7
  case XK_oslash = 0x00F8
  case XK_ugrave = 0x00F9
  case XK_uacute = 0x00FA
  case XK_ucircumflex = 0x00FB
  case XK_udiaeresis = 0x00FC
  case XK_yacute = 0x00FD
  case XK_thorn = 0x00FE
  case XK_ydiaeresis = 0x00FF
  /* Keyboard (XKB) Extension function and modifier keys */
  case XK_ISO_Lock = 0xFE01
  case XK_ISO_Level2_Latch = 0xFE02
  case XK_ISO_Level3_Shift = 0xFE03
  case XK_ISO_Level3_Latch = 0xFE04
  case XK_ISO_Level3_Lock = 0xFE05
  case XK_ISO_Level5_Shift = 0xFE11
  case XK_ISO_Level5_Latch = 0xFE12
  case XK_ISO_Level5_Lock = 0xFE13
  case XK_ISO_Group_Latch = 0xFE06
  case XK_ISO_Group_Lock = 0xFE07
  case XK_ISO_Next_Group = 0xFE08
  case XK_ISO_Next_Group_Lock = 0xFE09
  case XK_ISO_Prev_Group = 0xFE0A
  case XK_ISO_Prev_Group_Lock = 0xFE0B
  case XK_ISO_First_Group = 0xFE0C
  case XK_ISO_First_Group_Lock = 0xFE0D
  case XK_ISO_Last_Group = 0xFE0E
  case XK_ISO_Last_Group_Lock = 0xFE0F
  case XK_ISO_Left_Tab = 0xFE20
  case XK_ISO_Move_Line_Up = 0xFE21
  case XK_ISO_Move_Line_Down = 0xFE22
  case XK_ISO_Partial_Line_Up = 0xFE23
  case XK_ISO_Partial_Line_Down = 0xFE24
  case XK_ISO_Partial_Space_Left = 0xFE25
  case XK_ISO_Partial_Space_Right = 0xFE26
  case XK_ISO_Set_Margin_Left = 0xFE27
  case XK_ISO_Set_Margin_Right = 0xFE28
  case XK_ISO_Release_Margin_Left = 0xFE29
  case XK_ISO_Release_Margin_Right = 0xFE2A
  case XK_ISO_Release_Both_Margins = 0xFE2B
  case XK_ISO_Fast_Cursor_Left = 0xFE2C
  case XK_ISO_Fast_Cursor_Right = 0xFE2D
  case XK_ISO_Fast_Cursor_Up = 0xFE2E
  case XK_ISO_Fast_Cursor_Down = 0xFE2F
  case XK_ISO_Continuous_Underline = 0xFE30
  case XK_ISO_Discontinuous_Underline = 0xFE31
  case XK_ISO_Emphasize = 0xFE32
  case XK_ISO_Center_Object = 0xFE33
  case XK_ISO_Enter = 0xFE34

  init(macKeyCode: Int) {
    self = switch macKeyCode {
    case kVK_CapsLock: .XK_Caps_Lock
    case kVK_Command: .XK_Super_L // XK_Meta_L?
    case kVK_RightCommand: .XK_Super_R // XK_Meta_R?
    case kVK_Control: .XK_Control_L
    case kVK_RightControl: .XK_Control_R
    case kVK_Function: .XK_Hyper_L
    case kVK_Option: .XK_Alt_L
    case kVK_RightOption: .XK_Alt_R
    case kVK_Shift: .XK_Shift_L
    case kVK_RightShift: .XK_Shift_R
      // special
    case kVK_Delete: .XK_BackSpace
    case kVK_Enter_Powerbook: .XK_ISO_Enter
    case kVK_Escape: .XK_Escape
    case kVK_ForwardDelete: .XK_Delete
    case kVK_Help: .XK_Help
    case kVK_Return: .XK_Return
    case kVK_Space: .XK_space
    case kVK_Tab: .XK_Tab
      // function
    case kVK_F1: .XK_F1
    case kVK_F2: .XK_F2
    case kVK_F3: .XK_F3
    case kVK_F4: .XK_F4
    case kVK_F5: .XK_F5
    case kVK_F6: .XK_F6
    case kVK_F7: .XK_F7
    case kVK_F8: .XK_F8
    case kVK_F9: .XK_F9
    case kVK_F10: .XK_F10
    case kVK_F11: .XK_F11
    case kVK_F12: .XK_F12
    case kVK_F13: .XK_F13
    case kVK_F14: .XK_F14
    case kVK_F15: .XK_F15
    case kVK_F16: .XK_F16
    case kVK_F17: .XK_F17
    case kVK_F18: .XK_F18
    case kVK_F19: .XK_F19
    case kVK_F20: .XK_F20
      // cursor
    case kVK_UpArrow: .XK_Up
    case kVK_DownArrow: .XK_Down
    case kVK_LeftArrow: .XK_Left
    case kVK_RightArrow: .XK_Right
    case kVK_PageUp: .XK_Page_Up
    case kVK_PageDown: .XK_Page_Down
    case kVK_Home: .XK_Home
    case kVK_End: .XK_End
      // keypad
    case kVK_ANSI_Keypad0: .XK_KP_0
    case kVK_ANSI_Keypad1: .XK_KP_1
    case kVK_ANSI_Keypad2: .XK_KP_2
    case kVK_ANSI_Keypad3: .XK_KP_3
    case kVK_ANSI_Keypad4: .XK_KP_4
    case kVK_ANSI_Keypad5: .XK_KP_5
    case kVK_ANSI_Keypad6: .XK_KP_6
    case kVK_ANSI_Keypad7: .XK_KP_7
    case kVK_ANSI_Keypad8: .XK_KP_8
    case kVK_ANSI_Keypad9: .XK_KP_9
    case kVK_ANSI_KeypadEnter: .XK_KP_Enter
    case kVK_ANSI_KeypadClear: .XK_Clear
    case kVK_ANSI_KeypadDecimal: .XK_KP_Decimal
    case kVK_ANSI_KeypadEquals: .XK_KP_Equal
    case kVK_ANSI_KeypadMinus: .XK_KP_Subtract
    case kVK_ANSI_KeypadMultiply: .XK_KP_Multiply
    case kVK_ANSI_KeypadPlus: .XK_KP_Add
    case kVK_ANSI_KeypadDivide: .XK_KP_Divide
      // pc keyboard
    case kVK_PC_Application: .XK_Menu
      // JIS keyboard
    case kVK_JIS_KeypadComma: .XK_KP_Separator
    case kVK_JIS_Eisu: .XK_Eisu_toggle
    case kVK_JIS_Kana: .XK_Kana_Shift

    default: .XK_VoidSymbol
    }
  }

  init(keychar: unichar, shift: Bool, caps: Bool) {
    // NOTE: IBus/Rime use different keycodes for uppercase/lowercase letters.
    if 0x61...0x7A ~= keychar, shift != caps {
      // lowercase -> Uppercase
      self.init(rawValue: CInt(keychar) - 0x20)!; return
    }

    if 0x20...0x7E ~= keychar {
      self.init(rawValue: CInt(keychar))!; return
    }

    self = switch NSEvent.SpecialKey(rawValue: Int(keychar)) {
      // ASCII control characters
    case .newline: .XK_Linefeed
    case .backTab: .XK_ISO_Left_Tab
      // Function key characters
    case .f21: .XK_F21
    case .f22: .XK_F22
    case .f23: .XK_F23
    case .f24: .XK_F24
    case .f25: .XK_F25
    case .f26: .XK_F26
    case .f27: .XK_F27
    case .f28: .XK_F28
    case .f29: .XK_F29
    case .f30: .XK_F30
    case .f31: .XK_F31
    case .f32: .XK_F32
    case .f33: .XK_F33
    case .f34: .XK_F34
    case .f35: .XK_F35
      // Misc functional key characters
    case .insert: .XK_Insert
    case .begin: .XK_Begin
    case .scrollLock: .XK_Scroll_Lock
    case .pause: .XK_Pause
    case .sysReq: .XK_Sys_Req
    case .break: .XK_Break
    case .stop: .XK_Cancel
    case .print: .XK_Print
    case .clearLine: .XK_Num_Lock
    case .prev: .XK_Page_Up
    case .next: .XK_Page_Down
    case .select: .XK_Select
    case .execute: .XK_Execute
    case .undo: .XK_Undo
    case .redo: .XK_Redo
    case .find: .XK_Find
    case .modeSwitch: .XK_Mode_switch

    default: .XK_VoidSymbol
    }
  }

  init(name: String) { self.init(rawValue: Self.nameToRawValue(name))! }

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
  static func + (lhs: Self, rhs: Self) -> Self { .init(rawValue: lhs.rawValue + rhs.rawValue) ?? .XK_VoidSymbol }
  static func - (lhs: Self, rhs: Self) -> Self { .init(rawValue: lhs.rawValue - rhs.rawValue) ?? .XK_VoidSymbol }

  typealias Stride = CInt
  func distance(to other: Self) -> Stride { other.rawValue - rawValue }
  func advanced(by n: Stride) -> Self { .init(rawValue: rawValue + n) ?? .XK_VoidSymbol }

  static private func nameToRawValue(_ name: String) -> CInt {
    return switch name {
    // ascii
    case "space": 0x000020
    case "exclam": 0x000021
    case "quotedbl": 0x000022
    case "numbersign": 0x000023
    case "dollar": 0x000024
    case "percent": 0x000025
    case "ampersand": 0x000026
    case "apostrophe": 0x000027
    case "quoteright": 0x000027
    case "parenleft": 0x000028
    case "parenright": 0x000029
    case "asterisk": 0x00002A
    case "plus": 0x00002B
    case "comma": 0x00002C
    case "minus": 0x00002D
    case "period": 0x00002E
    case "slash": 0x00002F
    case "0": 0x000030
    case "1": 0x000031
    case "2": 0x000032
    case "3": 0x000033
    case "4": 0x000034
    case "5": 0x000035
    case "6": 0x000036
    case "7": 0x000037
    case "8": 0x000038
    case "9": 0x000039
    case "colon": 0x00003A
    case "semicolon": 0x00003B
    case "less": 0x00003C
    case "equal": 0x00003D
    case "greater": 0x00003E
    case "question": 0x00003F
    case "at": 0x000040
    case "A": 0x000041
    case "B": 0x000042
    case "C": 0x000043
    case "D": 0x000044
    case "E": 0x000045
    case "F": 0x000046
    case "G": 0x000047
    case "H": 0x000048
    case "I": 0x000049
    case "J": 0x00004A
    case "K": 0x00004B
    case "L": 0x00004C
    case "M": 0x00004D
    case "N": 0x00004E
    case "O": 0x00004F
    case "P": 0x000050
    case "Q": 0x000051
    case "R": 0x000052
    case "S": 0x000053
    case "T": 0x000054
    case "U": 0x000055
    case "V": 0x000056
    case "W": 0x000057
    case "X": 0x000058
    case "Y": 0x000059
    case "Z": 0x00005A
    case "bracketleft": 0x00005B
    case "backslash": 0x00005C
    case "bracketright": 0x00005D
    case "asciicircum": 0x00005E
    case "underscore": 0x00005F
    case "grave": 0x000060
    case "quoteleft": 0x000060
    case "a": 0x000061
    case "b": 0x000062
    case "c": 0x000063
    case "d": 0x000064
    case "e": 0x000065
    case "f": 0x000066
    case "g": 0x000067
    case "h": 0x000068
    case "i": 0x000069
    case "j": 0x00006A
    case "k": 0x00006B
    case "l": 0x00006C
    case "m": 0x00006D
    case "n": 0x00006E
    case "o": 0x00006F
    case "p": 0x000070
    case "q": 0x000071
    case "r": 0x000072
    case "s": 0x000073
    case "t": 0x000074
    case "u": 0x000075
    case "v": 0x000076
    case "w": 0x000077
    case "x": 0x000078
    case "y": 0x000079
    case "z": 0x00007A
    case "braceleft": 0x00007B
    case "bar": 0x00007C
    case "braceright": 0x00007D
    case "asciitilde": 0x00007E
    // latin-1
    case "nobreakspace": 0x0000A0
    case "exclamdown": 0x0000A1
    case "cent": 0x0000A2
    case "sterling": 0x0000A3
    case "currency": 0x0000A4
    case "yen": 0x0000A5
    case "brokenbar": 0x0000A6
    case "section": 0x0000A7
    case "diaeresis": 0x0000A8
    case "copyright": 0x0000A9
    case "ordfeminine": 0x0000AA
    case "guillemotleft": 0x0000AB
    case "notsign": 0x0000AC
    case "hyphen": 0x0000AD
    case "registered": 0x0000AE
    case "macron": 0x0000AF
    case "degree": 0x0000B0
    case "plusminus": 0x0000B1
    case "twosuperior": 0x0000B2
    case "threesuperior": 0x0000B3
    case "acute": 0x0000B4
    case "mu": 0x0000B5
    case "paragraph": 0x0000B6
    case "periodcentered": 0x0000B7
    case "cedilla": 0x0000B8
    case "onesuperior": 0x0000B9
    case "masculine": 0x0000BA
    case "guillemotright": 0x0000BB
    case "onequarter": 0x0000BC
    case "onehalf": 0x0000BD
    case "threequarters": 0x0000BE
    case "questiondown": 0x0000BF
    case "Agrave": 0x0000C0
    case "Aacute": 0x0000C1
    case "Acircumflex": 0x0000C2
    case "Atilde": 0x0000C3
    case "Adiaeresis": 0x0000C4
    case "Aring": 0x0000C5
    case "AE": 0x0000C6
    case "Ccedilla": 0x0000C7
    case "Egrave": 0x0000C8
    case "Eacute": 0x0000C9
    case "Ecircumflex": 0x0000CA
    case "Ediaeresis": 0x0000CB
    case "Igrave": 0x0000CC
    case "Iacute": 0x0000CD
    case "Icircumflex": 0x0000CE
    case "Idiaeresis": 0x0000CF
    case "ETH": 0x0000D0
    case "Eth": 0x0000D0
    case "Ntilde": 0x0000D1
    case "Ograve": 0x0000D2
    case "Oacute": 0x0000D3
    case "Ocircumflex": 0x0000D4
    case "Otilde": 0x0000D5
    case "Odiaeresis": 0x0000D6
    case "multiply": 0x0000D7
    case "Ooblique": 0x0000D8
    case "Ugrave": 0x0000D9
    case "Uacute": 0x0000DA
    case "Ucircumflex": 0x0000DB
    case "Udiaeresis": 0x0000DC
    case "Yacute": 0x0000DD
    case "THORN": 0x0000DE
    case "Thorn": 0x0000DE
    case "ssharp": 0x0000DF
    case "agrave": 0x0000E0
    case "aacute": 0x0000E1
    case "acircumflex": 0x0000E2
    case "atilde": 0x0000E3
    case "adiaeresis": 0x0000E4
    case "aring": 0x0000E5
    case "ae": 0x0000E6
    case "ccedilla": 0x0000E7
    case "egrave": 0x0000E8
    case "eacute": 0x0000E9
    case "ecircumflex": 0x0000EA
    case "ediaeresis": 0x0000EB
    case "igrave": 0x0000EC
    case "iacute": 0x0000ED
    case "icircumflex": 0x0000EE
    case "idiaeresis": 0x0000EF
    case "eth": 0x0000F0
    case "ntilde": 0x0000F1
    case "ograve": 0x0000F2
    case "oacute": 0x0000F3
    case "ocircumflex": 0x0000F4
    case "otilde": 0x0000F5
    case "odiaeresis": 0x0000F6
    case "division": 0x0000F7
    case "oslash": 0x0000F8
    case "ugrave": 0x0000F9
    case "uacute": 0x0000FA
    case "ucircumflex": 0x0000FB
    case "udiaeresis": 0x0000FC
    case "yacute": 0x0000FD
    case "thorn": 0x0000FE
    case "ydiaeresis": 0x0000FF
    case "Aogonek": 0x0001A1
    case "breve": 0x0001A2
    case "Lstroke": 0x0001A3
    case "Lcaron": 0x0001A5
    case "Sacute": 0x0001A6
    case "Scaron": 0x0001A9
    case "Scedilla": 0x0001AA
    case "Tcaron": 0x0001AB
    case "Zacute": 0x0001AC
    case "Zcaron": 0x0001AE
    case "Zabovedot": 0x0001AF
    case "aogonek": 0x0001B1
    case "ogonek": 0x0001B2
    case "lstroke": 0x0001B3
    case "lcaron": 0x0001B5
    case "sacute": 0x0001B6
    case "caron": 0x0001B7
    case "scaron": 0x0001B9
    case "scedilla": 0x0001BA
    case "tcaron": 0x0001BB
    case "zacute": 0x0001BC
    case "doubleacute": 0x0001BD
    case "zcaron": 0x0001BE
    case "zabovedot": 0x0001BF
    case "Racute": 0x0001C0
    case "Abreve": 0x0001C3
    case "Lacute": 0x0001C5
    case "Cacute": 0x0001C6
    case "Ccaron": 0x0001C8
    case "Eogonek": 0x0001CA
    case "Ecaron": 0x0001CC
    case "Dcaron": 0x0001CF
    case "Dstroke": 0x0001D0
    case "Nacute": 0x0001D1
    case "Ncaron": 0x0001D2
    case "Odoubleacute": 0x0001D5
    case "Rcaron": 0x0001D8
    case "Uring": 0x0001D9
    case "Udoubleacute": 0x0001DB
    case "Tcedilla": 0x0001DE
    case "racute": 0x0001E0
    case "abreve": 0x0001E3
    case "lacute": 0x0001E5
    case "cacute": 0x0001E6
    case "ccaron": 0x0001E8
    case "eogonek": 0x0001EA
    case "ecaron": 0x0001EC
    case "dcaron": 0x0001EF
    case "dstroke": 0x0001F0
    case "nacute": 0x0001F1
    case "ncaron": 0x0001F2
    case "odoubleacute": 0x0001F5
    case "rcaron": 0x0001F8
    case "uring": 0x0001F9
    case "udoubleacute": 0x0001FB
    case "tcedilla": 0x0001FE
    case "abovedot": 0x0001FF
    // others
    case "Hstroke": 0x0002A1
    case "Hcircumflex": 0x0002A6
    case "Iabovedot": 0x0002A9
    case "Gbreve": 0x0002AB
    case "Jcircumflex": 0x0002AC
    case "hstroke": 0x0002B1
    case "hcircumflex": 0x0002B6
    case "idotless": 0x0002B9
    case "gbreve": 0x0002BB
    case "jcircumflex": 0x0002BC
    case "Cabovedot": 0x0002C5
    case "Ccircumflex": 0x0002C6
    case "Gabovedot": 0x0002D5
    case "Gcircumflex": 0x0002D8
    case "Ubreve": 0x0002DD
    case "Scircumflex": 0x0002DE
    case "cabovedot": 0x0002E5
    case "ccircumflex": 0x0002E6
    case "gabovedot": 0x0002F5
    case "gcircumflex": 0x0002F8
    case "ubreve": 0x0002FD
    case "scircumflex": 0x0002FE
    case "kappa": 0x0003A2
    case "kra": 0x0003A2
    case "Rcedilla": 0x0003A3
    case "Itilde": 0x0003A5
    case "Lcedilla": 0x0003A6
    case "Emacron": 0x0003AA
    case "Gcedilla": 0x0003AB
    case "Tslash": 0x0003AC
    case "rcedilla": 0x0003B3
    case "itilde": 0x0003B5
    case "lcedilla": 0x0003B6
    case "emacron": 0x0003BA
    case "gcedilla": 0x0003BB
    case "tslash": 0x0003BC
    case "ENG": 0x0003BD
    case "eng": 0x0003BF
    case "Amacron": 0x0003C0
    case "Iogonek": 0x0003C7
    case "Eabovedot": 0x0003CC
    case "Imacron": 0x0003CF
    case "Ncedilla": 0x0003D1
    case "Omacron": 0x0003D2
    case "Kcedilla": 0x0003D3
    case "Uogonek": 0x0003D9
    case "Utilde": 0x0003DD
    case "Umacron": 0x0003DE
    case "amacron": 0x0003E0
    case "iogonek": 0x0003E7
    case "eabovedot": 0x0003EC
    case "imacron": 0x0003EF
    case "ncedilla": 0x0003F1
    case "omacron": 0x0003F2
    case "kcedilla": 0x0003F3
    case "uogonek": 0x0003F9
    case "utilde": 0x0003FD
    case "umacron": 0x0003FE
    case "overline": 0x00047E
    case "kana_fullstop": 0x0004A1
    case "kana_openingbracket": 0x0004A2
    case "kana_closingbracket": 0x0004A3
    case "kana_comma": 0x0004A4
    case "kana_conjunctive": 0x0004A5
    case "kana_middledot": 0x0004A5
    case "kana_WO": 0x0004A6
    case "kana_a": 0x0004A7
    case "kana_i": 0x0004A8
    case "kana_u": 0x0004A9
    case "kana_e": 0x0004AA
    case "kana_o": 0x0004AB
    case "kana_ya": 0x0004AC
    case "kana_yu": 0x0004AD
    case "kana_yo": 0x0004AE
    case "kana_tsu": 0x0004AF
    case "kana_tu": 0x0004AF
    case "prolongedsound": 0x0004B0
    case "kana_A": 0x0004B1
    case "kana_I": 0x0004B2
    case "kana_U": 0x0004B3
    case "kana_E": 0x0004B4
    case "kana_O": 0x0004B5
    case "kana_KA": 0x0004B6
    case "kana_KI": 0x0004B7
    case "kana_KU": 0x0004B8
    case "kana_KE": 0x0004B9
    case "kana_KO": 0x0004BA
    case "kana_SA": 0x0004BB
    case "kana_SHI": 0x0004BC
    case "kana_SU": 0x0004BD
    case "kana_SE": 0x0004BE
    case "kana_SO": 0x0004BF
    case "kana_TA": 0x0004C0
    case "kana_CHI": 0x0004C1
    case "kana_TI": 0x0004C1
    case "kana_TSU": 0x0004C2
    case "kana_TU": 0x0004C2
    case "kana_TE": 0x0004C3
    case "kana_TO": 0x0004C4
    case "kana_NA": 0x0004C5
    case "kana_NI": 0x0004C6
    case "kana_NU": 0x0004C7
    case "kana_NE": 0x0004C8
    case "kana_NO": 0x0004C9
    case "kana_HA": 0x0004CA
    case "kana_HI": 0x0004CB
    case "kana_FU": 0x0004CC
    case "kana_HU": 0x0004CC
    case "kana_HE": 0x0004CD
    case "kana_HO": 0x0004CE
    case "kana_MA": 0x0004CF
    case "kana_MI": 0x0004D0
    case "kana_MU": 0x0004D1
    case "kana_ME": 0x0004D2
    case "kana_MO": 0x0004D3
    case "kana_YA": 0x0004D4
    case "kana_YU": 0x0004D5
    case "kana_YO": 0x0004D6
    case "kana_RA": 0x0004D7
    case "kana_RI": 0x0004D8
    case "kana_RU": 0x0004D9
    case "kana_RE": 0x0004DA
    case "kana_RO": 0x0004DB
    case "kana_WA": 0x0004DC
    case "kana_N": 0x0004DD
    case "voicedsound": 0x0004DE
    case "semivoicedsound": 0x0004DF
    case "Arabic_comma": 0x0005AC
    case "Arabic_semicolon": 0x0005BB
    case "Arabic_question_mark": 0x0005BF
    case "Arabic_hamza": 0x0005C1
    case "Arabic_maddaonalef": 0x0005C2
    case "Arabic_hamzaonalef": 0x0005C3
    case "Arabic_hamzaonwaw": 0x0005C4
    case "Arabic_hamzaunderalef": 0x0005C5
    case "Arabic_hamzaonyeh": 0x0005C6
    case "Arabic_alef": 0x0005C7
    case "Arabic_beh": 0x0005C8
    case "Arabic_tehmarbuta": 0x0005C9
    case "Arabic_teh": 0x0005CA
    case "Arabic_theh": 0x0005CB
    case "Arabic_jeem": 0x0005CC
    case "Arabic_hah": 0x0005CD
    case "Arabic_khah": 0x0005CE
    case "Arabic_dal": 0x0005CF
    case "Arabic_thal": 0x0005D0
    case "Arabic_ra": 0x0005D1
    case "Arabic_zain": 0x0005D2
    case "Arabic_seen": 0x0005D3
    case "Arabic_sheen": 0x0005D4
    case "Arabic_sad": 0x0005D5
    case "Arabic_dad": 0x0005D6
    case "Arabic_tah": 0x0005D7
    case "Arabic_zah": 0x0005D8
    case "Arabic_ain": 0x0005D9
    case "Arabic_ghain": 0x0005DA
    case "Arabic_tatweel": 0x0005E0
    case "Arabic_feh": 0x0005E1
    case "Arabic_qaf": 0x0005E2
    case "Arabic_kaf": 0x0005E3
    case "Arabic_lam": 0x0005E4
    case "Arabic_meem": 0x0005E5
    case "Arabic_noon": 0x0005E6
    case "Arabic_ha": 0x0005E7
    case "Arabic_heh": 0x0005E7
    case "Arabic_waw": 0x0005E8
    case "Arabic_alefmaksura": 0x0005E9
    case "Arabic_yeh": 0x0005EA
    case "Arabic_fathatan": 0x0005EB
    case "Arabic_dammatan": 0x0005EC
    case "Arabic_kasratan": 0x0005ED
    case "Arabic_fatha": 0x0005EE
    case "Arabic_damma": 0x0005EF
    case "Arabic_kasra": 0x0005F0
    case "Arabic_shadda": 0x0005F1
    case "Arabic_sukun": 0x0005F2
    case "Serbian_dje": 0x0006A1
    case "Macedonia_gje": 0x0006A2
    case "Cyrillic_io": 0x0006A3
    case "Ukrainian_ie": 0x0006A4
    case "Ukranian_je": 0x0006A4
    case "Macedonia_dse": 0x0006A5
    case "Ukrainian_i": 0x0006A6
    case "Ukranian_i": 0x0006A6
    case "Ukrainian_yi": 0x0006A7
    case "Ukranian_yi": 0x0006A7
    case "Cyrillic_je": 0x0006A8
    case "Serbian_je": 0x0006A8
    case "Cyrillic_lje": 0x0006A9
    case "Serbian_lje": 0x0006A9
    case "Cyrillic_nje": 0x0006AA
    case "Serbian_nje": 0x0006AA
    case "Serbian_tshe": 0x0006AB
    case "Macedonia_kje": 0x0006AC
    case "Byelorussian_shortu": 0x0006AE
    case "Cyrillic_dzhe": 0x0006AF
    case "Serbian_dze": 0x0006AF
    case "numerosign": 0x0006B0
    case "Serbian_DJE": 0x0006B1
    case "Macedonia_GJE": 0x0006B2
    case "Cyrillic_IO": 0x0006B3
    case "Ukrainian_IE": 0x0006B4
    case "Ukranian_JE": 0x0006B4
    case "Macedonia_DSE": 0x0006B5
    case "Ukrainian_I": 0x0006B6
    case "Ukranian_I": 0x0006B6
    case "Ukrainian_YI": 0x0006B7
    case "Ukranian_YI": 0x0006B7
    case "Cyrillic_JE": 0x0006B8
    case "Serbian_JE": 0x0006B8
    case "Cyrillic_LJE": 0x0006B9
    case "Serbian_LJE": 0x0006B9
    case "Cyrillic_NJE": 0x0006BA
    case "Serbian_NJE": 0x0006BA
    case "Serbian_TSHE": 0x0006BB
    case "Macedonia_KJE": 0x0006BC
    case "Byelorussian_SHORTU": 0x0006BE
    case "Cyrillic_DZHE": 0x0006BF
    case "Serbian_DZE": 0x0006BF
    case "Cyrillic_yu": 0x0006C0
    case "Cyrillic_a": 0x0006C1
    case "Cyrillic_be": 0x0006C2
    case "Cyrillic_tse": 0x0006C3
    case "Cyrillic_de": 0x0006C4
    case "Cyrillic_ie": 0x0006C5
    case "Cyrillic_ef": 0x0006C6
    case "Cyrillic_ghe": 0x0006C7
    case "Cyrillic_ha": 0x0006C8
    case "Cyrillic_i": 0x0006C9
    case "Cyrillic_shorti": 0x0006CA
    case "Cyrillic_ka": 0x0006CB
    case "Cyrillic_el": 0x0006CC
    case "Cyrillic_em": 0x0006CD
    case "Cyrillic_en": 0x0006CE
    case "Cyrillic_o": 0x0006CF
    case "Cyrillic_pe": 0x0006D0
    case "Cyrillic_ya": 0x0006D1
    case "Cyrillic_er": 0x0006D2
    case "Cyrillic_es": 0x0006D3
    case "Cyrillic_te": 0x0006D4
    case "Cyrillic_u": 0x0006D5
    case "Cyrillic_zhe": 0x0006D6
    case "Cyrillic_ve": 0x0006D7
    case "Cyrillic_softsign": 0x0006D8
    case "Cyrillic_yeru": 0x0006D9
    case "Cyrillic_ze": 0x0006DA
    case "Cyrillic_sha": 0x0006DB
    case "Cyrillic_e": 0x0006DC
    case "Cyrillic_shcha": 0x0006DD
    case "Cyrillic_che": 0x0006DE
    case "Cyrillic_hardsign": 0x0006DF
    case "Cyrillic_YU": 0x0006E0
    case "Cyrillic_A": 0x0006E1
    case "Cyrillic_BE": 0x0006E2
    case "Cyrillic_TSE": 0x0006E3
    case "Cyrillic_DE": 0x0006E4
    case "Cyrillic_IE": 0x0006E5
    case "Cyrillic_EF": 0x0006E6
    case "Cyrillic_GHE": 0x0006E7
    case "Cyrillic_HA": 0x0006E8
    case "Cyrillic_I": 0x0006E9
    case "Cyrillic_SHORTI": 0x0006EA
    case "Cyrillic_KA": 0x0006EB
    case "Cyrillic_EL": 0x0006EC
    case "Cyrillic_EM": 0x0006ED
    case "Cyrillic_EN": 0x0006EE
    case "Cyrillic_O": 0x0006EF
    case "Cyrillic_PE": 0x0006F0
    case "Cyrillic_YA": 0x0006F1
    case "Cyrillic_ER": 0x0006F2
    case "Cyrillic_ES": 0x0006F3
    case "Cyrillic_TE": 0x0006F4
    case "Cyrillic_U": 0x0006F5
    case "Cyrillic_ZHE": 0x0006F6
    case "Cyrillic_VE": 0x0006F7
    case "Cyrillic_SOFTSIGN": 0x0006F8
    case "Cyrillic_YERU": 0x0006F9
    case "Cyrillic_ZE": 0x0006FA
    case "Cyrillic_SHA": 0x0006FB
    case "Cyrillic_E": 0x0006FC
    case "Cyrillic_SHCHA": 0x0006FD
    case "Cyrillic_CHE": 0x0006FE
    case "Cyrillic_HARDSIGN": 0x0006FF
    case "Greek_ALPHAaccent": 0x0007A1
    case "Greek_EPSILONaccent": 0x0007A2
    case "Greek_ETAaccent": 0x0007A3
    case "Greek_IOTAaccent": 0x0007A4
    case "Greek_IOTAdieresis": 0x0007A5
    case "Greek_IOTAdiaeresis": 0x0007A5
    case "Greek_OMICRONaccent": 0x0007A7
    case "Greek_UPSILONaccent": 0x0007A8
    case "Greek_UPSILONdieresis": 0x0007A9
    case "Greek_OMEGAaccent": 0x0007AB
    case "Greek_accentdieresis": 0x0007AE
    case "Greek_horizbar": 0x0007AF
    case "Greek_alphaaccent": 0x0007B1
    case "Greek_epsilonaccent": 0x0007B2
    case "Greek_etaaccent": 0x0007B3
    case "Greek_iotaaccent": 0x0007B4
    case "Greek_iotadieresis": 0x0007B5
    case "Greek_iotaaccentdieresis": 0x0007B6
    case "Greek_omicronaccent": 0x0007B7
    case "Greek_upsilonaccent": 0x0007B8
    case "Greek_upsilondieresis": 0x0007B9
    case "Greek_upsilonaccentdieresis": 0x0007BA
    case "Greek_omegaaccent": 0x0007BB
    case "Greek_ALPHA": 0x0007C1
    case "Greek_BETA": 0x0007C2
    case "Greek_GAMMA": 0x0007C3
    case "Greek_DELTA": 0x0007C4
    case "Greek_EPSILON": 0x0007C5
    case "Greek_ZETA": 0x0007C6
    case "Greek_ETA": 0x0007C7
    case "Greek_THETA": 0x0007C8
    case "Greek_IOTA": 0x0007C9
    case "Greek_KAPPA": 0x0007CA
    case "Greek_LAMBDA": 0x0007CB
    case "Greek_LAMDA": 0x0007CB
    case "Greek_MU": 0x0007CC
    case "Greek_NU": 0x0007CD
    case "Greek_XI": 0x0007CE
    case "Greek_OMICRON": 0x0007CF
    case "Greek_PI": 0x0007D0
    case "Greek_RHO": 0x0007D1
    case "Greek_SIGMA": 0x0007D2
    case "Greek_TAU": 0x0007D4
    case "Greek_UPSILON": 0x0007D5
    case "Greek_PHI": 0x0007D6
    case "Greek_CHI": 0x0007D7
    case "Greek_PSI": 0x0007D8
    case "Greek_OMEGA": 0x0007D9
    case "Greek_alpha": 0x0007E1
    case "Greek_beta": 0x0007E2
    case "Greek_gamma": 0x0007E3
    case "Greek_delta": 0x0007E4
    case "Greek_epsilon": 0x0007E5
    case "Greek_zeta": 0x0007E6
    case "Greek_eta": 0x0007E7
    case "Greek_theta": 0x0007E8
    case "Greek_iota": 0x0007E9
    case "Greek_kappa": 0x0007EA
    case "Greek_lambda": 0x0007EB
    case "Greek_lamda": 0x0007EB
    case "Greek_mu": 0x0007EC
    case "Greek_nu": 0x0007ED
    case "Greek_xi": 0x0007EE
    case "Greek_omicron": 0x0007EF
    case "Greek_pi": 0x0007F0
    case "Greek_rho": 0x0007F1
    case "Greek_sigma": 0x0007F2
    case "Greek_finalsmallsigma": 0x0007F3
    case "Greek_tau": 0x0007F4
    case "Greek_upsilon": 0x0007F5
    case "Greek_phi": 0x0007F6
    case "Greek_chi": 0x0007F7
    case "Greek_psi": 0x0007F8
    case "Greek_omega": 0x0007F9
    case "leftradical": 0x0008A1
    case "topleftradical": 0x0008A2
    case "horizconnector": 0x0008A3
    case "topintegral": 0x0008A4
    case "botintegral": 0x0008A5
    case "vertconnector": 0x0008A6
    case "topleftsqbracket": 0x0008A7
    case "botleftsqbracket": 0x0008A8
    case "toprightsqbracket": 0x0008A9
    case "botrightsqbracket": 0x0008AA
    case "topleftparens": 0x0008AB
    case "botleftparens": 0x0008AC
    case "toprightparens": 0x0008AD
    case "botrightparens": 0x0008AE
    case "leftmiddlecurlybrace": 0x0008AF
    case "rightmiddlecurlybrace": 0x0008B0
    case "topleftsummation": 0x0008B1
    case "botleftsummation": 0x0008B2
    case "topvertsummationconnector": 0x0008B3
    case "botvertsummationconnector": 0x0008B4
    case "toprightsummation": 0x0008B5
    case "botrightsummation": 0x0008B6
    case "rightmiddlesummation": 0x0008B7
    case "lessthanequal": 0x0008BC
    case "notequal": 0x0008BD
    case "greaterthanequal": 0x0008BE
    case "integral": 0x0008BF
    case "therefore": 0x0008C0
    case "variation": 0x0008C1
    case "infinity": 0x0008C2
    case "nabla": 0x0008C5
    case "approximate": 0x0008C8
    case "similarequal": 0x0008C9
    case "ifonlyif": 0x0008CD
    case "implies": 0x0008CE
    case "identical": 0x0008CF
    case "radical": 0x0008D6
    case "includedin": 0x0008DA
    case "includes": 0x0008DB
    case "intersection": 0x0008DC
    case "union": 0x0008DD
    case "logicaland": 0x0008DE
    case "logicalor": 0x0008DF
    case "partialderivative": 0x0008EF
    case "function": 0x0008F6
    case "leftarrow": 0x0008FB
    case "uparrow": 0x0008FC
    case "rightarrow": 0x0008FD
    case "downarrow": 0x0008FE
    case "blank": 0x0009DF
    case "soliddiamond": 0x0009E0
    case "checkerboard": 0x0009E1
    case "ht": 0x0009E2
    case "ff": 0x0009E3
    case "cr": 0x0009E4
    case "lf": 0x0009E5
    case "nl": 0x0009E8
    case "vt": 0x0009E9
    case "lowrightcorner": 0x0009EA
    case "uprightcorner": 0x0009EB
    case "upleftcorner": 0x0009EC
    case "lowleftcorner": 0x0009ED
    case "crossinglines": 0x0009EE
    case "horizlinescan1": 0x0009EF
    case "horizlinescan3": 0x0009F0
    case "horizlinescan5": 0x0009F1
    case "horizlinescan7": 0x0009F2
    case "horizlinescan9": 0x0009F3
    case "leftt": 0x0009F4
    case "rightt": 0x0009F5
    case "bott": 0x0009F6
    case "topt": 0x0009F7
    case "vertbar": 0x0009F8
    case "emspace": 0x000AA1
    case "enspace": 0x000AA2
    case "em3space": 0x000AA3
    case "em4space": 0x000AA4
    case "digitspace": 0x000AA5
    case "punctspace": 0x000AA6
    case "thinspace": 0x000AA7
    case "hairspace": 0x000AA8
    case "emdash": 0x000AA9
    case "endash": 0x000AAA
    case "signifblank": 0x000AAC
    case "ellipsis": 0x000AAE
    case "doubbaselinedot": 0x000AAF
    case "onethird": 0x000AB0
    case "twothirds": 0x000AB1
    case "onefifth": 0x000AB2
    case "twofifths": 0x000AB3
    case "threefifths": 0x000AB4
    case "fourfifths": 0x000AB5
    case "onesixth": 0x000AB6
    case "fivesixths": 0x000AB7
    case "careof": 0x000AB8
    case "figdash": 0x000ABB
    case "leftanglebracket": 0x000ABC
    case "decimalpoint": 0x000ABD
    case "rightanglebracket": 0x000ABE
    case "marker": 0x000ABF
    case "oneeighth": 0x000AC3
    case "threeeighths": 0x000AC4
    case "fiveeighths": 0x000AC5
    case "seveneighths": 0x000AC6
    case "trademark": 0x000AC9
    case "signaturemark": 0x000ACA
    case "trademarkincircle": 0x000ACB
    case "leftopentriangle": 0x000ACC
    case "rightopentriangle": 0x000ACD
    case "emopencircle": 0x000ACE
    case "emopenrectangle": 0x000ACF
    case "leftsinglequotemark": 0x000AD0
    case "rightsinglequotemark": 0x000AD1
    case "leftdoublequotemark": 0x000AD2
    case "rightdoublequotemark": 0x000AD3
    case "prescription": 0x000AD4
    case "minutes": 0x000AD6
    case "seconds": 0x000AD7
    case "latincross": 0x000AD9
    case "hexagram": 0x000ADA
    case "filledrectbullet": 0x000ADB
    case "filledlefttribullet": 0x000ADC
    case "filledrighttribullet": 0x000ADD
    case "emfilledcircle": 0x000ADE
    case "emfilledrect": 0x000ADF
    case "enopencircbullet": 0x000AE0
    case "enopensquarebullet": 0x000AE1
    case "openrectbullet": 0x000AE2
    case "opentribulletup": 0x000AE3
    case "opentribulletdown": 0x000AE4
    case "openstar": 0x000AE5
    case "enfilledcircbullet": 0x000AE6
    case "enfilledsqbullet": 0x000AE7
    case "filledtribulletup": 0x000AE8
    case "filledtribulletdown": 0x000AE9
    case "leftpointer": 0x000AEA
    case "rightpointer": 0x000AEB
    case "club": 0x000AEC
    case "diamond": 0x000AED
    case "heart": 0x000AEE
    case "maltesecross": 0x000AF0
    case "dagger": 0x000AF1
    case "doubledagger": 0x000AF2
    case "checkmark": 0x000AF3
    case "ballotcross": 0x000AF4
    case "musicalsharp": 0x000AF5
    case "musicalflat": 0x000AF6
    case "malesymbol": 0x000AF7
    case "femalesymbol": 0x000AF8
    case "telephone": 0x000AF9
    case "telephonerecorder": 0x000AFA
    case "phonographcopyright": 0x000AFB
    case "caret": 0x000AFC
    case "singlelowquotemark": 0x000AFD
    case "doublelowquotemark": 0x000AFE
    case "cursor": 0x000AFF
    case "leftcaret": 0x000BA3
    case "rightcaret": 0x000BA6
    case "downcaret": 0x000BA8
    case "upcaret": 0x000BA9
    case "overbar": 0x000BC0
    case "downtack": 0x000BC2
    case "upshoe": 0x000BC3
    case "downstile": 0x000BC4
    case "underbar": 0x000BC6
    case "jot": 0x000BCA
    case "quad": 0x000BCC
    case "uptack": 0x000BCE
    case "circle": 0x000BCF
    case "upstile": 0x000BD3
    case "downshoe": 0x000BD6
    case "rightshoe": 0x000BD8
    case "leftshoe": 0x000BDA
    case "lefttack": 0x000BDC
    case "righttack": 0x000BFC
    case "hebrew_doublelowline": 0x000CDF
    case "hebrew_aleph": 0x000CE0
    case "hebrew_bet": 0x000CE1
    case "hebrew_beth": 0x000CE1
    case "hebrew_gimel": 0x000CE2
    case "hebrew_gimmel": 0x000CE2
    case "hebrew_dalet": 0x000CE3
    case "hebrew_daleth": 0x000CE3
    case "hebrew_he": 0x000CE4
    case "hebrew_waw": 0x000CE5
    case "hebrew_zain": 0x000CE6
    case "hebrew_zayin": 0x000CE6
    case "hebrew_chet": 0x000CE7
    case "hebrew_het": 0x000CE7
    case "hebrew_tet": 0x000CE8
    case "hebrew_teth": 0x000CE8
    case "hebrew_yod": 0x000CE9
    case "hebrew_finalkaph": 0x000CEA
    case "hebrew_kaph": 0x000CEB
    case "hebrew_lamed": 0x000CEC
    case "hebrew_finalmem": 0x000CED
    case "hebrew_mem": 0x000CEE
    case "hebrew_finalnun": 0x000CEF
    case "hebrew_nun": 0x000CF0
    case "hebrew_samech": 0x000CF1
    case "hebrew_samekh": 0x000CF1
    case "hebrew_ayin": 0x000CF2
    case "hebrew_finalpe": 0x000CF3
    case "hebrew_pe": 0x000CF4
    case "hebrew_finalzade": 0x000CF5
    case "hebrew_finalzadi": 0x000CF5
    case "hebrew_zade": 0x000CF6
    case "hebrew_zadi": 0x000CF6
    case "hebrew_kuf": 0x000CF7
    case "hebrew_qoph": 0x000CF7
    case "hebrew_resh": 0x000CF8
    case "hebrew_shin": 0x000CF9
    case "hebrew_taf": 0x000CFA
    case "hebrew_taw": 0x000CFA
    case "Thai_kokai": 0x000DA1
    case "Thai_khokhai": 0x000DA2
    case "Thai_khokhuat": 0x000DA3
    case "Thai_khokhwai": 0x000DA4
    case "Thai_khokhon": 0x000DA5
    case "Thai_khorakhang": 0x000DA6
    case "Thai_ngongu": 0x000DA7
    case "Thai_chochan": 0x000DA8
    case "Thai_choching": 0x000DA9
    case "Thai_chochang": 0x000DAA
    case "Thai_soso": 0x000DAB
    case "Thai_chochoe": 0x000DAC
    case "Thai_yoying": 0x000DAD
    case "Thai_dochada": 0x000DAE
    case "Thai_topatak": 0x000DAF
    case "Thai_thothan": 0x000DB0
    case "Thai_thonangmontho": 0x000DB1
    case "Thai_thophuthao": 0x000DB2
    case "Thai_nonen": 0x000DB3
    case "Thai_dodek": 0x000DB4
    case "Thai_totao": 0x000DB5
    case "Thai_thothung": 0x000DB6
    case "Thai_thothahan": 0x000DB7
    case "Thai_thothong": 0x000DB8
    case "Thai_nonu": 0x000DB9
    case "Thai_bobaimai": 0x000DBA
    case "Thai_popla": 0x000DBB
    case "Thai_phophung": 0x000DBC
    case "Thai_fofa": 0x000DBD
    case "Thai_phophan": 0x000DBE
    case "Thai_fofan": 0x000DBF
    case "Thai_phosamphao": 0x000DC0
    case "Thai_moma": 0x000DC1
    case "Thai_yoyak": 0x000DC2
    case "Thai_rorua": 0x000DC3
    case "Thai_ru": 0x000DC4
    case "Thai_loling": 0x000DC5
    case "Thai_lu": 0x000DC6
    case "Thai_wowaen": 0x000DC7
    case "Thai_sosala": 0x000DC8
    case "Thai_sorusi": 0x000DC9
    case "Thai_sosua": 0x000DCA
    case "Thai_hohip": 0x000DCB
    case "Thai_lochula": 0x000DCC
    case "Thai_oang": 0x000DCD
    case "Thai_honokhuk": 0x000DCE
    case "Thai_paiyannoi": 0x000DCF
    case "Thai_saraa": 0x000DD0
    case "Thai_maihanakat": 0x000DD1
    case "Thai_saraaa": 0x000DD2
    case "Thai_saraam": 0x000DD3
    case "Thai_sarai": 0x000DD4
    case "Thai_saraii": 0x000DD5
    case "Thai_saraue": 0x000DD6
    case "Thai_sarauee": 0x000DD7
    case "Thai_sarau": 0x000DD8
    case "Thai_sarauu": 0x000DD9
    case "Thai_phinthu": 0x000DDA
    case "Thai_maihanakat_maitho": 0x000DDE
    case "Thai_baht": 0x000DDF
    case "Thai_sarae": 0x000DE0
    case "Thai_saraae": 0x000DE1
    case "Thai_sarao": 0x000DE2
    case "Thai_saraaimaimuan": 0x000DE3
    case "Thai_saraaimaimalai": 0x000DE4
    case "Thai_lakkhangyao": 0x000DE5
    case "Thai_maiyamok": 0x000DE6
    case "Thai_maitaikhu": 0x000DE7
    case "Thai_maiek": 0x000DE8
    case "Thai_maitho": 0x000DE9
    case "Thai_maitri": 0x000DEA
    case "Thai_maichattawa": 0x000DEB
    case "Thai_thanthakhat": 0x000DEC
    case "Thai_nikhahit": 0x000DED
    case "Thai_leksun": 0x000DF0
    case "Thai_leknung": 0x000DF1
    case "Thai_leksong": 0x000DF2
    case "Thai_leksam": 0x000DF3
    case "Thai_leksi": 0x000DF4
    case "Thai_lekha": 0x000DF5
    case "Thai_lekhok": 0x000DF6
    case "Thai_lekchet": 0x000DF7
    case "Thai_lekpaet": 0x000DF8
    case "Thai_lekkao": 0x000DF9
    case "Hangul_Kiyeog": 0x000EA1
    case "Hangul_SsangKiyeog": 0x000EA2
    case "Hangul_KiyeogSios": 0x000EA3
    case "Hangul_Nieun": 0x000EA4
    case "Hangul_NieunJieuj": 0x000EA5
    case "Hangul_NieunHieuh": 0x000EA6
    case "Hangul_Dikeud": 0x000EA7
    case "Hangul_SsangDikeud": 0x000EA8
    case "Hangul_Rieul": 0x000EA9
    case "Hangul_RieulKiyeog": 0x000EAA
    case "Hangul_RieulMieum": 0x000EAB
    case "Hangul_RieulPieub": 0x000EAC
    case "Hangul_RieulSios": 0x000EAD
    case "Hangul_RieulTieut": 0x000EAE
    case "Hangul_RieulPhieuf": 0x000EAF
    case "Hangul_RieulHieuh": 0x000EB0
    case "Hangul_Mieum": 0x000EB1
    case "Hangul_Pieub": 0x000EB2
    case "Hangul_SsangPieub": 0x000EB3
    case "Hangul_PieubSios": 0x000EB4
    case "Hangul_Sios": 0x000EB5
    case "Hangul_SsangSios": 0x000EB6
    case "Hangul_Ieung": 0x000EB7
    case "Hangul_Jieuj": 0x000EB8
    case "Hangul_SsangJieuj": 0x000EB9
    case "Hangul_Cieuc": 0x000EBA
    case "Hangul_Khieuq": 0x000EBB
    case "Hangul_Tieut": 0x000EBC
    case "Hangul_Phieuf": 0x000EBD
    case "Hangul_Hieuh": 0x000EBE
    case "Hangul_A": 0x000EBF
    case "Hangul_AE": 0x000EC0
    case "Hangul_YA": 0x000EC1
    case "Hangul_YAE": 0x000EC2
    case "Hangul_EO": 0x000EC3
    case "Hangul_E": 0x000EC4
    case "Hangul_YEO": 0x000EC5
    case "Hangul_YE": 0x000EC6
    case "Hangul_O": 0x000EC7
    case "Hangul_WA": 0x000EC8
    case "Hangul_WAE": 0x000EC9
    case "Hangul_OE": 0x000ECA
    case "Hangul_YO": 0x000ECB
    case "Hangul_U": 0x000ECC
    case "Hangul_WEO": 0x000ECD
    case "Hangul_WE": 0x000ECE
    case "Hangul_WI": 0x000ECF
    case "Hangul_YU": 0x000ED0
    case "Hangul_EU": 0x000ED1
    case "Hangul_YI": 0x000ED2
    case "Hangul_I": 0x000ED3
    case "Hangul_J_Kiyeog": 0x000ED4
    case "Hangul_J_SsangKiyeog": 0x000ED5
    case "Hangul_J_KiyeogSios": 0x000ED6
    case "Hangul_J_Nieun": 0x000ED7
    case "Hangul_J_NieunJieuj": 0x000ED8
    case "Hangul_J_NieunHieuh": 0x000ED9
    case "Hangul_J_Dikeud": 0x000EDA
    case "Hangul_J_Rieul": 0x000EDB
    case "Hangul_J_RieulKiyeog": 0x000EDC
    case "Hangul_J_RieulMieum": 0x000EDD
    case "Hangul_J_RieulPieub": 0x000EDE
    case "Hangul_J_RieulSios": 0x000EDF
    case "Hangul_J_RieulTieut": 0x000EE0
    case "Hangul_J_RieulPhieuf": 0x000EE1
    case "Hangul_J_RieulHieuh": 0x000EE2
    case "Hangul_J_Mieum": 0x000EE3
    case "Hangul_J_Pieub": 0x000EE4
    case "Hangul_J_PieubSios": 0x000EE5
    case "Hangul_J_Sios": 0x000EE6
    case "Hangul_J_SsangSios": 0x000EE7
    case "Hangul_J_Ieung": 0x000EE8
    case "Hangul_J_Jieuj": 0x000EE9
    case "Hangul_J_Cieuc": 0x000EEA
    case "Hangul_J_Khieuq": 0x000EEB
    case "Hangul_J_Tieut": 0x000EEC
    case "Hangul_J_Phieuf": 0x000EED
    case "Hangul_J_Hieuh": 0x000EEE
    case "Hangul_RieulYeorinHieuh": 0x000EEF
    case "Hangul_SunkyeongeumMieum": 0x000EF0
    case "Hangul_SunkyeongeumPieub": 0x000EF1
    case "Hangul_PanSios": 0x000EF2
    case "Hangul_KkogjiDalrinIeung": 0x000EF3
    case "Hangul_SunkyeongeumPhieuf": 0x000EF4
    case "Hangul_YeorinHieuh": 0x000EF5
    case "Hangul_AraeA": 0x000EF6
    case "Hangul_AraeAE": 0x000EF7
    case "Hangul_J_PanSios": 0x000EF8
    case "Hangul_J_KkogjiDalrinIeung": 0x000EF9
    case "Hangul_J_YeorinHieuh": 0x000EFA
    case "Korean_Won": 0x000EFF
    case "OE": 0x0013BC
    case "oe": 0x0013BD
    case "Ydiaeresis": 0x0013BE
    case "EcuSign": 0x0020A0
    case "ColonSign": 0x0020A1
    case "CruzeiroSign": 0x0020A2
    case "FFrancSign": 0x0020A3
    case "LiraSign": 0x0020A4
    case "MillSign": 0x0020A5
    case "NairaSign": 0x0020A6
    case "PesetaSign": 0x0020A7
    case "RupeeSign": 0x0020A8
    case "WonSign": 0x0020A9
    case "NewSheqelSign": 0x0020AA
    case "DongSign": 0x0020AB
    case "EuroSign": 0x0020AC
    case "3270_Duplicate": 0x00FD01
    case "3270_FieldMark": 0x00FD02
    case "3270_Right2": 0x00FD03
    case "3270_Left2": 0x00FD04
    case "3270_BackTab": 0x00FD05
    case "3270_EraseEOF": 0x00FD06
    case "3270_EraseInput": 0x00FD07
    case "3270_Reset": 0x00FD08
    case "3270_Quit": 0x00FD09
    case "3270_PA1": 0x00FD0A
    case "3270_PA2": 0x00FD0B
    case "3270_PA3": 0x00FD0C
    case "3270_Test": 0x00FD0D
    case "3270_Attn": 0x00FD0E
    case "3270_CursorBlink": 0x00FD0F
    case "3270_AltCursor": 0x00FD10
    case "3270_KeyClick": 0x00FD11
    case "3270_Jump": 0x00FD12
    case "3270_Ident": 0x00FD13
    case "3270_Rule": 0x00FD14
    case "3270_Copy": 0x00FD15
    case "3270_Play": 0x00FD16
    case "3270_Setup": 0x00FD17
    case "3270_Record": 0x00FD18
    case "3270_ChangeScreen": 0x00FD19
    case "3270_DeleteWord": 0x00FD1A
    case "3270_ExSelect": 0x00FD1B
    case "3270_CursorSelect": 0x00FD1C
    case "3270_PrintScreen": 0x00FD1D
    case "3270_Enter": 0x00FD1E
    case "ISO_Lock": 0x00FE01
    case "ISO_Level2_Latch": 0x00FE02
    case "ISO_Level3_Shift": 0x00FE03
    case "ISO_Level3_Latch": 0x00FE04
    case "ISO_Level3_Lock": 0x00FE05
    case "ISO_Group_Latch": 0x00FE06
    case "ISO_Group_Lock": 0x00FE07
    case "ISO_Next_Group": 0x00FE08
    case "ISO_Next_Group_Lock": 0x00FE09
    case "ISO_Prev_Group": 0x00FE0A
    case "ISO_Prev_Group_Lock": 0x00FE0B
    case "ISO_First_Group": 0x00FE0C
    case "ISO_First_Group_Lock": 0x00FE0D
    case "ISO_Last_Group": 0x00FE0E
    case "ISO_Last_Group_Lock": 0x00FE0F
    case "ISO_Left_Tab": 0x00FE20
    case "ISO_Move_Line_Up": 0x00FE21
    case "ISO_Move_Line_Down": 0x00FE22
    case "ISO_Partial_Line_Up": 0x00FE23
    case "ISO_Partial_Line_Down": 0x00FE24
    case "ISO_Partial_Space_Left": 0x00FE25
    case "ISO_Partial_Space_Right": 0x00FE26
    case "ISO_Set_Margin_Left": 0x00FE27
    case "ISO_Set_Margin_Right": 0x00FE28
    case "ISO_Release_Margin_Left": 0x00FE29
    case "ISO_Release_Margin_Right": 0x00FE2A
    case "ISO_Release_Both_Margins": 0x00FE2B
    case "ISO_Fast_Cursor_Left": 0x00FE2C
    case "ISO_Fast_Cursor_Right": 0x00FE2D
    case "ISO_Fast_Cursor_Up": 0x00FE2E
    case "ISO_Fast_Cursor_Down": 0x00FE2F
    case "ISO_Continuous_Underline": 0x00FE30
    case "ISO_Discontinuous_Underline": 0x00FE31
    case "ISO_Emphasize": 0x00FE32
    case "ISO_Center_Object": 0x00FE33
    case "ISO_Enter": 0x00FE34
    case "dead_grave": 0x00FE50
    case "dead_acute": 0x00FE51
    case "dead_circumflex": 0x00FE52
    case "dead_tilde": 0x00FE53
    case "dead_macron": 0x00FE54
    case "dead_breve": 0x00FE55
    case "dead_abovedot": 0x00FE56
    case "dead_diaeresis": 0x00FE57
    case "dead_abovering": 0x00FE58
    case "dead_doubleacute": 0x00FE59
    case "dead_caron": 0x00FE5A
    case "dead_cedilla": 0x00FE5B
    case "dead_ogonek": 0x00FE5C
    case "dead_iota": 0x00FE5D
    case "dead_voiced_sound": 0x00FE5E
    case "dead_semivoiced_sound": 0x00FE5F
    case "dead_belowdot": 0x00FE60
    case "dead_hook": 0x00FE61
    case "dead_horn": 0x00FE62
    // auxialiary
    case "AccessX_Enable": 0x00FE70
    case "AccessX_Feedback_Enable": 0x00FE71
    case "RepeatKeys_Enable": 0x00FE72
    case "SlowKeys_Enable": 0x00FE73
    case "BounceKeys_Enable": 0x00FE74
    case "StickyKeys_Enable": 0x00FE75
    case "MouseKeys_Enable": 0x00FE76
    case "MouseKeys_Accel_Enable": 0x00FE77
    case "Overlay1_Enable": 0x00FE78
    case "Overlay2_Enable": 0x00FE79
    case "AudibleBell_Enable": 0x00FE7A
    case "First_Virtual_Screen": 0x00FED0
    case "Prev_Virtual_Screen": 0x00FED1
    case "Next_Virtual_Screen": 0x00FED2
    case "Last_Virtual_Screen": 0x00FED4
    case "Terminate_Server": 0x00FED5
    case "Pointer_Left": 0x00FEE0
    case "Pointer_Right": 0x00FEE1
    case "Pointer_Up": 0x00FEE2
    case "Pointer_Down": 0x00FEE3
    case "Pointer_UpLeft": 0x00FEE4
    case "Pointer_UpRight": 0x00FEE5
    case "Pointer_DownLeft": 0x00FEE6
    case "Pointer_DownRight": 0x00FEE7
    case "Pointer_Button_Dflt": 0x00FEE8
    case "Pointer_Button1": 0x00FEE9
    case "Pointer_Button2": 0x00FEEA
    case "Pointer_Button3": 0x00FEEB
    case "Pointer_Button4": 0x00FEEC
    case "Pointer_Button5": 0x00FEED
    case "Pointer_DblClick_Dflt": 0x00FEEE
    case "Pointer_DblClick1": 0x00FEEF
    case "Pointer_DblClick2": 0x00FEF0
    case "Pointer_DblClick3": 0x00FEF1
    case "Pointer_DblClick4": 0x00FEF2
    case "Pointer_DblClick5": 0x00FEF3
    case "Pointer_Drag_Dflt": 0x00FEF4
    case "Pointer_Drag1": 0x00FEF5
    case "Pointer_Drag2": 0x00FEF6
    case "Pointer_Drag3": 0x00FEF7
    case "Pointer_Drag4": 0x00FEF8
    case "Pointer_EnableKeys": 0x00FEF9
    case "Pointer_Accelerate": 0x00FEFA
    case "Pointer_DfltBtnNext": 0x00FEFB
    case "Pointer_DfltBtnPrev": 0x00FEFC
    case "Pointer_Drag5": 0x00FEFD
    case "BackSpace": 0x00FF08
    case "Tab": 0x00FF09
    case "Linefeed": 0x00FF0A
    case "Clear": 0x00FF0B
    case "Return": 0x00FF0D
    case "Pause": 0x00FF13
    case "Scroll_Lock": 0x00FF14
    case "Sys_Req": 0x00FF15
    case "Escape": 0x00FF1B
    case "Multi_key": 0x00FF20
    case "Kanji": 0x00FF21
    case "Muhenkan": 0x00FF22
    case "Henkan": 0x00FF23
    case "Henkan_Mode": 0x00FF23
    case "Romaji": 0x00FF24
    case "Hiragana": 0x00FF25
    case "Katakana": 0x00FF26
    case "Hiragana_Katakana": 0x00FF27
    case "Zenkaku": 0x00FF28
    case "Hankaku": 0x00FF29
    case "Zenkaku_Hankaku": 0x00FF2A
    case "Touroku": 0x00FF2B
    case "Massyo": 0x00FF2C
    case "Kana_Lock": 0x00FF2D
    case "Kana_Shift": 0x00FF2E
    case "Eisu_Shift": 0x00FF2F
    case "Eisu_toggle": 0x00FF30
    case "Hangul": 0x00FF31
    case "Hangul_Start": 0x00FF32
    case "Hangul_End": 0x00FF33
    case "Hangul_Hanja": 0x00FF34
    case "Hangul_Jamo": 0x00FF35
    case "Hangul_Romaja": 0x00FF36
    case "Codeinput": 0x00FF37
    case "Hangul_Jeonja": 0x00FF38
    case "Hangul_Banja": 0x00FF39
    case "Hangul_PreHanja": 0x00FF3A
    case "Hangul_PostHanja": 0x00FF3B
    case "SingleCandidate": 0x00FF3C
    case "MultipleCandidate": 0x00FF3D
    case "PreviousCandidate": 0x00FF3E
    case "Hangul_Special": 0x00FF3F
    case "Home": 0x00FF50
    case "Left": 0x00FF51
    case "Up": 0x00FF52
    case "Right": 0x00FF53
    case "Down": 0x00FF54
    case "Page_Up": 0x00FF55
    case "Prior": 0x00FF55
    case "Page_Down": 0x00FF56
    case "Next": 0x00FF56
    case "End": 0x00FF57
    case "Begin": 0x00FF58
    case "Select": 0x00FF60
    case "Print": 0x00FF61
    case "Execute": 0x00FF62
    case "Insert": 0x00FF63
    case "Undo": 0x00FF65
    case "Redo": 0x00FF66
    case "Menu": 0x00FF67
    case "Find": 0x00FF68
    case "Cancel": 0x00FF69
    case "Help": 0x00FF6A
    case "Break": 0x00FF6B
    case "Arabic_switch": 0x00FF7E
    case "Greek_switch": 0x00FF7E
    case "Hangul_switch": 0x00FF7E
    case "Hebrew_switch": 0x00FF7E
    case "ISO_Group_Shift": 0x00FF7E
    case "Mode_switch": 0x00FF7E
    case "kana_switch": 0x00FF7E
    case "script_switch": 0x00FF7E
    case "Num_Lock": 0x00FF7F
    case "KP_Space": 0x00FF80
    case "KP_Tab": 0x00FF89
    case "KP_Enter": 0x00FF8D
    case "KP_F1": 0x00FF91
    case "KP_F2": 0x00FF92
    case "KP_F3": 0x00FF93
    case "KP_F4": 0x00FF94
    case "KP_Home": 0x00FF95
    case "KP_Left": 0x00FF96
    case "KP_Up": 0x00FF97
    case "KP_Right": 0x00FF98
    case "KP_Down": 0x00FF99
    case "KP_Page_Up": 0x00FF9A
    case "KP_Prior": 0x00FF9A
    case "KP_Page_Down": 0x00FF9B
    case "KP_Next": 0x00FF9B
    case "KP_End": 0x00FF9C
    case "KP_Begin": 0x00FF9D
    case "KP_Insert": 0x00FF9E
    case "KP_Delete": 0x00FF9F
    case "KP_Multiply": 0x00FFAA
    case "KP_Add": 0x00FFAB
    case "KP_Separator": 0x00FFAC
    case "KP_Subtract": 0x00FFAD
    case "KP_Decimal": 0x00FFAE
    case "KP_Divide": 0x00FFAF
    case "KP_0": 0x00FFB0
    case "KP_1": 0x00FFB1
    case "KP_2": 0x00FFB2
    case "KP_3": 0x00FFB3
    case "KP_4": 0x00FFB4
    case "KP_5": 0x00FFB5
    case "KP_6": 0x00FFB6
    case "KP_7": 0x00FFB7
    case "KP_8": 0x00FFB8
    case "KP_9": 0x00FFB9
    case "KP_Equal": 0x00FFBD
    case "F1": 0x00FFBE
    case "F2": 0x00FFBF
    case "F3": 0x00FFC0
    case "F4": 0x00FFC1
    case "F5": 0x00FFC2
    case "F6": 0x00FFC3
    case "F7": 0x00FFC4
    case "F8": 0x00FFC5
    case "F9": 0x00FFC6
    case "F10": 0x00FFC7
    case "F11": 0x00FFC8
    case "F12": 0x00FFC9
    case "F13": 0x00FFCA
    case "F14": 0x00FFCB
    case "F15": 0x00FFCC
    case "F16": 0x00FFCD
    case "F17": 0x00FFCE
    case "F18": 0x00FFCF
    case "F19": 0x00FFD0
    case "F20": 0x00FFD1
    case "F21": 0x00FFD2
    case "F22": 0x00FFD3
    case "F23": 0x00FFD4
    case "F24": 0x00FFD5
    case "F25": 0x00FFD6
    case "F26": 0x00FFD7
    case "F27": 0x00FFD8
    case "F28": 0x00FFD9
    case "F29": 0x00FFDA
    case "F30": 0x00FFDB
    case "F31": 0x00FFDC
    case "F32": 0x00FFDD
    case "F33": 0x00FFDE
    case "F34": 0x00FFDF
    case "F35": 0x00FFE0
    case "Shift_L": 0x00FFE1
    case "Shift_R": 0x00FFE2
    case "Control_L": 0x00FFE3
    case "Control_R": 0x00FFE4
    case "Caps_Lock": 0x00FFE5
    case "Shift_Lock": 0x00FFE6
    case "Meta_L": 0x00FFE7
    case "Meta_R": 0x00FFE8
    case "Alt_L": 0x00FFE9
    case "Alt_R": 0x00FFEA
    case "Super_L": 0x00FFEB
    case "Super_R": 0x00FFEC
    case "Hyper_L": 0x00FFED
    case "Hyper_R": 0x00FFEE
    case "Delete": 0x00FFFF
    default: 0xFFFFFF
    }
  }
}  // RimeKeycode
