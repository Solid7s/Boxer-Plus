/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXThemedButtonCell.h"
#import "ADBGeometry.h"
#import "Boxer-Swift.h"

@implementation BXThemedButtonCell

#pragma mark - Default theme handling

+ (NSString *) defaultThemeKey
{
    return nil;
}

- (void) setThemeKey: (NSString *)key
{
    if (![key isEqual: self.themeKey])
    {
        _themeKey = [key copy];
        
        [self.controlView setNeedsDisplay: YES];
    }
}

- (id) initWithCoder: (NSCoder *)coder
{
    self = [super initWithCoder: coder];
    if (self)
    {
        if (![coder containsValueForKey: @"themeKey"])
            self.themeKey = [self.class defaultThemeKey];
    }
    return self;
}

- (NSRect) imageRectForImage: (NSImage *)image forBounds: (NSRect)frame
{   
    NSRect insetFrame = [self imageRectForBounds: frame];
    
    NSImageAlignment alignment;
    
    switch (self.imagePosition)
    {
        case NSImageOnly:
        case NSImageOverlaps:
            alignment = NSImageAlignCenter;
            break;
        case NSImageLeft:
            alignment = NSImageAlignLeft;
            break;
        case NSImageRight:
            alignment = NSImageAlignRight;
            break;
        case NSImageAbove:
            alignment = NSImageAlignTop;
            break;
        case NSNoImage:
        default:
            return NSZeroRect;
    }
    
    NSRect imageFrame = [image imageRectAlignedInRect: insetFrame
                                            alignment: alignment
                                              scaling: self.imageScaling];
    
    return imageFrame;
}


- (NSRect) titleRectForBounds: (NSRect)frame
             withCheckboxRect: (NSRect)checkboxFrame
{
    NSRect textFrame = frame;
    
    switch (self.imagePosition)
    {
		case NSImageLeft:
            switch (self.controlSize)
            {
                case NSControlSizeSmall:
                    textFrame.size.width -= (NSMaxX(checkboxFrame) + 6);
                    textFrame.origin.x = (NSMaxX(checkboxFrame) + 6);
                    textFrame.origin.y -= 1;
                    break;
                case NSControlSizeMini:
                    textFrame.size.width -= (NSMaxX(checkboxFrame) + 4);
                    textFrame.origin.x = (NSMaxX(checkboxFrame) + 4);
                    break;
                case NSControlSizeRegular:
                default:
                    textFrame.size.width -= (NSMaxX(checkboxFrame) + 5);
                    textFrame.origin.x = (NSMaxX(checkboxFrame) + 5);
                    textFrame.origin.y -= 2;
                    break;
            }
			break;
            
		case NSImageRight:
			switch (self.controlSize)
            {
                case NSControlSizeSmall:
                    textFrame.origin.x += 2;
                    textFrame.size.width = (NSMinX(checkboxFrame) - NSMinX(textFrame) - 5);
                    textFrame.origin.y -= 1;
                    break;
                case NSControlSizeMini:
                    textFrame.origin.x += 2;
                    textFrame.size.width = (NSMinX(checkboxFrame) - NSMinX(textFrame) - 5);
                    break;
                case NSControlSizeRegular:
                default:
                    textFrame.origin.x += 2;
                    textFrame.size.width = (NSMinX(checkboxFrame) - NSMinX(textFrame) - 5);
                    textFrame.origin.y -= 2;
                    break;
            }
			break;
            
        default:
            break;
	}
    
    return textFrame;
}

- (NSRect) titleRectForBounds: (NSRect)frame withImageRect: (NSRect)imageFrame
{
    return [self titleRectForBounds: frame withCheckboxRect: imageFrame];
}

- (void) drawImage: (NSImage *)image withFrame: (NSRect)frame inView: (NSView *)controlView
{
    BGTheme *theme = [[BGThemeManager keyedManager] themeForKey: self.themeKey];
    
    NSRect imageRect = [self imageRectForImage: image
                                     forBounds: frame];
    
    CGFloat opacity = (self.isEnabled) ? 0.6 : 0.2;

    if (image.isTemplate)
    {       
        NSColor *tint = (self.isEnabled) ? theme.textColor : theme.disabledTextColor;
        NSShadow *shadow = theme.textShadow;
        
        NSImage *tintedImage = [image imageFilledWithColor: tint atSize: imageRect.size];
        
        [NSGraphicsContext saveGraphicsState];
            [shadow set];
            [tintedImage drawInRect: imageRect
                           fromRect: NSZeroRect
                          operation: NSCompositingOperationSourceOver
                           fraction: opacity
                     respectFlipped: YES
                              hints: nil];
        [NSGraphicsContext restoreGraphicsState];
    }
    else
    {
        [image drawInRect: imageRect
                 fromRect: NSZeroRect
                operation: NSCompositingOperationSourceOver
                 fraction: opacity
           respectFlipped: YES
                    hints: nil];
    }
}

@end
