// Drives the existing Windows chooser and guest keyboard in a disposable gamebox.
@import Cocoa;
#import "BXSession.h"
#import "BXSession+BXUIControls.h"
#import "BXGamebox.h"
#import "BXEmulator.h"
#import "BXEmulatedKeyboard.h"
#import "BXDOSWindowController.h"
#import "BXVideoFrame.h"

static BXSession *session;
static BOOL finished;
static NSUInteger commandIndex;

static void Check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); fflush(stderr); _Exit(1); }
}
static NSView *Find(NSView *view, Class type, NSString *label) {
    if ([view isKindOfClass:type] && ([view.accessibilityLabel isEqual:label] ||
        ([view respondsToSelector:@selector(title)] && [[(id)view title] isEqual:label]))) return view;
    for (NSView *child in view.subviews) { NSView *found = Find(child, type, label); if (found) return found; }
    return nil;
}
static void Capture(NSString *root) {
    BXVideoFrame *frame = session.DOSWindowController.renderingView.currentFrame;
    if (!frame) return;
    Check(frame.bytesPerPixel == 4, "capture expects the renderer's BGRA framebuffer");
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:frame.size.width pixelsHigh:frame.size.height bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
        bytesPerRow:frame.pitch bitsPerPixel:32];
    const unsigned char *pixels = frame.bytes;
    for (NSUInteger i = 0; i < frame.pitch * (NSUInteger)frame.size.height; i += 4) {
        rep.bitmapData[i] = pixels[i + 2];
        rep.bitmapData[i + 1] = pixels[i + 1];
        rep.bitmapData[i + 2] = pixels[i];
        rep.bitmapData[i + 3] = 255;
    }
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[root stringByAppendingPathComponent:@"guest.png"] atomically:YES];
}
static void Start(void) {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *root = env[@"BOXER_WINDOWS_TEST_ROOT"];
    NSString *program = env[@"BOXER_WINDOWS_PROGRAM"];
    BOOL choosing = [env[@"BOXER_WINDOWS_PHASE"] isEqual:@"choose"];
    Check([root containsString:@"/build/Windows-"], "test uses an isolated gamebox");
    NSURL *gameURL = [NSURL fileURLWithPath:env[@"BOXER_WINDOWS_GAME"] ?: [root stringByAppendingPathComponent:@"Test.boxer"]];
    Check([gameURL.path containsString:@"/boxer-work/build/"], "Windows test game stays under build");
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:gameURL display:YES
        completionHandler:^(NSDocument *doc, BOOL alreadyOpen, NSError *error) {
            if (error) NSLog(@"Windows test open error: %@", error);
            Check(doc && !error, "copied Windows gamebox opens"); session = (id)doc;
            [NSApp activateIgnoringOtherApps:YES];
        }];
    __block NSUInteger ticks = 0;
    __block BOOL saved = NO;
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        ticks++;
        if (choosing) {
            Check(ticks <= 30, "requested Windows program appears within 30 seconds");
            if (ticks == 4) [session chooseWindowsProgram:nil];
            if (ticks >= 5 && !saved) {
                NSView *view = session.windowForSheet.attachedSheet.contentView;
                NSPopUpButton *programs = (id)Find(view, NSPopUpButton.class, @"Game program:");
                if (![programs.itemTitles containsObject:program]) return;
                [programs selectItemWithTitle:program];
                [NSApp sendAction:programs.action to:programs.target from:programs];
                NSButton *save = (id)Find(view, NSButton.class, @"Save for Next Launch");
                Check(save.enabled, "Windows program is detected and valid in the existing chooser");
                [save performClick:nil]; saved = YES;
            } else if (saved && !session.windowForSheet.attachedSheet) {
                NSDictionary *launcher = session.gamebox.defaultLauncher;
                Check([launcher[@"BXLauncherArguments"] isEqual:program], "chooser saves the requested program");
                Check([launcher[@"BXLauncherPath"] isEqual:@"C.harddisk/WINDOWS/WIN.COM"], "chooser wraps setup through WIN.COM");
                NSLog(@"Saved Windows program launcher: %@", launcher);
                fprintf(stdout, "PASS: existing Windows chooser detects and saves the requested program\n"); fflush(stdout);
                finished = YES; [timer invalidate]; [session.windowForSheet performClose:nil];
            }
            return;
        }
        Capture(root);
        if (ticks == 8) {
            Check([session.targetArguments isEqual:program], "fresh launch uses the selected installer");
            Check(session.emulator.isRunningActiveProcess, "Windows is running");
            fprintf(stdout, "PASS: fresh process dispatches the selected program through Windows\n"); fflush(stdout);
        }
        NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"commands.json"]];
        NSArray *commands = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (ticks < 8 || commandIndex >= commands.count) return;
        NSString *command = commands[commandIndex++];
        NSLog(@"Windows test command: %@", command);
        if ([command isEqual:@"close"]) {
            finished = YES; [timer invalidate]; [session.windowForSheet performClose:nil];
        } else if ([command isEqual:@"enter"]) [session.emulator.keyboard keyPressed:KBD_enter];
        else if ([command isEqual:@"escape"]) [session.emulator.keyboard keyPressed:KBD_esc];
        else if ([command isEqual:@"tab"]) [session.emulator.keyboard keyPressed:KBD_tab];
        else if ([command isEqual:@"up"]) [session.emulator.keyboard keyPressed:KBD_up];
        else if ([command isEqual:@"down"]) [session.emulator.keyboard keyPressed:KBD_down];
        else if ([command isEqual:@"left"]) [session.emulator.keyboard keyPressed:KBD_left];
        else if ([command isEqual:@"right"]) [session.emulator.keyboard keyPressed:KBD_right];
        else [session.emulator.keyboard typeCharacters:command];
    }];
}
__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ Start(); }); }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                Check(finished, "test completes before app exit");
                fprintf(stdout, "PASS: Windows test closes normally\n"); fflush(stdout);
            }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            fprintf(stderr, "FAIL: Windows installer test timed out\n"); fflush(stderr); _Exit(2);
        });
    }
}
