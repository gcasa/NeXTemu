#import "NXTAppDelegate.h"

@interface NXTDisplayView : NSView
@end

@implementation NXTDisplayView

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [[NSColor blackColor] set];
    NSRectFill([self bounds]);
}

@end

static NSTextField *NXTCreateLabel(NSRect frame, NSString *text)
{
    NSTextField *field;
    field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setStringValue:text];
    [field setEditable:NO];
    [field setSelectable:NO];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    return field;
}

@implementation NXTAppDelegate

- (void)dealloc
{
    [_machine release];
    [_window release];
    [super dealloc];
}

- (void)buildMenu
{
    NSMenu *menuBar;
    NSMenuItem *applicationItem;
    NSMenu *applicationMenu;
    NSMenuItem *machineItem;
    NSMenu *machineMenu;

    menuBar = [[[NSMenu alloc] initWithTitle:@"Main Menu"] autorelease];
    applicationItem = [[[NSMenuItem alloc] initWithTitle:@"NeXTemu"
                                                   action:NULL
                                            keyEquivalent:@""] autorelease];
    [menuBar addItem:applicationItem];
    applicationMenu = [[[NSMenu alloc] initWithTitle:@"NeXTemu"] autorelease];
    [applicationMenu addItemWithTitle:@"About NeXTemu"
                                action:@selector(showAboutPanel:)
                         keyEquivalent:@""];
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    [applicationMenu addItemWithTitle:@"Quit NeXTemu"
                                action:@selector(terminate:)
                         keyEquivalent:@"q"];
    [applicationItem setSubmenu:applicationMenu];

    machineItem = [[[NSMenuItem alloc] initWithTitle:@"Machine"
                                               action:NULL
                                        keyEquivalent:@""] autorelease];
    [menuBar addItem:machineItem];
    machineMenu = [[[NSMenu alloc] initWithTitle:@"Machine"] autorelease];
    [machineMenu addItemWithTitle:@"Open ROM..."
                            action:@selector(openROM:)
                     keyEquivalent:@"o"];
    [machineMenu addItemWithTitle:@"Reset"
                            action:@selector(resetMachine:)
                     keyEquivalent:@"r"];
    [machineItem setSubmenu:machineMenu];
    [NSApp setMainMenu:menuBar];
}

- (void)buildWindow
{
    NSView *contentView;
    NSTextField *titleField;
    NSTextField *modelLabel;
    NSButton *openButton;
    NSButton *resetButton;
    NSUInteger style;

    style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 760, 620)
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"NeXTemu"];
    contentView = [_window contentView];

    titleField = NXTCreateLabel(NSMakeRect(24, 574, 420, 26), @"NeXTcube Emulator");
    [titleField setFont:[NSFont boldSystemFontOfSize:18.0]];
    [contentView addSubview:titleField];

    modelLabel = NXTCreateLabel(NSMakeRect(24, 538, 60, 24), @"Model:");
    [contentView addSubview:modelLabel];
    _modelButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(84, 534, 220, 30)
                                              pullsDown:NO];
    [_modelButton addItemWithTitle:@"NeXTcube (68040, 25 MHz)"];
    [_modelButton addItemWithTitle:@"NeXTcube Turbo (68040, 33 MHz)"];
    [contentView addSubview:_modelButton];
    [_modelButton release];

    openButton = [[[NSButton alloc] initWithFrame:NSMakeRect(570, 534, 166, 30)] autorelease];
    [openButton setTitle:@"Choose ROM..."];
    [openButton setBezelStyle:NSRoundedBezelStyle];
    [openButton setTarget:self];
    [openButton setAction:@selector(openROM:)];
    [contentView addSubview:openButton];

    _romField = [NXTCreateLabel(NSMakeRect(24, 504, 712, 22), @"No ROM selected") retain];
    [_romField setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [contentView addSubview:_romField];

    _displayView = [[NXTDisplayView alloc] initWithFrame:NSMakeRect(24, 96, 712, 392)];
    [contentView addSubview:_displayView];
    [_displayView release];

    _statusField = [NXTCreateLabel(NSMakeRect(24, 60, 520, 24), @"Stopped — choose a 128 KiB NeXT ROM image") retain];
    [contentView addSubview:_statusField];
    _registerField = [NXTCreateLabel(NSMakeRect(24, 32, 520, 24), @"SSP: —    PC: —") retain];
    [_registerField setFont:[NSFont userFixedPitchFontOfSize:12.0]];
    [contentView addSubview:_registerField];

    resetButton = [[[NSButton alloc] initWithFrame:NSMakeRect(570, 42, 166, 32)] autorelease];
    [resetButton setTitle:@"Reset Machine"];
    [resetButton setBezelStyle:NSRoundedBezelStyle];
    [resetButton setTarget:self];
    [resetButton setAction:@selector(resetMachine:)];
    [contentView addSubview:resetButton];

    [_window center];
    [_window makeKeyAndOrderFront:self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    [self buildMenu];
    [self buildWindow];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application
{
    (void)application;
    return YES;
}

- (void)openROM:(id)sender
{
    NSOpenPanel *panel;
    NSInteger response;
    NSString *path;
    NSString *errorMessage;
    NXTMachineModel model;
    NXTMachine *newMachine;

    (void)sender;
    panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setCanChooseFiles:YES];
    response = [panel runModal];
    if (response != NSOKButton) return;
    path = [panel filename];
    model = [_modelButton indexOfSelectedItem] == 0
        ? NXTMachineModelNeXTcube : NXTMachineModelNeXTcubeTurbo;
    newMachine = [[NXTMachine alloc] initWithModel:model
                                           ramSize:16U * 1024U * 1024U];
    errorMessage = nil;
    if (newMachine == nil || ![newMachine loadROMAtPath:path error:&errorMessage]) {
        if (errorMessage == nil) errorMessage = @"Unable to create the emulated machine";
        NSRunAlertPanel(@"Cannot Open ROM", @"%@", @"OK", nil, nil, errorMessage);
        [newMachine release];
        return;
    }
    [_machine release];
    _machine = newMachine;
    [_romField setStringValue:path];
    [self resetMachine:self];
}

- (void)resetMachine:(id)sender
{
    NSString *registers;
    (void)sender;
    if (_machine == nil) {
        NSBeep();
        [_statusField setStringValue:@"Stopped — choose a 128 KiB NeXT ROM image"];
        return;
    }
    if (![_machine reset]) {
        [_statusField setStringValue:@"Reset failed: ROM vectors could not be read"];
        return;
    }
    [_statusField setStringValue:@"ROM loaded; processor reset complete (execution core pending)"];
    registers = [NSString stringWithFormat:@"SSP: %08x    PC: %08x",
        (unsigned int)[[_machine processor] addressRegister:7],
        (unsigned int)[[_machine processor] programCounter]];
    [_registerField setStringValue:registers];
}

- (void)showAboutPanel:(id)sender
{
    (void)sender;
    NSRunInformationalAlertPanel(@"About NeXTemu",
        @"A portable NeXTcube emulator built with Objective-C 1.0 conventions.",
        @"OK", nil, nil);
}

@end
