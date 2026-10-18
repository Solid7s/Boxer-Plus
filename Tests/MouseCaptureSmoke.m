// Functional mouse-input check, loaded only into a disposable app/game copy.
@import Cocoa;
#import "BXEmulator.h"
#import "BXEmulatedMouse.h"
#import "BXSession+BXUIControls.h"
#import "BXDOSWindowController.h"
#import "BXInputController.h"
#import "BXVideoFrame.h"

@interface NSObject (BXMouseCapture)
- (NSBitmapImageRep *)captureOutputImage;
@end

static void Capture(BXSession *session, NSString *suffix) {
    BXVideoFrame *frame = [session.DOSWindowController.renderingView currentFrame];
    if (!frame) return;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:frame.size.width pixelsHigh:frame.size.height bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bitmapFormat:NSBitmapFormatAlphaFirst | NSBitmapFormatThirtyTwoBitLittleEndian
        bytesPerRow:frame.pitch bitsPerPixel:32];
    memcpy(rep.bitmapData, frame.bytes, frame.pitch * (NSUInteger)frame.size.height);
    NSString *path = [NSProcessInfo.processInfo.environment[@"BOXER_MOUSE_CAPTURE"] stringByAppendingString:suffix];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    id view = session.DOSWindowController.renderingView;
    NSBitmapImageRep *rendered = [[view valueForKey:@"filterChain"] captureOutputImage];
    [[rendered representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[path stringByAppendingString:@".rendered.png"] atomically:YES];
}

static void StartCheck(void) {
    NSString *game = NSProcessInfo.processInfo.environment[@"BOXER_TEST_GAME"];
    if (![game containsString:@"/build/"]) exit(2);
    __block BXSession *session = nil;
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:game]
        display:YES completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
            if (!document || error) { NSLog(@"FAIL: open game: %@", error); exit(2); }
            session = (id)document;
            [NSApp activateIgnoringOtherApps:YES];
        }];
    __block NSUInteger tick = 0;
    __block BOOL locked = NO, pressed = NO;
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        tick++;
        BXInputController *input = session.DOSWindowController.inputController;
        NSWindow *window = input.view.window;
        fprintf(stdout, "INPUT t=%lu process=%s executing=%d active=%d suspended=%d key=%d appActive=%d tracking=%d canLock=%d locked=%d view=%s\n",
            (unsigned long)tick, session.emulator.processName.UTF8String ?: "", session.emulator.isExecuting,
            session.emulator.mouse.isActive, session.isSuspended, window.isKeyWindow, NSApp.isActive,
            input.trackMouseWhileUnlocked, input.canLockMouse, input.mouseLocked, NSStringFromRect(input.view.frame).UTF8String);
        fflush(stdout);
        if (tick == 8) {
            Capture(session, @"-before.png");
            [NSApp activateIgnoringOtherApps:YES];
            [window makeKeyAndOrderFront:nil];
            input.mouseLocked = NO;
        }
        if (tick == 9) {
            NSPoint point = [input.view convertPoint:NSMakePoint(NSMidX(input.view.bounds), NSMidY(input.view.bounds)) toView:nil];
            NSPoint contentPoint = [window.contentView.superview convertPoint:point fromView:nil];
            NSView *hit = [window.contentView hitTest:contentPoint];
            fprintf(stdout, "HIT view=%s expected=%s responder=%s\n", NSStringFromClass(hit.class).UTF8String,
                    NSStringFromClass(input.view.class).UTF8String, NSStringFromClass(hit.nextResponder.class).UTF8String);
            // Click-to-capture through the real window responder chain.
            for (NSNumber *type in @[@(NSEventTypeLeftMouseDown), @(NSEventTypeLeftMouseUp)]) {
                NSEvent *event = [NSEvent mouseEventWithType:type.integerValue location:point
                    modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                    windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
                [NSApp sendEvent:event];
            }
            locked = input.mouseLocked;
            [NSApp sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                context:nil eventNumber:0 clickCount:1 pressure:1]];
            pressed = [session.emulator.mouse buttonIsDown:BXMouseButtonLeft];
            [NSApp sendEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                context:nil eventNumber:0 clickCount:1 pressure:0]];
            fflush(stdout);
        }
        if (tick == 10) {
            [session.emulator.mouse movedTo:NSZeroPoint by:NSMakePoint(0.1, 0.1)
                                  onCanvas:input.view.bounds whileLocked:YES];
        }
        if (tick == 11) {
            Capture(session, @"-after.png");
            BOOL released = ![session.emulator.mouse buttonIsDown:BXMouseButtonLeft];
            input.mouseLocked = NO;
            fprintf(stdout, "%s: mouse capture locked=%d pressed=%d released=%d\n",
                    locked && pressed && released ? "PASS" : "FAIL", locked, pressed, released);
            fflush(stdout);
            exit(locked && pressed && released ? 0 : 1);
        }
    }];
}

__attribute__((constructor)) static void InstallCheck(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ StartCheck(); });
            }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            fprintf(stderr, "FAIL: mouse check timeout\n"); fflush(stderr); exit(2);
        });
    }
}
