//Runs the real importer in a disposable app with a generated DOS installer.
@import Cocoa;
#import <objc/runtime.h>
#import "BXImportSession.h"
#import "BXImportWindowController.h"
#import "BXGamebox.h"
#import "BXEmulator.h"
#import "BXEmulator+BXDOSFileSystem.h"
#import "BXEmulatedKeyboard.h"
#import "BXDOSWindowController.h"
#import "BXVideoFrame.h"

@interface NSObject (BXImportSmokeActions)
@property (copy) NSURL *gamesFolderURL;
- (void)orderFrontWelcomePanel:(id)sender;
- (void)orderFrontImportGamePanel:(id)sender;
@end

static BXImportSession *session;
static BOOL finished;
static NSUInteger step, ticks;
static NSURL *source;
static NSUInteger commandIndex;
static BOOL finishCancelled;

static void Check(BOOL success, const char *message) {
    if (!success) { fprintf(stderr, "FAIL: %s\n", message); fflush(stderr); _Exit(1); }
}

static NSButton *ButtonWithAction(NSView *view, SEL action) {
    if ([view isKindOfClass:NSButton.class] && ((NSButton *)view).action == action) return (id)view;
    for (NSView *child in view.subviews) {
        NSButton *button = ButtonWithAction(child, action);
        if (button) return button;
    }
    return nil;
}

static NSPopUpButton *FindProgramPopup(NSView *view) {
    if ([view isKindOfClass:NSPopUpButton.class] && [view.accessibilityLabel isEqual:@"Game program:"]) return (id)view;
    for (NSView *child in view.subviews) { NSPopUpButton *found = FindProgramPopup(child); if (found) return found; }
    return nil;
}
static NSButton *ButtonWithTitle(NSView *view, NSString *title) {
    if ([view isKindOfClass:NSButton.class] && [[(NSButton *)view title] isEqual:title]) return (id)view;
    for (NSView *child in view.subviews) { NSButton *found = ButtonWithTitle(child, title); if (found) return found; }
    return nil;
}

static void LogAlertText(NSView *view) {
    if ([view isKindOfClass:NSTextField.class]) NSLog(@"Import alert: %@", ((NSTextField *)view).stringValue);
    for (NSView *child in view.subviews) LogAlertText(child);
}

static void CaptureInstaller(NSString *root) {
    BXVideoFrame *frame = session.DOSWindowController.renderingView.currentFrame;
    if (!frame) return;
    Check(frame.bytesPerPixel == 4, "capture expects the renderer's BGRA framebuffer");
    NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:frame.size.width pixelsHigh:frame.size.height bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
        bytesPerRow:frame.pitch bitsPerPixel:32];
    const unsigned char *pixels = frame.bytes;
    for (NSUInteger i = 0; i < frame.pitch * (NSUInteger)frame.size.height; i += 4) {
        image.bitmapData[i] = pixels[i + 2];
        image.bitmapData[i + 1] = pixels[i + 1];
        image.bitmapData[i + 2] = pixels[i];
        image.bitmapData[i + 3] = 255;
    }
    [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[root stringByAppendingPathComponent:@"installer.png"] atomically:YES];
}

static void Start(void) {
    NSString *root = NSProcessInfo.processInfo.environment[@"BOXER_IMPORT_ROOT"];
    NSString *mode = NSProcessInfo.processInfo.environment[@"BOXER_IMPORT_MODE"];
    BOOL scanOnly = [mode isEqual:@"windows-scan"];
    BOOL automaticWindows = [mode isEqual:@"windows-auto"];
    BOOL windows = [mode isEqual:@"windows"] || automaticWindows;
    BOOL automaticDisc = [mode isEqual:@"disc-installer"];
    BOOL disc = [mode isEqual:@"iso"] || windows || automaticDisc;
    BOOL installer = [mode isEqual:@"installer"] || disc || scanOnly;
    Check([root containsString:@"/build/"], "import fixture must be isolated");
    source = [NSURL fileURLWithPath:disc ? NSProcessInfo.processInfo.environment[@"BOXER_IMPORT_ISO"]
                                       : [root stringByAppendingPathComponent:@"Source"]];
    id appDelegate = NSApp.delegate;
    [appDelegate setGamesFolderURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Games"]]];
    [appDelegate orderFrontWelcomePanel:nil];
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        ticks++;
        if (ticks % 16 == 0) NSLog(@"Import heartbeat: step=%lu stage=%ld emulating=%d target=%@ windows=%@", (unsigned long)step,
            (long)session.importStage, session.isEmulating, session.targetURL, NSApp.windows);
        if (step == 0) {
            step = 1;
            [appDelegate orderFrontImportGamePanel:nil];
            session = (id)NSDocumentController.sharedDocumentController.documents.firstObject;
            Check([[session class] canImportFromSourceURL:source], "source is accepted by the import dropzone and file chooser");
            Check([session isKindOfClass:NSClassFromString(@"BXImportSession")], "Import New Game creates an import session");
            Check(session.importWindowController.window.isVisible, "import window is visible after leaving Welcome");
            [session importFromSourceURL:source];
        } else if (step == 1) {
            if (session.importStage == BXImportSessionLoadingSource) return;
            if (session.windowForSheet.attachedSheet) LogAlertText(session.windowForSheet.attachedSheet.contentView);
            if (installer) {
                Check(session.importStage == BXImportSessionWaitingForInstaller, "Release import must offer the detected installer, not silently skip it");
                Check(session.installerURLs.count >= 1 && session.gamebox == nil, "installer is detected before creating a gamebox");
                if (scanOnly) {
                    Check(session.installerURLs.count == 1 && [[session.installerURLs.firstObject lastPathComponent] isEqual:@"SETUP.EXE"],
                          "Windows-only media offers setup and excludes uninstallers");
                    fprintf(stdout, "PASS: Windows-only setup detection\n"); fflush(stdout);
                    const unsigned char program[] = {0xB8, 0, 0x4C, 0xCD, 0x21};
                    [[NSData dataWithBytes:program length:sizeof(program)] writeToURL:[source URLByAppendingPathComponent:@"DOSINST.COM"] atomically:YES];
                    [session cancelSourceSelection]; step = 12; [session importFromSourceURL:source]; return;
                }
                [session cancelSourceSelection];
                Check(session.importStage == BXImportSessionWaitingForSource && !session.sourceURL, "cancel installer selection returns to the dropzone");
                step = 2;
                [session importFromSourceURL:source];
            } else if (session.importStage == BXImportSessionFinished) {
                step = 4;
            }
        } else if (step == 12) {
            if (session.importStage == BXImportSessionLoadingSource) return;
            Check(session.importStage == BXImportSessionWaitingForInstaller && session.installerURLs.count == 2 &&
                  [[session.installerURLs.firstObject lastPathComponent] isEqual:@"DOSINST.COM"],
                  "mixed media retains DOS installer priority and offers Windows setup");
            fprintf(stdout, "PASS: mixed media keeps DOS installer priority\n"); fflush(stdout);
            finished = YES; [timer invalidate]; [session.importWindowController.window performClose:nil];
        } else if (step == 2) {
            if (session.importStage == BXImportSessionLoadingSource) return;
            Check(session.importStage == BXImportSessionWaitingForInstaller, "installer selection works after cancellation");
            NSButton *button = ButtonWithAction(session.importWindowController.window.contentView, NSSelectorFromString(@"launchSelectedInstaller:"));
            Check(button && button.isEnabled, "Start Installation button is connected and enabled");
            step = automaticWindows ? 7 : (windows ? 5 : 3);
            @try { [button performClick:nil]; }
            @catch (NSException *exception) {
                NSLog(@"Installer launch exception: %@\n%@", exception, exception.callStackSymbols);
                Check(NO, "installer handoff must not throw an exception");
            }
            NSLog(@"Installer action returned: stage=%ld target=%@ emulator=%@", (long)session.importStage, session.targetURL, session.emulator);
        } else if (step == 5) {
            NSOpenPanel *panel = (id)session.windowForSheet.attachedSheet;
            Check([panel isKindOfClass:NSOpenPanel.class], "Windows setup opens a runtime selection panel");
            [panel cancel:nil]; step = 6;
        } else if (step == 6 && !session.windowForSheet.attachedSheet) {
            Check(session.importStage == BXImportSessionWaitingForInstaller && !session.gamebox,
                  "cancelling runtime selection leaves no partial gamebox");
            [session launchWindowsInstallerAtURL:session.installerURLs.firstObject
                usingGameboxURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Empty.boxer"]]];
            step = 9;
        } else if (step == 9) {
            if (session.importStage == BXImportSessionPreparingWindows || !session.windowForSheet.attachedSheet) return;
            Check(session.importStage == BXImportSessionWaitingForInstaller && !session.gamebox,
                  "missing Windows runtime returns to selection without a partial gamebox");
            LogAlertText(session.windowForSheet.attachedSheet.contentView);
            [ButtonWithTitle(session.windowForSheet.attachedSheet.contentView, @"OK") performClick:nil]; step = 10;
        } else if (step == 10 && !session.windowForSheet.attachedSheet) {
            [session launchWindowsInstallerAtURL:session.installerURLs.firstObject
                usingGameboxURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Template.boxer"]]];
            step = 7;
        } else if (step == 7) {
            if (automaticWindows)
                Check(![session.windowForSheet.attachedSheet isKindOfClass:NSOpenPanel.class],
                      "bundled Windows starts without a runtime selection panel");
            if (session.importStage == BXImportSessionPreparingWindows) return;
            if (session.importStage != BXImportSessionRunningInstaller && ticks % 8 != 0) return;
            NSLog(@"Runtime copy stage=%ld operation=%@", (long)session.importStage, [session valueForKey:@"windowsCopyOperation"]);
            if (session.importStage != BXImportSessionRunningInstaller)
                for (NSWindow *window in NSApp.windows) LogAlertText(window.contentView);
            if (session.windowForSheet.attachedSheet) LogAlertText(session.windowForSheet.attachedSheet.contentView);
            Check(session.importStage == BXImportSessionRunningInstaller, "Windows runtime copy completes");
            NSURL *drive = [session valueForKey:@"rootDriveURL"];
            if (automaticWindows) {
                NSURL *runtime = [NSBundle.mainBundle URLForResource:@"Windows311" withExtension:nil];
                for (NSString *path in @[@"WINDOWS/WIN.COM", @"WINDOWS/SYSTEM/S3TRIO.DRV", @"AUTOEXEC.BAT"])
                    Check([[NSData dataWithContentsOfURL:[drive URLByAppendingPathComponent:path]]
                        isEqualToData:[NSData dataWithContentsOfURL:[runtime URLByAppendingPathComponent:path]]],
                        "automatic import copies this build's Windows runtime and drivers");
                Check(![[drive URLByAppendingPathComponent:@".gitkeep"] checkResourceIsReachableAndReturnError:NULL],
                      "source placeholder is not installed on the guest C drive");
                fprintf(stdout, "PASS: bundled Windows copied automatically without a runtime chooser\n"); fflush(stdout);
                step = 3; return;
            }
            Check([[NSString stringWithContentsOfURL:[drive URLByAppendingPathComponent:@"WINDOWS/BXIMPORT.TXT"]
                encoding:NSUTF8StringEncoding error:NULL] isEqual:@"shadow runtime marker"], "runtime copy includes current shadow files");
            Check([[drive URLByAppendingPathComponent:@".WINHIDDEN"] checkResourceIsReachableAndReturnError:NULL],
                  "runtime copy preserves hidden files");
            Check(![[drive URLByAppendingPathComponent:@"DELETE.ME"] checkResourceIsReachableAndReturnError:NULL],
                  "runtime copy respects shadow deletions");
            Check(![session.gamebox.gameIdentifier isEqual:[NSDictionary dictionaryWithContentsOfFile:
                [root stringByAppendingPathComponent:@"Template.boxer/Game Info.plist"]][@"BXGameIdentifier"]],
                "new gamebox has an independent identity");
            fprintf(stdout, "PASS: runtime selection cancellation and independent shadow-aware copy\n"); fflush(stdout);
            step = 3;
        } else if (step == 8) {
            NSView *view = session.windowForSheet.attachedSheet.contentView;
            NSPopUpButton *programs = FindProgramPopup(view);
            NSString *program = @"C:\\ALUNSER\\ALUNSER.EXE";
            if (![programs.itemTitles containsObject:program]) return;
            if (!finishCancelled) {
                [ButtonWithTitle(view, @"Cancel") performClick:nil]; finishCancelled = YES; step = 11; return;
            }
            [programs selectItemWithTitle:program];
            [NSApp sendAction:programs.action to:programs.target from:programs];
            NSButton *finish = ButtonWithTitle(view, @"Finish Import");
            Check(finish.enabled, "finish chooser can save the newly installed game");
            step = 4; [finish performClick:nil];
        } else if (step == 11 && !session.windowForSheet.attachedSheet) {
            Check(session.importStage == BXImportSessionRunningInstaller && session.isEmulating,
                  "cancelling final program selection resumes installation");
            [session finishInstaller]; step = 8;
        } else if (step == 3) {
            if (session.windowForSheet.attachedSheet) {
                LogAlertText(session.windowForSheet.attachedSheet.contentView);
                Check(NO, "installer launch must not show an error alert");
            }
            if (disc && !automaticDisc) {
                if (ticks % 4 == 0) CaptureInstaller(root);
                NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"commands.json"]];
                NSArray *commands = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
                if (commandIndex < commands.count && ticks % 4 == 0) {
                    NSString *command = commands[commandIndex++];
                    NSLog(@"ISO test command: %@", command);
                    if ([command isEqual:@"finish"]) {
                        Check(windows || !session.emulator.isRunningActiveProcess, "finish only after the actual installer has exited");
                        step = windows ? 8 : 4;
                        [session finishInstaller];
                    } else if ([command isEqual:@"enter"]) [session.emulator.keyboard keyPressed:KBD_enter];
                    else if ([command isEqual:@"escape"]) [session.emulator.keyboard keyPressed:KBD_esc];
                    else if ([command isEqual:@"down"]) [session.emulator.keyboard keyPressed:KBD_down];
                    else if ([command isEqual:@"up"]) [session.emulator.keyboard keyPressed:KBD_up];
                    else [session.emulator.keyboard typeCharacters:command];
                }
                return;
            }
            NSURL *drive = [session valueForKey:@"rootDriveURL"];
            NSURL *installedFile = [drive URLByAppendingPathComponent:@"GAME.COM"];
            if ([installedFile checkResourceIsReachableAndReturnError:NULL] && !session.emulator.isRunningActiveProcess) {
                const unsigned char bytes[] = {0xB8, 0, 0x4C, 0xCD, 0x21};
                Check([[NSData dataWithContentsOfURL:installedFile] isEqualToData:[NSData dataWithBytes:bytes length:sizeof(bytes)]],
                      "DOS installer executed and wrote the expected installed program");
                fprintf(stdout, "PASS: installer selection, cancellation, launch, and DOS file creation\n"); fflush(stdout);
                step = 4;
                [session finishInstaller];
            }
        } else if (step == 4 && session.importStage == BXImportSessionFinished) {
            Check(session.importWindowController.window.isVisible, "completed import shows its final window");
            Check([[session.gamebox.bundleURL.path stringByStandardizingPath] hasPrefix:[root stringByAppendingPathComponent:@"Games/"]], "gamebox stays in isolated games folder");
            Check([[session.gamebox.bundleURL URLByAppendingPathComponent:@"Game Info.plist"] checkResourceIsReachableAndReturnError:NULL], "completed gamebox metadata exists");
            if (windows) {
                Check([session.gamebox.defaultLauncher[@"BXLauncherArguments"] isEqual:@"C:\\ALUNSER\\ALUNSER.EXE"],
                      "completed Windows gamebox launches the game instead of setup");
                Check([[session.gamebox.bundleURL URLByAppendingPathComponent:@"C.harddisk/WINDOWS/WIN.COM"] checkResourceIsReachableAndReturnError:NULL],
                      "completed gamebox contains its own Windows installation");
            } else {
                Check(![[session.gamebox.bundleURL URLByAppendingPathComponent:@"C.harddisk/WINDOWS/WIN.COM"] checkResourceIsReachableAndReturnError:NULL],
                      "DOS imports do not copy Windows into their C drive");
            }
            fprintf(stdout, "PASS: %s import completed: %s\n", installer ? "installer" : "preinstalled", session.gamebox.bundleURL.path.UTF8String); fflush(stdout);
            finished = YES;
            [timer invalidate];
            [session.importWindowController.window performClose:nil];
        }
        if (ticks % 8 == 0) {
            fprintf(stdout, "Import progress: step=%lu stage=%ld progress=%.2f\n", (unsigned long)step, (long)session.importStage, (double)session.stageProgress);
            NSLog(@"Import diagnostic: target=%@ root=%@ active=%d prompt=%d paused=%d directory=%@ drives=%@ sheet=%@",
                  session.targetURL, [session valueForKey:@"rootDriveURL"], session.emulator.isRunningActiveProcess,
                  session.emulator.isAtPrompt, session.suspended, session.emulator.currentDirectory,
                  session.emulator.mountedDrives, session.windowForSheet.attachedSheet);
            fflush(stdout);
        }
    }];
}

__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        for (NSArray *hook in @[@[@"BXSession", @"_startEmulator"]]) {
            SEL selector = NSSelectorFromString(hook[1]);
            Method debugMethod = class_getInstanceMethod(NSClassFromString(hook[0]), selector);
            void (*debugOriginal)(id, SEL) = (void *)method_getImplementation(debugMethod);
            method_setImplementation(debugMethod, imp_implementationWithBlock(^(id object) {
                @try { debugOriginal(object, selector); }
                @catch (NSException *exception) {
                    NSLog(@"Import startup exception: %@\n%@", exception, exception.callStackSymbols);
                    Check(NO, "asynchronous emulator startup must not throw");
                }
            }));
        }
        //Record why real discs enter (or bypass) the installer stage.
        Method method = class_getInstanceMethod(NSClassFromString(@"BXImportSession"), NSSelectorFromString(@"installerScanDidFinish:"));
        void (*original)(id, SEL, NSNotification *) = (void *)method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^(id object, NSNotification *note) {
            id scan = note.object;
            NSLog(@"Import scan: DOS=%@ Windows=%@ installers=%@ alreadyInstalled=%@ error=%@",
                  [scan valueForKey:@"DOSExecutables"], [scan valueForKey:@"windowsExecutables"],
                  [scan valueForKey:@"matchingPaths"], [scan valueForKey:@"alreadyInstalled"], [scan valueForKey:@"error"]);
            original(object, NSSelectorFromString(@"installerScanDidFinish:"), note);
        }));
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer *timer) { Start(); }];
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            Check(finished, "app must not quit during import or window transitions");
            fprintf(stdout, "PASS: completed import requests application exit\n"); fflush(stdout);
        }];
        NSString *mode = NSProcessInfo.processInfo.environment[@"BOXER_IMPORT_MODE"];
        NSTimeInterval timeout = [mode hasPrefix:@"windows"] && ![mode isEqual:@"windows-scan"] ? 300 : ([mode isEqual:@"iso"] ? 600 : 40);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout*NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            fprintf(stderr, "FAIL: import check timed out\n"); fflush(stderr); _Exit(2);
        });
    }
}
