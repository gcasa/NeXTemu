#import "NXTAppDelegate.h"

static NSString * const NXTSCSIDiskPathDefaultsKey = @"NXTSCSIDiskImagePath";
static NSString * const NXTVerboseBootDefaultsKey = @"NXTVerboseBoot";
static NSString * const NXTFramebufferScaleDefaultsKey = @"NXTFramebufferScale";

@interface NXTDisplayView : NSView
{
    NXTMemory *_memory;
}
- (void)setMemory:(NXTMemory *)memory;
@end

@implementation NXTDisplayView

- (void)dealloc
{
    [_memory release];
    [super dealloc];
}

- (void)setMemory:(NXTMemory *)memory
{
    if (_memory == memory) return;
    [memory retain];
    [_memory release];
    _memory = memory;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NXTMemoryRegion *framebuffer;
    NSBitmapImageRep *bitmap;
    NXTUInt8 *source;
    unsigned char *destination;
    unsigned int x;
    unsigned int y;
    unsigned int pixel;
    unsigned int shade;
    unsigned int sourceIndex;
    BOOL hasVideo;
    NSDictionary *attributes;
    unsigned int sourceStride;
    (void)dirtyRect;
    [[NSColor blackColor] set];
    NSRectFill([self bounds]);
    if (_memory == nil) return;
    framebuffer = [_memory regionContainingAddress:0x0c000000U length:288U * 832U];
    if (framebuffer == nil)
        framebuffer = [_memory regionContainingAddress:0x0b000000U length:288U * 832U];
    if (framebuffer == nil) return;
    sourceStride = [framebuffer baseAddress] == 0x0c000000U ? 280U : 288U;
    source = [framebuffer mutableBytes];
    hasVideo = NO;
    for (sourceIndex = 0; sourceIndex < sourceStride * 832U; sourceIndex++) {
        if (source[sourceIndex] != 0) { hasVideo = YES; break; }
    }
    if (!hasVideo) {
        attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSColor whiteColor], NSForegroundColorAttributeName,
            [NSFont boldSystemFontOfSize:20.0], NSFontAttributeName, nil];
        [@"NeXT firmware is running…" drawAtPoint:NSMakePoint(225, 180)
                                      withAttributes:attributes];
        return;
    }
    bitmap = [[[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:1120 pixelsHigh:832
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:1120 * 4 bitsPerPixel:32]
        autorelease];
    if (bitmap == nil) return;
    destination = [bitmap bitmapData];
    for (y = 0; y < 832; y++) {
        for (x = 0; x < 1120; x++) {
            pixel = (source[y * sourceStride + x / 4] >> (6 - 2 * (x & 3))) & 3;
            shade = 255 - pixel * 85;
            destination[(y * 1120 + x) * 4 + 0] = (unsigned char)shade;
            destination[(y * 1120 + x) * 4 + 1] = (unsigned char)shade;
            destination[(y * 1120 + x) * 4 + 2] = (unsigned char)shade;
            destination[(y * 1120 + x) * 4 + 3] = 255;
        }
    }
    [bitmap drawInRect:[self bounds]];
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
    [_emulationTimer invalidate];
    [_emulationTimer release];
    [_diskField release];
    [_romField release];
    [_statusField release];
    [_registerField release];
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
    [machineMenu addItemWithTitle:@"Attach SCSI Disk..."
                            action:@selector(openDiskImage:)
                     keyEquivalent:@"d"];
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
    NSTextField *scaleLabel;
    NSButton *openButton;
    NSButton *resetButton;
    NSButton *diskButton;
    NSUInteger style;

    style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 760, 620)
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"NeXTemu"];
    contentView = [_window contentView];

    titleField = NXTCreateLabel(NSMakeRect(24, 174, 420, 26), @"NeXTcube Emulator");
    [titleField setFont:[NSFont boldSystemFontOfSize:18.0]];
    [contentView addSubview:titleField];

    modelLabel = NXTCreateLabel(NSMakeRect(24, 140, 60, 24), @"Model:");
    [contentView addSubview:modelLabel];
    _modelButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(84, 136, 220, 30)
                                              pullsDown:NO];
    [_modelButton addItemWithTitle:@"NeXTcube (68040, 25 MHz)"];
    [_modelButton addItemWithTitle:@"NeXTcube Turbo (68040, 33 MHz)"];
    [contentView addSubview:_modelButton];
    [_modelButton release];

    _verboseButton = [[[NSButton alloc] initWithFrame:NSMakeRect(324, 138, 150, 24)] autorelease];
    [_verboseButton setButtonType:NSSwitchButton];
    [_verboseButton setTitle:@"Verbose boot (-v)"];
    [_verboseButton setState:[[NSUserDefaults standardUserDefaults]
        boolForKey:NXTVerboseBootDefaultsKey] ? NSOnState : NSOffState];
    [_verboseButton setTarget:self];
    [_verboseButton setAction:@selector(toggleVerboseBoot:)];
    [contentView addSubview:_verboseButton];

    openButton = [[[NSButton alloc] initWithFrame:NSMakeRect(570, 106, 166, 30)] autorelease];
    [openButton setTitle:@"Choose ROM..."];
    [openButton setBezelStyle:NSRoundedBezelStyle];
    [openButton setTarget:self];
    [openButton setAction:@selector(openROM:)];
    [contentView addSubview:openButton];

    _romField = [NXTCreateLabel(NSMakeRect(24, 110, 530, 22), @"No ROM selected") retain];
    [_romField setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [contentView addSubview:_romField];

    _diskField = [NXTCreateLabel(NSMakeRect(24, 80, 350, 22), @"No SCSI disk attached") retain];
    [_diskField setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [contentView addSubview:_diskField];
    diskButton = [[[NSButton alloc] initWithFrame:NSMakeRect(570, 76, 166, 30)] autorelease];
    [diskButton setTitle:@"Attach Disk..."];
    [diskButton setBezelStyle:NSRoundedBezelStyle];
    [diskButton setTarget:self];
    [diskButton setAction:@selector(openDiskImage:)];
    [contentView addSubview:diskButton];

    scaleLabel = NXTCreateLabel(NSMakeRect(382, 82, 48, 22), @"Scale:");
    [contentView addSubview:scaleLabel];
    _framebufferScaleButton = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(428, 78, 126, 30) pullsDown:NO];
    [_framebufferScaleButton addItemWithTitle:@"100%"];
    [_framebufferScaleButton addItemWithTitle:@"200%"];
    [_framebufferScaleButton addItemWithTitle:@"300%"];
    [_framebufferScaleButton setTarget:self];
    [_framebufferScaleButton setAction:@selector(changeFramebufferScale:)];
    [contentView addSubview:_framebufferScaleButton];
    [_framebufferScaleButton release];

    _displayScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 210, 712, 368)];
    [_displayScrollView setHasHorizontalScroller:NO];
    [_displayScrollView setHasVerticalScroller:NO];
    [_displayScrollView setBorderType:NSNoBorder];
    _displayView = [[NXTDisplayView alloc] initWithFrame:NSMakeRect(0, 0, 1120, 832)];
    [_displayScrollView setDocumentView:_displayView];
    [contentView addSubview:_displayScrollView];
    [_displayView release];
    [_displayScrollView release];

    _statusField = [NXTCreateLabel(NSMakeRect(24, 48, 520, 24), @"Stopped — choose a 128 KiB NeXT ROM image") retain];
    [contentView addSubview:_statusField];
    _registerField = [NXTCreateLabel(NSMakeRect(24, 20, 520, 24), @"SSP: —    PC: —") retain];
    [_registerField setFont:[NSFont userFixedPitchFontOfSize:12.0]];
    [contentView addSubview:_registerField];

    resetButton = [[[NSButton alloc] initWithFrame:NSMakeRect(570, 28, 166, 32)] autorelease];
    [resetButton setTitle:@"Reset Machine"];
    [resetButton setBezelStyle:NSRoundedBezelStyle];
    [resetButton setTarget:self];
    [resetButton setAction:@selector(resetMachine:)];
    [contentView addSubview:resetButton];

    {
        NSView *subview;
        for (subview in [contentView subviews]) {
            [subview setAutoresizingMask:NSViewNotSizable];
        }
    }
    {
        NSInteger savedScale = [[NSUserDefaults standardUserDefaults]
            integerForKey:NXTFramebufferScaleDefaultsKey];
        if (savedScale != 200 && savedScale != 300) savedScale = 100;
        [_framebufferScaleButton selectItemWithTitle:
            [NSString stringWithFormat:@"%ld%%", (long)savedScale]];
        [self changeFramebufferScale:_framebufferScaleButton];
    }

    [_window center];
    [_window makeKeyAndOrderFront:self];
    _emulationTimer = [[NSTimer scheduledTimerWithTimeInterval:0.02
                                                       target:self
                                                     selector:@selector(emulationTick:)
                                                     userInfo:nil
                                                      repeats:YES] retain];
}

- (void)openDiskImage:(id)sender
{
    NSOpenPanel *panel;
    NSInteger response;
    NSString *path;
    NSString *errorMessage;
    (void)sender;
    if (_machine == nil) {
        NSRunAlertPanel(@"No Machine", @"Load a ROM before attaching a disk image.",
                        @"OK", nil, nil);
        return;
    }
    panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setCanChooseFiles:YES];
    response = [panel runModal];
    if (response != NSOKButton) return;
    path = [panel filename];
    errorMessage = nil;
    if (![_machine attachDiskImageAtPath:path error:&errorMessage]) {
        NSRunAlertPanel(@"Cannot Attach Disk", @"%@", @"OK", nil, nil, errorMessage);
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:path
                                              forKey:NXTSCSIDiskPathDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [_diskField setStringValue:[NSString stringWithFormat:@"SCSI disk: %@ (%.1f MiB)",
        path, (double)[_machine diskImageSize] / (1024.0 * 1024.0)]];
    if (![_machine reset]) {
        [_statusField setStringValue:@"SCSI disk attached, but the machine could not reset"];
        return;
    }
    [_statusField setStringValue:@"SCSI disk attached at target 0 — machine restarted"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSString *romsPath;
    NSArray *files;
    NSUInteger index;
    NSString *candidate;
    (void)notification;
    [self buildMenu];
    [self buildWindow];
    [NSApp activateIgnoringOtherApps:YES];
    romsPath = [[NSBundle mainBundle] pathForResource:@"roms" ofType:nil];
    files = romsPath == nil ? nil : [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:romsPath error:NULL];
    files = [files sortedArrayUsingSelector:@selector(compare:)];
    /* Prefer the newest bundled revision instead of filesystem order. */
    for (index = [files count]; index > 0; index--) {
        candidate = [romsPath stringByAppendingPathComponent:[files objectAtIndex:index - 1]];
        if ([self loadROMAtPath:candidate showErrors:NO]) break;
    }
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

    (void)sender;
    panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setCanChooseFiles:YES];
    response = [panel runModal];
    if (response != NSOKButton) return;
    path = [panel filename];
    [self loadROMAtPath:path showErrors:YES];
}

- (BOOL)loadROMAtPath:(NSString *)path showErrors:(BOOL)showErrors
{
    NSString *errorMessage;
    NSString *savedDiskPath;
    NXTMachineModel model;
    NXTMachine *newMachine;

    if ([[[path lastPathComponent] lowercaseString] rangeOfString:@"v74"].location != NSNotFound ||
        [[[path lastPathComponent] lowercaseString] rangeOfString:@"v72"].location != NSNotFound ||
        [[[path lastPathComponent] lowercaseString] rangeOfString:@"rev_3"].location != NSNotFound)
        [_modelButton selectItemAtIndex:1];
    model = [_modelButton indexOfSelectedItem] == 0
        ? NXTMachineModelNeXTcube : NXTMachineModelNeXTcubeTurbo;
    newMachine = [[NXTMachine alloc] initWithModel:model
                                           ramSize:(model == NXTMachineModelNeXTcubeTurbo
                                               ? 128U : 16U) * 1024U * 1024U];
    [newMachine setVerboseBoot:[[_verboseButton cell] state] == NSOnState];
    errorMessage = nil;
    if (newMachine == nil || ![newMachine loadROMAtPath:path error:&errorMessage]) {
        if (errorMessage == nil) errorMessage = @"Unable to create the emulated machine";
        if (showErrors)
            NSRunAlertPanel(@"Cannot Open ROM", @"%@", @"OK", nil, nil, errorMessage);
        [newMachine release];
        return NO;
    }
    [_machine release];
    _machine = newMachine;
    [_diskField setStringValue:@"No SCSI disk attached"];
    savedDiskPath = [[NSUserDefaults standardUserDefaults]
        stringForKey:NXTSCSIDiskPathDefaultsKey];
    if (savedDiskPath != nil &&
        [[NSFileManager defaultManager] fileExistsAtPath:savedDiskPath]) {
        errorMessage = nil;
        if ([_machine attachDiskImageAtPath:savedDiskPath error:&errorMessage]) {
            [_diskField setStringValue:[NSString stringWithFormat:@"SCSI disk: %@ (%.1f MiB)",
                savedDiskPath, (double)[_machine diskImageSize] / (1024.0 * 1024.0)]];
        } else {
            [[NSUserDefaults standardUserDefaults]
                removeObjectForKey:NXTSCSIDiskPathDefaultsKey];
        }
    }
    [(NXTDisplayView *)_displayView setMemory:[_machine memory]];
    [_romField setStringValue:path];
    [self resetMachine:self];
    return YES;
}

- (void)resetMachine:(id)sender
{
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
    [_statusField setStringValue:@"Running firmware…"];
    [_registerField setStringValue:@"SSP: 04000400    PC: 0100001e"];
    [_displayView setNeedsDisplay:YES];
}

- (void)toggleVerboseBoot:(id)sender
{
    BOOL enabled = [sender state] == NSOnState;
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:NXTVerboseBootDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (_machine != nil) {
        [_machine setVerboseBoot:enabled];
        [self resetMachine:sender];
        [_statusField setStringValue:enabled
            ? @"Verbose boot enabled — machine restarted"
            : @"Verbose boot disabled — machine restarted"];
    }
}

- (void)changeFramebufferScale:(id)sender
{
    NSInteger scale = 100;
    NSString *title = [sender titleOfSelectedItem];
    NSSize framebufferSize;
    NSSize contentSize;
    NSRect windowFrame;
    CGFloat oldTop;
    if ([title hasPrefix:@"200"]) scale = 200;
    else if ([title hasPrefix:@"300"]) scale = 300;
    [[NSUserDefaults standardUserDefaults] setInteger:scale
                                                forKey:NXTFramebufferScaleDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    framebufferSize = NSMakeSize(1120.0 * scale / 100.0,
                                 832.0 * scale / 100.0);
    contentSize = NSMakeSize(framebufferSize.width + 48.0,
                             framebufferSize.height + 234.0);
    windowFrame = [_window frame];
    oldTop = NSMaxY(windowFrame);
    windowFrame.size = [_window frameRectForContentRect:
        NSMakeRect(0, 0, contentSize.width, contentSize.height)].size;
    windowFrame.origin.y = oldTop - windowFrame.size.height;
    [_window setFrame:windowFrame display:YES animate:NO];
    [_displayScrollView setFrame:NSMakeRect(24, 210,
                                             framebufferSize.width,
                                             framebufferSize.height)];
    [_displayView setFrameSize:framebufferSize];
    [_displayView setNeedsDisplay:YES];
}

- (void)emulationTick:(NSTimer *)timer
{
    NSString *registers;
    NSString *status;
    NXTProcessorResult result;
    (void)timer;
    if (_machine == nil || [[_machine processor] isStopped]) return;
    result = [_machine runForInstructionCount:100000];
    if (result == NXTProcessorResultStopped) {
        status = @"Processor stopped normally";
    } else if (result == NXTProcessorResultInstructionLimit) {
        status = [NSString stringWithFormat:@"Running — %llu instructions",
            (unsigned long long)[[_machine processor] instructionsExecuted]];
    } else if (result == NXTProcessorResultBusError) {
        status = @"Processor halted on an unmapped memory access";
    } else {
        status = [NSString stringWithFormat:@"Unsupported opcode %04x at %08x",
            (unsigned int)[[_machine processor] lastOpcode],
            (unsigned int)[[_machine processor] lastOpcodeAddress]];
    }
    [_statusField setStringValue:status];
    registers = [NSString stringWithFormat:@"SSP: %08x    PC: %08x",
        (unsigned int)[[_machine processor] addressRegister:7],
        (unsigned int)[[_machine processor] programCounter]];
    [_registerField setStringValue:registers];
    _displayTicks++;
    if ((_displayTicks % 5) == 0) [_displayView setNeedsDisplay:YES];
}

- (void)showAboutPanel:(id)sender
{
    (void)sender;
    NSRunInformationalAlertPanel(@"About NeXTemu",
        @"A portable NeXTcube emulator built with Objective-C 1.0 conventions.",
        @"OK", nil, nil);
}

@end
