/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXThemes.h"

/// BXThemedButtonCell is a reimplementation of BGHUDButtonCell to provide more
/// control over checkbox and radio button rendering.
@interface BXThemedButtonCell : NSButtonCell <BXThemable>

@property (copy, nonatomic) NSString *themeKey;

/// Given an entire cell frame, returns the rect
/// in which to draw the checkbox/radio button.
- (NSRect) imageRectForImage: (NSImage *)image forBounds: (NSRect)frame;

/// Returns the rect into which to render a checkbox
/// or radio button label.
/// frame is expected to be the cell frame, while checkboxRect
/// is expected to be the area that will be occupied by the
/// checkbox or radio button.
- (NSRect) titleRectForBounds: (NSRect)frame
             withCheckboxRect: (NSRect)checkboxFrame;

/// Same as above, but for the specified image rectangle.
- (NSRect) titleRectForBounds: (NSRect)frame
                withImageRect: (NSRect)imageFrame;

@end
