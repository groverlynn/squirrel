import AppKit
import Cocoa
import InputMethodKit
import Sparkle
import UserNotifications

@main final class SquirrelApp: NSApplication {
  static let bundleId: String = Bundle.main.bundleIdentifier!

  static func main() {
    let args: [String] = CommandLine.arguments
    if args.count > 1 {
      switch args[1] {
      case "--quit":
        let runningSquirrels: [NSRunningApplication] = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        runningSquirrels.forEach { $0.terminate() }
        return
      case "--reload":
        DistributedNotificationCenter.default().postNotificationName(.init("SquirrelReloadNotification"), object: nil)
        return
      case "--register-input-source", "--install":
        SquirrelInputSource.RegisterInputSource()
        return
      case "--enable-input-source":
        var inputModes: RimeInputModes = []
        if args.count > 2 {
          args[2...].forEach { if let mode = RimeInputModes(code: $0) { inputModes.insert(mode) } }
        }
        SquirrelInputSource.EnableInputSource(inputModes)
        return
      case "--disable-input-source":
        SquirrelInputSource.DisableInputSource()
        return
      case "--select-input-source":
        var inputModes: RimeInputModes = []
        if args.count > 2 {
          args[2...].forEach { if let mode = RimeInputModes(code: $0) { inputModes.insert(mode) } }
        }
        SquirrelInputSource.SelectInputSource(inputModes)
        return
      case "--build":
        // notification
        showNotification(message: "deploy_update")
        // build all schemas in current directory
        var builderTraits: RimeTraits = RimeStructInit()
        builderTraits.app_name = ("rime.squirrel-builder" as NSString).utf8String
        RimeApi.setup(&builderTraits)
        RimeApi.deployer_initialize(nil)
        _ = RimeApi.deploy()
        return
      case "--sync":
        DistributedNotificationCenter.default().postNotificationName(.init("SquirrelSyncNotification"), object: nil)
        return
      default:
        break
      }
    }
    autoreleasepool {
      // find the bundle identifier and then initialize the input method server
      let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName")
      _ = IMKServer(name: connectionName as? String, bundleIdentifier: bundleId)

      // load the bundle explicitly because in this case the input method is a background only application
      let delegate = SquirrelApplicationDelegate()
      NSApplication.shared.delegate = delegate
      NSApplication.shared.setActivationPolicy(.accessory)

      // opencc will be configured with relative dictionary paths
      FileManager.default.changeCurrentDirectoryPath(Bundle.main.sharedSupportPath!)

      if delegate.problematicLaunchDetected() {
        print("Problematic launch detected!")
        let args: [String] = ["-v", NSLocalizedString("say_voice", comment: ""), NSLocalizedString("problematic_launch", comment: "")]
        if #available(macOS 10.13, *) {
          do {
            try Process.run(URL(fileURLWithPath: "/usr/bin/say", isDirectory: false), arguments: args, terminationHandler: nil)
          } catch {
            print("Error message cannot be communicated through audio:\n", NSLocalizedString("problematic_launch", comment: ""))
          }
        } else {
          Process.launchedProcess(launchPath: "/usr/bin/say", arguments: args)
        }
      } else {
        delegate.setupRime()
        delegate.startRime(withFullCheck: false)
        delegate.loadSettings()
        print("Squirrel reporting!")
      }

      // finally run everything
      NSApp.run()

      print("Squirrel is quitting...")
      RimeApi.finalize()
    }
  }
}

final class SquirrelApplicationDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate {
  @frozen enum SquirrelNotificationPolicy {
    case never, whenAppropriate, always
  }
  private(set) var showNotifications: SquirrelNotificationPolicy = .never
  private var switcherKeyEquivalent: RimeKeycode = .XK_VoidSymbol
  private var switcherKeyModifierMask: RimeModifiers = []
  var isCurrentInputMethod: Bool = false
  lazy var panel = SquirrelPanel()
  let menu = NSMenu()
  private let updateController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  var supportsGentleScheduledUpdateReminders: Bool { true }

  static let userDataDir = URL(fileURLWithPath: "Library/Rime/", isDirectory: true, relativeTo: FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
  static let RimeWiki = URL(string: "https://github.com/rime/home/wiki")!

  /*** updater ***/
  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    NSApp.setActivationPolicy(.regular)
    if !state.userInitiated {
      NSApp.dockTile.badgeLabel = "1"
      let content = UNMutableNotificationContent()
      content.title = NSLocalizedString("new_update", comment: "")
      content.body = String(format: NSLocalizedString("update_version", comment: ""), update.displayVersionString)
      let request = UNNotificationRequest(identifier: "SquirrelUpdateNotification", content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request)
    }
  }

  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
    NSApp.dockTile.badgeLabel = ""
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["SquirrelUpdateNotification"])
  }

  func standardUserDriverWillFinishUpdateSession() {
    NSApp.setActivationPolicy(.accessory)
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier == "SquirrelUpdateNotification" && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      updateController.updater.checkForUpdates()
    }
    completionHandler()
  }

  /*** launching ***/
  func applicationWillFinishLaunching(_ notification: Notification) {
    setupMenu()
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: nil, using: workspaceWillPowerOff(_:))
    let notifCenter = DistributedNotificationCenter.default()
    notifCenter.addObserver(forName: Notification.Name("SquirrelReloadNotification"), object: nil, queue: nil, using: rimeNeedsReload(_:))
    notifCenter.addObserver(forName: Notification.Name("SquirrelSyncNotification"), object: nil, queue: nil, using: rimeNeedsSync(_:))
    isCurrentInputMethod = false
    notifCenter.addObserver(forName: kTISNotifySelectedKeyboardInputSourceChanged as Notification.Name, object: nil, queue: nil, using: inputSourceChanged(_:))
  }

  func applicationWillTerminate(_ notification: Notification) {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
    panel.hide()
  }

  private func setupMenu() {
    let showSwitcher = NSMenuItem(title: NSLocalizedString("showSwitcher", comment: ""), action: #selector(showSwitcher(_:)), keyEquivalent: "")
    showSwitcher.target = self
    menu.addItem(showSwitcher)
    let deploy = NSMenuItem(title: NSLocalizedString("deploy", comment: ""), action: #selector(deploy(_:)), keyEquivalent: "`")
    deploy.target = self
    deploy.keyEquivalentModifierMask = [.control, .option]
    menu.addItem(deploy)
    let syncUserData = NSMenuItem(title: NSLocalizedString("syncUserData", comment: ""), action: #selector(syncUserData(_:)), keyEquivalent: "")
    syncUserData.target = self
    menu.addItem(syncUserData)
    let configure = NSMenuItem(title: NSLocalizedString("configure", comment: ""), action: #selector(configure(_:)), keyEquivalent: "")
    configure.target = self
    menu.addItem(configure)
    let openWiki = NSMenuItem(title: NSLocalizedString("openWiki", comment: ""), action: #selector(openWiki(_:)), keyEquivalent: "")
    openWiki.target = self
    menu.addItem(openWiki)
    let checkForUpdates = NSMenuItem(title: NSLocalizedString("checkForUpdates", comment: ""), action: #selector(checkForUpdates(_:)), keyEquivalent: "")
    checkForUpdates.target = self
    menu.addItem(checkForUpdates)
    let openLogFolder = NSMenuItem(title: NSLocalizedString("openLogFolder", comment: ""), action: #selector(openLogFolder(_:)), keyEquivalent: "")
    openLogFolder.target = self
    menu.addItem(openLogFolder)
  }

  /*** menu selectors ***/
  @objc func showSwitcher(_ sender: Any?) {
    print("Show Switcher")
    if switcherKeyEquivalent != .XK_VoidSymbol {
      let session = RimeSessionId((sender as! NSNumber).uint64Value)
      _ = RimeApi.process_key(session, switcherKeyEquivalent.rawValue, switcherKeyModifierMask.rawValue)
    }
  }

  @objc func deploy(_ sender: Any?) {
    print("Start maintenance...")
    shutdownRime()
    startRime(withFullCheck: true)
    loadSettings()
  }

  @objc func syncUserData(_ sender: Any?) {
    print("Sync user data")
    _ = RimeApi.sync_user_data()
  }

  @objc func configure(_ sender: Any?) {
    NSWorkspace.shared.open(Self.userDataDir)
  }

  @objc func checkForUpdates(_ sender: Any?) {
    if updateController.updater.canCheckForUpdates {
      print("Checking for updates")
      updateController.updater.checkForUpdates()
    } else {
      print("Cannot check for updates")
    }
  }

  @objc func openWiki(_ sender: Any?) {
    NSWorkspace.shared.open(Self.RimeWiki)
  }

  @objc func openLogFolder(_ sender: Any?) {
    let infoLog = URL(fileURLWithPath: "rime.squirrel.INFO", isDirectory: false, relativeTo: FileManager.default.temporaryDirectory).standardizedFileURL
    NSWorkspace.shared.activateFileViewerSelecting([infoLog])
  }

  func setupRime() {
    if !FileManager.default.fileExists(atPath: Self.userDataDir.path) {
      do {
        try FileManager.default.createDirectory(at: Self.userDataDir, withIntermediateDirectories: true)
      } catch {
        print("Error creating user data directory: \(Self.userDataDir.absoluteString)")
      }
    }
    RimeApi.set_notification_handler(notificationHandler, bridge(obj: self))
    var squirrelTraits: RimeTraits = RimeStructInit()
    squirrelTraits.shared_data_dir = (Bundle.main.sharedSupportURL as? NSURL)?.fileSystemRepresentation
    squirrelTraits.user_data_dir = (Self.userDataDir as NSURL).fileSystemRepresentation
    squirrelTraits.distribution_code_name = ("Squirrel" as NSString).utf8String
    squirrelTraits.distribution_name = ("鼠鬚管" as NSString).utf8String
    squirrelTraits.distribution_version = (Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? NSString)?.utf8String
    squirrelTraits.app_name = ("rime.squirrel" as NSString).utf8String
    RimeApi.setup(&squirrelTraits)
  }

  func startRime(withFullCheck fullCheck: Bool) {
    print("Initializing la rime...")
    RimeApi.initialize(nil)
    // check for configuration updates
    if RimeApi.start_maintenance(fullCheck) {
      // update squirrel config
      _ = RimeApi.deploy_config_file("squirrel.yaml", "config_version")
      print("[DEBUG] Maintenance has finished.")
    } else {
      print("[DEBUG] Maintenance has failed.")
    }
  }

  func shutdownRime() {
    RimeApi.finalize()
  }

  func loadSettings() {
    switcherKeyModifierMask = []
    switcherKeyEquivalent = .XK_VoidSymbol
    let defaulConfig = SquirrelConfig("default")
    if let hotkey = defaulConfig.string(forOption: "switcher/hotkeys/@0") {
      let keys: [String] = hotkey.components(separatedBy: "+")
      for i in 0 ..< (keys.count - 1) {
        if let modifier = RimeModifiers(name: keys[i]) {
          switcherKeyModifierMask.insert(modifier)
        }
      }
      switcherKeyEquivalent = RimeKeycode(name: keys.last!)
    }
    defaulConfig.close()

    let config = SquirrelConfig()
    if !config.openBaseConfig() {
      return
    }

    let showNotificationsWhen = config.string(forOption: "show_notifications_when")
    if showNotificationsWhen?.caseInsensitiveCompare("never") == .orderedSame {
      showNotifications = .never
    } else if showNotificationsWhen?.caseInsensitiveCompare("always") == .orderedSame {
      showNotifications = .always
    } else {
      showNotifications = .whenAppropriate
    }
    panel.loadConfig(config)
    config.close()
  }

  func loadSchemaSpecificSettings(schemaId: String, withRimeSession sessionId: RimeSessionId) {
    if schemaId.isEmpty || schemaId.hasPrefix(".") {
      return
    }
    // update the list of switchers that change styles and color-themes
    let baseConfig = SquirrelConfig("squirrel")
    let schema = SquirrelConfig()
    if schema.open(withSchemaId: schemaId, baseConfig: baseConfig) && schema.hasSection("style") {
      panel.optionSwitcher = schema.optionSwitcherForSchema()
      panel.optionSwitcher.update(withRimeSession: sessionId)
      panel.loadConfig(schema)
    } else {
      panel.optionSwitcher = SquirrelOptionSwitcher(schemaId: schemaId)
      panel.loadConfig(baseConfig)
    }
    schema.close()
    baseConfig.close()
  }

  func loadSchemaSpecificLabels(schemaId: String) {
    let defaultConfig = SquirrelConfig("default")
    if schemaId.isEmpty || schemaId.hasPrefix(".") {
      panel.loadLabelConfig(defaultConfig, directUpdate: true)
      defaultConfig.close()
      return
    }
    let schema = SquirrelConfig()
    if schema.open(withSchemaId: schemaId, baseConfig: defaultConfig) && schema.hasSection("menu") {
      panel.loadLabelConfig(schema, directUpdate: false)
    } else {
      panel.loadLabelConfig(defaultConfig, directUpdate: false)
    }
    schema.close()
    defaultConfig.close()
  }

  // prevent freezing the system
  func problematicLaunchDetected() -> Bool {
    var detected: Bool = false
    let logfile = URL(fileURLWithPath: "squirrel_launch.dat", isDirectory: false, relativeTo: FileManager.default.temporaryDirectory).standardizedFileURL
    print("[DEBUG] archive: \(logfile)")
    if let archive = try? Data(contentsOf: logfile, options: [.uncached]) {
      if let previousLaunch: NSDate = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSDate.self, from: archive), previousLaunch.timeIntervalSinceNow >= -2 {
        detected = true
      }
    }
    if let record: Data = try? NSKeyedArchiver.archivedData(withRootObject: Date(), requiringSecureCoding: false) {
      try? record.write(to: logfile, options: [.atomic])
    }
    return detected
  }

  func workspaceWillPowerOff(_ notification: Notification) {
    print("Finalizing before logging out.")
    shutdownRime()
  }

  func rimeNeedsReload(_ notification: Notification) {
    print("Reloading rime on demand.")
    deploy(nil)
  }

  func rimeNeedsSync(_ notification: Notification) {
    print("Sync rime on demand.")
    syncUserData(nil)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    print("Squirrel is quitting.")
    RimeApi.cleanup_all_sessions()
    return .terminateNow
  }

  func inputSourceChanged(_ notification: Notification) {
    let inputSource: TISInputSource = TISCopyCurrentKeyboardInputSource().takeUnretainedValue()
    if let inputSourceID: CFString = bridge(ptr: TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)), !(inputSourceID as String).hasPrefix(SquirrelApp.bundleId) {
      isCurrentInputMethod = false
    }
  }
}

private func showNotification(message: String) {
  if #available(macOS 10.14, *) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .provisional]) { granted, error in
      if error != nil {
        print("User notification authorization error: \(error.debugDescription)")
      }
    }
    center.getNotificationSettings { settings in
      if (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) && (settings.alertSetting == .enabled) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Squirrel", comment: "")
        content.subtitle = NSLocalizedString(message, comment: "")
        if #available(macOS 12.0, *) {
          content.interruptionLevel = .active
        }
        let request = UNNotificationRequest(identifier: "SquirrelNotification", content: content, trigger: nil)
        center.add(request) { error in
          if error != nil {
            print("User notification request error: \(error.debugDescription)")
          }
        }
      }
    }
  } else {
    let notification = NSUserNotification()
    notification.title = NSLocalizedString("Squirrel", comment: "")
    notification.subtitle = NSLocalizedString(message, comment: "")

    let notificationCenter = NSUserNotificationCenter.default
    notificationCenter.removeAllDeliveredNotifications()
    notificationCenter.deliver(notification)
  }
}

private func notificationHandler(context_object: UnsafeMutableRawPointer?, session_id: RimeSessionId, message_type: UnsafePointer<CChar>?, message_value: UnsafePointer<CChar>?) {
  if let type = message_type {
    switch String(cString: type) {
    case "deploy":
      if let message = message_value {
        switch String(cString: message) {
        case "start":
          showNotification(message: "deploy_start")
        case "success":
          showNotification(message: "deploy_success")
        case "failure":
          showNotification(message: "deploy_failure")
        default:
          break
        }
      }
    case "schema":
      if let appDelegate: SquirrelApplicationDelegate = bridge(ptr: context_object), appDelegate.showNotifications != .never, let message = message_value {
        let schemaName = String(cString: message).components(separatedBy: "/")
        if schemaName.count == 2 {
          appDelegate.panel.updateStatus(long: schemaName[1], short: schemaName[1])
        }
      }
    case "option":
      if let appDelegate: SquirrelApplicationDelegate = bridge(ptr: context_object), let message = message_value {
        let optionState = String(cString: message)
        let state: Bool = !optionState.hasPrefix("!")
        let optionName = state ? optionState : String(optionState.suffix(optionState.count - 1))
        let updateScriptVariant: Bool = appDelegate.panel.optionSwitcher.updateCurrentScriptVariant(optionState)
        var updateStyleOptions: Bool = false
        if appDelegate.panel.optionSwitcher.updateGroupState(optionState, ofOption: optionName) {
          updateStyleOptions = true
          let schemaId: String = appDelegate.panel.optionSwitcher.schemaId
          appDelegate.loadSchemaSpecificLabels(schemaId: schemaId)
          appDelegate.loadSchemaSpecificSettings(schemaId: schemaId, withRimeSession: session_id)
        }
        if updateScriptVariant && !updateStyleOptions {
          appDelegate.panel.updateScriptVariant()
        }
        if appDelegate.showNotifications != .never {
          let longLabel = RimeApi.get_state_label_abbreviated(session_id, optionName, state, false)
          let shortLabel = RimeApi.get_state_label_abbreviated(session_id, optionName, state, true)
          if longLabel.str != nil || shortLabel.str != nil {
            let long = longLabel.str == nil ? nil : String(cString: longLabel.str!)
            let short = shortLabel.str == nil || shortLabel.length < strlen(shortLabel.str) ? nil : String(cString: shortLabel.str!)
            appDelegate.panel.updateStatus(long: long, short: short)
          }
        }
      }
    default:
      break
    }
  }
}

extension NSApplication {
  var SquirrelAppDelegate: SquirrelApplicationDelegate {
    delegate as! SquirrelApplicationDelegate
  }
}

// MARK: Bridging

func bridge<T: AnyObject>(obj: T?) -> UnsafeMutableRawPointer? {
  return obj != nil ? Unmanaged.passUnretained(obj!).toOpaque() : nil
}

func bridge<T: AnyObject>(ptr: UnsafeMutableRawPointer?) -> T? {
  return ptr != nil ? Unmanaged<T>.fromOpaque(ptr!).takeUnretainedValue() : nil
}

let RimeApi = rime_get_api_stdbool().pointee
typealias RimeSessionId = UInt

protocol RimeStruct {
  var data_size: CInt { get set }
  init()
}

extension RimeTraits: RimeStruct {}
extension RimeCommit: RimeStruct {}
extension RimeStatus_stdbool: RimeStruct {}
extension RimeContext_stdbool: RimeStruct {}

func RimeStructInit<T: RimeStruct>() -> T {
  var rimeStruct = T.init()
  rimeStruct.data_size = CInt(MemoryLayout<T>.size - MemoryLayout.size(ofValue: rimeStruct.data_size))
  return rimeStruct
}
