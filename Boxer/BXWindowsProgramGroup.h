// Windows 3.x Program Manager group metadata. See WINDOWS-PROGRAM-SELECTOR.md.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface BXWindowsProgramGroup : NSObject
/// Read PMCC/PMXX groups. Invalid offsets, unterminated strings or extensions reject the group.
/// Each result has title, command, directory and index keys. Icon data is not decoded.
+ (NSArray<NSDictionary *> *)shortcutsInData:(NSData *)data;
/// Split the program name from its arguments, preserving quoted argument text.
+ (nullable NSDictionary *)partsOfCommand:(NSString *)command;
@end
NS_ASSUME_NONNULL_END
