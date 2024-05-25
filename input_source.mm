#import <Carbon/Carbon.h>

static const char kInstallPath[] =
  "/Library/Input Methods/Squirrel.app";

static const CFStringRef kHansInputModeID =
  CFSTR("im.rime.inputmethod.Squirrel.Hans");
static const CFStringRef kHantInputModeID =
  CFSTR("im.rime.inputmethod.Squirrel.Hant");
static const CFStringRef kCantInputModeID =
  CFSTR("im.rime.inputmethod.Squirrel.Cant");

typedef CF_OPTIONS(CFIndex, RimeInputMode) {
  DEFAULT_INPUT_MODE = 1 << 0,
  HANS_INPUT_MODE = 1 << 0,
  HANT_INPUT_MODE = 1 << 1,
  CANT_INPUT_MODE = 1 << 2
};

RimeInputMode GetEnabledInputModes(void);

void RegisterInputSource(void) {
  if (GetEnabledInputModes() != 0) { // Already registered
    return;
  }
  CFURLRef installPathURL = CFURLCreateFromFileSystemRepresentation
    (NULL, (UInt8*)kInstallPath, (CFIndex)strlen(kInstallPath), false);
  if (installPathURL != NULL) {
    TISRegisterInputSource((CFURLRef)CFAutorelease(installPathURL));
    NSLog(@"Registered input source from %s", kInstallPath);
  }
}

void EnableInputSource(void) {
  if (GetEnabledInputModes() != 0) {
    // keep user's manually enabled input modes
    return;
  }
  RimeInputMode input_modes_to_enable = 0;
  CFArrayRef localizations = CFArrayCreate
      (NULL, (CFTypeRef[]){CFSTR("zh-Hans"), CFSTR("zh-Hant"), CFSTR("zh-HK")},
       3, &kCFTypeArrayCallBacks);
  CFArrayRef preferred = CFBundleCopyLocalizationsForPreferences
    ((CFArrayRef)CFAutorelease(localizations), NULL);
  if (CFArrayGetCount(preferred) > 0) {
    CFStringRef language = (CFStringRef)CFArrayGetValueAtIndex(preferred, 0);
    if (CFStringCompare(language, CFSTR("zh-Hans"),
                        kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
      input_modes_to_enable |= HANS_INPUT_MODE;
    } else if (CFStringCompare(language, CFSTR("zh-Hant"),
                               kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
      input_modes_to_enable |= HANT_INPUT_MODE;
    } else if (CFStringCompare(language, CFSTR("zh-HK"),
                               kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
      input_modes_to_enable |= CANT_INPUT_MODE;
    }
  } else {
    input_modes_to_enable = HANS_INPUT_MODE;
  }
  CFRelease(preferred);
  CFDictionaryRef property = CFDictionaryCreate
    (NULL, (CFTypeRef[]){kTISPropertyBundleID},
     (CFTypeRef[]){CFBundleGetIdentifier(CFBundleGetMainBundle())},
     1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFArrayRef sourceList = TISCreateInputSourceList
    ((CFDictionaryRef)CFAutorelease(property), true);
  for (CFIndex i = 0; i < CFArrayGetCount(sourceList); ++i) {
    TISInputSourceRef inputSource = (TISInputSourceRef)
      CFArrayGetValueAtIndex(sourceList, i);
    CFStringRef sourceID = (CFStringRef)TISGetInputSourceProperty
      (inputSource, kTISPropertyInputSourceID);
    // NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, 0) == kCFCompareEqualTo &&
         (input_modes_to_enable & HANS_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kHantInputModeID, 0) == kCFCompareEqualTo &&
         (input_modes_to_enable & HANT_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kCantInputModeID, 0) == kCFCompareEqualTo &&
         (input_modes_to_enable & CANT_INPUT_MODE))) {
      CFBooleanRef isEnabled = (CFBooleanRef)TISGetInputSourceProperty
        (inputSource, kTISPropertyInputSourceIsEnabled);
      if (!CFBooleanGetValue(isEnabled)) {
        if (OSStatus enableError = TISEnableInputSource(inputSource) != 0) {
          NSLog(@"Failed to enable input source: %@ (%@)", sourceID,
                [NSError errorWithDomain:NSOSStatusErrorDomain
                                    code:enableError userInfo:nil]);
        } else {
          NSLog(@"Enabled input source: %@", sourceID);
        }
      }
    }
  }
  CFRelease(sourceList);
}

void SelectInputSource(void) {
  RimeInputMode enabled_input_modes = GetEnabledInputModes();
  RimeInputMode input_mode_to_select = 0;
  CFArrayRef localizations = CFArrayCreate
      (NULL, (CFTypeRef[]){CFSTR("zh-Hans"), CFSTR("zh-Hant"), CFSTR("zh-HK")},
       3, &kCFTypeArrayCallBacks);
  CFArrayRef preferred = CFBundleCopyLocalizationsForPreferences
                          ((CFArrayRef)CFAutorelease(localizations), NULL);
  for (CFIndex i = 0; i < CFArrayGetCount(preferred); ++i) {
    CFStringRef language = (CFStringRef)CFArrayGetValueAtIndex(preferred, i);
    if (CFStringCompare(language, CFSTR("zh-Hans"), kCFCompareCaseInsensitive)
        == kCFCompareEqualTo && (enabled_input_modes & HANS_INPUT_MODE)) {
      input_mode_to_select = HANS_INPUT_MODE;
      break;
    } else if (CFStringCompare(language, CFSTR("zh-Hant"), kCFCompareCaseInsensitive)
               == kCFCompareEqualTo && (enabled_input_modes & HANT_INPUT_MODE)) {
      input_mode_to_select = HANT_INPUT_MODE;
      break;
    } else if (CFStringCompare(language, CFSTR("zh-HK"), kCFCompareCaseInsensitive)
               == kCFCompareEqualTo && (enabled_input_modes & CANT_INPUT_MODE)) {
      input_mode_to_select = CANT_INPUT_MODE;
      break;
    }
  }
  CFRelease(preferred);
  if (input_mode_to_select == 0) {
    NSLog(@"No enabled input sources.");
    return;
  }
  CFDictionaryRef property = CFDictionaryCreate
    (NULL, (CFTypeRef[]){kTISPropertyBundleID},
     (CFTypeRef[]){CFBundleGetIdentifier(CFBundleGetMainBundle())},
     1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFArrayRef sourceList = TISCreateInputSourceList
    ((CFDictionaryRef)CFAutorelease(property), false);
  for (CFIndex i = 0; i < CFArrayGetCount(sourceList); ++i) {
    TISInputSourceRef inputSource = (TISInputSourceRef)
      CFArrayGetValueAtIndex(sourceList, i);
    CFStringRef sourceID = (CFStringRef)TISGetInputSourceProperty(
        inputSource, kTISPropertyInputSourceID);
    // NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, 0) == kCFCompareEqualTo &&
         ((input_mode_to_select & HANS_INPUT_MODE) != 0)) ||
        (CFStringCompare(sourceID, kHantInputModeID, 0) == kCFCompareEqualTo &&
         ((input_mode_to_select & HANT_INPUT_MODE) != 0)) ||
        (CFStringCompare(sourceID, kCantInputModeID, 0) == kCFCompareEqualTo &&
         ((input_mode_to_select & CANT_INPUT_MODE) != 0))) {
      // select the first enabled input mode in Squirrel.
      CFBooleanRef isSelectable = (CFBooleanRef)TISGetInputSourceProperty(
          inputSource, kTISPropertyInputSourceIsSelectCapable);
      CFBooleanRef isSelected = (CFBooleanRef)TISGetInputSourceProperty(
          inputSource, kTISPropertyInputSourceIsSelected);
      if (!CFBooleanGetValue(isSelected) && CFBooleanGetValue(isSelectable)) {
        if (OSStatus selectError = TISSelectInputSource(inputSource) != 0) {
          NSLog(@"Failed to select input source: %@ (%@)", sourceID,
                [NSError errorWithDomain:NSOSStatusErrorDomain
                                    code:selectError userInfo:nil]);
        } else {
          NSLog(@"Selected input source: %@", sourceID);
          break;
        }
      }
    }
  }
  CFRelease(sourceList);
}

void DisableInputSource(void) {
  CFDictionaryRef property = CFDictionaryCreate
    (NULL, (CFTypeRef[]){kTISPropertyBundleID},
     (CFTypeRef[]){CFBundleGetIdentifier(CFBundleGetMainBundle())},
     1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFArrayRef sourceList = TISCreateInputSourceList
    ((CFDictionaryRef)CFAutorelease(property), false);
  for (CFIndex i = CFArrayGetCount(sourceList); i > 0; --i) {
    TISInputSourceRef inputSource = (TISInputSourceRef)
      CFArrayGetValueAtIndex(sourceList, i - 1);
    CFStringRef sourceID = (CFStringRef)TISGetInputSourceProperty
      (inputSource, kTISPropertyInputSourceID);
    // NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, 0) == kCFCompareEqualTo ||
        CFStringCompare(sourceID, kHantInputModeID, 0) == kCFCompareEqualTo ||
        CFStringCompare(sourceID, kCantInputModeID, 0) == kCFCompareEqualTo) {
      if (OSStatus disableError = TISDisableInputSource(inputSource) != 0) {
        NSLog(@"Failed to disable input source: %@ (%@)", sourceID,
              [NSError errorWithDomain:NSOSStatusErrorDomain
                                  code:disableError userInfo:nil]);
      } else {
        NSLog(@"Disabled input source: %@", sourceID);
      }
    }
  }
  CFRelease(sourceList);
}

RimeInputMode GetEnabledInputModes(void) {
  RimeInputMode input_modes = 0;
  CFDictionaryRef property = CFDictionaryCreate
    (NULL, (CFTypeRef[]){kTISPropertyBundleID},
     (CFTypeRef[]){CFBundleGetIdentifier(CFBundleGetMainBundle())},
     1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFArrayRef sourceList = TISCreateInputSourceList
    ((CFDictionaryRef)CFAutorelease(property), false);
  for (CFIndex i = 0; i < CFArrayGetCount(sourceList); ++i) {
    TISInputSourceRef inputSource = (TISInputSourceRef)
      CFArrayGetValueAtIndex(sourceList, i);
    CFStringRef sourceID = (CFStringRef)TISGetInputSourceProperty
      (inputSource, kTISPropertyInputSourceID);
    // NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, 0) == kCFCompareEqualTo) {
      input_modes |= HANS_INPUT_MODE;
    } else if (CFStringCompare(sourceID, kHantInputModeID, 0) == kCFCompareEqualTo) {
      input_modes |= HANT_INPUT_MODE;
    } else if (CFStringCompare(sourceID, kCantInputModeID, 0) == kCFCompareEqualTo) {
      input_modes |= CANT_INPUT_MODE;
    }
  }
  CFRelease(sourceList);
  return input_modes;
}
