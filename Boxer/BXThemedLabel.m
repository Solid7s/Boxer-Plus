/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXThemedLabel.h"

@implementation BXThemedLabel

#pragma mark - Default theme handling

+ (NSString *) defaultThemeKey
{
    return nil;
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

//Fixes a BGHUDLabel/NSTextField bug where toggling enabledness
//won't cause a redraw.
- (void) setEnabled: (BOOL)flag
{
    [super setEnabled: flag];
    //IMPLEMENTATION NOTE: this is the only way I've found to force
    //a proper redraw. setNeedsDisplay: doesn't, nor updateCell: and their ilk.
    self.stringValue = self.stringValue;
}

- (void) setThemeKey: (NSString *)key
{
    if (![key isEqual: self.themeKey])
    {
        _themeKey = [key copy];
        self.stringValue = self.stringValue;
    }
}


- (void) drawRect: (NSRect)dirtyRect {
    
    BGTheme *theme = [[BGThemeManager keyedManager] themeForKey: self.themeKey];

    if (self.isEnabled)
    {
        self.textColor = theme.textColor;
    }
    else
    {
        self.textColor = theme.disabledTextColor;
    }
    
    //add text shadow before we draw the text itself
    NSShadow *textShadow = theme.textShadow;
    if (textShadow)
    {
        NSMutableAttributedString *value;
        if (self.attributedStringValue)
        {
            value = [self.attributedStringValue mutableCopy];
        }
        else
        {
            value = [[NSMutableAttributedString alloc] initWithString: self.stringValue];
        }
    
        [value addAttribute: NSShadowAttributeName
                      value: textShadow
                      range: NSMakeRange(0, [value length])];

        self.attributedStringValue = value;
    }
    
    [super drawRect: dirtyRect];
}

@end

#pragma mark -
#pragma mark Themed versions

@implementation BXHUDLabel
+ (NSString *) defaultThemeKey { return @"BXHUDTheme"; }
@end


@implementation BXBlueprintLabel
+ (NSString *) defaultThemeKey { return @"BXBlueprintTheme"; }
@end

@implementation BXBlueprintHelpTextLabel
+ (NSString *) defaultThemeKey { return @"BXBlueprintHelpTextTheme"; }
@end


@implementation BXAboutLabel
+ (NSString *) defaultThemeKey { return @"BXAboutTheme"; }
@end

@implementation BXAboutDarkLabel
+ (NSString *) defaultThemeKey { return @"BXAboutDarkTheme"; }
@end

@implementation BXAboutLightLabel
+ (NSString *) defaultThemeKey { return @"BXAboutLightTheme"; }
@end
