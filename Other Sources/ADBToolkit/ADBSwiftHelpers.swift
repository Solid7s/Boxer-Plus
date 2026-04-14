//
//  ADBSwiftHelpers.swift
//  Boxer
//
//  Created by C.W. Betts on 12/9/19.
//  Copyright © 2019 Alun Bestor and contributors. All rights reserved.
//

import Foundation

extension ADBBinCueImage {
    /// Returns `true` if the specified path contains a parseable cue file, `false` otherwise.
    /// Throws an error if there is a problem accessing the file.
    static func isCue(at cueURL: URL) throws -> Bool {
        var outError: NSError? = nil
        let isACue = __isCue(at: cueURL, error: &outError)
        if !isACue, let outError {
            throw outError
        }
        return isACue
    }
}

extension BXFileTypes {
    /// Returns the executable type of the file at the specified URL.
    /// If the executable type cannot be determined, this method will throw.
    static func typeOfExecutable(at url: URL) throws -> BXExecutableType {
        let handle: ADBFileHandle
        do {
            handle = try ADBFileHandle(url: url, options: .openForReading)
        } catch {
            throw BXExecutableTypesErrors(.couldNotReadExecutable, userInfo: [NSUnderlyingErrorKey: error,
                                                                                     NSURLErrorKey: url])
        }
        defer {
            handle.close()
        }
        return try typeOfExecutable(inStream: handle)
    }

    /// Returns the executable type of the file in the specified stream.
    /// If the executable type cannot be determined, this method will throw.
    static func typeOfExecutable(inStream handle: ADBReadable & ADBSeekable) throws -> BXExecutableType {
        var err: NSError?
        let toRet = __typeOfExecutable(inStream: handle, error: &err)
        
        if toRet == .unknown, let err {
            throw err
        }
        return toRet
    }

    /// Returns the executable type of the file at the specified path.
    /// If the executable type cannot be determined, this method will throw.
    static func typeOfExecutable(atPath path: String, in filesystem: ADBFilesystemPathAccess) throws -> BXExecutableType {
        let handle: ADBReadable & ADBSeekable
        do {
            //Should work, but just in case.
            guard let prehandle1 = try filesystem.fileHandle(atPath: path, options: .openForReading) as? ADBReadable & ADBSeekable else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            handle = prehandle1
        } catch {
            throw BXExecutableTypesErrors(.couldNotReadExecutable, userInfo: [NSUnderlyingErrorKey: error])
        }
        defer {
            if let hand2 = handle as? ADBFileHandleAccess {
                hand2.close()
            }
        }
        return try typeOfExecutable(inStream: handle)
    }
}
