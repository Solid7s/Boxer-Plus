/*
 *  Copyright (c) 2013, Alun Bestor (alun.bestor@gmail.com)
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification,
 *  are permitted provided that the following conditions are met:
 *
 *		Redistributions of source code must retain the above copyright notice, this
 *	    list of conditions and the following disclaimer.
 *
 *		Redistributions in binary form must reproduce the above copyright notice,
 *	    this list of conditions and the following disclaimer in the documentation
 *      and/or other materials provided with the distribution.
 *
 *	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 *	IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 *	INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 *	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
 *	OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 *	WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *	ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *	POSSIBILITY OF SUCH DAMAGE.
 */


#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// @c ADBPathEnumerator is an @c NSDirectoryEnumerator wrapper with a bunch of convenience methods
/// for filtering out unwanted files.
@interface ADBPathEnumerator : NSEnumerator<NSString*>
{
	NSDirectoryEnumerator<NSString*> *_enumerator;
	BOOL _skipHiddenFiles;
	BOOL _skipSubdirectories;
	BOOL _skipPackageContents;
	NSSet *_fileTypes;
    NSPredicate *_predicate;
    
	NSString *_basePath;
	NSString *_currentPath;
	NSString *_relativePath;
	
	NSFileManager *_manager;
	NSWorkspace *_workspace;
}

#pragma mark -
#pragma mark Properties

/// The enumerator we use internally for iterating the directory contents.
@property (readonly, strong, nonatomic, nullable) NSDirectoryEnumerator<NSString*> *enumerator;

/// The base path to iterate. Should not be modified during iteration.
@property (copy, nonatomic, nullable) NSString *basePath;

/// The full path of the last file returned by nextObject.
@property (readonly, copy, nonatomic, nullable) NSString *currentPath;

/// The path of the last file returned by nextObject, relative to basePath.
@property (readonly, copy, nonatomic, nullable) NSString *relativePath;

/// Whether nextObject should ignore hidden files. Is @c YES by default.
@property (assign, nonatomic) BOOL skipHiddenFiles;

/// Whether nextObject should only enumerate the base path, skipping all subdirectories. Is @c NO by default.
@property (assign, nonatomic) BOOL skipSubdirectories;

/// Whether nextObject should skip over files located in packages (the packages themselves will still be returned.) Is @c NO by default.
@property (assign, nonatomic) BOOL skipPackageContents;

/// What UTI filetypes nextObject will return. If nil, files of any type will be returned.
@property (copy, nonatomic, nullable) NSSet<NSString*> *fileTypes;

/// If specified, only files whose paths match this predicate will be returned.
@property (copy, nonatomic, nullable) NSPredicate *predicate;


/// Passthroughs for @c NSDirectoryEnumerator methods.
@property (copy, readonly, nonatomic, nullable) NSDictionary<NSFileAttributeKey, id> *fileAttributes;
@property (copy, readonly, nonatomic, nullable) NSDictionary<NSFileAttributeKey, id> *directoryAttributes;


#pragma mark -
#pragma mark Methods

/// Return a new autoreleased enumerator for the specified file path.
+ (instancetype) enumeratorAtPath: (NSString *)filePath NS_SWIFT_UNAVAILABLE("");

/// Initialise a new emulator for the specified file path.
- (instancetype) initWithPath: (NSString *)filePath;

/// Passthroughs for @c NSDirectoryEnumerator methods.
- (void) skipDescendants;

@end

NS_ASSUME_NONNULL_END
