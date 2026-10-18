// Opt-in integration probe loaded only into a disposable test copy of Boxer.
// BOXER_TEST_GAME must point to an isolated .boxer with a fresh game identifier.
@import Cocoa;
#include <sys/resource.h>
#include <stdint.h>
#import "BXEmulator.h"
#import "BXSession+BXUIControls.h"
#import "BXDOSWindowController.h"
#import "BXVideoFrame.h"

@interface NSObject (BXProbeCapture)
- (NSBitmapImageRep *)captureOutputImage;
@end

//Test-only observation of the existing SDL output queue. This does not alter
//samples, volume, buffer size, or the production app. Queue inspection is sampled
//once per 32 writes to keep the probe's overhead small and equal across builds.
extern int SDL_QueueAudio(uint32_t device, const void *data, uint32_t length);
extern uint32_t SDL_GetQueuedAudioSize(uint32_t device);
extern int SDL_GetAudioDeviceStatus(uint32_t device);
static uint64_t audioBytes, audioWrites, audioEmptySamples, audioNonSilentSamples;
static uint32_t audioQueueBytes;
static int audioDeviceStatus;
static int ProbeQueueAudio(uint32_t device, const void *data, uint32_t length) {
    audioBytes += length;
    if ((++audioWrites % 32) == 0 && length) {
        audioQueueBytes = SDL_GetQueuedAudioSize(device);
        audioDeviceStatus = SDL_GetAudioDeviceStatus(device);
        audioEmptySamples += audioQueueBytes == 0;
        const int16_t *samples = data;
        for (NSUInteger i = 0; i < length / sizeof(*samples); i++) {
            if (samples[i]) { audioNonSilentSamples++; break; }
        }
    }
    //dyld excludes the image declaring the interpose from replacement, so this
    //direct binding reaches SDL. dlsym would resolve the interposed symbol.
    return SDL_QueueAudio(device, data, length);
}
__attribute__((used, section("__DATA,__interpose"))) static const struct {
    const void *replacement;
    const void *original;
} audioInterpose = {(const void *)ProbeQueueAudio, (const void *)SDL_QueueAudio};

static double CPUSeconds(void) {
    struct rusage r;
    getrusage(RUSAGE_SELF, &r);
    return r.ru_utime.tv_sec + r.ru_utime.tv_usec * 1e-6 + r.ru_stime.tv_sec + r.ru_stime.tv_usec * 1e-6;
}

static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); fflush(stderr); exit(1); }
}

static void CheckPolicy(BXSession *session) {
    BXEmulator *emu = session.emulator;
    Class cls = NSClassFromString(@"BXEmulator");
    Check([[cls configStringForFixedSpeed:10000 isAuto:YES CPUUsage:75 cycleLimit:60000]
           isEqual:@"max 75% limit 60000"], "serialize budget and ceiling");
    Check([[cls configStringForFixedSpeed:10000 isAuto:NO CPUUsage:75 cycleLimit:60000]
           isEqual:@"fixed 10000"], "fixed speed serialization");
    Check([[cls configStringForFixedSpeed:10000 isAuto:YES CPUUsage:100 cycleLimit:-1]
           isEqual:@"max"], "legacy maximum serialization");
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"test" action:@selector(selectAutomaticCPUUsage:) keyEquivalent:@""];
    emu.autoSpeedCycleLimit = 60000;
    for (NSNumber *budget in @[@50, @75, @100]) {
        item.tag = budget.integerValue;
        [session selectAutomaticCPUUsage:item];
        Check(session.isAutoSpeed && session.autoSpeedCPUUsage == item.tag, "select automatic budget");
        [session validateMenuItem:item];
        Check(item.state == NSControlStateValueOn, "selected budget menu checkmark");
        session.CPUSpeed = 10000;
        Check(!session.isAutoSpeed, "fixed speed");
        session.autoSpeed = YES;
        Check(session.autoSpeedCPUUsage == item.tag, "fixed to automatic preserves budget");
        emu.turboSpeed = YES;
        emu.turboSpeed = NO;
        Check(session.isAutoSpeed && session.autoSpeedCPUUsage == item.tag, "turbo preserves budget");
        Check(emu.autoSpeedCycleLimit == 60000, "cycle ceiling survives speed changes");
    }
    session.autoSpeedCPUUsage = 75;
    [session synchronizeSettings];
    Check([session.gameSettings[@"autoSpeedCPUUsage"] integerValue] == 75, "persist budget");
    session.CPUSpeed = 10000;
    [session synchronizeSettings];
    Check([session.gameSettings[@"autoSpeedCPUUsage"] integerValue] == 75, "persist budget while fixed");
    NSMenuItem *limitItem = [[NSMenuItem alloc] initWithTitle:@"limit" action:@selector(selectAutomaticSpeedLimit:) keyEquivalent:@""];
    for (NSNumber *ceiling in @[@50000, @75000, @100000, @150000, @200000, @(-1)]) {
        session.CPUSpeed = 300000;
        limitItem.tag = ceiling.integerValue;
        [session selectAutomaticSpeedLimit:limitItem];
        Check(session.isAutoSpeed && emu.autoSpeedCycleLimit == limitItem.tag, "speed-limit menu selects auto and ceiling");
        Check(limitItem.tag < 0 || emu.fixedSpeed <= limitItem.tag, "new ceiling applies immediately");
        [session validateMenuItem:limitItem];
        Check(limitItem.state == NSControlStateValueOn, "speed-limit menu checkmark");
        [session synchronizeSettings];
        Check([session.gameSettings[@"autoSpeedCycleLimit"] integerValue] == limitItem.tag, "speed-limit menu saves per game");
    }
    session.CPUSpeed = 82500;
    limitItem.tag = 0;
    [session selectAutomaticSpeedLimit:limitItem];
    Check(emu.autoSpeedCycleLimit == 82500, "capture calibrated current speed");
    emu.autoSpeedCycleLimit = -1;
    session.autoSpeed = YES;
    fprintf(stdout, "PASS: CPU policy serialization, menu, fixed/auto, turbo, ceiling and save\n");
    fflush(stdout);
}

static void StartProbe(void) {
    NSString *game = NSProcessInfo.processInfo.environment[@"BOXER_TEST_GAME"];
    NSString *expectedProcess = NSProcessInfo.processInfo.environment[@"BOXER_TEST_PROCESS"] ?: @"DUKE3D";
    Check([game containsString:@"/build/"], "test game must be inside build directory");
    BOOL restoreTest = [NSProcessInfo.processInfo.environment[@"BOXER_TEST_POLICY"] integerValue] == 2;
    if (restoreTest) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[game stringByAppendingPathComponent:@"Game Info.plist"]];
        NSString *settingsKey = [@"BXGameSettings: " stringByAppendingString:info[@"BXGameIdentifier"]];
        [[NSUserDefaults standardUserDefaults] setObject:@{@"autoSpeedCPUUsage":@75, @"autoSpeedCycleLimit":@60000}
                                                 forKey:settingsKey];
        [@"[cpu]\ncore=dynamic\ncycles=fixed 10000\n" writeToFile:[game stringByAppendingPathComponent:@"DOSBox Preferences.conf"]
                                                   atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    __block BXSession *probeSession = nil;
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:game]
        display:YES completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
            Check(document != nil && error == nil, "open isolated game");
            probeSession = (id)document;
            [NSApp activateIgnoringOtherApps:YES];
        }];
    __block CFAbsoluteTime start = 0;
    __block double lastCPU = CPUSeconds();
    __block CFAbsoluteTime lastTime = CFAbsoluteTimeGetCurrent();
    __block BOOL checkedPolicy = NO;
    __block BOOL captured = NO;
    NSTimeInterval duration = MAX(44, [NSProcessInfo.processInfo.environment[@"BOXER_TEST_SECONDS"] doubleValue]);
    [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
        BXSession *session = probeSession;
        if (!session.isEmulating) return;
        BXEmulator *emu = session.emulator;
        if (restoreTest && [emu.processName.uppercaseString containsString:@"DUKE3D"]) {
            Check(!session.isAutoSpeed, "restore fixed speed from gamebox configuration");
            Check(session.autoSpeedCPUUsage == 75 && emu.autoSpeedCycleLimit == 60000, "restore saved automatic policy before launching game");
            session.autoSpeed = YES;
            [session synchronizeSettings];
            NSString *conf = [NSString stringWithContentsOfFile:[game stringByAppendingPathComponent:@"DOSBox Preferences.conf"]
                                                      encoding:NSUTF8StringEncoding error:nil];
            Check([conf containsString:@"max 75% limit 60000"], "save restored percentage and limit into portable gamebox config");
            //Closing after execution stops must use the saved policy, too.
            session.CPUSpeed = 10000;
            session.autoSpeed = YES;
            [emu setValue:@NO forKey:@"executing"];
            [session synchronizeSettings];
            conf = [NSString stringWithContentsOfFile:[game stringByAppendingPathComponent:@"DOSBox Preferences.conf"]
                                             encoding:NSUTF8StringEncoding error:nil];
            Check([conf containsString:@"max 75% limit 60000"], "save policy after emulator stops");
            fprintf(stdout, "PASS: restored policy, fixed-to-auto after reload, portable configuration and save after stopping\n");
            fflush(stdout); exit(0);
        }
        id view = session.DOSWindowController.renderingView;
        BXVideoFrame *frame = [view currentFrame];
        BOOL expectedProgram = NO;
        for (NSString *name in [expectedProcess.uppercaseString componentsSeparatedByString:@","])
            expectedProgram |= [emu.processName.uppercaseString containsString:name];
        BOOL inGame = expectedProgram && frame && !frame.containsText;
        if (!start && !inGame) {
            fprintf(stdout, "Waiting for game graphics: process=%s text=%d suspended=%d\n", emu.processName.UTF8String, frame.containsText, session.suspended);
            fflush(stdout);
            return;
        }
        if (!inGame) fprintf(stderr, "Unexpected transition: process=%s text=%d suspended=%d\n", emu.processName.UTF8String, frame.containsText, session.suspended);
        Check(inGame, "game must remain running in graphics mode throughout the probe");
        if ([NSProcessInfo.processInfo.environment[@"BOXER_TEST_CORE"] isEqual:@"normal"])
            Check(!session.isDynamic, "compatibility probe uses the normal CPU core");
        if (!start) start = CFAbsoluteTimeGetCurrent();
        double elapsed = CFAbsoluteTimeGetCurrent() - start;
        BOOL supportsBudget = [emu respondsToSelector:@selector(autoSpeedCPUUsage)];
        BOOL policyTest = [NSProcessInfo.processInfo.environment[@"BOXER_TEST_POLICY"] boolValue];
        if (supportsBudget && policyTest && elapsed >= 4 && !checkedPolicy) {
            CheckPolicy(session);
            checkedPolicy = YES;
            //A suspended emulator must keep pumping AppKit so the resume event
            //can arrive; throttling must never leave it stuck in pause.
            [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:NO block:^(NSTimer *resumeTimer) {
                Check(session.isPaused, "pause reaches the host event loop");
                session.paused = NO;
                fprintf(stdout, "PASS: paused event loop accepts resume\n");
                fflush(stdout);
            }];
            session.paused = YES;
        }
        NSInteger budget = [NSProcessInfo.processInfo.environment[@"BOXER_TEST_BUDGET"] integerValue];
        if (supportsBudget && budget > 0 && session.autoSpeedCPUUsage != budget) {
            session.autoSpeedCPUUsage = budget;
            session.autoSpeed = YES;
        }
        NSString *limit = NSProcessInfo.processInfo.environment[@"BOXER_TEST_LIMIT"];
        if (supportsBudget && limit.length) emu.autoSpeedCycleLimit = limit.integerValue;
        NSInteger fixed = [NSProcessInfo.processInfo.environment[@"BOXER_TEST_FIXED"] integerValue];
        if (fixed > 0 && (session.isAutoSpeed || session.CPUSpeed != fixed)) session.CPUSpeed = fixed;
        NSString *style = NSProcessInfo.processInfo.environment[@"BOXER_TEST_STYLE"];
        if (style.length) session.DOSWindowController.renderingStyle = style.integerValue;
        double now = CFAbsoluteTimeGetCurrent(), cpu = CPUSeconds();
        NSMutableDictionary *sample = [@{@"elapsed":@(elapsed), @"cpuPercent":@((cpu-lastCPU)/(now-lastTime)*100),
            @"cycles":@(emu.fixedSpeed), @"dynamicCore":@(session.isDynamic), @"auto":@(session.isAutoSpeed),
            @"paused":@(session.isPaused), @"budget":@(supportsBudget ? session.autoSpeedCPUUsage : 100)} mutableCopy];
        sample[@"suspended"] = @(session.suspended);
        sample[@"process"] = emu.processName;
        sample[@"gpu"] = [[view valueForKey:@"device"] name];
        if (supportsBudget) sample[@"cycleLimit"] = @(emu.autoSpeedCycleLimit);
        if ([emu respondsToSelector:@selector(hostEventPumpCount)]) {
            sample[@"eventPumps"] = @(emu.hostEventPumpCount);
            for (NSString *key in @[@"GPUTime", @"completedFrames", @"GPUFailures", @"drawableWaitTime"])
                sample[key] = [view valueForKey:key];
        }
        struct rusage usage;
        getrusage(RUSAGE_SELF, &usage);
        sample[@"voluntarySwitches"] = @(usage.ru_nvcsw);
        sample[@"involuntarySwitches"] = @(usage.ru_nivcsw);
        sample[@"audioBytes"] = @(audioBytes);
        sample[@"audioEmptySamples"] = @(audioEmptySamples);
        sample[@"audioNonSilentSamples"] = @(audioNonSilentSamples);
        sample[@"audioQueueBytes"] = @(audioQueueBytes);
        sample[@"audioDeviceStatus"] = @(audioDeviceStatus);
        if (supportsBudget) {
            sample[@"draws"] = [view valueForKey:@"submittedFrames"];
            sample[@"uploadBytes"] = [view valueForKey:@"uploadedBytes"];
        }
        sample[@"frameTime"] = @(frame.timestamp);
        if (frame) sample[@"resolution"] = NSStringFromSize(frame.size);
        NSData *json = [NSJSONSerialization dataWithJSONObject:sample options:0 error:nil];
        fprintf(stdout, "%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        fflush(stdout);
        lastTime = now; lastCPU = cpu;
        if (elapsed > 30 && !captured && frame) {
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:frame.size.width
                pixelsHigh:frame.size.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:NSBitmapFormatAlphaFirst | NSBitmapFormatThirtyTwoBitLittleEndian
                bytesPerRow:frame.pitch bitsPerPixel:32];
            memcpy(bitmap.bitmapData, frame.bytes, frame.pitch * frame.size.height);
            NSString *capture = NSProcessInfo.processInfo.environment[@"BOXER_TEST_CAPTURE"];
            if (capture) [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:capture atomically:YES];
            captured = YES;
        }
        if (elapsed >= duration) {
            Check(audioWrites > 0 && audioDeviceStatus == 1, "SDL audio device is playing queued samples");
            if ([emu respondsToSelector:@selector(hostEventPumpCount)]) {
                Check([[view valueForKey:@"GPUFailures"] unsignedIntegerValue] == 0, "game has no GPU errors");
            }
            if (supportsBudget) [session synchronizeSettings];
            //Capture the actual filtered Metal output after measurement, with
            //the live renderer's GPU submission complete before reusing uniforms.
            dispatch_semaphore_t inflight = [view valueForKey:@"inflightSemaphore"];
            Check(dispatch_semaphore_wait(inflight, dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC)) == 0,
                  "GPU finishes before output capture");
            NSBitmapImageRep *output = [[view valueForKey:@"filterChain"] captureOutputImage];
            dispatch_semaphore_signal(inflight);
            Check(output != nil, "capture filtered GPU output");
            NSString *capture = NSProcessInfo.processInfo.environment[@"BOXER_TEST_CAPTURE"];
            NSString *rendered = [[capture stringByDeletingPathExtension] stringByAppendingString:@".rendered.png"];
            if (rendered) [[output representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:rendered atomically:YES];
            fprintf(stdout, "PASS: game probe completed\n");
            fflush(stdout);
            exit(0);
        }
    }];
}

__attribute__((constructor)) static void InstallProbe(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ StartProbe(); });
            }];
        NSTimeInterval timeout = MAX(44, [NSProcessInfo.processInfo.environment[@"BOXER_TEST_SECONDS"] doubleValue]) + 90;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout*NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            fprintf(stderr, "FAIL: game probe timeout\n"); fflush(stderr); exit(2);
        });
    }
}
