#import "SquirrelApplicationDelegate.hh"

#import "SquirrelConfig.hh"
#import "SquirrelPanel.hh"
#import "macos_keycode.hh"
#import <rime_api_stdbool.h>
#import <rime_api.h>
#import <UserNotifications/UserNotifications.h>

static NSString* const kRimeWikiURL = @"https://github.com/rime/home/wiki";
static const CFStringRef kBundleId = CFSTR("im.rime.inputmethod.Squirrel");

@implementation SquirrelApplicationDelegate {
  int _switcherKeyEquivalent;
  int _switcherKeyModifierMask;
}

- (IBAction)showSwitcher:(id)sender {
  NSLog(@"Show Switcher");
  if (_switcherKeyEquivalent != 0) {
    RimeSessionId session = [sender unsignedLongValue];
    rime_get_api_stdbool()->process_key(session, _switcherKeyEquivalent,
                                        _switcherKeyModifierMask);
  }
}

- (IBAction)deploy:(id)sender {
  NSLog(@"Start maintenance...");
  [self shutdownRime];
  [self startRimeWithFullCheck:YES];
  [self loadSettings];
}

- (IBAction)syncUserData:(id)sender {
  NSLog(@"Sync user data");
  rime_get_api_stdbool()->sync_user_data();
}

- (IBAction)configure:(id)sender {
  NSURL* userDataDir = [NSFileManager.defaultManager.homeDirectoryForCurrentUser
                        URLByAppendingPathComponent:@"Library/Rime/" isDirectory:YES];
  [NSWorkspace.sharedWorkspace openURL:userDataDir];
}

- (IBAction)openWiki:(id)sender {
  [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:kRimeWikiURL]];
}

- (IBAction)openLogFolder:(id)sender {
  NSURL* infoLog = [NSFileManager.defaultManager.temporaryDirectory
                    URLByAppendingPathComponent:@"rime.squirrel.INFO" isDirectory:NO];
  [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[infoLog]];
}

extern void show_notification(const char* msg_text) {
  if (@available(macOS 10.14, *)) {
    UNUserNotificationCenter* center = UNUserNotificationCenter.currentNotificationCenter;
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionProvisional
                          completionHandler:^(BOOL granted, NSError* _Nullable error) {
      if (error != nil) {
        NSLog(@"User notification authorization error: %@", error.debugDescription);
      }
    }];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* _Nonnull settings) {
      if ((settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
           settings.authorizationStatus == UNAuthorizationStatusProvisional) &&
          (settings.alertSetting == UNNotificationSettingEnabled)) {
        UNMutableNotificationContent* content = UNMutableNotificationContent.alloc.init;
        content.title = NSLocalizedString(@"Squirrel", nil);
        content.subtitle = NSLocalizedString(@(msg_text), nil);
        if (@available(macOS 12.0, *)) {
          content.interruptionLevel = UNNotificationInterruptionLevelActive;
        }
        [center addNotificationRequest:[UNNotificationRequest
                                        requestWithIdentifier:@"SquirrelNotification"
                                        content:content
                                        trigger:nil]
                 withCompletionHandler:^(NSError* _Nullable error) {
          if (error != nil) {
            NSLog(@"User notification request error: %@", error.debugDescription);
          }
        }];
      }
    }];
  } else {
    NSUserNotification* notification = NSUserNotification.alloc.init;
    notification.title = NSLocalizedString(@"Squirrel", nil);
    notification.subtitle = NSLocalizedString(@(msg_text), nil);

    NSUserNotificationCenter* notificationCenter =
      NSUserNotificationCenter.defaultUserNotificationCenter;
    [notificationCenter removeAllDeliveredNotifications];
    [notificationCenter deliverNotification:notification];
  }
}

static void show_status(const char* msg_text_long,
                        const char* msg_text_short) {
  NSString* msgLong = msg_text_long != NULL ? @(msg_text_long) : nil;
  NSString* msgShort = msg_text_short != NULL ? @(msg_text_short) :
                       [msgLong substringWithRange:
                        [msgLong rangeOfComposedCharacterSequenceAtIndex:0]];
  [NSApp.squirrelAppDelegate.panel updateStatusLong:msgLong
                                        statusShort:msgShort];
}

static void notification_handler(void* context_object,
                                 RimeSessionId session_id,
                                 const char* message_type,
                                 const char* message_value) {
  if (strcmp(message_type, "deploy") == 0) {
    if (strcmp(message_value, "start") == 0) {
      show_notification("deploy_start");
    } else if (strcmp(message_value, "success") == 0) {
      show_notification("deploy_success");
    } else if (strcmp(message_value, "failure") == 0) {
      show_notification("deploy_failure");
    }
    return;
  }
  SquirrelApplicationDelegate* app_delegate = (__bridge id)context_object;
  // schema change
  if (strcmp(message_type, "schema") == 0 &&
      app_delegate.showNotifications != kShowNotificationsNever) {
    const char* schema_name = strchr(message_value, '/');
    if (schema_name != NULL) {
      ++schema_name;
      show_status(schema_name, schema_name);
    }
    return;
  }
  // option change
  if (strcmp(message_type, "option") == 0 && app_delegate) {
    bool state = message_value[0] != '!';
    const char* option_name = message_value + !state;
    BOOL updateScriptVariant = [app_delegate.panel.optionSwitcher
                                updateCurrentScriptVariant:@(message_value)];
    BOOL updateStyleOptions = NO;
    if ([app_delegate.panel.optionSwitcher updateGroupState:@(message_value)
                                                   ofOption:@(option_name)]) {
      updateStyleOptions = YES;
      NSString* schemaId = app_delegate.panel.optionSwitcher.schemaId;
      [app_delegate loadSchemaSpecificLabels:schemaId];
      [app_delegate loadSchemaSpecificSettings:schemaId
                               withRimeSession:session_id];
    }
    if (updateScriptVariant && !updateStyleOptions) {
      [app_delegate.panel updateScriptVariant];
    }
    if (app_delegate.showNotifications != kShowNotificationsNever) {
      RimeStringSlice state_label_long =
        rime_get_api_stdbool()->get_state_label_abbreviated(session_id, option_name, state, false);
      RimeStringSlice state_label_short =
        rime_get_api_stdbool()->get_state_label_abbreviated(session_id, option_name, state, true);
      if (state_label_long.str != NULL || state_label_short.str != NULL) {
        const char* short_message =
          state_label_short.length < strlen(state_label_short.str) ? NULL : state_label_short.str;
        show_status(state_label_long.str, short_message);
      }
    }
  }
}

- (void)setupRime {
  NSURL* userDataDir = [NSFileManager.defaultManager.homeDirectoryForCurrentUser
                        URLByAppendingPathComponent:@"Library/Rime/" isDirectory:YES];
  if (![userDataDir checkResourceIsReachableAndReturnError:nil]) {
    if (![NSFileManager.defaultManager
          createDirectoryAtURL:userDataDir
          withIntermediateDirectories:YES
          attributes:nil
          error:nil]) {
      NSLog(@"Error creating user data directory: %@", userDataDir);
    }
  }
  rime_get_api_stdbool()->set_notification_handler(notification_handler, (__bridge void*)self);
  RIME_STRUCT(RimeTraits, squirrel_traits);
  squirrel_traits.shared_data_dir = NSBundle.mainBundle.sharedSupportPath.fileSystemRepresentation;
  squirrel_traits.user_data_dir = userDataDir.fileSystemRepresentation;
  squirrel_traits.distribution_code_name = "Squirrel";
  squirrel_traits.distribution_name = "鼠鬚管";
  squirrel_traits.distribution_version =
    CFStringGetCStringPtr((CFStringRef)CFBundleGetValueForInfoDictionaryKey
    (CFBundleGetMainBundle(), kCFBundleVersionKey), kCFStringEncodingUTF8);
  squirrel_traits.app_name = "rime.squirrel";
  rime_get_api_stdbool()->setup(&squirrel_traits);
}

- (void)startRimeWithFullCheck:(bool)fullCheck {
  NSLog(@"Initializing la rime...");
  rime_get_api_stdbool()->initialize(NULL);
  // check for configuration updates
  if (rime_get_api_stdbool()->start_maintenance(fullCheck)) {
    // update squirrel config
    rime_get_api_stdbool()->deploy_config_file("squirrel.yaml", "config_version");
  }
}

- (void)shutdownRime {
  [_config close];
  _config = nil;
  rime_get_api_stdbool()->finalize();
}

- (void)loadSettings {
  _switcherKeyModifierMask = 0;
  _switcherKeyEquivalent = 0;
  SquirrelConfig* defaultConfig = SquirrelConfig.alloc.init;
  if ([defaultConfig openWithConfigId:@"default"]) {
    NSString* hotkey = [defaultConfig stringForOption:@"switcher/hotkeys/@0"];
    if (hotkey != nil) {
      NSArray<NSString*>* keys = [hotkey componentsSeparatedByString:@"+"];
      for (NSUInteger i = 0; i < keys.count - 1; ++i) {
        _switcherKeyModifierMask |= rime_modifiers_from_name(keys[i].UTF8String);
      }
      _switcherKeyEquivalent = rime_keycode_from_name(keys.lastObject.UTF8String);
    }
  }
  [defaultConfig close];

  _config = SquirrelConfig.alloc.init;
  if (!_config.openBaseConfig) {
    return;
  }
  NSString* showNotificationsWhen = [_config stringForOption:
                                     @"show_notifications_when"];
  if ([@"never" caseInsensitiveCompare:
       showNotificationsWhen] == NSOrderedSame) {
    _showNotifications = kShowNotificationsNever;
  } else if ([@"appropriate" caseInsensitiveCompare:
              showNotificationsWhen] == NSOrderedSame) {
    _showNotifications = kShowNotificationsWhenAppropriate;
  } else {
    _showNotifications = kShowNotificationsAlways;
  }
  [_panel loadConfig:_config];
}

- (void)loadSchemaSpecificSettings:(NSString*)schemaId
                   withRimeSession:(RimeSessionId)sessionId {
  if (schemaId.length == 0 || [schemaId hasPrefix:@"."]) {
    return;
  }
  // update the list of switchers that change styles and color-themes
  SquirrelConfig* schema = SquirrelConfig.alloc.init;
  if ([schema openWithSchemaId:schemaId baseConfig:_config]) {
    _panel.optionSwitcher = schema.getOptionSwitcher;
    [_panel.optionSwitcher updateWithRimeSession:sessionId];
    if ([schema hasSection:@"style"]) {
      [_panel loadConfig:schema];
    } else {
      [_panel loadConfig:_config];
    }
    [schema close];
  }
}

- (void)loadSchemaSpecificLabels:(NSString*)schemaId {
  SquirrelConfig* defaultConfig = SquirrelConfig.alloc.init;
  [defaultConfig openWithConfigId:@"default"];
  if (schemaId.length == 0 || [schemaId hasPrefix:@"."]) {
    [_panel loadLabelConfig:defaultConfig directUpdate:YES];
    [defaultConfig close];
    return;
  }
  SquirrelConfig* schema = SquirrelConfig.alloc.init;
  if ([schema openWithSchemaId:schemaId baseConfig:defaultConfig] &&
      [schema hasSection:@"menu"]) {
    [_panel loadLabelConfig:schema directUpdate:NO];
  } else {
    [_panel loadLabelConfig:defaultConfig directUpdate:NO];
  }
  [schema close];
  [defaultConfig close];
}

// prevent freezing the system
- (BOOL)problematicLaunchDetected {
  BOOL detected = NO;
  NSURL* logfile = [NSFileManager.defaultManager.temporaryDirectory
                    URLByAppendingPathComponent:@"squirrel_launch.dat"];
  NSLog(@"[DEBUG] archive: %@", logfile);
  NSData* archive = [NSData dataWithContentsOfURL:logfile
                                          options:NSDataReadingUncached
                                            error:nil];
  if (archive != nil) {
    NSDate* previousLaunch = [NSKeyedUnarchiver unarchivedObjectOfClass:NSDate.class
                                                               fromData:archive
                                                                  error:nil];
    if (previousLaunch.timeIntervalSinceNow >= -2) {
      detected = YES;
    }
  }
  NSData* record = [NSKeyedArchiver archivedDataWithRootObject:NSDate.date
                                         requiringSecureCoding:NO
                                                         error:nil];
  [record writeToURL:logfile atomically:NO];
  return detected;
}

- (void)workspaceWillPowerOff:(NSNotification*)notification {
  NSLog(@"Finalizing before logging out.");
  [self shutdownRime];
}

- (void)rimeNeedsReload:(NSNotification*)notification {
  NSLog(@"Reloading rime on demand.");
  [self deploy:nil];
}

- (void)rimeNeedsSync:(NSNotification*)notification {
  NSLog(@"Sync rime on demand.");
  [self syncUserData:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
  NSLog(@"Squirrel is quitting.");
  [_config close];
  rime_get_api_stdbool()->cleanup_all_sessions();
  return NSTerminateNow;
}

- (void)inputSourceChanged:(NSNotification*)notification {
  if (CFStringRef inputSource = (CFStringRef)TISGetInputSourceProperty
      (TISCopyCurrentKeyboardInputSource(), kTISPropertyInputSourceID)) {
    if (!CFStringHasPrefix(inputSource, kBundleId)) {
      _isCurrentInputMethod = NO;
    }
  }
}

//add an awakeFromNib item so that we can set the action method.  Note that
//any menuItems without an action will be disabled when displayed in the Text
//Input Menu.
- (void)awakeFromNib {
  NSNotificationCenter* center = NSWorkspace.sharedWorkspace.notificationCenter;
  [center addObserver:self
             selector:@selector(workspaceWillPowerOff:)
                 name:NSWorkspaceWillPowerOffNotification
               object:nil];

  NSDistributedNotificationCenter* notifCenter = NSDistributedNotificationCenter.defaultCenter;
  [notifCenter addObserver:self
                  selector:@selector(rimeNeedsReload:)
                      name:@"SquirrelReloadNotification"
                    object:nil];

  [notifCenter addObserver:self
                  selector:@selector(rimeNeedsSync:)
                      name:@"SquirrelSyncNotification"
                    object:nil];

  _isCurrentInputMethod = NO;
  [notifCenter addObserver:self
                  selector:@selector(inputSourceChanged:)
                      name:(id)kTISNotifySelectedKeyboardInputSourceChanged
                    object:nil
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
  [_panel hide];
}

@end  // SquirrelApplicationDelegate

@implementation NSApplication (SquirrelApp)

- (SquirrelApplicationDelegate*)squirrelAppDelegate {
  return (SquirrelApplicationDelegate*)self.delegate;
}

@end  // NSApplication (SquirrelApp)