#import "BXWindowsProgramGroup.h"

static NSUInteger Word(const uint8_t *bytes, NSUInteger offset) {
    return bytes[offset] | ((NSUInteger)bytes[offset + 1] << 8);
}

static NSString *StringAt(NSData *data, NSUInteger offset, NSUInteger end) {
    if (offset >= end || end > data.length) return nil;
    const uint8_t *bytes = data.bytes;
    const uint8_t *nul = memchr(bytes + offset, 0, end - offset);
    if (!nul) return nil;
    return [[NSString alloc] initWithBytes:bytes + offset length:nul - (bytes + offset)
        encoding:NSWindowsCP1252StringEncoding];
}

@implementation BXWindowsProgramGroup
+ (NSArray<NSDictionary *> *)shortcutsInData:(NSData *)data {
    if (data.length < 34 || data.length > 1024 * 1024) return @[];
    const uint8_t *bytes = data.bytes;
    if (memcmp(bytes, "PMCC", 4) && memcmp(bytes, "PMXX", 4)) return @[];
    NSUInteger baseEnd = Word(bytes, 6), count = Word(bytes, 32);
    NSUInteger tableEnd = 34 + count * 2;
    if (baseEnd < tableEnd || baseEnd > data.length) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger offset = Word(bytes, 34 + index * 2);
        if (!offset) continue; // Unused Program Manager slot.
        if (offset < tableEnd || offset > baseEnd || baseEnd - offset < 24) return @[];
        NSUInteger titleOffset = Word(bytes, offset + 18), commandOffset = Word(bytes, offset + 20);
        if (titleOffset < tableEnd || commandOffset < tableEnd) return @[];
        NSString *title = StringAt(data, titleOffset, baseEnd);
        NSString *command = StringAt(data, commandOffset, baseEnd);
        if (!title || !command) return @[];
        if (title.length && command.length)
            [items addObject:[@{ @"title": title, @"command": command, @"directory": @"", @"index": @(index) } mutableCopy]];
    }
    // 3.1 extension records attach a working directory to the original slot number,
    // not the packed index of the nonempty items returned above.
    NSUInteger cursor = baseEnd;
    while (cursor < data.length) {
        if (data.length - cursor < 6) return @[];
        NSUInteger type = Word(bytes, cursor), index = Word(bytes, cursor + 2), size = Word(bytes, cursor + 4);
        if (type == 0xffff) break;
        if (size < 6 || size > data.length - cursor) return @[];
        if (type == 0x8000 && (size < 10 || memcmp(bytes + cursor + 6, "PMCC", 4))) return @[];
        if (type == 0x8101) {
            NSString *directory = StringAt(data, cursor + 6, cursor + size);
            if (!directory) return @[];
            for (NSMutableDictionary *item in items)
                if ([item[@"index"] unsignedIntegerValue] == index) item[@"directory"] = directory;
        }
        cursor += size;
    }
    return items;
}

+ (NSDictionary *)partsOfCommand:(NSString *)command {
    NSString *text = [command stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    // These launch lines will pass through DOSBox's shell. Do not turn a shortcut
    // into a shell pipeline, redirection, or additional command.
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"\r\n\0<>|&"];
    if (!text.length || [text rangeOfCharacterFromSet:unsafe].location != NSNotFound) return nil;
    NSUInteger end;
    NSString *program;
    if ([text hasPrefix:@"\""]) {
        NSRange close = [text rangeOfString:@"\"" options:0 range:NSMakeRange(1, text.length - 1)];
        if (close.location == NSNotFound) return nil;
        program = [text substringWithRange:NSMakeRange(1, close.location - 1)];
        end = close.location + 1;
        if (end < text.length && ![NSCharacterSet.whitespaceCharacterSet characterIsMember:[text characterAtIndex:end]]) return nil;
    } else {
        NSRange space = [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet];
        end = space.location == NSNotFound ? text.length : space.location;
        program = [text substringToIndex:end];
    }
    if (!program.length) return nil;
    NSString *arguments = [[text substringFromIndex:end] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return @{ @"program": program, @"arguments": arguments };
}
@end
