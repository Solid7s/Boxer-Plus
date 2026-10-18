// Loaded into a test copy of Boxer so this exercises its actual compiled renderer.
// Does not open games or touch game saves. See run-performance-tests.sh.
@import Cocoa;
@import Metal;
@import QuartzCore;
#import <objc/runtime.h>
#import "BXMetalRenderingView.h"
#import "BXVideoFrame.h"

@interface NSObject (BXGPUMenuTests)
- (void)selectGraphicsProcessor:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static void Pump(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                         untilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]
                                            inMode:NSDefaultRunLoopMode dequeue:YES];
        if (event) [NSApp sendEvent:event];
        [NSApp updateWindows];
        [CATransaction flush];
    }
}

static NSUInteger Count(id view, NSString *key) {
    return [[view valueForKey:key] unsignedIntegerValue];
}

static NSMenuItem *GPUMenuItem(NSMenu *menu, NSInteger tag) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(selectGraphicsProcessor:) && item.tag == tag) return item;
        NSMenuItem *nested = item.submenu ? GPUMenuItem(item.submenu, tag) : nil;
        if (nested) return nested;
    }
    return nil;
}

//Only device metadata is faked; these exercise the app's compiled capability
//check, menu validation and action without needing a second physical Mac.
@interface BXMenuTestDevice : NSObject
@property (copy) NSString *name;
@property uint64_t registryID;
@property (getter=isLowPower) BOOL lowPower;
@property (getter=isRemovable) BOOL removable;
@end
@implementation BXMenuTestDevice
@end

static id FakeIntegratedDevice, FakeDiscreteDevice;

static id FakeGraphicsDevice(id self, SEL selector, BOOL highPerformance) {
    return highPerformance ? FakeDiscreteDevice : FakeIntegratedDevice;
}

static BXMenuTestDevice *MenuTestDevice(NSString *name, uint64_t registryID, BOOL lowPower, BOOL removable) {
    BXMenuTestDevice *device = [BXMenuTestDevice new];
    device.name = name;
    device.registryID = registryID;
    device.lowPower = lowPower;
    device.removable = removable;
    return device;
}

static void CheckUnavailableGPUChoices(id controller, NSMenuItem *discreteItem, NSMenuItem *integratedItem) {
    BXMenuTestDevice *intel = MenuTestDevice(@"Intel Iris Graphics", 1, YES, NO);
    //Also reject non-Intel integrated devices even if marked low-power.
    BXMenuTestDevice *apple = MenuTestDevice(@"Apple M2", 2, YES, NO);
    BXMenuTestDevice *discrete = MenuTestDevice(@"AMD Radeon Pro", 3, NO, NO);
    BXMenuTestDevice *external = MenuTestDevice(@"AMD External GPU", 4, NO, YES);
    NSNull *none = NSNull.null;
    NSArray *cases = @[
        @[intel, intel, @"Intel integrated only"],
        @[apple, apple, @"Apple Silicon, including Rosetta"],
        @[discrete, discrete, @"discrete only"],
        @[intel, external, @"Intel with only an external discrete GPU"],
        @[apple, discrete, @"Apple GPU cannot be offered as Integrated Intel GPU"],
        @[none, discrete, @"missing integrated device"],
        @[intel, none, @"missing discrete device"],
        @[none, none, @"no Metal devices"]
    ];
    Class renderer = NSClassFromString(@"BXMetalRenderingView");
    Method lookup = class_getClassMethod(renderer, @selector(graphicsDeviceForHighPerformance:));
    IMP original = method_setImplementation(lookup, (IMP)FakeGraphicsDevice);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:@"useHighPerformanceGPU"];
    @try {
        for (NSArray *scenario in cases) {
            FakeIntegratedDevice = scenario[0] == none ? nil : scenario[0];
            FakeDiscreteDevice = scenario[1] == none ? nil : scenario[1];
            for (NSNumber *preference in @[@NO, @YES]) {
                [defaults setObject:preference forKey:@"useHighPerformanceGPU"];
                for (NSMenuItem *item in @[discreteItem, integratedItem]) {
                    Check(![controller validateMenuItem:item] && item.state == NSControlStateValueOff,
                          [NSString stringWithFormat:@"%@ disables both choices without a misleading checkmark", scenario[2]]);
                    Check([item.title isEqualToString:item.tag ? @"Discrete GPU" : @"Integrated Intel GPU"],
                          @"disabled choices retain the requested labels");
                    [controller selectGraphicsProcessor:item];
                    Check([[defaults objectForKey:@"useHighPerformanceGPU"] isEqual:preference],
                          @"unavailable GPU action cannot change the saved preference");
                }
            }
        }
    } @finally {
        method_setImplementation(lookup, original);
        FakeIntegratedDevice = FakeDiscreteDevice = nil;
        if (saved) [defaults setObject:saved forKey:@"useHighPerformanceGPU"];
        else [defaults removeObjectForKey:@"useHighPerformanceGPU"];
    }
    fprintf(stdout, "PASS: disabled GPU choices for eight simulated device configurations\n");
}

static void RunRendererTests(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"useHighPerformanceGPU"];
    id<MTLDevice> discrete = nil, integrated = nil;
    for (id<MTLDevice> device in MTLCopyAllDevices()) {
        if (device.isRemovable) continue;
        if (device.isLowPower && !integrated) integrated = device;
        if (!device.isLowPower && !discrete) discrete = device;
    }
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(150, 150, 640, 480)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:NO];
    //Keep the application alive when the renderer window is hidden to test
    //occlusion: Boxer now quits normally after its final window closes.
    NSWindow *companion = [[NSWindow alloc] initWithContentRect:NSMakeRect(20, 20, 220, 80)
                                                    styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:NO];
    companion.title = @"Boxer Renderer Check";
    [companion orderBack:nil];
    BXMetalRenderingView *view = [[NSClassFromString(@"BXMetalRenderingView") alloc] initWithFrame:window.contentView.bounds];
    Check(view.device.registryID == (discrete ?: MTLCreateSystemDefaultDevice()).registryID,
          @"default selects built-in performance GPU when available");
    id controller = [[NSClassFromString(@"BXDOSWindowController") alloc] initWithWindow:nil];
    NSMenuItem *performanceItem = GPUMenuItem(NSApp.mainMenu, 1);
    NSMenuItem *energyItem = GPUMenuItem(NSApp.mainMenu, 0);
    Check(performanceItem && energyItem, @"compiled View menu has both wired GPU choices");
    Check([performanceItem.title isEqualToString:@"Discrete GPU"] &&
          [energyItem.title isEqualToString:@"Integrated Intel GPU"], @"compiled menu has the requested GPU labels");
    CheckUnavailableGPUChoices(controller, performanceItem, energyItem);
    BOOL separateGPUs = discrete && integrated && discrete.registryID != integrated.registryID &&
                        [integrated.name localizedCaseInsensitiveContainsString:@"Intel"];
    Check([controller validateMenuItem:performanceItem] == separateGPUs &&
          performanceItem.state == (separateGPUs ? NSControlStateValueOn : NSControlStateValueOff),
          @"discrete is checked by default only when both GPU choices are available");
    Check([controller validateMenuItem:energyItem] == separateGPUs, @"both choices require supported separate GPUs");
    [controller selectGraphicsProcessor:energyItem];
    if (separateGPUs) Check(![defaults boolForKey:@"useHighPerformanceGPU"], @"integrated menu choice is remembered");
    else Check([defaults objectForKey:@"useHighPerformanceGPU"] == nil, @"unsupported choice leaves the default preference unset");
    BXMetalRenderingView *lowPower = [[NSClassFromString(@"BXMetalRenderingView") alloc] initWithFrame:window.contentView.bounds];
    Check(lowPower.device.registryID == (separateGPUs ? integrated.registryID : view.device.registryID),
          @"reopened view uses selected integrated GPU or the available default");
    Check(view.device.registryID == (discrete ?: MTLCreateSystemDefaultDevice()).registryID,
          @"changing selection leaves the live renderer on its original GPU");
    [controller validateMenuItem:energyItem];
    if (separateGPUs) {
        Check(energyItem.state == NSControlStateValueOn && [energyItem.title isEqualToString:@"Integrated Intel GPU"],
              @"integrated GPU label and selection appear in menu");
    }
    window.contentView = lowPower;
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    BXVideoFrame *gpuFrame = [[NSClassFromString(@"BXVideoFrame") alloc] initWithSize:NSMakeSize(320, 200) depth:4];
    memset(gpuFrame.mutableBytes, 0x40, gpuFrame.pitch * 200);
    [lowPower updateWithFrame:gpuFrame];
    Pump(0.4);
    Check(Count(lowPower, @"submittedFrames") > 0 && Count(lowPower, @"GPUFailures") == 0,
          @"integrated GPU renders a frame successfully");
    [controller selectGraphicsProcessor:performanceItem];
    [controller validateMenuItem:performanceItem];
    if (separateGPUs) {
        Check([defaults boolForKey:@"useHighPerformanceGPU"] && performanceItem.state == NSControlStateValueOn,
              @"discrete menu choice is remembered and checked");
    } else {
        Check([defaults objectForKey:@"useHighPerformanceGPU"] == nil && performanceItem.state == NSControlStateValueOff,
              @"unsupported discrete choice leaves the default preference unset and unchecked");
    }
    BXMetalRenderingView *reopened = [[NSClassFromString(@"BXMetalRenderingView") alloc] initWithFrame:window.contentView.bounds];
    Check(reopened.device.registryID == view.device.registryID, @"reopening applies the performance selection");
    NSLog(@"GPU menu: %@ / %@", performanceItem.title, energyItem.title);
    reopened = nil;
    window.contentView = view;
    lowPower = nil;
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    Pump(0.3);

    BXVideoFrame *frame = [[NSClassFromString(@"BXVideoFrame") alloc] initWithSize:NSMakeSize(320, 200) depth:4];
    memset(frame.mutableBytes, 0x40, frame.pitch * 200);
    [view updateWithFrame:frame];
    Pump(0.3);
    NSLog(@"Renderer test: device=%@ visible=%d occlusion=%lu hidden=%d paused=%d needsDisplay=%d bounds=%@ uploads=%lu draws=%lu",
          view.device.name, window.isVisible, (unsigned long)window.occlusionState, view.isHiddenOrHasHiddenAncestor,
          view.isPaused, view.needsDisplay, NSStringFromRect(view.bounds), Count(view, @"uploadedBytes"), Count(view, @"submittedFrames"));
    Check(Count(view, @"submittedFrames") > 0, @"first frame must be presented");
    Check(Count(view, @"uploadedBytes") == frame.pitch * 200, @"first frame needs one full upload");

    NSUInteger draws = Count(view, @"submittedFrames");
    NSUInteger bytes = Count(view, @"uploadedBytes");
    for (NSUInteger i = 0; i < 120; i++) [view updateWithFrame:frame];
    Pump(0.3);
    Check(Count(view, @"submittedFrames") == draws, @"unchanged normal frames must not redraw");
    Check(Count(view, @"uploadedBytes") == bytes, @"unchanged frames must not upload");

    // Emulate several DOS updates before presentation. The mutable frame and its
    // dirty list are reused, just as BXVideoHandler reuses them in the application.
    [frame setNeedsDisplayInRegion:NSMakeRange(10, 2)];
    memset((uint8_t *)frame.mutableBytes + frame.pitch * 10, 0x77, frame.pitch * 2);
    [view updateWithFrame:frame];
    [frame clearDirtyRegions];
    [frame setNeedsDisplayInRegion:NSMakeRange(30, 1)];
    memset((uint8_t *)frame.mutableBytes + frame.pitch * 30, 0x99, frame.pitch);
    [view updateWithFrame:frame];
    [frame clearDirtyRegions];
    Pump(0.3);
    Check(Count(view, @"uploadedBytes") - bytes == frame.pitch * 3, @"coalesced dirty rows only");
    id<MTLTexture> texture = [view valueForKey:@"texture"];
    NSMutableData *pixels = [NSMutableData dataWithLength:frame.pitch * 200];
    [texture getBytes:pixels.mutableBytes bytesPerRow:frame.pitch fromRegion:MTLRegionMake2D(0, 0, 320, 200) mipmapLevel:0];
    Check(memcmp(pixels.bytes, frame.bytes, pixels.length) == 0, @"all dirty rows survive coalescing");

    // Hold the in-flight slot to exercise the retry path without timing luck.
    dispatch_semaphore_t inflight = [view valueForKey:@"inflightSemaphore"];
    dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
    [frame setNeedsDisplayInRegion:NSMakeRange(60, 1)];
    memset((uint8_t *)frame.mutableBytes + frame.pitch * 60, 0xbb, frame.pitch);
    [view updateWithFrame:frame];
    [view draw];
    Check(Count(view, @"skippedFrames") > 0, @"busy GPU must skip instead of waiting");
    dispatch_semaphore_signal(inflight);
    [view setNeedsDisplay:YES];
    Pump(0.3);
    [frame clearDirtyRegions];
    Check(Count(view, @"uploadedBytes") - bytes == frame.pitch * 4, @"busy GPU preserves pending rows");

    view.renderingStyle = BXRenderingStyleCRTLight;
    Pump(0.4);
    Check([[view valueForKey:@"filterChain"] valueForKey:@"shader"] != nil, @"CRT Light shader compiles");
    draws = Count(view, @"submittedFrames");
    Pump(0.3);
    Check(Count(view, @"submittedFrames") == draws, @"static CRT Light must not animate unchanged frames");
    [frame setNeedsDisplayInRegion:NSMakeRange(100, 1)];
    [view updateWithFrame:frame];
    [frame clearDirtyRegions];
    Pump(0.3);
    Check(Count(view, @"submittedFrames") > draws, @"CRT Light presents changed game frames");
    Check(Count(view, @"GPUFailures") == 0, @"CRT Light submits successfully");

    view.renderingStyle = BXRenderingStyleCRT;
    Pump(0.4);
    draws = Count(view, @"submittedFrames");
    Pump(0.3);
    Check(Count(view, @"submittedFrames") > draws, @"CRT animation continues without new DOS pixels");
    view.renderingSuspended = YES;
    Pump(0.2);
    draws = Count(view, @"submittedFrames");
    Pump(0.3);
    Check(Count(view, @"submittedFrames") == draws, @"pause stops CRT animation");

    NSArray *groups = view.parameterGroups;
    if (groups.count) {
        id parameter = [[groups[0] valueForKey:@"parameters"] firstObject];
        if (parameter) {
            [parameter setValue:[parameter valueForKey:@"value"] forKey:@"value"];
            Pump(0.2);
            Check(Count(view, @"submittedFrames") > draws, @"shader controls redraw while paused");
        }
    }

    view.renderingSuspended = NO;
    [window orderOut:nil];
    Pump(0.2);
    draws = Count(view, @"submittedFrames");
    Pump(0.3);
    Check(Count(view, @"submittedFrames") == draws, @"occlusion stops rendering");
    [window makeKeyAndOrderFront:nil];
    Pump(0.3);
    Check(Count(view, @"submittedFrames") > draws, @"exposure resumes CRT");

    view.renderingStyle = BXRenderingStyleNormal;
    view.renderingSuspended = YES;
    Pump(0.2);
    draws = Count(view, @"submittedFrames");
    [window setContentSize:NSMakeSize(700, 500)];
    Pump(0.3);
    Check(Count(view, @"submittedFrames") > draws, @"resize redraws a paused frame");
    [view updateWithFrame:nil];
    Pump(0.2);
    Check(view.currentFrame == nil, @"clearing a frame releases the source");
    [view updateWithFrame:frame];
    Pump(0.2);
    Check(view.currentFrame == frame, @"new source after clear is presented");
    Check(Count(view, @"GPUFailures") == 0, @"all render styles complete without GPU errors");
    Check(companion.isVisible, @"companion window keeps the renderer test alive through occlusion");
    fprintf(stdout, "PASS: GPU selection, first frame, unchanged frames, dirty rows, coalescing, busy GPU, CRT Light, CRT, pause, shader controls, occlusion, resize, clear/resume\n");
    fflush(stdout);
    exit(0);
}

__attribute__((constructor)) static void InstallTests(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                //Do not hold the main dispatch queue while pumping the AppKit
                //loop: MetalKit and command-buffer completions use that queue.
                [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer *timer) { RunRendererTests(); }];
            }];
    }
}
