import AppKit
import Cocoa

final class SquirrelOptionSwitcher: NSObject {
  static let Scripts: [String] = ["zh-Hans", "zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh-SG", "zh-CN", "zh"]

  private(set) var schemaId: String
  private(set) var currentScriptVariant: String
  private var optionNames: Set<String>
  private(set) var optionStates: Set<String>
  private var scriptVariantOptions: [String: String]
  private var switcher: [String: String]
  private var optionGroups: [String: Set<String>]

  init(schemaId: String?, switcher: [String: String]?, optionGroups: [String: Set<String>]?, defaultScriptVariant: String?, scriptVariantOptions: [String: String]?) {
    self.schemaId = schemaId ?? ""
    self.switcher = switcher ?? [:]
    self.optionGroups = optionGroups ?? [:]
    optionNames = switcher == nil ? [] : Set(switcher!.keys)
    optionStates = switcher == nil ? [] : Set(switcher!.values)
    currentScriptVariant = defaultScriptVariant ?? Bundle.preferredLocalizations(from: Self.Scripts)[0]
    self.scriptVariantOptions = scriptVariantOptions ?? [:]
    super.init()
  }

  convenience init(schemaId: String?) {
    self.init(schemaId: schemaId, switcher: [:], optionGroups: [:], defaultScriptVariant: nil, scriptVariantOptions: [:])
  }

  override convenience init() {
    self.init(schemaId: "", switcher: [:], optionGroups: [:], defaultScriptVariant: nil, scriptVariantOptions: [:])
  }

  // return whether switcher options has been successfully updated
  func updateSwitcher(_ switcher: [String: String]!) -> Bool {
    guard !self.switcher.isEmpty && switcher?.count == self.switcher.count else { return false }
    let optionNames: Set<String> = Set(switcher.keys)
    if optionNames == self.optionNames {
      self.switcher = switcher
      optionStates = Set(switcher.values)
      return true
    }
    return false
  }

  func updateGroupState(_ optionState: String, ofOption optionName: String) -> Bool {
    guard let optionGroup = optionGroups[optionName] else { return false }
    if optionGroup.count == 1 {
      if optionName != (optionState.hasPrefix("!") ? String(optionState.dropFirst()) : optionState) {
        return false
      }
      switcher[optionName] = optionState
    } else if optionGroup.contains(optionState) {
      optionGroup.forEach{ switcher[$0] = optionState }
    }
    optionStates = Set(switcher.values)
    return true
  }

  func updateCurrentScriptVariant(_ scriptVariant: String) -> Bool {
    guard !scriptVariantOptions.isEmpty else { return false }
    guard let scriptVariantCode = scriptVariantOptions[scriptVariant] else { return false }
    currentScriptVariant = scriptVariantCode
    return true
  }

  func update(withRimeSession session: RimeSessionId) {
    guard !switcher.isEmpty && session != 0 else { return }
    for state in optionStates {
      var updatedState: String?
      let optionGroup: [String] = Array(switcher.filter { (key, value) in value == state }.keys)
      _ = optionGroup.first(where: { if RimeApi.get_option(session, $0) { updatedState = $0; return true } else { return false } })
      updatedState ?= "!" + optionGroup[0]
      if updatedState != state {
        _ = updateGroupState(updatedState!, ofOption: state)
      }
    }
    // update script variant
    _ = scriptVariantOptions.first(where: { if $0.key.hasPrefix("!") ? !RimeApi.get_option(session, String($0.key.dropFirst())) : RimeApi.get_option(session, $0.key) { _ = updateCurrentScriptVariant($0.key); return true } else { return false } })
  }
}  // SquirrelOptionSwitcher

final class SquirrelAppOptions: NSObject {
  private var appOptions: [String: Any] = [:]

  subscript<T: Any>(option: String) -> T? {
    get { appOptions[option] as? T }
    set { appOptions[option] = newValue }
  }

  func boolValue(forOption option: String) -> Bool {
    if let value = appOptions[option] as? Bool { return value } else { return false }
  }
  func intValue(forOption option: String) -> Int {
    if let value = appOptions[option] as? Int { return value } else { return 0 }
  }
  func doubleValue(forOption option: String) -> Double {
    if let value = appOptions[option] as? Double { return value } else { return 0.0 }
  }
}  // SquirrelAppOptions

final class SquirrelConfig: NSObject {
  static let colorSpaceMap: [String: NSColorSpace] = ["deviceRGB": .deviceRGB, "genericRGB": .genericRGB, "sRGB": .sRGB, "displayP3": .displayP3, "adobeRGB": .adobeRGB1998, "extendedSRGB": .extendedSRGB]

  private var cache: [String: Any]
  private var config: RimeConfig = RimeConfig()
  private var baseConfig: SquirrelConfig?
  private var isOpen: Bool
  private var schemaId: String?
  private var colorSpaceObject: NSColorSpace
  private var colorSpaceName: String
  var colorSpace: String {
    get { return colorSpaceName }
    set {
      let name: String = newValue.replacingOccurrences(of: "_", with: "")
      if name == colorSpaceName { return }
      Self.colorSpaceMap.forEach{ if $0.key.caseInsensitiveCompare(name) == .orderedSame { colorSpaceName = $0.key; colorSpaceObject = $0.value; return } }
    }
  }

  override init() {
    cache = [:]
    isOpen = false
    colorSpaceObject = .sRGB
    colorSpaceName = "sRGB"
    super.init()
  }

  convenience init(_ arg: String) {
    self.init()
    switch arg {
    case "squirrel":
      _ = openBaseConfig()
    case "default":
      _ = open(withConfigId: arg)
    case "user", "installation":
      _ = open(userConfig: arg)
    default:
      _ = open(withSchemaId: arg, baseConfig: nil)
    }
  }

  func openBaseConfig() -> Bool {
    close()
    isOpen = RimeApi.config_open("squirrel", &config)
    return isOpen
  }

  func open(withSchemaId schemaId: String, baseConfig: SquirrelConfig?) -> Bool {
    close()
    isOpen = RimeApi.schema_open(schemaId, &config)
    if isOpen {
      self.schemaId = schemaId
      self.baseConfig = baseConfig ?? SquirrelConfig("squirrel")
    }
    return isOpen
  }

  func open(userConfig configId: String) -> Bool {
    close()
    isOpen = RimeApi.user_config_open(configId, &config)
    return isOpen
  }

  func open(withConfigId configId: String) -> Bool {
    close()
    isOpen = RimeApi.config_open(configId, &config)
    return isOpen
  }

  func close() {
    if isOpen && RimeApi.config_close(&config) {
      isOpen = false
    }
    baseConfig = nil
    schemaId = nil
  }

  deinit {
    close()
    cache.removeAll()
  }

  func hasSection(_ section: String) -> Bool {
    if isOpen {
      var iterator = RimeConfigIterator()
      if RimeApi.config_begin_map(&iterator, &config, section) {
        RimeApi.config_end(&iterator)
        return true
      }
    }
    return false
  }

  func setOption(_ option: String, withBool value: Bool) -> Bool {
    return RimeApi.config_set_bool(&config, option, value)
  }

  func setOption(_ option: String, withInt value: Int) -> Bool {
    return RimeApi.config_set_int(&config, option, CInt(value))
  }

  func setOption(_ option: String, withDouble value: Double) -> Bool {
    return RimeApi.config_set_double(&config, option, value)
  }

  func setOption(_ option: String, withString value: String) -> Bool {
    return RimeApi.config_set_string(&config, option, value)
  }

  func boolValue(forOption option: String) -> Bool {
    return nullableBool(forOption: option, alias: nil) ?? false
  }

  func intValue(forOption option: String) -> Int {
    return nullableInt(forOption: option, alias: nil) ?? 0
  }

  func doubleValue(forOption option: String) -> Double {
    return nullableDouble(forOption: option, alias: nil) ?? 0.0
  }

  func doubleValue(forOption option: String, constraint function: (Double) -> Double) -> Double {
    return function(nullableDouble(forOption: option, alias: nil) ?? 0.0)
  }

  func nullableBool(forOption option: String, alias: String?) -> Bool? {
    if let cachedValue = cachedValue(ofType: Bool.self, forKey: option) {
      return cachedValue
    }
    var value: Bool = false
    if isOpen && RimeApi.config_get_bool(&config, option, &value) {
      cache[option] = value
      return value
    }
    if let aliasOption = option.replaceLastPathComponent(with: alias), isOpen && RimeApi.config_get_bool(&config, aliasOption, &value) {
      cache[option] = value
      return value
    }
    return baseConfig?.nullableBool(forOption: option, alias: alias)
  }

  func nullableInt(forOption option: String, alias: String?) -> Int? {
    if let cachedValue = cachedValue(ofType: Int.self, forKey: option) {
      return cachedValue
    }
    var value: CInt = 0
    if isOpen && RimeApi.config_get_int(&config, option, &value) {
      cache[option] = Int(value)
      return Int(value)
    }
    if let aliasOption = option.replaceLastPathComponent(with: alias), isOpen && RimeApi.config_get_int(&config, aliasOption, &value) {
      cache[option] = Int(value)
      return Int(value)
    }
    return baseConfig?.nullableInt(forOption: option, alias: alias)
  }

  func nullableDouble(forOption option: String, alias: String?) -> Double? {
    if let cachedValue = cachedValue(ofType: Double.self, forKey: option) {
      return cachedValue
    }
    var value: Double = 0
    if isOpen && RimeApi.config_get_double(&config, option, &value) {
      cache[option] = value
      return value
    }
    if let aliasOption = option.replaceLastPathComponent(with: alias), isOpen && RimeApi.config_get_double(&config, aliasOption, &value) {
      cache[option] = value
      return value
    }
    return baseConfig?.nullableDouble(forOption: option, alias: alias)
  }

  func nullableDouble(forOption option: String, alias: String?, constraint function: (Double) -> Double) -> Double? {
    if let value = nullableDouble(forOption: option, alias: alias) {
      return function(value)
    }
    return nil
  }

  func nullableBool(forOption option: String) -> Bool? {
    return nullableBool(forOption: option, alias: nil)
  }

  func nullableInt(forOption option: String) -> Int? {
    return nullableInt(forOption: option, alias: nil)
  }

  func nullableDouble(forOption option: String) -> Double? {
    return nullableDouble(forOption: option, alias: nil)
  }

  func nullableDouble(forOption option: String, constraint function: (Double) -> Double) -> Double? {
    if let value = nullableDouble(forOption: option, alias: nil) {
      return function(value)
    }
    return nil
  }

  func string(forOption option: String, alias: String?) -> String? {
    if let cachedValue = cachedValue(ofType: String.self, forKey: option) {
      return cachedValue
    }
    if isOpen, let value = RimeApi.config_get_cstring(&config, option) {
      let string = String(cString: value).trimmingCharacters(in: .whitespaces)
      cache[option] = string
      return string
    }
    if let aliasOption: String = option.replaceLastPathComponent(with: alias), isOpen, let value = RimeApi.config_get_cstring(&config, aliasOption) {
      let string = String(cString: value).trimmingCharacters(in: .whitespaces)
      cache[option] = string
      return string
    }
    return baseConfig?.string(forOption: option, alias: alias)
  }

  func color(forOption option: String, alias: String?) -> NSColor? {
    if let cachedValue = cachedValue(ofType: NSColor.self, forKey: option) {
      return cachedValue
    }
    if let hexCode = string(forOption: option, alias: alias), let color = color(hexCode: hexCode) {
      cache[option] = color
      return color
    }
    return baseConfig?.color(forOption: option, alias: alias)
  }

  func image(forOption option: String, alias: String?) -> NSImage? {
    if let cachedValue = cachedValue(ofType: NSImage.self, forKey: option) {
      return cachedValue
    }
    if let file = string(forOption: option, alias: alias), let image = image(filePath: file) {
      cache[option] = image
      return image
    }
    return baseConfig?.image(forOption: option, alias: alias)
  }

  func string(forOption option: String) -> String? {
    return string(forOption: option, alias: nil)
  }

  func color(forOption option: String) -> NSColor? {
    return color(forOption: option, alias: nil)
  }

  func image(forOption option: String) -> NSImage? {
    return image(forOption: option, alias: nil)
  }

  func listSize(forOption option: String) -> Int {
    return RimeApi.config_list_size(&config, option)
  }

  func list(forOption option: String) -> [String]? {
    var iterator = RimeConfigIterator()
    guard RimeApi.config_begin_list(&iterator, &config, option) else { return nil }
    var strList: [String] = []
    while RimeApi.config_next(&iterator) {
      strList.append(string(forOption: String(cString: iterator.path!))!)
    }
    RimeApi.config_end(&iterator)
    return strList.count == 0 ? nil : strList
  }

  static let localeScript: [String: String] = ["simplification": "zh-Hans", "simplified": "zh-Hans", "!traditional": "zh-Hans", "traditional": "zh-Hant", "!simplification": "zh-Hant", "!simplified": "zh-Hant"]
  static let localeRegion: [String: String] = ["tw": "zh-TW", "taiwan": "zh-TW", "hk": "zh-HK", "hongkong": "zh-HK", "hong_kong": "zh-HK", "mo": "zh-MO", "macau": "zh-MO", "macao": "zh-MO", "sg": "zh-SG", "singapore": "zh-SG", "cn": "zh-CN", "china": "zh-CN"]

  static func code(scriptVariant: String) -> String {
    return localeScript.first(where: { return $0.key.caseInsensitiveCompare(scriptVariant) == .orderedSame })?.value ?? localeRegion.first(where: { return scriptVariant.range(of: $0.key, options: [.caseInsensitive]) != nil })?.value ?? "zh"
  }

  func optionSwitcherForSchema() -> SquirrelOptionSwitcher {
    guard let schemaId = schemaId, !schemaId.isEmpty && schemaId != "." else {
      return SquirrelOptionSwitcher()
    }
    var switchIter = RimeConfigIterator()
    guard RimeApi.config_begin_list(&switchIter, &config, "switches") else {
      return SquirrelOptionSwitcher(schemaId: schemaId)
    }
    var switcher: [String: String] = [:]
    var optionGroups: [String: Set<String>] = [:]
    var defaultScriptVariant: String?
    var scriptVariantOptions: [String: String] = [:]
    while RimeApi.config_next(&switchIter) {
      let reset = intValue(forOption: String(cString: switchIter.path!) + "/reset")
      if let name = string(forOption: String(cString: switchIter.path!) + "/name") {
        if hasSection("style/!" + name) || hasSection("style/" + name) {
          switcher[name] = reset != 0 ? name : "!" + name
          optionGroups[name] = [name]
        }
        if defaultScriptVariant == nil && (name.caseInsensitiveCompare("simplification") == .orderedSame || name.caseInsensitiveCompare("simplified") == .orderedSame || name.caseInsensitiveCompare("traditional") == .orderedSame) {
          defaultScriptVariant = reset != 0 ? name : "!" + name
          scriptVariantOptions[name] = Self.code(scriptVariant: name)
          scriptVariantOptions["!" + name] = Self.code(scriptVariant: "!" + name)
        }
      } else {
        var optionIter = RimeConfigIterator()
        guard RimeApi.config_begin_list(&optionIter, &config, String(cString: switchIter.path!) + "/options") else { continue }
        var optGroup: [String] = []
        var hasStyleSection: Bool = false
        var hasScriptVariant = defaultScriptVariant != nil
        while RimeApi.config_next(&optionIter) {
          let option: String = string(forOption: String(cString: optionIter.path!))!
          optGroup.append(option)
          hasStyleSection |= hasSection("style/" + option)
          hasScriptVariant |= option.caseInsensitiveCompare("simplification") == .orderedSame || option.caseInsensitiveCompare("simplified") == .orderedSame || option.caseInsensitiveCompare("traditional") == .orderedSame
        }
        RimeApi.config_end(&optionIter)
        if hasStyleSection {
          optGroup.forEach { switcher[$0] = optGroup[reset]; optionGroups[$0] = Set(optGroup) }
        }
        if defaultScriptVariant == nil && hasScriptVariant {
          optGroup.forEach{ scriptVariantOptions[$0] = Self.code(scriptVariant: $0) }
          defaultScriptVariant = scriptVariantOptions[optGroup[reset]]
        }
      }
    }
    RimeApi.config_end(&switchIter)
    return SquirrelOptionSwitcher(schemaId: schemaId, switcher: switcher, optionGroups: optionGroups, defaultScriptVariant: defaultScriptVariant, scriptVariantOptions: scriptVariantOptions)
  }

  func appOptions(forApp bundleId: String) -> SquirrelAppOptions {
    let rootKey = "app_options/" + bundleId
    if let cachedValue = cachedValue(ofType: SquirrelAppOptions.self, forKey: rootKey) {
      return cachedValue
    }
    let appOptions = SquirrelAppOptions()
    var iterator = RimeConfigIterator()
    if !RimeApi.config_begin_map(&iterator, &config, rootKey) {
      cache[rootKey] = appOptions
      return appOptions
    }
    while RimeApi.config_next(&iterator) {
      // print("DEBUG option[\(iterator.index)]: \(iterator.key) (\(iterator.path))")
      let path = String(cString: iterator.path!), key = String(cString: iterator.key!)
      if let boolValue = nullableBool(forOption: path) {
        appOptions[key] = boolValue
      } else if let intValue = nullableInt(forOption: path) {
        appOptions[key] = intValue
      } else if let doubleValue = nullableDouble(forOption: path) {
        appOptions[key] = doubleValue
      }
    }
    RimeApi.config_end(&iterator)
    cache[rootKey] = appOptions
    return appOptions
  }

  // MARK: Private functions

  private func cachedValue<T>(ofType: T.Type, forKey key: String) -> T? {
    if let value = cache[key] as? T { return value } else { return nil }
  }

  private func color(hexCode: String?) -> NSColor? {
    guard let hexCode = hexCode, (hexCode.count == 8 || hexCode.count == 10) && (hexCode.hasPrefix("0x") || hexCode.hasPrefix("0X")) else { return nil }
    let hexScanner = Scanner(string: hexCode)
    var hex: UInt32 = 0x0
    guard hexScanner.scanHexInt32(&hex) && hexScanner.isAtEnd else { return nil }
    let r = CGFloat(hex % 0x100)
    let g = CGFloat(hex / 0x100 % 0x100)
    let b = CGFloat(hex / 0x10000 % 0x100)
    // 0xaaBBGGRR or 0xBBGGRR
    let a = hexCode.count == 10 ? CGFloat(hex / 0x1000000) : 255.0
    let components: [CGFloat] = [r / 255.0, g / 255.0, b / 255.0, a / 255.0]
    return NSColor(colorSpace: colorSpaceObject, components: components, count: 4)
  }

  private func image(filePath: String?) -> NSImage? {
    guard let filePath = filePath else { return nil }
    let imageFile = URL(fileURLWithPath: filePath, isDirectory: false, relativeTo: SquirrelApplicationDelegate.userDataDir).standardizedFileURL
    guard FileManager.default.fileExists(atPath: imageFile.path) else { return nil }
    return NSImage(byReferencing: imageFile)
  }
}  // SquirrelConfig

extension String {
  func unicharIndex(charIndex offset: CInt) -> Int {
    return utf8.index(utf8.startIndex, offsetBy: Int(offset)).utf16Offset(in: self)
  }

  func replaceLastPathComponent(with replacement: String?) -> String? {
    guard let replacement = replacement, let sep = range(of: "/", options: .backwards) else { return replacement }
    return String(self[..<sep.upperBound]) + replacement
  }
}
