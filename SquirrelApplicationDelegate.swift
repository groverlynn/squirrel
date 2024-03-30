import UserNotifications
import AppKit
import Cocoa


enum SquirrelNotificationPolicy: Int {
  case never = 0
  case whenAppropriate = 1
  case always = 2
}

let kRimeWikiURL: String = "https://github.com/rime/home/wiki"

fileprivate func bridge<T : AnyObject>(obj : T?) -> UnsafeMutableRawPointer? {
  return obj != nil ? UnsafeMutableRawPointer(Unmanaged.passUnretained(obj!).toOpaque()) : nil
}
fileprivate func bridge<T : AnyObject>(ptr : UnsafeMutableRawPointer?) -> T? {
  return ptr != nil ? Unmanaged<T>.fromOpaque(ptr!).takeUnretainedValue() : nil
}


func show_notification(_ msg_text: UnsafePointer<CChar>) {
  if #available(macOS 10.14, *) {
    let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
    center.requestAuthorization(options:UNAuthorizationOptions(arrayLiteral: [.alert, .provisional])) { (granted:Swift.Bool, error:(any Error)?) in
      if (error != nil) {
        NSLog("User notification authorization error: %s", error.debugDescription)
      }
    }
    center.getNotificationSettings { (settings:UNNotificationSettings) in
      if ((settings.authorizationStatus == .authorized ||
           settings.authorizationStatus == .provisional) &&
          (settings.alertSetting == .enabled)) {
        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        content.title = NSLocalizedString("Squirrel", comment: "")
        content.subtitle = NSLocalizedString(String(cString: msg_text), comment: "")
        if #available(macOS 12.0, *) {
          content.interruptionLevel = .active
        }
        let request: UNNotificationRequest = UNNotificationRequest.init(identifier: "SquirrelNotification", content: content, trigger: nil)
        center.add(request) { error in
          if (error != nil) {
            NSLog("User notification request error: %s", error.debugDescription);
          }
        }
      }
    }
  } else {
    let notification: NSUserNotification = NSUserNotification()
    notification.title = NSLocalizedString("Squirrel", comment: "")
    notification.subtitle = NSLocalizedString(String(cString: msg_text), comment: "")

    let notificationCenter: NSUserNotificationCenter = NSUserNotificationCenter.default
    notificationCenter.removeAllDeliveredNotifications()
    notificationCenter.deliver(notification)
  }
}

fileprivate func show_status(msg_text_long: UnsafePointer<CChar>?, msg_text_short: UnsafePointer<CChar>?) {
  let msgLong: String? = msg_text_long != nil ? String(cString: msg_text_long!) : nil
  let msgShort: String? = msg_text_short != nil ? String(cString: msg_text_short!) : msgLong != nil ? String(msgLong![msgLong!.rangeOfComposedCharacterSequence(at: msgLong!.startIndex)]) : nil
  NSApp.SquirrelAppDelegate().panel?.updateStatus(long: msgLong, short:msgShort)
}

fileprivate func notification_handler(context_object: UnsafeMutableRawPointer?,
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
  if (strcmp(message_type, "schema") == 0 && app_delegate?.showNotifications != .never) {
    var schema_name: UnsafeMutablePointer<CChar>? = strchr(message_value, Int32(UnicodeScalar("/").value))
    if (schema_name != nil) {
      schema_name! += 1
      show_status(msg_text_long: schema_name, msg_text_short: schema_name)
    }
    return
  }
  // option change
  if (strcmp(message_type, "option") == 0 && app_delegate != nil && message_value != nil) {
    let state: Boolean = message_value![0] != UInt8(ascii: "!")
    let option_name: UnsafePointer<CChar> = message_value! + (state ? 0 : 1)
    if (app_delegate!.panel!.optionSwitcher?.containsOption(String(cString: option_name)) ?? false) {
      if (app_delegate!.panel!.optionSwitcher?.updateGroupState(String(cString: message_value!),
                                                                ofOption: String(cString: option_name)) ?? false) {
        let schemaId: String = app_delegate!.panel!.optionSwitcher!.schemaId
        app_delegate?.loadSchemaSpecificLabels(schemaId: schemaId)
        app_delegate?.loadSchemaSpecificSettings(schemaId: schemaId, withRimeSession:session_id)
      }
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

fileprivate func updateOptionSwitcher(optionSwitcher: SquirrelOptionSwitcher?,
                                      sessionId: RimeSessionId) -> SquirrelOptionSwitcher? {
  if (optionSwitcher?.switcher == nil || sessionId == 0) {
    return nil
  }
  var switcher: [String: String] = optionSwitcher!.switcher
  let prevStates: Set = Set(optionSwitcher!.optionStates())
  for state in prevStates {
    var updatedState: String?
    let optionGroup: [String] = switcher.compactMap({ (key: String, value: String) -> String? in
      value == state ? key : nil
    })
    for option in optionGroup {
      if (rime_get_api().pointee.get_option(sessionId, option).Bool) {
        updatedState = option
        break
      }
    }
    updatedState = updatedState ?? "!" + optionGroup[0]
    if (updatedState != state) {
      for option in optionGroup {
        switcher[option] = updatedState
      }
    }
  }
  _ = optionSwitcher!.updateSwitcher(switcher)
  return optionSwitcher;
}

class SquirrelApplicationDelegate: NSObject, NSApplicationDelegate {

  @IBOutlet var menu: NSMenu?
  @IBOutlet var panel: SquirrelPanel?
  @IBOutlet var updater: NSObject?
  private var _config: SquirrelConfig?
  var config: SquirrelConfig? {
    get { return _config }
  }
  private var _showNotifications: SquirrelNotificationPolicy = .never
  var showNotifications: SquirrelNotificationPolicy {
    get { return _showNotifications }
  }

  @IBAction func deploy(_ sender: Any?) {
    self.shutdownRime()
    self.startRime(withFullCheck: true)
    self.loadSettings()
  }

  @IBAction func syncUserData(_ sender: Any?) {
    NSLog("Sync user data")
    _ = rime_get_api().pointee.sync_user_data()
  }

  @IBAction func configure(_ sender: Any?) {
    NSWorkspace.shared.open(URL.init(fileURLWithPath: ("~/Library/Rime/" as NSString).expandingTildeInPath, isDirectory: true))
  }

  @IBAction func openWiki(_ sender: Any?) {
    NSWorkspace.shared.open(URL.init(string: kRimeWikiURL)!)
  }

  @IBAction func openLogFolder(_ sender: Any?) {
    let tmpDir: String = NSTemporaryDirectory()
    let logFile: String = (tmpDir as NSString).appendingPathComponent("rime.squirrel.INFO")
    NSWorkspace.shared.selectFile(logFile, inFileViewerRootedAtPath: tmpDir)
  }

  override init() {
    super.init()
  }

  func setupRime() {
    let userDataDir: String = ("~/Library/Rime" as NSString).expandingTildeInPath
    let fileManager: FileManager = FileManager.default
    if (!fileManager.fileExists(atPath: userDataDir)) {
      do {
        try fileManager.createDirectory(atPath: userDataDir, withIntermediateDirectories: true, attributes: nil)
      } catch {
        NSLog("Error creating user data directory: %s", userDataDir)
      }
    }

    rime_get_api().pointee.set_notification_handler(notification_handler, bridge(obj: self))
    var squirrel_traits: RimeTraits = RimeTraits()
    squirrel_traits.shared_data_dir = Bundle.main.sharedSupportPath?.utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    squirrel_traits.user_data_dir = userDataDir.utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    squirrel_traits.distribution_code_name = "Squirrel".utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    squirrel_traits.distribution_name = "鼠鬚管".utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    squirrel_traits.distribution_version = (Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! NSString).utf8String
    squirrel_traits.app_name = "rime.squirrel".utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    rime_get_api().pointee.setup(&squirrel_traits)
  }

  func startRime(withFullCheck: Boolean) {
    NSLog("Initializing la rime...")
    rime_get_api().pointee.initialize(nil)
    // check for configuration updates
    if (rime_get_api().pointee.start_maintenance(withFullCheck.Bool).Bool) {
      // update squirrel config
      _ = rime_get_api().pointee.deploy_config_file("squirrel.yaml", "config_version")
    }
  }

  func shutdownRime() {
    self.config?.close()
    rime_get_api().pointee.finalize()
  }

  func loadSettings() {
    _config = SquirrelConfig()
    if (!_config!.openBaseConfig()) {
      return
    }

    let showNotificationsWhen: String? = _config!.getStringForOption("show_notifications_when") ?? nil
    if (showNotificationsWhen == "never") {
      _showNotifications = .never
    } else if (showNotificationsWhen == "appropriate") {
      _showNotifications = .whenAppropriate
    } else {
      _showNotifications = .always
    }
    panel?.loadConfig(_config!)
  }

  func loadSchemaSpecificSettings(schemaId: String, withRimeSession sessionId: RimeSessionId) {
    if (schemaId.count == 0 || schemaId.hasPrefix(".")) {
    return;
  }
  // update the list of switchers that change styles and color-themes
    let schema: SquirrelConfig = SquirrelConfig.init()
    if (schema.open(withSchemaId: schemaId, baseConfig: self.config!) &&
        schema.hasSection("style")) {
      let optionSwitcher: SquirrelOptionSwitcher? = schema.getOptionSwitcher()
      panel?.optionSwitcher = updateOptionSwitcher(optionSwitcher: optionSwitcher, sessionId: sessionId)
      panel?.loadConfig(schema)
    } else {
      panel?.optionSwitcher = SquirrelOptionSwitcher.init(schemaId: schemaId)
      panel?.loadConfig(self.config)
    }
    schema.close()
  }

  func loadSchemaSpecificLabels(schemaId: String) {
    let defaultConfig: SquirrelConfig = SquirrelConfig.init()
    _ = defaultConfig.open(withConfigId: "default")
    if (schemaId.count == 0 || schemaId.hasPrefix(".")) {
      panel?.loadLabelConfig(defaultConfig, directUpdate: true)
      defaultConfig.close()
      return
    }
    let schema: SquirrelConfig = SquirrelConfig.init()
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
    let logfile: URL = URL.init(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("squirrel_launch.dat")
    NSLog("[DEBUG] archive: %s", [logfile]);
    if let archive = try? Data.init(contentsOf: logfile, options: .uncached)  {
      if let previousLaunch: NSDate = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSDate.self, from: archive) {
        if (previousLaunch.timeIntervalSinceNow >= -2) {
          detected = true
        }
      }
    }
    if let record:Data = try? NSKeyedArchiver.archivedData(withRootObject: Date.init(), requiringSecureCoding: false) {
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

  internal func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    NSLog("Squirrel is quitting.")
    _config?.close()
    rime_get_api().pointee.cleanup_all_sessions()
    return .terminateNow
  }

  //add an awakeFromNib item so that we can set the action method.  Note that
  //any menuItems without an action will be disabled when displayed in the Text
  //Input Menu.
  override func awakeFromNib() {
    let center: NotificationCenter = NSWorkspace.shared.notificationCenter
    center.addObserver(self, selector: #selector(workspaceWillPowerOff), name: Notification.Name(NSWorkspace.willPowerOffNotification.rawValue), object: nil)

    let notifCenter: DistributedNotificationCenter = DistributedNotificationCenter.default()
    notifCenter.addObserver(self, selector: #selector(rimeNeedsReload(_:)), name: Notification.Name("SquirrelReloadNotification"), object: nil)
    notifCenter.addObserver(self, selector: #selector(rimeNeedsSync(_:)), name: Notification.Name("SquirrelSyncNotification"), object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
    panel?.hide()
  }

}

extension NSApplication {

  func SquirrelAppDelegate() -> SquirrelApplicationDelegate {
    return delegate as! SquirrelApplicationDelegate
  }

}
