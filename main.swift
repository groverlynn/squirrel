import AppKit
import Cocoa
import InputMethodKit


typealias Boolean = Swift.Bool

extension Int32 {
  var Bool: Swift.Bool {
    return self != 0
  }
}
extension Swift.Bool {
  var Bool: Int32 {
    return self ? 1 : 0
  }
}

// Each input method needs a unique connection name.
// Note that periods and spaces are not allowed in the connection name.
let kConnectionName: String = "Squirrel_1_Connection"

func main(_ argc: Int32,
          _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int {
  if argc > 1 && (strcmp("--quit", argv[1]) == 0) {
    let bundleId: String = Bundle.main.bundleIdentifier!
    let runningSquirrels: Array = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    for SquirrelApp in runningSquirrels {
      SquirrelApp.terminate()
    }
    return 0
  }

  if argc > 1 && (strcmp("--reload", argv[1]) == 0) {
    DistributedNotificationCenter.default().post(name: NSNotification.Name("SquirrelReloadNotification"), object: nil)
    return 0
  }

  if argc > 1 && (strcmp("--install", argv[1]) == 0) {
    // register and enable Squirrel
    RegisterInputSource()
    let input_modes: RimeInputMode? = GetEnabledInputModes()
    DeactivateInputSource()
    ActivateInputSource(modes: input_modes ?? RimeInputMode(arrayLiteral: .DEFAULT_INPUT_MODE))
    return 0
  }

  if argc > 1 && (strcmp("--build", argv[1]) == 0) {
    // notification
    show_notification("deploy_update")
    // build all schemas in current directory
    var builder_traits: RimeTraits = RimeTraits()
    builder_traits.app_name = "rime.squirrel-builder".utf8CString.withUnsafeBufferPointer{ $0.baseAddress }
    rime_get_api().pointee.setup(&builder_traits)
    rime_get_api().pointee.deployer_initialize(nil)
    return rime_get_api().pointee.deploy().Bool ? 0 : 1
  }

  if argc > 1 && (strcmp("--sync", argv[1]) == 0) {
    DistributedNotificationCenter.default().post(name: NSNotification.Name("SquirrelSyncNotification"), object: nil)
    return 0
  }

  autoreleasepool {
    // find the bundle identifier and then initialize the input method server
    let main: Bundle = Bundle.main
    _ = IMKServer(name: kConnectionName, bundleIdentifier: main.bundleIdentifier)

    // load the bundle explicitly because in this case the input method is a
    // background only application
    main.loadNibNamed(NSNib.Name("MainMenu"), owner: NSApplication.shared, topLevelObjects: nil)

    // opencc will be configured with relative dictionary paths
    FileManager.default.changeCurrentDirectoryPath(main.sharedSupportPath!)


    if (NSApp.SquirrelAppDelegate().problematicLaunchDetected)() {
      NSLog("Problematic launch detected!")
      let args: Array = ["-v", NSLocalizedString("say_voice", comment: ""),
                         NSLocalizedString("problematic_launch", comment: "")]
      if #available(macOS 10.13, *) {
        do {
          try Process.run(URL.init(fileURLWithPath: "/usr/bin/say", isDirectory: false),
                          arguments: args, terminationHandler: nil)
        } catch {
          NSLog("Error message cannot be communicated through audio:\n%s",
                NSLocalizedString("problematic_launch", comment: ""))
        }
      } else {
        Process.launchedProcess(launchPath: "/usr/bin/say", arguments: args)
      }
    } else {
      NSApp.SquirrelAppDelegate().setupRime()
      NSApp.SquirrelAppDelegate().startRime(withFullCheck: false)
      NSApp.SquirrelAppDelegate().loadSettings()
      NSLog("Squirrel reporting!")
    }

    // finally run everything
    NSApplication.shared.run()

    NSLog("Squirrel is quitting...")
    rime_get_api().pointee.finalize()
  }
  return 0
}
