import AppKit
import Carbon

struct RimeModifiers: OptionSet, Sendable {
  let rawValue: CInt

  static let Shift = RimeModifiers(rawValue: 1 << 0)
  static let Lock = RimeModifiers(rawValue: 1 << 1)
  static let Control = RimeModifiers(rawValue: 1 << 2)
  static let Alt = RimeModifiers(rawValue: 1 << 3)
  static let Handled = RimeModifiers(rawValue: 1 << 24)
  static let Ignored = RimeModifiers(rawValue: 1 << 25)
  static let Super = RimeModifiers(rawValue: 1 << 26)
  static let Hyper = RimeModifiers(rawValue: 1 << 27)
  static let Meta = RimeModifiers(rawValue: 1 << 28)
  static let Release = RimeModifiers(rawValue: 1 << 30)
  static let ModifierMask = RimeModifiers(rawValue: 0x5F001FFF)

  init(rawValue: CInt) { self.rawValue = rawValue }

  init(macModifiers: NSEvent.ModifierFlags) {
    var modifiers: RimeModifiers = []
    if macModifiers.contains(.shift) { modifiers.insert(.Shift) }
    if macModifiers.contains(.capsLock) { modifiers.insert(.Lock) }
    if macModifiers.contains(.control) { modifiers.insert(.Control) }
    if macModifiers.contains(.option) { modifiers.insert(.Alt) }
    if macModifiers.contains(.command) { modifiers.insert(.Super) }
    if macModifiers.contains(.function) { modifiers.insert(.Hyper) }
    self = modifiers
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
let kVK_Enter_Powerbook: Int = 0x34
// pc keyboard
let kVK_PC_Application: Int = 0x6E
let kVK_PC_Power: Int = 0x7F

enum RimeKeycode: CInt, Sendable {
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

  init(macKeycode: Int) {
    switch macKeycode {
    case kVK_CapsLock: self = .XK_Caps_Lock
    case kVK_Command: self = .XK_Super_L // XK_Meta_L?
    case kVK_RightCommand: self = .XK_Super_R // XK_Meta_R?
    case kVK_Control: self = .XK_Control_L
    case kVK_RightControl: self = .XK_Control_R
    case kVK_Function: self = .XK_Hyper_L
    case kVK_Option: self = .XK_Alt_L
    case kVK_RightOption: self = .XK_Alt_R
    case kVK_Shift: self = .XK_Shift_L
    case kVK_RightShift: self = .XK_Shift_R
    // special
    case kVK_Delete: self = .XK_BackSpace
    case kVK_Enter_Powerbook: self = .XK_ISO_Enter
    case kVK_Escape: self = .XK_Escape
    case kVK_ForwardDelete: self = .XK_Delete
    case kVK_Help: self = .XK_Help
    case kVK_Return: self = .XK_Return
    case kVK_Space: self = .XK_space
    case kVK_Tab: self = .XK_Tab
    // function
    case kVK_F1: self = .XK_F1
    case kVK_F2: self = .XK_F2
    case kVK_F3: self = .XK_F3
    case kVK_F4: self = .XK_F4
    case kVK_F5: self = .XK_F5
    case kVK_F6: self = .XK_F6
    case kVK_F7: self = .XK_F7
    case kVK_F8: self = .XK_F8
    case kVK_F9: self = .XK_F9
    case kVK_F10: self = .XK_F10
    case kVK_F11: self = .XK_F11
    case kVK_F12: self = .XK_F12
    case kVK_F13: self = .XK_F13
    case kVK_F14: self = .XK_F14
    case kVK_F15: self = .XK_F15
    case kVK_F16: self = .XK_F16
    case kVK_F17: self = .XK_F17
    case kVK_F18: self = .XK_F18
    case kVK_F19: self = .XK_F19
    case kVK_F20: self = .XK_F20
    // cursor
    case kVK_UpArrow: self = .XK_Up
    case kVK_DownArrow: self = .XK_Down
    case kVK_LeftArrow: self = .XK_Left
    case kVK_RightArrow: self = .XK_Right
    case kVK_PageUp: self = .XK_Page_Up
    case kVK_PageDown: self = .XK_Page_Down
    case kVK_Home: self = .XK_Home
    case kVK_End: self = .XK_End
    // keypad
    case kVK_ANSI_Keypad0: self = .XK_KP_0
    case kVK_ANSI_Keypad1: self = .XK_KP_1
    case kVK_ANSI_Keypad2: self = .XK_KP_2
    case kVK_ANSI_Keypad3: self = .XK_KP_3
    case kVK_ANSI_Keypad4: self = .XK_KP_4
    case kVK_ANSI_Keypad5: self = .XK_KP_5
    case kVK_ANSI_Keypad6: self = .XK_KP_6
    case kVK_ANSI_Keypad7: self = .XK_KP_7
    case kVK_ANSI_Keypad8: self = .XK_KP_8
    case kVK_ANSI_Keypad9: self = .XK_KP_9
    case kVK_ANSI_KeypadEnter: self = .XK_KP_Enter
    case kVK_ANSI_KeypadClear: self = .XK_Clear
    case kVK_ANSI_KeypadDecimal: self = .XK_KP_Decimal
    case kVK_ANSI_KeypadEquals: self = .XK_KP_Equal
    case kVK_ANSI_KeypadMinus: self = .XK_KP_Subtract
    case kVK_ANSI_KeypadMultiply: self = .XK_KP_Multiply
    case kVK_ANSI_KeypadPlus: self = .XK_KP_Add
    case kVK_ANSI_KeypadDivide: self = .XK_KP_Divide
    // pc keyboard
    case kVK_PC_Application: self = .XK_Menu
    // JIS keyboard
    case kVK_JIS_KeypadComma: self = .XK_KP_Separator
    case kVK_JIS_Eisu: self = .XK_Eisu_toggle
    case kVK_JIS_Kana: self = .XK_Kana_Shift

    default: self = .XK_VoidSymbol
    }
  }

  init(keychar: unichar, shift: Bool, caps: Bool) {
    // NOTE: IBus/Rime use different keycodes for uppercase/lowercase letters.
    if keychar >= 0x61 && keychar <= 0x7A && (shift != caps) {
      // lowercase -> Uppercase
      self.init(rawValue: CInt(keychar) - 0x20)!; return
    }

    if keychar >= 0x20 && keychar <= 0x7E {
      self.init(rawValue: CInt(keychar))!; return
    }

    switch NSEvent.SpecialKey(rawValue: Int(keychar)) {
    // ASCII control characters
    case .newline: self = .XK_Linefeed
    case .backTab: self = .XK_ISO_Left_Tab
    // Function key characters
    case .f21: self = .XK_F21
    case .f22: self = .XK_F22
    case .f23: self = .XK_F23
    case .f24: self = .XK_F24
    case .f25: self = .XK_F25
    case .f26: self = .XK_F26
    case .f27: self = .XK_F27
    case .f28: self = .XK_F28
    case .f29: self = .XK_F29
    case .f30: self = .XK_F30
    case .f31: self = .XK_F31
    case .f32: self = .XK_F32
    case .f33: self = .XK_F33
    case .f34: self = .XK_F34
    case .f35: self = .XK_F35
    // Misc functional key characters
    case .insert: self = .XK_Insert
    case .begin: self = .XK_Begin
    case .scrollLock: self = .XK_Scroll_Lock
    case .pause: self = .XK_Pause
    case .sysReq: self = .XK_Sys_Req
    case .break: self = .XK_Break
    case .stop: self = .XK_Cancel
    case .print: self = .XK_Print
    case .clearLine: self = .XK_Num_Lock
    case .prev: self = .XK_Page_Up
    case .next: self = .XK_Page_Down
    case .select: self = .XK_Select
    case .execute: self = .XK_Execute
    case .undo: self = .XK_Undo
    case .redo: self = .XK_Redo
    case .find: self = .XK_Find
    case .modeSwitch: self = .XK_Mode_switch

    default: self = .XK_VoidSymbol
    }
  }

  init(name: String) { self.init(rawValue: Self.nameToRawValue(name))! }

  @inlinable static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  @inlinable static func > (lhs: Self, rhs: Self) -> Bool { lhs.rawValue > rhs.rawValue }
  @inlinable static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
  @inlinable static func <= (lhs: Self, rhs: Self) -> Bool { lhs.rawValue <= rhs.rawValue }
  @inlinable static func >= (lhs: Self, rhs: Self) -> Bool { lhs.rawValue >= rhs.rawValue }
  @inlinable static func != (lhs: Self, rhs: Self) -> Bool { lhs.rawValue != rhs.rawValue }
  @inlinable static func + (lhs: Self, rhs: Self) -> Self { Self(rawValue: lhs.rawValue + rhs.rawValue) ?? XK_VoidSymbol }
  @inlinable static func - (lhs: Self, rhs: Self) -> Self { Self(rawValue: lhs.rawValue - rhs.rawValue) ?? XK_VoidSymbol }

  private static func nameToRawValue(_ name: String) -> CInt {
    switch name {
    // ascii
    case "space": return 0x000020
    case "exclam": return 0x000021
    case "quotedbl": return 0x000022
    case "numbersign": return 0x000023
    case "dollar": return 0x000024
    case "percent": return 0x000025
    case "ampersand": return 0x000026
    case "apostrophe": return 0x000027
    case "quoteright": return 0x000027
    case "parenleft": return 0x000028
    case "parenright": return 0x000029
    case "asterisk": return 0x00002A
    case "plus": return 0x00002B
    case "comma": return 0x00002C
    case "minus": return 0x00002D
    case "period": return 0x00002E
    case "slash": return 0x00002F
    case "0": return 0x000030
    case "1": return 0x000031
    case "2": return 0x000032
    case "3": return 0x000033
    case "4": return 0x000034
    case "5": return 0x000035
    case "6": return 0x000036
    case "7": return 0x000037
    case "8": return 0x000038
    case "9": return 0x000039
    case "colon": return 0x00003A
    case "semicolon": return 0x00003B
    case "less": return 0x00003C
    case "equal": return 0x00003D
    case "greater": return 0x00003E
    case "question": return 0x00003F
    case "at": return 0x000040
    case "A": return 0x000041
    case "B": return 0x000042
    case "C": return 0x000043
    case "D": return 0x000044
    case "E": return 0x000045
    case "F": return 0x000046
    case "G": return 0x000047
    case "H": return 0x000048
    case "I": return 0x000049
    case "J": return 0x00004A
    case "K": return 0x00004B
    case "L": return 0x00004C
    case "M": return 0x00004D
    case "N": return 0x00004E
    case "O": return 0x00004F
    case "P": return 0x000050
    case "Q": return 0x000051
    case "R": return 0x000052
    case "S": return 0x000053
    case "T": return 0x000054
    case "U": return 0x000055
    case "V": return 0x000056
    case "W": return 0x000057
    case "X": return 0x000058
    case "Y": return 0x000059
    case "Z": return 0x00005A
    case "bracketleft": return 0x00005B
    case "backslash": return 0x00005C
    case "bracketright": return 0x00005D
    case "asciicircum": return 0x00005E
    case "underscore": return 0x00005F
    case "grave": return 0x000060
    case "quoteleft": return 0x000060
    case "a": return 0x000061
    case "b": return 0x000062
    case "c": return 0x000063
    case "d": return 0x000064
    case "e": return 0x000065
    case "f": return 0x000066
    case "g": return 0x000067
    case "h": return 0x000068
    case "i": return 0x000069
    case "j": return 0x00006A
    case "k": return 0x00006B
    case "l": return 0x00006C
    case "m": return 0x00006D
    case "n": return 0x00006E
    case "o": return 0x00006F
    case "p": return 0x000070
    case "q": return 0x000071
    case "r": return 0x000072
    case "s": return 0x000073
    case "t": return 0x000074
    case "u": return 0x000075
    case "v": return 0x000076
    case "w": return 0x000077
    case "x": return 0x000078
    case "y": return 0x000079
    case "z": return 0x00007A
    case "braceleft": return 0x00007B
    case "bar": return 0x00007C
    case "braceright": return 0x00007D
    case "asciitilde": return 0x00007E
    // latin-1
    case "nobreakspace": return 0x0000A0
    case "exclamdown": return 0x0000A1
    case "cent": return 0x0000A2
    case "sterling": return 0x0000A3
    case "currency": return 0x0000A4
    case "yen": return 0x0000A5
    case "brokenbar": return 0x0000A6
    case "section": return 0x0000A7
    case "diaeresis": return 0x0000A8
    case "copyright": return 0x0000A9
    case "ordfeminine": return 0x0000AA
    case "guillemotleft": return 0x0000AB
    case "notsign": return 0x0000AC
    case "hyphen": return 0x0000AD
    case "registered": return 0x0000AE
    case "macron": return 0x0000AF
    case "degree": return 0x0000B0
    case "plusminus": return 0x0000B1
    case "twosuperior": return 0x0000B2
    case "threesuperior": return 0x0000B3
    case "acute": return 0x0000B4
    case "mu": return 0x0000B5
    case "paragraph": return 0x0000B6
    case "periodcentered": return 0x0000B7
    case "cedilla": return 0x0000B8
    case "onesuperior": return 0x0000B9
    case "masculine": return 0x0000BA
    case "guillemotright": return 0x0000BB
    case "onequarter": return 0x0000BC
    case "onehalf": return 0x0000BD
    case "threequarters": return 0x0000BE
    case "questiondown": return 0x0000BF
    case "Agrave": return 0x0000C0
    case "Aacute": return 0x0000C1
    case "Acircumflex": return 0x0000C2
    case "Atilde": return 0x0000C3
    case "Adiaeresis": return 0x0000C4
    case "Aring": return 0x0000C5
    case "AE": return 0x0000C6
    case "Ccedilla": return 0x0000C7
    case "Egrave": return 0x0000C8
    case "Eacute": return 0x0000C9
    case "Ecircumflex": return 0x0000CA
    case "Ediaeresis": return 0x0000CB
    case "Igrave": return 0x0000CC
    case "Iacute": return 0x0000CD
    case "Icircumflex": return 0x0000CE
    case "Idiaeresis": return 0x0000CF
    case "ETH": return 0x0000D0
    case "Eth": return 0x0000D0
    case "Ntilde": return 0x0000D1
    case "Ograve": return 0x0000D2
    case "Oacute": return 0x0000D3
    case "Ocircumflex": return 0x0000D4
    case "Otilde": return 0x0000D5
    case "Odiaeresis": return 0x0000D6
    case "multiply": return 0x0000D7
    case "Ooblique": return 0x0000D8
    case "Ugrave": return 0x0000D9
    case "Uacute": return 0x0000DA
    case "Ucircumflex": return 0x0000DB
    case "Udiaeresis": return 0x0000DC
    case "Yacute": return 0x0000DD
    case "THORN": return 0x0000DE
    case "Thorn": return 0x0000DE
    case "ssharp": return 0x0000DF
    case "agrave": return 0x0000E0
    case "aacute": return 0x0000E1
    case "acircumflex": return 0x0000E2
    case "atilde": return 0x0000E3
    case "adiaeresis": return 0x0000E4
    case "aring": return 0x0000E5
    case "ae": return 0x0000E6
    case "ccedilla": return 0x0000E7
    case "egrave": return 0x0000E8
    case "eacute": return 0x0000E9
    case "ecircumflex": return 0x0000EA
    case "ediaeresis": return 0x0000EB
    case "igrave": return 0x0000EC
    case "iacute": return 0x0000ED
    case "icircumflex": return 0x0000EE
    case "idiaeresis": return 0x0000EF
    case "eth": return 0x0000F0
    case "ntilde": return 0x0000F1
    case "ograve": return 0x0000F2
    case "oacute": return 0x0000F3
    case "ocircumflex": return 0x0000F4
    case "otilde": return 0x0000F5
    case "odiaeresis": return 0x0000F6
    case "division": return 0x0000F7
    case "oslash": return 0x0000F8
    case "ugrave": return 0x0000F9
    case "uacute": return 0x0000FA
    case "ucircumflex": return 0x0000FB
    case "udiaeresis": return 0x0000FC
    case "yacute": return 0x0000FD
    case "thorn": return 0x0000FE
    case "ydiaeresis": return 0x0000FF
    case "Aogonek": return 0x0001A1
    case "breve": return 0x0001A2
    case "Lstroke": return 0x0001A3
    case "Lcaron": return 0x0001A5
    case "Sacute": return 0x0001A6
    case "Scaron": return 0x0001A9
    case "Scedilla": return 0x0001AA
    case "Tcaron": return 0x0001AB
    case "Zacute": return 0x0001AC
    case "Zcaron": return 0x0001AE
    case "Zabovedot": return 0x0001AF
    case "aogonek": return 0x0001B1
    case "ogonek": return 0x0001B2
    case "lstroke": return 0x0001B3
    case "lcaron": return 0x0001B5
    case "sacute": return 0x0001B6
    case "caron": return 0x0001B7
    case "scaron": return 0x0001B9
    case "scedilla": return 0x0001BA
    case "tcaron": return 0x0001BB
    case "zacute": return 0x0001BC
    case "doubleacute": return 0x0001BD
    case "zcaron": return 0x0001BE
    case "zabovedot": return 0x0001BF
    case "Racute": return 0x0001C0
    case "Abreve": return 0x0001C3
    case "Lacute": return 0x0001C5
    case "Cacute": return 0x0001C6
    case "Ccaron": return 0x0001C8
    case "Eogonek": return 0x0001CA
    case "Ecaron": return 0x0001CC
    case "Dcaron": return 0x0001CF
    case "Dstroke": return 0x0001D0
    case "Nacute": return 0x0001D1
    case "Ncaron": return 0x0001D2
    case "Odoubleacute": return 0x0001D5
    case "Rcaron": return 0x0001D8
    case "Uring": return 0x0001D9
    case "Udoubleacute": return 0x0001DB
    case "Tcedilla": return 0x0001DE
    case "racute": return 0x0001E0
    case "abreve": return 0x0001E3
    case "lacute": return 0x0001E5
    case "cacute": return 0x0001E6
    case "ccaron": return 0x0001E8
    case "eogonek": return 0x0001EA
    case "ecaron": return 0x0001EC
    case "dcaron": return 0x0001EF
    case "dstroke": return 0x0001F0
    case "nacute": return 0x0001F1
    case "ncaron": return 0x0001F2
    case "odoubleacute": return 0x0001F5
    case "rcaron": return 0x0001F8
    case "uring": return 0x0001F9
    case "udoubleacute": return 0x0001FB
    case "tcedilla": return 0x0001FE
    case "abovedot": return 0x0001FF
    // others
    case "Hstroke": return 0x0002A1
    case "Hcircumflex": return 0x0002A6
    case "Iabovedot": return 0x0002A9
    case "Gbreve": return 0x0002AB
    case "Jcircumflex": return 0x0002AC
    case "hstroke": return 0x0002B1
    case "hcircumflex": return 0x0002B6
    case "idotless": return 0x0002B9
    case "gbreve": return 0x0002BB
    case "jcircumflex": return 0x0002BC
    case "Cabovedot": return 0x0002C5
    case "Ccircumflex": return 0x0002C6
    case "Gabovedot": return 0x0002D5
    case "Gcircumflex": return 0x0002D8
    case "Ubreve": return 0x0002DD
    case "Scircumflex": return 0x0002DE
    case "cabovedot": return 0x0002E5
    case "ccircumflex": return 0x0002E6
    case "gabovedot": return 0x0002F5
    case "gcircumflex": return 0x0002F8
    case "ubreve": return 0x0002FD
    case "scircumflex": return 0x0002FE
    case "kappa": return 0x0003A2
    case "kra": return 0x0003A2
    case "Rcedilla": return 0x0003A3
    case "Itilde": return 0x0003A5
    case "Lcedilla": return 0x0003A6
    case "Emacron": return 0x0003AA
    case "Gcedilla": return 0x0003AB
    case "Tslash": return 0x0003AC
    case "rcedilla": return 0x0003B3
    case "itilde": return 0x0003B5
    case "lcedilla": return 0x0003B6
    case "emacron": return 0x0003BA
    case "gcedilla": return 0x0003BB
    case "tslash": return 0x0003BC
    case "ENG": return 0x0003BD
    case "eng": return 0x0003BF
    case "Amacron": return 0x0003C0
    case "Iogonek": return 0x0003C7
    case "Eabovedot": return 0x0003CC
    case "Imacron": return 0x0003CF
    case "Ncedilla": return 0x0003D1
    case "Omacron": return 0x0003D2
    case "Kcedilla": return 0x0003D3
    case "Uogonek": return 0x0003D9
    case "Utilde": return 0x0003DD
    case "Umacron": return 0x0003DE
    case "amacron": return 0x0003E0
    case "iogonek": return 0x0003E7
    case "eabovedot": return 0x0003EC
    case "imacron": return 0x0003EF
    case "ncedilla": return 0x0003F1
    case "omacron": return 0x0003F2
    case "kcedilla": return 0x0003F3
    case "uogonek": return 0x0003F9
    case "utilde": return 0x0003FD
    case "umacron": return 0x0003FE
    case "overline": return 0x00047E
    case "kana_fullstop": return 0x0004A1
    case "kana_openingbracket": return 0x0004A2
    case "kana_closingbracket": return 0x0004A3
    case "kana_comma": return 0x0004A4
    case "kana_conjunctive": return 0x0004A5
    case "kana_middledot": return 0x0004A5
    case "kana_WO": return 0x0004A6
    case "kana_a": return 0x0004A7
    case "kana_i": return 0x0004A8
    case "kana_u": return 0x0004A9
    case "kana_e": return 0x0004AA
    case "kana_o": return 0x0004AB
    case "kana_ya": return 0x0004AC
    case "kana_yu": return 0x0004AD
    case "kana_yo": return 0x0004AE
    case "kana_tsu": return 0x0004AF
    case "kana_tu": return 0x0004AF
    case "prolongedsound": return 0x0004B0
    case "kana_A": return 0x0004B1
    case "kana_I": return 0x0004B2
    case "kana_U": return 0x0004B3
    case "kana_E": return 0x0004B4
    case "kana_O": return 0x0004B5
    case "kana_KA": return 0x0004B6
    case "kana_KI": return 0x0004B7
    case "kana_KU": return 0x0004B8
    case "kana_KE": return 0x0004B9
    case "kana_KO": return 0x0004BA
    case "kana_SA": return 0x0004BB
    case "kana_SHI": return 0x0004BC
    case "kana_SU": return 0x0004BD
    case "kana_SE": return 0x0004BE
    case "kana_SO": return 0x0004BF
    case "kana_TA": return 0x0004C0
    case "kana_CHI": return 0x0004C1
    case "kana_TI": return 0x0004C1
    case "kana_TSU": return 0x0004C2
    case "kana_TU": return 0x0004C2
    case "kana_TE": return 0x0004C3
    case "kana_TO": return 0x0004C4
    case "kana_NA": return 0x0004C5
    case "kana_NI": return 0x0004C6
    case "kana_NU": return 0x0004C7
    case "kana_NE": return 0x0004C8
    case "kana_NO": return 0x0004C9
    case "kana_HA": return 0x0004CA
    case "kana_HI": return 0x0004CB
    case "kana_FU": return 0x0004CC
    case "kana_HU": return 0x0004CC
    case "kana_HE": return 0x0004CD
    case "kana_HO": return 0x0004CE
    case "kana_MA": return 0x0004CF
    case "kana_MI": return 0x0004D0
    case "kana_MU": return 0x0004D1
    case "kana_ME": return 0x0004D2
    case "kana_MO": return 0x0004D3
    case "kana_YA": return 0x0004D4
    case "kana_YU": return 0x0004D5
    case "kana_YO": return 0x0004D6
    case "kana_RA": return 0x0004D7
    case "kana_RI": return 0x0004D8
    case "kana_RU": return 0x0004D9
    case "kana_RE": return 0x0004DA
    case "kana_RO": return 0x0004DB
    case "kana_WA": return 0x0004DC
    case "kana_N": return 0x0004DD
    case "voicedsound": return 0x0004DE
    case "semivoicedsound": return 0x0004DF
    case "Arabic_comma": return 0x0005AC
    case "Arabic_semicolon": return 0x0005BB
    case "Arabic_question_mark": return 0x0005BF
    case "Arabic_hamza": return 0x0005C1
    case "Arabic_maddaonalef": return 0x0005C2
    case "Arabic_hamzaonalef": return 0x0005C3
    case "Arabic_hamzaonwaw": return 0x0005C4
    case "Arabic_hamzaunderalef": return 0x0005C5
    case "Arabic_hamzaonyeh": return 0x0005C6
    case "Arabic_alef": return 0x0005C7
    case "Arabic_beh": return 0x0005C8
    case "Arabic_tehmarbuta": return 0x0005C9
    case "Arabic_teh": return 0x0005CA
    case "Arabic_theh": return 0x0005CB
    case "Arabic_jeem": return 0x0005CC
    case "Arabic_hah": return 0x0005CD
    case "Arabic_khah": return 0x0005CE
    case "Arabic_dal": return 0x0005CF
    case "Arabic_thal": return 0x0005D0
    case "Arabic_ra": return 0x0005D1
    case "Arabic_zain": return 0x0005D2
    case "Arabic_seen": return 0x0005D3
    case "Arabic_sheen": return 0x0005D4
    case "Arabic_sad": return 0x0005D5
    case "Arabic_dad": return 0x0005D6
    case "Arabic_tah": return 0x0005D7
    case "Arabic_zah": return 0x0005D8
    case "Arabic_ain": return 0x0005D9
    case "Arabic_ghain": return 0x0005DA
    case "Arabic_tatweel": return 0x0005E0
    case "Arabic_feh": return 0x0005E1
    case "Arabic_qaf": return 0x0005E2
    case "Arabic_kaf": return 0x0005E3
    case "Arabic_lam": return 0x0005E4
    case "Arabic_meem": return 0x0005E5
    case "Arabic_noon": return 0x0005E6
    case "Arabic_ha": return 0x0005E7
    case "Arabic_heh": return 0x0005E7
    case "Arabic_waw": return 0x0005E8
    case "Arabic_alefmaksura": return 0x0005E9
    case "Arabic_yeh": return 0x0005EA
    case "Arabic_fathatan": return 0x0005EB
    case "Arabic_dammatan": return 0x0005EC
    case "Arabic_kasratan": return 0x0005ED
    case "Arabic_fatha": return 0x0005EE
    case "Arabic_damma": return 0x0005EF
    case "Arabic_kasra": return 0x0005F0
    case "Arabic_shadda": return 0x0005F1
    case "Arabic_sukun": return 0x0005F2
    case "Serbian_dje": return 0x0006A1
    case "Macedonia_gje": return 0x0006A2
    case "Cyrillic_io": return 0x0006A3
    case "Ukrainian_ie": return 0x0006A4
    case "Ukranian_je": return 0x0006A4
    case "Macedonia_dse": return 0x0006A5
    case "Ukrainian_i": return 0x0006A6
    case "Ukranian_i": return 0x0006A6
    case "Ukrainian_yi": return 0x0006A7
    case "Ukranian_yi": return 0x0006A7
    case "Cyrillic_je": return 0x0006A8
    case "Serbian_je": return 0x0006A8
    case "Cyrillic_lje": return 0x0006A9
    case "Serbian_lje": return 0x0006A9
    case "Cyrillic_nje": return 0x0006AA
    case "Serbian_nje": return 0x0006AA
    case "Serbian_tshe": return 0x0006AB
    case "Macedonia_kje": return 0x0006AC
    case "Byelorussian_shortu": return 0x0006AE
    case "Cyrillic_dzhe": return 0x0006AF
    case "Serbian_dze": return 0x0006AF
    case "numerosign": return 0x0006B0
    case "Serbian_DJE": return 0x0006B1
    case "Macedonia_GJE": return 0x0006B2
    case "Cyrillic_IO": return 0x0006B3
    case "Ukrainian_IE": return 0x0006B4
    case "Ukranian_JE": return 0x0006B4
    case "Macedonia_DSE": return 0x0006B5
    case "Ukrainian_I": return 0x0006B6
    case "Ukranian_I": return 0x0006B6
    case "Ukrainian_YI": return 0x0006B7
    case "Ukranian_YI": return 0x0006B7
    case "Cyrillic_JE": return 0x0006B8
    case "Serbian_JE": return 0x0006B8
    case "Cyrillic_LJE": return 0x0006B9
    case "Serbian_LJE": return 0x0006B9
    case "Cyrillic_NJE": return 0x0006BA
    case "Serbian_NJE": return 0x0006BA
    case "Serbian_TSHE": return 0x0006BB
    case "Macedonia_KJE": return 0x0006BC
    case "Byelorussian_SHORTU": return 0x0006BE
    case "Cyrillic_DZHE": return 0x0006BF
    case "Serbian_DZE": return 0x0006BF
    case "Cyrillic_yu": return 0x0006C0
    case "Cyrillic_a": return 0x0006C1
    case "Cyrillic_be": return 0x0006C2
    case "Cyrillic_tse": return 0x0006C3
    case "Cyrillic_de": return 0x0006C4
    case "Cyrillic_ie": return 0x0006C5
    case "Cyrillic_ef": return 0x0006C6
    case "Cyrillic_ghe": return 0x0006C7
    case "Cyrillic_ha": return 0x0006C8
    case "Cyrillic_i": return 0x0006C9
    case "Cyrillic_shorti": return 0x0006CA
    case "Cyrillic_ka": return 0x0006CB
    case "Cyrillic_el": return 0x0006CC
    case "Cyrillic_em": return 0x0006CD
    case "Cyrillic_en": return 0x0006CE
    case "Cyrillic_o": return 0x0006CF
    case "Cyrillic_pe": return 0x0006D0
    case "Cyrillic_ya": return 0x0006D1
    case "Cyrillic_er": return 0x0006D2
    case "Cyrillic_es": return 0x0006D3
    case "Cyrillic_te": return 0x0006D4
    case "Cyrillic_u": return 0x0006D5
    case "Cyrillic_zhe": return 0x0006D6
    case "Cyrillic_ve": return 0x0006D7
    case "Cyrillic_softsign": return 0x0006D8
    case "Cyrillic_yeru": return 0x0006D9
    case "Cyrillic_ze": return 0x0006DA
    case "Cyrillic_sha": return 0x0006DB
    case "Cyrillic_e": return 0x0006DC
    case "Cyrillic_shcha": return 0x0006DD
    case "Cyrillic_che": return 0x0006DE
    case "Cyrillic_hardsign": return 0x0006DF
    case "Cyrillic_YU": return 0x0006E0
    case "Cyrillic_A": return 0x0006E1
    case "Cyrillic_BE": return 0x0006E2
    case "Cyrillic_TSE": return 0x0006E3
    case "Cyrillic_DE": return 0x0006E4
    case "Cyrillic_IE": return 0x0006E5
    case "Cyrillic_EF": return 0x0006E6
    case "Cyrillic_GHE": return 0x0006E7
    case "Cyrillic_HA": return 0x0006E8
    case "Cyrillic_I": return 0x0006E9
    case "Cyrillic_SHORTI": return 0x0006EA
    case "Cyrillic_KA": return 0x0006EB
    case "Cyrillic_EL": return 0x0006EC
    case "Cyrillic_EM": return 0x0006ED
    case "Cyrillic_EN": return 0x0006EE
    case "Cyrillic_O": return 0x0006EF
    case "Cyrillic_PE": return 0x0006F0
    case "Cyrillic_YA": return 0x0006F1
    case "Cyrillic_ER": return 0x0006F2
    case "Cyrillic_ES": return 0x0006F3
    case "Cyrillic_TE": return 0x0006F4
    case "Cyrillic_U": return 0x0006F5
    case "Cyrillic_ZHE": return 0x0006F6
    case "Cyrillic_VE": return 0x0006F7
    case "Cyrillic_SOFTSIGN": return 0x0006F8
    case "Cyrillic_YERU": return 0x0006F9
    case "Cyrillic_ZE": return 0x0006FA
    case "Cyrillic_SHA": return 0x0006FB
    case "Cyrillic_E": return 0x0006FC
    case "Cyrillic_SHCHA": return 0x0006FD
    case "Cyrillic_CHE": return 0x0006FE
    case "Cyrillic_HARDSIGN": return 0x0006FF
    case "Greek_ALPHAaccent": return 0x0007A1
    case "Greek_EPSILONaccent": return 0x0007A2
    case "Greek_ETAaccent": return 0x0007A3
    case "Greek_IOTAaccent": return 0x0007A4
    case "Greek_IOTAdieresis": return 0x0007A5
    case "Greek_IOTAdiaeresis": return 0x0007A5
    case "Greek_OMICRONaccent": return 0x0007A7
    case "Greek_UPSILONaccent": return 0x0007A8
    case "Greek_UPSILONdieresis": return 0x0007A9
    case "Greek_OMEGAaccent": return 0x0007AB
    case "Greek_accentdieresis": return 0x0007AE
    case "Greek_horizbar": return 0x0007AF
    case "Greek_alphaaccent": return 0x0007B1
    case "Greek_epsilonaccent": return 0x0007B2
    case "Greek_etaaccent": return 0x0007B3
    case "Greek_iotaaccent": return 0x0007B4
    case "Greek_iotadieresis": return 0x0007B5
    case "Greek_iotaaccentdieresis": return 0x0007B6
    case "Greek_omicronaccent": return 0x0007B7
    case "Greek_upsilonaccent": return 0x0007B8
    case "Greek_upsilondieresis": return 0x0007B9
    case "Greek_upsilonaccentdieresis": return 0x0007BA
    case "Greek_omegaaccent": return 0x0007BB
    case "Greek_ALPHA": return 0x0007C1
    case "Greek_BETA": return 0x0007C2
    case "Greek_GAMMA": return 0x0007C3
    case "Greek_DELTA": return 0x0007C4
    case "Greek_EPSILON": return 0x0007C5
    case "Greek_ZETA": return 0x0007C6
    case "Greek_ETA": return 0x0007C7
    case "Greek_THETA": return 0x0007C8
    case "Greek_IOTA": return 0x0007C9
    case "Greek_KAPPA": return 0x0007CA
    case "Greek_LAMBDA": return 0x0007CB
    case "Greek_LAMDA": return 0x0007CB
    case "Greek_MU": return 0x0007CC
    case "Greek_NU": return 0x0007CD
    case "Greek_XI": return 0x0007CE
    case "Greek_OMICRON": return 0x0007CF
    case "Greek_PI": return 0x0007D0
    case "Greek_RHO": return 0x0007D1
    case "Greek_SIGMA": return 0x0007D2
    case "Greek_TAU": return 0x0007D4
    case "Greek_UPSILON": return 0x0007D5
    case "Greek_PHI": return 0x0007D6
    case "Greek_CHI": return 0x0007D7
    case "Greek_PSI": return 0x0007D8
    case "Greek_OMEGA": return 0x0007D9
    case "Greek_alpha": return 0x0007E1
    case "Greek_beta": return 0x0007E2
    case "Greek_gamma": return 0x0007E3
    case "Greek_delta": return 0x0007E4
    case "Greek_epsilon": return 0x0007E5
    case "Greek_zeta": return 0x0007E6
    case "Greek_eta": return 0x0007E7
    case "Greek_theta": return 0x0007E8
    case "Greek_iota": return 0x0007E9
    case "Greek_kappa": return 0x0007EA
    case "Greek_lambda": return 0x0007EB
    case "Greek_lamda": return 0x0007EB
    case "Greek_mu": return 0x0007EC
    case "Greek_nu": return 0x0007ED
    case "Greek_xi": return 0x0007EE
    case "Greek_omicron": return 0x0007EF
    case "Greek_pi": return 0x0007F0
    case "Greek_rho": return 0x0007F1
    case "Greek_sigma": return 0x0007F2
    case "Greek_finalsmallsigma": return 0x0007F3
    case "Greek_tau": return 0x0007F4
    case "Greek_upsilon": return 0x0007F5
    case "Greek_phi": return 0x0007F6
    case "Greek_chi": return 0x0007F7
    case "Greek_psi": return 0x0007F8
    case "Greek_omega": return 0x0007F9
    case "leftradical": return 0x0008A1
    case "topleftradical": return 0x0008A2
    case "horizconnector": return 0x0008A3
    case "topintegral": return 0x0008A4
    case "botintegral": return 0x0008A5
    case "vertconnector": return 0x0008A6
    case "topleftsqbracket": return 0x0008A7
    case "botleftsqbracket": return 0x0008A8
    case "toprightsqbracket": return 0x0008A9
    case "botrightsqbracket": return 0x0008AA
    case "topleftparens": return 0x0008AB
    case "botleftparens": return 0x0008AC
    case "toprightparens": return 0x0008AD
    case "botrightparens": return 0x0008AE
    case "leftmiddlecurlybrace": return 0x0008AF
    case "rightmiddlecurlybrace": return 0x0008B0
    case "topleftsummation": return 0x0008B1
    case "botleftsummation": return 0x0008B2
    case "topvertsummationconnector": return 0x0008B3
    case "botvertsummationconnector": return 0x0008B4
    case "toprightsummation": return 0x0008B5
    case "botrightsummation": return 0x0008B6
    case "rightmiddlesummation": return 0x0008B7
    case "lessthanequal": return 0x0008BC
    case "notequal": return 0x0008BD
    case "greaterthanequal": return 0x0008BE
    case "integral": return 0x0008BF
    case "therefore": return 0x0008C0
    case "variation": return 0x0008C1
    case "infinity": return 0x0008C2
    case "nabla": return 0x0008C5
    case "approximate": return 0x0008C8
    case "similarequal": return 0x0008C9
    case "ifonlyif": return 0x0008CD
    case "implies": return 0x0008CE
    case "identical": return 0x0008CF
    case "radical": return 0x0008D6
    case "includedin": return 0x0008DA
    case "includes": return 0x0008DB
    case "intersection": return 0x0008DC
    case "union": return 0x0008DD
    case "logicaland": return 0x0008DE
    case "logicalor": return 0x0008DF
    case "partialderivative": return 0x0008EF
    case "function": return 0x0008F6
    case "leftarrow": return 0x0008FB
    case "uparrow": return 0x0008FC
    case "rightarrow": return 0x0008FD
    case "downarrow": return 0x0008FE
    case "blank": return 0x0009DF
    case "soliddiamond": return 0x0009E0
    case "checkerboard": return 0x0009E1
    case "ht": return 0x0009E2
    case "ff": return 0x0009E3
    case "cr": return 0x0009E4
    case "lf": return 0x0009E5
    case "nl": return 0x0009E8
    case "vt": return 0x0009E9
    case "lowrightcorner": return 0x0009EA
    case "uprightcorner": return 0x0009EB
    case "upleftcorner": return 0x0009EC
    case "lowleftcorner": return 0x0009ED
    case "crossinglines": return 0x0009EE
    case "horizlinescan1": return 0x0009EF
    case "horizlinescan3": return 0x0009F0
    case "horizlinescan5": return 0x0009F1
    case "horizlinescan7": return 0x0009F2
    case "horizlinescan9": return 0x0009F3
    case "leftt": return 0x0009F4
    case "rightt": return 0x0009F5
    case "bott": return 0x0009F6
    case "topt": return 0x0009F7
    case "vertbar": return 0x0009F8
    case "emspace": return 0x000AA1
    case "enspace": return 0x000AA2
    case "em3space": return 0x000AA3
    case "em4space": return 0x000AA4
    case "digitspace": return 0x000AA5
    case "punctspace": return 0x000AA6
    case "thinspace": return 0x000AA7
    case "hairspace": return 0x000AA8
    case "emdash": return 0x000AA9
    case "endash": return 0x000AAA
    case "signifblank": return 0x000AAC
    case "ellipsis": return 0x000AAE
    case "doubbaselinedot": return 0x000AAF
    case "onethird": return 0x000AB0
    case "twothirds": return 0x000AB1
    case "onefifth": return 0x000AB2
    case "twofifths": return 0x000AB3
    case "threefifths": return 0x000AB4
    case "fourfifths": return 0x000AB5
    case "onesixth": return 0x000AB6
    case "fivesixths": return 0x000AB7
    case "careof": return 0x000AB8
    case "figdash": return 0x000ABB
    case "leftanglebracket": return 0x000ABC
    case "decimalpoint": return 0x000ABD
    case "rightanglebracket": return 0x000ABE
    case "marker": return 0x000ABF
    case "oneeighth": return 0x000AC3
    case "threeeighths": return 0x000AC4
    case "fiveeighths": return 0x000AC5
    case "seveneighths": return 0x000AC6
    case "trademark": return 0x000AC9
    case "signaturemark": return 0x000ACA
    case "trademarkincircle": return 0x000ACB
    case "leftopentriangle": return 0x000ACC
    case "rightopentriangle": return 0x000ACD
    case "emopencircle": return 0x000ACE
    case "emopenrectangle": return 0x000ACF
    case "leftsinglequotemark": return 0x000AD0
    case "rightsinglequotemark": return 0x000AD1
    case "leftdoublequotemark": return 0x000AD2
    case "rightdoublequotemark": return 0x000AD3
    case "prescription": return 0x000AD4
    case "minutes": return 0x000AD6
    case "seconds": return 0x000AD7
    case "latincross": return 0x000AD9
    case "hexagram": return 0x000ADA
    case "filledrectbullet": return 0x000ADB
    case "filledlefttribullet": return 0x000ADC
    case "filledrighttribullet": return 0x000ADD
    case "emfilledcircle": return 0x000ADE
    case "emfilledrect": return 0x000ADF
    case "enopencircbullet": return 0x000AE0
    case "enopensquarebullet": return 0x000AE1
    case "openrectbullet": return 0x000AE2
    case "opentribulletup": return 0x000AE3
    case "opentribulletdown": return 0x000AE4
    case "openstar": return 0x000AE5
    case "enfilledcircbullet": return 0x000AE6
    case "enfilledsqbullet": return 0x000AE7
    case "filledtribulletup": return 0x000AE8
    case "filledtribulletdown": return 0x000AE9
    case "leftpointer": return 0x000AEA
    case "rightpointer": return 0x000AEB
    case "club": return 0x000AEC
    case "diamond": return 0x000AED
    case "heart": return 0x000AEE
    case "maltesecross": return 0x000AF0
    case "dagger": return 0x000AF1
    case "doubledagger": return 0x000AF2
    case "checkmark": return 0x000AF3
    case "ballotcross": return 0x000AF4
    case "musicalsharp": return 0x000AF5
    case "musicalflat": return 0x000AF6
    case "malesymbol": return 0x000AF7
    case "femalesymbol": return 0x000AF8
    case "telephone": return 0x000AF9
    case "telephonerecorder": return 0x000AFA
    case "phonographcopyright": return 0x000AFB
    case "caret": return 0x000AFC
    case "singlelowquotemark": return 0x000AFD
    case "doublelowquotemark": return 0x000AFE
    case "cursor": return 0x000AFF
    case "leftcaret": return 0x000BA3
    case "rightcaret": return 0x000BA6
    case "downcaret": return 0x000BA8
    case "upcaret": return 0x000BA9
    case "overbar": return 0x000BC0
    case "downtack": return 0x000BC2
    case "upshoe": return 0x000BC3
    case "downstile": return 0x000BC4
    case "underbar": return 0x000BC6
    case "jot": return 0x000BCA
    case "quad": return 0x000BCC
    case "uptack": return 0x000BCE
    case "circle": return 0x000BCF
    case "upstile": return 0x000BD3
    case "downshoe": return 0x000BD6
    case "rightshoe": return 0x000BD8
    case "leftshoe": return 0x000BDA
    case "lefttack": return 0x000BDC
    case "righttack": return 0x000BFC
    case "hebrew_doublelowline": return 0x000CDF
    case "hebrew_aleph": return 0x000CE0
    case "hebrew_bet": return 0x000CE1
    case "hebrew_beth": return 0x000CE1
    case "hebrew_gimel": return 0x000CE2
    case "hebrew_gimmel": return 0x000CE2
    case "hebrew_dalet": return 0x000CE3
    case "hebrew_daleth": return 0x000CE3
    case "hebrew_he": return 0x000CE4
    case "hebrew_waw": return 0x000CE5
    case "hebrew_zain": return 0x000CE6
    case "hebrew_zayin": return 0x000CE6
    case "hebrew_chet": return 0x000CE7
    case "hebrew_het": return 0x000CE7
    case "hebrew_tet": return 0x000CE8
    case "hebrew_teth": return 0x000CE8
    case "hebrew_yod": return 0x000CE9
    case "hebrew_finalkaph": return 0x000CEA
    case "hebrew_kaph": return 0x000CEB
    case "hebrew_lamed": return 0x000CEC
    case "hebrew_finalmem": return 0x000CED
    case "hebrew_mem": return 0x000CEE
    case "hebrew_finalnun": return 0x000CEF
    case "hebrew_nun": return 0x000CF0
    case "hebrew_samech": return 0x000CF1
    case "hebrew_samekh": return 0x000CF1
    case "hebrew_ayin": return 0x000CF2
    case "hebrew_finalpe": return 0x000CF3
    case "hebrew_pe": return 0x000CF4
    case "hebrew_finalzade": return 0x000CF5
    case "hebrew_finalzadi": return 0x000CF5
    case "hebrew_zade": return 0x000CF6
    case "hebrew_zadi": return 0x000CF6
    case "hebrew_kuf": return 0x000CF7
    case "hebrew_qoph": return 0x000CF7
    case "hebrew_resh": return 0x000CF8
    case "hebrew_shin": return 0x000CF9
    case "hebrew_taf": return 0x000CFA
    case "hebrew_taw": return 0x000CFA
    case "Thai_kokai": return 0x000DA1
    case "Thai_khokhai": return 0x000DA2
    case "Thai_khokhuat": return 0x000DA3
    case "Thai_khokhwai": return 0x000DA4
    case "Thai_khokhon": return 0x000DA5
    case "Thai_khorakhang": return 0x000DA6
    case "Thai_ngongu": return 0x000DA7
    case "Thai_chochan": return 0x000DA8
    case "Thai_choching": return 0x000DA9
    case "Thai_chochang": return 0x000DAA
    case "Thai_soso": return 0x000DAB
    case "Thai_chochoe": return 0x000DAC
    case "Thai_yoying": return 0x000DAD
    case "Thai_dochada": return 0x000DAE
    case "Thai_topatak": return 0x000DAF
    case "Thai_thothan": return 0x000DB0
    case "Thai_thonangmontho": return 0x000DB1
    case "Thai_thophuthao": return 0x000DB2
    case "Thai_nonen": return 0x000DB3
    case "Thai_dodek": return 0x000DB4
    case "Thai_totao": return 0x000DB5
    case "Thai_thothung": return 0x000DB6
    case "Thai_thothahan": return 0x000DB7
    case "Thai_thothong": return 0x000DB8
    case "Thai_nonu": return 0x000DB9
    case "Thai_bobaimai": return 0x000DBA
    case "Thai_popla": return 0x000DBB
    case "Thai_phophung": return 0x000DBC
    case "Thai_fofa": return 0x000DBD
    case "Thai_phophan": return 0x000DBE
    case "Thai_fofan": return 0x000DBF
    case "Thai_phosamphao": return 0x000DC0
    case "Thai_moma": return 0x000DC1
    case "Thai_yoyak": return 0x000DC2
    case "Thai_rorua": return 0x000DC3
    case "Thai_ru": return 0x000DC4
    case "Thai_loling": return 0x000DC5
    case "Thai_lu": return 0x000DC6
    case "Thai_wowaen": return 0x000DC7
    case "Thai_sosala": return 0x000DC8
    case "Thai_sorusi": return 0x000DC9
    case "Thai_sosua": return 0x000DCA
    case "Thai_hohip": return 0x000DCB
    case "Thai_lochula": return 0x000DCC
    case "Thai_oang": return 0x000DCD
    case "Thai_honokhuk": return 0x000DCE
    case "Thai_paiyannoi": return 0x000DCF
    case "Thai_saraa": return 0x000DD0
    case "Thai_maihanakat": return 0x000DD1
    case "Thai_saraaa": return 0x000DD2
    case "Thai_saraam": return 0x000DD3
    case "Thai_sarai": return 0x000DD4
    case "Thai_saraii": return 0x000DD5
    case "Thai_saraue": return 0x000DD6
    case "Thai_sarauee": return 0x000DD7
    case "Thai_sarau": return 0x000DD8
    case "Thai_sarauu": return 0x000DD9
    case "Thai_phinthu": return 0x000DDA
    case "Thai_maihanakat_maitho": return 0x000DDE
    case "Thai_baht": return 0x000DDF
    case "Thai_sarae": return 0x000DE0
    case "Thai_saraae": return 0x000DE1
    case "Thai_sarao": return 0x000DE2
    case "Thai_saraaimaimuan": return 0x000DE3
    case "Thai_saraaimaimalai": return 0x000DE4
    case "Thai_lakkhangyao": return 0x000DE5
    case "Thai_maiyamok": return 0x000DE6
    case "Thai_maitaikhu": return 0x000DE7
    case "Thai_maiek": return 0x000DE8
    case "Thai_maitho": return 0x000DE9
    case "Thai_maitri": return 0x000DEA
    case "Thai_maichattawa": return 0x000DEB
    case "Thai_thanthakhat": return 0x000DEC
    case "Thai_nikhahit": return 0x000DED
    case "Thai_leksun": return 0x000DF0
    case "Thai_leknung": return 0x000DF1
    case "Thai_leksong": return 0x000DF2
    case "Thai_leksam": return 0x000DF3
    case "Thai_leksi": return 0x000DF4
    case "Thai_lekha": return 0x000DF5
    case "Thai_lekhok": return 0x000DF6
    case "Thai_lekchet": return 0x000DF7
    case "Thai_lekpaet": return 0x000DF8
    case "Thai_lekkao": return 0x000DF9
    case "Hangul_Kiyeog": return 0x000EA1
    case "Hangul_SsangKiyeog": return 0x000EA2
    case "Hangul_KiyeogSios": return 0x000EA3
    case "Hangul_Nieun": return 0x000EA4
    case "Hangul_NieunJieuj": return 0x000EA5
    case "Hangul_NieunHieuh": return 0x000EA6
    case "Hangul_Dikeud": return 0x000EA7
    case "Hangul_SsangDikeud": return 0x000EA8
    case "Hangul_Rieul": return 0x000EA9
    case "Hangul_RieulKiyeog": return 0x000EAA
    case "Hangul_RieulMieum": return 0x000EAB
    case "Hangul_RieulPieub": return 0x000EAC
    case "Hangul_RieulSios": return 0x000EAD
    case "Hangul_RieulTieut": return 0x000EAE
    case "Hangul_RieulPhieuf": return 0x000EAF
    case "Hangul_RieulHieuh": return 0x000EB0
    case "Hangul_Mieum": return 0x000EB1
    case "Hangul_Pieub": return 0x000EB2
    case "Hangul_SsangPieub": return 0x000EB3
    case "Hangul_PieubSios": return 0x000EB4
    case "Hangul_Sios": return 0x000EB5
    case "Hangul_SsangSios": return 0x000EB6
    case "Hangul_Ieung": return 0x000EB7
    case "Hangul_Jieuj": return 0x000EB8
    case "Hangul_SsangJieuj": return 0x000EB9
    case "Hangul_Cieuc": return 0x000EBA
    case "Hangul_Khieuq": return 0x000EBB
    case "Hangul_Tieut": return 0x000EBC
    case "Hangul_Phieuf": return 0x000EBD
    case "Hangul_Hieuh": return 0x000EBE
    case "Hangul_A": return 0x000EBF
    case "Hangul_AE": return 0x000EC0
    case "Hangul_YA": return 0x000EC1
    case "Hangul_YAE": return 0x000EC2
    case "Hangul_EO": return 0x000EC3
    case "Hangul_E": return 0x000EC4
    case "Hangul_YEO": return 0x000EC5
    case "Hangul_YE": return 0x000EC6
    case "Hangul_O": return 0x000EC7
    case "Hangul_WA": return 0x000EC8
    case "Hangul_WAE": return 0x000EC9
    case "Hangul_OE": return 0x000ECA
    case "Hangul_YO": return 0x000ECB
    case "Hangul_U": return 0x000ECC
    case "Hangul_WEO": return 0x000ECD
    case "Hangul_WE": return 0x000ECE
    case "Hangul_WI": return 0x000ECF
    case "Hangul_YU": return 0x000ED0
    case "Hangul_EU": return 0x000ED1
    case "Hangul_YI": return 0x000ED2
    case "Hangul_I": return 0x000ED3
    case "Hangul_J_Kiyeog": return 0x000ED4
    case "Hangul_J_SsangKiyeog": return 0x000ED5
    case "Hangul_J_KiyeogSios": return 0x000ED6
    case "Hangul_J_Nieun": return 0x000ED7
    case "Hangul_J_NieunJieuj": return 0x000ED8
    case "Hangul_J_NieunHieuh": return 0x000ED9
    case "Hangul_J_Dikeud": return 0x000EDA
    case "Hangul_J_Rieul": return 0x000EDB
    case "Hangul_J_RieulKiyeog": return 0x000EDC
    case "Hangul_J_RieulMieum": return 0x000EDD
    case "Hangul_J_RieulPieub": return 0x000EDE
    case "Hangul_J_RieulSios": return 0x000EDF
    case "Hangul_J_RieulTieut": return 0x000EE0
    case "Hangul_J_RieulPhieuf": return 0x000EE1
    case "Hangul_J_RieulHieuh": return 0x000EE2
    case "Hangul_J_Mieum": return 0x000EE3
    case "Hangul_J_Pieub": return 0x000EE4
    case "Hangul_J_PieubSios": return 0x000EE5
    case "Hangul_J_Sios": return 0x000EE6
    case "Hangul_J_SsangSios": return 0x000EE7
    case "Hangul_J_Ieung": return 0x000EE8
    case "Hangul_J_Jieuj": return 0x000EE9
    case "Hangul_J_Cieuc": return 0x000EEA
    case "Hangul_J_Khieuq": return 0x000EEB
    case "Hangul_J_Tieut": return 0x000EEC
    case "Hangul_J_Phieuf": return 0x000EED
    case "Hangul_J_Hieuh": return 0x000EEE
    case "Hangul_RieulYeorinHieuh": return 0x000EEF
    case "Hangul_SunkyeongeumMieum": return 0x000EF0
    case "Hangul_SunkyeongeumPieub": return 0x000EF1
    case "Hangul_PanSios": return 0x000EF2
    case "Hangul_KkogjiDalrinIeung": return 0x000EF3
    case "Hangul_SunkyeongeumPhieuf": return 0x000EF4
    case "Hangul_YeorinHieuh": return 0x000EF5
    case "Hangul_AraeA": return 0x000EF6
    case "Hangul_AraeAE": return 0x000EF7
    case "Hangul_J_PanSios": return 0x000EF8
    case "Hangul_J_KkogjiDalrinIeung": return 0x000EF9
    case "Hangul_J_YeorinHieuh": return 0x000EFA
    case "Korean_Won": return 0x000EFF
    case "OE": return 0x0013BC
    case "oe": return 0x0013BD
    case "Ydiaeresis": return 0x0013BE
    case "EcuSign": return 0x0020A0
    case "ColonSign": return 0x0020A1
    case "CruzeiroSign": return 0x0020A2
    case "FFrancSign": return 0x0020A3
    case "LiraSign": return 0x0020A4
    case "MillSign": return 0x0020A5
    case "NairaSign": return 0x0020A6
    case "PesetaSign": return 0x0020A7
    case "RupeeSign": return 0x0020A8
    case "WonSign": return 0x0020A9
    case "NewSheqelSign": return 0x0020AA
    case "DongSign": return 0x0020AB
    case "EuroSign": return 0x0020AC
    case "3270_Duplicate": return 0x00FD01
    case "3270_FieldMark": return 0x00FD02
    case "3270_Right2": return 0x00FD03
    case "3270_Left2": return 0x00FD04
    case "3270_BackTab": return 0x00FD05
    case "3270_EraseEOF": return 0x00FD06
    case "3270_EraseInput": return 0x00FD07
    case "3270_Reset": return 0x00FD08
    case "3270_Quit": return 0x00FD09
    case "3270_PA1": return 0x00FD0A
    case "3270_PA2": return 0x00FD0B
    case "3270_PA3": return 0x00FD0C
    case "3270_Test": return 0x00FD0D
    case "3270_Attn": return 0x00FD0E
    case "3270_CursorBlink": return 0x00FD0F
    case "3270_AltCursor": return 0x00FD10
    case "3270_KeyClick": return 0x00FD11
    case "3270_Jump": return 0x00FD12
    case "3270_Ident": return 0x00FD13
    case "3270_Rule": return 0x00FD14
    case "3270_Copy": return 0x00FD15
    case "3270_Play": return 0x00FD16
    case "3270_Setup": return 0x00FD17
    case "3270_Record": return 0x00FD18
    case "3270_ChangeScreen": return 0x00FD19
    case "3270_DeleteWord": return 0x00FD1A
    case "3270_ExSelect": return 0x00FD1B
    case "3270_CursorSelect": return 0x00FD1C
    case "3270_PrintScreen": return 0x00FD1D
    case "3270_Enter": return 0x00FD1E
    case "ISO_Lock": return 0x00FE01
    case "ISO_Level2_Latch": return 0x00FE02
    case "ISO_Level3_Shift": return 0x00FE03
    case "ISO_Level3_Latch": return 0x00FE04
    case "ISO_Level3_Lock": return 0x00FE05
    case "ISO_Group_Latch": return 0x00FE06
    case "ISO_Group_Lock": return 0x00FE07
    case "ISO_Next_Group": return 0x00FE08
    case "ISO_Next_Group_Lock": return 0x00FE09
    case "ISO_Prev_Group": return 0x00FE0A
    case "ISO_Prev_Group_Lock": return 0x00FE0B
    case "ISO_First_Group": return 0x00FE0C
    case "ISO_First_Group_Lock": return 0x00FE0D
    case "ISO_Last_Group": return 0x00FE0E
    case "ISO_Last_Group_Lock": return 0x00FE0F
    case "ISO_Left_Tab": return 0x00FE20
    case "ISO_Move_Line_Up": return 0x00FE21
    case "ISO_Move_Line_Down": return 0x00FE22
    case "ISO_Partial_Line_Up": return 0x00FE23
    case "ISO_Partial_Line_Down": return 0x00FE24
    case "ISO_Partial_Space_Left": return 0x00FE25
    case "ISO_Partial_Space_Right": return 0x00FE26
    case "ISO_Set_Margin_Left": return 0x00FE27
    case "ISO_Set_Margin_Right": return 0x00FE28
    case "ISO_Release_Margin_Left": return 0x00FE29
    case "ISO_Release_Margin_Right": return 0x00FE2A
    case "ISO_Release_Both_Margins": return 0x00FE2B
    case "ISO_Fast_Cursor_Left": return 0x00FE2C
    case "ISO_Fast_Cursor_Right": return 0x00FE2D
    case "ISO_Fast_Cursor_Up": return 0x00FE2E
    case "ISO_Fast_Cursor_Down": return 0x00FE2F
    case "ISO_Continuous_Underline": return 0x00FE30
    case "ISO_Discontinuous_Underline": return 0x00FE31
    case "ISO_Emphasize": return 0x00FE32
    case "ISO_Center_Object": return 0x00FE33
    case "ISO_Enter": return 0x00FE34
    case "dead_grave": return 0x00FE50
    case "dead_acute": return 0x00FE51
    case "dead_circumflex": return 0x00FE52
    case "dead_tilde": return 0x00FE53
    case "dead_macron": return 0x00FE54
    case "dead_breve": return 0x00FE55
    case "dead_abovedot": return 0x00FE56
    case "dead_diaeresis": return 0x00FE57
    case "dead_abovering": return 0x00FE58
    case "dead_doubleacute": return 0x00FE59
    case "dead_caron": return 0x00FE5A
    case "dead_cedilla": return 0x00FE5B
    case "dead_ogonek": return 0x00FE5C
    case "dead_iota": return 0x00FE5D
    case "dead_voiced_sound": return 0x00FE5E
    case "dead_semivoiced_sound": return 0x00FE5F
    case "dead_belowdot": return 0x00FE60
    case "dead_hook": return 0x00FE61
    case "dead_horn": return 0x00FE62
    // auxialiary
    case "AccessX_Enable": return 0x00FE70
    case "AccessX_Feedback_Enable": return 0x00FE71
    case "RepeatKeys_Enable": return 0x00FE72
    case "SlowKeys_Enable": return 0x00FE73
    case "BounceKeys_Enable": return 0x00FE74
    case "StickyKeys_Enable": return 0x00FE75
    case "MouseKeys_Enable": return 0x00FE76
    case "MouseKeys_Accel_Enable": return 0x00FE77
    case "Overlay1_Enable": return 0x00FE78
    case "Overlay2_Enable": return 0x00FE79
    case "AudibleBell_Enable": return 0x00FE7A
    case "First_Virtual_Screen": return 0x00FED0
    case "Prev_Virtual_Screen": return 0x00FED1
    case "Next_Virtual_Screen": return 0x00FED2
    case "Last_Virtual_Screen": return 0x00FED4
    case "Terminate_Server": return 0x00FED5
    case "Pointer_Left": return 0x00FEE0
    case "Pointer_Right": return 0x00FEE1
    case "Pointer_Up": return 0x00FEE2
    case "Pointer_Down": return 0x00FEE3
    case "Pointer_UpLeft": return 0x00FEE4
    case "Pointer_UpRight": return 0x00FEE5
    case "Pointer_DownLeft": return 0x00FEE6
    case "Pointer_DownRight": return 0x00FEE7
    case "Pointer_Button_Dflt": return 0x00FEE8
    case "Pointer_Button1": return 0x00FEE9
    case "Pointer_Button2": return 0x00FEEA
    case "Pointer_Button3": return 0x00FEEB
    case "Pointer_Button4": return 0x00FEEC
    case "Pointer_Button5": return 0x00FEED
    case "Pointer_DblClick_Dflt": return 0x00FEEE
    case "Pointer_DblClick1": return 0x00FEEF
    case "Pointer_DblClick2": return 0x00FEF0
    case "Pointer_DblClick3": return 0x00FEF1
    case "Pointer_DblClick4": return 0x00FEF2
    case "Pointer_DblClick5": return 0x00FEF3
    case "Pointer_Drag_Dflt": return 0x00FEF4
    case "Pointer_Drag1": return 0x00FEF5
    case "Pointer_Drag2": return 0x00FEF6
    case "Pointer_Drag3": return 0x00FEF7
    case "Pointer_Drag4": return 0x00FEF8
    case "Pointer_EnableKeys": return 0x00FEF9
    case "Pointer_Accelerate": return 0x00FEFA
    case "Pointer_DfltBtnNext": return 0x00FEFB
    case "Pointer_DfltBtnPrev": return 0x00FEFC
    case "Pointer_Drag5": return 0x00FEFD
    case "BackSpace": return 0x00FF08
    case "Tab": return 0x00FF09
    case "Linefeed": return 0x00FF0A
    case "Clear": return 0x00FF0B
    case "Return": return 0x00FF0D
    case "Pause": return 0x00FF13
    case "Scroll_Lock": return 0x00FF14
    case "Sys_Req": return 0x00FF15
    case "Escape": return 0x00FF1B
    case "Multi_key": return 0x00FF20
    case "Kanji": return 0x00FF21
    case "Muhenkan": return 0x00FF22
    case "Henkan": return 0x00FF23
    case "Henkan_Mode": return 0x00FF23
    case "Romaji": return 0x00FF24
    case "Hiragana": return 0x00FF25
    case "Katakana": return 0x00FF26
    case "Hiragana_Katakana": return 0x00FF27
    case "Zenkaku": return 0x00FF28
    case "Hankaku": return 0x00FF29
    case "Zenkaku_Hankaku": return 0x00FF2A
    case "Touroku": return 0x00FF2B
    case "Massyo": return 0x00FF2C
    case "Kana_Lock": return 0x00FF2D
    case "Kana_Shift": return 0x00FF2E
    case "Eisu_Shift": return 0x00FF2F
    case "Eisu_toggle": return 0x00FF30
    case "Hangul": return 0x00FF31
    case "Hangul_Start": return 0x00FF32
    case "Hangul_End": return 0x00FF33
    case "Hangul_Hanja": return 0x00FF34
    case "Hangul_Jamo": return 0x00FF35
    case "Hangul_Romaja": return 0x00FF36
    case "Codeinput": return 0x00FF37
    case "Hangul_Jeonja": return 0x00FF38
    case "Hangul_Banja": return 0x00FF39
    case "Hangul_PreHanja": return 0x00FF3A
    case "Hangul_PostHanja": return 0x00FF3B
    case "SingleCandidate": return 0x00FF3C
    case "MultipleCandidate": return 0x00FF3D
    case "PreviousCandidate": return 0x00FF3E
    case "Hangul_Special": return 0x00FF3F
    case "Home": return 0x00FF50
    case "Left": return 0x00FF51
    case "Up": return 0x00FF52
    case "Right": return 0x00FF53
    case "Down": return 0x00FF54
    case "Page_Up": return 0x00FF55
    case "Prior": return 0x00FF55
    case "Page_Down": return 0x00FF56
    case "Next": return 0x00FF56
    case "End": return 0x00FF57
    case "Begin": return 0x00FF58
    case "Select": return 0x00FF60
    case "Print": return 0x00FF61
    case "Execute": return 0x00FF62
    case "Insert": return 0x00FF63
    case "Undo": return 0x00FF65
    case "Redo": return 0x00FF66
    case "Menu": return 0x00FF67
    case "Find": return 0x00FF68
    case "Cancel": return 0x00FF69
    case "Help": return 0x00FF6A
    case "Break": return 0x00FF6B
    case "Arabic_switch": return 0x00FF7E
    case "Greek_switch": return 0x00FF7E
    case "Hangul_switch": return 0x00FF7E
    case "Hebrew_switch": return 0x00FF7E
    case "ISO_Group_Shift": return 0x00FF7E
    case "Mode_switch": return 0x00FF7E
    case "kana_switch": return 0x00FF7E
    case "script_switch": return 0x00FF7E
    case "Num_Lock": return 0x00FF7F
    case "KP_Space": return 0x00FF80
    case "KP_Tab": return 0x00FF89
    case "KP_Enter": return 0x00FF8D
    case "KP_F1": return 0x00FF91
    case "KP_F2": return 0x00FF92
    case "KP_F3": return 0x00FF93
    case "KP_F4": return 0x00FF94
    case "KP_Home": return 0x00FF95
    case "KP_Left": return 0x00FF96
    case "KP_Up": return 0x00FF97
    case "KP_Right": return 0x00FF98
    case "KP_Down": return 0x00FF99
    case "KP_Page_Up": return 0x00FF9A
    case "KP_Prior": return 0x00FF9A
    case "KP_Page_Down": return 0x00FF9B
    case "KP_Next": return 0x00FF9B
    case "KP_End": return 0x00FF9C
    case "KP_Begin": return 0x00FF9D
    case "KP_Insert": return 0x00FF9E
    case "KP_Delete": return 0x00FF9F
    case "KP_Multiply": return 0x00FFAA
    case "KP_Add": return 0x00FFAB
    case "KP_Separator": return 0x00FFAC
    case "KP_Subtract": return 0x00FFAD
    case "KP_Decimal": return 0x00FFAE
    case "KP_Divide": return 0x00FFAF
    case "KP_0": return 0x00FFB0
    case "KP_1": return 0x00FFB1
    case "KP_2": return 0x00FFB2
    case "KP_3": return 0x00FFB3
    case "KP_4": return 0x00FFB4
    case "KP_5": return 0x00FFB5
    case "KP_6": return 0x00FFB6
    case "KP_7": return 0x00FFB7
    case "KP_8": return 0x00FFB8
    case "KP_9": return 0x00FFB9
    case "KP_Equal": return 0x00FFBD
    case "F1": return 0x00FFBE
    case "F2": return 0x00FFBF
    case "F3": return 0x00FFC0
    case "F4": return 0x00FFC1
    case "F5": return 0x00FFC2
    case "F6": return 0x00FFC3
    case "F7": return 0x00FFC4
    case "F8": return 0x00FFC5
    case "F9": return 0x00FFC6
    case "F10": return 0x00FFC7
    case "F11": return 0x00FFC8
    case "F12": return 0x00FFC9
    case "F13": return 0x00FFCA
    case "F14": return 0x00FFCB
    case "F15": return 0x00FFCC
    case "F16": return 0x00FFCD
    case "F17": return 0x00FFCE
    case "F18": return 0x00FFCF
    case "F19": return 0x00FFD0
    case "F20": return 0x00FFD1
    case "F21": return 0x00FFD2
    case "F22": return 0x00FFD3
    case "F23": return 0x00FFD4
    case "F24": return 0x00FFD5
    case "F25": return 0x00FFD6
    case "F26": return 0x00FFD7
    case "F27": return 0x00FFD8
    case "F28": return 0x00FFD9
    case "F29": return 0x00FFDA
    case "F30": return 0x00FFDB
    case "F31": return 0x00FFDC
    case "F32": return 0x00FFDD
    case "F33": return 0x00FFDE
    case "F34": return 0x00FFDF
    case "F35": return 0x00FFE0
    case "Shift_L": return 0x00FFE1
    case "Shift_R": return 0x00FFE2
    case "Control_L": return 0x00FFE3
    case "Control_R": return 0x00FFE4
    case "Caps_Lock": return 0x00FFE5
    case "Shift_Lock": return 0x00FFE6
    case "Meta_L": return 0x00FFE7
    case "Meta_R": return 0x00FFE8
    case "Alt_L": return 0x00FFE9
    case "Alt_R": return 0x00FFEA
    case "Super_L": return 0x00FFEB
    case "Super_R": return 0x00FFEC
    case "Hyper_L": return 0x00FFED
    case "Hyper_R": return 0x00FFEE
    case "Delete": return 0x00FFFF
    default: return 0xFFFFFF
    }
  }
}  // RimeKeycode
