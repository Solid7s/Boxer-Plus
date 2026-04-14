/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// \c BXEmulatorConfiguration is a Property List-style parser for configuration files in DOSBox format.
/// It can read and write conf files, though it is not currently able to preserve layout and comments.
@interface BXEmulatorConfiguration : NSObject

#pragma mark -
#pragma mark Properties

/// Whether the configuration has any settings or startup commands in it.
@property (readonly, nonatomic, getter=isEmpty) BOOL empty;

/// Returns a dictionary of all settings organised by section (not including startup commands.)
@property (copy, readonly, nonatomic) NSDictionary<NSString*, NSDictionary<NSString*, NSString*>*> *settings;

/// Returns an array of all startup commands.
@property (copy, readonly, nonatomic, nullable) NSArray<NSString*> *startupCommands;

/// A string to prepend as a header comment at the start of the configuration file.
/// Used by description and writeToFile:error:
@property (copy, nonatomic, nullable) NSString *preamble;

/// A string to prepend as a section comment to the start of the autoexec block.
/// Used by description and writeToFile:error:
@property (copy, nonatomic, nullable) NSString *startupCommandsPreamble;


#pragma mark -
#pragma mark Loading and saving configurations

/// Returns an instance containing the settings in the file at the specified location.
/// Will return \c nil and populate \c outError on failure to read the file.
+ (nullable instancetype) configurationWithContentsOfURL: (NSURL *)URL error: (out NSError **)outError;
- (nullable instancetype) initWithContentsOfURL: (NSURL *)URL error: (out NSError **)outError;
+ (nullable instancetype) configurationWithContentsOfFile: (NSString *)filePath error: (out NSError **)outError;

/// Returns an instance containing the settings parsed from the specified DOSBox-formatted
/// configuration string.
+ (instancetype) configurationWithString: (NSString *)configuration;
- (instancetype) initWithString: (NSString *)configuration;

/// Returns an instance using the specified heirarchical dictionary of sections and settings.
- (instancetype) initWithSettings: (NSDictionary<NSString*,id> *)initialSettings;

/// Returns an autoreleased empty configuration.
+ (instancetype) configuration;

/// Returns an empty configuration.
- (instancetype) init NS_DESIGNATED_INITIALIZER;

/// Writes the configuration in DOSBox format atomically to the specified location.
/// Returns \c YES if write was successful, or \c NO and sets error if the write failed.
/// NOTE: this will overwrite any file that exists at that location. It will not currently
/// preserve the layout or comments of the file it is replacing, nor the file from which
/// the configuration was originally loaded (if any).
- (BOOL) writeToURL: (NSURL *)URL error: (out NSError **)outError;
- (BOOL) writeToFile: (NSString *)filePath error: (out NSError **)outError;

/// Returns a string representation of the configuration in DOSBox format,
/// as it would look when written to a file.
@property (readonly, copy) NSString *description;


#pragma mark -
#pragma mark Setting and getting individual settings

/// Gets the value for the setting with the specified key under the specified section.
/// Will return nil if the setting is not found.
- (nullable NSString *) valueForKey: (NSString *)settingName
						  inSection: (NSString *)sectionName;

/// Sets the value for the setting with the specified key under the specified section.
- (void) setValue: (NSString *)settingValue
		   forKey: (NSString *)settingName
		inSection: (NSString *)sectionName;

/// Removes the setting with the specified key and section altogether from the configuration.
- (void) removeValueForKey: (NSString *)settingName
				 inSection: (NSString *)sectionName;


#pragma mark -
#pragma mark Setting and getting startup commands

/// Adds the specified command onto the end of the startup commands.
- (void) addStartupCommand: (NSString *)command;

/// Adds all the specified commands onto the end of the startup commands.
- (void) addStartupCommands: (NSArray<NSString*> *)commands;

/// Removes all occurrences of the specified command.
/// Only exact matches will be removed.
- (void) removeStartupCommand: (NSString *)command;

/// Removes all startup commands.
- (void) removeStartupCommands;


#pragma mark -
#pragma mark Setting and getting sections

/// Return a dictionary of all settings for the specified section.
- (nullable NSDictionary<NSString*,NSString*> *) settingsForSection: (NSString *)sectionName;

/// Replaces the settings for the specified section with the new ones.
- (void) setSettings: (nullable NSDictionary<NSString*,NSString*> *)newSettings forSection: (NSString *)sectionName;

/// Merges the specfied configuration settings into the specified section.
/// Duplicate settings will be overridden; otherwise existing sections and settings will be left in place.
- (void) addSettings: (NSDictionary<NSString*,NSString*> *)newSettings toSection: (NSString *)sectionName;

/// Remove an entire section and all its settings.
- (void) removeSection: (NSString *)sectionName;


#pragma mark -
#pragma mark Merging settings from other configurations

/// Merges the configuration settings from the specified configuration into this one.
/// Duplicate settings will be overridden; otherwise existing sections and settings will be left in place.
- (void) addSettingsFromConfiguration: (BXEmulatorConfiguration *)configuration;

/// Merges the configuration settings from the specified dictionary into this configuration.
/// Duplicate settings will be overridden; otherwise existing sections and settings will be left in place.
- (void) addSettingsFromDictionary: (NSDictionary<NSString*,id> *)newSettings;

/// Eliminates all configuration settings that are identical to those in the specified configuration,
/// leaving only the settings that differ.
- (void) excludeDuplicateSettingsFromConfiguration: (BXEmulatorConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
