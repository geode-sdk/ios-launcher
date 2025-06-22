#import <Foundation/Foundation.h>

typedef void (^LCParseMachOCallback)(const char* path, struct mach_header_64* header, int fd, void* filePtr);

typedef NS_ENUM(NSInteger, Store) { SideStore, AltStore, Unknown };

NSString* LCParseMachO(const char* path, bool readOnly, LCParseMachOCallback callback);
void LCPatchAddRPath(const char* path, struct mach_header_64* header);
void LCPatchExecSlice(const char* path, struct mach_header_64* header);
void LCPatchLibrary(const char* path, struct mach_header_64* header);
void LCChangeExecUUID(struct mach_header_64* header);
bool checkCodeSignature(const char* path);
void refreshFile(NSString* execPath);

@interface PKZipArchiver : NSObject

- (NSData*)zippedDataForURL:(NSURL*)url;

@end

@interface LCUtils : NSObject

+ (void)validateJITLessSetup:(void (^)(BOOL success, NSError* error))completionHandler;
+ (NSURL*)archiveTweakedAltStoreWithError:(NSError**)error;
+ (NSData*)certificateData;
+ (NSString*)certificatePassword;

+ (BOOL)askForJIT;
+ (BOOL)launchToGuestApp;

+ (NSProgress*)signAppBundleWithZSign:(NSURL*)path completionHandler:(void (^)(BOOL success, NSError* error))completionHandler;
+ (BOOL)isAppGroupAltStoreLike;
+ (NSString*)getCertTeamIdWithKeyData:(NSData*)keyData password:(NSString*)password;
+ (int)validateCertificate:(void (^)(int status, NSDate* expirationDate, NSString* error))completionHandler;
+ (Store)store;
+ (NSString*)teamIdentifier;
+ (NSString*)appGroupID;
+ (NSString*)appUrlScheme;
+ (NSURL*)appGroupPath;
+ (NSString*)storeInstallURLScheme;

// ext
+ (NSUserDefaults*)appGroupUserDefault;
+ (NSString*)getStoreName;
+ (NSString*)getAppRunningLCScheme:(NSString*)bundleId;

+ (void)signFilesInFolder:(NSURL*)url onProgressCreated:(void (^)(NSProgress* progress))onProgressCreated completion:(void (^)(NSString* error))completion;
+ (void)signTweaks:(NSURL*)tweakFolderUrl force:(BOOL)force progressHandler:(void (^)(NSProgress* progress))progressHandler completion:(void (^)(NSError* error))completion;
+ (void)signMods:(NSURL*)geodeUrl force:(BOOL)force progressHandler:(void (^)(NSProgress* progress))progressHandler completion:(void (^)(NSError* error))completion;
@end
