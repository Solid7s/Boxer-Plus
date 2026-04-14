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

#import "ADBImageAwareFileScan.h"
#import "NSWorkspace+ADBMountedVolumes.h"
#import "NSWorkspace+ADBFileTypes.h"
#import "ADBBinCueImage.h"
#import "BXFileTypes.h"
#import "ADBFilesystem.h"


@implementation ADBImageAwareFileScan
@synthesize mountedVolumePath = _mountedVolumePath;
@synthesize ejectAfterScanning = _ejectAfterScanning;
@synthesize didMountVolume = _didMountVolume;
@synthesize cueImageFilesystem = _cueImageFilesystem;

- (id) init
{
    if ((self = [super init]))
    {
        self.ejectAfterScanning = ADBFileScanEjectIfSelfMounted;
    }
    return self;
}

- (NSString *) fullPathFromRelativePath: (NSString *)relativePath
{
    //Return paths relative to the mounted volume instead, if available.
    NSString *filesystemRoot = (self.mountedVolumePath) ? self.mountedVolumePath : self.basePath;
    return [filesystemRoot stringByAppendingPathComponent: relativePath];
}

//If we have a mounted volume path for an image, enumerate that instead of the original base path
- (NSDirectoryEnumerator *) enumerator
{
    if (self.mountedVolumePath)
        return [_manager enumeratorAtPath: self.mountedVolumePath];
    else return [super enumerator];
}

//Returns an ADBFilesystemPathEnumeration for CUE image filesystems
- (id <ADBFilesystemPathEnumeration>) imageFilesystemEnumerator
{
    if (self.cueImageFilesystem)
        return [self.cueImageFilesystem enumeratorAtPath: @"/" options: 0 errorHandler: nil];
    return nil;
}

//Split the work up into separate stages for easier overriding in subclasses.
- (void) main
{
    [self mountVolumesForScan];
    if (!self.isCancelled)
        [self performScan];
    [self unmountVolumesForScan];
}

- (void) performScan
{
    //If we have a CUE image filesystem, enumerate it using the image's own enumerator
    if (self.cueImageFilesystem)
    {
        [self performScanOfCueImageFilesystem];
    }
    else
    {
        [super main];
    }
}

//Performs a scan of the CUE image filesystem using ADBBinCueImage's enumerator
- (void) performScanOfCueImageFilesystem
{
    NSAssert(self.basePath != nil, @"No base path provided for file scan operation.");
    if (self.basePath == nil)
        return;
    
    [_matchingPaths removeAllObjects];
    
    id <ADBFilesystemPathEnumeration> enumerator = [self.cueImageFilesystem enumeratorAtPath: @"/" 
                                                                                     options: 0 
                                                                                errorHandler: nil];
    
    NSString *relativePath;
    while ((relativePath = [enumerator nextObject]) != nil)
    {
        BOOL keepScanning;
        if (self.isCancelled) break;
        
        @autoreleasepool {
            
            //Check if this is a directory by looking at file attributes
            BOOL isDirectory = NO;
            [self.cueImageFilesystem fileExistsAtPath: relativePath isDirectory: &isDirectory];
            
            if (isDirectory)
            {
                if (![self shouldScanSubpath: relativePath])
                    [enumerator skipDescendants];
            }
            
            keepScanning = [self matchAgainstPath: relativePath];
        }
        
        if (self.isCancelled || !keepScanning) break;
    }
}

- (void) mountVolumesForScan
{
    NSString *volumePath = nil;
    _didMountVolume = NO;
    
    NSURL *baseURL = [NSURL fileURLWithPath: self.basePath];
    NSString *extension = baseURL.pathExtension.lowercaseString;
    
    //Check if this is a CUE sheet that needs special handling
    if ([extension isEqualToString: @"cue"] || [extension isEqualToString: @"inst"] ||
        [_workspace file: self.basePath matchesTypes: [NSSet setWithObject: BXCuesheetImageType]])
    {
        //CUE files cannot be mounted by hdiutil, so we use ADBBinCueImage to read them directly
        NSError *imageError = nil;
        ADBBinCueImage *cueImage = [ADBBinCueImage imageWithContentsOfURL: baseURL error: &imageError];
        
        if (cueImage)
        {
            self.cueImageFilesystem = cueImage;
            //Note: didMountVolume stays NO since we didn't mount anything
        }
        else
        {
            self.error = imageError;
            [self cancel];
        }
        return;
    }
    
    //If the target path is on a disk image, then mount the image for scanning
    if ([_workspace file: self.basePath matchesTypes: [NSSet setWithObject: @"public.disk-image"]])
    {
        //First, check if the image is already mounted
        volumePath = [[[_workspace mountedVolumeURLsForSourceImageAtURL: baseURL] firstObject] path];
        
        //If it's not mounted yet, mount it ourselves
        if (!volumePath)
        {
            NSError *mountError = nil;
            ADBImageMountingOptions options = ADBMountReadOnly | ADBMountInvisible;
            NSArray<NSURL *> *images = [_workspace mountImageAtURL: baseURL
                                                           options: options
                                                             error: &mountError];
            
            if (images.count > 0)
            {
                _didMountVolume = YES;
                volumePath = [images.firstObject path];
            }
            //If we couldn't mount the image, give up in failure
            else
            {
                self.error = mountError;
                [self cancel];
                return;
            }
        }
        
        self.mountedVolumePath = volumePath;
    }
}

- (void) unmountVolumesForScan
{
    //If we mounted a volume ourselves in order to scan it,
    //or we've been told to always eject, then unmount the volume
    //once we're done
    if (self.mountedVolumePath)
    {
        if ((self.ejectAfterScanning == ADBFileScanAlwaysEject) ||
            (_didMountVolume && self.ejectAfterScanning == ADBFileScanEjectIfSelfMounted))
        {
            [_workspace unmountAndEjectDeviceAtPath: self.mountedVolumePath];
            self.mountedVolumePath = nil;
        }
    }
    
    //Clean up the CUE image filesystem if we were using one
    if (self.cueImageFilesystem)
    {
        self.cueImageFilesystem = nil;
    }
}

@end
