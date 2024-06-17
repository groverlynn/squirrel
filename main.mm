
#import "SquirrelApplicationDelegate.hh"
#import <rime_api_stdbool.h>
#import <rime_api.h>
#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

typedef CF_OPTIONS(CFIndex, RimeInputMode) {
  DEFAULT_INPUT_MODE = 1 << 0,
  HANS_INPUT_MODE = 1 << 0,
  HANT_INPUT_MODE = 1 << 1,
  CANT_INPUT_MODE = 1 << 2
};

void RegisterInputSource(void);
void DisableInputSource(void);
void EnableInputSource(RimeInputMode modesToEnable);
void SelectInputSource(RimeInputMode modeToSelect);

int main(int argc, char* argv[]) {
  if (argc > 1 && strcmp("--quit", argv[1]) == 0) {
    NSString* bundleId = NSBundle.mainBundle.bundleIdentifier;
    for (NSRunningApplication* squirrelApp in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleId])
      [squirrelApp terminate];
    return 0;
  }

  if (argc > 1 && strcmp("--reload", argv[1]) == 0) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:kWillReloadNotification object:nil];
    return 0;
  }

  if (argc > 1 && (strcmp("--register-input-source", argv[1]) == 0 || strcmp("--install", argv[1]) == 0)) {
    RegisterInputSource();
    return 0;
  }

  if (argc > 1 && strcmp("--enable-input-source", argv[1]) == 0) {
    RimeInputMode modesToEnable = 0;
    if (argc > 2) {
      for (int i = 2; i < argc; ++i) {
        if (strcmp("Hans", argv[i]) == 0 || strcmp("hans", argv[i]) == 0 || strcmp("HANS", argv[i]))
          modesToEnable |= HANS_INPUT_MODE;
        else if (strcmp("Hant", argv[i]) == 0 || strcmp("hant", argv[i]) == 0 || strcmp("HANT", argv[i]))
          modesToEnable |= HANT_INPUT_MODE;
        else if (strcmp("Cant", argv[i]) == 0 || strcmp("cant", argv[i]) == 0 || strcmp("CANT", argv[i]))
          modesToEnable |= CANT_INPUT_MODE;
      }
    }
    EnableInputSource(modesToEnable);
    return 0;
  }

  if (argc > 1 && strcmp("--disable-input-source", argv[1]) == 0) {
    DisableInputSource();
    return 0;
  }

  if (argc > 1 && strcmp("--select-input-source", argv[1]) == 0) {
    RimeInputMode modeToSelect = 0;
    if (argc > 2) {
      for (int i = 2; i < argc; ++i) {
        if (strcmp("Hans", argv[i]) == 0 || strcmp("hans", argv[i]) == 0 || strcmp("HANS", argv[i]))
          modeToSelect |= HANS_INPUT_MODE;
        else if (strcmp("Hant", argv[i]) == 0 || strcmp("hant", argv[i]) == 0 || strcmp("HANT", argv[i]))
          modeToSelect |= HANT_INPUT_MODE;
        else if (strcmp("Cant", argv[i]) == 0 || strcmp("cant", argv[i]) == 0 || strcmp("CANT", argv[i]))
          modeToSelect |= CANT_INPUT_MODE;
      }
    }
    SelectInputSource(modeToSelect);
    return 0;
  }

  if (argc > 1 && strcmp("--build", argv[1]) == 0) {
    // notification
    show_notification("deploy_update");
    // build all schemas in current directory
    RIME_STRUCT(RimeTraits, builder_traits);
    builder_traits.app_name = "rime.squirrel-builder";
    rime_get_api_stdbool()->setup(&builder_traits);
    rime_get_api_stdbool()->deployer_initialize(NULL);
    return rime_get_api_stdbool()->deploy() ? 0 : 1;
  }

  if (argc > 1 && strcmp("--sync", argv[1]) == 0) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:kWillSyncNotification object:nil];
    return 0;
  }

  @autoreleasepool {
    // find the bundle identifier and then initialize the input method server
    IMKServer* server __unused =
      [IMKServer.alloc initWithName:NSBundle.mainBundle.infoDictionary[@"InputMethodConnectionName"]
                   bundleIdentifier:NSBundle.mainBundle.bundleIdentifier];

    // load the bundle explicitly because in this case the input method is a
    // background only application
    [NSBundle.mainBundle loadNibNamed:@"MainMenu"
                                owner:NSApplication.sharedApplication
                      topLevelObjects:nil];

    // opencc will be configured with relative dictionary paths
    [NSFileManager.defaultManager changeCurrentDirectoryPath:NSBundle.mainBundle.sharedSupportPath];

    if (NSApp.SquirrelAppDelegate.problematicLaunchDetected) {
      NSLog(@"Problematic launch detected!");
      NSArray<NSString*>* args = @[@"-v",
                                   [NSBundle.mainBundle localizedStringForKey:@"say_voice"
                                                                        value:nil
                                                                        table:@"Notifications"],
                                   [NSBundle.mainBundle localizedStringForKey:@"problematic_launch"
                                                                        value:nil
                                                                        table:@"Notifications"]];
      if (@available(macOS 10.13, *)) {
        NSURL* say = [NSURL fileURLWithPath:@"/usr/bin/say" isDirectory:NO];
        [NSTask launchedTaskWithExecutableURL:say
                                    arguments:args
                                        error:nil
                           terminationHandler:nil];
      } else {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/say" arguments:args];
      }
    } else {
      [NSApp.SquirrelAppDelegate setupRime];
      [NSApp.SquirrelAppDelegate startRimeWithFullCheck:false];
      [NSApp.SquirrelAppDelegate loadSettings];
      NSLog(@"Squirrel reporting!");
    }

    // finally run everything
    [NSApp run];

    NSLog(@"Squirrel is quitting...");
    rime_get_api_stdbool()->finalize();
  }
  return 0;
}
