#import <AppKit/AppKit.h>
#import "NXTAppDelegate.h"

int main(int argc, const char **argv)
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
