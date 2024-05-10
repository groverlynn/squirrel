import Cocoa


class SquirrelOptionSwitcher: NSObject {

  private var _schemaId: String
  var schemaId: String {
    get { return _schemaId }
  }
  private var _currentScriptVariant: String
  var currentScriptVariant: String {
    get { return _currentScriptVariant }
  }
  private var _optionNames: Set<String>
  var optionNames: Set<String> {
    get { return _optionNames }
  }
  private var _optionStates: Set<String>
  var optionStates: Set<String> {
    get { return _optionStates }
  }
  private var _scriptVariantOptions: [String: String]
  var scriptVariantOptions: [String: String] {
    get { return _scriptVariantOptions }
  }
  private var _switcher: [String: String]
  var switcher: [String: String] {
    get { return _switcher }
  }
  private var _optionGroups: [String: [String]]
  var optionGroups: [String: [String]] {
    get { return _optionGroups }
  }

  let kScripts: [String] = ["zh-Hans", "zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh-SG", "zh-CN", "zh"]

  init(schemaId: String?,
       switcher: [String: String]?,
       optionGroups: [String: [String]]?,
       defaultScriptVariant: String?,
       scriptVariantOptions: [String: String]?) {
    _schemaId = schemaId ?? ""
    _switcher = switcher ?? [:]
    _optionGroups = optionGroups ?? [:]
    _optionNames = switcher == nil ? [] : Set(switcher!.keys)
    _optionStates = switcher == nil ? [] : Set(switcher!.values)
    _currentScriptVariant = defaultScriptVariant ?? Bundle.preferredLocalizations(from: kScripts)[0]
    _scriptVariantOptions = scriptVariantOptions ?? [:]
  }

  init(schemaId: String?) {
    _schemaId = schemaId ?? ""
    _switcher = [:]
    _optionGroups = [:]
    _optionNames = []
    _optionStates = []
    _currentScriptVariant = "zh"
    _scriptVariantOptions = [:]
  }

  override init() {
    _schemaId = ""
    _switcher = [:]
    _optionGroups = [:]
    _optionNames = []
    _optionStates = []
    _currentScriptVariant = "zh"
    _scriptVariantOptions = [:]
  }

  // return whether switcher options has been successfully updated
  func updateSwitcher(_ switcher: [String: String]!) -> Boolean {
    if (_switcher.isEmpty || switcher?.count != _switcher.count) {
      return false
    }
    let optNames: Set<String> = Set(switcher.keys)
    if (optNames == _optionNames) {
      _switcher = switcher
      _optionStates = Set(switcher.values)
      return true
    }
   return false
  }

  func updateGroupState(_ optionState: String,
                        ofOption optionName: String) -> Boolean {
    if let optionGroup = _optionGroups[optionName] {
      if (optionGroup.count == 1) {
        if (optionState == (optionState.hasPrefix("!") ? "!" + optionName : optionName)) {
          return false
        }
        _switcher[optionName] = optionState
      } else if !(optionGroup.contains(optionState)) {
        for option in optionGroup {
          _switcher[option] = optionState
        }
      }
      _optionStates = Set(_switcher.values)
      return true
    } else {
      return false
    }
  }

  func updateCurrentScriptVariant(_ scriptVariant: String) -> Boolean {
    if (_scriptVariantOptions.isEmpty) {
      return false
    }
    if let scriptVariantCode = _scriptVariantOptions[scriptVariant] {
      _currentScriptVariant = scriptVariantCode
      return true
    } else {
      return false
    }
  }

  func update(withRimeSession session: RimeSessionId) {
    if (_switcher.count == 0 || session == 0) {
      return
    }
    for state in _optionStates {
      var updatedState: String?
      let optionGroup: [String] = _switcher.compactMap({ (key: String, value: String) -> String? in
        value == state ? key : nil
      })
      for option in optionGroup {
        if (rime_get_api().pointee.get_option(session, option).Bool) {
          updatedState = option
          break
        }
      }
      updatedState = updatedState ?? "!" + optionGroup[0]
      if (updatedState != state) {
        _ = updateGroupState(updatedState!, ofOption: state)
      }
    }
    // update script variant
    if (_scriptVariantOptions.count > 0) {
      for (option, _) in _scriptVariantOptions {
        if (option.hasPrefix("!")
            ? !rime_get_api().pointee.get_option(session, option.suffix(option.count - 1).withCString{ $0 }).Bool
            : rime_get_api().pointee.get_option(session, option.withCString{ $0 }).Bool) {
          _ = updateCurrentScriptVariant(option)
          break
        }
      }
    }
  }

}  // SquirrelOptionSwitcher


struct SquirrelAppOptions {
  private var appOptions: [String: Any]
  init() { appOptions = [:] }
  subscript(key: String) -> Any? {
    get { if let value = appOptions[key] {
            if value is Boolean.Type {
              return value as! Boolean
            } else if value is Int.Type {
              return value as! Int
            } else if value is Double.Type {
              return value as! Double
            }
          }
          return nil
        }
    set (newValue) {
      if newValue is Boolean.Type || newValue is Int.Type ||
          newValue is Double.Type {
        appOptions[key] = newValue }
    }
  }
  mutating func setValue(_ value: Boolean, forKey key: String) {
    appOptions[key] = value
  }
  mutating func setValue(_ value: Int, forKey key: String) {
    appOptions[key] = value
  }
  mutating func setValue(_ value: Double, forKey key: String) {
    appOptions[key] = value
  }
  func boolValue(forKey key: String) -> Boolean! {
    if let value = appOptions[key], value is Boolean.Type {
      return value as? Boolean
    } else {
      return false
    }
  }
  func intValue(forKey key: String) -> Int! {
    if let value = appOptions[key], value is Int.Type {
      return value as? Int
    } else {
      return 0
    }
  }
  func doubleValue(forKey key: String) -> Double! {
    if let value = appOptions[key], value is Double.Type {
      return value as? Double
    } else {
      return 0.0
    }
  }
}

let colorSpaceMap: [String: NSColorSpace] =
  ["deviceRGB"    : NSColorSpace.deviceRGB,
   "genericRGB"   : NSColorSpace.genericRGB,
   "sRGB"         : NSColorSpace.sRGB,
   "displayP3"    : NSColorSpace.displayP3,
   "adobeRGB"     : NSColorSpace.adobeRGB1998,
   "extendedSRGB" : NSColorSpace.extendedSRGB]

class SquirrelConfig : NSObject {

  private var _cache: [String: Any]
  private var _config: RimeConfig
  private var _baseConfig: SquirrelConfig?
  private var _isOpen: Boolean
  var isOpen: Boolean {
    get { return _isOpen }
  }
  private var _schemaId: String?
  private var _colorSpace: NSColorSpace
  private var _colorSpaceName: String
  var colorSpace: String {
    get { return _colorSpaceName }
    set (newValue) {
      let name: String = newValue.replacingOccurrences(of: "_", with: "")
      if (name == _colorSpaceName) {
        return
      }
      for (CSName, CSObj) in colorSpaceMap {
        if (CSName.caseInsensitiveCompare(name) == .orderedSame) {
          _colorSpaceName = CSName
          _colorSpace = CSObj
          return
        }
      }
    }
  }

  override init() {
    _cache = [:]
    _config = RimeConfig()
    _isOpen = false
    _colorSpace = NSColorSpace.sRGB
    _colorSpaceName = "sRGB"
  }

  func openBaseConfig() -> Boolean {
    close()
    _isOpen = rime_get_api().pointee.config_open("squirrel", &_config).Bool
    return _isOpen
  }

  func open(withSchemaId schemaId: String, baseConfig: SquirrelConfig) -> Boolean {
    close()
    _isOpen = rime_get_api().pointee.schema_open(schemaId, &_config).Bool
    if (_isOpen) {
      _schemaId = schemaId
      _baseConfig = baseConfig
    }
    return _isOpen
  }

  func open(userConfig configId: String) -> Boolean {
    close()
    _isOpen = rime_get_api().pointee.user_config_open(configId, &_config).Bool
    return _isOpen
  }

  func open(withConfigId configId: String) -> Boolean {
    close()
    _isOpen = rime_get_api().pointee.config_open(configId, &_config).Bool
    return _isOpen
  }

  func close() {
    if (_isOpen && rime_get_api().pointee.config_close(&_config).Bool) {
      _baseConfig = nil
      _schemaId = nil
      _isOpen = false
    }
  }

  deinit {
    close()
    _cache.removeAll()
  }

  func hasSection(_ section: String) -> Boolean {
    if (_isOpen) {
      var iterator = RimeConfigIterator()
      if (rime_get_api().pointee.config_begin_map(&iterator, &_config, section).Bool) {
        rime_get_api().pointee.config_end(&iterator);
        return true
      }
    }
    return false
  }

  func setOption(_ option: String, withBool value: Boolean) -> Boolean {
    return rime_get_api().pointee.config_set_bool(&_config, option, value.Bool).Bool
  }

  func setOption(_ option: String, withInt value: Int) -> Boolean {
    return rime_get_api().pointee.config_set_int(&_config, option, CInt(value)).Bool
  }

  func setOption(_ option: String, withDouble value: Double) -> Boolean {
    return rime_get_api().pointee.config_set_double(&_config, option, CDouble(value)).Bool
  }

  func setOption(_ option: String, withString value: String) -> Boolean {
    return rime_get_api().pointee.config_set_string(&_config, option, value).Bool
  }

  func getBoolForOption(_ option: String) -> Boolean! {
    return getOptionalBoolForOption(option, alias: nil) ?? false
  }

  func getIntForOption(_ option: String) -> Int! {
    return getOptionalIntForOption(option, alias: nil) ?? 0
  }

  func getDoubleForOption(_ option: String) -> Double! {
    return getOptionalDoubleForOption(option, alias: nil) ?? 0
  }

  func getDoubleForOption(_ option: String,
                          applyConstraint function: (Double) -> Double) -> Double! {
    return function(getOptionalDoubleForOption(option, alias: nil) ?? 0)
  }

  func getOptionalBoolForOption(_ option: String, alias: String?) -> Boolean? {
    if let cachedValue = cachedValueOfType(Boolean.self, forKey: option) as? Boolean {
      return cachedValue
    }
    var value: RimeBool = False
    if (_isOpen && rime_get_api().pointee.config_get_bool(&_config, option, &value).Bool) {
      _cache[option] = value.Bool
      return value.Bool
    }
    if (alias != nil) {
      let aliasOption: String = ((option as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent((alias! as NSString).lastPathComponent)
      if (_isOpen && rime_get_api().pointee.config_get_bool(&_config, aliasOption, &value).Bool) {
        _cache[option] = value.Bool
        return value.Bool
      }
    }
    return _baseConfig?.getOptionalBoolForOption(option, alias: alias)
  }

  func getOptionalIntForOption(_ option: String, alias: String?) -> Int? {
    if let cachedValue = cachedValueOfType(Int.self, forKey: option) as? Int {
      return cachedValue
    }
    var value: CInt = 0
    if (_isOpen && rime_get_api().pointee.config_get_int(&_config, option, &value).Bool) {
      _cache[option] = Int(value)
      return Int(value)
    }
    if (alias != nil) {
      let aliasOption: String = ((option as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent((alias! as NSString).lastPathComponent)
      if (_isOpen && rime_get_api().pointee.config_get_int(&_config, aliasOption, &value).Bool) {
        _cache[option] = Int(value)
        return Int(value)
      }
    }
    return _baseConfig?.getOptionalIntForOption(option, alias: alias)
  }

  func getOptionalDoubleForOption(_ option: String, alias: String?) -> Double? {
    if let cachedValue = cachedValueOfType(Double.self, forKey: option) as? Double {
      return cachedValue;
    }
    var value: CDouble = 0
    if (_isOpen && rime_get_api().pointee.config_get_double(&_config, option, &value).Bool) {
      _cache[option] = Double(value)
      return Double(value)
    }
    if (alias != nil) {
      let aliasOption: String = ((option as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent((alias! as NSString).lastPathComponent)
      if (_isOpen && rime_get_api().pointee.config_get_double(&_config, aliasOption, &value).Bool) {
        _cache[option] = Double(value)
        return Double(value)
      }
    }
    return _baseConfig?.getOptionalDoubleForOption(option, alias: alias)
  }

  func getOptionalDoubleForOption(_ option: String, alias: String?,
                                  applyConstraint function: (CDouble) -> CDouble) -> Double? {
    if let value = getOptionalDoubleForOption(option, alias: alias) {
      return function(value)
    } else {
      return nil
    }
  }

  func getOptionalBoolForOption(_ option: String) -> Boolean? {
    return getOptionalBoolForOption(option, alias: nil)
  }

  func getOptionalIntForOption(_ option: String) -> Int? {
    return getOptionalIntForOption(option, alias: nil)
  }

  func getOptionalDoubleForOption(_ option: String) -> Double? {
    return getOptionalDoubleForOption(option, alias: nil)
  }

  func getOptionalDoubleForOption(_ option: String,
                                  applyConstraint function: (CDouble) -> CDouble) -> Double? {
    if let value = getOptionalDoubleForOption(option, alias: nil) {
      return function(value)
    } else {
      return nil
    }
  }

  func getStringForOption(_ option: String, alias: String?) -> String? {
    if let cachedValue = cachedValueOfType(String.self, forKey: option) as? String {
      return cachedValue
    }
    var value: UnsafePointer<CChar>? = _isOpen ? rime_get_api().pointee.config_get_cstring(&_config, option) : nil
    if (value != nil) {
      let string: String = String(cString: value!).trimmingCharacters(in: CharacterSet.whitespaces)
      _cache[option] = string
      return string
    }
    if (alias != nil) {
      let aliasOption: String = ((option as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent((alias! as NSString).lastPathComponent)
      value = _isOpen ? rime_get_api().pointee.config_get_cstring(&_config, aliasOption) : nil
      if (value != nil) {
        let string: String = String(cString: value!).trimmingCharacters(in: CharacterSet.whitespaces)
        _cache[option] = string
        return string
      }
    }
    return _baseConfig?.getStringForOption(option, alias: alias) ?? nil
  }

  func getColorForOption(_ option: String, alias: String?) -> NSColor? {
    if let cachedValue = cachedValueOfClass(NSColor.self, forKey: option) as? NSColor {
      return cachedValue
    }
    if let color = colorFromString(getStringForOption(option, alias: alias)) {
      _cache[option] = color
      return color
    }
    return _baseConfig?.getColorForOption(option, alias:  alias) ?? nil
  }

  func getImageForOption(_ option: String, alias: String?) -> NSImage? {
    if let cachedValue = cachedValueOfClass(NSImage.self, forKey: option) as? NSImage {
      return cachedValue
    }
    if let image = imageFromFile(getStringForOption(option, alias: alias)) {
      _cache[option] = image
      return image
    }
    return _baseConfig?.getImageForOption(option, alias: alias) ?? nil
  }

  func getStringForOption(_ option: String) -> String? {
    return getStringForOption(option, alias: nil)
  }

  func getColorForOption(_ option: String) -> NSColor? {
    return getColorForOption(option, alias: nil)
  }

  func getImageForOption(_ option: String) -> NSImage? {
    return getImageForOption(option, alias: nil)
  }

  func getListSizeForOption(_ option: String) -> Int {
    return rime_get_api().pointee.config_list_size(&_config, option)
  }

  func getListForOption(_ option: String) -> [String]? {
    var iterator = RimeConfigIterator()
    if (!rime_get_api().pointee.config_begin_list(&iterator, &_config, option).Bool) {
      return nil;
    }
    var strList: [String] = []
    while (rime_get_api().pointee.config_next(&iterator).Bool) {
      strList.append(getStringForOption(String(cString: iterator.path))!)
    }
    rime_get_api().pointee.config_end(&iterator)
    return strList.count == 0 ? nil : strList
  }

  let localeScript: [String: String] =
    ["simplification" : "zh-Hans",
     "simplified"     : "zh-Hans",
     "!traditional"   : "zh-Hans",
     "traditional"    : "zh-Hant",
     "!simplification": "zh-Hant",
     "!simplified"    : "zh-Hant"]
  let localeRegion: [String: String] =
    ["tw"       : "zh-TW", "taiwan"   : "zh-TW",
     "hk"       : "zh-HK", "hongkong" : "zh-HK",
     "hong_kong": "zh-HK", "mo"       : "zh-MO",
     "macau"    : "zh-MO", "macao"    : "zh-MO",
     "sg"       : "zh-SG", "singapore": "zh-SG",
     "cn"       : "zh-CN", "china"    : "zh-CN"]

  func codeForScriptVariant(_ scriptVariant: String) -> String {
    for (script, locale) in localeScript {
      if (script.caseInsensitiveCompare(scriptVariant) == .orderedSame) {
        return locale;
      }
    }
    for (region, locale) in localeRegion {
      if (scriptVariant.range(of: region, options: .caseInsensitive) != nil) {
        return locale;
      }
    }
    return "zh";
  }

  func getOptionSwitcher() -> SquirrelOptionSwitcher {
    if (_schemaId == nil || _schemaId!.isEmpty || _schemaId == ".") {
      return SquirrelOptionSwitcher()
    }
    var switchIter: RimeConfigIterator = RimeConfigIterator()
    if (!rime_get_api().pointee.config_begin_list(&switchIter, &_config, "switches").Bool) {
      return SquirrelOptionSwitcher(schemaId: _schemaId)
    }
    var switcher: [String: String] = [:]
    var optionGroups: [String: [String]] = [:]
    var defaultScriptVariant: String?
    var scriptVariantOptions: [String: String] = [:]
    while (rime_get_api().pointee.config_next(&switchIter).Bool) {
      let reset: Int = getIntForOption(String(cString: switchIter.path) + "/reset")
      let name: String? = getStringForOption(String(cString: switchIter.path) + "/name")
      if (name != nil) {
        if (hasSection("style/!" + name!) || hasSection("style/" + name!)) {
          switcher[name!] = reset != 0 ? name! : "!" + name!
          optionGroups[name!] = [name!]
        }
        if (defaultScriptVariant == nil &&
            (name?.caseInsensitiveCompare("simplification") == .orderedSame ||
             name?.caseInsensitiveCompare("simplified") == .orderedSame ||
             name?.caseInsensitiveCompare("traditional") == .orderedSame)) {
          defaultScriptVariant = reset > 0 ? name : "!" + name!
          scriptVariantOptions[name!] = codeForScriptVariant(name!)
          scriptVariantOptions["!" + name!] = codeForScriptVariant("!" + name!)
        }
      } else {
        var optionIter: RimeConfigIterator = RimeConfigIterator()
        if (!rime_get_api().pointee.config_begin_list(
          &optionIter, &_config, String(cString: switchIter.path) + "/options").Bool) {
          continue;
        }
        var optGroup: [String] = []
        var hasStyleSection: Boolean = false
        let hasScriptVariant = defaultScriptVariant != nil
        while (rime_get_api().pointee.config_next(&optionIter).Bool) {
          let option: String = getStringForOption(String(cString: optionIter.path))!
          optGroup.append(option)
          hasStyleSection = hasStyleSection || hasSection("style/" + option)
        }
        rime_get_api().pointee.config_end(&optionIter);
        if (hasStyleSection) {
          for i in 0..<optGroup.count {
            switcher[optGroup[i]] = optGroup[size_t(reset)]
            optionGroups[optGroup[i]] = optGroup
          }
        }
        if (defaultScriptVariant == nil && hasScriptVariant) {
          for opt in optGroup {
            scriptVariantOptions[opt] = codeForScriptVariant(opt)
          }
          defaultScriptVariant = scriptVariantOptions[optGroup[reset]]
        }
      }
    }
    rime_get_api().pointee.config_end(&switchIter)
    return SquirrelOptionSwitcher(schemaId: _schemaId,
                                  switcher: switcher,
                                  optionGroups: optionGroups,
                                  defaultScriptVariant: defaultScriptVariant,
                                  scriptVariantOptions: scriptVariantOptions)
  }

  func getAppOptions(_ appName: String) -> SquirrelAppOptions {
    let rootKey = "app_options/" + appName
    var appOptions = SquirrelAppOptions()
    var iterator = RimeConfigIterator()
    if (!rime_get_api().pointee.config_begin_map(&iterator, &_config, rootKey).Bool) {
      return appOptions;
    }
    while (rime_get_api().pointee.config_next(&iterator).Bool) {
      // NSLog(@"DEBUG option[%d]: %s (%s)", iterator.index, iterator.key, iterator.path);
      if let value: Any = getOptionalBoolForOption(String(cString: iterator.path)) ??
                          getOptionalIntForOption(String(cString: iterator.path)) ??
                          getOptionalDoubleForOption(String(cString: iterator.path)),
         type(of: value) == Boolean.self || type(of: value) == Int.self {
        appOptions[String(cString: iterator.key)] = value
      }
    }
    rime_get_api().pointee.config_end(&iterator)
    return appOptions
  }

  // MARK: Private functions

  private func cachedValueOfClass(_ aClass: AnyClass, forKey key: String) -> AnyObject? {
    let value: AnyObject? = _cache[key] as? AnyObject
    return (value?.isMember(of: aClass) ?? false) ? value : nil
  }

  private func cachedValueOfType(_ metaType: Any.Type, forKey key: String) -> Any? {
    let value: Any? = _cache[key]
    return value != nil && type(of: value!) == metaType ? value : nil
  }

  private func colorFromString(_ string: String?) -> NSColor? {
    if (string == nil || (string!.count != 8 && string!.count != 10)) {
      return nil
    }
    var r: CInt = 0, g: CInt = 0, b: CInt = 0, a: CInt = 0xff
    if (string!.count == 10) {
      // 0xaaBBGGRR
      withUnsafePointer(to: &a) { ptr_a in
        withUnsafePointer(to: &b) { ptr_b in
          withUnsafePointer(to: &g) { ptr_g in
            withUnsafePointer(to: &r) { ptr_r in
              withVaList([ptr_a, ptr_b, ptr_g, ptr_r]) { va_list in
                string?.withCString { buffer in
                  _ = vsscanf(buffer, "0x%02x%02x%02x%02x", va_list)
                }
              }
            }
          }
        }
      }
    } else if (string!.count == 8) {
      // 0xBBGGRR
      withUnsafePointer(to: &b) { ptr_b in
        withUnsafePointer(to: &g) { ptr_g in
          withUnsafePointer(to: &r) { ptr_r in
            withVaList([ptr_b, ptr_g, ptr_r]) { va_list in
              string?.withCString { buffer in
                _ = vsscanf(buffer, "0x%02x%02x%02x", va_list)
              }
            }
          }
        }
      }
    }
    let components: [CGFloat] = [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, CGFloat(a) / 255]
    return NSColor(colorSpace: _colorSpace, components: components, count: 4)
  }

  private func imageFromFile(_ filePath: String?) -> NSImage? {
    if (filePath == nil) {
      return nil
    }
    let userDataDir = URL(fileURLWithPath:("~/Library/Rime" as NSString).expandingTildeInPath,
                          isDirectory: true)
    let imageFile = URL(fileURLWithPath: filePath!,
                        isDirectory: false, relativeTo: userDataDir)
    if ((try? imageFile.checkResourceIsReachable()) != nil) {
      let image = NSImage(byReferencing: imageFile)
      return image
    }
    return nil
  }

}  // SquirrelConfig
