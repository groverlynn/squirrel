import UserNotifications
import AppKit
import Cocoa
import InputMethodKit
import Sparkle

typealias Boolean = Swift.Bool

extension CInt {
  var Bool: Swift.Bool {
    get { return self != 0 }
  }
}

extension Swift.Bool {
  var Bool: CInt {
    get { return self ? 1 : 0 }
  }
}

let kRimeWikiURL: String = "https://github.com/rime/home/wiki"

func bridge<T: AnyObject>(obj: T?) -> UnsafeMutableRawPointer? {
  return obj != nil ? UnsafeMutableRawPointer(Unmanaged.passUnretained(obj!).toOpaque()) : nil
}
func bridge<T: AnyObject>(ptr: UnsafeMutableRawPointer?) -> T? {
  return ptr != nil ? Unmanaged<T>.fromOpaque(ptr!).takeUnretainedValue() : nil
}

extension RimeTraits {
   init() { self.init(data_size: CInt(MemoryLayout<RimeTraits>.size - MemoryLayout<CInt>.size),
                      shared_data_dir: nil, user_data_dir: nil, distribution_name: nil,
                      distribution_code_name: nil, distribution_version: nil, app_name: nil,
                      modules: nil, min_log_level: 0, log_dir: nil, prebuilt_data_dir: nil, staging_dir: nil) }
}
extension RimeStatus {
  init() { self.init(data_size: CInt(MemoryLayout<RimeStatus>.size - MemoryLayout<CInt>.size),
                     schema_id: nil, schema_name: nil, is_disabled: 0,
                     is_composing: 0, is_ascii_mode: 0, is_full_shape: 0,
                     is_simplified: 0, is_traditional: 0, is_ascii_punct: 0) }
}
extension RimeContext {
  init() { self.init(data_size: CInt(MemoryLayout<RimeContext>.size - MemoryLayout<CInt>.size),
                     composition: RimeComposition(), menu: RimeMenu(),
                     commit_text_preview: nil, select_labels: nil) }
}
extension RimeCommit {
  init() { self.init(data_size: CInt(MemoryLayout<RimeCommit>.size - MemoryLayout<CInt>.size), text: nil) }
}

fileprivate func show_status(msg_text_long: UnsafePointer<CChar>?,
                             msg_text_short: UnsafePointer<CChar>?) {
  let msgLong: String? = msg_text_long != nil ? String(cString: msg_text_long!) : nil
  let msgShort: String? = msg_text_short != nil ? String(cString: msg_text_short!) : msgLong != nil ? String(msgLong![msgLong!.rangeOfComposedCharacterSequence(at: msgLong!.startIndex)]) : nil
  NSApp.squirrelAppDelegate.panel?.updateStatus(long: msgLong, short:msgShort)
}

func show_notification(_ msg_text: String) {
  if #available(macOS 10.14, *) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .provisional]) {
      (granted:Swift.Bool, error:(any Error)?) in
      if (error != nil) {
        NSLog("User notification authorization error: %@", error.debugDescription)
      }
    }
    center.getNotificationSettings { (settings:UNNotificationSettings) in
      if ((settings.authorizationStatus == .authorized ||
           settings.authorizationStatus == .provisional) &&
          (settings.alertSetting == .enabled)) {
        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        content.title = NSLocalizedString("Squirrel", comment: "")
        content.subtitle = NSLocalizedString(msg_text, comment: "")
        if #available(macOS 12.0, *) {
          content.interruptionLevel = .active
        }
        let request = UNNotificationRequest.init(identifier: "SquirrelNotification",
                                                 content: content, trigger: nil)
        center.add(request) { error in
          if (error != nil) {
            NSLog("User notification request error: %@", error.debugDescription)
          }
        }
      }
    }
  } else {
    let notification = NSUserNotification()
    notification.title = NSLocalizedString("Squirrel", comment: "")
    notification.subtitle = NSLocalizedString(msg_text, comment: "")

    let notificationCenter = NSUserNotificationCenter.default
    notificationCenter.removeAllDeliveredNotifications()
    notificationCenter.deliver(notification)
  }
}

func notification_handler(context_object: UnsafeMutableRawPointer?,
                          session_id: RimeSessionId,
                          message_type: UnsafePointer<CChar>?,
                          message_value: UnsafePointer<CChar>?) {
  if (strcmp(message_type, "deploy") == 0) {
    if (strcmp(message_value, "start") == 0) {
      show_notification("deploy_start")
    } else if (strcmp(message_value, "success") == 0) {
      show_notification("deploy_success")
    } else if (strcmp(message_value, "failure") == 0) {
      show_notification("deploy_failure")
    }
    return
  }
  let app_delegate: SquirrelApplicationDelegate? = bridge(ptr: context_object)
  // schema change
  if (strcmp(message_type, "schema") == 0 &&
      app_delegate?.showNotifications != .never) {
    var schema_name: UnsafeMutablePointer<CChar>? = 
      strchr(message_value, CInt(UnicodeScalar("/").value))
    if (schema_name != nil) {
      schema_name! += 1
      show_status(msg_text_long: schema_name, msg_text_short: schema_name)
    }
    return
  }
  // option change
  if (strcmp(message_type, "option") == 0 &&
      app_delegate != nil && message_value != nil) {
    let state: Boolean = message_value![0] != UInt8(ascii: "!")
    let option_name: UnsafePointer<CChar> = message_value! + (state ? 0 : 1)
    var updateStyleOptions: Boolean = false
    var updateScriptVariant: Boolean = false
    if (app_delegate!.panel!.optionSwitcher.updateCurrentScriptVariant(String(cString: message_value!))) {
      updateScriptVariant = true;
    }
    if (app_delegate!.panel!.optionSwitcher.updateGroupState(String(cString: message_value!),
                                                             ofOption: String(cString: option_name))) {
      updateStyleOptions = true
      let schemaId: String = app_delegate?.panel?.optionSwitcher.schemaId ?? ""
      app_delegate!.loadSchemaSpecificLabels(schemaId: schemaId)
      app_delegate!.loadSchemaSpecificSettings(schemaId: schemaId, withRimeSession: session_id)
    }
    if (updateScriptVariant && !updateStyleOptions) {
        app_delegate!.panel!.updateScriptVariant()
    }
    if (app_delegate?.showNotifications != .never) {
      let state_label_long: RimeStringSlice = rime_get_api().pointee.get_state_label_abbreviated(session_id, option_name, state.Bool, False)
      let state_label_short: RimeStringSlice = rime_get_api().pointee.get_state_label_abbreviated(session_id, option_name, state.Bool, True)
      if (state_label_long.str != nil || state_label_short.str != nil) {
        let short_message: UnsafePointer<CChar>? = state_label_short.length < strlen(state_label_short.str) ? nil : state_label_short.str
        show_status(msg_text_long: state_label_long.str, msg_text_short: short_message)
      }
    }
  }
}

enum SquirrelNotificationPolicy: Int {
  case never, whenAppropriate, always
}

class SquirrelApplicationDelegate: NSObject, NSApplicationDelegate {
  private var _switcherKeyEquivalent: CInt = 0
  private var _switcherKeyModifierMask: CInt = 0
  private var _isCurrentInputMethod: Boolean = false
  var isCurrentInputMethod: Boolean { get { return _isCurrentInputMethod } }
  private var _config: SquirrelConfig?
  var config: SquirrelConfig? { get { return _config } }
  private var _showNotifications: SquirrelNotificationPolicy = .never
  var showNotifications: SquirrelNotificationPolicy { get { return _showNotifications } }

  @objc @IBOutlet weak var menu: NSMenu?
  @objc @IBOutlet weak var panel: SquirrelPanel?
  @objc @IBOutlet weak var updater: SPUUpdater?

  @objc @IBAction func showSwitcher(_ sender: Any?) {
    NSLog("Show Switcher");
    let session: RimeSessionId = sender as! UInt
    _ = rime_get_api().pointee.process_key(session, _switcherKeyEquivalent, _switcherKeyModifierMask);
  }

  @objc @IBAction func deploy(_ sender: Any?) {
    self.shutdownRime()
    self.startRime(withFullCheck: True)
    self.loadSettings()
  }

  @objc @IBAction func syncUserData(_ sender: Any?) {
    NSLog("Sync user data")
    _ = rime_get_api().pointee.sync_user_data()
  }

  @objc @IBAction func configure(_ sender: Any?) {
    NSWorkspace.shared.open(URL.init(fileURLWithPath: ("~/Library/Rime/" as NSString).expandingTildeInPath, isDirectory: true))
  }

  @objc @IBAction func openWiki(_ sender: Any?) {
    NSWorkspace.shared.open(URL.init(string: kRimeWikiURL)!)
  }

  @objc @IBAction func openLogFolder(_ sender: Any?) {
    let tmpDir: String = NSTemporaryDirectory()
    let logFile: String = (tmpDir as NSString).appendingPathComponent("rime.squirrel.INFO")
    NSWorkspace.shared.selectFile(logFile, inFileViewerRootedAtPath: tmpDir)
  }

  @objc func setupRime() {
    let fileManager = FileManager.default
    var userDataDir: URL = fileManager.homeDirectoryForCurrentUser
    userDataDir.appendPathComponent("Library/Rime", isDirectory: true)
    do {
      let exist = try userDataDir.checkResourceIsReachable() 
      if (!exist) {
        do {
          try fileManager.createDirectory(at: userDataDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
          NSLog("Error creating user data directory: %@", userDataDir.path)
        }
      }
    } catch {
      NSLog("Error checking user data directory: %@", userDataDir.path)
    }
    rime_get_api().pointee.set_notification_handler(notification_handler, bridge(obj: self))
    var squirrel_traits: RimeTraits = RimeTraits()
    squirrel_traits.shared_data_dir = Bundle.main.sharedSupportURL?.withUnsafeFileSystemRepresentation{ $0 }
    squirrel_traits.user_data_dir = userDataDir.withUnsafeFileSystemRepresentation{ $0 }
    squirrel_traits.distribution_code_name = "Squirrel".withCString{ $0 }
    squirrel_traits.distribution_name = "鼠鬚管".withCString{ $0 }
    squirrel_traits.distribution_version = CFBundleGetValueForInfoDictionaryKey(CFBundleGetMainBundle(), kCFBundleVersionKey).fileSystemRepresentation
    squirrel_traits.app_name = "rime.squirrel".withCString{ $0 }
    rime_get_api().pointee.setup(&squirrel_traits)
  }

  @objc func startRime(withFullCheck fullCheck: Bool) {
    NSLog("Initializing la rime...")
    rime_get_api().pointee.initialize(nil)
    // check for configuration updates
    if (rime_get_api().pointee.start_maintenance(fullCheck).Bool) {
      // update squirrel config
      _ = rime_get_api().pointee.deploy_config_file("squirrel.yaml", "config_version")
    }
  }

  @objc func shutdownRime() {
    self.config?.close()
    rime_get_api().pointee.finalize()
  }

  @objc func loadSettings() {
    var modifiers: NSEvent.ModifierFlags = []
    var keychar: UInt16 = 0
    var rime_modifiers: RimeModifier = []
    var rime_keycode: CInt = 0
    let defaulConfig = SquirrelConfig()
    if (defaulConfig.open(withConfigId:"default")) {
      if let hotkey = defaulConfig.getStringForOption("switcher/hotkeys/@0") {
        let keys: [String] = hotkey.components(separatedBy:"+")
        for i in 0..<(keys.count - 1) {
          modifiers.insert(parse_macos_modifiers(keys[i]))
          rime_modifiers.insert(parse_rime_modifiers(keys[i]))
        }
        rime_keycode = parse_rime_keycode(keys.last!)
        keychar = parse_macos_keychar(keys.last!)
      }
    }
    defaulConfig.close()
    menu?.items[0].keyEquivalent = String(keychar)
    menu?.items[0].keyEquivalentModifierMask = modifiers
    _switcherKeyEquivalent = rime_keycode
    _switcherKeyModifierMask = rime_modifiers.rawValue

    _config = SquirrelConfig()
    if (!_config!.openBaseConfig()) {
      return
    }
    if let showNotificationsWhen: String = _config?.getStringForOption("show_notifications_when") {
      if (showNotificationsWhen.caseInsensitiveCompare("never") == .orderedSame) {
        _showNotifications = .never
      } else if (showNotificationsWhen.caseInsensitiveCompare("always") == .orderedSame) {
        _showNotifications = .always
      } else {
        _showNotifications = .whenAppropriate
      }
    } else {
      _showNotifications = .whenAppropriate
    }
    panel?.loadConfig(_config!)
  }

  func loadSchemaSpecificSettings(schemaId: String,
                                  withRimeSession sessionId: RimeSessionId) {
    if (schemaId.count == 0 || schemaId.hasPrefix(".")) {
      return;
    }
    // update the list of switchers that change styles and color-themes
    let schema: SquirrelConfig = SquirrelConfig()
    if (schema.open(withSchemaId: schemaId, baseConfig: self.config!) &&
        schema.hasSection("style")) {
      let optionSwitcher: SquirrelOptionSwitcher? = schema.getOptionSwitcher()
      optionSwitcher?.update(withRimeSession: sessionId)
      panel?.optionSwitcher = optionSwitcher!
      panel?.loadConfig(schema)
    } else {
      panel?.optionSwitcher = SquirrelOptionSwitcher.init(schemaId: schemaId)
      panel?.loadConfig(_config!)
    }
    schema.close()
  }

  func loadSchemaSpecificLabels(schemaId: String) {
    let defaultConfig: SquirrelConfig = SquirrelConfig()
    _ = defaultConfig.open(withConfigId: "default")
    if (schemaId.count == 0 || schemaId.hasPrefix(".")) {
      panel?.loadLabelConfig(defaultConfig, directUpdate: true)
      defaultConfig.close()
      return
    }
    let schema: SquirrelConfig = SquirrelConfig()
    if (schema.open(withSchemaId: schemaId, baseConfig: defaultConfig) &&
        schema.hasSection("menu")) {
      panel?.loadLabelConfig(schema, directUpdate: false)
    } else {
      panel?.loadLabelConfig(defaultConfig, directUpdate: false)
    }
    schema.close()
    defaultConfig.close()
  }

  // prevent freezing the system
  func problematicLaunchDetected() -> Boolean {
    var detected: Boolean = false
    let logfile: URL = FileManager.default.temporaryDirectory.appendingPathComponent("squirrel_launch.dat")
    NSLog("[DEBUG] archive: %@", [logfile]);
    if let archive = try? Data.init(contentsOf: logfile, options: .uncached)  {
      if let previousLaunch: NSDate = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSDate.self, from: archive) {
        if (previousLaunch.timeIntervalSinceNow >= -2) {
          detected = true
        }
      }
    }
    if let record:Data = try? NSKeyedArchiver.archivedData(withRootObject: Date(), requiringSecureCoding: false) {
      try? record.write(to: logfile, options: .atomic)
    }
    return detected
  }

  @objc func workspaceWillPowerOff(_ notification: NSNotification) {
    NSLog("Finalizing before logging out.")
    shutdownRime()
  }

  @objc func rimeNeedsReload(_ notification: NSNotification) {
    NSLog("Reloading rime on demand.")
    deploy(nil)
  }

  @objc func rimeNeedsSync(_ notification: NSNotification) {
    NSLog("Sync rime on demand.");
    syncUserData(nil)
  }

  @objc func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    NSLog("Squirrel is quitting.")
    _config?.close()
    rime_get_api().pointee.cleanup_all_sessions()
    return .terminateNow
  }

  @objc func inputSourceChanged(_ notification: NSNotification) {
    let inputSource: TISInputSource = TISCopyCurrentKeyboardInputSource().takeUnretainedValue()
    let inputSourceID: String = Unmanaged<AnyObject>.fromOpaque(TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)).takeUnretainedValue() as! String
    if (!inputSourceID.hasPrefix(Bundle.main.bundleIdentifier!)) {
      _isCurrentInputMethod = false
    }
  }

  //add an awakeFromNib item so that we can set the action method.  Note that
  //any menuItems without an action will be disabled when displayed in the Text
  //Input Menu.
  @objc override func awakeFromNib() {
    let center: NotificationCenter = NSWorkspace.shared.notificationCenter
    center.addObserver(self, selector: #selector(workspaceWillPowerOff(_:)),
                       name: NSWorkspace.willPowerOffNotification, object: nil)

    let notifCenter: DistributedNotificationCenter = DistributedNotificationCenter.default()
    notifCenter.addObserver(self, selector: #selector(rimeNeedsReload(_:)),
                            name: Notification.Name("SquirrelReloadNotification"), object: nil)
    notifCenter.addObserver(self, selector: #selector(rimeNeedsSync(_:)),
                            name: Notification.Name("SquirrelSyncNotification"), object: nil)
    _isCurrentInputMethod = false
    notifCenter.addObserver(self, selector: #selector(inputSourceChanged(_:)),
                            name: kTISNotifySelectedKeyboardInputSourceChanged as NSNotification.Name?,
                            object: nil, suspensionBehavior: .deliverImmediately)
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
    panel?.hide()
  }

}

extension NSApplication {

  @objc var squirrelAppDelegate: SquirrelApplicationDelegate {
    get { return delegate as! SquirrelApplicationDelegate }
  }

}
