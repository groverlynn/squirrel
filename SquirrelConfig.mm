#import "SquirrelConfig.hh"

#import <rime_api_stdbool.h>
#import <rime_api.h>

static NSArray<NSString*>* const scripts = @[@"zh-Hans", @"zh-Hant", @"zh-TW", @"zh-HK",
                                             @"zh-MO", @"zh-SG", @"zh-CN", @"zh"];

@implementation SquirrelOptionSwitcher

- (instancetype)initWithSchemaId:(NSString*)schemaId
                        switcher:(NSMutableDictionary<NSString*, NSString*>*)switcher
                    optionGroups:(NSDictionary<NSString*, NSOrderedSet<NSString*>*>*)optionGroups
            defaultScriptVariant:(NSString*)defaultScriptVariant
            scriptVariantOptions:(NSDictionary<NSString*, NSString*>*)scriptVariantOptions {
  if (self = [super init]) {
    _schemaId = schemaId ? : @"";
    _switcher = switcher ? : NSMutableDictionary.dictionary;
    _optionGroups = optionGroups ? : NSDictionary.dictionary;
    _optionNames = [NSSet setWithArray:_switcher.allKeys];
    _optionStates = [NSSet setWithArray:_switcher.allValues];
    _currentScriptVariant = defaultScriptVariant ? : [NSBundle preferredLocalizationsFromArray:scripts][0];
    _scriptVariantOptions = scriptVariantOptions ? : NSDictionary.dictionary;
  }
  return self;
}

- (instancetype)initWithSchemaId:(NSString*)schemaId {
  return [self initWithSchemaId:schemaId
                       switcher:nil
                   optionGroups:nil
           defaultScriptVariant:nil
           scriptVariantOptions:nil];
}

- (instancetype)init {
  return [self initWithSchemaId:nil
                       switcher:nil
                   optionGroups:nil
           defaultScriptVariant:nil
           scriptVariantOptions:nil];
}

- (BOOL)updateSwitcher:(NSMutableDictionary<NSString*, NSString*>*)switcher {
  if (switcher.count != _switcher.count) {
    return NO;
  }
  NSSet<NSString*>* optNames = [NSSet setWithArray:switcher.allKeys];
  if ([optNames isEqualToSet:_optionNames]) {
    _switcher = switcher;
    _optionStates = [NSSet setWithArray:switcher.allValues];
    return YES;
  }
  return NO;
}

- (BOOL)updateGroupState:(NSString*)optionState
                ofOption:(NSString*)optionName {
  NSOrderedSet* optionGroup = _optionGroups[optionName];
  if (optionGroup == nil) {
    return NO;
  }
  if (optionGroup.count == 1) {
    if (![optionName isEqualToString:[optionState hasPrefix:@"!"] ?
          [optionState substringFromIndex:1] : optionState]) {
      return NO;
    }
    _switcher[optionName] = optionState;
  } else if ([optionGroup containsObject:optionState]) {
    for (NSString* option in optionGroup) {
      _switcher[option] = optionState;
    }
  }
  _optionStates = [NSSet setWithArray:_switcher.allValues];
  return YES;
}

- (BOOL)updateCurrentScriptVariant:(NSString*)scriptVariant {
  if (_scriptVariantOptions.count == 0) {
    return NO;
  }
  NSString* scriptVariantCode = _scriptVariantOptions[scriptVariant];
  if (scriptVariantCode == nil) {
    return NO;
  }
  _currentScriptVariant = scriptVariantCode;
  return YES;
}

- (void)updateWithRimeSession:(RimeSessionId)session {
  for (NSString* state in _optionStates) {
    NSString* updatedState;
    NSArray<NSString*>* optionGroup = [_switcher allKeysForObject:state];
    for (NSString* option in optionGroup) {
      if (rime_get_api_stdbool()->get_option(session, option.UTF8String)) {
        updatedState = option;
        break;
      }
    }
    updatedState = updatedState ? : [@"!" append:optionGroup[0]];
    if (![updatedState isEqualToString:state]) {
      [self updateGroupState:updatedState ofOption:state];
    }
  }
  // update script variant
  if (_scriptVariantOptions.count > 0) {
    for (NSString* option in _scriptVariantOptions) {
      if ([option hasPrefix:@"!"]
          ? !rime_get_api_stdbool()->get_option(session, [option substringFromIndex:1].UTF8String)
          : rime_get_api_stdbool()->get_option(session, option.UTF8String)) {
        [self updateCurrentScriptVariant:option];
        break;
      }
    }
  }
}

@end  // SquirrelOptionSwitcher


@implementation SquirrelAppOptions

- (bool)boolValueForKey:(NSString*)key {
  if (NSNumber* value = self[key];
      value != nil && strcmp(value.objCType, @encode(BOOL)) == 0) {
    return value.boolValue;
  }
  return NO;
}

- (int)intValueForKey:(NSString*)key {
  if (NSNumber* value = self[key];
      value != nil && strcmp(value.objCType, @encode(int)) == 0) {
    return value.intValue;
  }
  return 0;
}

- (double)doubleValueForKey:(NSString*)key {
  if (NSNumber* value = self[key];
      value != nil && strcmp(value.objCType, @encode(double)) == 0) {
    return value.doubleValue;
  }
  return 0.0;
}

@end  // SquirrelAppOptions


@implementation SquirrelConfig {
  NSCache<NSString*, id>* _cache;
  SquirrelConfig* _baseConfig;
  NSColorSpace* _colorSpace;
  NSString* _colorSpaceName;
  RimeConfig _config;
  BOOL _isOpen;
}

- (instancetype)init {
  if (self = [super init]) {
    _cache = NSCache.alloc.init;
    _colorSpace = NSColorSpace.sRGBColorSpace;
    _colorSpaceName = @"sRGB";
  }
  return self;
}

- (NSString*)colorSpace {
  return _colorSpaceName;
}

static NSDictionary<NSString*, NSColorSpace*>* const colorSpaceMap =
  @{@"deviceRGB"    : NSColorSpace.deviceRGBColorSpace,
    @"genericRGB"   : NSColorSpace.genericRGBColorSpace,
    @"sRGB"         : NSColorSpace.sRGBColorSpace,
    @"displayP3"    : NSColorSpace.displayP3ColorSpace,
    @"adobeRGB"     : NSColorSpace.adobeRGB1998ColorSpace,
    @"extendedSRGB" : NSColorSpace.extendedSRGBColorSpace};

- (void)setColorSpace:(NSString*)colorSpace {
  colorSpace = [colorSpace stringByReplacingOccurrencesOfString:@"_" withString:@""];
  if ([_colorSpaceName caseInsensitiveCompare:colorSpace] == NSOrderedSame) {
    return;
  }
  for (NSString* name in colorSpaceMap) {
    if ([name caseInsensitiveCompare:colorSpace] == NSOrderedSame) {
      _colorSpaceName = name;
      _colorSpace = colorSpaceMap[name];
      return;
    }
  }
}

- (BOOL)openBaseConfig {
  [self close];
  _isOpen = rime_get_api_stdbool()->config_open("squirrel", &_config);
  return _isOpen;
}

- (BOOL)openWithSchemaId:(NSString*)schemaId
              baseConfig:(SquirrelConfig*)baseConfig {
  [self close];
  _isOpen = rime_get_api_stdbool()->schema_open(schemaId.UTF8String, &_config);
  if (_isOpen) {
    _schemaId = schemaId;
    _baseConfig = baseConfig;
  }
  return _isOpen;
}

- (BOOL)openUserConfig:(NSString*)configId {
  [self close];
  _isOpen = rime_get_api_stdbool()->user_config_open(configId.UTF8String, &_config);
  return _isOpen;
}

- (BOOL)openWithConfigId:(NSString*)configId {
  [self close];
  _isOpen = rime_get_api_stdbool()->config_open(configId.UTF8String, &_config);
  return _isOpen;
}

- (void)close {
  if (_isOpen) {
    rime_get_api_stdbool()->config_close(&_config);
    _baseConfig = nil;
    _isOpen = NO;
  }
}

- (void)dealloc {
  [self close];
  [_cache removeAllObjects];
}

- (BOOL)hasSection:(NSString*)section {
  if (_isOpen) {
    RimeConfigIterator iterator;
    if (rime_get_api_stdbool()->config_begin_map(&iterator, &_config, section.UTF8String)) {
      rime_get_api_stdbool()->config_end(&iterator);
      return YES;
    }
  }
  return NO;
}

- (BOOL)setOption:(NSString*)option withBool:(bool)value {
  return rime_get_api_stdbool()->config_set_bool(&_config, option.UTF8String, value);
}

- (BOOL)setOption:(NSString*)option withInt:(int)value {
  return rime_get_api_stdbool()->config_set_int(&_config, option.UTF8String, value);
}

- (BOOL)setOption:(NSString*)option withDouble:(double)value {
  return rime_get_api_stdbool()->config_set_double(&_config, option.UTF8String, value);
}

- (BOOL)setOption:(NSString*)option withString:(NSString*)value {
  return rime_get_api_stdbool()->config_set_string(&_config, option.UTF8String, value.UTF8String);
}

- (bool)boolValueForOption:(NSString*)option {
  return [self optionalBoolForOption:option alias:nil].boolValue;
}

- (int)intValueForOption:(NSString*)option {
  return [self optionalIntForOption:option alias:nil].intValue;
}

- (double)doubleForOption:(NSString*)option {
  return [self optionalDoubleForOption:option alias:nil].doubleValue;
}

- (double)doubleForOption:(NSString*)option
             constraint:(double(*)(double param))func {
  return func([self optionalDoubleForOption:option alias:nil].doubleValue);
}

- (NSNumber*)optionalBoolForOption:(NSString*)option {
  return [self optionalBoolForOption:option alias:nil];
}

- (NSNumber*)optionalIntForOption:(NSString*)option {
  return [self optionalIntForOption:option alias:nil];
}

- (NSNumber*)optionalDoubleForOption:(NSString*)option {
  return [self optionalDoubleForOption:option alias:nil];
}

- (NSNumber*)optionalDoubleForOption:(NSString*)option
                        constraint:(double(*)(double param))func {
  NSNumber* value = [self optionalDoubleForOption:option alias:nil];
  return value ? [NSNumber numberWithDouble:func(value.doubleValue)] : nil;
}

- (NSNumber*)optionalBoolForOption:(NSString*)option
                                alias:(NSString*)alias {
  if (NSNumber* cachedValue = [self cachedValueOfObjCType:@encode(BOOL) forKey:option]) {
    return cachedValue;
  }
  if (bool value; _isOpen && rime_get_api_stdbool()->
      config_get_bool(&_config, option.UTF8String, &value)) {
    NSNumber* number = [NSNumber numberWithBool:value];
    [_cache setObject:number forKey:option];
    return number;
  }
  if (alias != nil) {
    NSString* aliasOption = [[option stringByDeletingLastPathComponent]
                             stringByAppendingPathComponent:alias.lastPathComponent];
    if (bool value; _isOpen && rime_get_api_stdbool()->
        config_get_bool(&_config, aliasOption.UTF8String, &value)) {
      NSNumber* number = [NSNumber numberWithBool:value];
      [_cache setObject:number forKey:option];
      return number;
    }
  }
  return [_baseConfig optionalBoolForOption:option alias:alias];
}

- (NSNumber*)optionalIntForOption:(NSString*)option
                               alias:(NSString*)alias {
  if (NSNumber* cachedValue = [self cachedValueOfObjCType:@encode(int) forKey:option]) {
    return cachedValue;
  }
  if (int value; _isOpen && rime_get_api_stdbool()->
      config_get_int(&_config, option.UTF8String, &value)) {
    NSNumber* number = [NSNumber numberWithInt:value];
    [_cache setObject:number forKey:option];
    return number;
  }
  if (alias != nil) {
    NSString* aliasOption = [[option stringByDeletingLastPathComponent]
                             stringByAppendingPathComponent:alias.lastPathComponent];
    if (int value; _isOpen && rime_get_api_stdbool()->
        config_get_int(&_config, aliasOption.UTF8String, &value)) {
      NSNumber* number = [NSNumber numberWithInt:value];
      [_cache setObject:number forKey:option];
      return number;
    }
  }
  return [_baseConfig optionalIntForOption:option alias:alias];
}

- (NSNumber*)optionalDoubleForOption:(NSString*)option
                                  alias:(NSString*)alias {
  if (NSNumber* cachedValue = [self cachedValueOfObjCType:@encode(double) forKey:option]) {
    return cachedValue;
  }
  if (double value; _isOpen && rime_get_api_stdbool()->
      config_get_double(&_config, option.UTF8String, &value)) {
    NSNumber* number = [NSNumber numberWithDouble:value];
    [_cache setObject:number forKey:option];
    return number;
  }
  if (alias != nil) {
    NSString* aliasOption = [[option stringByDeletingLastPathComponent]
                             stringByAppendingPathComponent:alias.lastPathComponent];
    if (double value; _isOpen && rime_get_api_stdbool()->
        config_get_double(&_config, aliasOption.UTF8String, &value)) {
      NSNumber* number = [NSNumber numberWithDouble:value];
      [_cache setObject:number forKey:option];
      return number;
    }
  }
  return [_baseConfig optionalDoubleForOption:option alias:alias];
}

- (NSNumber*)optionalDoubleForOption:(NSString*)option
                                  alias:(NSString*)alias
                        constraint:(double(*)(double param))func {
  NSNumber* value = [self optionalDoubleForOption:option alias:alias];
  return value ? [NSNumber numberWithDouble:func(value.doubleValue)] : nil;
}

- (NSString*)stringForOption:(NSString*)option {
  return [self stringForOption:option alias:nil];
}

- (NSColor*)colorForOption:(NSString*)option {
  return [self colorForOption:option alias:nil];
}

- (NSImage*)imageForOption:(NSString*)option {
  return [self imageForOption:option alias:nil];
}

- (NSString*)stringForOption:(NSString*)option
                          alias:(NSString*)alias {
  if (NSString* cachedValue = [self cachedValueOfClass:NSString.class forKey:option]) {
    return cachedValue;
  }
  const char* value = _isOpen ? rime_get_api_stdbool()->
    config_get_cstring(&_config, option.UTF8String) : NULL;
  if (value != NULL) {
    NSString* string = [@(value) stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceCharacterSet];
    [_cache setObject:string forKey:option];
    return string;
  }
  if (alias != nil) {
    NSString* aliasOption = [[option stringByDeletingLastPathComponent]
                             stringByAppendingPathComponent:alias.lastPathComponent];
    value = _isOpen ? rime_get_api_stdbool()->
      config_get_cstring(&_config, aliasOption.UTF8String) : NULL;
    if (value != NULL) {
      NSString* string = [@(value) stringByTrimmingCharactersInSet:
                          NSCharacterSet.whitespaceCharacterSet];
      [_cache setObject:string forKey:option];
      return string;
    }
  }
  return [_baseConfig stringForOption:option alias:alias];
}

- (NSColor*)colorForOption:(NSString*)option
                        alias:(NSString*)alias {
  if (NSColor* cachedValue = [self cachedValueOfClass:NSColor.class forKey:option]) {
    return cachedValue;
  }
  if (NSColor* color = [self colorFromString:[self stringForOption:option alias:alias]]) {
    [_cache setObject:color forKey:option];
    return color;
  }
  return [_baseConfig colorForOption:option alias:alias];
}

- (NSImage*)imageForOption:(NSString*)option
                        alias:(NSString*)alias {
  if (NSImage* cachedValue = [self cachedValueOfClass:NSImage.class forKey:option]) {
    return cachedValue;
  }
  if (NSImage* image = [self imageFromFile:[self stringForOption:option alias:alias]]) {
    [_cache setObject:image forKey:option];
    return image;
  }
  return [_baseConfig imageForOption:option alias:alias];
}

- (NSUInteger)listSizeForOption:(NSString*)option {
  return rime_get_api_stdbool()->config_list_size(&_config, option.UTF8String);
}

- (NSArray<NSString*>*)listForOption:(NSString*)option {
  RimeConfigIterator iterator;
  if (!rime_get_api_stdbool()->config_begin_list(&iterator, &_config, option.UTF8String)) {
    return nil;
  }
  NSMutableArray<NSString*>* strList = NSMutableArray.alloc.init;
  while (rime_get_api_stdbool()->config_next(&iterator))
    [strList addObject:[self stringForOption:@(iterator.path)]];
  rime_get_api_stdbool()->config_end(&iterator);
  return strList;
}

static NSDictionary<NSString*, NSString*>* const localeScript =
  @{@"simplification"  : @"zh-Hans",
    @"simplified"      : @"zh-Hans",
    @"!traditional"    : @"zh-Hans",
    @"traditional"     : @"zh-Hant",
    @"!simplification" : @"zh-Hant",
    @"!simplified"     : @"zh-Hant"};
static NSDictionary<NSString*, NSString*>* const localeRegion =
  @{@"tw"       : @"zh-TW", @"taiwan"   : @"zh-TW",
    @"hk"       : @"zh-HK", @"hongkong" : @"zh-HK",
    @"hong_kong": @"zh-HK", @"mo"       : @"zh-MO",
    @"macau"    : @"zh-MO", @"macao"    : @"zh-MO",
    @"sg"       : @"zh-SG", @"singapore": @"zh-SG",
    @"cn"       : @"zh-CN", @"china"    : @"zh-CN"};

static NSString* codeForScriptVariant(NSString* scriptVariant) {
  for (NSString* script in localeScript) {
    if ([script caseInsensitiveCompare:scriptVariant] == NSOrderedSame) {
      return localeScript[script];
    }
  }
  for (NSString* region in localeRegion) {
    if ([scriptVariant rangeOfString:region
                             options:NSCaseInsensitiveSearch].length > 0) {
      return localeRegion[region];
    }
  }
  return @"zh";
}

- (SquirrelOptionSwitcher*)getOptionSwitcher {
  RimeConfigIterator switchIter;
  if (!rime_get_api_stdbool()->config_begin_list(&switchIter, &_config, "switches")) {
    return [SquirrelOptionSwitcher.alloc initWithSchemaId:_schemaId];
  }
  NSMutableDictionary<NSString*, NSString*>* switcher = NSMutableDictionary.alloc.init;
  NSMutableDictionary<NSString*, NSOrderedSet<NSString*>*>* optionGroups = NSMutableDictionary.alloc.init;
  NSString* defaultScriptVariant = nil;
  NSMutableDictionary<NSString*, NSString*>* scriptVariantOptions = NSMutableDictionary.alloc.init;
  while (rime_get_api_stdbool()->config_next(&switchIter)) {
    int reset = [self intValueForOption:[@(switchIter.path) append:@"/reset"]];
    if (NSString* name = [self stringForOption:[@(switchIter.path) append:@"/name"]]) {
      if ([self hasSection:[@"style/!" append:name]] ||
          [self hasSection:[@"style/" append:name]]) {
        switcher[name] = reset ? name : [@"!" append:name];
        optionGroups[name] = [NSOrderedSet orderedSetWithObject:name];
      }
      if (defaultScriptVariant == nil &&
          ([name caseInsensitiveCompare:@"simplification"] == NSOrderedSame ||
           [name caseInsensitiveCompare:@"simplified"] == NSOrderedSame ||
           [name caseInsensitiveCompare:@"traditional"] == NSOrderedSame)) {
        defaultScriptVariant = reset ? name : [@"!" append:name];
        scriptVariantOptions[name] = codeForScriptVariant(name);
        scriptVariantOptions[[@"!" append:name]] =
          codeForScriptVariant([@"!" append:name]);
      }
    } else {
      RimeConfigIterator optionIter;
      if (!rime_get_api_stdbool()->config_begin_list(&optionIter, &_config,
          [@(switchIter.path) append:@"/options"].UTF8String)) {
        continue;
      }
      NSMutableOrderedSet<NSString*>* optGroup = NSMutableOrderedSet.alloc.init;
      BOOL hasStyleSection = NO;
      BOOL hasScriptVariant = defaultScriptVariant != nil;
      while (rime_get_api_stdbool()->config_next(&optionIter)) {
        NSString* option = [self stringForOption:@(optionIter.path)];
        [optGroup addObject:option];
        hasStyleSection |= [self hasSection:[@"style/" append:option]];
        hasScriptVariant |= [option caseInsensitiveCompare:@"simplification"] == NSOrderedSame ||
                            [option caseInsensitiveCompare:@"simplified"] == NSOrderedSame ||
                            [option caseInsensitiveCompare:@"traditional"] == NSOrderedSame;
      }
      rime_get_api_stdbool()->config_end(&optionIter);
      if (hasStyleSection) {
        for (NSUInteger i = 0; i < optGroup.count; ++i) {
          switcher[optGroup[i]] = optGroup[(NSUInteger)reset];
          optionGroups[optGroup[i]] = optGroup;
        }
      }
      if (defaultScriptVariant == nil && hasScriptVariant) {
        for (NSString* opt in optGroup) {
          scriptVariantOptions[opt] = codeForScriptVariant(opt);
        }
        defaultScriptVariant = scriptVariantOptions[optGroup[(NSUInteger)reset]];
      }
    }
  }
  rime_get_api_stdbool()->config_end(&switchIter);
  return [SquirrelOptionSwitcher.alloc initWithSchemaId:_schemaId
                                               switcher:switcher
                                           optionGroups:optionGroups
                                   defaultScriptVariant:defaultScriptVariant ? : @"zh"
                                   scriptVariantOptions:scriptVariantOptions];
}

- (SquirrelAppOptions*)getAppOptions:(NSString*)appName {
  NSString* rootKey = [@"app_options/" append:appName];
  NSMutableDictionary<NSString*, NSNumber*>* appOptions = NSMutableDictionary.alloc.init;
  RimeConfigIterator iterator;
  if (!rime_get_api_stdbool()->config_begin_map(&iterator, &_config, rootKey.UTF8String)) {
    return appOptions.copy;
  }
  while (rime_get_api_stdbool()->config_next(&iterator)) {
    // NSLog(@"DEBUG option[%d]: %s (%s)", iterator.index, iterator.key, iterator.path);
    if (NSNumber* value = [self optionalBoolForOption:@(iterator.path)] ? :
                          [self optionalIntForOption:@(iterator.path)] ? :
                          [self optionalDoubleForOption:@(iterator.path)]) {
      appOptions[@(iterator.key)] = value;
    }
  }
  rime_get_api_stdbool()->config_end(&iterator);
  return appOptions.copy;
}

#pragma mark - Private methods

- (id)cachedValueOfClass:(Class)aClass
                  forKey:(NSString*)key {
  if (id value = [_cache objectForKey:key];
      [value isMemberOfClass:aClass]) {
    return value;
  }
  return nil;
}

- (NSNumber*)cachedValueOfObjCType:(const char*)type
                            forKey:(NSString*)key {
  if (id value = [_cache objectForKey:key];
      [value isMemberOfClass:NSNumber.class] &&
      strcmp([value objCType], type) == 0) {
    return value;
  }
  return nil;
}

- (NSColor*)colorFromString:(NSString*)string {
  if (string == nil || (string.length != 8 && string.length != 10) ||
      (![string hasPrefix:@"0x"] && ![string hasPrefix:@"0X"])) {
    return nil;
  }
  NSScanner* hexScanner = [NSScanner scannerWithString:string];
  if (UInt hex = 0x0; [hexScanner scanHexInt:&hex] && hexScanner.atEnd) {
    UInt r = hex % 0x100;
    UInt g = hex / 0x100 % 0x100;
    UInt b = hex / 0x10000 % 0x100;
    // 0xaaBBGGRR or 0xBBGGRR
    UInt a = string.length == 10 ? hex / 0x1000000 : 0xFF;
    CGFloat components[4] = {r / 255.0, g / 255.0, b / 255.0, a / 255.0};
    return [NSColor colorWithColorSpace:_colorSpace
                             components:components count:4];
  }
  return nil;
}

- (NSImage*)imageFromFile:(NSString*)filePath {
  if (filePath == nil) {
    return nil;
  }
  NSURL* userDataDir = [NSURL fileURLWithPath:@"~/Library/Rime".stringByExpandingTildeInPath
                                  isDirectory:YES];
  NSURL* imageFile = [NSURL fileURLWithPath:filePath
                                isDirectory:NO
                              relativeToURL:userDataDir];
  if ([imageFile checkResourceIsReachableAndReturnError:nil]) {
    NSImage* image = [NSImage.alloc initByReferencingURL:imageFile];
    return image;
  }
  return nil;
}

@end  // SquirrelConfig


@implementation NSString (NSStringAppendString)

- (NSString*)append:(NSString*)string {
  return [self stringByAppendingString:string];
}

@end  // NSString (NSStringAppendString)