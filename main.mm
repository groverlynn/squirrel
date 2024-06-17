
#import "SquirrelApplicationDelegate.hh"
#import <rime_api_stdbool.h>
#import <rime_api.h>
#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

void RegisterInputSource(void);
void DisableInputSource(void);
void EnableInputSource(void);
void SelectInputSource(void);

int main(int argc, char* argv[]) {
  if (argc > 1 && strcmp("--quit", argv[1]) == 0) {
    NSString* bundleId = NSBundle.mainBundle.bundleIdentifier;
    NSArray<NSRunningApplication*>* runningSquirrels =
      [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleId];
    for (NSRunningApplication* squirrelApp in runningSquirrels) {
      [squirrelApp terminate];
    }
    return 0;
  }

  if (argc > 1 && strcmp("--reload", argv[1]) == 0) {
    [NSDistributedNotificationCenter.defaultCenter
     postNotificationName:@"SquirrelReloadNotification"
                   object:nil];
    return 0;
  }

  if (argc > 1 && (strcmp("--register-input-source", argv[1]) == 0 ||
                   strcmp("--install", argv[1]) == 0)) {
    RegisterInputSource();
    return 0;
  }

  if (argc > 1 && strcmp("--enable-input-source", argv[1]) == 0) {
    EnableInputSource();
    return 0;
  }

  if (argc > 1 && strcmp("--disable-input-source", argv[1]) == 0) {
    DisableInputSource();
    return 0;
  }

  if (argc > 1 && strcmp("--select-input-source", argv[1]) == 0) {
    SelectInputSource();
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
    [NSDistributedNotificationCenter.defaultCenter
     postNotificationName:@"SquirrelSyncNotification"
                   object:nil];
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
    [NSFileManager.defaultManager
     changeCurrentDirectoryPath:NSBundle.mainBundle.sharedSupportPath];

    if (NSApp.squirrelAppDelegate.problematicLaunchDetected) {
      NSLog(@"Problematic launch detected!");
      NSArray<NSString*>* args = @[@"-v", NSLocalizedStringFromTable(@"say_voice", @"Notifications", nil),
                                   NSLocalizedStringFromTable(@"problematic_launch", @"Notifications", nil)];
      if (@available(macOS 10.13, *)) {
        NSURL* say = [NSURL fileURLWithPath:@"/usr/bin/say" isDirectory:NO];
        [NSTask launchedTaskWithExecutableURL:say
                                    arguments:args
                                        error:nil
                           terminationHandler:nil];
      } else {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/say"
                                 arguments:args];
      }
    } else {
      [NSApp.squirrelAppDelegate setupRime];
      [NSApp.squirrelAppDelegate startRimeWithFullCheck:false];
      [NSApp.squirrelAppDelegate loadSettings];
      NSLog(@"Squirrel reporting!");
    }

    // finally run everything
    [NSApp run];

    NSLog(@"Squirrel is quitting...");
    rime_get_api_stdbool()->finalize();
  }
  return 0;
}
