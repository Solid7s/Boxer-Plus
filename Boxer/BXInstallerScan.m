/*
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXInstallerScan.h"
#import "BXImportSession+BXImportPolicies.h"

#import "RegexKitLite.h"
#import "NSWorkspace+ADBFileTypes.h"
#import "NSWorkspace+ADBMountedVolumes.h"
#import "NSString+ADBPaths.h"
#import "BXFileTypes.h"
#import "BXSessionError.h"
#import "ADBBinCueImage.h"

@interface BXInstallerScan ()

@property (readwrite, copy, nonatomic) NSArray<NSString*> *windowsExecutables;
@property (readwrite, copy, nonatomic) NSArray<NSString*> *DOSExecutables;
@property (readwrite, copy, nonatomic) NSArray<NSString*> *DOSBoxConfigurations;
@property (readwrite, copy, nonatomic) NSArray<NSString*> *macOSApps;
@property (readwrite, strong, nonatomic) BXGameProfile *detectedProfile;
@property (readwrite, nonatomic, getter=isAlreadyInstalled) BOOL alreadyInstalled;
@property (readwrite, copy, nonatomic) NSString *preferredWindowsInstaller;

/// Helper methods for adding executables to their appropriate match arrays,
/// a la addMatchingPath:
- (void) addWindowsExecutable: (NSString *)relativePath;
- (void) addDOSExecutable: (NSString *)relativePath;
- (void) addMacOSApp: (NSString *)relativePath;
- (void) addDOSBoxConfiguration: (NSString *)relativePath;

/// Returns whether the path looks like a Windows installer
- (BOOL) isWindowsInstallerAtPath: (NSString *)relativePath;

@end

@implementation BXInstallerScan

- (id) init
{
    if ((self = [super init]))
    {
        self.windowsExecutables     = [NSMutableArray arrayWithCapacity: 10];
        self.DOSExecutables         = [NSMutableArray arrayWithCapacity: 10];
        self.macOSApps              = [NSMutableArray arrayWithCapacity: 10];
        self.DOSBoxConfigurations   = [NSMutableArray arrayWithCapacity: 2];
    }
    return self;
}

//Override isMatchingPath: to handle file type checking for CUE images
- (BOOL) isMatchingPath: (NSString *)relativePath
{
    if (self.skipHiddenFiles && [relativePath.lastPathComponent hasPrefix: @"."]) return NO;
    
    if (self.predicate && ![self.predicate evaluateWithObject: relativePath]) return NO;
    
    if (self.fileTypes)
    {
        //For CUE images, use the image filesystem to check file types
        if (self.cueImageFilesystem)
        {
            NSString *matchingType = [self.cueImageFilesystem typeOfFileAtPath: relativePath matchingTypes: self.fileTypes];
            if (!matchingType) return NO;
        }
        else
        {
            NSString *fullPath = [self fullPathFromRelativePath: relativePath];
            if (![_workspace file: fullPath matchesTypes: self.fileTypes]) return NO;
        }
    }
    
    return YES;
}

//Helper method to check if a file matches executable types, using either NSWorkspace
//(for regular files) or the CUE image filesystem (for CUE/BIN images)
- (BOOL) fileAtPathMatchesExecutableTypes: (NSString *)path
{
    NSSet *executableTypes = [BXFileTypes executableTypes];
    
    //If we have a CUE image filesystem, use it to check the file type
    if (self.cueImageFilesystem)
    {
        NSString *matchingType = [self.cueImageFilesystem typeOfFileAtPath: path matchingTypes: executableTypes];
        return matchingType != nil;
    }
    else
    {
        //Otherwise, use the standard NSWorkspace method
        NSString *fullPath = [self fullPathFromRelativePath: path];
        return [_workspace file: fullPath matchesTypes: executableTypes];
    }
}

//Helper method to check if a file matches Mac app types
- (BOOL) fileAtPathMatchesMacAppTypes: (NSString *)path
{
    NSSet *macAppTypes = [BXFileTypes macOSAppTypes];
    
    //CUE images don't contain Mac apps, so always return NO for CUE filesystems
    if (self.cueImageFilesystem)
    {
        return NO;
    }
    else
    {
        NSString *fullPath = [self fullPathFromRelativePath: path];
        return [_workspace file: fullPath matchesTypes: macAppTypes];
    }
}

//Overridden to gather additional data besides just matching installers.
- (BOOL) matchAgainstPath: (NSString *)relativePath
{
    //Filter out files that don't match BXFileScan's basic tests
    //(Basically this just filters out hidden files.)
    if ([self isMatchingPath: relativePath])
    {   
        if ([BXImportSession isIgnoredFileAtPath: relativePath]) return YES;
        
        NSString *fullPath = [self fullPathFromRelativePath: relativePath];
        
        //Check for DOSBox configuration files.
        //For CUE images, check using the image filesystem
        if (self.cueImageFilesystem)
        {
            //Check if file extension is .conf for CUE images
            if ([relativePath.pathExtension.lowercaseString isEqualToString: @"conf"])
            {
                [self addDOSBoxConfiguration: relativePath];
            }
        }
        else if ([BXImportSession isConfigurationFileAtPath: fullPath])
        {
            [self addDOSBoxConfiguration: relativePath];
        }
        
        //Check for telltales that indicate an already-installed game, but keep scanning even if we find one.
        if (!self.isAlreadyInstalled && [BXImportSession isPlayableGameTelltaleAtPath: relativePath])
        {
            self.alreadyInstalled = YES;
        }
        
        if ([self fileAtPathMatchesExecutableTypes: relativePath])
        {
            //For CUE images, we can't use NSURL-based executable checking
            //Instead, check by extension and assume .COM/.BAT are DOS-compatible
            BOOL isCompatible = NO;
            if (self.cueImageFilesystem)
            {
                NSString *extension = relativePath.pathExtension.lowercaseString;
                isCompatible = [extension isEqualToString: @"com"] || 
                               [extension isEqualToString: @"bat"] ||
                               ([extension isEqualToString: @"exe"] && 
                                [BXFileTypes isCompatibleExecutableAtPath: relativePath
                                                               filesystem: self.cueImageFilesystem
                                                                    error: NULL]);
            }
            else
            {
                isCompatible = [BXFileTypes isCompatibleExecutableAtURL: [NSURL fileURLWithPath: fullPath] error: NULL];
            }
            
			if (isCompatible)
            {
                [self addDOSExecutable: relativePath];
                
                //If this looks like an installer to us, finally add it into our list of matches
                if ([BXImportSession isInstallerAtPath: relativePath] && ![self.detectedProfile isIgnoredInstallerAtPath: relativePath])
                {
                    [self addMatchingPath: relativePath];
                    
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObject: self.lastMatch
                                                                         forKey: ADBFileScanLastMatchKey];
                    
                    [self _sendInProgressNotificationWithInfo: userInfo];
                }
            }
            //Check if this Windows executable is an installer we should run
            else
            {
                [self addWindowsExecutable: relativePath];
                
                //If it looks like a Windows installer, track it as a potential installer
                if ([self isWindowsInstallerAtPath: relativePath])
                {
                    NSLog(@"[BXInstallerScan] Found Windows installer: %@", relativePath);
                    [self addMatchingPath: relativePath];
                    
                    //If we haven't found a preferred Windows installer yet, or this one
                    //is in the root directory, prefer it
                    if (!self.preferredWindowsInstaller ||
                        relativePath.pathComponents.count <= self.preferredWindowsInstaller.pathComponents.count)
                    {
                        self.preferredWindowsInstaller = relativePath;
                    }
                    
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObject: self.lastMatch
                                                                         forKey: ADBFileScanLastMatchKey];
                    
                    [self _sendInProgressNotificationWithInfo: userInfo];
                }
            }
        }
        else if ([self fileAtPathMatchesMacAppTypes: relativePath])
        {
            [self addMacOSApp: relativePath];
        }
    }
    
    return YES;
}

- (void) addWindowsExecutable: (NSString *)relativePath
{
    [[self mutableArrayValueForKey: @"windowsExecutables"] addObject: relativePath];
}

- (void) addDOSExecutable: (NSString *)relativePath
{
    [[self mutableArrayValueForKey: @"DOSExecutables"] addObject: relativePath];
}

- (void) addMacOSApp: (NSString *)relativePath
{
    [[self mutableArrayValueForKey: @"macOSApps"] addObject: relativePath];
}


- (void) addDOSBoxConfiguration: (NSString *)relativePath
{
    [[self mutableArrayValueForKey: @"DOSBoxConfigurations"] addObject: relativePath];
}

- (BOOL) isWindowsInstallerAtPath: (NSString *)relativePath
{
    NSString *fileName = relativePath.lastPathComponent.lowercaseString;
    
    //Common Windows installer patterns
    NSSet *installerPatterns = [NSSet setWithObjects:
        @"^setup\\.exe$",
        @"^install\\.exe$",
        @"^inst\\.exe$",
        @"^setup32\\.exe$",
        @"^install32\\.exe$",
        @"^winsetup\\.exe$",
        @"^wininstall\\.exe$",
        @"^.*_setup\\.exe$",
        @"^.*_install\\.exe$",
        nil];
    
    for (NSString *pattern in installerPatterns)
    {
        if ([fileName isMatchedByRegex: pattern
                               options: RKLCaseless
                               inRange: NSMakeRange(0, fileName.length)
                                 error: NULL])
        {
            return YES;
        }
    }
    
    return NO;
}

- (NSString *) recommendedSourcePath
{
    //If we mounted a volume to scan it, recommend the mounted volume as the source to use.
    if (self.mountedVolumePath)
    {
        return self.mountedVolumePath;
    }
    else return self.basePath;
}

+ (NSSet *) keyPathsForValuesAffectingRecommendedSourcePath
{
    return [NSSet setWithObjects: @"basePath", @"mountedVolumePath", nil];
}

- (void) performScan
{
    //Detect the game profile before we start.
    if (!self.detectedProfile)
    {
        //If we are scanning a mounted image, scan the mounted volume path for the game profile
        //instead of the base image path.
        NSString *profileScanPath = (self.mountedVolumePath) ? self.mountedVolumePath : self.basePath;

        //IMPLEMENTATION NOTE: detectedProfileForPath:searchSubfolders: trawls the same
        //directory structure as our own installer scan, so it would be more efficient
        //to do profile detection in the same loop as installer detection.
        //However, profile detection relies on iterating the same file structure multiple
        //times in order to scan for different profile 'priorities' so this isn't an option.
        //Also, it appears OS X's directory enumerator caches the result of a directory
        //scan so that subsequent reiterations do not do disk I/O.
        BXGameProfile *profile = [BXGameProfile detectedProfileForPath: profileScanPath
                                                      searchSubfolders: YES];

        self.detectedProfile = profile;
    }

    [super performScan];

    if (!self.error)
    {
        //If we discovered windows executables (or Mac apps) as well as DOS programs,
        //check the DOS programs more thoroughly to make sure they indicate a complete DOS game
        //(and not just some leftover batch files or utilities.)
        BOOL isConclusivelyDOS = (self.DOSExecutables.count > 0);
        if (isConclusivelyDOS && (self.windowsExecutables.count || self.macOSApps.count))
        {
            isConclusivelyDOS = NO;
            for (NSString *path in self.DOSExecutables)
            {
                //Forgive the double-negative, but it's quicker to test files for inconclusiveness
                //than for conclusiveness, so the method makes more sense with this phrasing.
                if (![BXImportSession isInconclusiveDOSProgramAtPath: path])
                {
                    isConclusivelyDOS = YES;
                    break;
                }
            }
        }

        //If this really is a DOS game, determine a preferred installer from among those discovered
        //in the scan (if any).
        if (isConclusivelyDOS)
        {
            NSString *preferredInstallerPath = nil;

            if (self.detectedProfile)
            {
                //Check through all the DOS executables in order of path depth, to see
                //if any of them match the game profile's idea of a preferred installer:
                //if so, we'll add it to the list of installers (if it's not already there)
                //and use it as the preferred one.
                for (NSString *relativePath in [self.DOSExecutables sortedArrayUsingSelector: @selector(pathDepthCompare:)])
                {
                    if ([self.detectedProfile isDesignatedInstallerAtPath: relativePath])
                    {
                        preferredInstallerPath = relativePath;
                        break;
                    }
                }
            }

            [self willChangeValueForKey: @"matchingPaths"];

            //Sort the installers we found by depth, to prioritise the ones in the root directory.
            [_matchingPaths sortUsingSelector: @selector(pathDepthCompare:)];

            //If the game profile didn't suggest a preferred installer,
            //then pick one from the set of discovered installers
            if (!preferredInstallerPath)
            {
                preferredInstallerPath = [BXImportSession preferredInstallerFromPaths: _matchingPaths];
            }

            //Bump the preferred installer up to the first entry in the list of installers.
            if (preferredInstallerPath)
            {
                [_matchingPaths removeObject: preferredInstallerPath];
                [_matchingPaths insertObject: preferredInstallerPath atIndex: 0];
            }

            [self didChangeValueForKey: @"matchingPaths"];
        }

        //If we didn't find any DOS executables and couldn't identify this as a known game,
        //then this isn't a game we can import and we should reject it.

        //IMPLEMENTATION NOTE: if we didn't find any DOS executables, but *did* identify
        //a profile for the game, then we give the game the benefit of the doubt.
        //This case normally indicates that the game is preinstalled and the game files
        //are just buried away on a disc image inside the source folder.
        //(e.g. GOG releases of Wing Commander 3 and Ultima Underworld 1 & 2.)

        else if (!self.DOSBoxConfigurations.count && !(self.isAlreadyInstalled && self.detectedProfile))
        {
            NSURL *baseURL = [NSURL fileURLWithPath: self.basePath];
            
            //If we found a Windows installer, allow the import to proceed
            //(Windows 3.11 will be pre-installed and the installer will run with "win")
            if (self.preferredWindowsInstaller)
            {
                NSLog(@"[BXInstallerScan] Allowing Windows installer import: %@", self.preferredWindowsInstaller);
                //Don't set an error - let the import proceed
            }
            //If there were windows executables present but no installer, this is probably a Windows-only game.
            else if (self.windowsExecutables.count > 0)
            {
                self.error = [BXImportWindowsOnlyError errorWithSourceURL: baseURL userInfo: nil];
            }

            //If there were classic Mac OS/OS X apps present, this is probably a Mac game.
            else if (self.macOSApps.count > 0)
            {
                //Check if it may be a hybrid-mode CD, in which case we'll show
                //a different set of advice to the user.

                BOOL isHybridCD = [_workspace isHybridCDAtURL: [NSURL fileURLWithPath: self.basePath]];
                Class errorClass = isHybridCD ? [BXImportHybridCDError class] : [BXImportMacAppError class];

                self.error = [errorClass errorWithSourceURL: baseURL userInfo: nil];
            }
            //Otherwise, the folder may be empty or contains something other than a DOS game.
            //TODO: additional logic to detect Classic Mac games.
            else
            {
                self.error = [BXImportNoExecutablesError errorWithSourceURL: baseURL userInfo: nil];
            }
        }
    }
}

@end
