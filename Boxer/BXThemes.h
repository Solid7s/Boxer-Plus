/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


//BXThemes defines custom UI themes for BGHUDAppKit to customise the appearance of UI elements.
//These are used in Boxer's inspector panel and elsewhere.

#import <Cocoa/Cocoa.h>
#import "BGThemeManager.h"

/// Extends BGTheme with more specific overrides.
@interface BGTheme (BXThemeExtensions)

/// Registers the theme class with the theme manager,
/// keyed under the specific name.
/// If name is nil, the classname will be used.
+ (void) registerWithName: (NSString *)name;

- (NSColor *) textColor;
- (NSColor *) disabledTextColor;
- (NSShadow *) textShadow;

- (NSGradient *) imageFill;
- (NSShadow *) imageInnerShadow;
- (NSShadow *) imageDropShadow;

- (NSGradient *) selectedImageFill;
- (NSShadow *) selectedImageInnerShadow;
- (NSShadow *) selectedImageDropShadow;

- (NSGradient *) disabledImageFill;
- (NSShadow *) disabledImageInnerShadow;
- (NSShadow *) disabledImageDropShadow;

- (NSGradient *) highlightedImageFill;
- (NSShadow *) highlightedImageInnerShadow;
- (NSShadow *) highlightedImageDropShadow;

- (NSGradient *) pushedImageFill;
- (NSShadow *) pushedImageInnerShadow;
- (NSShadow *) pushedImageDropShadow;


@end


/// Base class used by all Boxer themes. Currently empty.
@interface BXBaseTheme : BGTheme
@end

/// Adds a soft shadow around text.
@interface BXBlueprintTheme : BXBaseTheme
@end

/// Same as above, but paler text.
@interface BXBlueprintHelpTextTheme : BXBlueprintTheme
@end

/// White text, blue highlights and subtle text shadows
/// for HUD and bezel panels.
@interface BXHUDTheme : BXBaseTheme
@end

/// Lightly indented text for program panels and inspector.
@interface BXIndentedTheme : BXBaseTheme
@end


/// Style used for list items in inspector.
@interface BXInspectorListTheme : BXBaseTheme
@end

/// Style used for selected list items in inspector.
@interface BXInspectorListSelectionTheme : BXInspectorListTheme
@end

@interface BXInspectorListControlTheme : BXBaseTheme
@end

@interface BXInspectorListControlSelectionTheme : BXInspectorListControlTheme
@end


@interface BXLauncherTheme : BXBaseTheme
@end

@interface BXLauncherHelpTextTheme : BXLauncherTheme
@end

@interface BXLauncherHeadingTheme : BXLauncherTheme
@end


/// Lightly indented medium text for About panel.
@interface BXAboutTheme : BXBaseTheme
@end

/// Lightly indented dark text for About panel.
@interface BXAboutDarkTheme : BXAboutTheme
@end

/// Lightly indented bright text for About panel.
@interface BXAboutLightTheme : BXAboutTheme
@end


@protocol BXThemable <NSObject>

@required
@property (copy, nonatomic) NSString *themeKey;


/// Base implementations for these are provided by BXThemableExtensions,
/// so they're automatically available on any object that implement this protocol.
@optional
+ (NSString *) defaultThemeKey;
@property (readonly, nonatomic) BGTheme *themeForKey;

@end


@interface NSObject (BXThemableExtensions)

/// The initial theme key for all instances of this object.
+ (NSString *) defaultThemeKey;

@property (readonly, nonatomic) BGTheme *themeForKey;

@end


/// NSControl extension to allow passthroughs to themed cell properties
@interface NSControl (BXThemedControls) <BXThemable>
@end
