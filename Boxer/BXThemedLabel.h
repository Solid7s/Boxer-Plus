/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXThemes.h"


@interface BXThemedLabel : NSTextField <BXThemable>
@property (copy, nonatomic) NSString *themeKey;
@end


@interface BXHUDLabel : BXThemedLabel
@end


@interface BXBlueprintLabel : BXThemedLabel
@end

@interface BXBlueprintHelpTextLabel : BXThemedLabel
@end


@interface BXAboutLabel : BXThemedLabel
@end

@interface BXAboutDarkLabel : BXThemedLabel
@end

@interface BXAboutLightLabel : BXThemedLabel
@end
