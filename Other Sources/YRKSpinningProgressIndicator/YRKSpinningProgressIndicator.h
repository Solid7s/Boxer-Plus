//
//  YRKSpinningProgressIndicator.h
//
//  Copyright 2009 Kelan Champagne. All rights reserved.
//

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface YRKSpinningProgressIndicator : NSView {
    int _position;
    int _numFins;
    
    BOOL _isAnimating;
    NSTimer *_animationTimer;
	NSThread *_animationThread;
    
    NSColor *_foreColor;
    NSColor *_backColor;
    BOOL _drawBackground;
    
    NSTimer *_fadeOutAnimationTimer;
    BOOL _isFadingOut;
    
    // For determinate mode
    BOOL _isIndeterminate;
    double _currentValue;
    double _maxValue;
    CGFloat _lineWidth;
    CGFloat _lineStartOffset;
    CGFloat _lineEndOffset;
    
    BOOL _usesThreadedAnimation;
}

//A property for bindings. Calls stopAnimation/startAnimation when set.
@property (nonatomic, assign, getter=isAnimating) IBInspectable BOOL animating;

@property (nonatomic, assign, getter=isIndeterminate) IBInspectable BOOL indeterminate;
@property (nonatomic, copy) IBInspectable NSColor *color;
@property (nonatomic, copy) IBInspectable NSColor *backgroundColor;
@property (nonatomic, assign) IBInspectable BOOL drawsBackground;
@property (nonatomic, assign) IBInspectable double doubleValue;
@property (nonatomic, assign) IBInspectable double maxValue;
@property (nonatomic, assign) BOOL usesThreadedAnimation;
@property (nonatomic, assign) IBInspectable CGFloat lineWidth;
@property (nonatomic, assign) IBInspectable CGFloat lineStartOffset;
@property (nonatomic, assign) IBInspectable CGFloat lineEndOffset;

- (IBAction)stopAnimation: (id)sender;
- (IBAction)startAnimation: (id)sender;

@end
