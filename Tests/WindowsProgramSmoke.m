// Exercise the compiled picker, ISO discovery, cancellation and a fresh-process launch.
@import Cocoa;
#import <objc/runtime.h>
#import "BXEmulator+BXShell.h"
#import "BXEmulator+BXDOSFileSystem.h"
#import "BXSession.h"
#import "BXSession+BXUIControls.h"
#import "BXGamebox.h"
#import "BXEmulator.h"
#import "BXDOSWindowController.h"
#import "BXVideoFrame.h"

static BXSession *session;
static NSWindow *testCompanion;
static NSData *originalInfo;
static NSString *infoPath;
static BOOL finished, sawShortcutDirectory;

static void Check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); fflush(stderr); exit(1); }
}
static NSView *Find(NSView *view, Class type, NSString *label) {
    if ([view isKindOfClass:type] &&
        ([view.accessibilityLabel isEqual:label] ||
         ([view respondsToSelector:@selector(title)] && [[(id)view title] isEqual:label]))) return view;
    for (NSView *child in view.subviews) {
        NSView *found = Find(child, type, label);
        if (found) return found;
    }
    return nil;
}
static NSMenuItem *PickerItem(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(chooseWindowsProgram:)) return item;
        NSMenuItem *child = PickerItem(item.submenu);
        if (child) return child;
    }
    return nil;
}
static NSPopUpButton *Programs(void) {
    return (id)Find(session.windowForSheet.attachedSheet.contentView, NSPopUpButton.class, @"Game program:");
}
static void SelectShortcut(NSString *title) {
    NSMenuItem *match = nil;
    for (NSMenuItem *item in Programs().itemArray)
        if ([item.representedObject[@"shortcut"][@"title"] isEqual:title]) match = item;
    Check(match != nil, "shortcut is present by its Windows display name");
    [Programs() selectItem:match];
    [NSApp sendAction:Programs().action to:Programs().target from:Programs()];
    for (NSView *view in Programs().superview.subviews)
        if ([view isKindOfClass:NSTextField.class]) fprintf(stdout, "Picker: %s\n", [(NSTextField *)view stringValue].UTF8String);
    fflush(stdout);
}
static void Click(NSString *title) {
    NSButton *button = (id)Find(session.windowForSheet.attachedSheet.contentView, NSButton.class, title);
    Check(button && button.enabled, "expected sheet button is enabled");
    [button performClick:nil];
}
static void Start(void) {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *game = env[@"BOXER_TEST_GAME"];
    Check([game containsString:@"/build/"], "use an isolated gamebox");
    infoPath = [game stringByAppendingPathComponent:@"Game Info.plist"];
    originalInfo = [NSData dataWithContentsOfFile:infoPath];
    BOOL launch = [env[@"BOXER_PICKER_PHASE"] isEqual:@"launch"];
    NSUInteger launchSeconds = [env[@"BOXER_PICKER_SECONDS"] integerValue] ?: 120;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *key = [@"BXGameSettings: " stringByAppendingString:info[@"BXGameIdentifier"]];
    //Simulate an old installer being remembered even after selecting the real game.
    if (launch) {
        NSMutableDictionary *settings = [[NSUserDefaults.standardUserDefaults dictionaryForKey:key] mutableCopy] ?: [NSMutableDictionary dictionary];
        settings[@"BXLastProgramPath"] = @"C.harddisk/WINDOWS/WIN.COM";
        settings[@"BXLastProgramLaunchArguments"] = @"C:\\~WING.TMP\\_MSTEST.EXE";
        settings[@"showLaunchPanel"] = @NO;
        [NSUserDefaults.standardUserDefaults setObject:settings forKey:key];
    }
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:game]
        display:YES completionHandler:^(NSDocument *doc, BOOL alreadyOpen, NSError *error) {
            Check(doc && !error, "open the copied Congo gamebox");
            session = (id)doc;
            if ([env[@"BOXER_PICKER_HIDE_WINDOW"] boolValue]) {
                testCompanion = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 280, 80)
                    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
                testCompanion.releasedWhenClosed = NO;
                testCompanion.title = @"Congo startup check";
                [testCompanion orderFront:nil];
                [session.windowForSheet orderOut:nil];
            }
            else [NSApp activateIgnoringOtherApps:YES];
        }];
    __block NSUInteger tick = 0;
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        tick++;
        if (!launch) {
            if (tick == 4) {
                Check(PickerItem(NSApp.mainMenu) != nil, "compiled menu has the picker action");
                [session chooseWindowsProgram:nil];
            } else if (tick == 6) {
                Check([Programs().itemTitles containsObject:@"D:\\CONGO.EXE"], "picker discovers Congo inside the ISO");
                Check([Programs().itemTitles containsObject:@"C:\\WINDOWS\\SOL.EXE"], "picker discovers installed Windows executables");
                Click(@"Cancel");
            } else if (tick == 7) {
                Check([[NSData dataWithContentsOfFile:infoPath] isEqual:originalInfo], "Cancel leaves metadata unchanged");
                [session chooseWindowsProgram:nil];
            } else if (tick == 9) {
                SelectShortcut(@"Reader test");
                Click(@"Save for Next Launch");
            } else if (tick == 10) {
                NSDictionary *selected = session.gamebox.defaultLauncher;
                Check([selected[@"BXLauncherArguments"] isEqual:@"C:\\WINDOWS\\WRITE.EXE \"C:\\CONGO\\README.WRI\""], "shortcut arguments survive exactly");
                Check([selected[@"BXLauncherWorkingDirectory"] isEqual:@"C:\\CONGO"], "shortcut working folder saved");
                [session chooseWindowsProgram:nil];
            } else if (tick == 12) {
                SelectShortcut(@"Congo");
                Click(@"Save for Next Launch");
            } else if (tick == 13) {
                NSDictionary *selected = session.gamebox.defaultLauncher;
                Check([selected[@"BXLauncherArguments"] isEqual:@"D:\\CONGO.EXE"] &&
                      [selected[@"BXLauncherWindowsStartup"] boolValue], "selected Windows shortcut is the new default");
                Check([selected[@"BXLauncherPath"] isEqual:@"C.harddisk/WINDOWS/WIN.COM"], "shortcut wraps game through WIN.COM");
                Check([selected[@"BXLauncherWorkingDirectory"] isEqual:@"D:\\"], "Congo uses its own working folder");
                Check([selected[@"BXLauncherTitle"] isEqual:@"Congo"], "launcher preserves the shortcut title");
                fprintf(stdout, "PASS: shortcut names, quoted arguments, working folders, Cancel, portable saved launcher\n"); fflush(stdout);
                [session chooseWindowsProgram:nil];
            } else if (tick == 15) {
                Check([Programs().selectedItem.representedObject[@"shortcut"][@"title"] isEqual:@"Congo"], "picker remembers shortcut identity");
                Click(@"Save for Next Launch");
            } else if (tick == 16) {
                Check(session.gamebox.launchers.count == 2, "saving the same shortcut does not duplicate launchers");
                finished = YES;
                [session.windowForSheet performClose:nil];
            [testCompanion close];
            }
        } else if (tick == 5 || tick == 10 || tick == 18 || tick == 60 || tick == launchSeconds) {
            Check([session.targetArguments isEqual:@"D:\\CONGO.EXE"], "fresh launch overrides stale installer arguments");
            Check(sawShortcutDirectory || [env[@"BOXER_PICKER_SKIP_DIRECTORY_CHECK"] boolValue], "startup preserves the shortcut working directory before WIN.COM runs");
            Check(session.emulator.isRunningActiveProcess, "Windows is running after selecting Congo");
            BXVideoFrame *frame = session.DOSWindowController.renderingView.currentFrame;
            Check(frame != nil, "guest framebuffer is available");
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                pixelsWide:frame.size.width pixelsHigh:frame.size.height bitsPerSample:8 samplesPerPixel:4
                hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                bitmapFormat:NSBitmapFormatAlphaFirst | NSBitmapFormatThirtyTwoBitLittleEndian
                bytesPerRow:frame.pitch bitsPerPixel:32];
            memcpy(rep.bitmapData, frame.bytes, frame.pitch * (NSUInteger)frame.size.height);
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:[game stringByAppendingFormat:@"-launch-%lu.png", (unsigned long)tick] atomically:YES];
            if (tick < launchSeconds) return;
            fprintf(stdout, "PASS: fresh process launches WIN.COM with D:\\CONGO.EXE despite stale saved installer\n"); fflush(stdout);
            finished = YES;
            [session.windowForSheet performClose:nil];
            [testCompanion close];
        }
    }];
}
__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        Class emulator = NSClassFromString(@"BXEmulator");
        SEL selector = @selector(executeProgramAtDOSPath:withArguments:changingDirectory:);
        Method method = class_getInstanceMethod(emulator, selector);
        void (*original)(id, SEL, NSString *, NSString *, BOOL) = (void *)method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^(BXEmulator *object, NSString *path, NSString *args, BOOL change) {
            if ([args isEqual:@"D:\\CONGO.EXE"])
                sawShortcutDirectory = !change && [object.currentDriveLetter isEqual:@"D"] && object.currentDirectory.length == 0;
            original(object, selector, path, args, change);
        }));
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ Start(); }); }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                Check(finished, "test finishes before natural app termination");
                fprintf(stdout, "PASS: normal window close exits the app\n"); fflush(stdout);
            }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            fprintf(stderr, "FAIL: Windows picker test timeout\n"); exit(2);
        });
    }
}
