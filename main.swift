import AppKit
import Cocoa
import InputMethodKit

// Each input method needs a unique connection name.
// Note that periods and spaces are not allowed in the connection name.
let kConnectionName = "Squirrel_1_Connection"

//let delegate = SquirrelApplicationDelegate()
//NSApplication.shared.delegate = delegate
_ = Main(CommandLine.argc, CommandLine.unsafeArgv)

func Main(_ argc: CInt,
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
    return 0;
  }

  if (argc > 1 && strcmp("--disable-input-source", argv[1]!) == 0) {
    DisableInputSource();
    return 0;
  }

  if (argc > 1 && strcmp("--select-input-source", argv[1]!) == 0) {
    SelectInputSource();
    return 0;
  }

  if (argc > 1 && strcmp("--build", argv[1]!) == 0) {
    // notification
    show_notification("deploy_update")
    // build all schemas in current directory
    var builder_traits: RimeTraits = RimeTraits()
    builder_traits.app_name = "rime.squirrel-builder".utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    rime_get_api().pointee.setup(&builder_traits)
    rime_get_api().pointee.deployer_initialize(nil)
    return rime_get_api().pointee.deploy().Bool ? 0 : 1
  }

  if (argc > 1 && strcmp("--sync", argv[1]!) == 0) {
    DistributedNotificationCenter.default().post(name: NSNotification.Name("SquirrelSyncNotification"), object: nil)
    return 0
  }

  autoreleasepool {
    // find the bundle identifier and then initialize the input method server
    _ = IMKServer(name: kConnectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

    // load the bundle explicitly because in this case the input method is a
    // background only application
    Bundle.main.loadNibNamed("MainMenu", owner: NSApplication.shared, topLevelObjects: nil)

    // opencc will be configured with relative dictionary paths
    FileManager.default.changeCurrentDirectoryPath(Bundle.main.sharedSupportPath!)

    if (NSApp.squirrelAppDelegate.problematicLaunchDetected()) {
      NSLog("Problematic launch detected!")
      let args: [String] = ["-v", NSLocalizedString("say_voice", comment: ""),
                            NSLocalizedString("problematic_launch", comment: "")]
      if #available(macOS 10.13, *) {
        do {
          try Process.run(URL.init(fileURLWithPath: "/usr/bin/say", isDirectory: false),
                          arguments: args, terminationHandler: nil)
        } catch {
          NSLog("Error message cannot be communicated through audio:\n%@",
                NSLocalizedString("problematic_launch", comment: ""))
        }
      } else {
        Process.launchedProcess(launchPath: "/usr/bin/say", arguments: args)
      }
    } else {
      NSApp.squirrelAppDelegate.setupRime()
      NSApp.squirrelAppDelegate.startRime(withFullCheck: False)
      NSApp.squirrelAppDelegate.loadSettings()
      NSLog("Squirrel reporting!")
    }

    // finally run everything
    NSApplication.shared.run()

    NSLog("Squirrel is quitting...")
    rime_get_api().pointee.finalize()
  }
  return 0
}
