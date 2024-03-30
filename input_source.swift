import Carbon


struct RimeInputMode: OptionSet {
  let rawValue: Int32
  static let DEFAULT_INPUT_MODE = RimeInputMode(rawValue: 1 << 0)
  static let HANS_INPUT_MODE = RimeInputMode(rawValue: 1 << 0)
  static let HANT_INPUT_MODE = RimeInputMode(rawValue: 1 << 1)
  static let CANT_INPUT_MODE = RimeInputMode(rawValue: 1 << 3)
}


let kInstallLocation: String = "/Library/Input Methods/Squirrel.app"

let kHansInputModeID: CFString = "im.rime.inputmethod.Squirrel.Hans" as NSString
let kHantInputModeID: CFString = "im.rime.inputmethod.Squirrel.Hant" as NSString
let kCantInputModeID: CFString = "im.rime.inputmethod.Squirrel.Cant" as NSString


func RegisterInputSource() {
  let installedLocationURL: CFURL? = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, Array(kInstallLocation.utf8), CFIndex(strlen(kInstallLocation)), false)
  if (installedLocationURL != nil) {
    TISRegisterInputSource(installedLocationURL)
    NSLog("Registered input source from %s", kInstallLocation)
  }
}

func ActivateInputSource(modes: RimeInputMode) {
  let sourceList: CFArray = TISCreateInputSourceList(nil, true) as! CFArray
  for i in 0..<CFArrayGetCount(sourceList) {
    let inputSource: TISInputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID: CFString = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) as! CFString
    //NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, CFStringCompareFlags()) == .compareEqualTo && modes.contains(.HANS_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kHantInputModeID, CFStringCompareFlags()) == .compareEqualTo && modes.contains(.HANT_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kCantInputModeID, CFStringCompareFlags()) == .compareEqualTo && modes.contains(.CANT_INPUT_MODE))) {
      let enableError: OSStatus = TISEnableInputSource(inputSource)
      if (enableError != 0) {
        NSLog("Error %d. Failed to enable input mode: %@", [enableError, sourceID])
      } else {
        NSLog("Enabled input mode: %@", [sourceID])
        let isSelectable: CFBoolean = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsSelectCapable) as! CFBoolean
        if (CFBooleanGetValue(isSelectable)) {
          let selectError: OSStatus = TISSelectInputSource(inputSource)
          if (selectError != 0) {
            NSLog("Error %d. Failed to select input mode: %@", [selectError, sourceID])
          } else {
            NSLog("Selected input mode: %@", [sourceID])
          }
        }
      }
    }
  }
}

func DeactivateInputSource() {
  let sourceList: CFArray  = TISCreateInputSourceList(nil, true) as! CFArray
  for i in (0..<CFArrayGetCount(sourceList)).reversed() {
    let inputSource: TISInputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID: CFString = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) as! CFString
    //NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, CFStringCompareFlags()) == .compareEqualTo ||
        CFStringCompare(sourceID, kHantInputModeID, CFStringCompareFlags()) == .compareEqualTo ||
        CFStringCompare(sourceID, kCantInputModeID, CFStringCompareFlags()) == .compareEqualTo) {
      let isEnabled: CFBoolean = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsEnabled) as! CFBoolean
      if (CFBooleanGetValue(isEnabled)) {
        let disableError: OSStatus = TISDisableInputSource(inputSource)
        if (disableError != 0) {
          NSLog("Error %d. Failed to disable input source: %@", [disableError, sourceID])
        } else {
          NSLog("Disabled input source: %@", [sourceID])
        }
      }
    }
  }
}

func GetEnabledInputModes() -> RimeInputMode {
  var input_modes = RimeInputMode()
  let sourceList: CFArray = TISCreateInputSourceList(nil, true) as! CFArray
  for i in 0..<CFArrayGetCount(sourceList) {
    let inputSource: TISInputSource = CFArrayGetValueAtIndex(sourceList, i) as! TISInputSource
    let sourceID: CFString = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) as! CFString
    //NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, CFStringCompareFlags()) == .compareEqualTo ||
        CFStringCompare(sourceID, kHantInputModeID, CFStringCompareFlags()) == .compareEqualTo ||
        CFStringCompare(sourceID, kCantInputModeID, CFStringCompareFlags()) == .compareEqualTo) {
      let isEnabled: CFBoolean = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsEnabled) as! CFBoolean
      if (CFBooleanGetValue(isEnabled)) {
        if (CFStringCompare(sourceID, kHansInputModeID, CFStringCompareFlags()) == .compareEqualTo) {
          input_modes.insert(.HANS_INPUT_MODE)
        } else if (CFStringCompare(sourceID, kHantInputModeID, CFStringCompareFlags()) == .compareEqualTo) {
          input_modes.insert(.HANT_INPUT_MODE)
        } else if (CFStringCompare(sourceID, kCantInputModeID, CFStringCompareFlags()) == .compareEqualTo) {
          input_modes.insert(.CANT_INPUT_MODE)
        }
      }
    }
  }
  if (!input_modes.isEmpty) {
    NSLog("Enabled Input Modes:%s%s%s",
          input_modes.contains(.HANS_INPUT_MODE) ? " Hans" : "",
          input_modes.contains(.HANT_INPUT_MODE) ? " Hant" : "",
          input_modes.contains(.CANT_INPUT_MODE) ? " Cant" : "")
  } else {
    let languages: Array = Bundle.preferredLocalizations(from: ["zh-Hans", "zh-Hant", "zh-HK"])
    if (languages.count > 0) {
      let lang: String = languages.first!
      if (lang == "zh-Hans") {
        input_modes.insert(.HANS_INPUT_MODE)
      } else if (lang == "zh-Hant") {
        input_modes.insert(.HANT_INPUT_MODE)
      } else if (lang == "zh-HK") {
        input_modes.insert(.CANT_INPUT_MODE)
      }
    }
    if (!input_modes.isEmpty) {
      NSLog("Preferred Input Mode:%s%s%s",
            input_modes.contains(.HANS_INPUT_MODE) ? " Hans" : "",
            input_modes.contains(.HANT_INPUT_MODE) ? " Hant" : "",
            input_modes.contains(.CANT_INPUT_MODE) ? " Cant" : "")
    } else {
      input_modes = .HANS_INPUT_MODE
      NSLog("Default Input Mode: Hans")
    }
  }
  return input_modes
}
