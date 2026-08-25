/*
 * Copyright (C) 2026 Gregory Casamento
 *
 * This file is part of NeXTemu.
 *
 * NeXTemu is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * NeXTemu is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with NeXTemu.  If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef NXT_APP_DELEGATE_H
#define NXT_APP_DELEGATE_H

#import <AppKit/AppKit.h>
#import "NXTMachine.h"

/** Coordinates the NeXTemu application, machine, and display window. */
@interface NXTAppDelegate : NSObject <NSApplicationDelegate>
{
  NSWindow *_window;
  NSPopUpButton *_modelButton;
  NSButton *_verboseButton;
  NSPopUpButton *_framebufferScaleButton;
  NSScrollView *_displayScrollView;
  NSTextField *_romField;
  NSTextField *_diskField;
  NSTextField *_statusField;
  NSTextField *_registerField;
  NSTextField *_speedField;
  NSView *_displayView;
  NXTMachine *_machine;
  NSTimer *_emulationTimer;
  unsigned int _displayTicks;
  NXTUInt64 _speedSampleInstructions;
  NSTimeInterval _speedSampleTime;
}

/** Builds the application interface and restores the previous configuration.
 */
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
/** Returns whether closing the last application window should terminate. */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)application;
/** Presents a panel for selecting and loading a ROM image. */
- (void)openROM:(id)sender;
/** Presents a panel for selecting and attaching a raw disk image. */
- (void)openDiskImage:(id)sender;
/** Resets the emulated machine. */
- (void)resetMachine:(id)sender;
/** Updates the verbose firmware-boot preference. */
- (void)toggleVerboseBoot:(id)sender;
/** Updates the framebuffer display scale. */
- (void)changeFramebufferScale:(id)sender;
/** Presents the application's About panel. */
- (void)showAboutPanel:(id)sender;
/** Loads a ROM image, optionally presenting errors to the user. */
- (BOOL)loadROMAtPath:(NSString *)path showErrors:(BOOL)showErrors;
/** Advances emulation and refreshes the application display. */
- (void)emulationTick:(NSTimer *)timer;

@end

#endif
