@import Foundation;
#import "BXWindowsProgramGroup.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"pass a real Congo group fixture");
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSArray *items = [BXWindowsProgramGroup shortcutsInData:data];
        Check(items.count == 2, @"Congo group has two entries");
        Check([items[1][@"title"] isEqual:@"Congo"] && [items[1][@"command"] isEqual:@"d:\\congo.exe"], @"Congo shortcut command");
        Check([items[1][@"directory"] isEqual:@"d:\\"], @"Congo working directory extension");
        Check([items[0][@"directory"] isEqual:@"c:\\congo\\"], @"extensions map to their original program slots");
        NSDictionary *parts = [BXWindowsProgramGroup partsOfCommand:@"  \"C:\\MY GAME\\RUN.EXE\" /level:2 \"save one.dat\"  "];
        Check([parts[@"program"] isEqual:@"C:\\MY GAME\\RUN.EXE"] && [parts[@"arguments"] isEqual:@"/level:2 \"save one.dat\""], @"quoted executable and arguments remain intact");
        Check([[BXWindowsProgramGroup partsOfCommand:@"WRITE.EXE C:\\CONGO\\README.WRI"][@"arguments"] isEqual:@"C:\\CONGO\\README.WRI"], @"bare executable with document argument");
        for (NSString *bad in @[@"", @"\"missing", @"\"run.exe\"bad", @"run.exe\rnext.exe", @"run.exe | next.exe", @"run.exe > save.dat", @"run.exe & next.exe"])
            Check([BXWindowsProgramGroup partsOfCommand:bad] == nil, @"unsupported command rejected");
        // Every truncated prefix and invalid offset must terminate safely.
        for (NSUInteger length = 0; length < data.length; length++)
            (void)[BXWindowsProgramGroup shortcutsInData:[data subdataWithRange:NSMakeRange(0, length)]];
        NSMutableData *broken = [data mutableCopy];
        uint8_t *bytes = broken.mutableBytes;
        bytes[34] = bytes[35] = 0xff;
        Check([BXWindowsProgramGroup shortcutsInData:broken].count == 0, @"out-of-bounds item rejected");
        broken = [data mutableCopy]; bytes = broken.mutableBytes;
        NSUInteger extension = bytes[6] | (bytes[7] << 8);
        bytes[extension + 4] = bytes[extension + 5] = 0;
        Check([BXWindowsProgramGroup shortcutsInData:broken].count == 0, @"zero-length extension cannot loop");
        broken = [data mutableCopy]; bytes = broken.mutableBytes;
        bytes[34] = bytes[35] = 0; // Empty first slot must not renumber the second.
        NSArray *sparse = [BXWindowsProgramGroup shortcutsInData:broken];
        Check(sparse.count == 1 && [sparse[0][@"directory"] isEqual:@"d:\\"], @"sparse group slot indices survive parsing");
        puts("PASS: real Windows group metadata, working folders, quoted arguments, sparse slots, malformed input");
    }
}
