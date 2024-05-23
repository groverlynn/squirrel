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
    if self.switcher.isEmpty || switcher?.count != self.switcher.count {
      return false
    }
    let optionNames: Set<String> = Set(switcher.keys)
    if optionNames == self.optionNames {
      self.switcher = switcher
      optionStates = Set(switcher.values)
      return true
    }
    return false
  }

  func updateGroupState(_ optionState: String, ofOption optionName: String) -> Bool {
    if let optionGroup = optionGroups[optionName] {
      if optionGroup.count == 1 {
        if optionName != (optionState.hasPrefix("!") ? String(optionState.dropFirst()) : optionState) {
          return false
        }
        switcher[optionName] = optionState
      } else if optionGroup.contains(optionState) {
        for option in optionGroup {
          switcher[option] = optionState
        }
      }
      optionStates = Set(switcher.values)
      return true
    } else {
      return false
    }
  }

  func updateCurrentScriptVariant(_ scriptVariant: String) -> Bool {
    if scriptVariantOptions.isEmpty {
      return false
    }
    if let scriptVariantCode = scriptVariantOptions[scriptVariant] {
      currentScriptVariant = scriptVariantCode
      return true
    } else {
      return false
    }
  }

  func update(withRimeSession session: RimeSessionId) {
    if switcher.isEmpty || session == 0 { return }
    for state in optionStates {
      var updatedState: String?
      let optionGroup: [String] = Array(switcher.filter { (key, value) in value == state }.keys)
      for option in optionGroup {
        if RimeApi.get_option(session, option) {
          updatedState = option; break
        }
      }
      updatedState ?= "!" + optionGroup[0]
      if updatedState != state {
        _ = updateGroupState(updatedState!, ofOption: state)
      }
    }
    // update script variant
    for (option, _) in scriptVariantOptions {
      if option.hasPrefix("!") ? !RimeApi.get_option(session, option.suffix(option.count - 1).withCString { $0 }) : RimeApi.get_option(session, option.withCString { $0 }) {
        _ = updateCurrentScriptVariant(option); break
      }
    }
  }
} // SquirrelOptionSwitcher

struct SquirrelAppOptions {
  private var appOptions: [String: Any]

  init() { appOptions = [:] }

  subscript(key: String) -> Any? {
    get {
      if let value = appOptions[key] {
        if value is Bool.Type {
          return value as! Bool
        } else if value is Int.Type {
          return value as! Int
        } else if value is Double.Type {
          return value as! Double
        }
      }
      return nil
    }
    set (newValue) {
      if newValue is Bool.Type || newValue is Int.Type || newValue is Double.Type {
        appOptions[key] = newValue
      }
    }
  }

  mutating func setValue(_ value: Bool, forKey key: String) {
    appOptions[key] = value
  }

  mutating func setValue(_ value: Int, forKey key: String) {
    appOptions[key] = value
  }

  mutating func setValue(_ value: Double, forKey key: String) {
    appOptions[key] = value
  }

  func boolValue(forKey key: String) -> Bool {
    if let value = appOptions[key], value is Bool.Type {
      return value as! Bool
    }
    return false
  }

  func intValue(forKey key: String) -> Int {
    if let value = appOptions[key], value is Int.Type {
      return value as! Int
    }
    return 0
  }

  func doubleValue(forKey key: String) -> Double {
    if let value = appOptions[key], value is Double.Type {
      return value as! Double
    }
    return 0.0
  }
}

final class SquirrelConfig: NSObject {
  static let colorSpaceMap: [String: NSColorSpace] = ["deviceRGB": .deviceRGB,
                                                      "genericRGB": .genericRGB,
                                                      "sRGB": .sRGB,
                                                      "displayP3": .displayP3,
                                                      "adobeRGB": .adobeRGB1998,
                                                      "extendedSRGB": .extendedSRGB]

  private var cache: [String: Any]
  private var config: RimeConfig = RimeConfig()
  private var baseConfig: SquirrelConfig?
  private var isOpen: Bool
  private var schemaId: String?
  private var colorSpaceObject: NSColorSpace
  private var colorSpaceName: String
  var colorSpace: String {
    get { return colorSpaceName }
    set (newValue) {
      let name: String = newValue.replacingOccurrences(of: "_", with: "")
      if name == colorSpaceName { return }
      for (csName, csObject) in Self.colorSpaceMap {
        if csName.caseInsensitiveCompare(name) == .orderedSame {
          colorSpaceName = csName
          colorSpaceObject = csObject
          return
        }
      }
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
      if baseConfig == nil {
        self.baseConfig = SquirrelConfig("squirrel")
      } else {
        self.baseConfig = baseConfig
      }
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
      baseConfig = nil
      schemaId = nil
      isOpen = false
    }
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
    return RimeApi.config_set_double(&config, option, CDouble(value))
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
    var value: CBool = false
    if isOpen && RimeApi.config_get_bool(&config, option, &value) {
      cache[option] = Bool(value)
      return Bool(value)
    }
    if let aliasOption = option.replaceLastPathComponent(with: alias),
       isOpen && RimeApi.config_get_bool(&config, aliasOption, &value) {
      cache[option] = Bool(value)
      return Bool(value)
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
    if let aliasOption = option.replaceLastPathComponent(with: alias),
       isOpen && RimeApi.config_get_int(&config, aliasOption, &value) {
      cache[option] = Int(value)
      return Int(value)
    }
    return baseConfig?.nullableInt(forOption: option, alias: alias)
  }

  func nullableDouble(forOption option: String, alias: String?) -> Double? {
    if let cachedValue = cachedValue(ofType: Double.self, forKey: option) {
      return cachedValue
    }
    var value: CDouble = 0
    if isOpen && RimeApi.config_get_double(&config, option, &value) {
      cache[option] = Double(value)
      return Double(value)
    }
    if let aliasOption = option.replaceLastPathComponent(with: alias),
       isOpen && RimeApi.config_get_double(&config, aliasOption, &value) {
      cache[option] = Double(value)
      return Double(value)
    }
    return baseConfig?.nullableDouble(forOption: option, alias: alias)
  }

  func nullableDouble(forOption option: String, alias: String?, constraint function: (CDouble) -> CDouble) -> Double? {
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

  func nullableDouble(forOption option: String,
                      constraint function: (CDouble) -> CDouble) -> Double? {
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
      let str = String(cString: value).trimmingCharacters(in: .whitespaces)
      cache[option] = str
      return str
    }
    if let aliasOption: String = option.replaceLastPathComponent(with: alias), isOpen,
       let value = RimeApi.config_get_cstring(&config, aliasOption) {
      let str = String(cString: value).trimmingCharacters(in: .whitespaces)
      cache[option] = str
      return str
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
    if !RimeApi.config_begin_list(&iterator, &config, option) {
      return nil
    }
    var strList: [String] = []
    while RimeApi.config_next(&iterator) {
      strList.append(string(forOption: String(cString: iterator.path!))!)
    }
    RimeApi.config_end(&iterator)
    return strList.count == 0 ? nil : strList
  }

  static let localeScript: [String: String] = ["simplification": "zh-Hans",
                                               "simplified": "zh-Hans",
                                               "!traditional": "zh-Hans",
                                               "traditional": "zh-Hant",
                                               "!simplification": "zh-Hant",
                                               "!simplified": "zh-Hant"]
  static let localeRegion: [String: String] = ["tw": "zh-TW", "taiwan": "zh-TW",
                                               "hk": "zh-HK", "hongkong": "zh-HK",
                                               "hong_kong": "zh-HK", "mo": "zh-MO",
                                               "macau": "zh-MO", "macao": "zh-MO",
                                               "sg": "zh-SG", "singapore": "zh-SG",
                                               "cn": "zh-CN", "china": "zh-CN"]

  static func code(scriptVariant: String) -> String {
    for (script, locale) in localeScript {
      if script.caseInsensitiveCompare(scriptVariant) == .orderedSame {
        return locale
      }
    }
    for (region, locale) in localeRegion {
      if scriptVariant.range(of: region, options: [.caseInsensitive]) != nil {
        return locale
      }
    }
    return "zh"
  }

  func optionSwitcherForSchema() -> SquirrelOptionSwitcher {
    if schemaId == nil || schemaId!.isEmpty || schemaId == "." {
      return SquirrelOptionSwitcher()
    }
    var switchIter = RimeConfigIterator()
    if !RimeApi.config_begin_list(&switchIter, &config, "switches") {
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
        if defaultScriptVariant == nil && (name.caseInsensitiveCompare("simplification") == .orderedSame ||
          name.caseInsensitiveCompare("simplified") == .orderedSame ||
          name.caseInsensitiveCompare("traditional") == .orderedSame) {
          defaultScriptVariant = reset != 0 ? name : "!" + name
          scriptVariantOptions[name] = Self.code(scriptVariant: name)
          scriptVariantOptions["!" + name] = Self.code(scriptVariant: "!" + name)
        }
      } else {
        var optionIter = RimeConfigIterator()
        if !RimeApi.config_begin_list(&optionIter, &config, String(cString: switchIter.path!) + "/options") {
          continue
        }
        var optGroup: [String] = []
        var hasStyleSection: Bool = false
        var hasScriptVariant = defaultScriptVariant != nil
        while RimeApi.config_next(&optionIter) {
          let option: String = string(forOption: String(cString: optionIter.path!))!
          optGroup.append(option)
          hasStyleSection = hasStyleSection || hasSection("style/" + option)
          hasScriptVariant = hasScriptVariant || option.caseInsensitiveCompare("simplification") == .orderedSame ||
            option.caseInsensitiveCompare("simplified") == .orderedSame ||
            option.caseInsensitiveCompare("traditional") == .orderedSame
        }
        RimeApi.config_end(&optionIter)
        if hasStyleSection {
          for i in 0 ..< optGroup.count {
            switcher[optGroup[i]] = optGroup[reset]
            optionGroups[optGroup[i]] = Set(optGroup)
          }
        }
        if defaultScriptVariant == nil && hasScriptVariant {
          for opt in optGroup {
            scriptVariantOptions[opt] = Self.code(scriptVariant: opt)
          }
          defaultScriptVariant = scriptVariantOptions[optGroup[reset]]
        }
      }
    }
    RimeApi.config_end(&switchIter)
    return SquirrelOptionSwitcher(schemaId: schemaId, switcher: switcher, optionGroups: optionGroups, defaultScriptVariant: defaultScriptVariant, scriptVariantOptions: scriptVariantOptions)
  }

  func appOptions(forApp bundleId: String) -> SquirrelAppOptions {
    if let cachedValue = cachedValue(ofType: SquirrelAppOptions.self, forKey: bundleId) {
      return cachedValue
    }
    let rootKey = "app_options/" + bundleId
    var appOptions = SquirrelAppOptions()
    var iterator = RimeConfigIterator()
    if !RimeApi.config_begin_map(&iterator, &config, rootKey) {
      cache[bundleId] = appOptions
      return appOptions
    }
    while RimeApi.config_next(&iterator) {
      // print("DEBUG option[\(iterator.index)]: \(iterator.key) (\(iterator.path))")
      if let value: Any = nullableBool(forOption: String(cString: iterator.path!)) ??
        nullableInt(forOption: String(cString: iterator.path!)) ??
        nullableDouble(forOption: String(cString: iterator.path!)) {
        appOptions[String(cString: iterator.key!)] = value
      }
    }
    RimeApi.config_end(&iterator)
    cache[bundleId] = appOptions
    return appOptions
  }

  // MARK: Private functions

  private func cachedValue<T>(ofType: T.Type, forKey key: String) -> T? {
    if let value = cache[key], value is T.Type {
      return value as? T
    }
    return nil
  }

  private func color(hexCode: String?) -> NSColor? {
    if hexCode == nil || (hexCode!.count != 8 && hexCode!.count != 10) || (!hexCode!.hasPrefix("0x") && !hexCode!.hasPrefix("0X")) {
      return nil
    }
    let hexScanner = Scanner(string: hexCode!)
    var hex: UInt32 = 0x0
    if hexScanner.scanHexInt32(&hex) && hexScanner.isAtEnd {
      let r = hex % 0x100
      let g = hex / 0x100 % 0x100
      let b = hex / 0x10000 % 0x100
      // 0xaaBBGGRR or 0xBBGGRR
      let a = hexCode!.count == 10 ? hex / 0x1000000 : 0xFF
      let components: [CGFloat] = [CGFloat(r) / 255.0, CGFloat(g) / 255.0, CGFloat(b) / 255.0, CGFloat(a) / 255.0]
      return NSColor(colorSpace: colorSpaceObject, components: components, count: 4)
    }
    return nil
  }

  private func image(filePath: String?) -> NSImage? {
    if filePath == nil {
      return nil
    }
    let imageFile = URL(fileURLWithPath: filePath!, isDirectory: false, relativeTo: SquirrelApplicationDelegate.userDataDir).standardizedFileURL
    if FileManager.default.fileExists(atPath: imageFile.path) {
      return NSImage(byReferencing: imageFile)
    }
    return nil
  }
} // SquirrelConfig

extension String {
  func unicharIndex(charIndex offset: CInt) -> Int {
    return utf8.index(utf8.startIndex, offsetBy: Int(offset)).utf16Offset(in: self)
  }

  func replaceLastPathComponent(with replacement: String?) -> String? {
    if let replacement = replacement, let sep = range(of: "/", options: .backwards) {
      return String(self[..<sep.upperBound]) + replacement
    }
    return replacement
  }
}
