import Carbon
import Foundation

struct RimeInputModes: OptionSet, Sendable, Hashable {
  let rawValue: CInt

  static let Default: Self = .init(rawValue: 1 << 0)
  static let Hans: Self = .init(rawValue: 1 << 0)
  static let Hant: Self = .init(rawValue: 1 << 1)
  static let Cant: Self = .init(rawValue: 1 << 2)

  init(rawValue: CInt) { self.rawValue = rawValue }

  init?(code: String) {
    switch code {
    case "Hans": self = .Hans
    case "Hant": self = .Hant
    case "Cant": self = .Cant
    default: return nil
    }
  }
}  // RimeInputModes

extension SquirrelApp {
  static private let inputModeIDHans: String = "\(bundleId).Hans"
  static private let inputModeIDHant: String = "\(bundleId).Hant"
  static private let inputModeIDCant: String = "\(bundleId).Cant"
  static private let inputModeIDs: Set<String> = [inputModeIDHans, inputModeIDHant, inputModeIDCant]
  static private let inputModeToID: [(mode: RimeInputModes, id: String)] = [(.Hans, inputModeIDHans), (.Hant, inputModeIDHant), (.Cant, inputModeIDCant)]
  static private let preferences: [String] = Bundle.preferredLocalizations(from: ["zh-Hans", "zh-Hant", "zh-HK"], forPreferences: nil)
  static private var property: CFDictionary { [kTISPropertyBundleID : bundleId] as CFDictionary }

  static func RegisterInputSource() {
    guard !GetEnabledInputModes(includeAllInstalled: true).isEmpty else {
      // Already registered
      print("Squirrel is already registered."); return
    }
    let bundlePath: NSURL = .init(fileURLWithPath: "/Library/Input Methods/Squirrel.App", isDirectory: false)
    let registerError: OSStatus = TISRegisterInputSource(bundlePath)
    if registerError == noErr {
      print("Squirrel has been successfully registered at \(bundlePath.path!)")
    } else {
      print("Squirrel failed to register at \(bundlePath.path!) (error code: \(registerError))")
    }
  }

  static func EnableInputSource(_ modes: RimeInputModes) {
    guard !GetEnabledInputModes(includeAllInstalled: false).isEmpty else {
      // keep user's manually enabled input modes
      print("Squirrel input method(s) is already enabled."); return
    }
    var inputModesToEnable: RimeInputModes = modes
    if inputModesToEnable.isEmpty {
      if !preferences.isEmpty {
        inputModesToEnable = switch preferences.first {
        case "zh-Hans": [.Hans]
        case "zh-Hant": [.Hant]
        case "zh-HK": [.Cant]
        default: []
        }
      } else {
        inputModesToEnable = [.Hans]
      }
    }
    let inputModeIDsToEnable: [String] = inputModeToID.filter({ inputModesToEnable.contains($0.mode) }).map(\.id)
    let sourceList: [TISInputSource] = TISCreateInputSourceList(property, true).takeRetainedValue() as! [TISInputSource]
    for source in sourceList {
      guard let sourceID: String = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID), as: CFString.self) as? String, inputModeIDsToEnable.contains(sourceID) else { continue }
      // print("Examining input source: \(sourceID)")
      guard let isEnabled: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)), !CFBooleanGetValue(isEnabled) else { continue }
      let enableError: OSStatus = TISEnableInputSource(source)
      if enableError == noErr {
        print("Enabled input source: \(sourceID)")
      } else {
        print("Failed to enable input source: \(sourceID) (error code: \(enableError))")
      }
    }
  }

  static func SelectInputSource(_ modes: RimeInputModes) {
    let enabledInputModes: RimeInputModes = GetEnabledInputModes(includeAllInstalled: false)
    var inputModeToSelect: RimeInputModes = modes.intersection(enabledInputModes)
    if inputModeToSelect.isEmpty {
      for language in preferences {
        switch language {
        case "zh-Hans": if enabledInputModes.contains(.Hans) { inputModeToSelect = .Hans }
        case "zh-Hant": if enabledInputModes.contains(.Hant) { inputModeToSelect = .Hant }
        case "zh-HK": if enabledInputModes.contains(.Cant) { inputModeToSelect = .Cant }
        default: continue
        }
        break
      }
    }
    if inputModeToSelect.isEmpty {
      print("No enabled input sources."); return
    }
    let inputModeIDToSelect: [String] = inputModeToID.filter({ inputModeToSelect.contains($0.mode) }).map(\.id)
    let sourceList: [TISInputSource] = TISCreateInputSourceList(property, false).takeRetainedValue() as! [TISInputSource]
    for source in sourceList {
      guard let sourceID: String = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID), as: CFString.self) as? String, inputModeIDToSelect.contains(sourceID) else { continue }
      // print("Examining input source: \(sourceID)")
      // select the first enabled input mode in Squirrel
      guard let isSelectable: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)), let isSelected: CFBoolean = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelected)), !CFBooleanGetValue(isSelected), CFBooleanGetValue(isSelectable) else { continue }
      let selectError: OSStatus = TISSelectInputSource(source)
      if selectError == noErr {
        print("Selected input source: \(sourceID)"); break
      } else {
        print("Failed to select input source: \(sourceID) (error code: \(selectError))")
      }
    }
  }

  static func DisableInputSource() {
    let sourceList: [TISInputSource] = TISCreateInputSourceList(property, false).takeRetainedValue() as! [TISInputSource]
    for source in sourceList {
      guard let sourceID: String = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID), as: CFString.self) as? String, inputModeIDs.contains(sourceID) else { continue }
      // print("Examining input source: \(sourceID)")
      let disableError: OSStatus = TISDisableInputSource(source)
      if disableError == noErr {
        print("Disabled input source: \(sourceID)")
      } else {
        print("Failed to disable input source: \(sourceID) (error code: \(disableError))")
      }
    }
  }

  static private func GetEnabledInputModes(includeAllInstalled: Bool) -> RimeInputModes {
    var inputModes: RimeInputModes = []
    let sourceList: [TISInputSource] = TISCreateInputSourceList(property, includeAllInstalled).takeRetainedValue() as! [TISInputSource]
    for source in sourceList {
      guard let sourceID: String = bridge(ptr: TISGetInputSourceProperty(source, kTISPropertyInputSourceID), as: CFString.self) as? String else { continue }
      // print("Examining input source: \(sourceID)")
      switch sourceID {
      case inputModeIDHans: inputModes.insert(.Hans)
      case inputModeIDHant: inputModes.insert(.Hant)
      case inputModeIDCant: inputModes.insert(.Cant)
      default: continue
      }
    }
    return inputModes
  }
}  // SquirrelApp

extension CFString {
  var length: Int { CFStringGetLength(self) }
}
