#import <Cocoa/Cocoa.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

typedef struct {
  const char* name;
  bool state;
} NameState;

__attribute__((objc_direct_members))
@interface SquirrelOptionSwitcher : NSObject

@property(nonatomic, readonly, strong, nonnull) NSString* schemaId;
@property(nonatomic, readonly, strong, nonnull) NSString* currentScriptVariant;
@property(nonatomic, readonly, strong, nonnull) NSSet<NSString*>* optionNames;
@property(nonatomic, readonly, strong, nonnull) NSSet<NSString*>* optionStates;
@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSString*, NSString*>* scriptVariantOptions;
@property(nonatomic, readonly, strong, nonnull) NSMutableDictionary<NSString*, NSString*>* switcher;
@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSString*, NSOrderedSet<NSString*>*>* optionGroups;
@property(nonatomic, readonly, strong, nonnull) NSDictionary<NSString*, NSValue*>* optionAliases;

- (instancetype _Nonnull)initWithSchemaId:(NSString* _Nullable)schemaId
                                 switcher:(NSMutableDictionary<NSString*, NSString*>* _Nullable)switcher
                             optionGroups:(NSDictionary<NSString*, NSOrderedSet<NSString*>*>* _Nullable)optionGroups
                     defaultScriptVariant:(NSString* _Nullable)defaultScriptVariant
                     scriptVariantOptions:(NSDictionary<NSString*, NSString*>* _Nullable)scriptVariantOptions
                            optionAliases:(NSDictionary<NSString*, NSValue*>* _Nullable)optionAliases NS_DESIGNATED_INITIALIZER;
- (instancetype _Nonnull)initWithSchemaId:(NSString* _Nullable)schemaId;
// return whether switcher options has been successfully updated
- (BOOL)updateSwitcher:(NSMutableDictionary<NSString*, NSString*>* _Nonnull)switcher;
- (BOOL)updateGroupState:(NSString* _Nonnull)optionState
                ofOption:(NSString* _Nonnull)optionName;
- (BOOL)updateCurrentScriptVariant:(NSString* _Nonnull)scriptVariant;
- (void)update;

@end  // SquirrelOptionSwitcher


__attribute__((objc_direct_members))
@interface SquirrelAppOptions : NSDictionary<NSString*, NSNumber*>

- (bool)boolValueForOption:(NSString* _Nonnull)option;
- (int)intValueForOption:(NSString* _Nonnull)option;
- (double)doubleValueForOption:(NSString* _Nonnull)option;

@end  // SquirrelAppOptions


__attribute__((objc_direct_members))
@interface SquirrelConfig : NSObject

@property(nonatomic, strong, readonly, nullable) NSString* schemaId;
@property(nonatomic, strong, nonnull) NSString* colorSpace;

- (instancetype _Nonnull)initWithType:(NSString* _Nonnull)arg;
- (BOOL)openBaseConfig;
- (BOOL)openWithSchemaId:(NSString* _Nonnull)schemaId
              baseConfig:(SquirrelConfig* _Nullable)config;
- (BOOL)openUserConfig:(NSString* _Nonnull)configId;
- (BOOL)openWithConfigId:(NSString* _Nonnull)configId;
- (void)close;

- (BOOL)hasSection:(NSString* _Nonnull)section;

- (BOOL)setOption:(NSString* _Nonnull)option withBool:(bool)value;
- (BOOL)setOption:(NSString* _Nonnull)option withInt:(int)value;
- (BOOL)setOption:(NSString* _Nonnull)option withDouble:(double)value;
- (BOOL)setOption:(NSString* _Nonnull)option withString:(NSString* _Nonnull)value;

- (bool)boolValueForOption:(NSString* _Nonnull)option;
- (int)intValueForOption:(NSString* _Nonnull)option;
- (double)doubleValueForOption:(NSString* _Nonnull)option;
- (double)doubleValueForOption:(NSString* _Nonnull)option
                    constraint:(double(* _Nonnull)(double param))func;

- (NSNumber* _Nullable)nullableBoolForOption:(NSString* _Nonnull)option;
- (NSNumber* _Nullable)nullableIntForOption:(NSString* _Nonnull)option;
- (NSNumber* _Nullable)nullableDoubleForOption:(NSString* _Nonnull)option;
- (NSNumber* _Nullable)nullableDoubleForOption:(NSString* _Nonnull)option
                                    constraint:(double(* _Nonnull)(double param))func;

- (NSNumber* _Nullable)nullableBoolForOption:(NSString* _Nonnull)option
                                       alias:(NSString* _Nullable)alias;
- (NSNumber* _Nullable)nullableIntForOption:(NSString* _Nonnull)option
                                      alias:(NSString* _Nullable)alias;
- (NSNumber* _Nullable)nullableDoubleForOption:(NSString* _Nonnull)option
                                         alias:(NSString* _Nullable)alias;
- (NSNumber* _Nullable)nullableDoubleForOption:(NSString* _Nonnull)option
                                         alias:(NSString* _Nullable)alias
                                    constraint:(double(* _Nonnull)(double param))func;

- (NSString* _Nullable)stringForOption:(NSString* _Nonnull)option;
// 0xaabbggrr or 0xbbggrr
- (NSColor* _Nullable)colorForOption:(NSString* _Nonnull)option;
// file path (absolute or relative to ~/Library/Rime)
- (NSImage* _Nullable)imageForOption:(NSString* _Nonnull)option;

- (NSString* _Nullable)stringForOption:(NSString* _Nonnull)option
                                 alias:(NSString* _Nullable)alias;
- (NSColor* _Nullable)colorForOption:(NSString* _Nonnull)option
                               alias:(NSString* _Nullable)alias;
- (NSImage* _Nullable)imageForOption:(NSString* _Nonnull)option
                               alias:(NSString* _Nullable)alias;

- (NSUInteger)listSizeForOption:(NSString* _Nonnull)option;
- (NSArray<NSString*>* _Nullable)listForOption:(NSString* _Nonnull)option;

- (SquirrelOptionSwitcher* _Nonnull)optionSwitcherForSchema;
- (SquirrelAppOptions* _Nonnull)appOptionsForApp:(NSString* _Nonnull)bundleId;

@end  // SquirrelConfig


__attribute__((objc_direct_members))
@interface NSString (NSStringAppendString)

- (NSString* _Nonnull)append:(NSString* _Nonnull)string;
- (NSString* _Nonnull)keyPathByReplacingLastComponentWith:(NSString* _Nonnull)replacement;

@end

extern inline NSUInteger fmin(NSUInteger x, NSUInteger y) {
  return x < y ? x : y;
}
extern inline NSUInteger fmax(NSUInteger x, NSUInteger y) {
  return x < y ? y : x;
}
template <typename T> extern inline T clamp(T x, T min, T max) {
  const auto y = x < min ? min : x;
  return y > max ? max : y;
}

NS_HEADER_AUDIT_END(nullability, sendability)
