import Carbon


struct RimeInputMode: OptionSet {
  let rawValue: CInt
  static let DEFAULT = RimeInputMode(rawValue: 1 << 0)
  static let HANS = RimeInputMode(rawValue: 1 << 0)
  static let HANT = RimeInputMode(rawValue: 1 << 1)
  static let CANT = RimeInputMode(rawValue: 1 << 3)
}


let kInstallPath: String = "/Library/Input Methods/Squirrel.app"

let kHansInputModeID = "im.rime.inputmethod.Squirrel.Hans" as CFString
let kHantInputModeID = "im.rime.inputmethod.Squirrel.Hant" as CFString
let kCantInputModeID = "im.rime.inputmethod.Squirrel.Cant" as CFString

func RegisterInputSource() {
  if (!GetEnabledInputModes().isEmpty) {
    // Already registered
    return
  }
  if let installPathURL = CFURLCreateFromFileSystemRepresentation(
    kCFAllocatorDefault, Array(kInstallPath.utf8), CFIndex(strlen(kInstallPath)), false) {
    TISRegisterInputSource(installPathURL)
    NSLog("Registered input source from %@", kInstallPath)
  }
}

func EnableInputSource() {
  if (!GetEnabledInputModes().isEmpty) {
    // keep user's manually enabled input modes
    return;
  }
  var input_modes_to_enable = RimeInputMode()
  let preferred: CFArray = CFBundleCopyLocalizationsForPreferences(
    ["zh-Hans", "zh-Hant", "zh-HK"] as CFArray, nil)
  if (CFArrayGetCount(preferred) > 0) {
    let language: CFString = CFArrayGetValueAtIndex(preferred, 0) as! CFString
    if (CFStringCompare(language, "zh-Hans" as CFString,
                        [.compareCaseInsensitive]) == .compareEqualTo) {
      input_modes_to_enable.insert(.HANS)
    } else if (CFStringCompare(language, "zh-Hant" as CFString,
                               [.compareCaseInsensitive]) == .compareEqualTo) {
      input_modes_to_enable.insert(.HANT)
    } else if (CFStringCompare(language, "zh-HK" as CFString,
                               [.compareCaseInsensitive]) == .compareEqualTo) {
      input_modes_to_enable.insert(.CANT)
    }
  } else {
    input_modes_to_enable = .HANS
  }
  let property = [kTISPropertyBundleID:
                    CFBundleGetIdentifier(CFBundleGetMainBundle())] as CFDictionary
  let sourceList = TISCreateInputSourceList(property, true) as! CFArray
  for i in 0..<CFArrayGetCount(sourceList) {
    let inputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID = TISGetInputSourceProperty(
      inputSource, kTISPropertyInputSourceID) as! CFString
    // NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo &&
         input_modes_to_enable.contains(.HANS)) ||
        (CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo &&
         input_modes_to_enable.contains(.HANT)) ||
        (CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo &&
         input_modes_to_enable.contains(.CANT))) {
      let isEnabled = TISGetInputSourceProperty(
        inputSource, kTISPropertyInputSourceIsEnabled) as! CFBoolean
      if (!CFBooleanGetValue(isEnabled)) {
        let enableError: OSStatus = TISEnableInputSource(inputSource)
        if (enableError != 0) {
          NSLog("Failed to enable input source: %@ (%@)",
                [sourceID, NSError(domain: NSOSStatusErrorDomain,
                                   code: Int(enableError), userInfo: nil)])
        } else {
          NSLog("Enabled input source: %@", [sourceID])
        }
      }
    }
  }
}

func SelectInputSource() {
  let enabled_input_modes: RimeInputMode = GetEnabledInputModes();
  var input_mode_to_select = RimeInputMode();
  let preferred: CFArray = CFBundleCopyLocalizationsForPreferences(
    ["zh-Hans", "zh-Hant", "zh-HK"] as CFArray, nil)
  for i in 0..<CFArrayGetCount(preferred) {
    let language = CFArrayGetValueAtIndex(preferred, i) as! CFString
    if (CFStringCompare(language, "zh-Hans" as CFString,
                        [.compareCaseInsensitive]) == .compareEqualTo &&
        enabled_input_modes.contains(.HANS)) {
      input_mode_to_select.update(with: .HANS)
      break
    }
    if (CFStringCompare(language, "zh-Hant" as CFString,
                        [.compareCaseInsensitive]) == .compareEqualTo &&
        enabled_input_modes.contains(.HANT)) {
      input_mode_to_select.update(with: .HANT)
      break
    }
    if (CFStringCompare(language, "zh-HK" as CFString,
                        [.compareCaseInsensitive]) == .compareEqualTo &&
        enabled_input_modes.contains(.CANT)) {
      input_mode_to_select.update(with: .CANT)
      break
    }
  }
  if (input_mode_to_select.isEmpty) {
    NSLog("No enabled input sources.")
    return
  }
  let property = [kTISPropertyBundleID:
                    CFBundleGetIdentifier(CFBundleGetMainBundle())] as CFDictionary
  let sourceList = TISCreateInputSourceList(property, false) as! CFArray
  for i in 0..<CFArrayGetCount(sourceList) {
    let inputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID = TISGetInputSourceProperty(
      inputSource, kTISPropertyInputSourceID) as! CFString
    // NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo &&
         input_mode_to_select.contains(.HANS)) ||
        (CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo &&
         input_mode_to_select.contains(.HANT)) ||
        (CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo &&
         input_mode_to_select.contains(.CANT))) {
      // select the first enabled input mode in Squirrel.
      let isSelectable = TISGetInputSourceProperty(
        inputSource, kTISPropertyInputSourceIsSelectCapable) as! CFBoolean
      let isSelected = TISGetInputSourceProperty(
        inputSource, kTISPropertyInputSourceIsSelected) as! CFBoolean
      if (!CFBooleanGetValue(isSelected) && CFBooleanGetValue(isSelectable)) {
        let selectError: OSStatus = TISSelectInputSource(inputSource)
        if (selectError != 0) {
          NSLog("Failed to select input source: %@ (%@)",
                [sourceID, NSError(domain: NSOSStatusErrorDomain, code: Int(selectError))])
        } else {
          NSLog("Selected input source: %@", [sourceID])
          break
        }
      }
    }
  }
}

func DisableInputSource() {
  let property = [kTISPropertyBundleID:
                    CFBundleGetIdentifier(CFBundleGetMainBundle())] as CFDictionary
  let sourceList = TISCreateInputSourceList(property, false) as! CFArray
  for i in (0..<CFArrayGetCount(sourceList)).reversed() {
    let inputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID = TISGetInputSourceProperty(
      inputSource, kTISPropertyInputSourceID) as! CFString
    // NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo ||
        CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo ||
        CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo) {
      let disableError: OSStatus = TISDisableInputSource(inputSource)
      if (disableError != 0) {
        NSLog("Failed to disable input source: %@ (%@)",
              [sourceID, NSError(domain: NSOSStatusErrorDomain, code: Int(disableError))])
      } else {
        NSLog("Disabled input source: %@", [sourceID])
      }
    }
  }
}

func GetEnabledInputModes() -> RimeInputMode {
  var input_modes = RimeInputMode()
  let property = [kTISPropertyBundleID:
                    CFBundleGetIdentifier(CFBundleGetMainBundle())] as CFDictionary
  let sourceList = TISCreateInputSourceList(property, false) as! CFArray
  for i in 0..<CFArrayGetCount(sourceList) {
    let inputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID = TISGetInputSourceProperty(
      inputSource, kTISPropertyInputSourceID) as! CFString
    // NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, []) == .compareEqualTo) {
      input_modes.insert(.HANS)
    } else if (CFStringCompare(sourceID, kHantInputModeID, []) == .compareEqualTo) {
      input_modes.insert(.HANT)
    } else if (CFStringCompare(sourceID, kCantInputModeID, []) == .compareEqualTo) {
      input_modes.insert(.CANT)
    }
  }
  return input_modes
}
