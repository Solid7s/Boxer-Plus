/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import <Foundation/Foundation.h>


//MIDI-related constants for General MIDI and MT-32 messages.
NS_ENUM(uint8_t) {
    BXSysexStart = 0xF0,
    BXSysexEnd = 0xF7,

    /// MIDI messages use 7 bits, but must be sent via byte arrays.
    /// This mask clears the 8th and higher bits of the byte.
    BXMIDIBitmask = 0x7F
};


#pragma mark -
#pragma mark General MIDI sysex message codes

NS_ENUM(uint8_t) {
    BXGeneralMIDISysexNonRealtime = 0x7E,
    BXGeneralMIDISysexRealtime = 0x7F,

    BXGeneralMIDISysexAllChannels = 0x7F,
    BXGeneralMIDISysexDeviceControl = 0x04,
    BXGeneralMIDISysexMasterVolume = 0x01,

#define BXGeneralMIDIMaxMasterVolume 0x3FFF //16383


    BXSysexManufacturerIDRoland = 0x41,
    BXSysexManufacturerIDNonRealtime = 0x7E,
    BXSysexManufacturerIDRealtime = 0x7F,
};

#pragma mark -
#pragma mark Roland sysex message format

//! Start byte, manufacturer ID, device ID, model ID, message Type
#define BXRolandSysexHeaderLength 5l
//! High byte, middle byte, low byte
#define BXRolandSysexAddressLength 3l
//! High byte, middle byte, low byte
#define BXRolandSysexRequestSizeLength 3l
//! Checksum, end byte
#define BXRolandSysexTailLength 2l


#define BXRolandSysexChecksumModulus 128

NS_ENUM(uint8_t) {
    BXRolandSysexModelIDMT32 = 0x16,
    BXRolandSysexModelIDD50 = 0x14,

    BXRolandSysexDeviceIDDefault = 0x10,

    BXRolandSysexRequest = 0x11,
    BXRolandSysexSend = 0x12
};

NS_ENUM(NSInteger) {
    BXRolandSysexSendMinLength = (BXRolandSysexHeaderLength + BXRolandSysexAddressLength + BXRolandSysexTailLength),

    BXRolandSysexRequestLength = (BXRolandSysexSendMinLength + BXRolandSysexRequestSizeLength)
};

#pragma mark -
#pragma mark MT-32-specific sysex message parameters

#define BXMT32MaxMasterVolume 100
#define BXMT32LCDMessageLength 20l

NS_ENUM(uint8_t) {
    BXMT32SysexAddressPatchMemory = 0x05,
    BXMT32SysexAddressTimbreMemory = 0x08,
    BXMT32SysexAddressSystemArea = 0x10,
    BXMT32SysexAddressReset = 0x7F,
    BXMT32SysexAddressDisplay = 0x20,


    BXChannelModeChangePrefix = 0xB0,
    BXAllNotesOffMessage = 0x7B
};
