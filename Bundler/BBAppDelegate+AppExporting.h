//
//  BBAppDelegate+AppExporting.h
//  Boxer Bundler
//
//  Created by Alun Bestor on 25/08/2012.
//  Copyright (c) 2012 Alun Bestor. All rights reserved.
//

#import "BBAppDelegate.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Error constants

extern NSErrorDomain const BBAppExportErrorDomain;

typedef NS_ERROR_ENUM(BBAppExportErrorDomain, BBAppExportErrorCode) {
    /// The app could not be code-signed successfully.
    BBAppExportCodeSignFailed,
};

/// The NSError userInfo key listing the code signing identity used for a failed code sign.
extern NSErrorUserInfoKey const BBAppExportCodeSigningIdentityKey;


#pragma mark - BBAppDelegate interface

@interface BBAppDelegate (AppExporting)

/// Begin asynchronously creating a new app at the specified destination URL.
/// @c completionHandler is called upon completion, with the resulting URL and @c nil (if successful)
/// or @c nil and an error representing the reason for failure (if unsuccessful).
- (void) createAppAtDestinationURL: (NSURL *)destinationURL
                        completion: (void(^)(NSURL *_Nullable appURL, NSError *_Nullable error))completionHandler;

/// Synchronously create a new app at the specified destination URL, using our current parameters.
/// Returns the URL of the generated app, or nil and populates outError upon failure.
/// This method can safely overwrite an existing app at destinationURL; if the app creation fails,
/// any existing app will be left untouched.
- (nullable NSURL *) createAppAtDestinationURL: (NSURL *)destinationURL
                                         error: (NSError **)outError;

@end

NS_ASSUME_NONNULL_END
