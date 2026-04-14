/* 
 This code was found online in a comment at:
 http://notes.stripsapp.com/nsdata-to-nsstring-as-hex-bytes/
 Its original authorship is unknown but to the best of my knowledge,
 the code was provided with no explicit copyright or license.
 */

#import "NSData+HexStrings.h"

@implementation NSData (HexStrings)

- (NSString *) stringWithHexBytes
{
	static const char hexdigits[] = "0123456789ABCDEF";
	NSUInteger numBytes = [self length];
	const unsigned char* bytes = [self bytes];
	
	NSMutableData *strDat = [NSMutableData dataWithLength:numBytes * 2 + 1];
	char *strbuf = (char *)strDat.mutableBytes;
	char *hex = strbuf;
	NSString *hexBytes = nil;
	
	NSUInteger i;
	for (i = 0; i<numBytes; ++i) {
		const unsigned char c = *bytes++;
		*hex++ = hexdigits[(c >> 4) & 0xF];
		*hex++ = hexdigits[(c ) & 0xF];
	}
	*hex = 0;
	hexBytes = [[NSString alloc] initWithData:strDat encoding:NSASCIIStringEncoding];
	return hexBytes;
}

@end
