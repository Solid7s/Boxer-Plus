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

@property (readwrite, nonatomic) BXRenderingStyle renderingStyle;
@property (assign, nonatomic) BOOL managesViewport;
@property (assign, nonatomic) NSSize maxViewportSize;
@property (readonly, nonatomic) NSRect viewportRect;

@end

NS_ASSUME_NONNULL_END
