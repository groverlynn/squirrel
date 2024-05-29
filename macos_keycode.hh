#ifndef _MACOS_KEYCODE_HH_
#define _MACOS_KEYCODE_HH_

#import <AppKit/AppKit.h>

// credit goes to tekezo@
// https://github.com/tekezo/Karabiner/blob/master/src/bridge/generator/keycode/data/KeyCode.data

enum {
  // powerbook
  kVK_Enter_Powerbook  = 0x34,
  // pc keyboard
  kVK_PC_Application   = 0x6e,
//  kVK_PC_BS            = 0x33, // = delete (backspace)
//  kVK_PC_Del           = 0x75, // = forward delete
//  kVK_PC_Insert        = 0x72, // = help
//  kVK_PC_KeypadNumLock = 0x47, // = keypad clear
//  kVK_PC_Pause         = 0x71, // = F15
  kVK_PC_Power         = 0x7f,
//  kVK_PC_PrintScreen   = 0x69, // = F13
//  kVK_PC_ScrollLock    = 0x6b, // = F14
};

// conversion functions

int RimeModifiers(NSEventModifierFlags mac_modifiers);
int RimeKeycode(ushort mac_keycode);
int RimeKeycode(unichar keychar, bool shift, bool caps);

int RimeModifiers(const char* modifier_name);
int RimeKeycode(const char* key_name);

#endif /* _MACOS_KEYCODE_HH_ */
