#import <Carbon/Carbon.h>

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

RimeInputMode GetEnabledInputModes(Boolean includeAllInstalled);

CFArrayRef GetPreferredLocale(void) {
  CFTypeRef locales[] = {CFSTR("zh-Hans"), CFSTR("zh-Hant"), CFSTR("zh-HK")};
  CFArrayRef localizations = CFArrayCreate(NULL, locales, 3, &kCFTypeArrayCallBacks);
  CFArrayRef preferred = CFBundleCopyLocalizationsForPreferences(localizations, NULL);
  CFRelease(localizations);
  return preferred;
}

CFArrayRef GetInputSourceList(Boolean includeAllInstalled) {
  CFTypeRef keys[] = {kTISPropertyBundleID};
  CFTypeRef values[] = {CFBundleGetIdentifier(CFBundleGetMainBundle())};
  CFDictionaryRef property = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFArrayRef sourceList = TISCreateInputSourceList(property, includeAllInstalled);
  CFRelease(property);
  return sourceList;
}

void RegisterInputSource(void) {
  if (GetEnabledInputModes(true) != 0) { // Already registered
    NSLog(@"Squirrel is already registered.");
    return;
  }
  CFStringRef installPath = CFSTR("/Library/Input Methods/Squirrel.app");
  if (CFURLRef installURL = CFURLCreateWithFileSystemPath(NULL, installPath, kCFURLPOSIXPathStyle, false)) {
    if (OSStatus error = TISRegisterInputSource((CFURLRef)CFAutorelease(installURL)) != noErr)
      NSLog(@"Squirrel failed to register at %@ (error code: %d)", installPath, error);
    else
      NSLog(@"Squirrel has been successfully registered at %@", installPath);
  }
}

void EnableInputSource(RimeInputMode modesToEnable) {
  if (GetEnabledInputModes(false) != 0) {
    // keep user's manually enabled input modes
    NSLog(@"Squirrel input method(s) is already enabled.");
    return;
  }
  if (modesToEnable == 0) {
    CFArrayRef preferred = GetPreferredLocale();
    if (CFArrayGetCount(preferred) > 0) {
      CFStringRef language = (CFStringRef)CFArrayGetValueAtIndex(preferred, 0);
      if (CFStringCompare(language, CFSTR("zh-Hans"), kCFCompareCaseInsensitive) == kCFCompareEqualTo)
        modesToEnable = HANS_INPUT_MODE;
      else if (CFStringCompare(language, CFSTR("zh-Hant"), kCFCompareCaseInsensitive) == kCFCompareEqualTo)
        modesToEnable = HANT_INPUT_MODE;
      else if (CFStringCompare(language, CFSTR("zh-HK"), kCFCompareCaseInsensitive) == kCFCompareEqualTo)
        modesToEnable = CANT_INPUT_MODE;
    } else {
      modesToEnable = HANS_INPUT_MODE;
    }
    CFRelease(preferred);
  }
  CFArrayRef sourceList = GetInputSourceList(true);
  for (CFIndex i = 0; i < CFArrayGetCount(sourceList); ++i) {
    TISInputSourceRef inputSource = (TISInputSourceRef)CFArrayGetValueAtIndex(sourceList, i);
    CFStringRef sourceID = (CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);
    // NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, 0) == kCFCompareEqualTo && (modesToEnable & HANS_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kHantInputModeID, 0) == kCFCompareEqualTo && (modesToEnable & HANT_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kCantInputModeID, 0) == kCFCompareEqualTo && (modesToEnable & CANT_INPUT_MODE))) {
      CFBooleanRef isEnabled = (CFBooleanRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsEnabled);
      if (!CFBooleanGetValue(isEnabled)) {
        if (OSStatus error = TISEnableInputSource(inputSource) != noErr)
          NSLog(@"Failed to enable input source: %@ (error code: %d)", sourceID, error);
        else
          NSLog(@"Enabled input source: %@", sourceID);
      }
    }
  }
  CFRelease(sourceList);
}

void SelectInputSource(RimeInputMode modeToSelect) {
  RimeInputMode enabledModes = GetEnabledInputModes(false);
  modeToSelect &= enabledModes;
  if (modeToSelect == 0) {
    CFArrayRef preferred = GetPreferredLocale();
    for (CFIndex i = 0; i < CFArrayGetCount(preferred); ++i) {
      CFStringRef language = (CFStringRef)CFArrayGetValueAtIndex(preferred, i);
      if (CFStringCompare(language, CFSTR("zh-Hans"), kCFCompareCaseInsensitive) == kCFCompareEqualTo &&
          (enabledModes & HANS_INPUT_MODE)) {
        modeToSelect = HANS_INPUT_MODE;
        break;
      } else if (CFStringCompare(language, CFSTR("zh-Hant"), kCFCompareCaseInsensitive) == kCFCompareEqualTo &&
                 (enabledModes & HANT_INPUT_MODE)) {
        modeToSelect = HANT_INPUT_MODE;
        break;
      } else if (CFStringCompare(language, CFSTR("zh-HK"), kCFCompareCaseInsensitive) == kCFCompareEqualTo &&
                 (enabledModes & CANT_INPUT_MODE)) {
        modeToSelect = CANT_INPUT_MODE;
        break;
      }
    }
    CFRelease(preferred);
  }
  if (modeToSelect == 0) {
    NSLog(@"No enabled input sources.");
    return;
  }
  CFArrayRef sourceList = GetInputSourceList(false);
  for (CFIndex i = 0; i < CFArrayGetCount(sourceList); ++i) {
    TISInputSourceRef inputSource = (TISInputSourceRef)CFArrayGetValueAtIndex(sourceList, i);
    CFStringRef sourceID = (CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);
    // NSLog(@"Examining input source: %@", sourceID);
    if ((CFStringCompare(sourceID, kHansInputModeID, 0) == kCFCompareEqualTo && (modeToSelect & HANS_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kHantInputModeID, 0) == kCFCompareEqualTo && (modeToSelect & HANT_INPUT_MODE)) ||
        (CFStringCompare(sourceID, kCantInputModeID, 0) == kCFCompareEqualTo && (modeToSelect & CANT_INPUT_MODE))) {
      // select the first enabled input mode in Squirrel.
      CFBooleanRef isSelectable = (CFBooleanRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsSelectCapable);
      CFBooleanRef isSelected = (CFBooleanRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsSelected);
      if (!CFBooleanGetValue(isSelected) && CFBooleanGetValue(isSelectable)) {
        if (OSStatus error = TISSelectInputSource(inputSource) != noErr) {
          NSLog(@"Failed to select input source: %@ (error code: %d)", sourceID, error);
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
  CFArrayRef sourceList = GetInputSourceList(false);
  for (CFIndex i = CFArrayGetCount(sourceList); i > 0; --i) {
    TISInputSourceRef inputSource = (TISInputSourceRef)CFArrayGetValueAtIndex(sourceList, i - 1);
    CFStringRef sourceID = (CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);
    // NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, 0) == kCFCompareEqualTo ||
        CFStringCompare(sourceID, kHantInputModeID, 0) == kCFCompareEqualTo ||
        CFStringCompare(sourceID, kCantInputModeID, 0) == kCFCompareEqualTo) {
      if (OSStatus error = TISDisableInputSource(inputSource) != noErr)
        NSLog(@"Failed to disable input source: %@ (error code: %d)", sourceID, error);
      else
        NSLog(@"Disabled input source: %@", sourceID);
    }
  }
  CFRelease(sourceList);
}

RimeInputMode GetEnabledInputModes(Boolean includeAllInstalled) {
  RimeInputMode input_modes = 0;
  CFArrayRef sourceList = GetInputSourceList(includeAllInstalled);
  for (CFIndex i = 0; i < CFArrayGetCount(sourceList); ++i) {
    TISInputSourceRef inputSource = (TISInputSourceRef)CFArrayGetValueAtIndex(sourceList, i);
    CFStringRef sourceID = (CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);
    // NSLog(@"Examining input source: %@", sourceID);
    if (CFStringCompare(sourceID, kHansInputModeID, 0) == kCFCompareEqualTo)
      input_modes |= HANS_INPUT_MODE;
    else if (CFStringCompare(sourceID, kHantInputModeID, 0) == kCFCompareEqualTo)
      input_modes |= HANT_INPUT_MODE;
    else if (CFStringCompare(sourceID, kCantInputModeID, 0) == kCFCompareEqualTo)
      input_modes |= CANT_INPUT_MODE;
  }
  CFRelease(sourceList);
  return input_modes;
}
