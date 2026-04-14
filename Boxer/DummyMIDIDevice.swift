//
//  DummyMIDIDevice.swift
//  Boxer
//
//  Created by C.W. Betts on 10/9/23.
//  Copyright © 2023 Alun Bestor and contributors. All rights reserved.
//

import Foundation

/// `DummyMIDIDevice` receives but ignores all MIDI events.
/// It is used as a placeholder when MIDI is disabled.
final class DummyMIDIDevice : NSObject, BXMIDIDevice {
    var volume: Float {
        get {
            return 0
        }
        set {
            // do nothing
        }
    }
    
    var supportsMT32Music: Bool {
        return false
    }
    
    var supportsGeneralMIDIMusic: Bool {
        return false
    }
    
    var isProcessing: Bool {
        return false
    }
    
    var dateWhenReady: Date {
        return Date.distantPast
    }
    
    func handleMessage(_ message: Data) {}
    
    func handleSysex(_ message: Data) {}
    
    func pause() {}
    
    func resume() {}
    
    func close() {}
}
