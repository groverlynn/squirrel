import AppKit
import Cocoa
import InputMethodKit
import Sparkle
import UserNotifications
import Combine

@main final class SquirrelApp: NSObject, Sendable {
  static let delegate: SquirrelApplicationDelegate = .init()
  static let bundleId: String = Bundle.main.bundleIdentifier!

  static func main() {
    let args: [String] = CommandLine.arguments
    if args.count > 1 {
      switch args[1] {
      case "--quit":
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).forEach { $0.terminate() }
        return
      case "--reload":
        DistributedNotificationCenter.default().postNotificationName(SquirrelApplicationDelegate.willReloadNotification, object: nil)
        return
      case "--register-input-source", "--install":
        RegisterInputSource()
        return
      case "--enable-input-source":
        let inputModes: RimeInputModes = args.dropFirst(2).reduce(RimeInputModes(), { $0.union(RimeInputModes(code: $1) ?? []) })
        EnableInputSource(inputModes)
        return
      case "--disable-input-source":
        DisableInputSource()
        return
      case "--select-input-source":
        let inputModes: RimeInputModes = args.dropFirst(2).reduce(RimeInputModes(), { $0.union(RimeInputModes(code: $1) ?? []) })
        SelectInputSource(inputModes)
        return
      case "--build":
        ShowNotification(message: "deploy_update")
        // build all schemas in current directory
        var builderTraits: RimeTraits = RimeStructInit()
        builderTraits.app_name = "rime.squirrel-builder".utf8CString.withUnsafeBufferPointer(\.baseAddress)
        RimeApi.setup(&builderTraits)
        RimeApi.deployer_initialize(nil)
        _ = RimeApi.deploy()
        return
      case "--sync":
        DistributedNotificationCenter.default().postNotificationName(SquirrelApplicationDelegate.willSyncNotification, object: nil)
        return
      default:
        break
      }
    }

    autoreleasepool {
      // find the bundle identifier and then initialize the input method server
      _ = IMKServer(name: Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String, bundleIdentifier: bundleId)
      // load the bundle explicitly because in this case the input method is a background only application
      NSApplication.shared.delegate = delegate
      NSApplication.shared.setActivationPolicy(.accessory)
      // opencc will be configured with relative dictionary paths
      FileManager.default.changeCurrentDirectoryPath(Bundle.main.sharedSupportPath!)

      if delegate.problematicLaunchDetected() {
        print("Problematic launch detected!")
        let args: [String] = ["-v", Bundle.main.localizedString(forKey: "say_voice", value: nil, table: "Notifications"), Bundle.main.localizedString(forKey: "problematic_launch", value: nil, table: "Notifications")]
        if #available(macOS 10.13, *) {
          do {
            try Process.run(URL(fileURLWithPath: "/usr/bin/say", isDirectory: false), arguments: args, terminationHandler: nil)
          } catch {
            print(args[2])
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

enum SquirrelNotificationPolicy: Sendable {
  case never, whenAppropriate, always
}

final class SquirrelApplicationDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate, Sendable {
  static let userDataDir: URL = .init(fileURLWithPath: "Library/Rime/", isDirectory: true, relativeTo: FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
  static private let RimeWiki: URL = .init(string: "https://github.com/rime/home/wiki")!
  static let willReloadNotification: Notification.Name = .init("SquirrelWillReload")
  static let willSyncNotification: Notification.Name = .init("SquirrelWillSync")
  static let updaterIdentifier: String = "SquirrelUpdateNotification"
  static let notifIdentifier: String = "SquirrelNotification"
  private var updateController: SPUStandardUpdaterController { .init(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) }
  var supportsGentleScheduledUpdateReminders: Bool { true }

  nonisolated(unsafe) private(set) var workspaceWillPowerOff: AnyCancellable?
  nonisolated(unsafe) private(set) var rimeWillReload: AnyCancellable?
  nonisolated(unsafe) private(set) var rimeWillSync: AnyCancellable?
  nonisolated(unsafe) private(set) var inputSourceDidChange: AnyCancellable?

  nonisolated(unsafe) private(set) var showNotifications: SquirrelNotificationPolicy = .never
  nonisolated(unsafe) private(set) var switcherKeyEquivalent: RimeKeyCode = .XK_VoidSymbol
  nonisolated(unsafe) private(set) var switcherKeyModifierMask: RimeModifiers = []

  @MainActor let panel: SquirrelPanel = .init()
  var menu: NSMenu {
    let menu: NSMenu = .init()
    menu.addItem(NSMenuItem(title: Bundle.main.localizedString(forKey: "showSwitcher", value: nil, table: "MainMenu"), action: #selector(showSwitcher(_:)), keyEquivalent: ""))
    let deploy: NSMenuItem = .init(title: Bundle.main.localizedString(forKey: "deploy", value: nil, table: "MainMenu"), action: #selector(deploy(_:)), keyEquivalent: "`")
    deploy.keyEquivalentModifierMask = [.control, .option]
    menu.addItem(deploy)
    menu.addItem(NSMenuItem(title: Bundle.main.localizedString(forKey: "syncUserData", value: nil, table: "MainMenu"), action: #selector(syncUserData(_:)), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: Bundle.main.localizedString(forKey: "configure", value: nil, table: "MainMenu"), action: #selector(configure(_:)), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: Bundle.main.localizedString(forKey: "openWiki", value: nil, table: "MainMenu"), action: #selector(openWiki(_:)), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: Bundle.main.localizedString(forKey: "checkForUpdates", value: nil, table: "MainMenu"), action: #selector(checkForUpdates(_:)), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: Bundle.main.localizedString(forKey: "openLogFolder", value: nil, table: "MainMenu"), action: #selector(openLogFolder(_:)), keyEquivalent: ""))
    return menu
  }

  /* updater */
  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    _ = MainActor.assumeIsolated { NSApp.setActivationPolicy(.regular) }
    if !state.userInitiated {
      MainActor.assumeIsolated { NSApp.dockTile.badgeLabel = "1" }
      let content: UNMutableNotificationContent = .init()
      content.title = Bundle.main.localizedString(forKey: "new_update", value: nil, table: "Notifications")
      content.body = String(format: Bundle.main.localizedString(forKey: "update_version", value: nil, table: "Notifications"), update.displayVersionString)
      let request: UNNotificationRequest = .init(identifier: Self.updaterIdentifier, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request)
    }
  }

  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
    MainActor.assumeIsolated { NSApp.dockTile.badgeLabel = "" }
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.updaterIdentifier])
  }

  func standardUserDriverWillFinishUpdateSession() {
    MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier == Self.updaterIdentifier, response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      updateController.updater.checkForUpdates()
    }
  }

  /* launching */
  func applicationWillFinishLaunching(_ notification: Notification) {
    let center: NotificationCenter = NSWorkspace.shared.notificationCenter
    workspaceWillPowerOff = center.publisher(for: NSWorkspace.willPowerOffNotification).sink { _ in
      print("Finalizing before logging out.")
      self.shutdownRime()
    }
    let notifCenter: DistributedNotificationCenter = .default()
    rimeWillReload = notifCenter.publisher(for: Self.willReloadNotification).sink { _ in
      print("Reloading rime on demand.")
      self.deploy(nil)
    }
    rimeWillSync = notifCenter.publisher(for: Self.willSyncNotification).sink { _ in
      print("Sync rime on demand.")
      self.syncUserData(nil)
    }
    SquirrelInputController.isCurrentInputMethod = false
    inputSourceDidChange = notifCenter.publisher(for: kTISNotifySelectedKeyboardInputSourceChanged as Notification.Name).sink { _ in
      let inputSource: TISInputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
      if let inputSourceID: String = bridge(ptr: TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID), as: CFString.self) as? String, !inputSourceID.hasPrefix(SquirrelApp.bundleId) {
        SquirrelInputController.isCurrentInputMethod = false
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    workspaceWillPowerOff?.cancel()
    rimeWillReload?.cancel()
    rimeWillSync?.cancel()
    inputSourceDidChange?.cancel()
    panel.hide()
  }

  /* menu selectors */
  @objc func showSwitcher(_ sender: Any?) {
    print("Show Switcher")
    guard switcherKeyEquivalent != .XK_VoidSymbol, let session: RimeSessionId = sender as? RimeSessionId else { return }
    _ = RimeApi.process_key(session, switcherKeyEquivalent.rawValue, switcherKeyModifierMask.rawValue)
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

  @objc func openWiki(_ sender: Any?) {
    NSWorkspace.shared.open(Self.RimeWiki)
  }

  @objc func checkForUpdates(_ sender: Any?) {
    if updateController.updater.canCheckForUpdates {
      print("Checking for updates")
      updateController.updater.checkForUpdates()
    } else {
      print("Cannot check for updates")
    }
  }

  @objc func openLogFolder(_ sender: Any?) {
    let infoLog: URL = .init(fileURLWithPath: "rime.squirrel.INFO", isDirectory: false, relativeTo: FileManager.default.temporaryDirectory).standardizedFileURL
    NSWorkspace.shared.activateFileViewerSelecting([infoLog])
  }

  func setupRime() {
    if !FileManager.default.fileExists(atPath: Self.userDataDir.path) {
      do {
        try FileManager.default.createDirectory(at: Self.userDataDir, withIntermediateDirectories: true)
      } catch {
        print("Error creating user data directory: \(Self.userDataDir.path)")
      }
    }
    RimeApi.set_notification_handler(notificationHandler, bridge(obj: self))
    var squirrelTraits: RimeTraits = RimeStructInit()
    squirrelTraits.shared_data_dir = Bundle.main.sharedSupportURL?.withUnsafeFileSystemRepresentation(\.unsafelyUnwrapped)
    squirrelTraits.user_data_dir = Self.userDataDir.withUnsafeFileSystemRepresentation(\.unsafelyUnwrapped)
    squirrelTraits.distribution_code_name = "Squirrel".utf8CString.withUnsafeBufferPointer(\.baseAddress)
    squirrelTraits.distribution_name = "鼠鬚管".utf8CString.withUnsafeBufferPointer(\.baseAddress)
    squirrelTraits.distribution_version = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? UnsafePointer<CChar>
    squirrelTraits.app_name = "rime.squirrel".utf8CString.withUnsafeBufferPointer(\.baseAddress)
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
    let defaultConfig: SquirrelConfig = .init(.default)
    SquirrelInputController.goodOldCapsLock = defaultConfig.boolValue(for: "ascii_composer/good_old_caps_lock") ?? false
    if let hotkey: String = defaultConfig.stringValue(for: "switcher/hotkeys/@0") {
      let keys: [String] = hotkey.components(separatedBy: "+")
      switcherKeyModifierMask = keys.dropLast().reduce([], { $0.union(RimeModifiers(name: $1) ?? []) })
      switcherKeyEquivalent = RimeKeyCode(name: keys.last!)
    }
    defaultConfig.close()
    MainActor.assumeIsolated {
      let baseConfig: SquirrelConfig = .init()
      guard baseConfig.openBaseConfig() else { return }
      showNotifications = switch baseConfig.stringValue(for: "show_notifications_when") {
      case "never": .never
      case "always": .always
      default: .whenAppropriate
      }
      SquirrelInputController.keyboardLayout = baseConfig.stringValue(for: "keyboard_layout")
      SquirrelInputController.chordDuration = if let duration: Double = baseConfig.doubleValue(for: "chord_duration"), duration.isNormal { duration } else { 0.1 }
      panel.optionSwitcher = SquirrelOptionSwitcher()
      SquirrelTheme.light.updateTheme(withConfig: baseConfig, styleOptions: panel.optionSwitcher.optionStates, scriptVariant: panel.optionSwitcher.currentScriptVariant)
      if #available(macOS 10.14, *) {
        SquirrelTheme.dark.updateTheme(withConfig: baseConfig, styleOptions: panel.optionSwitcher.optionStates, scriptVariant: panel.optionSwitcher.currentScriptVariant)
      }
      panel.getLocked()
      panel.updateDisplayParameters()
      baseConfig.close()
    }
  }

  func loadSchemaSpecificSettings(schemaId: String) {
    guard !schemaId.isEmpty, !schemaId.hasPrefix(".") else { return }
    // update the list of switchers that change styles and color-themes
    MainActor.assumeIsolated {
      let baseConfig: SquirrelConfig = .init(.base)
      let schema: SquirrelConfig = .init()
      if schema.open(schemaId: schemaId, baseConfig: baseConfig), schema.hasSection("style") {
        panel.optionSwitcher = schema.optionSwitcher()
        panel.optionSwitcher.update()
        SquirrelTheme.light.updateTheme(withConfig: schema, styleOptions: panel.optionSwitcher.optionStates, scriptVariant: panel.optionSwitcher.currentScriptVariant)
        if #available(macOS 10.14, *) {
          SquirrelTheme.dark.updateTheme(withConfig: schema, styleOptions: panel.optionSwitcher.optionStates, scriptVariant: panel.optionSwitcher.currentScriptVariant)
        }
      } else {
        panel.optionSwitcher = SquirrelOptionSwitcher(schemaId: schemaId)
        SquirrelTheme.light.updateTheme(withConfig: baseConfig, styleOptions: panel.optionSwitcher.optionStates, scriptVariant: panel.optionSwitcher.currentScriptVariant)
        if #available(macOS 10.14, *) {
          SquirrelTheme.dark.updateTheme(withConfig: baseConfig, styleOptions: panel.optionSwitcher.optionStates, scriptVariant: panel.optionSwitcher.currentScriptVariant)
        }
      }
      panel.getLocked()
      panel.updateDisplayParameters()
      schema.close()
      baseConfig.close()
    }
  }

  func loadSchemaSpecificLabels(schemaId: String) {
    MainActor.assumeIsolated {
      let defaultConfig: SquirrelConfig = .init(.default)
      if schemaId.isEmpty || schemaId.hasPrefix(".") {
        SquirrelTheme.light.updateLabels(withConfig: defaultConfig, directUpdate: true)
        if #available(macOS 10.14, *) {
          SquirrelTheme.dark.updateLabels(withConfig: defaultConfig, directUpdate: true)
        }
        panel.updateDisplayParameters()
      } else {
        let schema: SquirrelConfig = .init()
        if schema.open(schemaId: schemaId, baseConfig: defaultConfig), schema.hasSection("menu") {
          SquirrelTheme.light.updateLabels(withConfig: schema, directUpdate: false)
          if #available(macOS 10.14, *) {
            SquirrelTheme.dark.updateLabels(withConfig: schema, directUpdate: false)
          }
        } else {
          SquirrelTheme.light.updateLabels(withConfig: defaultConfig, directUpdate: false)
          if #available(macOS 10.14, *) {
            SquirrelTheme.dark.updateLabels(withConfig: defaultConfig, directUpdate: false)
          }
        }
        schema.close()
      }
      defaultConfig.close()
    }
  }

  // prevent freezing the system
  func problematicLaunchDetected() -> Bool {
    var detected: Bool = false
    let logfile: URL = .init(fileURLWithPath: "squirrel_launch.dat", isDirectory: false, relativeTo: FileManager.default.temporaryDirectory).standardizedFileURL
    print("[DEBUG] archive: \(logfile)")
    if let archive: Data = try? Data(contentsOf: logfile, options: [.uncached]) {
      if let previousLaunch: NSDate = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSDate.self, from: archive), previousLaunch.timeIntervalSinceNow >= -2 {
        detected = true
      }
    }
    if let record: Data = try? NSKeyedArchiver.archivedData(withRootObject: Date(), requiringSecureCoding: false) {
      try? record.write(to: logfile, options: [.atomic])
    }
    return detected
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    print("Squirrel is quitting.")
    RimeApi.cleanup_all_sessions()
    return .terminateNow
  }
}  // SquirrelApplicationDelegate

private func ShowNotification(message: String) {
  if #available(macOS 10.14, *) {
    let center: UNUserNotificationCenter = .current()
    center.requestAuthorization(options: [.alert, .provisional]) { granted, error in
      if error != nil {
        print("User notification authorization error: \(error.debugDescription)")
      }
    }
    center.getNotificationSettings { settings in
      guard (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional), settings.alertSetting == .enabled else { return }
      let content: UNMutableNotificationContent = .init()
      content.title = Bundle.main.localizedString(forKey: "Squirrel", value: nil, table: "Notifications")
      content.subtitle = Bundle.main.localizedString(forKey: message, value: nil, table: "Notifications")
      if #available(macOS 12.0, *) { content.interruptionLevel = .active }
      let request: UNNotificationRequest = .init(identifier: SquirrelApplicationDelegate.notifIdentifier, content: content, trigger: nil)
      center.add(request) { error in
        if error != nil {
          print("User notification request error: \(error.debugDescription)")
        }
      }
    }
  } else {
    let notification: NSUserNotification = .init()
    notification.title = Bundle.main.localizedString(forKey: "Squirrel", value: nil, table: "Notifications")
    notification.subtitle = Bundle.main.localizedString(forKey: message, value: nil, table: "Notifications")
    let notificationCenter: NSUserNotificationCenter = .default
    notificationCenter.removeAllDeliveredNotifications()
    notificationCenter.deliver(notification)
  }
}

private let notificationHandler: @convention(c) (UnsafeMutableRawPointer?, RimeSessionId, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = { contextObject, sessionId, messageType, messageValue in
  guard let messageType = messageType else { return }
  switch String(cString: messageType) {
  case "deploy":
    guard let messageValue = messageValue else { break }
    switch String(cString: messageValue) {
    case "start": ShowNotification(message: "deploy_start")
    case "success": ShowNotification(message: "deploy_success")
    case "failure": ShowNotification(message: "deploy_failure")
    default: break
    }
  case "schema":
    guard let appDelegate: SquirrelApplicationDelegate = bridge(ptr: contextObject), appDelegate.showNotifications != .never, let messageValue = messageValue else { break }
    let schemaName: [String] = String(cString: messageValue).components(separatedBy: "/")
    if schemaName.count == 2 {
      MainActor.assumeIsolated { appDelegate.panel.updateStatus(long: schemaName[1], short: schemaName[1]) }
    }
  case "option":
    guard let appDelegate: SquirrelApplicationDelegate = bridge(ptr: contextObject), let messageValue = messageValue else { break }
    let optionState: String = .init(cString: messageValue)
    MainActor.assumeIsolated {
      guard let (optionName, state) : (String, Bool) = appDelegate.panel.optionSwitcher.optionAliases[optionState] else { return }
      let updateScriptVariant: Bool = appDelegate.panel.optionSwitcher.updateCurrentScriptVariant(optionState)
      var updateStyleOptions: Bool = false
      if appDelegate.panel.optionSwitcher.updateGroupState(optionState, ofOption: optionName) {
        updateStyleOptions = true
        let schemaId: String = appDelegate.panel.optionSwitcher.schemaId
        appDelegate.loadSchemaSpecificLabels(schemaId: schemaId)
        appDelegate.loadSchemaSpecificSettings(schemaId: schemaId)
      }
      if updateScriptVariant, !updateStyleOptions {
        appDelegate.panel.updateScriptVariant()
      }
      guard appDelegate.showNotifications != .never else { return }
      var longLabel: RimeStringSlice = RimeApi.get_state_label_abbreviated(sessionId, optionName, state, false)
      var shortLabel: RimeStringSlice = RimeApi.get_state_label_abbreviated(sessionId, optionName, state, true)
      let long: String? = longLabel.str == nil ? nil : String(cString: longLabel.str)
      let short: String? = shortLabel.str == nil || shortLabel.length < strlen(shortLabel.str) ? nil : String(cString: shortLabel.str)
      appDelegate.panel.updateStatus(long: long, short: short)
    }
  default: break
  }
}

// MARK: Bridging

func bridge<T: AnyObject>(obj: T!) -> UnsafeMutableRawPointer! {
  obj == nil ? nil : Unmanaged.passUnretained(obj).toOpaque()
}

func bridge<T: AnyObject>(ptr: UnsafeMutableRawPointer!, as type: T.Type = T.self) -> T! {
  ptr == nil ? nil : Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

typealias RimeSessionId = UInt
var RimeApi: RimeApi_stdbool { rime_get_api_stdbool().pointee }

protocol RimeStruct {
  var data_size: CInt { get set }
  init()
}

extension RimeTraits: RimeStruct {}
extension RimeCommit: RimeStruct {}
extension RimeStatus_stdbool: RimeStruct {}
extension RimeContext_stdbool: RimeStruct {}

func RimeStructInit<T: RimeStruct>(Type: T.Type = T.self) -> T {
  var rimeStruct: T = .init()
  rimeStruct.data_size = CInt(MemoryLayout<T>.size - MemoryLayout.size(ofValue: rimeStruct.data_size))
  return rimeStruct
}
