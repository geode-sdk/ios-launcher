#import <Foundation/Foundation.h>
#include <filesystem>
#import "Patcher.h"
#import "LCUtils/unarchive.h"
#import "Utils.h"
#import "components/LogUtils.h"
#import "src/LCUtils/Shared.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>


#include <dlfcn.h>
// change to 0x1692, and max is 0x7fff
#define TEXT_OFFSET 0x8050
// #define TEXT_OFFSET 0x8a8000
#define TEXT_MAX 0x10000
// used to be 0x4000

#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

static uint32_t findImageIndex(const char* dylibName) {
	uint32_t count = _dyld_image_count();
	for (uint32_t i = 0; i < count; ++i) {
		const char* name = _dyld_get_image_name(i);
		if (strstr(name, dylibName))
			return i;
	}
	return UINT32_MAX;
}

// sorry but dlsym is NOT working and its giving me a headache, so lets just go through all symbols
void* findSymbolAddr(const char* targetMangledName) {
	uint32_t idx = findImageIndex("libTulipHook.dylib");
	if (idx == UINT32_MAX) {
		AppLog(@"Failed to load TulipHook: couldn't find image index");
		return nullptr;
	}

	const struct mach_header_64* header = (struct mach_header_64*)_dyld_get_image_header(idx);
	intptr_t slide = _dyld_get_image_vmaddr_slide(idx);

	struct symtab_command* symtabCmd = nullptr;
	struct load_command* cmd = (struct load_command*)(header + 1);
	for (uint32_t i = 0; i < header->ncmds; ++i) {
		if (cmd->cmd == LC_SYMTAB) {
			symtabCmd = (struct symtab_command*)cmd;
			break;
		}
		cmd = (struct load_command*)((uint8_t*)cmd + cmd->cmdsize);
	}
	if (!symtabCmd) {
		AppLog(@"Failed to load TulipHook: no symbol table");
		return nullptr;
	}

	auto base = (uint8_t*)header;
	auto symTable = (struct nlist_64*)(base + symtabCmd->symoff);
	auto strTable = (char*)(base + symtabCmd->stroff);

	for (uint32_t i = 0; i < symtabCmd->nsyms; ++i) {
		uint32_t strx = symTable[i].n_un.n_strx;
		if (strx == 0)
			continue;
		const char* name = strTable + strx;
		if ((symTable[i].n_type & N_STAB) == 0 && (symTable[i].n_type & N_TYPE) == N_SECT) {
			if (strcmp(name, targetMangledName) == 0) {
				uintptr_t addr = symTable[i].n_value + slide;
				// AppLog(@"found symbol %s @ %p", name, (void*)addr);
				AppLog(@"Loaded TulipHook (ID: %lu, func: %p)", (unsigned long)idx, (void*)addr);
				return (void*)addr;
			}
		}
	}
	AppLog(@"Failed to load TulipHook: Symbol not found");
	return nullptr;
}

#include "include/TulipHook.hpp"
using namespace tulip;

generateTrampolineTemp generateTrampoline;
generateHandlerTemp generateHandler;

getRelocatedBytesDef getRelocatedBytes;
getCommonHandlerBytesDef getCommonHandlerBytes;
getCommonIntervenerBytesDef getCommonIntervenerBytes;

static size_t CAVE_OFFSET = 0x0;
static size_t codeCaveOffset = 0x0;

// from the article (converted from python to objc)
static uint64_t align(uint64_t size, uint64_t align) {
	uint64_t rem = size % align;
	return rem ? (size + (align - rem)) : size;
}

// credits:
// https://lief.re/doc/latest/tutorials/11_macho_modification.html (diagram)
// https://alexdremov.me/mystery-of-mach-o-object-file-builders/ (for structs)
// https://alexomara.com/blog/adding-a-segment-to-an-existing-macos-mach-o-binary/ (mainly this, thanks to the python script!)
// this function creates a new segment and section (rx), and it's main purpose is to allow for an rx area for our code cave, since ios doesnt like us touching the __TEXT seg
// originally i wanted to extend __text or create a section in __TEXT, but found that headache inducing so i just decided to make a new segment instead, plus its better because i dont have to shift EVERYTHING after that section, load command tables were stupid to handle
BOOL appendNewSection(NSMutableData* data, uint32_t sect_size) {
	NSUInteger origSize = data.length;
	const char* segNameC = "__CUSTOM";
	const char* sectNameC = "__custom";
	uint64_t sectSize = TEXT_MAX;

	uint8_t* buf = (uint8_t*)data.mutableBytes;
	struct mach_header_64* header = (struct mach_header_64*)buf;

	uint8_t* lcPtr = buf + sizeof(*header);
	uint32_t ncmds = header->ncmds;
	
	struct segment_command_64* linkSeg = NULL;
	uint32_t linkIndex = 0;
	uint64_t linkFileOff = 0;
	uint8_t* searchPtr = lcPtr;
	for (uint32_t i = 0; i < ncmds; i++) {
		struct load_command* lc = (struct load_command*)searchPtr;
		if (lc->cmd == LC_SEGMENT_64) {
			struct segment_command_64* sc = (struct segment_command_64*)searchPtr;
			if (strncmp(sc->segname, "__LINKEDIT", 16) == 0) {
				linkSeg = sc;
				linkIndex = i;
				linkFileOff = sc->fileoff;
				break;
			}
		}
		searchPtr += lc->cmdsize;
	}
	if (!linkSeg) {
		AppLog(@"Couldn't find __LINKEDIT segment.");
		return NO;
	}

	uint64_t alignedSize = align(MAX(sectSize, 0x4000), 0x1000);
	struct segment_command_64 newSeg;
	struct section_64 newSect;
	memset(&newSeg, 0, sizeof(newSeg));
	memset(&newSect, 0, sizeof(newSect));
	newSeg.cmd = LC_SEGMENT_64;
	newSeg.cmdsize = sizeof(newSeg) + sizeof(newSect);
	strncpy(newSeg.segname, segNameC, 16);
	newSeg.vmaddr = linkSeg->vmaddr;
	newSeg.vmsize = alignedSize;
	newSeg.fileoff = linkFileOff;
	newSeg.filesize = alignedSize;
	newSeg.maxprot = VM_PROT_READ | VM_PROT_EXECUTE;
	newSeg.initprot = VM_PROT_READ | VM_PROT_EXECUTE;
	newSeg.nsects = 1;

	strncpy(newSect.sectname, sectNameC, 16);
	strncpy(newSect.segname, segNameC, 16);
	newSect.addr = newSeg.vmaddr;
	newSect.size = sectSize;
	newSect.offset = newSeg.fileoff;
	newSect.align = sectSize < 16 ? 0 : 4;
	newSect.flags = 0x80000400; // S_REGULAR | S_ATTR_PURE_INSTRUCTIONS;

	linkSeg->vmaddr += alignedSize;
	linkSeg->fileoff += alignedSize;

	// i love mach-o (most of this was assist because this has been giving me a headache) just to shift the linkedit cmds
	searchPtr = lcPtr;
	for (uint32_t i = 0; i < ncmds; i++) {
		struct load_command* lc = (struct load_command*)searchPtr;
		if (lc->cmd == LC_DYLD_INFO_ONLY || lc->cmd == LC_DYLD_INFO) {
			struct dyld_info_command* dc = (struct dyld_info_command*)searchPtr;
			#define SHIFT(field) if (dc->field >= linkFileOff) dc->field += alignedSize
			SHIFT(rebase_off);
			SHIFT(bind_off);
			SHIFT(weak_bind_off);
			SHIFT(lazy_bind_off);
			SHIFT(export_off);
			#undef SHIFT
		} else if (lc->cmd == LC_SYMTAB) {
			struct symtab_command* sc = (struct symtab_command*)searchPtr;
			if (sc->symoff >= linkFileOff)
				sc->symoff += alignedSize;
			if (sc->stroff >= linkFileOff)
				sc->stroff += alignedSize;
		} else if (lc->cmd == LC_DYSYMTAB) {
			struct dysymtab_command* dc = (struct dysymtab_command*)searchPtr;
			#define DS(field) if (dc->field >= linkFileOff) dc->field += alignedSize
			DS(tocoff);
			DS(modtaboff);
			DS(extrefsymoff);
			DS(indirectsymoff);
			DS(extreloff);
			DS(locreloff);
			#undef DS
		} else if (lc->cmd == LC_CODE_SIGNATURE || lc->cmd == LC_SEGMENT_SPLIT_INFO || lc->cmd == LC_FUNCTION_STARTS || lc->cmd == LC_DATA_IN_CODE ||
				   lc->cmd == LC_DYLIB_CODE_SIGN_DRS) {
			struct linkedit_data_command* ld = (struct linkedit_data_command*)searchPtr;
			if (ld->dataoff >= linkFileOff)
				ld->dataoff += alignedSize;
		}
		searchPtr += lc->cmdsize;
	}
	header->ncmds += 1;
	header->sizeofcmds += newSeg.cmdsize;

	// rebuilding just in case because binary shifts are wacky
	NSMutableData* out = [NSMutableData data];
	[out appendBytes:buf length:sizeof(*header)];
	lcPtr = buf + sizeof(*header);
	for (uint32_t i = 0; i < ncmds; i++) {
		struct load_command* lc = (struct load_command*)lcPtr;
		if (i == linkIndex) {
			[out appendBytes:&newSeg length:sizeof(newSeg)];
			[out appendBytes:&newSect length:sizeof(newSect)];
		}
		[out appendBytes:lcPtr length:lc->cmdsize];
		lcPtr += lc->cmdsize;
	}
	NSUInteger headerLen = out.length;
	if (headerLen < linkFileOff) {
		NSUInteger copySize = linkFileOff - headerLen;
		[out appendBytes:buf + headerLen length:copySize];
	}
	uint8_t* dead = (uint8_t*)calloc(1, alignedSize);
	[out appendBytes:dead length:sectSize];
	if (alignedSize > sectSize) {
		[out appendBytes:dead + sectSize length:(alignedSize - sectSize)];
	}
	free(dead);
	[out appendBytes:buf + linkFileOff length:origSize - linkFileOff];
	[data setData:out];
	return YES;
}
// ^^^

@implementation Patcher

static NSMutableDictionary* _originalBytes = nil;
static NSMutableArray* _patchedFuncs = nil;

+ (NSMutableDictionary<NSString*, NSData*>*)originalBytes {
	if (!_originalBytes) {
		_originalBytes = [NSMutableDictionary dictionary];
	}
	return _originalBytes;
}

+ (NSMutableArray<NSNumber*>*)patchedFuncs {
	if (!_patchedFuncs) {
		_patchedFuncs = [NSMutableArray new];
	}
	return _patchedFuncs;
}

+ (void)setPatchedFuncs:(NSMutableArray<NSNumber*>*)patchedFuncs {
	_patchedFuncs = patchedFuncs;
}
+ (void)setOriginalBytes:(NSMutableDictionary<NSString*, NSData*>*)originalBytes {
	_originalBytes = originalBytes;
}

+ (BOOL)loadTulipHook {
	// it definitely makes sense
	void* handle = dlopen("@loader_path/Frameworks/libTulipHook.dylib", RTLD_LAZY | RTLD_GLOBAL);
	const char* dlerr = dlerror();
	if (!handle || (uint64_t)handle > 0xf00000000000) {
		if (dlerr) {
			AppLog(@"Failed to load TulipHook: %s", dlerr);
		} else {
			AppLog(@"Failed to load TulipHook: An unknown error occured.");
		}
		return NO;
	}
	AppLog(@"Loaded TulipHook (Handle: %#llx)", handle);

	auto addr = findSymbolAddr("__ZN5tulip4hook17getRelocatedBytesExxRKNSt3__16vectorIhNS1_9allocatorIhEEEE");
	if (!addr)
		return NO;
	auto addr2 = findSymbolAddr("__ZN5tulip4hook21getCommonHandlerBytesExl");
	auto addr3 = findSymbolAddr("__ZN5tulip4hook24getCommonIntervenerBytesExxml");
	if (!addr2 || !addr3)
		return NO;
	getRelocatedBytes = reinterpret_cast<getRelocatedBytesDef>(addr);
	getCommonHandlerBytes = reinterpret_cast<getCommonHandlerBytesDef>(addr2);
	getCommonIntervenerBytes = reinterpret_cast<getCommonIntervenerBytesDef>(addr3);
	return YES;
}

/*
codeCave = 0x3000
patch(codeCave, commonHandlerBytes)
codeCave += commonHandlerBytes.size
for func in list:
  res = trampolineGen(codeCave, func)
  patch(codeCave, res.bytes, res.size)
  codeCave += res.size
for func in list:
  patch(func.addr, intervenerBytes)
*/

+ (BOOL)patchFunc:(NSMutableData*)data strAddr:(NSString*)strAddr textSect:(struct section_64*)textSect customSect:(struct section_64*)customSect {
	uint64_t addr = strtoull([strAddr UTF8String], NULL, 0);
	if (self.originalBytes[strAddr] != nil) {
		//AppLogDebug(@"Function at %#llx already patched!", addr);
		AppLog(@"Function at %#llx already patched!", addr);
		return NO;
	}
	// safe guard so we dont override some needed bytes
	if (codeCaveOffset >= TEXT_MAX) {
		AppLogWarn(@"Cannot patch more than %#llx! (Current code cave offset: %#llx)", TEXT_MAX, codeCaveOffset);
		return NO;
	}
	int funcIndex = [self.originalBytes count] + 1;
	NSData* original = [data subdataWithRange:NSMakeRange((NSUInteger)addr, 4 * sizeof(uint32_t))];
	self.originalBytes[strAddr] = original;

	if (getRelocatedBytes && getCommonIntervenerBytes) {
		const uint8_t* bytes = static_cast<const uint8_t*>(original.bytes);
		std::vector<uint8_t> bytesVec = std::vector<uint8_t>(bytes, bytes + original.length);
		// RelocaledBytesReturn gen = getRelocatedBytes((textSect->addr + addr), (textSect->addr + codeCaveOffset), bytesVec);
		RelocaledBytesReturn gen = getRelocatedBytes((textSect->addr + addr), (((customSect->addr + codeCaveOffset) + textSect->offset)), bytesVec);
		if (!gen.error.empty()) {
			AppLogError(@"[TulipHook] getRelocatedBytes failed: %s", gen.error.c_str());
			return NO;
		} else if (gen.bytes.size() == 0) {
			AppLogError(@"[TulipHook] getRelocatedBytes: Bytes Vector is empty");
			return NO;
		}
		[data replaceBytesInRange:NSMakeRange(customSect->offset + codeCaveOffset, gen.bytes.size()) withBytes:gen.bytes.data()];
		// std::vector<uint8_t> intervenerBytes = getCommonIntervenerBytes((textSect->addr + addr), (textSect->addr + TEXT_OFFSET), funcIndex, (codeCaveOffset - TEXT_OFFSET));
		std::vector<uint8_t> intervenerBytes = getCommonIntervenerBytes((textSect->addr + addr), (customSect->addr + textSect->offset), funcIndex, codeCaveOffset);
		if (intervenerBytes.size() > 0) {
			[data replaceBytesInRange:NSMakeRange(addr, intervenerBytes.size()) withBytes:intervenerBytes.data()];
		}
		codeCaveOffset += gen.bytes.size();
		return YES;
	}
	return NO;
}
+ (BOOL)patchWithPatches:(NSMutableData*)data addr:(uint64_t)addr size:(NSUInteger)size patchData:(NSData*)patchData {
	[data replaceBytesInRange:NSMakeRange(addr, size) withBytes:patchData.bytes];
	return YES;
}

+ (NSArray<NSString*>*)getHookOffsetsFromData:(NSString*)data {
	// \[GEODE_MODIFY_ADDRESS\] base::get\(\) \+ (0x[0-9a-fA-F]+) \[GEODE_MODIFY_END\]
	NSMutableArray<NSString*>* offsets = [NSMutableArray array];
	NSError* error;
	NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\\[GEODE_MODIFY_ADDRESS\\]\\s*base::get\\(\\) \\+ (0x[0-9a-fA-F]+) \\[GEODE_MODIFY_END\\]"
																		   options:0
																			 error:&error];
	if (regex && !error) {
		NSArray<NSTextCheckingResult*>* matches = [regex matchesInString:data options:0 range:NSMakeRange(0, data.length)];
		for (NSTextCheckingResult* match in matches) {
			NSRange range = [match rangeAtIndex:1];
			NSString* string = [data substringWithRange:range];
			[offsets addObject:string];
		}
	}
	return [offsets copy];
}

+ (NSArray<NSString*>*)getStaticHookOffsetsFromData:(NSString*)data {
	// \[GEODE_MODIFY_NAME\](.+?)\[GEODE_MODIFY_OFFSET\]([0-9a-fA-F]+)\[GEODE_MODIFY_END\]
	NSMutableArray<NSString*>* offsets = [NSMutableArray array];
	NSError* error;
	NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\\[GEODE_MODIFY_NAME\\](.+?)\\[GEODE_MODIFY_OFFSET\\]([0-9a-fA-F]+)\\[GEODE_MODIFY_END\\]"
																		   options:0
																			 error:&error];
	if (regex && !error) {
		NSArray<NSTextCheckingResult*>* matches = [regex matchesInString:data options:0 range:NSMakeRange(0, data.length)];
		for (NSTextCheckingResult* match in matches) {
			NSRange range = [match rangeAtIndex:1];
			NSString* string = [data substringWithRange:range];
			[offsets addObject:string];
		}
	}
	return [offsets copy];
}

+ (NSArray<NSTextCheckingResult*>*)getStaticPatchesOffsetsFromData:(NSString*)data {
	// \[GEODE_PATCH_SIZE\]([0-9]+)\[GEODE_PATCH_BYTES\](.+?)\[GEODE_PATCH_OFFSET\]([0-9a-fA-F]+)\[GEODE_PATCH_END\]
	NSError* error;
	NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\\[GEODE_PATCH_SIZE\\]([0-9]+)\\[GEODE_PATCH_BYTES\\](.+?)\\[GEODE_PATCH_OFFSET\\]([0-9a-fA-F]+)\\[GEODE_PATCH_END\\]"
																		   options:0
																			 error:&error];
	if (regex && !error) {
		NSArray<NSTextCheckingResult*>* matches = [regex matchesInString:data options:0 range:NSMakeRange(0, data.length)];
		return matches;
	}
	return nil;
}

// ai because im too lazy to do this
+ (NSString *)hexStringWithSpaces:(NSData*)data includeSpaces:(BOOL)includeSpaces {
    const unsigned char *dataBuffer = (const unsigned char *)[data bytes];
    if (!dataBuffer) {
        return [NSString string];
    }
    
    NSUInteger          dataLength  = [data length];
    // Each byte is two hex chars, plus optional space (except after last byte)
    NSUInteger          stringSize  = dataLength * 2 + (includeSpaces ? dataLength - 1 : 0);
    NSMutableString    *hexString   = [NSMutableString stringWithCapacity:stringSize];
    
    for (NSUInteger i = 0; i < dataLength; ++i) {
        if (includeSpaces && i > 0) {
            [hexString appendString:@" "];
        }
        [hexString appendFormat:@"%02X", dataBuffer[i]];
    }
    
    return [hexString copy];
}

+ (void)startUnzip:(void (^)(NSString* doForce))completionHandler {
    return completionHandler(nil);
	NSFileManager* fm = [NSFileManager defaultManager];
	NSError* error;
	BOOL isDir = NO;
	NSString *forceSign = nil;
	NSURL* zipModsPath = [[LCPath dataPath] URLByAppendingPathComponent:@"GeometryDash/Documents/game/geode/mods"];
	NSString* unzipModsPath = [[LCPath dataPath] URLByAppendingPathComponent:@"GeometryDash/Documents/game/geode/unzipped"].path;
	if ([fm fileExistsAtPath:[[LCPath dataPath] URLByAppendingPathComponent:@"GeometryDash/Documents/game/geode"].path isDirectory:&isDir]) {
		if (isDir) {
			AppLog(@"Checking if mods need to be unzipped...");
			[fm createDirectoryAtPath:unzipModsPath withIntermediateDirectories:YES attributes:nil error:nil];
			NSArray* modsDir = [fm contentsOfDirectoryAtURL:zipModsPath includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
			if (error) {
				AppLog(@"Couldn't read mods directory: %@", error);
				error = nil;
			}
			if (modsDir && modsDir.count > 0) {
				for (NSURL* url in modsDir) {
					if (![url.pathExtension.lowercaseString isEqualToString:@"geode"])
						continue;
					NSString* modName = [url URLByDeletingPathExtension].lastPathComponent;
					NSString *extractTarget = [unzipModsPath stringByAppendingPathComponent:modName];
					BOOL isDir;
					if (!(![fm fileExistsAtPath:extractTarget isDirectory:&isDir] || !isDir)) continue;
					AppLog(@"Unzipping %@", modName);
					forceSign = @"force";
					// erm 
					dispatch_semaphore_t sema = dispatch_semaphore_create(0);
					[Utils decompress:url.path extractionPath:extractTarget completion:^(int err) {
						if (err != 0) {
							AppLog(@"Failed to decompress %@: Code %@", url.path, err);
						}
						dispatch_semaphore_signal(sema);
					}];
					dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER); // is this really safe...
					NSString *datePath = [extractTarget stringByAppendingPathComponent:@"/modified-at"];
					NSDictionary<NSFileAttributeKey, id> *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:extractTarget error:nil];
					if (!attrs) continue;
					auto modifiedDate = std::__fs::filesystem::last_write_time(extractTarget.UTF8String);
					auto modifiedCount = std::chrono::duration_cast<std::chrono::milliseconds>(modifiedDate.time_since_epoch());
					auto modifiedHash = std::to_string(modifiedCount.count());
					[[NSString stringWithCString:modifiedHash.c_str() encoding:[NSString defaultCStringEncoding]] writeToFile:datePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
				}
			}
		}
	}
    completionHandler(forceSign);
}

// handler addr being that textHandlerStorage
+ (void)patchGDBinary:(NSURL*)from to:(NSURL*)to withHandlerAddress:(uint64_t)handlerAddress force:(BOOL)force completionHandler:(void (^)(BOOL success, NSString* error))completionHandler {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSError* error;
	self.originalBytes = [NSMutableDictionary dictionary];
	if (![fm fileExistsAtPath:from.path]) {
		[fm copyItemAtURL:to toURL:from error:&error];
		if (error) {
			return completionHandler(NO, [NSString stringWithFormat:@"Couldn't copy binary: %@", error.localizedDescription]);
		}
	}
	if (![fm fileExistsAtPath:from.path]) {
		return completionHandler(NO, @"Couldn't find original binary.");
	}
	NSString *forceSign = nil;

	[Patcher startUnzip:^(NSString *doForce) {
	    NSError* error;
        AppLog(@"Patching Binary...");
        if (![Patcher loadTulipHook])
            return completionHandler(NO, @"Couldn't load TulipHook");
        NSMutableData* data = [NSMutableData dataWithContentsOfURL:from options:0 error:&error];
        if (!data || error) {
            AppLog(@"Couldn't read binary: %@", error);
            return completionHandler(NO, @"Couldn't read binary");
        }
        uint8_t* base = (uint8_t*)data.mutableBytes;
        struct mach_header_64* header = (struct mach_header_64*)base;
        uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
        if (data.length < sizeof(struct mach_header_64) || (header->magic != MH_MAGIC && header->magic != MH_MAGIC_64)) {
            AppLog(@"Couldn't patch! Binary is not 64-bit Mach-O.");
            return completionHandler(NO, @"Binary is not 64-bit Mach-O.");
        }

        AppLog(@"Writing new executable region...");
        if (!appendNewSection(data, 0x4000)) {
            AppLog(@"Something went wrong when writing a new executable region.");
            return completionHandler(NO, @"Couldn't write new RX region.");
        }

        // === PATCH STEP 1 ====
        struct segment_command_64* textSeg = NULL;
        struct section_64* textSect = NULL;
        struct section_64* customSect = NULL;
        struct linkedit_data_command const* func_start = NULL; // is this necessary
        struct load_command* command = (struct load_command*)imageHeaderPtr;
        for (int i = 0; i < header->ncmds; i++) {
            if (command->cmd == LC_SEGMENT_64) {
                struct segment_command_64* seg = (struct segment_command_64*)command;
                if (strcmp(seg->segname, "__TEXT") == 0) {
                    textSeg = seg;
                    struct section_64* sect = (struct section_64*)(seg + 1);
                    for (int x = 0; x < seg->nsects; x++) {
                        if (strcmp(sect[x].sectname, "__text") == 0) {
                            textSect = &sect[x];
                            // break;
                        } else if (strcmp(sect[x].sectname, "__mysect") == 0) {
                            customSect = &sect[x];
                        }
                    }
                } else if (strcmp(seg->segname, "__CUSTOM") == 0) {
                    struct section_64* sect = (struct section_64*)(seg + 1);
                    for (int x = 0; x < seg->nsects; x++) {
                        if (strcmp(sect[x].sectname, "__custom") == 0) {
                            customSect = &sect[x];
                            CAVE_OFFSET = customSect->addr;
                            codeCaveOffset = CAVE_OFFSET;
                            break;
                        }
                    }
                }
            } else if (command->cmd == LC_FUNCTION_STARTS) {
                func_start = (struct linkedit_data_command const*)command; // load command of function start
            }
            // void* -> char*
            command = (struct load_command*)((char*)command + command->cmdsize);
        }
        if (!textSeg) {
            AppLog(@"Couldn't find __TEXT segment.");
            return completionHandler(NO, @"Couldn't find __TEXT segment (Binary corrupted?)");
        }
        if (!textSect) {
            AppLog(@"Couldn't find __text section.");
            return completionHandler(NO, @"Couldn't find __text segment (Binary corrupted?)");
        }
        if (!customSect) {
            AppLog(@"Couldn't find __custom section.");
            return completionHandler(NO, @"Couldn't find __custom segment (Creating RX region failed?)");
        }
        if (func_start == NULL || func_start->datasize == 0) {
            AppLog(@"Couldn't find LC_FUNCTION_STARTS cmd.");
            return completionHandler(NO, @"Couldn't find LC_FUNCTION_STARTS segment (Binary corrupted?)");
        }

        AppLog(@"Patching handler at %#llx...", CAVE_OFFSET);
        if (getCommonHandlerBytes) {
            // textSect->addr + TEXT_OFFSET, handlerAddress - TEXT_OFFSET
            std::vector<uint8_t> bytes = getCommonHandlerBytes(customSect->addr, (handlerAddress - (customSect->addr - textSeg->vmaddr)));
            if (bytes.size() == 0) {
                AppLog(@"Handler generation from TulipHook failed. (Empty bytes)");
                return completionHandler(NO, @"TulipHook failed to generate handler bytes (Empty bytes)");
            }
            //[data replaceBytesInRange:NSMakeRange(codeCaveOffset, bytes.size()) withBytes:bytes.data()];
            [data replaceBytesInRange:NSMakeRange(customSect->offset, bytes.size()) withBytes:bytes.data()];
            // codeCaveOffset += bytes.size();
            codeCaveOffset = bytes.size();
        } else {
            AppLog(@"Couldn't patch! getCommonHandlerBytes function is null!");
            return completionHandler(NO, @"TulipHook failed find getCommonHandlerBytes");
        }

        // === PATCH STEP 2 ====
		NSString* unzipModsPath = [[LCPath dataPath] URLByAppendingPathComponent:@"GeometryDash/Documents/game/geode/unzipped"].path;
		NSURL* savedJSONURL = [[LCPath dataPath] URLByAppendingPathComponent:@"GeometryDash/Documents/save/geode/mods/geode.loader/saved.json"];
		NSData* savedJSONData = [NSData dataWithContentsOfURL:savedJSONURL options:0 error:&error];
		NSDictionary* savedJSONDict;
		BOOL canParseJSON = NO;
		NSMutableArray<NSString*>* modEnabledDict = [NSMutableArray new];
		if (!error) {
			savedJSONDict = [NSJSONSerialization JSONObjectWithData:savedJSONData options:kNilOptions error:&error];
			if (!error && savedJSONDict && [savedJSONDict isKindOfClass:[NSDictionary class]]) {
				canParseJSON = YES;
				for (NSString *key in savedJSONDict.allKeys) {
					if ([key hasPrefix:@"should-load-"]) {
						BOOL value = [savedJSONDict[key] boolValue];
						if (value) {
							[modEnabledDict addObject:[NSString stringWithFormat:@"%@.ios.dylib", [key substringFromIndex:12]]];
						}
					}
				}
			}
		}

        NSArray* modsDir = [fm contentsOfDirectoryAtPath:unzipModsPath error:&error];
        if (error) {
            AppLog(@"Couldn't read unzipped directory: %@", error);
            error = nil;
        }
        NSMutableArray<NSString*>* modDict = [NSMutableArray new];
        NSString* geodePath = [Utils getTweakDir];
        if (geodePath) {
            [modDict addObject:geodePath];
        }
		if (canParseJSON) {
			AppLog(@"saved.json parsed!");
			for (NSString* modId in modsDir) {
				NSString* modPath = [unzipModsPath stringByAppendingPathComponent:modId];
				BOOL isDir;
				if (![fm fileExistsAtPath:modPath isDirectory:&isDir] || !isDir) continue;
				NSArray* modDir = [fm contentsOfDirectoryAtPath:modPath error:&error];
				if (error) continue;
				for (NSString* file in modDir) {
					if ([file hasSuffix:@"ios.dylib"]) {
						if ([modEnabledDict containsObject:file]) {
							[modDict addObject:[modPath stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@", file]]];
						}
					}
				}
			}
		}
        for (int i = 0; i < modDict.count; i++) {
            AppLog(@"Patching functions... (%i/%i)", (i + 1), modDict.count);
            NSData* mdata = [NSData dataWithContentsOfFile:[modDict objectAtIndex:i] options:0 error:nil];
            if (mdata == nil) continue;
            NSString* dataString = [[NSString alloc] initWithData:mdata encoding:NSASCIIStringEncoding];
            for (NSString* offset in [Patcher getHookOffsetsFromData:dataString]) {
                if (![offset hasPrefix:@"0x"])
                    continue;
                if ([Patcher patchFunc:data strAddr:offset textSect:textSect customSect:customSect]) {
                    AppLogDebug(@"Patched Function %@", offset);
                };
            }
            for (NSString* offset in [Patcher getStaticHookOffsetsFromData:dataString]) {
                if ([Patcher patchFunc:data strAddr:offset textSect:textSect customSect:customSect]) {
                    AppLogDebug(@"Patched Function %@", offset);
                };
            }
            NSArray<NSTextCheckingResult*>* staticMatches = [Patcher getStaticPatchesOffsetsFromData:dataString];
            for (NSTextCheckingResult* match in staticMatches) {
                NSString *sizeString = [dataString substringWithRange:[match rangeAtIndex:1]];
                NSUInteger patchSize = [sizeString integerValue];
                NSData *patchData = [[dataString substringWithRange:[match rangeAtIndex:2]] dataUsingEncoding:NSISOLatin1StringEncoding];
                
                NSString *strAddr = [NSString stringWithFormat:@"0x%@", [dataString substringWithRange:[match rangeAtIndex:3]]];
                NSUInteger addr = strtoull([strAddr UTF8String], NULL, 0);

                [data replaceBytesInRange:NSMakeRange(addr, patchSize) withBytes:patchData.bytes];
                AppLogDebug(@"Patched Offset %#llx with %i bytes (%@)", addr, patchSize, [Patcher hexStringWithSpaces:patchData includeSpaces:YES]);
            }
        }
        NSString* patchChecksum = [[Utils getPrefs] stringForKey:@"PATCH_CHECKSUM"];
        NSArray* keys = [self.originalBytes allKeys];
        NSString* hash = [Utils sha256sumWithString:[keys componentsJoinedByString:@","]];
        if (patchChecksum != nil) {
            if (![patchChecksum isEqualToString:hash]) {
                AppLog(@"Hash mismatch (%@ vs %@), now writing to binary...", patchChecksum, hash)
                [[Utils getPrefs] setObject:hash forKey:@"PATCH_CHECKSUM"];
            } else {
                //AppLog(@"Binary already patched, skipping...");
                if (!force) {
                    AppLog(@"Binary already patched, skipping...");
                    return completionHandler(YES, nil);
                }
            }
        } else {
            AppLog(@"Got hash %@, now writing to binary...", hash)
            [[Utils getPrefs] setObject:hash forKey:@"PATCH_CHECKSUM"];
        }

        struct mach_header_64* headerNew = (struct mach_header_64*)(uint8_t*)data.mutableBytes;
        if (data.length < sizeof(struct mach_header_64) || (headerNew->magic != MH_MAGIC && headerNew->magic != MH_MAGIC_64)) {
            // okay how would this realistically happen
            AppLog(@"Couldn't patch! Binary wasn't properly patched as a 64-bit Mach-O.");
            return completionHandler(NO, @"Patched binary wasn't properly patched as a proper Mach-O binary");
        }

        [data writeToURL:to options:NSDataWritingAtomic error:&error];
        if (error) {
            AppLog(@"Couldn't patch binary: %@", error);
            return completionHandler(NO, [NSString stringWithFormat:@"Patch failed: %@", error.localizedDescription]);
        }
        AppLog(@"Binary has been patched!");
        return completionHandler(YES, forceSign);
    }];
}
@end
