#ifndef NXT_APP_DELEGATE_H
#define NXT_APP_DELEGATE_H

#import <AppKit/AppKit.h>
#import "NXTMachine.h"

@interface NXTAppDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow *_window;
    NSPopUpButton *_modelButton;
    NSTextField *_romField;
    NSTextField *_statusField;
    NSTextField *_registerField;
    NSView *_displayView;
    NXTMachine *_machine;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application;
- (void)openROM:(id)sender;
- (void)resetMachine:(id)sender;
- (void)showAboutPanel:(id)sender;

@end

#endif
