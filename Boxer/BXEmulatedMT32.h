/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

//BXEmulatedMT32 provides a BXMIDIDevice wrapper for the MUNT MT-32 emulator.
//It takes an optional delegate to which it sends notifications of LCD display messages.
//Unlike the other BXMIDIDevice classes, this currently feeds audio output back into
//DOSBox's own mixer.

#import <Foundation/Foundation.h>
#import "BXMIDIDevice.h"
#import "BXAudioSource.h"

#ifdef __cplusplus
    #import "MT32Emu/mt32emu.h"

NS_ASSUME_NONNULL_BEGIN

@class BXEmulatedMT32;
/// MT32Emu has a C++ callback class for handling emulated synth notifications.
/// We implement a thin C++ wrapper that sends messages back to `BXEmulatedMT32` for handling.
    class BXEmulatedMT32ReportHandler : public MT32Emu::ReportHandler
    {
    public:
        BXEmulatedMT32ReportHandler(BXEmulatedMT32 *delegate) { _delegate = delegate; };
        
    protected:
        void onErrorControlROM();
        void onErrorPCMROM();
        void showLCDMessage(const char *message);
        void printDebug(const char *fmt, va_list list);
    private:
        BXEmulatedMT32 *_delegate;
    };

NS_ASSUME_NONNULL_END

extern "C" {
#endif


NS_ASSUME_NONNULL_BEGIN

#pragma mark -
#pragma mark Constants

extern NSErrorDomain const BXEmulatedMT32ErrorDomain;
/// Keys included in the error dictionary for `BXEmulatedMT32MismatchedROMs` errors.
/// These point to NSNumbers whose integer values represent the types of the respective ROMs.
extern NSErrorUserInfoKey const BXMT32ControlROMTypeKey;
extern NSErrorUserInfoKey const BXMT32PCMROMTypeKey;


typedef NS_ERROR_ENUM(BXEmulatedMT32ErrorDomain, BXEmulatedMT32Errors) {
    BXEmulatedMT32MissingROM,       //!< No ROMs were specified when initializing.
    BXEmulatedMT32CouldNotReadROM,  //!< A specified ROM could not be opened.
    BXEmulatedMT32InvalidROM,       //!< A specified ROM was not a valid MT-32 ROM.
    BXEmulatedMT32MismatchedROMs,   //!< Control and PCM ROMs aren't from matching versions.
};


typedef NS_OPTIONS(NSUInteger, BXMT32ROMType) {
    BXMT32ROMTypeUnknown    = 0,
    
    //Mutually exclusive
    BXMT32ROMIsControl NS_SWIFT_NAME(isControl) = 1 << 0,
    BXMT32ROMIsPCM NS_SWIFT_NAME(isPCM)         = 1 << 1,
    
    //Mutually exclusive
    BXMT32ROMIsMT32 NS_SWIFT_NAME(isMT32)   = 1 << 2,
    BXMT32ROMIsCM32L NS_SWIFT_NAME(isCM32)  = 1 << 3,
    
    BXMT32Control NS_SWIFT_NAME(control)    = BXMT32ROMIsControl | BXMT32ROMIsMT32,
    BXMT32PCM NS_SWIFT_NAME(pcm)            = BXMT32ROMIsPCM | BXMT32ROMIsMT32,
    BXCM32LControl NS_SWIFT_NAME(lControl)  = BXMT32ROMIsControl | BXMT32ROMIsCM32L,
    BXCM32LPCM NS_SWIFT_NAME(lPCM)          = BXMT32ROMIsPCM | BXMT32ROMIsCM32L,
    
    BXMT32ModelMask NS_SWIFT_NAME(modelMask)    = BXMT32ROMIsMT32 | BXMT32ROMIsCM32L,
    BXMT32TypeMask NS_SWIFT_NAME(typeMask)      = BXMT32ROMIsControl | BXMT32ROMIsPCM,
};


#pragma mark -
#pragma mark Interface declaration


@protocol BXEmulatedMT32Delegate;

/// `BXEmulatedMT32` provides a `BXMIDIDevice` wrapper for the MUNT MT-32 emulator.
/// It takes an optional delegate to which it sends notifications of LCD display messages.
/// Unlike the other `BXMIDIDevice` classes, this currently feeds audio output back into
/// DOSBox's own mixer.
@interface BXEmulatedMT32 : NSObject <BXMIDIDevice, BXAudioSource>

@property (copy, nonatomic) NSURL *PCMROMURL NS_SWIFT_NAME(pcmROMURL);
@property (copy, nonatomic) NSURL *controlROMURL;
@property (weak, nonatomic) id <BXEmulatedMT32Delegate> delegate;
@property (assign, nonatomic) unsigned int sampleRate;

- (nullable instancetype) initWithPCMROM: (NSURL *)PCMROMURL
                              controlROM: (NSURL *)controlROMURL
                                delegate: (nullable id <BXEmulatedMT32Delegate>)delegate
                                   error: (NSError **)outError;


#pragma mark -
#pragma mark Helper class methods

/// Returns the exact type of ROM at the specified URL: PCM/Control, MT32/CM32L.
/// Returns `BXMT32ROMTypeUnknown` and populates `outError` if the type of ROM could
/// not be determined.
+ (BXMT32ROMType) typeOfROMAtURL: (NSURL *)URL error: (out NSError **)outError NS_REFINED_FOR_SWIFT;

/// Returns whether the specified pair of ROMs is MT32 or CM32L.
/// Returns `BXMT32ROMTypeUnknown` and populates `outError` if there was an error
/// determining the types of the ROMs or if they are mismatched.
+ (BXMT32ROMType) typeOfROMPairWithControlROMURL: (NSURL *)controlROMURL
                                       PCMROMURL: (NSURL *)PCMROMURL
                                           error: (out NSError **)outError NS_REFINED_FOR_SWIFT;
@end

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
