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


#import "ADBSingleFileTransfer.h"
#include <copyfile.h>

#pragma mark -
#pragma mark Notification constants and keys

NSString * const ADBFileTransferFilesTotalKey		= @"ADBFileTransferFilesTotalKey";
NSString * const ADBFileTransferFilesTransferredKey	= @"ADBFileTransferFilesTransferredKey";
NSString * const ADBFileTransferBytesTotalKey		= @"ADBFileTransferBytesTotalKey";
NSString * const ADBFileTransferBytesTransferredKey	= @"ADBFileTransferBytesTransferredKey";
NSString * const ADBFileTransferCurrentPathKey		= @"ADBFileTransferCurrentPathKey";



#pragma mark -
#pragma mark Private method declarations

@interface ADBSingleFileTransfer ()

@property (readwrite) unsigned long long numBytes;
@property (readwrite) unsigned long long bytesTransferred;
@property (readwrite) NSUInteger numFiles;
@property (readwrite) NSUInteger filesTransferred;
@property (readwrite, copy) NSString *currentPath;

//Start up the FSFileOperation. Returns NO and populates @error if the transfer could not be started.
- (BOOL) _beginTransfer;

//Called periodically by a timer, to check the progress of the FSFileOperation.
- (void) _checkTransferProgress;

@end


#pragma mark -
#pragma mark Implementation

@implementation ADBSingleFileTransfer
{
    copyfile_state_t _copyState;
@package
	NSInteger _storedCurrentFileCount;
	NSString *_storedCurrentFile;
	BOOL _isDone;
}
@synthesize copyFiles = _copyFiles, pollInterval = _pollInterval;
@synthesize sourcePath = _sourcePath, destinationPath = _destinationPath, currentPath = _currentPath;
@synthesize numFiles = _numFiles, filesTransferred = _filesTransferred;
@synthesize numBytes = _numBytes, bytesTransferred = _bytesTransferred;

static int ADBSingleFileCallback(int what, int stage, copyfile_state_t state,
								 const char * src, const char * dst, void * ctx)
{
    ADBSingleFileTransfer *nsCtx = (__bridge ADBSingleFileTransfer *)(ctx);
    @synchronized(nsCtx) {
		if (nsCtx.cancelled) {
			return COPYFILE_QUIT;
			nsCtx->_isDone = YES;
		}
		switch (what) {
			case COPYFILE_RECURSE_FILE:
				nsCtx->_storedCurrentFileCount++;
				nsCtx->_storedCurrentFile = [nsCtx->_manager stringWithFileSystemRepresentation: src length: strlen(src)];
				break;
				
			case COPYFILE_RECURSE_ERROR:
				nsCtx.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
											  userInfo:@{NSFilePathErrorKey: [nsCtx->_manager stringWithFileSystemRepresentation: src length: strlen(src)]}];
				return COPYFILE_QUIT;
				break;
				
			default:
				break;
		}
		if (stage == COPYFILE_ERR) {
			return COPYFILE_QUIT;
		}
    }
    
    return COPYFILE_CONTINUE;
}

#pragma mark -
#pragma mark Initialization and deallocation

- (id) init
{
	if ((self = [super init]))
	{
        _copyState = copyfile_state_alloc();
        copyfile_state_set(_copyState, COPYFILE_STATE_STATUS_CB, &ADBSingleFileCallback);
        copyfile_state_set(_copyState, COPYFILE_STATE_STATUS_CTX, (__bridge CFTypeRef)(self));
		
		_pollInterval = ADBFileTransferDefaultPollInterval;
		
		//Maintain our own NSFileManager instance to ensure thread safety
		_manager = [[NSFileManager alloc] init];
	}
	return self;
}

- (id) initFromPath: (NSString *)sourcePath toPath: (NSString *)destinationPath copyFiles: (BOOL)copyFiles
{
	if ((self = [self init]))
	{
        self.sourcePath = sourcePath;
        self.destinationPath = destinationPath;
        self.copyFiles = copyFiles;
	}
	return self;
}

+ (id) transferFromPath: (NSString *)sourcePath toPath: (NSString *)destinationPath copyFiles: (BOOL)copyFiles
{
	return [[self alloc] initFromPath: sourcePath
								toPath: destinationPath
							 copyFiles: copyFiles];
}

- (void) dealloc
{
	copyfile_state_free(_copyState);
}


#pragma mark -
#pragma mark Performing the transfer

+ (NSSet *) keyPathsForValuesAffectingCurrentProgress
{
	return [NSSet setWithObjects: @"numBytes", @"bytesTransferred", nil];
}

- (ADBOperationProgress) currentProgress
{
	if (self.numBytes > 0)
	{
		return (ADBOperationProgress)self.bytesTransferred / (ADBOperationProgress)self.numBytes;		
	}
	else return 0;
}

+ (NSSet *) keyPathsForValuesAffectingIndeterminate
{
	return [NSSet setWithObject: @"numBytes"];
}

- (BOOL) isIndeterminate
{
	return self.numBytes == 0;
}

- (void) main
{
    NSAssert(self.sourcePath != nil, @"No source path provided for file transfer.");
    NSAssert(self.destinationPath != nil, @"No destination path provided for file transfer.");
    if (!self.sourcePath || !self.destinationPath)
        return;
    
    //IMPLEMENTATION NOTE: we used to check for the existence of the source path and the nonexistence
    //of the destination path before beginning, but this was redundant (the file operation would fail
    //under these circumstances anyway) and would lead to race conditions.
    
	//Start up the file transfer, bailing out if it could not be started
	if ([self _beginTransfer])
    {
        //Use a timer to poll the FSFileOperation. (This also keeps the runloop below alive.)
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: self.pollInterval
                                                          target: self
                                                        selector: @selector(_checkTransferProgress)
                                                        userInfo: NULL
                                                         repeats: YES];
        
        //Run the runloop until the transfer is finished, letting the timer call our polling function.
        //We use a runloop instead of just sleeping, because the runloop lets cancellation messages
        //get dispatched to us correctly.)
        while (_isDone == NO && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                                                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: self.pollInterval]])
        {
            //Cancel the file operation if we've been cancelled in the meantime
            //(this will break out of the loop once the file operation finishes)
            //if (self.isCancelled)
            //    FSFileOperationCancel(_fileOp);
        }
        
        [timer invalidate];
	}
}

- (BOOL) _beginTransfer
{
	NSString *destinationBase = self.destinationPath.stringByDeletingLastPathComponent;
	
	//If the destination base folder does not yet exist, create it and any intermediate directories
	if (![_manager fileExistsAtPath: destinationBase])
	{
		NSError *dirError = nil;
		BOOL created = [_manager createDirectoryAtPath: destinationBase
						   withIntermediateDirectories: YES
											attributes: nil
												 error: &dirError];
		if (created)
		{
			_hasCreatedFiles = YES;
		}
		else
		{
			self.error = dirError;
			return NO;
		}
	}
	
	const char *srcPath = self.sourcePath.fileSystemRepresentation;
	const char *destPath = self.destinationPath.fileSystemRepresentation;
	
	NSArray *contents = [_manager subpathsAtPath:self.sourcePath];
	unsigned long long fileSize = 0;
	//TODO: More accurate sizing.
	for (NSString *path in contents) {
		NSDictionary *fattrib = [_manager attributesOfItemAtPath:[self.sourcePath stringByAppendingPathComponent:path] error:nil];
		fileSize +=[fattrib fileSize];
	}
	self.numBytes = fileSize;
	//TODO: more accurate counting
	self.numFiles = contents.count;

	copyfile_flags_t copyFlags = COPYFILE_RECURSIVE;
	if (self.copyFiles) {
		copyFlags |= COPYFILE_CLONE;
	} else {
		copyFlags |= COPYFILE_ALL | COPYFILE_MOVE;
	}
	_isDone = NO;
	dispatch_async(dispatch_get_global_queue(0, 0), ^{
		if (copyfile(srcPath, destPath, self->_copyState, copyFlags) != 0) {
			if (errno != ECANCELED) {
				self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			}
		}
		self->_isDone = YES;
	});
	
	return YES;
}

- (BOOL) undoTransfer
{
	//Delete the destination path to clean up
	//TODO: for move operations, we should put the files back.
	if (_hasCreatedFiles && self.copyFiles)
	{
		return [_manager removeItemAtPath: self.destinationPath error: nil];
	}
    else return NO;
}

- (void) _checkTransferProgress
{	
	off_t copybytesTransferred = 0;
	
	int status = copyfile_state_get(_copyState, COPYFILE_STATE_COPIED, &copybytesTransferred);
	
	//NSAssert1(!status, @"Could not get file operation status, FSPathFileOperationCopyStatus returned error code: %i", status);
	if (_storedCurrentFile)
	{
		@synchronized(self) {
			self.currentPath = _storedCurrentFile;
		}
	}
    
	if (status != 0 && errno != ECANCELED && _currentPath)
	{
        NSDictionary *info = (self.currentPath) ? @{ NSFilePathErrorKey: self.currentPath } : nil;
		self.error = [NSError errorWithDomain: NSPOSIXErrorDomain code: errno userInfo: info];
	}
	
	//self.numBytes           = bytes.unsignedLongLongValue;
	self.bytesTransferred   = copybytesTransferred;
	//self.numFiles           = files.unsignedIntegerValue;
	self.filesTransferred   = _storedCurrentFileCount;

	
	if (!_isDone)
	{
		NSDictionary *info = @{
            ADBFileTransferFilesTransferredKey: @(self.filesTransferred),
            ADBFileTransferBytesTransferredKey: @(self.bytesTransferred),
            ADBFileTransferFilesTotalKey:       @(self.numFiles),
            ADBFileTransferBytesTotalKey:       @(self.numBytes),
            ADBFileTransferCurrentPathKey:      self.currentPath,
        };
        
		[self _sendInProgressNotificationWithInfo: info];
	}
	
	//Make a note that we have actually copied/moved any data, in case we need to clean up later
	if (self.bytesTransferred > 0)
        _hasCreatedFiles = YES;
}

@end
