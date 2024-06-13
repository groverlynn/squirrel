import Carbon
import Foundation

struct RimeInputModes: OptionSet, Sendable {
  let rawValue: CInt
  static let DEFAULT = RimeInputModes(rawValue: 1 << 0)
  static let HANS = RimeInputModes(rawValue: 1 << 0)
  static let HANT = RimeInputModes(rawValue: 1 << 1)
  static let CANT = RimeInputModes(rawValue: 1 << 2)

  init(rawValue: CInt) {
    self.rawValue = rawValue
  }

  init?(code: String) {
    switch code {
    case "HANS", "Hans", "hans": self = .HANS
    case "HANT", "Hant", "hant": self = .HANT
    case "CANT", "Cant", "cant": self = .CANT
    default: return nil
    }
  }
}  // RimeInputModes

extension SquirrelApp {
  static let property = [kTISPropertyBundleID!: Bundle.main.bundleIdentifier! as CFString] as CFDictionary
  static let InputModeIDHans = "im.rime.inputmethod.Squirrel.Hans" as CFString
  static let InputModeIDHant = "im.rime.inputmethod.Squirrel.Hant" as CFString
  static let InputModeIDCant = "im.rime.inputmethod.Squirrel.Cant" as CFString
  static let preferences = Bundle.preferredLocalizations(from: ["zh-Hans", "zh-Hant", "zh-HK"], forPreferences: nil)

  static func RegisterInputSource() {
    guard !GetEnabledInputModes(includeAllInstalled: true).isEmpty else { // Already registered
      print("Squirrel is already registered."); return
    }
    let bundlePath = NSURL(fileURLWithPath: "/Library/Input Methods/Squirrel.App", isDirectory: false)
    let registerError = TISRegisterInputSource(bundlePath)
    if registerError == noErr {
      print("Squirrel has been successfully registered at \(bundlePath.path!) .")
    } else {
      print("Squirrel failed to register at \(bundlePath.path!) (error code: \(registerError)")
    }
  }

  static func EnableInputSource(_ modes: RimeInputModes) {
    guard !GetEnabledInputModes(includeAllInstalled: false).isEmpty else { // keep user's manually enabled input modes
      print("Squirrel input method(s) is already enabled."); return
    }
    var inputModesToEnable: RimeInputModes = modes
    if inputModesToEnable.isEmpty {
      if !preferences.isEmpty {
        if preferences[0].caseInsensitiveCompare("zh-Hans") == .orderedSame {
          inputModesToEnable.insert(.HANS)
        } else if preferences[0].caseInsensitiveCompare("zh-Hant") == .orderedSame {
          inputModesToEnable.insert(.HANT)
        } else if preferences[0].caseInsensitiveCompare("zh-HK") == .orderedSame {
          inputModesToEnable.insert(.CANT)
        }
      } else {
        inputModesToEnable = [.HANS]
      }
    }
    let sourceList = TISCreateInputSourceList(property, true).takeUnretainedValue() as! [TISInputSource]
    for source in sourceList {
      guard let sourceID: CFString = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID)), (sourceID == InputModeIDHans && inputModesToEnable.contains(.HANS)) || (sourceID == InputModeIDHant && inputModesToEnable.contains(.HANT)) || (sourceID == InputModeIDCant && inputModesToEnable.contains(.CANT)) else { continue }
        // print("Examining input source: \(sourceID)")
      guard let isEnabled: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)), !CFBooleanGetValue(isEnabled) else { continue }
      let enableError: OSStatus = TISEnableInputSource(source)
      if enableError != noErr {
        print("Failed to enable input source: \(sourceID) (error code:\(enableError)")
      } else {
        print("Enabled input source: \(sourceID)")
      }
    }
  }

  static func SelectInputSource(_ mode: RimeInputModes?) {
    let enabledInputModes: RimeInputModes = GetEnabledInputModes(includeAllInstalled: false)
    var inputModeToSelect: RimeInputModes? = mode
    if inputModeToSelect == nil || !enabledInputModes.contains(inputModeToSelect!) {
      for language in preferences {
        if language.caseInsensitiveCompare("zh-Hans") == .orderedSame && enabledInputModes.contains(.HANS) {
          inputModeToSelect = .HANS; break
        }
        if language.caseInsensitiveCompare("zh-Hant") == .orderedSame && enabledInputModes.contains(.HANT) {
          inputModeToSelect = .HANT; break
        }
        if language.caseInsensitiveCompare("zh-HK") == .orderedSame && enabledInputModes.contains(.CANT) {
          inputModeToSelect = .CANT; break
        }
      }
    }
    guard inputModeToSelect != nil else {
      print("No enabled input sources."); return
    }
    let sourceList = TISCreateInputSourceList(property, false).takeUnretainedValue() as! [TISInputSource]
    for source in sourceList {
      guard let sourceID: CFString = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID)), (sourceID == InputModeIDHans && inputModeToSelect == .HANS) || (sourceID == InputModeIDHant && inputModeToSelect == .HANT) || (sourceID == InputModeIDCant && inputModeToSelect == .CANT) else { continue }
      // print("Examining input source: \(sourceID)")
      // select the first enabled input mode in Squirrel
      guard let isSelectable: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)), let isSelected: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelected)), !CFBooleanGetValue(isSelected) && CFBooleanGetValue(isSelectable) else { continue }
      let selectError: OSStatus = TISSelectInputSource(source)
      if selectError != noErr {
        print("Failed to select input source: \(sourceID) (error code: \(selectError)")
      } else {
        print("Selected input source: \(sourceID)"); break
      }
    }
  }

  static func DisableInputSource() {
    let sourceList = TISCreateInputSourceList(property, false).takeUnretainedValue() as! [TISInputSource]
    for source in sourceList {
      guard let sourceID: CFString = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID)), sourceID == InputModeIDHans || sourceID == InputModeIDHant || sourceID == InputModeIDCant else { continue }
        // print("Examining input source: \(sourceID)")
      let disableError: OSStatus = TISDisableInputSource(source)
      if disableError != noErr {
        print("Failed to disable input source: \(sourceID) (error code: \(disableError)")
      } else {
        print("Disabled input source: \(sourceID)")
      }
    }
  }

  private static func GetEnabledInputModes(includeAllInstalled: Bool) -> RimeInputModes {
    var inputModes: RimeInputModes = []
    let sourceList = TISCreateInputSourceList(property, includeAllInstalled).takeUnretainedValue() as! [TISInputSource]
    for source in sourceList {
      guard let sourceID: CFString = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID)) else { continue }
        // print("Examining input source: \(sourceID)")
      switch sourceID {
      case InputModeIDHans: inputModes.insert(.HANS)
      case InputModeIDHant: inputModes.insert(.HANT)
      case InputModeIDCant: inputModes.insert(.CANT)
      default: continue
      }
    }
    return inputModes
  }
}  // SquirrelApp
