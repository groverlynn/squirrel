import AppKit
import Cocoa

struct SquirrelOptionSwitcher: Sendable {
  static private let Scripts: [String] = ["zh-Hans", "zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh-SG", "zh-CN", "zh"]

  private(set) var schemaId: String
  private(set) var currentScriptVariant: String
  private var optionNames: Set<String>
  private(set) var optionStates: Set<String>
  private var scriptVariantOptions: [String : String]
  private var switcher: [String : String]
  private var optionGroups: [String : Set<String>]
  private(set) var optionAliases: [String : (String, Bool)]

  init(schemaId: String = "", switcher: [String : String] = [:], optionGroups: [String : Set<String>] = [:], defaultScriptVariant: String? = nil, scriptVariantOptions: [String : String] = [:], optionAliases: [String : (String, Bool)] = [:]) {
    self.schemaId = schemaId
    self.switcher = switcher
    self.optionGroups = optionGroups
    self.optionNames = Set(switcher.keys)
    self.optionStates = Set(switcher.values)
    self.currentScriptVariant = defaultScriptVariant ?? Bundle.preferredLocalizations(from: Self.Scripts)[0]
    self.scriptVariantOptions = scriptVariantOptions
    self.optionAliases = optionAliases
  }

  // return whether switcher options has been successfully updated
  mutating func updateSwitcher(_ switcher: [String : String]) -> Bool {
    guard !self.switcher.isEmpty, switcher.count == self.switcher.count else { return false }
    let optionNames: Set<String> = Set(switcher.keys)
    guard optionNames == self.optionNames else { return false }
    self.switcher = switcher
    optionStates = Set(switcher.values)
    return true
  }

  mutating func updateGroupState(_ optionState: String, ofOption optionName: String) -> Bool {
    guard let optionGroup: Set<String> = optionGroups[optionName] else { return false }
    if optionGroup.count == 1 {
      if optionName != (optionState.hasPrefix("!") ? String(optionState.dropFirst()) : optionState) {
        return false
      }
      switcher[optionName] = optionState
    } else if optionGroup.contains(optionState) {
      optionGroup.forEach { switcher[$0] = optionState }
    }
    optionStates = Set(switcher.values)
    return true
  }

  mutating func updateCurrentScriptVariant(_ scriptVariant: String?) -> Bool {
    guard let scriptVariant = scriptVariant, !scriptVariantOptions.isEmpty, let scriptVariantCode: String = scriptVariantOptions[scriptVariant] else { return false }
    currentScriptVariant = scriptVariantCode
    return true
  }

  mutating func update() {
    guard !switcher.isEmpty, let session = SquirrelInputController.current?.session, session != 0 else { return }
    for state in optionStates {
      var updatedState: String?
      let optionGroup: [String] = switcher.filter({ $0.value == state }).map(\.key)
      updatedState = optionGroup.first { RimeApi.get_option(session, $0) }
      updatedState ?= "!" + optionGroup[0]
      if updatedState != state {
        _ = updateGroupState(updatedState!, ofOption: state)
      }
    }
    // update script variant
    _ = updateCurrentScriptVariant(scriptVariantOptions.keys.first { $0.hasPrefix("!") ? !RimeApi.get_option(session, String($0.dropFirst())) : RimeApi.get_option(session, $0) })
  }
}  // SquirrelOptionSwitcher

protocol DefaultValueDefined: Sendable { static var `default`: Self { get } }
extension Bool: DefaultValueDefined { static var `default`: Bool { false } }
extension Int: DefaultValueDefined { static var `default`: Int { 0 } }
extension Double: DefaultValueDefined { static var `default`: Double { .zero } }

struct SquirrelAppOptions: Sendable {
  private var appOptions: [String : DefaultValueDefined] = [:]

  subscript<T: DefaultValueDefined>(option: String) -> T? {
    get { appOptions[option] as? T }
    set { appOptions[option] = newValue }
  }

  subscript<T: DefaultValueDefined>(option: String, as type: T.Type = T.self) -> T {
    get { appOptions[option] as? T ?? T.default }
  }
}  // SquirrelAppOptions

final class SquirrelConfig: NSObject {
  static private let colorSpaceMap: [String : NSColorSpace] = ["deviceRGB" : .deviceRGB, "genericRGB" : .genericRGB, "sRGB" : .sRGB, "displayP3" : .displayP3, "adobeRGB" : .adobeRGB1998, "extendedSRGB" : .extendedSRGB]

  private var cache: [String : Any] = [:]
  private var config: RimeConfig = .init()
  private var baseConfig: SquirrelConfig?
  private var isOpen: Bool = false
  private var schemaId: String?
  private var colorSpaceObject: NSColorSpace = .sRGB
  private var colorSpaceName: String = "sRGB"
  var colorSpace: String {
    get { colorSpaceName }
    set { let name: String = newValue.replacingOccurrences(of: "_", with: "")
          guard name != colorSpaceName, let (key, value) = Self.colorSpaceMap.first(where: { $0.key ~= name }) else { return }
          (colorSpaceName, colorSpaceObject) = (key, value) }
  }

  enum RimeConfigType: RawRepresentable, Sendable {
    case base, `default`, user, installation, schema(String)

    init?(rawValue: String) {
      self = switch rawValue {
      case "squirrel": .base
      case "default": .default
      case "user": .user
      case "installation": .installation
      default: .schema(rawValue)
      }
    }

    var rawValue: String {
      return switch self {
      case .base: "squirrel"
      case .default: "default"
      case .user: "user"
      case .installation: "installation"
      case .schema(let id): id
      }
    }
  }

  convenience init(_ type: RimeConfigType) {
    self.init()
    _ = switch type {
    case .base: openBaseConfig()
    case .default: open(configId: "default")
    case .user, .installation: open(userConfig: type.rawValue)
    case .schema(let id): open(schemaId: id, baseConfig: SquirrelConfig(.base))
    }
  }

  func openBaseConfig() -> Bool {
    close()
    isOpen = RimeApi.config_open("squirrel", &config)
    return isOpen
  }

  func open(schemaId: String, baseConfig: SquirrelConfig?) -> Bool {
    close()
    isOpen = RimeApi.schema_open(schemaId, &config)
    if isOpen {
      self.schemaId = schemaId
      self.baseConfig = baseConfig
    }
    return isOpen
  }

  func open(userConfig: String) -> Bool {
    close()
    isOpen = RimeApi.user_config_open(userConfig, &config)
    return isOpen
  }

  func open(configId: String) -> Bool {
    close()
    isOpen = RimeApi.config_open(configId, &config)
    return isOpen
  }

  func close() {
    if isOpen, RimeApi.config_close(&config) {
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
    guard isOpen else { return false }
    var iterator: RimeConfigIterator = .init()
    guard RimeApi.config_begin_map(&iterator, &config, section) else { return false }
    RimeApi.config_end(&iterator)
    return true
  }

  func setOption(_ option: String, with value: Bool) -> Bool {  RimeApi.config_set_bool(&config, option, value) }
  func setOption(_ option: String, with value: Int) -> Bool { RimeApi.config_set_int(&config, option, CInt(value)) }
  func setOption(_ option: String, with value: Double) -> Bool { RimeApi.config_set_double(&config, option, value) }
  func setOption(_ option: String, with value: String) -> Bool { RimeApi.config_set_string(&config, option, value) }

  func boolValue(for option: String, alias: String? = nil) -> Bool? {
    if let cachedValue: Bool = cachedValue(for: option) {
      return cachedValue
    }
    var value: Bool = false
    if isOpen, RimeApi.config_get_bool(&config, option, &value) {
      cache[option] = value
      return value
    }
    if isOpen, let alias = alias, RimeApi.config_get_bool(&config, option.replacingLastPathComponent(with: alias), &value) {
      cache[option] = value
      return value
    }
    return baseConfig?.boolValue(for: option, alias: alias)
  }

  func intValue(for option: String, alias: String? = nil) -> Int? {
    if let cachedValue: Int = cachedValue(for: option) {
      return cachedValue
    }
    var value: CInt = 0
    if isOpen, RimeApi.config_get_int(&config, option, &value) {
      cache[option] = Int(value)
      return Int(value)
    }
    if isOpen, let alias = alias, RimeApi.config_get_int(&config, option.replacingLastPathComponent(with: alias), &value) {
      cache[option] = Int(value)
      return Int(value)
    }
    return baseConfig?.intValue(for: option, alias: alias)
  }

  func doubleValue(for option: String, alias: String? = nil) -> Double? {
    if let cachedValue: Double = cachedValue(for: option) {
      return cachedValue
    }
    var value: Double = 0
    if isOpen, RimeApi.config_get_double(&config, option, &value) {
      cache[option] = value
      return value
    }
    if isOpen, let alias = alias, RimeApi.config_get_double(&config, option.replacingLastPathComponent(with: alias), &value) {
      cache[option] = value
      return value
    }
    return baseConfig?.doubleValue(for: option, alias: alias)
  }

  func doubleValue(for option: String, alias: String? = nil, constraint function: (Double) -> Double) -> Double? {
    guard let value: Double = doubleValue(for: option, alias: alias) else { return nil }
    return function(value)
  }

  func stringValue(for option: String, alias: String? = nil) -> String? {
    if let cachedValue: String = cachedValue(for: option) {
      return cachedValue
    }
    if isOpen, let value: UnsafePointer<CChar> = RimeApi.config_get_cstring(&config, option) {
      let string: String = .init(cString: value).trimmingCharacters(in: .whitespaces)
      cache[option] = string
      return string
    }
    if isOpen, let alias = alias, let value: UnsafePointer<CChar> = RimeApi.config_get_cstring(&config, option.replacingLastPathComponent(with: alias)) {
      let string: String = .init(cString: value).trimmingCharacters(in: .whitespaces)
      cache[option] = string
      return string
    }
    return baseConfig?.stringValue(for: option, alias: alias)
  }

  func colorValue(for option: String, alias: String? = nil) -> NSColor? {
    if let cachedValue: NSColor = cachedValue(for: option) {
      return cachedValue
    }
    if let hexCode: String = stringValue(for: option, alias: alias), let color: NSColor = color(hexCode: hexCode) {
      cache[option] = color
      return color
    }
    return baseConfig?.colorValue(for: option, alias: alias)
  }

  func imageValue(for option: String, alias: String? = nil) -> NSImage? {
    if let cachedValue: NSImage = cachedValue(for: option) {
      return cachedValue
    }
    if let file: String = stringValue(for: option, alias: alias), let image: NSImage = image(filePath: file) {
      cache[option] = image
      return image
    }
    return baseConfig?.imageValue(for: option, alias: alias)
  }

  func listSize(for option: String) -> Int { RimeApi.config_list_size(&config, option) }

  func listValue(for option: String) -> [String]? {
    var iterator: RimeConfigIterator = .init()
    guard RimeApi.config_begin_list(&iterator, &config, option) else { return nil }
    var strList: [String] = []
    while RimeApi.config_next(&iterator) {
      strList.append(stringValue(for: String(cString: iterator.path))!)
    }
    RimeApi.config_end(&iterator)
    return strList.isEmpty ? nil : strList
  }

  static private let localeScript: [String : String] = ["simplification" : "zh-Hans", "simplified" : "zh-Hans", "!traditional" : "zh-Hans", "traditional" : "zh-Hant", "!simplification" : "zh-Hant", "!simplified" : "zh-Hant"]
  static private let localeRegion: [String : String] = ["tw" : "zh-TW", "taiwan" : "zh-TW", "hk" : "zh-HK", "hongkong" : "zh-HK", "hong_kong" : "zh-HK", "mo" : "zh-MO", "macau" : "zh-MO", "macao" : "zh-MO", "sg" : "zh-SG", "singapore" : "zh-SG", "cn" : "zh-CN", "china" : "zh-CN"]
  static private func code(scriptVariant: String) -> String {
    localeScript.first(where: { $0.key ~= scriptVariant })?.value ?? localeRegion.first(where: { scriptVariant.range(of: $0.key, options: [.caseInsensitive, .diacriticInsensitive]) != nil })?.value ?? "zh"
  }

  func optionSwitcher() -> SquirrelOptionSwitcher {
    guard let schemaId = schemaId, !schemaId.isEmpty, schemaId != "." else { return .init() }
    var switchIter: RimeConfigIterator = .init()
    guard RimeApi.config_begin_list(&switchIter, &config, "switches") else { return .init(schemaId: schemaId) }
    var switcher: [String : String] = [:]
    var optionGroups: [String : Set<String>] = [:]
    var defaultScriptVariant: String?
    var scriptVariantOptions: [String : String] = [:]
    var optionAliases: [String : (String, Bool)] = [:]
    while RimeApi.config_next(&switchIter) {
      var reset: Int = intValue(for: String(cString: switchIter.path) + "/reset") ?? 0
      if let name: String = stringValue(for: String(cString: switchIter.path) + "/name") {
        if hasSection("style/!" + name) || hasSection("style/" + name) {
          switcher[name] = reset != 0 ? name : "!" + name
          optionGroups[name] = [name]
        }
        if defaultScriptVariant == nil, Set(["simplification", "simplified", "traditional"]).contains(where: { name ~= $0 }) {
          defaultScriptVariant = reset != 0 ? name : "!" + name
          scriptVariantOptions[name] = Self.code(scriptVariant: name)
          scriptVariantOptions["!" + name] = Self.code(scriptVariant: "!" + name)
        }
        optionAliases[name] = (name, true)
        optionAliases["!" + name] = (name, false)
      } else {
        var optionIter: RimeConfigIterator = .init()
        guard RimeApi.config_begin_list(&optionIter, &config, String(cString: switchIter.path) + "/options") else { continue }
        var optGroup: [String] = []
        var hasStyleSection: Bool = false
        var hasScriptVariant: Bool = defaultScriptVariant != nil
        while RimeApi.config_next(&optionIter) {
          let option: String = stringValue(for: String(cString: optionIter.path))!
          optGroup.append(option)
          hasStyleSection |= hasSection("style/" + option)
          hasScriptVariant |= Set(["simplification", "simplified", "traditional"]).contains(where: { option ~= $0 })
        }
        RimeApi.config_end(&optionIter)
        optGroup.forEach { optionAliases[$0] = ($0, true) }
        optionAliases["!" + optGroup.last!] = (optGroup.first!, true)
        reset = reset.clamp(min: 0, max: optGroup.count - 1)
        if hasStyleSection {
          optGroup.forEach { switcher[$0] = optGroup[reset]; optionGroups[$0] = Set(optGroup) }
        }
        if defaultScriptVariant == nil, hasScriptVariant {
          optGroup.forEach { scriptVariantOptions[$0] = Self.code(scriptVariant: $0) }
          defaultScriptVariant = scriptVariantOptions[optGroup[reset]]
        }
      }
    }
    RimeApi.config_end(&switchIter)
    return .init(schemaId: schemaId, switcher: switcher, optionGroups: optionGroups, defaultScriptVariant: defaultScriptVariant, scriptVariantOptions: scriptVariantOptions, optionAliases: optionAliases)
  }

  func appOptions(for bundleId: String) -> SquirrelAppOptions {
    let rootKey: String = "app_options/" + bundleId
    if let cachedValue: SquirrelAppOptions = cachedValue(for: rootKey) {
      return cachedValue
    }
    var appOptions: SquirrelAppOptions = .init()
    var iterator: RimeConfigIterator = .init()
    if !RimeApi.config_begin_map(&iterator, &config, rootKey) {
      cache[rootKey] = appOptions
      return appOptions
    }
    while RimeApi.config_next(&iterator) {
      // print("DEBUG option[\(iterator.index)]: \(iterator.key) (\(iterator.path))")
      let path: String = .init(cString: iterator.path), key: String = .init(cString: iterator.key)
      if let boolValue: Bool = boolValue(for: path) {
        appOptions[key] = boolValue
      } else if let intValue: Int = intValue(for: path) {
        appOptions[key] = intValue
      } else if let doubleValue: Double = doubleValue(for: path) {
        appOptions[key] = doubleValue
      }
    }
    RimeApi.config_end(&iterator)
    cache[rootKey] = appOptions
    return appOptions
  }

  // MARK: Private functions

  private func cachedValue<T>(ofType: T.Type = T.self, for key: String) -> T? { cache[key] as? T }

  private func color(hexCode: String?) -> NSColor? {
    guard let hexCode = hexCode, [8, 10].contains(hexCode.count), ["0x", "0X"].contains(where: { hexCode.hasPrefix($0) }) else { return nil }
    let hexScanner: Scanner = .init(string: hexCode)
    var hex: CUnsignedLongLong = 0x0
    guard hexScanner.scanHexInt64(&hex), hexScanner.isAtEnd else { return nil }
    let r: CGFloat = .init(hex % 0x100)
    let g: CGFloat = .init(hex / 0x100 % 0x100)
    let b: CGFloat = .init(hex / 0x10000 % 0x100)
    // 0xaaBBGGRR or 0xBBGGRR
    let a: CGFloat = hexCode.count == 10 ? .init(hex / 0x1000000) : 255.0
    let components: [CGFloat] = [r / 255.0, g / 255.0, b / 255.0, a / 255.0]
    return NSColor(colorSpace: colorSpaceObject, components: components, count: 4)
  }

  private func image(filePath: String?) -> NSImage? {
    guard let filePath = filePath else { return nil }
    let imageFile: URL = .init(fileURLWithPath: filePath, isDirectory: false, relativeTo: SquirrelApplicationDelegate.userDataDir).standardizedFileURL
    guard FileManager.default.fileExists(atPath: imageFile.path) else { return nil }
    return NSImage(byReferencing: imageFile)
  }
}  // SquirrelConfig

extension String {
  static let fullWidthSpace: Self = "　"

  // UTF16/UniChar length and index
  var length: Int { utf16.count }
  subscript(index: Int) -> unichar {
    utf16[utf16.index(utf8.startIndex, offsetBy: index.clamp(min: 0, max: utf16.count))]
  }
  subscript(range: Range<Int>) -> String {
    String(self[String.Index(utf16Offset: range.lowerBound.clamp(min: 0, max: utf16.count), in: self) ..< String.Index(utf16Offset: range.upperBound.clamp(min: 0, max: utf16.count), in: self)])
  }
  subscript(range: ClosedRange<Int>) -> String {
    String(self[String.Index(utf16Offset: range.lowerBound.clamp(min: 0, max: utf16.count), in: self) ... String.Index(utf16Offset: range.upperBound.clamp(min: 0, max: utf16.count - 1), in: self)])
  }
  subscript(range: PartialRangeFrom<Int>) -> String {
    String(self[String.Index(utf16Offset: range.lowerBound.clamp(min: 0, max: utf16.count), in: self)...])
  }
  subscript(range: PartialRangeUpTo<Int>) -> String {
    String(self[..<String.Index(utf16Offset: range.upperBound.clamp(min: 0, max: utf16.count), in: self)])
  }
  subscript(range: PartialRangeThrough<Int>) -> String {
    String(self[...String.Index(utf16Offset: range.upperBound.clamp(min: 0, max: utf16.count - 1), in: self)])
  }

  // UTF8/CChar length and index
  subscript(index: CInt) -> CChar {
    utf8CString[Int(index).clamp(min: 0, max: utf8.count)]
  }
  subscript(range: Range<CInt>) -> String {
    String(utf8[utf8.index(utf8.startIndex, offsetBy: Int(range.lowerBound).clamp(min: 0, max: utf8.count)) ..< utf8.index(utf8.startIndex, offsetBy: Int(range.upperBound).clamp(min: 0, max: utf8.count))])!
  }
  subscript(range: ClosedRange<CInt>) -> String {
    String(utf8[utf8.index(utf8.startIndex, offsetBy: Int(range.lowerBound).clamp(min: 0, max: utf8.count)) ... utf8.index(utf8.startIndex, offsetBy: Int(range.upperBound).clamp(min: 0, max: utf8.count - 1))])!
  }
  subscript(range: PartialRangeFrom<CInt>) -> String {
    String(utf8[utf8.index(utf8.startIndex, offsetBy: Int(range.lowerBound).clamp(min: 0, max: utf8.count))...])!
  }
  subscript(range: PartialRangeUpTo<CInt>) -> String {
    String(utf8[..<utf8.index(utf8.startIndex, offsetBy: Int(range.upperBound).clamp(min: 0, max: utf8.count))])!
  }
  subscript(range: PartialRangeThrough<CInt>) -> String {
    String(utf8[...utf8.index(utf8.startIndex, offsetBy: Int(range.upperBound).clamp(min: 0, max: utf8.count - 1))])!
  }

  func UniCharIndex(CCharIndex: CInt) -> Int {
    utf8.index(utf8.startIndex, offsetBy: Int(CCharIndex).clamp(min: 0, max: utf8.count)).utf16Offset(in: self)
  }

  func replacingLastPathComponent(with replacement: String) -> String {
    guard let sep: Range<String.Index> = range(of: "/", options: [.backwards]) else { return replacement }
    return replacingCharacters(in: sep.upperBound..., with: replacement)
  }
}

extension StringProtocol {
  static func ~= (lhs: Self, rhs: Self) -> Bool { lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
}
