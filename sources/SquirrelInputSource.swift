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
    case "HANS", "Hans", "hans":
      self = .HANS
    case "HANT", "Hant", "hant":
      self = .HANT
    case "CANT", "Cant", "cant":
      self = .CANT
    default:
      return nil
    }
  }
}

final class SquirrelInputSource {
  static let property: NSDictionary = [kTISPropertyBundleID!: Bundle.main.bundleIdentifier! as NSString]
  static let InputModeIDHans = "im.rime.inputmethod.Squirrel.Hans"
  static let InputModeIDHant = "im.rime.inputmethod.Squirrel.Hant"
  static let InputModeIDCant = "im.rime.inputmethod.Squirrel.Cant"
  static let preferences = Bundle.preferredLocalizations(from: ["zh-Hans", "zh-Hant", "zh-HK"], forPreferences: nil)

  static func RegisterInputSource() {
    if !GetEnabledInputModes().isEmpty { // Already registered
      print("Squirrel is already registered."); return
    }
    let bundlePath = NSURL(fileURLWithPath: "/Library/Input Methods/Squirrel.App", isDirectory: false)
    let registerError = TISRegisterInputSource(bundlePath)
    if registerError == noErr {
      print("Squirrel has been successfully registered at \(bundlePath.absoluteString!) .")
    } else {
      let error = NSError(domain: NSOSStatusErrorDomain, code: Int(registerError), userInfo: nil)
      print("Squirrel failed to register at \(bundlePath.absoluteString!) (\(error.debugDescription)")
    }
  }

  static func EnableInputSource(_ modes: RimeInputModes) {
    if !GetEnabledInputModes().isEmpty { // keep user's manually enabled input modes
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
      if let sourceID: CFString = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID)), (sourceID as String == InputModeIDHans && inputModesToEnable.contains(.HANS)) || (sourceID as String == InputModeIDHant && inputModesToEnable.contains(.HANT)) || (sourceID as String == InputModeIDCant && inputModesToEnable.contains(.CANT)) {
        // print("Examining input source: \(sourceID)")
        if let isEnabled: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)), !CFBooleanGetValue(isEnabled) {
          let enableError: OSStatus = TISEnableInputSource(source)
          if enableError != noErr {
            let error = NSError(domain: NSOSStatusErrorDomain, code: Int(enableError), userInfo: nil)
            print("Failed to enable input source: \(sourceID) (\(error.debugDescription))")
          } else {
            print("Enabled input source: \(sourceID)")
          }
        }
      }
    }
  }

  static func SelectInputSource(_ mode: RimeInputModes?) {
    let enabledInputModes: RimeInputModes = GetEnabledInputModes()
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
    if inputModeToSelect == nil {
      print("No enabled input sources."); return
    }
    let sourceList = TISCreateInputSourceList(property, false).takeUnretainedValue() as! [TISInputSource]
    for source in sourceList {
      if let sourceID: CFString = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID)), (sourceID as String == InputModeIDHans && inputModeToSelect == .HANS) || (sourceID as String == InputModeIDHant && inputModeToSelect == .HANT) || (sourceID as String == InputModeIDCant && inputModeToSelect == .CANT) {
        // print("Examining input source: \(sourceID)")
        // select the first enabled input mode in Squirrel
        if let isSelectable: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)), let isSelected: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelected)), !CFBooleanGetValue(isSelected) && CFBooleanGetValue(isSelectable) {
          let selectError: OSStatus = TISSelectInputSource(source)
          if selectError != noErr {
            let error = NSError(domain: NSOSStatusErrorDomain, code: Int(selectError))
            print("Failed to select input source: \(sourceID) (\(error.debugDescription))")
          } else {
            print("Selected input source: \(sourceID)"); break
          }
        }
      }
    }
  }

  static func DisableInputSource() {
    let sourceList = TISCreateInputSourceList(property, false).takeUnretainedValue() as! [TISInputSource]
    for source in sourceList {
      if let sourceID: CFString = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID)), sourceID as String == InputModeIDHans || sourceID as String == InputModeIDHant || sourceID as String == InputModeIDCant {
        // print("Examining input source: \(sourceID)")
        let disableError: OSStatus = TISDisableInputSource(source)
        if disableError != noErr {
          let error = NSError(domain: NSOSStatusErrorDomain, code: Int(disableError))
          print("Failed to disable input source: \(sourceID) (\(error.debugDescription))")
        } else {
          print("Disabled input source: \(sourceID)")
        }
      }
    }
  }

  private static func GetEnabledInputModes() -> RimeInputModes {
    var inputModes: RimeInputModes = []
    let sourceList = TISCreateInputSourceList(property, false).takeUnretainedValue() as! [TISInputSource]
    for source in sourceList {
      if let sourceID: CFString = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID)) {
        // print("Examining input source: \(sourceID)")
        switch sourceID as String {
        case InputModeIDHans:
          inputModes.insert(.HANS)
        case InputModeIDHant:
          inputModes.insert(.HANT)
        case InputModeIDCant:
          inputModes.insert(.CANT)
        default:
          break
        }
      }
    }
    return inputModes
  }
}
