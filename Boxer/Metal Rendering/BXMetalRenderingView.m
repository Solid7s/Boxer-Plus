//
//  BXMetalRenderingView.m
//  Boxer
//
//  Created by Stuart Carnie on 7/10/20.
//  
//

@import QuartzCore;
@import OpenEmuShaders;

#import "ADBGeometry.h"
#import "BXMetalRenderingView+Private.h"
#import "BXVideoFrame.h"
#import "BXMetalLayer.h"

/// Only send 1 frame at once to the GPU.
/// Since we aren't synced to the display, even one more
/// is enough to block in nextDrawable for more than a frame
/// and cause audio skipping.
/// TODO(sgc): implement triple buffering
#define MAX_INFLIGHT 1

static void *BXShaderParameterContext = &BXShaderParameterContext;

@interface BXMetalRenderingView() {
    
}

@property (nonatomic, readwrite) NSArray<OEShaderParamGroup *> *parameterGroups;

@end

@implementation BXMetalRenderingView {
    CAMetalLayer    *_videoLayer;
    OEFilterChain   *_filterChain;
    id<MTLTexture>  _texture;
    
    dispatch_semaphore_t    _inflightSemaphore;
    NSInteger               _skippedFrames;
    id<MTLDevice>           _device;
    id<MTLCommandQueue>     _commandQueue;
    MTLClearColor           _clearColor;
    
    BOOL _inViewportAnimation;
    BOOL _managesViewport;
    NSSize _maxViewportSize;
    NSRect _viewportRect;
    NSRect _targetViewportRect;
    BXRenderingStyle _renderingStyle;
    BOOL _renderingSuspended;
    BOOL _needsFramePresentation;
    NSMutableData *_pendingPixels;
    NSMutableIndexSet *_pendingRows;
    NSSize _sourceSize;
    NSSize _sourceAspect;
    NSUInteger _sourcePitch;
    NSArray<OEShaderParameter *> *_observedParameters;
    //Diagnostic counters, also exercised by Tests/RendererSmoke.m via KVC.
    NSUInteger _submittedFrames;
    NSUInteger _uploadedBytes;
    NSUInteger _completedFrames;
    NSUInteger _GPUFailures;
    NSTimeInterval _GPUTime;
    NSTimeInterval _drawableWaitTime;
}

@synthesize currentFrame=_currentFrame;
@synthesize maxFrameSize=_maxFrameSize;

+ (BOOL)prefersHighPerformanceGPU {
    NSNumber *preference = [[NSUserDefaults standardUserDefaults] objectForKey:@"useHighPerformanceGPU"];
    return preference ? preference.boolValue : YES;
}

+ (id<MTLDevice>)graphicsDeviceForHighPerformance:(BOOL)highPerformance {
    //Choose the actual built-in discrete/integrated device. The system default
    //can vary with graphics switching, so it is only the single-GPU fallback.
    for (id<MTLDevice> device in MTLCopyAllDevices()) {
        if (!device.isRemovable && device.isLowPower == !highPerformance) return device;
    }
    return MTLCreateSystemDefaultDevice();
}

+ (BOOL)supportsGraphicsProcessorSelection {
    id<MTLDevice> integrated = [self graphicsDeviceForHighPerformance:NO];
    id<MTLDevice> discrete = [self graphicsDeviceForHighPerformance:YES];
    //The fallback device is usable for rendering, but is not a second GPU.
    //Requiring an Intel integrated GPU also excludes Apple Silicon under Rosetta.
    return integrated && discrete && integrated.registryID != discrete.registryID &&
           !integrated.isRemovable && integrated.isLowPower &&
           [integrated.name localizedCaseInsensitiveContainsString:@"Intel"] &&
           !discrete.isRemovable && !discrete.isLowPower;
}

+ (id<MTLDevice>)preferredDevice {
    return [self graphicsDeviceForHighPerformance:self.prefersHighPerformanceGPU];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder: coder]) {
        self.device = [self.class preferredDevice];
        [self initDefaults];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    id<MTLDevice> device = [self.class preferredDevice];
    
    if (self = [super initWithFrame: frameRect device:device]) {
        [self initDefaults];
    }
    return self;
}

- (OEFilterChain *)filterChain {
    return _filterChain;
}

- (void)initDefaults {
    _inflightSemaphore = dispatch_semaphore_create(MAX_INFLIGHT);
    _device = self.device;
    self.framebufferOnly = YES;
    self.presentsWithTransaction = NO;
    //Static filters redraw only on invalidation. CRT's frame-count animation
    //uses the display timer only while the game is active and visible.
    self.paused = YES;
    self.enableSetNeedsDisplay = YES;
    _pendingRows = [NSMutableIndexSet indexSet];
    
    _commandQueue      = [_device newCommandQueue];
    _clearColor        = MTLClearColorMake(0, 0, 0, 1);
    _filterChain = [[OEFilterChain alloc] initWithDevice:_device];
    [_filterChain setDefaultFilteringLinear:NO];
    
    // some reasonable default
    [_filterChain setSourceRect:CGRectMake(0, 0, 648, 480) aspect:CGSizeMake(4, 3)];
    self.renderingStyle = BXRenderingStyleNormal;
    
    self.wantsLayer = YES;
    
    _videoLayer = (CAMetalLayer *)self.layer;
    
    [self updateRenderState];
    
    _maxFrameSize = NSMakeSize(16384, 16384);
}

- (BOOL)supportsRenderingStyle:(BXRenderingStyle)style {
    return style >= BXRenderingStyleNormal && style < BXNumRenderingStyles;
}

- (void)setRenderingStyle:(BXRenderingStyle)renderingStyle {
    if (renderingStyle == _renderingStyle)
    {
        return;
    }
    
    [self willChangeValueForKey:@"renderingStyle"];
    
    _renderingStyle = renderingStyle;
    
    switch (renderingStyle) {
    case BXRenderingStyleNormal: {
        NSURL *path = [NSBundle.mainBundle URLForResource:@"Pixellate" withExtension:@"slangp" subdirectory:@"Shaders/Pixellate"];
        [_filterChain setShaderFromURL:path error:nil];
        break;
    }
        
    case BXRenderingStyleCRT: {
        NSURL *path = [NSBundle.mainBundle URLForResource:@"CRT Geom" withExtension:@"slangp" subdirectory:@"Shaders/CRT Geom"];
        [_filterChain setShaderFromURL:path error:nil];
        break;
    }

    case BXRenderingStyleCRTLight: {
        NSURL *path = [NSBundle.mainBundle URLForResource:@"CRT Light" withExtension:@"slangp" subdirectory:@"Shaders/CRT Light"];
        NSError *error = nil;
        if (![_filterChain setShaderFromURL:path error:&error]) NSLog(@"Could not load CRT Light: %@", error);
        break;
    }
        
    case BXRenderingStyleSmoothed: {
        NSURL *path = [NSBundle.mainBundle URLForResource:@"Smooth" withExtension:@"slangp"  subdirectory:@"Shaders/Smooth"];
        [_filterChain setShaderFromURL:path error:nil];
        break;
    }
    default: break;
    }
    
    [self didChangeValueForKey:@"renderingStyle"];
    
    self.parameterGroups = _filterChain.shader.parameterGroups;
    for (OEShaderParameter *parameter in _observedParameters)
        [parameter removeObserver:self forKeyPath:@"value" context:BXShaderParameterContext];
    NSMutableArray *parameters = [NSMutableArray array];
    for (OEShaderParamGroup *group in self.parameterGroups)
        [parameters addObjectsFromArray:group.parameters];
    _observedParameters = parameters;
    for (OEShaderParameter *parameter in _observedParameters)
        [parameter addObserver:self forKeyPath:@"value" options:0 context:BXShaderParameterContext];
    [self updateDrawingMode];
    [self invalidateFrame];
}

- (void)updateWithFrame:(BXVideoFrame *)frame {
    //DOS frames and AppKit presentation are delivered on the main thread.
    //Copy changed rows now: DOSBox reuses both the pixel buffer and dirty list
    //before a deferred draw may happen. Upload only after the previous GPU job
    //has completed, so the CPU never modifies a texture still being sampled.
    if (frame == nil) {
        _currentFrame = nil;
        _pendingPixels = nil;
        [_pendingRows removeAllIndexes];
        _sourceSize = NSZeroSize;
        [self updateDrawingMode];
        [self invalidateFrame];
        return;
    }

    BOOL newBuffer = frame != _currentFrame || !NSEqualSizes(frame.size, _sourceSize);
    BOOL aspectChanged = !NSEqualSizes(frame.scaledSize, _sourceAspect);
    if (newBuffer) {
        if (NSIsEmptyRect(self.viewportRect)) {
            NSRect viewportRect = [self viewportForFrame:frame];
            [self setViewportRect:viewportRect animated:NO];
        }
        _currentFrame = frame;
        _sourceSize = frame.size;
        _sourcePitch = frame.pitch;
        _pendingPixels = [NSMutableData dataWithBytes:frame.bytes length:frame.pitch * frame.size.height];
        [_pendingRows removeAllIndexes];
        [_pendingRows addIndexesInRange:NSMakeRange(0, frame.size.height)];
        [self updateDrawingMode];
    } else {
        for (NSUInteger i = 0; i < frame.numDirtyRegions; i++) {
            NSRange rows = NSIntersectionRange([frame dirtyRegionAtIndex:i], NSMakeRange(0, frame.size.height));
            if (!rows.length) continue;
            NSUInteger offset = rows.location * _sourcePitch;
            memcpy((uint8_t *)_pendingPixels.mutableBytes + offset,
                   (const uint8_t *)frame.bytes + offset, rows.length * _sourcePitch);
            [_pendingRows addIndexesInRange:rows];
        }
    }
    _sourceAspect = frame.scaledSize;
    if (newBuffer || aspectChanged || _pendingRows.count) [self invalidateFrame];
    
    // If the frame changes size or aspect ratio, and we're responsible for the viewport ourselves,
    // then smoothly animate the transition to the new size.
    if (self.managesViewport)
    {
        [self setViewportRect:[self viewportForFrame:frame] animated:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    if (![self canPresent]) return;
    _needsFramePresentation = YES;
    
    @autoreleasepool {
        if (dispatch_semaphore_wait(_inflightSemaphore, DISPATCH_TIME_NOW) != 0) {
            _skippedFrames++;
        } else {
            CFTimeInterval drawableStart = CACurrentMediaTime();
            id<CAMetalDrawable> drawable = _videoLayer.nextDrawable;
            _drawableWaitTime += CACurrentMediaTime() - drawableStart;
            if (drawable != nil) {
                if (_currentFrame) {
                    if (_texture.width != _sourceSize.width || _texture.height != _sourceSize.height) {
                        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                            width:_sourceSize.width height:_sourceSize.height mipmapped:NO];
                        _texture = [_device newTextureWithDescriptor:td];
                        [_filterChain setSourceTexture:_texture];
                    }
                    [_pendingRows enumerateRangesUsingBlock:^(NSRange rows, BOOL *stop) {
                        [self->_texture replaceRegion:MTLRegionMake2D(0, rows.location, self->_sourceSize.width, rows.length)
                            mipmapLevel:0 withBytes:(const uint8_t *)self->_pendingPixels.bytes + rows.location * self->_sourcePitch
                            bytesPerRow:self->_sourcePitch];
                        self->_uploadedBytes += rows.length * self->_sourcePitch;
                    }];
                    [_pendingRows removeAllIndexes];
                    [_filterChain setSourceRect:CGRectMake(0, 0, _sourceSize.width, _sourceSize.height) aspect:_sourceAspect];
                } else {
                    _texture = nil;
                    [_filterChain setSourceTexture:nil];
                }
                //One submission and one completion cover both stages. In
                //particular, a missing drawable must not leave offscreen work
                //running after we release the single in-flight slot.
                id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
                commandBuffer.label = @"Boxer frame";
                if (_texture) [_filterChain renderOffscreenPassesWithCommandBuffer:commandBuffer];
                MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor new];
                rpd.colorAttachments[0].clearColor = _clearColor;
                // TODO: Use MTLLoadActionDontCare
                // We can use MTLLoadActionDontCare when source texture
                // is same aspect ratio as drawable (i.e. windowed)
                rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
                rpd.colorAttachments[0].texture    = drawable.texture;
                id<MTLRenderCommandEncoder> rce = [commandBuffer renderCommandEncoderWithDescriptor:rpd];
                if (_texture) [_filterChain renderFinalPassWithCommandEncoder:rce];
                [rce endEncoding];
                
                dispatch_semaphore_t inflight = _inflightSemaphore;
                __weak BXMetalRenderingView *weakSelf = self;
                [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                    NSTimeInterval GPUTime = 0;
                    if (@available(macOS 10.15, *))
                        GPUTime = MAX(0, completed.GPUEndTime - completed.GPUStartTime);
                    BOOL failed = completed.status == MTLCommandBufferStatusError;
                    if (failed) NSLog(@"Boxer Metal submission failed: %@", completed.error);
                    dispatch_semaphore_signal(inflight);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        BXMetalRenderingView *view = weakSelf;
                        if (view) {
                            view->_completedFrames++;
                            view->_GPUTime += GPUTime;
                            view->_GPUFailures += failed;
                            if (view->_needsFramePresentation) [view invalidateFrame];
                        }
                    });
                }];
                
                [commandBuffer presentDrawable:drawable];
                _needsFramePresentation = NO;
                _submittedFrames++;
                [commandBuffer commit];
            } else {
                dispatch_semaphore_signal(self->_inflightSemaphore);
            }
        }
    }
}

- (BOOL)canPresent {
    return self.window && self.window.isVisible && !self.isHiddenOrHasHiddenAncestor &&
        (self.window.occlusionState & NSWindowOcclusionStateVisible) && !NSIsEmptyRect(self.bounds);
}

- (void)invalidateFrame {
    _needsFramePresentation = YES;
    if ([self canPresent]) [self setNeedsDisplay:YES];
}

- (void)updateDrawingMode {
    self.paused = !(_renderingStyle == BXRenderingStyleCRT && _currentFrame &&
                    !_renderingSuspended && [self canPresent]);
}

- (void)setRenderingSuspended:(BOOL)suspended {
    if (_renderingSuspended == suspended) return;
    _renderingSuspended = suspended;
    [self updateDrawingMode];
    [self invalidateFrame];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidChangeOcclusionStateNotification object:nil];
    if (self.window) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(visibilityChanged:)
        name:NSWindowDidChangeOcclusionStateNotification object:self.window];
    [self updateRenderState];
    [self visibilityChanged:nil];
}

- (void)visibilityChanged:(NSNotification *)notification {
    [self updateDrawingMode];
    [self invalidateFrame];
}

- (void)viewDidHide {
    [super viewDidHide];
    [self visibilityChanged:nil];
}

- (void)viewDidUnhide {
    [super viewDidUnhide];
    [self visibilityChanged:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == BXShaderParameterContext) [self invalidateFrame];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (OEShaderParameter *parameter in _observedParameters)
        [parameter removeObserver:self forKeyPath:@"value" context:BXShaderParameterContext];
}

#pragma mark - Viewport / Bounds

- (void)updateRenderState {
    [_videoLayer setBounds:self.bounds];
    NSRect rect = [self convertRectToBacking:self.bounds];
    _videoLayer.drawableSize = NSSizeToCGSize(rect.size);
    [_filterChain setDrawableSize:_videoLayer.drawableSize];
    if (self.currentFrame) {
        [self setViewportRect:[self viewportForFrame:self.currentFrame] animated:NO];
    }
    [self invalidateFrame];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (!self.inLiveResize) {
        [self updateRenderState];
    }
}

- (void) viewDidEndLiveResize
{
    [self updateRenderState];
}

- (void) windowDidChangeBackingProperties: (NSNotification *)notification
{
    [self updateRenderState];
}

#pragma mark - Animation

+ (id) defaultAnimationForKey: (NSString *)key
{
    if ([key isEqualToString: @"viewportRect"])
    {
        CABasicAnimation *animation = [CABasicAnimation animation];
        animation.duration = 0.2;
        animation.timingFunction = [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseIn];
        return animation;
    }
    else
    {
        return [super defaultAnimationForKey:key];
    }
}

- (void)animationDidStart:(CAAnimation *)anim
{
    _inViewportAnimation = YES;
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    _inViewportAnimation = NO;
    anim.delegate = nil;
}

//Returns the rectangular region of the view into which the specified frame should be drawn.
- (NSRect)viewportForFrame:(BXVideoFrame *)frame
{
    if (frame != nil && self.managesViewport)
    {
        NSSize frameSize = frame.scaledSize;
        NSRect frameRect = NSMakeRect(0.0f, 0.0f, frameSize.width, frameSize.height);
        
        NSRect canvasRect = self.bounds;
        NSRect maxViewportRect = canvasRect;
        
        //If we have a maximum viewport size, fit the frame within that; otherwise, just fill the canvas as best we can.
        if (!NSEqualSizes(self.maxViewportSize, NSZeroSize) && sizeFitsWithinSize(self.maxViewportSize, canvasRect.size))
        {
            maxViewportRect = resizeRectFromPoint(canvasRect, self.maxViewportSize, NSMakePoint(0.5f, 0.5f));
        }
        
        NSRect fittedViewportRect = fitInRect(frameRect, maxViewportRect, NSMakePoint(0.5f, 0.5f));
        
        return fittedViewportRect;
    }
    else
    {
        return self.bounds;
    }
}

- (void) setManagesViewport:(BOOL)enabled
{
    if (_managesViewport != enabled)
    {
        _managesViewport = enabled;
        
        // Update our viewport immediately to compensate for the change
        [self setViewportRect:[self viewportForFrame:self.currentFrame]
                     animated:NO];
    }
}

- (void)setViewportRect:(NSRect)newRect
{
    if (!NSEqualRects(newRect, _viewportRect))
    {
        _viewportRect = newRect;
        [self invalidateFrame];
    }
}

- (void)setViewportRect:(NSRect)newRect animated:(BOOL)animated
{
    if (!NSEqualRects(_targetViewportRect, newRect))
    {
        //If our viewport is zero (i.e. we haven't received a frame until now)
        //then just replace the viewport with the new one instead of animating to it.
        if (!animated || NSIsEmptyRect(_viewportRect))
        {
            _targetViewportRect = newRect;
            self.viewportRect = newRect;
        }
        else
        {
            _targetViewportRect = newRect;
            
            [NSAnimationContext beginGrouping]; {
                NSAnimationContext.currentContext.duration = 0.2;
                [self.animator setViewportRect:_targetViewportRect];
                [NSAnimationContext endGrouping];
            }
        }
    }
}


@end
