import Carbon


struct RimeInputMode: OptionSet {
  let rawValue: CInt
  static let DEFAULT_INPUT_MODE = RimeInputMode(rawValue: 1 << 0)
  static let HANS_INPUT_MODE = RimeInputMode(rawValue: 1 << 0)
  static let HANT_INPUT_MODE = RimeInputMode(rawValue: 1 << 1)
  static let CANT_INPUT_MODE = RimeInputMode(rawValue: 1 << 3)
}


let kInstallPath: String = "/Library/Input Methods/Squirrel.app"

let kHansInputModeID: CFString = "im.rime.inputmethod.Squirrel.Hans" as NSString
let kHantInputModeID: CFString = "im.rime.inputmethod.Squirrel.Hant" as NSString
let kCantInputModeID: CFString = "im.rime.inputmethod.Squirrel.Cant" as NSString

func RegisterInputSource() {
  let input_modes_enabled: RimeInputMode = GetEnabledInputModes()
  if (!input_modes_enabled.isEmpty) { // Already registered
    return;
  }
  let installPathURL: CFURL? = CFURLCreateFromFileSystemRepresentation(
    kCFAllocatorDefault, Array(kInstallPath.utf8), CFIndex(strlen(kInstallPath)), false)
  if (installPathURL != nil) {
    TISRegisterInputSource(installPathURL)
    NSLog("Registered input source from %@", kInstallPath)
  }
}

func EnableInputSource() {
  let input_modes_enabled: RimeInputMode = GetEnabledInputModes()
  if (!input_modes_enabled.isEmpty) {
    // keep user's manually enabled input modes
    return;
  }
  var input_modes_to_enable: RimeInputMode = RimeInputMode()
  let preferred: CFArray = CFBundleCopyLocalizationsForPreferences(["zh-Hans", "zh-Hant", "zh-HK"] as CFArray, nil)
  if (CFArrayGetCount(preferred) > 0) {
    let language: CFString = CFArrayGetValueAtIndex(preferred, 0) as! CFString
    if (CFStringCompare(language, "zh-Hans" as CFString, []) == .compareEqualTo) {
      input_modes_to_enable.insert(.HANS_INPUT_MODE)
    } else if (CFStringCompare(language, "zh-Hant" as CFString, []) == .compareEqualTo) {
      input_modes_to_enable.insert(.HANT_INPUT_MODE)
    } else if (CFStringCompare(language, "zh-HK" as CFString, []) == .compareEqualTo) {
      input_modes_to_enable.insert(.CANT_INPUT_MODE)
    }
  } else {
    input_modes_to_enable = .HANS_INPUT_MODE
  }
  let property: CFDictionary = [kTISPropertyBundleID: CFBundleGetIdentifier(CFBundleGetMainBundle())] as CFDictionary
  let sourceList: CFArray = TISCreateInputSourceList(property, true) as! CFArray
  for i in 0..<CFArrayGetCount(sourceList) {
    let inputSource: TISInputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID: CFString = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) as! CFString
    //NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo &&
         input_modes_to_enable.contains(.HANS_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo &&
         input_modes_to_enable.contains(.HANT_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo &&
         input_modes_to_enable.contains(.CANT_INPUT_MODE))) {
      let isEnabled: CFBoolean = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsEnabled) as! CFBoolean
      if (!CFBooleanGetValue(isEnabled)) {
        let enableError: OSStatus = TISEnableInputSource(inputSource)
        if (enableError != 0) {
          NSLog("Failed to enable input source: %@ (%@)",
                [sourceID, NSError.init(domain: NSOSStatusErrorDomain, code: Int(enableError), userInfo: nil)])
        } else {
          NSLog("Enabled input source: %@", [sourceID])
        }
      }
    }
  }
}

func SelectInputSource() {
  let enabled_input_modes: RimeInputMode = GetEnabledInputModes();
  var input_mode_to_select: RimeInputMode = RimeInputMode();
  let preferred: CFArray = CFBundleCopyLocalizationsForPreferences(["zh-Hans", "zh-Hant", "zh-HK"] as CFArray, nil)
  for i in 0..<CFArrayGetCount(preferred) {
    let language: CFString = CFArrayGetValueAtIndex(preferred, i) as! CFString
    if (CFStringCompare(language, "zh-Hans" as CFString, []) == .compareEqualTo &&
        enabled_input_modes.contains(.HANS_INPUT_MODE)) {
      input_mode_to_select.update(with: .HANS_INPUT_MODE)
      break
    }
    if (CFStringCompare(language, "zh-Hant" as CFString, []) == .compareEqualTo &&
        enabled_input_modes.contains(.HANT_INPUT_MODE)) {
      input_mode_to_select.update(with: .HANT_INPUT_MODE)
      break
    }
    if (CFStringCompare(language, "zh-HK" as CFString, []) == .compareEqualTo &&
        enabled_input_modes.contains(.CANT_INPUT_MODE)) {
      input_mode_to_select.update(with: .CANT_INPUT_MODE)
      break
    }
  }
  if (input_mode_to_select.isEmpty) {
    NSLog("No enabled input sources.")
    return
  }
  let property: CFDictionary = [kTISPropertyBundleID: CFBundleGetIdentifier(CFBundleGetMainBundle())] as CFDictionary
  let sourceList: CFArray = TISCreateInputSourceList(property, false) as! CFArray
  for i in 0..<CFArrayGetCount(sourceList) {
    let inputSource: TISInputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID: CFString = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) as! CFString
    // NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo &&
         input_mode_to_select.contains(.HANS_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo &&
         input_mode_to_select.contains(.HANT_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo &&
         input_mode_to_select.contains(.CANT_INPUT_MODE))) {
      // select the first enabled input mode in Squirrel.
      let isSelectable: CFBoolean = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsSelectCapable) as! CFBoolean
      let isSelected: CFBoolean = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsSelected) as! CFBoolean
      if (!CFBooleanGetValue(isSelected) && CFBooleanGetValue(isSelectable)) {
        let selectError: OSStatus = TISSelectInputSource(inputSource)
        if (selectError != 0) {
          NSLog("Failed to select input source: %@ (%@)",
                [sourceID, NSError.init(domain: NSOSStatusErrorDomain, code: Int(selectError))])
        } else {
          NSLog("Selected input source: %@", [sourceID])
          break
        }
      }
    }
  }
}

func DisableInputSource() {
  let property: CFDictionary = [kTISPropertyBundleID: CFBundleGetIdentifier(CFBundleGetMainBundle())] as CFDictionary
  let sourceList: CFArray = TISCreateInputSourceList(property, false) as! CFArray
  for i in (0..<CFArrayGetCount(sourceList)).reversed() {
    let inputSource: TISInputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID: CFString = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) as! CFString
    //NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo ||
        CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo ||
        CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo) {
      let disableError: OSStatus = TISDisableInputSource(inputSource)
      if (disableError != 0) {
        NSLog("Failed to disable input source: %@ (%@)",
              [sourceID, NSError.init(domain: NSOSStatusErrorDomain, code: Int(disableError))])
      } else {
        NSLog("Disabled input source: %@", [sourceID])
      }
    }
  }
}

func GetEnabledInputModes() -> RimeInputMode {
  var input_modes = RimeInputMode()
  let property: CFDictionary = [kTISPropertyBundleID: CFBundleGetIdentifier(CFBundleGetMainBundle())] as CFDictionary
  let sourceList: CFArray = TISCreateInputSourceList(property, false) as! CFArray
  for i in 0..<CFArrayGetCount(sourceList) {
    let inputSource: TISInputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID: CFString = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) as! CFString
    //NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo ||
        CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo ||
        CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo) {
      let isEnabled: CFBoolean = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsEnabled) as! CFBoolean
      if (CFBooleanGetValue(isEnabled)) {
        if (CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo) {
          input_modes.insert(.HANS_INPUT_MODE)
        } else if (CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo) {
          input_modes.insert(.HANT_INPUT_MODE)
        } else if (CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo) {
          input_modes.insert(.CANT_INPUT_MODE)
        }
      }
    }
  }
  return input_modes
}
