import Cocoa


class SquirrelOptionSwitcher {

  private var _schemaId: String
  var schemaId: String {
    get { return _schemaId }
  }
  private var _optionNames: [String]
  var optionNames: [String] {
    get { return _optionNames }
  }
  private var _optionGroups: [String: [String]]
  var optionGroups: [String: [String]] {
    get { return _optionGroups }
  }
  private var _switcher: [String: String]
  var switcher: [String: String] {
    get { return _switcher }
  }

  init(schemaId: String,
       switcher: [String: String]?,
       optionGroups: [String: [String]]?) {
    _schemaId = schemaId
    _switcher = switcher ?? [:]
    _optionGroups = optionGroups ?? [:]
    _optionNames = switcher == nil ? [] : Array(switcher!.keys)
  }

  init(schemaId: String) {
    _schemaId = schemaId
    _switcher = [:]
    _optionGroups = [:]
    _optionNames = []
  }

  func optionStates() -> [String] {
    return Array(_switcher.values)
  }

  // return whether switcher options has been successfully updated
  func updateSwitcher(_ switcher: [String: String]?) -> Boolean {
    if (_switcher.isEmpty || switcher?.count != _switcher.count) {
      return false
    }
    var updatedSwitcher: [String: String]! = Dictionary(minimumCapacity: _switcher.count)
    for option: String in _optionNames {
      if switcher![option] == nil {
        return false
      }
      updatedSwitcher[option] = switcher![option]
    }
    _switcher = updatedSwitcher
    return true
  }

  func updateGroupState(_ optionState: String,
                        ofOption optionName: String) -> Boolean {
    let optionGroup: [String]? = _optionGroups[optionName]
    if !(optionGroup?.contains(optionState) ?? false) {
      return false
    }
    var updatedSwitcher: [String: String]! = _switcher
    for option: String in optionGroup! {
      updatedSwitcher.updateValue(optionState, forKey: option)
    }
    _switcher = updatedSwitcher
    return true
  }

  func containsOption(_ optionName: String) -> Boolean {
    return _optionNames.contains(optionName)
  }

}  // SquirrelOptionSwitcher

typealias SquirrelAppOptions = [String: Any]

class SquirrelConfig {
  private var _cache: [String: Any]
  private var _config: RimeConfig
  private var _baseConfig: SquirrelConfig?
  private var _isOpen: Boolean
  var isOpen: Boolean {
    get { return _isOpen }
  }
  private var _colorSpace: String
  var colorSpace: String {
    get { return _colorSpace }
    set (colorSpace) { _colorSpace = colorSpace }
  }
  private var _schemaId: String
  var schemaId: String {
    get { return _schemaId }
  }

  init() {
    _cache = [:]
    _config = RimeConfig()
    _isOpen = false
    _colorSpace = "srgb"
    _schemaId = ""
  }

  func openBaseConfig() -> Boolean {
    close()
    _isOpen = rime_get_api().pointee.config_open("squirrel", &_config).Bool
    return _isOpen
  }

  func open(withSchemaId schemaId: String, baseConfig: SquirrelConfig) -> Boolean {
    close()
    _isOpen = rime_get_api().pointee.schema_open(schemaId, &_config).Bool
    if _isOpen {
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
    if _isOpen && rime_get_api().pointee.config_close(&_config).Bool {
      _baseConfig = nil
      _isOpen = false
    }
  }

  deinit {
    close()
    _cache.removeAll()
  }

  func hasSection(_ section: String) -> Boolean {
    if _isOpen {
      var iterator: RimeConfigIterator = RimeConfigIterator()
      if rime_get_api().pointee.config_begin_map(&iterator, &_config, section).Bool {
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
    return getOptionalBoolForOption(option) ?? false
  }

  func getIntForOption(_ option: String) -> Int! {
    return getOptionalIntForOption(option) ?? 0
  }

  func getDoubleForOption(_ option: String) -> Double! {
    return getOptionalDoubleForOption(option) ?? 0
  }

  func getDoubleForOption(_ option: String, applyConstraint function: (Double) -> Double) -> Double! {
    let value: Double = getOptionalDoubleForOption(option) ?? 0
    return function(value)
  }

  func getOptionalBoolForOption(_ option: String) -> Boolean? {
    let cachedValue: Boolean? = cachedValueOfType(Boolean.self, forKey: option) as? Boolean
    if (cachedValue != nil) {
      return cachedValue
    }
    var value: Bool = False
    if (_isOpen && rime_get_api().pointee.config_get_bool(&_config, option, &value).Bool) {
      _cache[option] = value.Bool
      return value.Bool
    }
    return _baseConfig?.getOptionalBoolForOption(option) ?? nil
  }

  func getOptionalIntForOption(_ option: String) -> Int? {
    let cachedValue: Int? = cachedValueOfType(Int.self, forKey: option) as? Int
    if (cachedValue != nil) {
      return cachedValue
    }
    var value: CInt = 0
    if (_isOpen && rime_get_api().pointee.config_get_int(&_config, option, &value).Bool) {
      _cache[option] = Int(value)
      return Int(value)
    }
    return _baseConfig?.getOptionalIntForOption(option) ?? nil
  }

  func getOptionalDoubleForOption(_ option: String) -> Double? {
    let cachedValue: Double? = cachedValueOfType(Double.self, forKey: option) as? Double
    if (cachedValue != nil) {
      return cachedValue;
    }
    var value: CDouble = 0
    if (_isOpen && rime_get_api().pointee.config_get_double(&_config, option, &value).Bool) {
      _cache[option] = Double(value)
      return Double(value)
    }
    return _baseConfig?.getOptionalDoubleForOption(option) ?? nil
  }

  func getOptionalDoubleForOption(_ option: String, applyConstraint function: (CDouble) -> CDouble) -> Double? {
    let value: Double? = getOptionalDoubleForOption(option)
    return value != nil ? function(value!) : nil
  }

  func getStringForOption(_ option: String) -> String? {
    let cachedValue: String? = cachedValueOfType(String.self, forKey: option) as? String
    if (cachedValue != nil) {
      return cachedValue
    }
    let value: UnsafePointer<CChar>? = _isOpen ? rime_get_api().pointee.config_get_cstring(&_config, option) : nil
    if (value != nil) {
      let string: String = String(cString: value!).trimmingCharacters(in: CharacterSet.whitespaces)
      _cache[option] = string
      return string
    }
    return _baseConfig?.getStringForOption(option) ?? nil
  }

  func getColorForOption(_ option: String) -> NSColor? {
    let cachedValue: NSColor? = cachedValueOfClass(NSColor.self, forKey: option) as? NSColor
    if (cachedValue != nil) {
      return cachedValue
    }
    let color: NSColor? = colorFromString(getStringForOption(option))
    if (color != nil) {
      _cache[option] = color
      return color
    }
    return _baseConfig?.getColorForOption(option) ?? nil
  }

  func getImageForOption(_ option: String) -> NSImage? {
    let cachedValue: NSImage? = cachedValueOfClass(NSImage.self, forKey: option) as? NSImage
    if (cachedValue != nil) {
      return cachedValue
    }
    let image: NSImage? = imageFromFile(getStringForOption(option))
    if (image != nil) {
      _cache[option] = image
      return image
    }
    return _baseConfig?.getImageForOption(option) ?? nil
  }

  func getListSizeForOption(_ option: String) -> Int {
    return rime_get_api().pointee.config_list_size(&_config, option)
  }

  func getListForOption(_ option: String) -> [String]? {
    var iterator: RimeConfigIterator = RimeConfigIterator()
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

  func getOptionSwitcher() -> SquirrelOptionSwitcher? {
    var switchIter: RimeConfigIterator = RimeConfigIterator()
    if (!rime_get_api().pointee.config_begin_list(&switchIter, &_config, "switches").Bool) {
      return nil;
    }
    var switcher: [String: String] = [:]
    var optionGroups: [String: [String]] = [:]
    while (rime_get_api().pointee.config_next(&switchIter).Bool) {
      let reset: Int = getIntForOption(String(cString: switchIter.path) + "/reset")
      let name: String? = getStringForOption(String(cString: switchIter.path) + "/name")
      if (name != nil) {
        if hasSection("style/!" + name!) || hasSection("style/" + name!) {
          switcher[name!] = reset != 0 ? name! : "!" + name!
          optionGroups[name!] = [name!]
        }
      } else {
        var optionIter: RimeConfigIterator = RimeConfigIterator()
        if (!rime_get_api().pointee.config_begin_list(
          &optionIter, &_config, String(cString: switchIter.path) + "/options").Bool) {
          continue;
        }
        var optionGroup: [String] = []
        var hasStyleSection: Boolean = false
        while (rime_get_api().pointee.config_next(&optionIter).Bool) {
          let option: String = getStringForOption(String(cString: optionIter.path))!
          optionGroup.append(option)
          hasStyleSection = hasStyleSection || hasSection("style/" + option)
        }
        rime_get_api().pointee.config_end(&optionIter);
        if (hasStyleSection) {
          for i in 0..<optionGroup.count {
            switcher[optionGroup[i]] = optionGroup[size_t(reset)]
            optionGroups[optionGroup[i]] = optionGroup
          }
        }
      }
    }
    rime_get_api().pointee.config_end(&switchIter)
    return SquirrelOptionSwitcher.init(schemaId: _schemaId, switcher: switcher, optionGroups: optionGroups)
  }

  func getAppOptions(_ appName: String) -> SquirrelAppOptions? {
    let rootKey: String = "app_options/" + appName
    var appOptions: SquirrelAppOptions = SquirrelAppOptions()
    var iterator: RimeConfigIterator = RimeConfigIterator()
    if (!rime_get_api().pointee.config_begin_map(&iterator, &_config, rootKey).Bool) {
      return nil;
    }
    while (rime_get_api().pointee.config_next(&iterator).Bool) {
      //NSLog(@"DEBUG option[%d]: %s (%s)", iterator.index, iterator.key, iterator.path);
      let value: Any? = getOptionalBoolForOption(String(cString: iterator.path)) ??
                        getOptionalIntForOption(String(cString: iterator.path)) ??
                        getOptionalDoubleForOption(String(cString: iterator.path))
      if (value != nil) {
        appOptions[String(cString: iterator.key)] = value
      }
    }
    rime_get_api().pointee.config_end(&iterator);
    return appOptions.count > 0 ? appOptions : nil;
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
    if (string == nil) {
      return nil
    }
    var r: CInt = 0, g: CInt = 0, b: CInt = 0, a: CInt = 0xff
    if (string?.count == 10) {
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
    } else if (string?.count == 8) {
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
    if (self.colorSpace == "display_p3") {
      return NSColor.init(displayP3Red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    } else {  // sRGB by default
      return NSColor.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
  }

  private func imageFromFile(_ filePath: String?) -> NSImage? {
    if (filePath == nil) {
      return nil
    }
    let userDataDir: URL = URL.init(fileURLWithPath:("~/Library/Rime" as NSString).expandingTildeInPath, isDirectory: true)
    let imageFile: URL = URL.init(fileURLWithPath: filePath!, isDirectory: false, relativeTo: userDataDir)
    if ((try? imageFile.checkResourceIsReachable()) != nil) {
      let image: NSImage = NSImage.init(byReferencing: imageFile)
      return image
    }
    return nil
  }

}  // SquirrelConfig
