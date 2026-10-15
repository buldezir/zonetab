// Private WindowServer / Accessibility functions. All of these are exported by public frameworks
// (CoreGraphics, HIServices); the SkyLight-only functions are looked up at runtime in SkyLight.swift.

#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <stdbool.h>

typedef int32_t CGSConnectionID;

/// Symbolic hot key ids: 1 = ⌘⇥ (app switcher), 2 = ⌘⇧⇥. Disabling them persists after the process exits.
extern CGError CGSSetSymbolicHotKeyEnabled(int32_t hotKey, bool enabled);

extern CGSConnectionID CGSMainConnectionID(void);

/// Per display: "Display Identifier" (UUID string, or "Main" when displays share Spaces) and
/// "Current Space" (a dictionary whose "type" is 4 for a full-screen Space).
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID cid) CF_RETURNS_RETAINED;

/// The WindowServer window id behind an AX window element.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

/// GetProcessForPID is deprecated (and hidden from Swift) but still the only way to get the process serial number
/// the SkyLight focus functions take.
static inline OSStatus ZTGetProcessForPID(pid_t pid, ProcessSerialNumber *psn) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return GetProcessForPID(pid, psn);
#pragma clang diagnostic pop
}
