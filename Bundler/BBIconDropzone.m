//
//  BBIconDropzone.m
//  Boxer Bundler
//
//  Created by Alun Bestor on 15/08/2012.
//  Copyright (c) 2012 Alun Bestor. All rights reserved.
//

#import "BBIconDropzone.h"

@implementation BBIconDropzone

- (id) initWithFrame: (NSRect)frame
{
    self = [super initWithFrame: frame];
    if (self)
    {
        NSArray *registeredTypes = self.registeredDraggedTypes;
        [self registerForDraggedTypes: [registeredTypes arrayByAddingObject: NSPasteboardTypeFileURL]];
    }
    
    return self;
}

- (BOOL) performDragOperation: (id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    
    if ([pboard.types containsObject: NSPasteboardTypeFileURL])
    {
        NSArray<NSURL *> *filePaths = [pboard readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
        NSURL *lastFilePath = filePaths.lastObject;
        
        if (lastFilePath)
        {
            BOOL dropSucceeded = [super performDragOperation: sender];
            
            if (dropSucceeded)
            {
                self.lastDroppedImageURL = lastFilePath;
                return YES;
            }
        }
    }
    return NO;
}

@end
