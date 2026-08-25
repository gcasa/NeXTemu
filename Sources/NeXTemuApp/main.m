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

#import <AppKit/AppKit.h>
#import "NXTAppDelegate.h"

int
main (int argc, const char **argv)
{
  NSAutoreleasePool *pool;
  NSApplication *application;
  NXTAppDelegate *delegate;

  (void)argc;
  (void)argv;
  pool = [[NSAutoreleasePool alloc] init];
  application = [NSApplication sharedApplication];
  delegate = [[NXTAppDelegate alloc] init];
  [application setDelegate:delegate];
  [application run];
  [delegate release];
  [pool drain];
  return 0;
}
