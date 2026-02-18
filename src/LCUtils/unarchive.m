#import "src/components/LogUtils.h"
#import "unarchive.h"

#include "archive.h"
#include "archive_entry.h"

CGFloat completedUnitCount = 0;
CGFloat totalUnitCount = 0;

CGFloat comp_completedUnitCount = 0;
CGFloat comp_totalUnitCount = 0;

static int copy_data(struct archive* ar, struct archive* aw, NSProgress* progress) {
	int r;
	const void* buff;
	size_t size;
	la_int64_t offset;

	for (;;) {
		r = archive_read_data_block(ar, &buff, &size, &offset);
		if (r == ARCHIVE_EOF)
			return (ARCHIVE_OK);
		if (r < ARCHIVE_OK)
			return (r);
		r = archive_write_data_block(aw, buff, size, offset);
		if (r < ARCHIVE_OK) {
			fprintf(stderr, "%s\n", archive_error_string(aw));
			return (r);
		}
		progress.completedUnitCount += size;
		completedUnitCount += size;
	}
}

bool forceProgress = false;

CGFloat getProgress() {
	if (forceProgress) {
		return 100;
	}
	CGFloat progress = ((completedUnitCount / totalUnitCount) * 100);
	if (!(progress >= 0)) {
		return 1;
	} else {
		return progress;
	}
}

CGFloat getProgressCompress() {
	if (forceProgress) {
		return 100;
	}
	CGFloat progress = ((comp_completedUnitCount / comp_totalUnitCount) * 100);
	if (!(progress >= 0)) {
		return 1;
	} else {
		return progress;
	}
}

int extract(NSString* fileToExtract, NSString* extractionPath, NSProgress* progress) {
	forceProgress = false;
	completedUnitCount = 0;
	totalUnitCount = 0;
	struct archive* a;
	struct archive* ext;
	struct archive_entry* entry;
	int flags;
	int r;

	/* Select which attributes we want to restore. */
	flags = ARCHIVE_EXTRACT_TIME;
	flags |= ARCHIVE_EXTRACT_PERM;
	flags |= ARCHIVE_EXTRACT_ACL;
	flags |= ARCHIVE_EXTRACT_FFLAGS;

	// Calculate decompressed size
	a = archive_read_new();
	archive_read_support_format_all(a);
	archive_read_support_filter_all(a);
	if ((r = archive_read_open_filename(a, fileToExtract.fileSystemRepresentation, 10240))) {
		archive_read_free(a);
		AppLog(@"Failed to open archive: %@", fileToExtract);
		forceProgress = true;
		return 1;
	}
	while ((r = archive_read_next_header(a, &entry)) != ARCHIVE_EOF) {
		if (r < ARCHIVE_OK) {
			fprintf(stderr, "%s\n", archive_error_string(a));
			AppLog(@"Error reading archive header: %s", archive_error_string(a));
		}
		if (r < ARCHIVE_WARN) {
			archive_read_close(a);
			archive_read_free(a);
			AppLog(@"Archive warning: %s", archive_error_string(a));
			return 1;
		}
		totalUnitCount += archive_entry_size(entry);
		progress.totalUnitCount += archive_entry_size(entry);
	}
	archive_read_close(a);
	archive_read_free(a);

	// Re-open the archive and extract
	a = archive_read_new();
	archive_read_support_format_all(a);
	archive_read_support_filter_all(a);
	if ((r = archive_read_open_filename(a, fileToExtract.fileSystemRepresentation, 10240))) {
		archive_read_free(a);
		AppLog(@"Failed to reopen archive for extraction: %@", fileToExtract);
		forceProgress = true;
		return 1;
	}
	ext = archive_write_disk_new();
	archive_write_disk_set_options(ext, flags);
	archive_write_disk_set_standard_lookup(ext);

	while ((r = archive_read_next_header(a, &entry)) != ARCHIVE_EOF) {
		if (r == ARCHIVE_EOF)
			break;
		if (r < ARCHIVE_OK) {
			fprintf(stderr, "%s\n", archive_error_string(a));
			AppLog(@"Error reading header: %s", archive_error_string(a));
		}
		if (r < ARCHIVE_WARN)
			break;

		NSString* currentFile = [NSString stringWithUTF8String:archive_entry_pathname(entry)];
		NSString* fullOutputPath = [extractionPath stringByAppendingPathComponent:currentFile];
		// printf("extracting %@ to %@\n", currentFile, fullOutputPath);
		archive_entry_set_pathname(entry, fullOutputPath.fileSystemRepresentation);

		r = archive_write_header(ext, entry);
		if (r < ARCHIVE_OK) {
			fprintf(stderr, "%s\n", archive_error_string(ext));
			AppLog(@"Error writing header: %s", archive_error_string(ext));
		} else if (archive_entry_size(entry) > 0) {
			r = copy_data(a, ext, progress);
			if (r < ARCHIVE_OK) {
				fprintf(stderr, "%s\n", archive_error_string(ext));
				AppLog(@"Error copying data: %s", archive_error_string(ext));
			}
			if (r < ARCHIVE_WARN)
				break;
		}
		r = archive_write_finish_entry(ext);
		if (r < ARCHIVE_OK) {
			fprintf(stderr, "%s\n", archive_error_string(ext));
			AppLog(@"Error finishing entry: %s", archive_error_string(ext));
		}
		if (r < ARCHIVE_WARN)
			break;
	}
	archive_read_close(a);
	archive_read_free(a);
	archive_write_close(ext);
	archive_write_free(ext);

	return 0;
}

// i cant be bothered to do this...
int addFileToArchive(struct archive* write, NSString* filePath, NSString* basePath, NSProgress* progress) {
	NSFileManager* fm = [NSFileManager defaultManager];

	// Get file attributes
	NSError* error = nil;
	NSDictionary* attributes = [fm attributesOfItemAtPath:filePath error:&error];
	if (!attributes) {
		AppLog(@"Failed to get file attributes for %@: %@", filePath, error.localizedDescription);
		return -1;
	}

	// Create archive entry
	struct archive_entry* entry = archive_entry_new();

	// Create relative path for the archive entry
	NSString* relativePath = [filePath stringByReplacingOccurrencesOfString:basePath withString:@""];
	if ([relativePath hasPrefix:@"/"]) {
		relativePath = [relativePath substringFromIndex:1];
	}

	//"Payload/Cowabunga.app"
	// relativePath = [@"Payload/GeodeHelper.app" stringByAppendingString:relativePath];
	relativePath = [@"Payload/GD" stringByAppendingString:relativePath];
	// relativePath = [relativePath stringByReplacingOccurrencesOfString:@"GDcom.robtop.geometryjump.app" withString:@"GeodeHelper.app"];
	relativePath = [relativePath stringByReplacingOccurrencesOfString:@"GDcom.robtop.geometryjump.app" withString:@"GeometryJump.app"];
	archive_entry_set_pathname(entry, relativePath.fileSystemRepresentation);

	NSString* fileType = attributes[NSFileType];

	if ([fileType isEqualToString:NSFileTypeDirectory]) {
		// Directory entry
		archive_entry_set_filetype(entry, AE_IFDIR);
		archive_entry_set_perm(entry, 0755);
		archive_entry_set_size(entry, 0);

		// Write directory header
		int r = archive_write_header(write, entry);
		if (r < ARCHIVE_OK) {
			AppLog(@"ZIP directory header error: %s", archive_error_string(write));
			archive_entry_free(entry);
			return -1;
		}

		// Finish directory entry (no data to write)
		if (archive_write_finish_entry(write) < ARCHIVE_OK) {
			AppLog(@"ZIP directory finish-entry error: %s", archive_error_string(write));
		}

	} else if ([fileType isEqualToString:NSFileTypeRegular]) {
		// Regular file entry
		unsigned long long fileSize = [attributes[NSFileSize] unsignedLongLongValue];

		archive_entry_set_filetype(entry, AE_IFREG);
		archive_entry_set_perm(entry, 0644);
		archive_entry_set_size(entry, fileSize);

		// Write file header
		int r = archive_write_header(write, entry);
		if (r < ARCHIVE_OK) {
			AppLog(@"ZIP file header error: %s", archive_error_string(write));
			archive_entry_free(entry);
			return -1;
		}

		// Open and read the file
		FILE* file = fopen(filePath.fileSystemRepresentation, "rb");
		if (!file) {
			AppLog(@"Failed to open file for reading: %@", filePath);
			archive_entry_free(entry);
			return -1;
		}

		// Write file data
		char buffer[8192];
		size_t bytesRead;
		while ((bytesRead = fread(buffer, 1, sizeof(buffer), file)) > 0) {
			if (archive_write_data(write, buffer, bytesRead) < 0) {
				AppLog(@"ZIP data write error: %s", archive_error_string(write));
				fclose(file);
				archive_entry_free(entry);
				return -1;
			}
			completedUnitCount += bytesRead;
			progress.completedUnitCount += bytesRead;
		}

		fclose(file);

		// Finish file entry
		if (archive_write_finish_entry(write) < ARCHIVE_OK) {
			AppLog(@"ZIP file finish-entry error: %s", archive_error_string(write));
		}
	}

	archive_entry_free(entry);
	return 0;
}

// https://github.com/libarchive/libarchive/wiki/Examples#user-content-A_Basic_Write_Example
int compress(NSString* directoryToCompress, NSString* zipPath, NSProgress* progress) {
	NSFileManager* fm = [NSFileManager defaultManager];
	forceProgress = false;
	comp_completedUnitCount = 0;
	comp_totalUnitCount = 0;

	struct archive* write = archive_write_new();
	archive_write_set_format_zip(write);
	if (archive_write_open_filename(write, zipPath.fileSystemRepresentation) != ARCHIVE_OK) {
		AppLog(@"Failed to open zip output: %@", zipPath);
		forceProgress = true;
		archive_write_free(write);
		return 1;
	}

	NSString* basePath = [directoryToCompress stringByDeletingLastPathComponent];

	NSDirectoryEnumerator* enumerator = [fm enumeratorAtPath:directoryToCompress];
	NSDirectoryEnumerator* enumerator2 = [fm enumeratorAtPath:directoryToCompress];
	NSString* file;

	if (addFileToArchive(write, directoryToCompress, basePath, progress) < 0) {
		archive_write_close(write);
		archive_write_free(write);
		forceProgress = true;
		return 1;
	}
	while ((file = [enumerator2 nextObject])) {
		comp_totalUnitCount++;
	}
	while ((file = [enumerator nextObject])) {
		comp_completedUnitCount++;
		NSString* fullPath = [directoryToCompress stringByAppendingPathComponent:file];

		if (addFileToArchive(write, fullPath, basePath, progress) < 0) {
			archive_write_close(write);
			archive_write_free(write);
			forceProgress = true;
			return 1;
		}
	}

	archive_write_close(write);
	archive_write_free(write);
	return 0;
}

// == Enterprise Mode only == //
// i cant be bothered to do this...
int addFileToArchiveEnt(struct archive* write, NSString* filePath, NSString* basePath, BOOL includeData) {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSError* error = nil;
	NSDictionary* attributes = [fm attributesOfItemAtPath:filePath error:&error];
	if (!attributes) {
		NSLog(@"[EnterpriseLoader] Failed to get file attributes for %@: %@", filePath, error.localizedDescription);
		return -1;
	}
	struct archive_entry* entry = archive_entry_new();
	NSString* relativePath = [filePath stringByReplacingOccurrencesOfString:basePath withString:@""];
	if ([relativePath hasPrefix:@"/"]) {
		relativePath = [relativePath substringFromIndex:1];
	}
	archive_entry_set_pathname(entry, relativePath.fileSystemRepresentation);
	NSString* fileType = attributes[NSFileType];
	if ([fileType isEqualToString:NSFileTypeDirectory]) {
		archive_entry_set_filetype(entry, AE_IFDIR);
		archive_entry_set_perm(entry, 0755);
		archive_entry_set_size(entry, 0);
		int r = archive_write_header(write, entry);
		if (r < ARCHIVE_OK) {
			NSLog(@"[EnterpriseLoader] ZIP directory header error: %s", archive_error_string(write));
			archive_entry_free(entry);
			return -1;
		}
		if (archive_write_finish_entry(write) < ARCHIVE_OK) {
			NSLog(@"[EnterpriseLoader] ZIP directory finish-entry error: %s", archive_error_string(write));
		}
	} else if ([fileType isEqualToString:NSFileTypeRegular]) {
		unsigned long long fileSize = includeData ? [attributes[NSFileSize] unsignedLongLongValue] : 0;
		archive_entry_set_filetype(entry, AE_IFREG);
		archive_entry_set_perm(entry, 0644);
		archive_entry_set_size(entry, fileSize);
		int r = archive_write_header(write, entry);
		if (r < ARCHIVE_OK) {
			NSLog(@"[EnterpriseLoader] ZIP file header error: %s", archive_error_string(write));
			archive_entry_free(entry);
			return -1;
		}
		if (includeData) {
			FILE* file = fopen(filePath.fileSystemRepresentation, "rb");
			if (!file) {
				NSLog(@"[EnterpriseLoader] Failed to open file for reading: %@", filePath);
				archive_entry_free(entry);
				return -1;
			}
			char buffer[8192];
			size_t bytesRead;
			while ((bytesRead = fread(buffer, 1, sizeof(buffer), file)) > 0) {
				if (archive_write_data(write, buffer, bytesRead) < 0) {
					NSLog(@"[EnterpriseLoader] ZIP data write error: %s", archive_error_string(write));
					fclose(file);
					archive_entry_free(entry);
					return -1;
				}
			}
			fclose(file);
		}
		if (archive_write_finish_entry(write) < ARCHIVE_OK) {
			NSLog(@"[EnterpriseLoader] ZIP file finish-entry error: %s", archive_error_string(write));
		}
	}
	archive_entry_free(entry);
	return 0;
}

// https://github.com/libarchive/libarchive/wiki/Examples#user-content-A_Basic_Write_Example
int compressEnt(NSString* docPath, NSString* zipPath, BOOL* force) {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSMutableArray<NSDictionary*>* files = [NSMutableArray array];

	NSString* logsDir = [docPath stringByAppendingPathComponent:@"game/geode/logs"];
	NSArray<NSString*>* logsContents = [fm contentsOfDirectoryAtPath:logsDir error:nil];
	for (NSString* fname in logsContents) {
		NSString* full = [logsDir stringByAppendingPathComponent:fname];
		[files addObject:@{@"path" : full, @"includeData" : @YES}];
	}
	NSString* crashLogsDir = [docPath stringByAppendingPathComponent:@"game/geode/crashlogs"];
	NSArray<NSString*>* crashLogsContents = [fm contentsOfDirectoryAtPath:crashLogsDir error:nil];
	for (NSString* fname in crashLogsContents) {
		NSString* full = [crashLogsDir stringByAppendingPathComponent:fname];
		[files addObject:@{@"path" : full, @"includeData" : @YES}];
	}
	NSString* zmodsDir = [docPath stringByAppendingPathComponent:@"game/geode/mods"];
	NSArray<NSString*>* zmodsContents = [fm contentsOfDirectoryAtPath:zmodsDir error:nil];
	for (NSString* fname in zmodsContents) {
		NSString* full = [zmodsDir stringByAppendingPathComponent:fname];
		[files addObject:@{@"path" : full, @"includeData" : @NO}];
	}
	NSString* binsDir = [docPath stringByAppendingPathComponent:@"game/geode/unzipped/binaries"];
	NSArray<NSString*>* binsContents = [fm contentsOfDirectoryAtPath:binsDir error:nil];
	for (NSString* fname in binsContents) {
		NSString* full = [binsDir stringByAppendingPathComponent:fname];
		[files addObject:@{@"path" : full, @"includeData" : @YES}];
	}

	NSString* unzipDir = [docPath stringByAppendingPathComponent:@"game/geode/unzipped"];
	NSArray<NSString*>* modsDir = [fm contentsOfDirectoryAtPath:unzipDir error:nil];
	for (NSString* modId in modsDir) {
		NSString* modPath = [unzipDir stringByAppendingPathComponent:modId];
		NSString* modBinPath = [modPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.ios.dylib", [modPath lastPathComponent]]];
		if ([fm fileExistsAtPath:modBinPath]) {
			[files addObject:@{@"path" : modBinPath, @"includeData" : @YES}];
		}
		NSString* modJsonPath = [modPath stringByAppendingPathComponent:@"mod.json"];
		if ([fm fileExistsAtPath:modJsonPath]) {
			[files addObject:@{@"path" : modJsonPath, @"includeData" : @YES}];
		}
	}

	NSString* savedJsonPath = [docPath stringByAppendingPathComponent:@"save/geode/mods/geode.loader/saved.json"];
	if ([fm fileExistsAtPath:savedJsonPath]) {
		[files addObject:@{@"path" : savedJsonPath, @"includeData" : @YES}];
	}
	struct archive* write = archive_write_new();
	archive_write_set_format_zip(write);
	if (archive_write_open_filename(write, zipPath.fileSystemRepresentation) != ARCHIVE_OK) {
		NSLog(@"[EnterpriseLoader] Failed to open zip output: %@", zipPath);
		archive_write_free(write);
		return 1;
	}
	NSLog(@"[EnterpriseLoader] Now compressing %lu files", (unsigned long)files.count);
	for (NSDictionary* item in files) {
		NSString* path = item[@"path"];
		BOOL includeData = [item[@"includeData"] boolValue];
		if (addFileToArchiveEnt(write, path, docPath, includeData) < 0) {
			archive_write_close(write);
			archive_write_free(write);
			return 1;
		}
	}
	archive_write_close(write);
	archive_write_free(write);
	return 0;
}
