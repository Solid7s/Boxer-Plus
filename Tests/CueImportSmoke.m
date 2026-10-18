// Runs against the compiled app's actual scanner, image reader and drive bundler.
@import Cocoa;
#import "BXInstallerScan.h"
#import "BXFileTypes.h"
#import "BXDrive.h"
#import "BXDriveBundleImport.h"

static void Check(BOOL ok, NSString *message) {
    fprintf(ok ? stdout : stderr, "%s: %s\n", ok ? "PASS" : "FAIL", message.UTF8String);
    fflush(ok ? stdout : stderr);
    if (!ok) _Exit(1);
}

static BXInstallerScan *Scan(NSURL *url) {
    BXInstallerScan *scan = [NSClassFromString(@"BXInstallerScan") scanWithBasePath:url.path];
    [scan start];
    return scan;
}

static void Run(void) {
    NSURL *root = [NSURL fileURLWithPath:NSProcessInfo.processInfo.environment[@"BOXER_CUE_ROOT"]];
    Check([root.path containsString:@"/build/"], @"fixtures are isolated");
    for (NSString *name in @[@"cooked.cue", @"raw.cue", @"mixed.cue"])
    {
        NSURL *url = [root URLByAppendingPathComponent:name];
        BXInstallerScan *scan = Scan(url);
        Check(scan.succeeded && !scan.error, [NSString stringWithFormat:@"%@ scans without hdiutil: %@", name, scan.error]);
        Check(!scan.didMountVolume && scan.imageFilesystem != nil, @"uses direct disc reader");
        Check([scan.matchingPaths containsObject:@"INSTALL.COM"] && [scan.DOSExecutables containsObject:@"TOOLS/NESTED.COM"], @"DOS installers and subdirectories are scanned");
        Check([scan.windowsInstallers isEqual:@[@"SETUP.EXE"]], @"Windows setup classified from image bytes; uninstaller excluded");
        NSURL *logical = [scan.imageFilesystem logicalURLForPath:@"INSTALL.COM"];
        Check([logical isEqual:[url URLByAppendingPathComponent:@"INSTALL.COM"]], @"installer URL belongs to the cuesheet");
        Check([[scan.imageFilesystem pathForLogicalURL:logical] isEqual:@"/INSTALL.COM"], @"logical URL round trips");
        Check([[scan.imageFilesystem contentsOfFileAtPath:@"INSTALL.COM" error:NULL]
            isEqual:[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"Source/INSTALL.COM"]]], @"sector reader returns exact executable bytes");
    }

    BXInstallerScan *missing = Scan([root URLByAppendingPathComponent:@"missing.cue"]);
    Check(!missing.succeeded && missing.error != nil && missing.matchingPaths.count == 0, @"missing audio track fails before installer selection");
    BXInstallerScan *invalid = Scan([root URLByAppendingPathComponent:@"invalid.cue"]);
    Check(!invalid.succeeded && invalid.error != nil, @"invalid cuesheet fails with an error");

    NSURL *mixed = [root URLByAppendingPathComponent:@"mixed.cue"];
    BXDrive *drive = [NSClassFromString(@"BXDrive") driveWithContentsOfURL:mixed letter:@"D" type:BXDriveCDROM];
    BXDriveBundleImport *bundle = [[NSClassFromString(@"BXDriveBundleImport") alloc] initForDrive:drive
        destinationFolderURL:[root URLByAppendingPathComponent:@"Bundled"] copyFiles:YES];
    [bundle start];
    Check(bundle.succeeded && !bundle.error, [NSString stringWithFormat:@"CUE/BIN/audio bundling succeeds: %@", bundle.error]);
    for (NSString *name in @[@"track.bin", @"audio.bin"])
        Check([[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:name]]
            isEqual:[NSData dataWithContentsOfURL:[bundle.destinationURL URLByAppendingPathComponent:name]]],
            [NSString stringWithFormat:@"%@ preserved byte for byte", name]);
    BXInstallerScan *bundled = Scan([bundle.destinationURL URLByAppendingPathComponent:@"tracks.cue"]);
    Check(bundled.succeeded && [bundled.matchingPaths containsObject:@"INSTALL.COM"], @"bundled disc reopens with its relative track paths");
    _Exit(0);
}

__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                @try { Run(); } @catch (NSException *error) { Check(NO, error.description); }
            }];
    }
}
