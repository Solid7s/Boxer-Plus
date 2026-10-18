// Optional, passive diagnostics for a real mouse session. Never linked into Boxer.
@import Cocoa;
#import "BXSession.h"
#import "BXEmulator.h"
#import "BXEmulatedMouse.h"
#import "BXDOSWindowController.h"
#import "BXInputController.h"

static CGError ObserveAssociation(boolean_t connected) {
    CGError result = CGAssociateMouseAndMouseCursorPosition(connected);
    fprintf(stdout, "MOUSE association connected=%d result=%d\n", connected, result); fflush(stdout);
    return result;
}
static CGError ObserveWarp(CGPoint point) {
    CGError result = CGWarpMouseCursorPosition(point);
    fprintf(stdout, "MOUSE warp x=%.1f y=%.1f result=%d\n", point.x, point.y, result); fflush(stdout);
    return result;
}
__attribute__((used, section("__DATA,__interpose"))) static const struct {
    const void *replacement;
    const void *original;
} mouseInterpose[] = {
    {(const void *)ObserveAssociation, (const void *)CGAssociateMouseAndMouseCursorPosition},
    {(const void *)ObserveWarp, (const void *)CGWarpMouseCursorPosition}
};

__attribute__((constructor)) static void InstallObserver(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *notification) {
                [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp | NSEventMaskMouseEntered | NSEventMaskMouseExited
                    handler:^NSEvent *(NSEvent *event) {
                        fprintf(stdout, "MOUSE event type=%lu window=%ld location=%s\n", (unsigned long)event.type,
                            (long)event.windowNumber, NSStringFromPoint(event.locationInWindow).UTF8String); fflush(stdout);
                        return event;
                    }];
                [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
                    for (BXSession *session in [NSDocumentController sharedDocumentController].documents) {
                        if (![session respondsToSelector:@selector(emulator)]) continue;
                        BXInputController *input = session.DOSWindowController.inputController;
                        NSWindow *window = input.view.window;
                        fprintf(stdout, "MOUSE state program=%s active=%d suspended=%d key=%d front=%d locked=%d canLock=%d size=%s first=%s modal=%s\n",
                            session.emulator.processName.UTF8String ?: "", session.emulator.mouse.isActive, session.isSuspended,
                            window.isKeyWindow, NSApp.isActive, input.mouseLocked, input.canLockMouse,
                            NSStringFromSize(input.view.bounds.size).UTF8String, NSStringFromClass(window.firstResponder.class).UTF8String,
                            NSApp.modalWindow.title.UTF8String ?: "");
                    }
                    fflush(stdout);
                }];
            }];
    }
}
