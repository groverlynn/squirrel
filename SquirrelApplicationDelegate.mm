#import "SquirrelApplicationDelegate.hh"

#import "SquirrelConfig.hh"
#import "SquirrelPanel.hh"
#import "macos_keycode.hh"
#import <rime_api_stdbool.h>
#import <rime_api.h>
#import <UserNotifications/UserNotifications.h>

static NSString* const kRimeWikiURL = @"https://github.com/rime/home/wiki";
static NSString* const kNotifIdentifier = @"SquirrelNotification";
static NSURL* const kUserDataDir = [NSFileManager.defaultManager.homeDirectoryForCurrentUser
                                    URLByAppendingPathComponent:@"Library/Rime/" isDirectory:YES];
static const CFStringRef kBundleId = CFSTR("im.rime.inputmethod.Squirrel");

@implementation SquirrelApplicationDelegate {
  int _switcherKeyEquivalent;
  int _switcherKeyModifierMask;
}

- (IBAction)showSwitcher:(id)sender {
  NSLog(@"Show Switcher");
  if (_switcherKeyEquivalent != 0) {
    RimeSessionId session = [sender unsignedLongValue];
    rime_get_api_stdbool()->process_key(session, _switcherKeyEquivalent, _switcherKeyModifierMask);
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
  [NSWorkspace.sharedWorkspace openURL:kUserDataDir];
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
      if (error != nil)
        NSLog(@"User notification authorization error: %@", error.debugDescription);
    }];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* _Nonnull settings) {
      if ((settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
           settings.authorizationStatus == UNAuthorizationStatusProvisional) &&
          (settings.alertSetting == UNNotificationSettingEnabled)) {
        UNMutableNotificationContent* content = UNMutableNotificationContent.alloc.init;
        content.title = [NSBundle.mainBundle localizedStringForKey:@"Squirrel"
                                                             value:nil
                                                             table:@"Notifications"];
        content.subtitle = [NSBundle.mainBundle localizedStringForKey:@(msg_text)
                                                                value:nil
                                                                table:@"Notifications"];
        if (@available(macOS 12.0, *))
          content.interruptionLevel = UNNotificationInterruptionLevelActive;
        [center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:kNotifIdentifier
                                                                            content:content
                                                                            trigger:nil]
                 withCompletionHandler:^(NSError* _Nullable error) {
          if (error != nil)
            NSLog(@"User notification request error: %@", error.debugDescription);
        }];
      }
    }];
  } else {
    NSUserNotification* notification = NSUserNotification.alloc.init;
    notification.title = [NSBundle.mainBundle localizedStringForKey:@"Squirrel"
                                                              value:nil
                                                              table:@"Notifications"];
    notification.subtitle = [NSBundle.mainBundle localizedStringForKey:@(msg_text)
                                                                 value:nil
                                                                 table:@"Notifications"];
    NSUserNotificationCenter* notificationCenter = NSUserNotificationCenter.defaultUserNotificationCenter;
    [notificationCenter removeAllDeliveredNotifications];
    [notificationCenter deliverNotification:notification];
  }
}

static void notification_handler(void* context_object,
                                 RimeSessionId session_id,
                                 const char* message_type,
                                 const char* message_value) {
  if (strcmp(message_type, "deploy") == 0) {
    if (strcmp(message_value, "start") == 0)
      show_notification("deploy_start");
    else if (strcmp(message_value, "success") == 0)
      show_notification("deploy_success");
    else if (strcmp(message_value, "failure") == 0)
      show_notification("deploy_failure");
    return;
  }
  // schema change
  if (strcmp(message_type, "schema") == 0) {
    if (SquirrelApplicationDelegate* app_delegate = (__bridge id)context_object;
        app_delegate.showNotifications != kShowNotificationsNever) {
      const char* schema_name = strchr(message_value, '/');
      if (schema_name != NULL) {
        ++schema_name;
        [app_delegate.panel updateStatusLong:@(schema_name) statusShort:@(schema_name)];
      }
    }
    return;
  }
  // option change
  if (strcmp(message_type, "option") == 0) {
    if (SquirrelApplicationDelegate* app_delegate = (__bridge id)context_object;
        app_delegate.showNotifications != kShowNotificationsNever) {
      NSString* option_state = @(message_value);
      NSValue* option_alias = app_delegate.panel.optionSwitcher.optionAliases[option_state];
      if (option_alias != nil) {
        NameState name_state;
        [option_alias getValue:&name_state];
        BOOL updateScriptVariant = [app_delegate.panel.optionSwitcher updateCurrentScriptVariant:option_state];
        BOOL updateStyleOptions = NO;
        if ([app_delegate.panel.optionSwitcher updateGroupState:option_state
                                                       ofOption:@(name_state.name)]) {
          updateStyleOptions = YES;
          NSString* schemaId = app_delegate.panel.optionSwitcher.schemaId;
          [app_delegate loadSchemaSpecificLabels:schemaId];
          [app_delegate loadSchemaSpecificSettings:schemaId];
        }
        if (updateScriptVariant && !updateStyleOptions)
          [app_delegate.panel updateScriptVariant];
        if (app_delegate.showNotifications != kShowNotificationsNever) {
          RimeStringSlice long_label = rime_get_api_stdbool()->get_state_label_abbreviated(session_id, name_state.name, name_state.state, false);
          RimeStringSlice short_label = rime_get_api_stdbool()->get_state_label_abbreviated(session_id, name_state.name, name_state.state, true);
          if (long_label.str != NULL || short_label.str != NULL) {
            NSString* long_message = long_label.str == NULL ? nil : @(long_label.str);
            NSString* short_message = short_label.str == NULL || short_label.length < strlen(short_label.str) ? nil : @(short_label.str);
            [app_delegate.panel updateStatusLong:long_message statusShort:short_message];
          }
        }
      }
    }
  }
}

- (void)setupRime {
  if (![kUserDataDir checkResourceIsReachableAndReturnError:nil]) {
    if (![NSFileManager.defaultManager createDirectoryAtURL:kUserDataDir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil])
      NSLog(@"Error creating user data directory: %@", kUserDataDir);
  }
  rime_get_api_stdbool()->set_notification_handler(notification_handler, (__bridge void*)self);
  RIME_STRUCT(RimeTraits, squirrel_traits);
  squirrel_traits.shared_data_dir = NSBundle.mainBundle.sharedSupportPath.fileSystemRepresentation;
  squirrel_traits.user_data_dir = kUserDataDir.fileSystemRepresentation;
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
  if (rime_get_api_stdbool()->start_maintenance(fullCheck))
    rime_get_api_stdbool()->deploy_config_file("squirrel.yaml", "config_version");
}

- (void)shutdownRime {
  rime_get_api_stdbool()->finalize();
}

- (void)loadSettings {
  _switcherKeyModifierMask = 0;
  _switcherKeyEquivalent = 0;
  SquirrelConfig* defaultConfig = SquirrelConfig.alloc.init;
  if ([defaultConfig openWithConfigId:@"default"]) {
    SquirrelInputController.goodOldCapsLock = [defaultConfig boolValueForOption:@"ascii_composer/good_old_caps_lock"];
    NSString* hotkey = [defaultConfig stringForOption:@"switcher/hotkeys/@0"];
    if (hotkey != nil) {
      NSArray<NSString*>* keys = [hotkey componentsSeparatedByString:@"+"];
      for (NSUInteger i = 0; i < keys.count - 1; ++i)
        _switcherKeyModifierMask |= RimeModifiers(keys[i].UTF8String);
      _switcherKeyEquivalent = RimeKeycode(keys.lastObject.UTF8String);
    }
  }
  [defaultConfig close];

  SquirrelConfig* config = SquirrelConfig.alloc.init;
  if (!config.openBaseConfig)
    return;
  NSString* showNotificationsWhen = [config stringForOption:@"show_notifications_when"];
  if ([@"never" caseInsensitiveCompare:showNotificationsWhen] == NSOrderedSame)
    _showNotifications = kShowNotificationsNever;
  else if ([@"always" caseInsensitiveCompare:showNotificationsWhen] == NSOrderedSame)
    _showNotifications = kShowNotificationsAlways;
  else
    _showNotifications = kShowNotificationsWhenAppropriate;
  SquirrelInputController.keyboardLayout = [config stringForOption:@"keyboard_layout"];
  CGFloat chordDuration = [[config nullableDoubleForOption:@"chord_duration"] doubleValue];
  SquirrelInputController.chordDuration = isnormal(chordDuration) ? chordDuration : 0.1;
  _panel.optionSwitcher = SquirrelOptionSwitcher.alloc.init;
  [_panel loadConfig:config];
  [config close];
}

- (void)loadSchemaSpecificSettings:(NSString*)schemaId {
  if (schemaId.length == 0 || [schemaId hasPrefix:@"."])
    return;
  // update the list of switchers that change styles and color-themes
  SquirrelConfig* baseConfig = [SquirrelConfig.alloc initWithType:@".base"];
  SquirrelConfig* schema = SquirrelConfig.alloc.init;
  if ([schema openWithSchemaId:schemaId baseConfig:baseConfig]) {
    _panel.optionSwitcher = schema.optionSwitcherForSchema;
    [_panel.optionSwitcher update];
    if ([schema hasSection:@"style"])
      [_panel loadConfig:schema];
    else
      [_panel loadConfig:baseConfig];
    [schema close];
    [baseConfig close];
  }
}

- (void)loadSchemaSpecificLabels:(NSString*)schemaId {
  SquirrelConfig* defaultConfig = [SquirrelConfig.alloc initWithType:@".default"];
  if (schemaId.length == 0 || [schemaId hasPrefix:@"."]) {
    [_panel loadLabelConfig:defaultConfig directUpdate:YES];
  } else {
    SquirrelConfig* schema = SquirrelConfig.alloc.init;
    if ([schema openWithSchemaId:schemaId baseConfig:defaultConfig] &&
        [schema hasSection:@"menu"])
      [_panel loadLabelConfig:schema directUpdate:NO];
    else
      [_panel loadLabelConfig:defaultConfig directUpdate:NO];
    [schema close];
  }
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
    if (previousLaunch.timeIntervalSinceNow >= -2)
      detected = YES;
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

- (void)rimeWillReload:(NSNotification*)notification {
  NSLog(@"Reloading rime on demand.");
  [self deploy:nil];
}

- (void)rimeWillSync:(NSNotification*)notification {
  NSLog(@"Sync rime on demand.");
  [self syncUserData:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
  NSLog(@"Squirrel is quitting.");
  rime_get_api_stdbool()->cleanup_all_sessions();
  return NSTerminateNow;
}

- (void)inputSourceDidChange:(NSNotification*)notification {
  if (CFStringRef inputSource = (CFStringRef)TISGetInputSourceProperty(TISCopyCurrentKeyboardInputSource(),
                                                                       kTISPropertyInputSourceID)) {
    if (!CFStringHasPrefix(inputSource, kBundleId))
      _isCurrentInputMethod = NO;
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
                  selector:@selector(rimeWillReload:)
                      name:kWillReloadNotification
                    object:nil];

  [notifCenter addObserver:self
                  selector:@selector(rimeWillSync:)
                      name:kWillSyncNotification
                    object:nil];

  _isCurrentInputMethod = NO;
  [notifCenter addObserver:self
                  selector:@selector(inputSourceDidChange:)
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

- (SquirrelApplicationDelegate*)SquirrelAppDelegate {
  return (SquirrelApplicationDelegate*)self.delegate;
}

@end  // NSApplication (SquirrelApp)
