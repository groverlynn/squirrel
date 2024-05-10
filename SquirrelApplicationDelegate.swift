import UserNotifications
import AppKit
import Cocoa
import InputMethodKit
import Sparkle

typealias Boolean = Swift.Bool
typealias RimeBool = CInt

let kConnectionName = "Squirrel_1_Connection"
let kRimeWikiURL: String = "https://github.com/rime/home/wiki"

@NSApplicationMain @objc class SquirrelApp: NSApplication, NSApplicationDelegate {

  func main() {
//    let argc = CommandLine.argc
//    let argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> = CommandLine.unsafeArgv

    func NSApplicationMain(_ argc: CInt,
                           _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> CInt {
      if (argc > 1 && strcmp("--quit", argv[1]!) == 0) {
        let bundleId: String = Bundle.main.bundleIdentifier!
        let runningSquirrels: [NSRunningApplication] =
          NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        for SquirrelApp in runningSquirrels {
          SquirrelApp.terminate()
        }
        return 0
      }

      if (argc > 1 && strcmp("--reload", argv[1]!) == 0) {
        DistributedNotificationCenter.default().post(name: NSNotification.Name("SquirrelReloadNotification"), object: nil)
        return 0
      }

      if (argc > 1 && (strcmp("--register-input-source", argv[1]!) == 0 ||
                       strcmp("--install", argv[1]!) == 0)) {
        RegisterInputSource()
        return 0
      }

      if (argc > 1 && strcmp("--enable-input-source", argv[1]!) == 0) {
        EnableInputSource();
        return 0
      }

      if (argc > 1 && strcmp("--disable-input-source", argv[1]!) == 0) {
        DisableInputSource();
        return 0
      }

      if (argc > 1 && strcmp("--select-input-source", argv[1]!) == 0) {
        SelectInputSource();
        return 0
      }

      if (argc > 1 && strcmp("--build", argv[1]!) == 0) {
        // notification
        show_notification("deploy_update")
        // build all schemas in current directory
        var builder_traits: RimeTraits = RimeTraits()
        builder_traits.app_name = "rime.squirrel-builder"
          .utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
        rime_get_api().pointee.setup(&builder_traits)
        rime_get_api().pointee.deployer_initialize(nil)
        return rime_get_api().pointee.deploy().Bool ? 0 : 1
      }

      if (argc > 1 && strcmp("--sync", argv[1]!) == 0) {
        DistributedNotificationCenter.default().post(
          name: NSNotification.Name("SquirrelSyncNotification"), object: nil)
        return 0
      }

      autoreleasepool {
        // find the bundle identifier and then initialize the input method server
        _ = IMKServer(name: kConnectionName,
                      bundleIdentifier: Bundle.main.bundleIdentifier)

        // load the bundle explicitly because in this case the input method is a
        // background only application
        Bundle.main.loadNibNamed("MainMenu", owner: NSApplication.shared,
                                 topLevelObjects: nil)

        // opencc will be configured with relative dictionary paths
        FileManager.default.changeCurrentDirectoryPath(Bundle.main.sharedSupportPath!)

        if (NSApp.squirrelApp.problematicLaunchDetected()) {
          NSLog("Problematic launch detected!")
          let args: [String] = ["-v", NSLocalizedString("say_voice", comment: ""),
                                NSLocalizedString("problematic_launch", comment: "")]
          if #available(macOS 10.13, *) {
            do {
              try Process.run(URL(fileURLWithPath: "/usr/bin/say", isDirectory: false),
                              arguments: args, terminationHandler: nil)
            } catch {
              NSLog("Error message cannot be communicated through audio:\n%@",
                    NSLocalizedString("problematic_launch", comment: ""))
            }
          } else {
            Process.launchedProcess(launchPath: "/usr/bin/say", arguments: args)
          }
        } else {
          NSApp.squirrelApp.setupRime()
          NSApp.squirrelApp.startRime(withFullCheck: False)
          NSApp.squirrelApp.loadSettings()
          NSLog("Squirrel reporting!")
        }

        // finally run everything
        NSApplication.shared.run()

        NSLog("Squirrel is quitting...")
        rime_get_api().pointee.finalize()
      }
      return 0
    }
  }

  private var _switcherKeyEquivalent: CInt = 0
  private var _switcherKeyModifierMask: RimeModifier = []
  private var _isCurrentInputMethod: Boolean = false
  var isCurrentInputMethod: Boolean {
    get { return _isCurrentInputMethod }
    set (newValue) { _isCurrentInputMethod = newValue }
  }
  private var _config: SquirrelConfig?
  var config: SquirrelConfig? { get { return _config } }
  private var _showNotifications: SquirrelNotificationPolicy = .never
  var showNotifications: SquirrelNotificationPolicy { get { return _showNotifications } }

  private weak var _menuBar: NSMenu?
  @objc @IBOutlet weak var menuBar: NSMenu? {
    get { return _menuBar }
    set(newValue) { _menuBar = newValue }
  }
  private weak var _panel: SquirrelPanel?
  @objc @IBOutlet weak var panel: SquirrelPanel? {
    get { return _panel }
    set(newValue) { _panel = newValue }
  }
  private weak var _updater: SPUUpdater?
  @objc @IBOutlet weak var updater: SPUUpdater? {
    get { return _updater }
    set(newValue) { _updater = newValue }
  }

  @objc @IBAction func showSwitcher(_ sender: Any?) {
    NSLog("Show Switcher");
    if (_switcherKeyEquivalent != 0) {
      let session: RimeSessionId = sender as! UInt
      _ = rime_get_api().pointee.process_key(session, _switcherKeyEquivalent,
                                             _switcherKeyModifierMask.rawValue);
    }
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
    NSWorkspace.shared.open(URL(fileURLWithPath: "~/Library/Rime/", isDirectory: true).standardized)
  }

  @objc @IBAction func openWiki(_ sender: Any?) {
    NSWorkspace.shared.open(URL(string: kRimeWikiURL)!)
  }

  @objc @IBAction func openLogFolder(_ sender: Any?) {
    let infoLog: URL = FileManager.default.temporaryDirectory
                         .appendingPathComponent("rime.squirrel.INFO", isDirectory: false)
    let warningLog: URL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("rime.squirrel.WARNING", isDirectory: false)
    let errorLog: URL = FileManager.default.temporaryDirectory
                          .appendingPathComponent("rime.squirrel.ERROR", isDirectory: false)
    NSWorkspace.shared.activateFileViewerSelecting([infoLog, warningLog, errorLog])
  }

  @objc func setupRime() {
    var userDataDir: URL = FileManager.default.homeDirectoryForCurrentUser
    userDataDir.appendPathComponent("Library/Rime", isDirectory: true)
    do { let exist = try userDataDir.checkResourceIsReachable()
          if (!exist) {
            do { try FileManager.default.createDirectory(at: userDataDir,
                   withIntermediateDirectories: true, attributes: nil)
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
    squirrel_traits.distribution_code_name = "Squirrel".utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    squirrel_traits.distribution_name = "鼠鬚管".utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    squirrel_traits.distribution_version = CFBundleGetValueForInfoDictionaryKey(
      CFBundleGetMainBundle(), kCFBundleVersionKey).fileSystemRepresentation
    squirrel_traits.app_name = "rime.squirrel".utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    rime_get_api().pointee.setup(&squirrel_traits)
  }

  @objc func startRime(withFullCheck fullCheck: RimeBool) {
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
    _switcherKeyModifierMask = []
    _switcherKeyEquivalent = 0
    let defaulConfig = SquirrelConfig()
    if (defaulConfig.open(withConfigId:"default")) {
      if let hotkey = defaulConfig.getStringForOption("switcher/hotkeys/@0") {
        let keys: [String] = hotkey.components(separatedBy:"+")
        for i in 0..<(keys.count - 1) {
          _switcherKeyModifierMask.insert(rime_modifiers_from_name(keys[i]))
        }
        _switcherKeyEquivalent = rime_keycode_from_name(keys.last!)
      }
    }
    defaulConfig.close()

    _config = SquirrelConfig()
    if (!_config!.openBaseConfig()) {
      return
    }
    _showNotifications = .whenAppropriate
    if let showNotificationsWhen = _config?.getStringForOption("show_notifications_when") {
      if (showNotificationsWhen.caseInsensitiveCompare("never") == .orderedSame) {
        _showNotifications = .never
      } else if (showNotificationsWhen.caseInsensitiveCompare("always") == .orderedSame) {
        _showNotifications = .always
      }
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
      panel?.optionSwitcher = schema.getOptionSwitcher()
      panel?.optionSwitcher.update(withRimeSession: sessionId)
      panel?.loadConfig(schema)
    } else {
      panel?.optionSwitcher = SquirrelOptionSwitcher(schemaId: schemaId)
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
    if let archive = try? Data(contentsOf: logfile, options: .uncached)  {
      if let previousLaunch: NSDate = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSDate.self, from: archive) {
        if (previousLaunch.timeIntervalSinceNow >= -2) {
          detected = true
        }
      }
    }
    if let record: Data = try? NSKeyedArchiver.archivedData(withRootObject: Date(), requiringSecureCoding: false) {
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
    if let inputSourceID = Unmanaged<AnyObject>.fromOpaque(TISGetInputSourceProperty(
      inputSource, kTISPropertyInputSourceID)).takeUnretainedValue() as? String {
      if (!inputSourceID.hasPrefix(Bundle.main.bundleIdentifier!)) {
        _isCurrentInputMethod = false
      }
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
        let request = UNNotificationRequest(identifier: "SquirrelNotification",
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

func show_status(msg_text_long: UnsafePointer<CChar>?,
                 msg_text_short: UnsafePointer<CChar>?) {
  let msgLong: String? = msg_text_long != nil ? String(cString: msg_text_long!) : nil
  let msgShort: String? = msg_text_short != nil ? String(cString: msg_text_short!) : msgLong != nil
  ? String(msgLong![msgLong!.rangeOfComposedCharacterSequence(at: msgLong!.startIndex)]) : nil
  NSApp.squirrelApp.panel?.updateStatus(long: msgLong, short:msgShort)
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
  let app_delegate: SquirrelApp? = bridge(ptr: context_object)
  // schema change
  if (strcmp(message_type, "schema") == 0 &&
      app_delegate?.showNotifications != .never) {
    var schema_name: UnsafeMutablePointer<CChar>? =
    strchr(message_value, CInt(UInt8(ascii: "/")))
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
    let updateScriptVariant: Boolean = app_delegate!.panel!.optionSwitcher
      .updateCurrentScriptVariant(String(cString: message_value!))
    var updateStyleOptions: Boolean = false
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
      let state_label_long: RimeStringSlice = rime_get_api().pointee
        .get_state_label_abbreviated(session_id, option_name, state.Bool, False)
      let state_label_short: RimeStringSlice = rime_get_api().pointee
        .get_state_label_abbreviated(session_id, option_name, state.Bool, True)
      if (state_label_long.str != nil || state_label_short.str != nil) {
        let short_message: UnsafePointer<CChar>? =
        state_label_short.length < strlen(state_label_short.str) ? nil : state_label_short.str
        show_status(msg_text_long: state_label_long.str, msg_text_short: short_message)
      }
    }
  }
}

@frozen enum SquirrelNotificationPolicy: Int {
  case never, whenAppropriate, always
}

extension NSApplication {

  @objc var squirrelApp: SquirrelApp {
    get { return delegate as! SquirrelApp }
  }

}
