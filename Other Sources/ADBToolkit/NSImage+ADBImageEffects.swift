//
//  NSImage+ADBImageEffects_Swift.swift
//  Boxer
//
//  Created by C.W. Betts on 2/3/24.
//  Copyright © 2024 Alun Bestor and contributors. All rights reserved.
//

import Cocoa

extension NSImage {
	
	/// Returns the relative anchor point (from *{0.0, 0.0}* to *{1.0, 1.0}*)
	/// that's equivalent to the specified image alignment constant.
	@objc(anchorForImageAlignment:)
	open class func anchor(for alignment: NSImageAlignment) -> NSPoint {
		switch alignment {
		case .alignCenter:
				return NSMakePoint(0.5, 0.5)
				
		case .alignBottom:
				return NSMakePoint(0.5, 0.0)
				
		case .alignTop:
				return NSMakePoint(0.5, 1.0)
				
		case .alignLeft:
				return NSMakePoint(0.0, 0.5)
				
		case .alignRight:
				return NSMakePoint(1.0, 0.5)
				
		case .alignBottomLeft:
				return NSMakePoint(0.0, 0.0)
				
		case .alignBottomRight:
				return NSMakePoint(1.0, 0.0)
				
		case .alignTopLeft:
				return NSMakePoint(0.0, 1.0)
				
		case .alignTopRight:
				return NSMakePoint(1.0, 1.0)
				
			default:
				return NSZeroPoint
		}
	}
	
	/// Returns a rect suitable for drawing this image into,
	/// given the specified alignment and scaling mode. Intended
	/// for `NSCell`/`NSControl` subclasses.
	@objc(imageRectAlignedInRect:alignment:scaling:)
	open func imageRectAligned(in outerRect: NSRect, alignment: NSImageAlignment, scaling: NSImageScaling) -> NSRect {
		var drawRect = NSRect.zero
		drawRect.size = self.size
		let anchor = type(of: self).anchor(for: alignment)
		
		switch (scaling) {
		case .scaleProportionallyDown:
			drawRect = constrainToRect(drawRect, outerRect, anchor)

		case .scaleProportionallyUpOrDown:
			drawRect = fitInRect(drawRect, outerRect, anchor)

		case .scaleAxesIndependently:
			drawRect = outerRect

		case .scaleNone:
			fallthrough
		default:
			drawRect = alignInRectWithAnchor(drawRect, outerRect, anchor)
		}
		return drawRect
	}

	/// Returns a new version of the image filled with the specified color at the
	/// specified size, using the current image's alpha channel. The resulting image
	/// will be a bitmap.
	///
	/// Pass `.zero` as the size to use the size of the original image.
	/// Intended for use with black-and-transparent template images,
	/// although it will work with any image.
	@objc(imageFilledWithColor:atSize:)
	func imageFilled(with color: NSColor, at size: NSSize) -> NSImage {
		let targetSize: NSSize
		if size == .zero {
			targetSize = self.size
		} else {
			targetSize = size
		}
		
		let imageRect = NSRect(origin: .zero, size: targetSize)
		
		let sourceImage = self
		#if false // This hasn't been tested yet...
		let maskedImage = NSImage(size: targetSize, flipped: false) { dirty in
			color.set()
			dirty.fill(using: .sourceOver)
			sourceImage.draw(in: dirty,
							 from: .zero,
							 operation: .destinationIn,
							 fraction: 1)
			
			return true
		}
		
		return maskedImage
		#else
		let maskedImage = NSImage(size: targetSize)
		
		do {
			maskedImage.lockFocus()
			defer {
				maskedImage.unlockFocus()
			}
			color.set()
			
			imageRect.fill(using: .sourceOver)
			sourceImage.draw(in: imageRect,
							 from: .zero,
							 operation: .destinationIn,
							 fraction: 1)
		}
		
		return maskedImage
		#endif
	}
	
	/// Returns a new version of the image masked by the specified image, at the
	/// specified size. The resulting image will be a bitmap.
	@objc(imageMaskedByImage:atSize:)
	open func imageMasked(by image: NSImage, at size: NSSize) -> NSImage {
		var targetSize: NSSize
		if size == .zero {
			targetSize = self.size
		} else {
			targetSize = size
		}
		
		let maskedImage = self.copy() as! NSImage
		maskedImage.size = targetSize
		
		let imageRect = NSRect(origin: .zero, size: targetSize)
		
		// TODO: Use NSImage(size:flipped:drawingHandler:) instead.
		do {
			maskedImage.lockFocus()
			defer {
				maskedImage.unlockFocus()
			}
			image.draw(in: imageRect, from: .zero, operation: .destinationIn, fraction: 1)
		}
		return maskedImage
	}
	
	/// Draw a template image filled with the specified gradient and rendered
	/// with the specified inner and drop shadows.
	@objc(drawInRect:withGradient:dropShadow:innerShadow:respectFlipped:)
	open func draw(in drawRect: NSRect, with fillGradient: NSGradient?, dropShadow: NSShadow?, innerShadow: NSShadow?, respectFlipped respectContextIsFlipped: Bool) {
		precondition(self.isTemplate, "drawInRect:withGradient:dropShadow:innerShadow: can only be used with template images.")
		
		//Check if we're rendering into a backing intended for retina displays.
		var pointSize = NSMakeSize(1, 1)
		pointSize = NSView.focusView!.convertToBacking(pointSize)

		let contextSize = NSView.focusView!.bounds.size
		
		let context = NSGraphicsContext.current!
		let cgContext = context.cgContext

		let drawFlipped = respectContextIsFlipped && context.isFlipped

		//Now calculate the total area of the context that will be affected by our drawing,
		//including our drop shadow. Our mask images will be created at this size to ensure
		//that the whole canvas is properly masked.
		
		var totalDirtyRect = drawRect
		if let dropShadow {
			totalDirtyRect = totalDirtyRect.union(dropShadow.shadowedRect(drawRect, flipped: false))
		}
		
		//TWEAK: also expand the dirty rect to encompass our *inner* shadow as well.
		//Because the resulting mask is used to draw the inner shadow, it needs to have enough
		//padding around all relevant edges that the inner shadow appears 'solid' and doesn't
		//get cut off.
		if let innerShadow {
			totalDirtyRect = totalDirtyRect.union(innerShadow.rect(toCast: drawRect, flipped: false))
		}
		
		let maskRect = CGRectIntegral(totalDirtyRect)
		
		//First get a representation of the image suitable for drawing into the destination.
		let imageRect = NSRectToCGRect(drawRect)
		var tmpRect = drawRect
		let baseImage = cgImage(forProposedRect: &tmpRect, context: context, hints: nil)

		
		//Next, render it into a new bitmap context sized to cover the whole dirty area.
		//We then grab regular and inverted CGImages from that context to use as masks.
		
		//NOTE: Because CGBitmapContexts are not retina-aware and use device pixels,
		//we have to compensate accordingly when we're rendering for a retina backing.
		let maskPixelSize = CGSizeMake(maskRect.size.width * pointSize.width,
									   maskRect.size.height * pointSize.height)

		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let maskContext = CGContext(data: nil, width: Int(maskPixelSize.width), height: Int(maskPixelSize.height), bitsPerComponent: 8, bytesPerRow: Int(maskPixelSize.width) * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		
		let relativeMaskRect = CGRect(x: (imageRect.origin.x - maskRect.origin.x) * pointSize.width,
									  y: (imageRect.origin.y - maskRect.origin.y) * pointSize.height,
									  width: imageRect.size.width * pointSize.width,
									  height: imageRect.size.height * pointSize.height)
		
		maskContext.draw(baseImage!, in: relativeMaskRect)
		//Grab our first mask image, which is just the original image with padding.
		let imageMask = maskContext.makeImage()

		//Now invert the colors in the context and grab another image, which will be our inverse mask.
		maskContext.setBlendMode(.xor)
		maskContext.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
		maskContext.fill(CGRectMake(0, 0, maskPixelSize.width, maskPixelSize.height))
		let invertedImageMask = maskContext.makeImage()

		
		//To render the drop shadow, draw the original mask but clipped by the inverted mask:
		//so that the shadow is only drawn around the edges, and not within the inside of the image.
		//(IMPLEMENTATION NOTE: we draw the drop shadow in a separate pass instead of just setting the
		//drop shadow when we draw the fill gradient, because otherwise a semi-transparent gradient would
		//render a drop shadow underneath the translucent parts: making the result appear muddy.)
		if let dropShadow {
			cgContext.saveGState()
			defer {
				cgContext.restoreGState()
			}
			if (drawFlipped) {
				cgContext.translateBy(x: 0.0, y: contextSize.height)
				cgContext.scaleBy(x: 1.0, y: -1.0)
			}
			
			//IMPLEMENTATION NOTE: we want to draw the drop shadow but not the image that's 'causing' the shadow.
			//So, we draw that image wayyy off the top of the canvas, and offset the shadow far enough that
			//it lands in the expected position.
			
			let imageOffset = CGRectOffset(maskRect, 0, maskRect.size.height)
			let shadowOffset = CGSizeMake(dropShadow.shadowOffset.width,
										  dropShadow.shadowOffset.height - maskRect.size.height)
			
			let shadowColor = dropShadow.shadowColor?.cgColor
			
			cgContext.clip(to: maskRect, mask: invertedImageMask!)
			cgContext.setShadow(offset: shadowOffset, blur: dropShadow.shadowBlurRadius, color: shadowColor)
			cgContext.draw(imageMask!, in: imageOffset)
		}
		
		//Finally, render the inner region with the gradient and inner shadow (if any)
		//by clipping the drawing area to the regular mask.
		if (fillGradient != nil || innerShadow != nil) {
			cgContext.saveGState()
			defer {
				cgContext.restoreGState()
			}
			
			if drawFlipped {
				cgContext.translateBy(x: 0.0, y: contextSize.height)
				cgContext.scaleBy(x: 1.0, y: -1.0)
			}
			cgContext.clip(to: maskRect, mask: imageMask!)
			
			if let fillGradient {
				fillGradient.draw(in: drawRect, angle: 270.0)
			}
			
			if let innerShadow {
				//See dropShadow note above about offsets.
				let imageOffset = CGRectOffset(maskRect, 0, maskRect.size.height)
				let shadowOffset = CGSizeMake(innerShadow.shadowOffset.width,
											  innerShadow.shadowOffset.height - maskRect.size.height)
				
				let shadowColor = innerShadow.shadowColor?.cgColor
				
				cgContext.setShadow(offset: shadowOffset, blur: innerShadow.shadowBlurRadius, color: shadowColor)
				cgContext.draw(invertedImageMask!, in: imageOffset)
			}
		}
	}
}
