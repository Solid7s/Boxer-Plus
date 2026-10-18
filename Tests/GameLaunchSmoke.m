// Opens an installed DOS game in a fresh process and captures its real guest frame.
@import Cocoa;
#import "BXSession.h"
#import "BXGamebox.h"
#import "BXEmulator.h"
#import "BXEmulator+BXDOSFileSystem.h"
#import "BXEmulatedKeyboard.h"
#import "BXDrive.h"
#import "BXDOSWindowController.h"
#import "BXVideoFrame.h"

static BXSession *session;
static BOOL finished;
static void Check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); fflush(stderr); _Exit(1); }
}
static void Start(void) {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *root = env[@"BOXER_LAUNCH_ROOT"];
    NSURL *program = [NSURL fileURLWithPath:env[@"BOXER_LAUNCH_PROGRAM"]];
    Check([root containsString:@"/boxer-work/build/"] && [program.path containsString:@"/boxer-work/build/"], "test remains in disposable build folders");
    [NSDocumentController.sharedDocumentController openDocumentWithContentsOfURL:program display:YES
        completionHandler:^(NSDocument *document, BOOL opened, NSError *error) {
            if (error) NSLog(@"Open failed: %@", error);
            Check(document && !error, "installed executable opens its enclosing gamebox");
            session = (id)document;
        }];
    __block NSUInteger ticks = 0, commandIndex = 0;
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        ticks++;
        BXVideoFrame *frame = session.DOSWindowController.renderingView.currentFrame;
        if (frame) {
            Check(frame.bytesPerPixel == 4, "capture expects BGRA");
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:frame.size.width
                pixelsHigh:frame.size.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                bytesPerRow:frame.pitch bitsPerPixel:32];
            const unsigned char *bytes = frame.bytes;
            for (NSUInteger i=0; i<frame.pitch*(NSUInteger)frame.size.height; i+=4) {
                rep.bitmapData[i]=bytes[i+2]; rep.bitmapData[i+1]=bytes[i+1]; rep.bitmapData[i+2]=bytes[i]; rep.bitmapData[i+3]=255;
            }
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:[root stringByAppendingPathComponent:@"guest.png"] atomically:YES];
        }
        if (ticks == 8) {
            Check(session.gamebox && session.emulator.isRunningActiveProcess && frame, "fresh gamebox launch is running with a rendered frame");
            BOOL bundledDisc = NO;
            for (BXDrive *drive in session.emulator.mountedDrives) if (drive.type == BXDriveCDROM) {
                Check([drive.sourceURL.path hasPrefix:session.gamebox.bundleURL.path], "CD uses the copy inside the gamebox");
                bundledDisc = YES;
            }
            Check(bundledDisc, "bundled CD is mounted after reopening");
            NSLog(@"Launched %@ with drives %@", session.targetURL, session.emulator.mountedDrives);
            fprintf(stdout, "PASS: installed game runs in a fresh process with its bundled disc\n"); fflush(stdout);
        }
        NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"commands.json"]];
        NSArray *commands = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (ticks < 8 || commandIndex >= commands.count) return;
        NSString *command = commands[commandIndex++];
        if ([command isEqual:@"close"]) { finished=YES; [timer invalidate]; [session.windowForSheet performClose:nil]; }
        else if ([command isEqual:@"enter"]) [session.emulator.keyboard keyPressed:KBD_enter];
        else if ([command isEqual:@"escape"]) [session.emulator.keyboard keyPressed:KBD_esc];
        else [session.emulator.keyboard typeCharacters:command];
    }];
}
__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil
            usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ Start(); }); }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil
            usingBlock:^(NSNotification *note) { Check(finished, "game does not exit before the test finishes");
                fprintf(stdout, "PASS: game window requests application exit\n"); fflush(stdout); }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            fprintf(stderr, "FAIL: game launch test timed out\n"); fflush(stderr); _Exit(2);
        });
    }
}
