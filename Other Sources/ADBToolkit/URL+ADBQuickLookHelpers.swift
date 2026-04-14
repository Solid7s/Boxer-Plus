//
//  URL+ADBQuickLookHelpers.swift
//  Boxer
//
//  Created by C.W. Betts on 11/9/20.
//  Copyright © 2020 Alun Bestor and contributors. All rights reserved.
//

import Foundation
import QuickLook
import AppKit.NSImage

extension URL {
    
    /// Returns a QuickLook thumbnail for the file at this URL, or `nil` if no thumbnail
    /// could be generated.
    /// - parameter pixelSize: Specifies the maximum pixel dimensions for the preview,
    /// without taking into account any UI scaling factors. The returned image is
    /// guaranteed to be *at most* this size; a smaller image may be returned.
    /// - parameter useIconStyle: If true, the thumbnail will be generated with the
    /// shadow and page-curl effects as seen in Finder.
    ///
    /// USAGE NOTE: this method is synchronous and can take a while to complete, so
    /// should be performed on a background thread.
    func quickLookThumbnail(maxSize pixelSize: NSSize, useIconStyle: Bool) -> NSImage? {
        let options: [String: Any] = [kQLThumbnailOptionIconModeKey! as String: useIconStyle]
        guard let cgThumbnail = QLThumbnailImageCreate(kCFAllocatorDefault, self as NSURL, pixelSize, options as NSDictionary)?.takeRetainedValue() else {
            return nil
        }
        
        return NSImage(cgImage: cgThumbnail, size: .zero)
    }
}

extension NSURL {
	/// Returns a QuickLook thumbnail for the file at this URL, or `nil` if no thumbnail could be generated.
	/// pixelSize specifies the maximum pixel dimensions for the preview, without taking into account
	/// any UI scaling factors. The returned image is guaranteed to be *at most* this size;
	/// a smaller image may be returned.
	///
	/// If `useIconStyle` is true, the thumbnail will be generated with the shadow and page-curl effects
	/// as seen in Finder.
	///
	/// USAGE NOTE: this method is synchronous and can take a while to complete, so should be performed on a background thread.
	@objc(quickLookThumbnailWithMaxSize:iconStyle:)
	func quickLookThumbnail(maxSize pixelSize: NSSize, useIconStyle: Bool) -> NSImage? {
		guard let image = (self as URL).quickLookThumbnail(maxSize: pixelSize, useIconStyle: useIconStyle) else {
			return nil
		}
		return image
	}
}
