//
//  BXMetalRenderingView+BXImageCapture.m
//  Boxer
//
//  Created by Stuart Carnie on 7/11/20.
//  
//

@import OpenEmuShaders;

#import "BXMetalRenderingView+BXImageCapture.h"
#import "BXMetalRenderingView+Private.h"

@implementation BXMetalRenderingView (BXImageCapture)

- (NSBitmapImageRep *)bitmapImageRepForCachingDisplayInRect:(NSRect)rect {
    // HACK: This is cheating, as this should return a container
    // suitable for storing the image in a call to cacheDisplayInRect:ToBitmapImageRep:
    return [self.filterChain captureOutputImage];
}

- (void)cacheDisplayInRect:(NSRect)rect toBitmapImageRep:(NSBitmapImageRep *)rep {
    // do nothing, because we captured the image in bitmapImageRepForCachingDisplayInRect
}

@end
