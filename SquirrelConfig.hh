#import <Cocoa/Cocoa.h>

typedef uintptr_t RimeSessionId;

__attribute__((objc_direct_members))
@interface SquirrelOptionSwitcher : NSObject

@property(nonatomic, readonly, strong, nonnull) NSString* schemaId;
@property(nonatomic, readonly, strong, nonnull) NSString* currentScriptVariant;
@property(nonatomic, readonly, strong, nonnull) NSSet<NSString*>* optionNames;
@property(nonatomic, readonly, strong, nonnull) NSSet<NSString*>* optionStates;
@property(nonatomic, readonly, strong, nonnull)
    NSDictionary<NSString*, NSString*>* scriptVariantOptions;
@property(nonatomic, readonly, strong, nonnull)
    NSMutableDictionary<NSString*, NSString*>* switcher;
@property(nonatomic, readonly, strong, nonnull)
    NSDictionary<NSString*, NSOrderedSet<NSString*>*>* optionGroups;

- (instancetype _Nonnull)
        initWithSchemaId:(NSString* _Nullable)schemaId
                switcher:(NSMutableDictionary<NSString*, NSString*>* _Nullable)
                             switcher
            optionGroups:
                (NSDictionary<NSString*, NSOrderedSet<NSString*>*>* _Nullable)
                    optionGroups
    defaultScriptVariant:(NSString* _Nullable)defaultScriptVariant
    scriptVariantOptions:
        (NSDictionary<NSString*, NSString*>* _Nullable)scriptVariantOptions
    NS_DESIGNATED_INITIALIZER;
- (instancetype _Nonnull)initWithSchemaId:(NSString* _Nullable)schemaId;
// return whether switcher options has been successfully updated
- (BOOL)updateSwitcher:
    (NSMutableDictionary<NSString*, NSString*>* _Nonnull)switcher;
- (BOOL)updateGroupState:(NSString* _Nonnull)optionState
                ofOption:(NSString* _Nonnull)optionName;
- (BOOL)updateCurrentScriptVariant:(NSString* _Nonnull)scriptVariant;
- (void)updateWithRimeSession:(RimeSessionId)session;

@end  // SquirrelOptionSwitcher

__attribute__((objc_direct_members))
@interface SquirrelAppOptions : NSDictionary<NSString*, NSNumber*>

- (bool)boolValueForKey:(NSString* _Nonnull)key;
- (int)intValueForKey:(NSString* _Nonnull)key;
- (double)doubleValueForKey:(NSString* _Nonnull)key;

@end  // SquirrelAppOptions

__attribute__((objc_direct_members))
@interface SquirrelConfig : NSObject

@property(nonatomic, strong, readonly, nullable) NSString* schemaId;
@property(nonatomic, strong, nonnull) NSString* colorSpace;

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
- (BOOL)setOption:(NSString* _Nonnull)option
       withString:(NSString* _Nonnull)value;

- (bool)boolValueForOption:(NSString* _Nonnull)option;
- (int)intValueForOption:(NSString* _Nonnull)option;
- (double)doubleForOption:(NSString* _Nonnull)option;
- (double)doubleForOption:(NSString* _Nonnull)option
               constraint:(double (*_Nonnull)(double param))func;

- (NSNumber* _Nullable)optionalBoolForOption:(NSString* _Nonnull)option;
- (NSNumber* _Nullable)optionalIntForOption:(NSString* _Nonnull)option;
- (NSNumber* _Nullable)optionalDoubleForOption:(NSString* _Nonnull)option;
- (NSNumber* _Nullable)optionalDoubleForOption:(NSString* _Nonnull)option
                                    constraint:
                                        (double (*_Nonnull)(double param))func;

- (NSNumber* _Nullable)optionalBoolForOption:(NSString* _Nonnull)option
                                       alias:(NSString* _Nullable)alias;
- (NSNumber* _Nullable)optionalIntForOption:(NSString* _Nonnull)option
                                      alias:(NSString* _Nullable)alias;
- (NSNumber* _Nullable)optionalDoubleForOption:(NSString* _Nonnull)option
                                         alias:(NSString* _Nullable)alias;
- (NSNumber* _Nullable)optionalDoubleForOption:(NSString* _Nonnull)option
                                         alias:(NSString* _Nullable)alias
                                    constraint:
                                        (double (*_Nonnull)(double param))func;

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

- (SquirrelOptionSwitcher* _Nonnull)getOptionSwitcher;
- (SquirrelAppOptions* _Nonnull)getAppOptions:(NSString* _Nonnull)appName;

@end  // SquirrelConfig

__attribute__((objc_direct_members))
@interface NSString (NSStringAppendString)

- (NSString* _Nonnull)append:(NSString* _Nonnull)string;

@end
