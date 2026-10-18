// Short diagnostic only: post markers to AppKit from a worker thread, then
// deliver their relative motion at dispatch. Measures queue-to-input dispatch
// and changed-frame/submission gaps, NOT physical-mouse or screen latency.
@import Cocoa;
@import QuartzCore;
#import <objc/runtime.h>
#import "BXSession.h"
#import "BXEmulator.h"
#import "BXEmulatedMouse.h"
#import "BXDOSWindowController.h"
#import "BXInputController.h"
#import "BXVideoFrame.h"

static const NSInteger FirstEvent = 410000;
static const NSUInteger EventCount = 500;
static double delays[500], gaps[2048], drawGaps[2048], lastFrame, lastDraw;
static NSUInteger received, changed, gapCount, drawGapCount, moved;
static BOOL measuring, handlingProbe;
static Class relativeEventClass;
static BXInputController *probeInput;

static NSEvent *RelativeEvent(NSPoint point, NSInteger windowNumber, NSUInteger index, NSTimeInterval timestamp) {
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:point modifierFlags:0
        timestamp:timestamp windowNumber:windowNumber context:nil
        eventNumber:FirstEvent+index clickCount:0 pressure:0];
    // AppKit's factory has no relative-delta arguments. Keep its concrete
    // window event intact and override only these getters in this test process.
    // A CGEvent round trip loses the factory event's window routing metadata.
    if (!relativeEventClass) {
        relativeEventClass = objc_allocateClassPair(event.class, "BXProbeRelativeMouseEvent", 0);
        class_addMethod(relativeEventClass, @selector(deltaX), imp_implementationWithBlock(^CGFloat(NSEvent *self) {
            return ((self.eventNumber-FirstEvent)/50)%2 ? -2 : 2;
        }), method_getTypeEncoding(class_getInstanceMethod(event.class, @selector(deltaX))));
        class_addMethod(relativeEventClass, @selector(deltaY), imp_implementationWithBlock(^CGFloat(NSEvent *self) {
            return ((self.eventNumber-FirstEvent)/100)%2 ? -1 : 1;
        }), method_getTypeEncoding(class_getInstanceMethod(event.class, @selector(deltaY))));
        objc_registerClassPair(relativeEventClass);
    }
    object_setClass(event, relativeEventClass);
    return event;
}

static int Compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

static void Report(const char *name, double *values, NSUInteger count) {
    if (!count) return;
    qsort(values, count, sizeof(double), Compare);
    printf("%s count=%lu median_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f\n",
        name, (unsigned long)count, values[count/2], values[(count-1)*95/100],
        values[(count-1)*99/100], values[count-1]);
}

static void InstallHooks(void) {
    Method dispatch = class_getInstanceMethod(NSApp.class, @selector(sendEvent:));
    void (*originalDispatch)(id, SEL, NSEvent *) = (void *)method_getImplementation(dispatch);
    method_setImplementation(dispatch, imp_implementationWithBlock(^(id self, NSEvent *event) {
        if (event.type == NSEventTypeApplicationDefined && event.subtype == 2417) {
            // AppKit discards manufactured mouse movement without WindowServer
            // tracking metadata. A marker takes the same production event pump;
            // only after dequeue do we deliver its motion to the real controller.
            [probeInput mouseMoved:RelativeEvent(event.locationInWindow, event.windowNumber, event.data1, event.timestamp)];
            return;
        }
        originalDispatch(self, @selector(sendEvent:), event);
    }));
    Method input = class_getInstanceMethod(NSClassFromString(@"BXInputController"), @selector(mouseMoved:));
    void (*originalInput)(id, SEL, NSEvent *) = (void *)method_getImplementation(input);
    method_setImplementation(input, imp_implementationWithBlock(^(id self, NSEvent *event) {
        BOOL probe = event.eventNumber >= FirstEvent && event.eventNumber < FirstEvent + EventCount;
        if (probe && received < EventCount)
            delays[received++] = (NSProcessInfo.processInfo.systemUptime - event.timestamp) * 1000;
        handlingProbe = probe;
        originalInput(self, @selector(mouseMoved:), event);
        handlingProbe = NO;
    }));
    SEL movement = @selector(movedTo:by:onCanvas:whileLocked:);
    Method mouse = class_getInstanceMethod(NSClassFromString(@"BXEmulatedMouse"), movement);
    void (*originalMouse)(id, SEL, NSPoint, NSPoint, NSRect, BOOL) = (void *)method_getImplementation(mouse);
    method_setImplementation(mouse, imp_implementationWithBlock(^(BXEmulatedMouse *self, NSPoint point, NSPoint delta, NSRect canvas, BOOL locked) {
        if (handlingProbe && self.isActive && (delta.x || delta.y)) moved++;
        originalMouse(self, movement, point, delta, canvas, locked);
    }));
    Method update = class_getInstanceMethod(NSClassFromString(@"BXMetalRenderingView"), @selector(updateWithFrame:));
    void (*originalUpdate)(id, SEL, BXVideoFrame *) = (void *)method_getImplementation(update);
    method_setImplementation(update, imp_implementationWithBlock(^(id self, BXVideoFrame *frame) {
        if (measuring && frame.numDirtyRegions) {
            double now = CACurrentMediaTime();
            if (lastFrame && gapCount < 2048) gaps[gapCount++] = (now - lastFrame) * 1000;
            lastFrame = now;
            changed++;
        }
        originalUpdate(self, @selector(updateWithFrame:), frame);
    }));
    Method draw = class_getInstanceMethod(NSClassFromString(@"BXMetalRenderingView"), @selector(drawRect:));
    void (*originalDraw)(id, SEL, NSRect) = (void *)method_getImplementation(draw);
    method_setImplementation(draw, imp_implementationWithBlock(^(id self, NSRect rect) {
        NSUInteger before = [[self valueForKey:@"submittedFrames"] unsignedIntegerValue];
        originalDraw(self, @selector(drawRect:), rect);
        if (measuring && [[self valueForKey:@"submittedFrames"] unsignedIntegerValue] > before) {
            double now = CACurrentMediaTime();
            if (lastDraw && drawGapCount < 2048) drawGaps[drawGapCount++] = (now-lastDraw)*1000;
            lastDraw = now;
        }
    }));
}

static void Start(void) {
    NSString *game = NSProcessInfo.processInfo.environment[@"BOXER_TEST_GAME"];
    if (![game containsString:@"/build/"]) exit(2);
    InstallHooks();
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:game]
        display:YES completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
        if (!document || error) { NSLog(@"FAIL: %@", error); exit(2); }
        BXSession *session = (id)document;
        [NSApp activateIgnoringOtherApps:YES];
        [NSTimer scheduledTimerWithTimeInterval:18 repeats:NO block:^(NSTimer *timer) {
            BXInputController *input = session.DOSWindowController.inputController;
            NSWindow *window = input.view.window;
            BOOL small = [NSProcessInfo.processInfo.environment[@"BOXER_QUEUE_WINDOW"] isEqualToString:@"small"];
            [window setContentSize:small ? NSMakeSize(640, 480) : NSMakeSize(1046, 835)];
            [window makeKeyAndOrderFront:nil];
            [NSApp activateIgnoringOtherApps:YES];
            // Activation is asynchronous. Give AppKit time to deliver focus
            // and resize notifications before locking or sampling motion.
            [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *focusTimer) {
            input.mouseLocked = YES;
            if (!input.mouseLocked) {
                fprintf(stderr, "FAIL: probe could not capture mouse (appActive=%d key=%d canLock=%d)\n",
                    NSApp.isActive, window.isKeyWindow, input.canLockMouse);
                exit(2);
            }
            NSPoint point = [input.view convertPoint:NSMakePoint(NSMidX(input.view.bounds), NSMidY(input.view.bounds)) toView:nil];
            NSInteger windowNumber = window.windowNumber;
            probeInput = input;
            printf("START program=%s auto=%d cycles=%ld locked=%d size=%s legacy=%s\n",
                session.emulator.processName.UTF8String, session.emulator.isAutoSpeed, (long)session.emulator.fixedSpeed,
                input.mouseLocked, NSStringFromSize(input.view.bounds.size).UTF8String,
                getenv("BOXER_LEGACY_SCHEDULER") ?: "0");
            fflush(stdout);
            measuring = YES;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
                for (NSUInteger i = 0; i < EventCount; i++) @autoreleasepool {
                    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:point
                        modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:windowNumber
                        context:nil subtype:2417 data1:i data2:0];
                    [NSApp postEvent:event atStart:NO];
                    [NSThread sleepForTimeInterval:0.008];
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    measuring = NO;
                    input.mouseLocked = NO;
                    NSMutableArray *samples = [NSMutableArray array];
                    for (NSUInteger i = 0; i < received; i++) [samples addObject:@(delays[i])];
                    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"queue_ms":samples}
                        options:NSJSONWritingPrettyPrinted error:nil];
                    [json writeToFile:NSProcessInfo.processInfo.environment[@"BOXER_QUEUE_SAMPLES"] atomically:YES];
                    // Exclude the first 64 markers (~0.5 s) from a second summary
                    // so the requested window resize is separate from motion.
                    if (received > 64) Report("STEADY_QUEUE_TO_INPUT", delays+64, received-64);
                    Report("QUEUE_TO_INPUT", delays, received);
                    Report("CHANGED_FRAME_GAPS", gaps, gapCount);
                    Report("SUBMIT_GAPS", drawGaps, drawGapCount);
                    printf("RESULT sent=%lu received=%lu moved=%lu changed=%lu\n", (unsigned long)EventCount,
                        (unsigned long)received, (unsigned long)moved, (unsigned long)changed);
                    fflush(stdout);
                    BOOL motionOK = received == EventCount && moved == received && changed > 50;
                    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer *resume) {
                        BOOL paused = session.isPaused;
                        session.paused = NO;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            BOOL resumed = paused && !session.isPaused;
                            printf("%s: queued motion and pause/resume\n", motionOK && resumed ? "PASS" : "FAIL");
                            fflush(stdout);
                            exit(motionOK && resumed ? 0 : 1);
                        });
                    }];
                    session.paused = YES;
                });
            });
            }];
        }];
    }];
}

__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ Start(); });
            }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            fprintf(stderr, "FAIL: mouse queue probe timeout\n"); exit(2);
        });
    }
}
