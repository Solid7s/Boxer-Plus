// Functional close/quit check in a disposable app and game copy.
// Success requires normal AppKit termination; only failures call exit().
@import Cocoa;
#import "BXSession.h"
#import "BXSession+BXUIControls.h"
#import "BXEmulator.h"
#import "BXDOSWindowController.h"

static BXSession *session;
static NSWindow *gameWindow, *companion;
static BOOL accepted, expectTermination;
static NSString *settingsKey;

static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); fflush(stderr); exit(1); }
}

static NSButton *Button(NSView *view, NSString *title) {
    if ([view isKindOfClass:NSButton.class] && [((NSButton *)view).title isEqual:title]) return (id)view;
    for (NSView *child in view.subviews) {
        NSButton *found = Button(child, title);
        if (found) return found;
    }
    return nil;
}

static void AnswerClose(NSString *title) {
    Check(gameWindow.attachedSheet != nil, "closing an active game asks for confirmation");
    NSButton *button = Button(gameWindow.attachedSheet.contentView, title);
    Check(button != nil, "close sheet has the expected button");
    [button performClick:nil];
}

static void Start(void) {
    NSString *game = NSProcessInfo.processInfo.environment[@"BOXER_TEST_GAME"];
    Check([game containsString:@"/build/"], "test game must be an isolated copy");
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[game stringByAppendingPathComponent:@"Game Info.plist"]];
    settingsKey = [@"BXGameSettings: " stringByAppendingString:info[@"BXGameIdentifier"]];
    BOOL keepOtherWindow = [NSProcessInfo.processInfo.environment[@"BOXER_CLOSE_MODE"] isEqual:@"companion"];
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:game]
        display:YES completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
            Check(document && !error, "open isolated SimTower");
            session = (id)document;
            gameWindow = session.DOSWindowController.window;
            if (keepOtherWindow) {
                companion = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 160)
                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
                companion.releasedWhenClosed = NO;
                companion.title = @"Window-close check";
                [companion orderFront:nil];
                [gameWindow makeKeyAndOrderFront:nil];
            }
            [NSApp activateIgnoringOtherApps:YES];
        }];
    __block NSUInteger tick = 0;
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        tick++;
        if (tick == 8) {
            Check(session.emulator.isRunningActiveProcess, "a game is running before close");
            session.autoSpeedCPUUsage = 75;
            session.autoSpeedCycleLimit = 60000;
            [gameWindow performClose:nil];
        } else if (tick == 9) {
            AnswerClose(@"Cancel");
        } else if (tick == 10) {
            Check(gameWindow.isVisible && !gameWindow.attachedSheet && !session.emulator.isCancelled,
                  "cancel keeps the game and window running");
            fprintf(stdout, "PASS: cancel preserves the active game\n"); fflush(stdout);
            [gameWindow performClose:nil];
        } else if (tick == 11) {
            accepted = YES;
            expectTermination = !keepOtherWindow;
            fprintf(stdout, "Accepting game-window close; companion=%d\n", keepOtherWindow); fflush(stdout);
            AnswerClose(@"Close");
        } else if (tick == 13 && keepOtherWindow) {
            Check(accepted && !gameWindow.isVisible && companion.isVisible, "another window keeps the app alive");
            Check(NSDocumentController.sharedDocumentController.documents.count == 0, "closed game is removed from document list");
            fprintf(stdout, "PASS: another window stays open after game close\n"); fflush(stdout);
            expectTermination = YES;
            [companion performClose:nil];
        } else if (tick == 17) {
            Check(NO, "app stayed running after the last window closed");
        }
    }];
}

__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ Start(); });
            }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                Check(accepted && expectTermination, "app terminates only after final accepted close");
                Check(!session.isEmulating && session.emulator.isCancelled, "close cancels emulation");
                NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:settingsKey];
                Check([saved[@"autoSpeedCPUUsage"] integerValue] == 75 && [saved[@"autoSpeedCycleLimit"] integerValue] == 60000,
                      "close saves the session settings");
                fprintf(stdout, "PASS: normal app termination, emulator cancellation, and saved settings\n"); fflush(stdout);
            }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            fprintf(stderr, "FAIL: close check timeout\n"); fflush(stderr); exit(2);
        });
    }
}
