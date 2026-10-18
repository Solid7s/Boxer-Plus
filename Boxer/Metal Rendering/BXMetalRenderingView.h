//
//  BXMetalRenderingView.h
//  Boxer
//
//  Created by Stuart Carnie on 7/10/20.
//  
//

@import Foundation;
@import MetalKit;

#import "BXFrameRenderingView.h"

NS_ASSUME_NONNULL_BEGIN

@interface BXMetalRenderingView : MTKView<BXFrameRenderingView>

// Shared by the renderer and the GPU menu so displayed and selected devices agree.
+ (BOOL)prefersHighPerformanceGPU;
+ (nullable id<MTLDevice>)graphicsDeviceForHighPerformance:(BOOL)highPerformance;
+ (BOOL)supportsGraphicsProcessorSelection;

@property (readwrite, nonatomic) BXRenderingStyle renderingStyle;
@property (readwrite, nonatomic) BOOL renderingSuspended;
@property (assign, nonatomic) BOOL managesViewport;
@property (assign, nonatomic) NSSize maxViewportSize;
@property (readonly, nonatomic) NSRect viewportRect;

@end

NS_ASSUME_NONNULL_END
