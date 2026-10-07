/* Mac OS X portion of menu.cpp */

#include "config.h"
#include "codepage.h"
#include "dos_inc.h"
#include "menu.h"
#include "mapper.h"
#include "macosx_host.h"
#include "sdlmain.h"

#if defined(C_SDL2) && !(defined(C_NATIVE_MACOS) && C_NATIVE_MACOS)
# include "SDL.h"
# include "SDL_version.h"
# include "SDL_syswm.h"
#endif

#if defined(MACOSX)
# include <MacTypes.h>
# include <Cocoa/Cocoa.h>
# include <Carbon/Carbon.h>
# include <ApplicationServices/ApplicationServices.h>
# include <IOKit/pwr_mgt/IOPMLib.h>

#if defined(__clang__)
# if __has_feature(objc_arc)
#  error "menu_macos.mm uses manual reference counting and must be compiled without ARC"
# endif
#endif

#if DOSBOXMENU_TYPE == DOSBOXMENU_NSMENU
@interface NSApplication (DOSBoxX)
- (void)DOSBoxXMenuAction:(id)sender;
- (void)DOSBoxXMenuActionNewInstance:(id)sender;
- (void)DOSBoxXMenuActionMapper:(id)sender;
- (void)DOSBoxXMenuActionCapMouse:(id)sender;
- (void)DOSBoxXMenuActionCfgGUI:(id)sender;
- (void)DOSBoxXMenuActionPause:(id)sender;
@end
#endif

#if !defined(C_SDL2)
extern "C" void* sdl1_hax_stock_macosx_menu(void);
extern "C" void sdl1_hax_stock_macosx_menu_additem(NSMenu *modme);
extern "C" NSWindow *sdl1_hax_get_window(void);
#endif

static NSWindow *macosx_active_window(void)
{
#if defined(C_NATIVE_MACOS) && C_NATIVE_MACOS
    return (NSWindow *)macosx_native_window();
#elif defined(C_SDL2)
    SDL_SysWMinfo wminfo = {};
    SDL_VERSION(&wminfo.version);
    if (SDL_GetWindowWMInfo(GFX_GetSDLWindow(), &wminfo) >= 0 &&
        wminfo.subsystem == SDL_SYSWM_COCOA)
        return wminfo.info.cocoa.window;
    return nil;
#else
    return sdl1_hax_get_window();
#endif
}

void *macosx_content_view(void)
{
    NSWindow *wnd = macosx_active_window();
    return wnd ? (void *)[wnd contentView] : nullptr;
}

#if !defined(C_SDL2)
void SetAlpha(double alpha) {
    NSWindow *wnd = macosx_active_window();
    if (wnd != nil) wnd.alphaValue = alpha;
}
#else
void sdl1_hax_set_topmost(unsigned char topmost) {
    NSWindow *wnd = macosx_active_window();
    if (wnd != nil) {
        if (topmost)
            [ wnd setLevel: NSStatusWindowLevel ];
        else
            [ wnd setLevel: NSNormalWindowLevel ];
    }
}
#endif

#if defined(MACOSX)
void MacOSEnableWindowCapture(unsigned int enable) {
    NSWindow *wnd = macosx_active_window();

    if (wnd) {
        [wnd setSharingType:(enable?NSWindowSharingReadOnly:NSWindowSharingNone)];
    }
}
#endif

#if defined(MACOSX) && defined(C_SDL2)
bool IME_GetEnable() {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (!source)
        return false;

    CFBooleanRef ascii_capable = (CFBooleanRef)TISGetInputSourceProperty(
        source, kTISPropertyInputSourceIsASCIICapable);
    const bool enabled = ascii_capable ? !CFBooleanGetValue(ascii_capable) : false;
    CFRelease(source);
    return enabled;
}

void IME_SetEnable(int state) {
    if (state) {
        NSArray *languages = [NSLocale preferredLanguages];
        NSString *locale = [languages count] > 0
                                 ? [languages objectAtIndex:0]
                                 : [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
        if (!locale)
            return;

        TISInputSourceRef source = TISCopyInputSourceForLanguage((CFStringRef)locale);
        if (source) {
            TISSelectInputSource(source);
            CFRelease(source);
        }
        return;
    }

    CFArrayRef sources = TISCreateASCIICapableInputSourceList();
    if (!sources)
        return;

    if (CFArrayGetCount(sources) > 0) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, 0);
        if (source)
            TISSelectInputSource(source);
    }
    CFRelease(sources);
}
#endif

extern int pause_menu_item_tag;

char tempstr[4096];

bool macosx_clipboard_get(std::string &result)
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *text = [pb stringForType:NSPasteboardTypeString];
    if (!text) {
        result.clear();
        return false;
    }

    const char *utf8 = [text UTF8String];
    result.assign(utf8 ? utf8 : "");
    return utf8 != nullptr;
}

bool macosx_clipboard_set(const std::string &value)
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *text = [NSString stringWithUTF8String:value.c_str()];
    if (!text)
        return false;

    [pb clearContents];
    return [pb setString:text forType:NSPasteboardTypeString];
}

bool has_touch_bar_support = false;

bool macosx_detect_nstouchbar(void) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101202/* touch bar interface appeared in 10.12.2+ according to Apple */
    return (has_touch_bar_support = (NSClassFromString(@"NSTouchBar") != nil));
#else
    return false;
#endif
}

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101202/* touch bar interface appeared in 10.12.2+ according to Apple */
# if !defined(C_SDL2)
extern "C" void sdl1_hax_make_touch_bar_set_callback(NSTouchBar* (*newcb)(NSWindow*));
# endif

static NSTouchBarItemIdentifier TouchBarCustomIdentifier = @"com.dosbox-x.touchbar.custom";
static NSTouchBarItemIdentifier TouchBarMapperIdentifier = @"com.dosbox-x.touchbar.mapper";
static NSTouchBarItemIdentifier TouchBarCFGGUIIdentifier = @"com.dosbox-x.touchbar.cfggui";
static NSTouchBarItemIdentifier TouchBarHostKeyIdentifier = @"com.dosbox-x.touchbar.hostkey";
static NSTouchBarItemIdentifier TouchBarPauseIdentifier = @"com.dosbox-x.touchbar.pause";
static NSTouchBarItemIdentifier TouchBarCursorCaptureIdentifier = @"com.dosbox-x.touchbar.capcursor";

@interface DOSBoxXTouchBarDelegate : NSViewController
@end

@interface DOSBoxXTouchBarDelegate () <NSTouchBarDelegate,NSTextViewDelegate>
@end

@interface DOSBoxHostButton : NSButton
@end
#endif


#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101202/* touch bar interface appeared in 10.12.2+ according to Apple */
@implementation DOSBoxHostButton
- (void)touchesBeganWithEvent:(NSEvent*)event
{
    fprintf(stderr,"Host key down\n");
    ext_signal_host_key(true);
    [super touchesBeganWithEvent:event];
}

- (void)touchesEndedWithEvent:(NSEvent*)event
{
    fprintf(stderr,"Host key up\n");
    ext_signal_host_key(false);
    [super touchesEndedWithEvent:event];
}

- (void)touchesCancelledWithEvent:(NSEvent*)event
{
    fprintf(stderr,"Host key cancelled\n");
    ext_signal_host_key(false);
    [super touchesCancelledWithEvent:event];
}
@end
#endif

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101202/* touch bar interface appeared in 10.12.2+ according to Apple */
@implementation DOSBoxXTouchBarDelegate
- (void)onHostKey:(id)sender
{
    (void)sender;
    fprintf(stderr,"HostKey\n");
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    (void)touchBar;

    if ([identifier isEqualToString:TouchBarMapperIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:TouchBarMapperIdentifier];

        item.view = [NSButton buttonWithTitle:@"Mapper" target:NSApp action:@selector(DOSBoxXMenuActionMapper:)];
        item.customizationLabel = TouchBarCustomIdentifier;

        return [item autorelease];
    }
    else if ([identifier isEqualToString:TouchBarHostKeyIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:TouchBarHostKeyIdentifier];

        item.view = [DOSBoxHostButton buttonWithTitle:@"Host Key" target:self action:@selector(onHostKey:)];
        item.customizationLabel = TouchBarCustomIdentifier;

        return [item autorelease];
    }
    else if ([identifier isEqualToString:TouchBarCFGGUIIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:TouchBarCFGGUIIdentifier];

        item.view = [NSButton buttonWithTitle:@"Cfg GUI" target:NSApp action:@selector(DOSBoxXMenuActionCfgGUI:)];
        item.customizationLabel = TouchBarCustomIdentifier;

        return [item autorelease];
    }
    else if ([identifier isEqualToString:TouchBarPauseIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:TouchBarPauseIdentifier];

        item.view = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameTouchBarPauseTemplate] target:NSApp action:@selector(DOSBoxXMenuActionPause:)];
        item.customizationLabel = TouchBarCustomIdentifier;

        return [item autorelease];
    }
    else if ([identifier isEqualToString:TouchBarCursorCaptureIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:TouchBarCursorCaptureIdentifier];

        item.view = [NSButton buttonWithTitle:@"CapMouse" target:NSApp action:@selector(DOSBoxXMenuActionCapMouse:)];
        item.customizationLabel = TouchBarCustomIdentifier;

        return [item autorelease];
    }
    else {
        fprintf(stderr,"Touch bar warning, unknown item '%s'\n",[identifier UTF8String]);
    }

    return nil;
}
@end
#endif

void macosx_reload_touchbar(void) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101202/* touch bar interface appeared in 10.12.2+ according to Apple */
    NSWindow *wnd = macosx_active_window();
    if (wnd != nil)
        [wnd setTouchBar:nil];

    macosx_init_touchbar();
#endif
}

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101202/* touch bar interface appeared in 10.12.2+ according to Apple */
NSTouchBar* macosx_on_make_touch_bar(NSWindow *wnd) {
    (void)wnd;

    // NSTouchBar.delegate is weak. Keep one stateless delegate alive for the
    // process instead of depending on a leaked temporary allocation.
    static DOSBoxXTouchBarDelegate *touchBarDelegate = nil;
    if (!touchBarDelegate)
        touchBarDelegate = [[DOSBoxXTouchBarDelegate alloc] init];

    NSTouchBar* touchBar = [[NSTouchBar alloc] init];
    touchBar.delegate = touchBarDelegate;

    touchBar.customizationIdentifier = TouchBarCustomIdentifier;
    if (GUI_IsRunning()) {
        touchBar.defaultItemIdentifiers = @[
            NSTouchBarItemIdentifierOtherItemsProxy
        ];
    }
    else if (MAPPER_IsRunning()) {
        touchBar.defaultItemIdentifiers = @[
            NSTouchBarItemIdentifierFixedSpaceLarge, // try to keep the user from hitting the ESC button accidentally when reaching for Host Key
            TouchBarHostKeyIdentifier,
            NSTouchBarItemIdentifierFixedSpaceLarge,
            NSTouchBarItemIdentifierOtherItemsProxy
        ];
    }
    else {
        touchBar.defaultItemIdentifiers = @[
            NSTouchBarItemIdentifierFixedSpaceLarge, // try to keep the user from hitting the ESC button accidentally when reaching for Host Key
            TouchBarHostKeyIdentifier,
            NSTouchBarItemIdentifierFixedSpaceLarge,
            TouchBarPauseIdentifier,
            NSTouchBarItemIdentifierFixedSpaceLarge,
            TouchBarCursorCaptureIdentifier,
            NSTouchBarItemIdentifierFixedSpaceLarge,
            TouchBarMapperIdentifier,
            TouchBarCFGGUIIdentifier,
            NSTouchBarItemIdentifierOtherItemsProxy
        ];
    }

    touchBar.customizationAllowedItemIdentifiers = @[
        TouchBarHostKeyIdentifier,
        TouchBarMapperIdentifier,
        TouchBarCFGGUIIdentifier,
        TouchBarCursorCaptureIdentifier,
        TouchBarPauseIdentifier
    ];

// Do not mark as principal, it just makes the button centered in the touch bar
//    touchBar.principalItemIdentifier = TouchBarMapperIdentifier;

    return touchBar;
}
#endif

void macosx_init_touchbar(void) {
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101202/* touch bar interface appeared in 10.12.2+ according to Apple */
    if (!has_touch_bar_support)
        return;

# if defined(C_SDL2)
    NSWindow *wnd = macosx_active_window();
    if (wnd != nil) {
        NSTouchBar *touchBar = macosx_on_make_touch_bar(wnd);
        [wnd setTouchBar:touchBar];
        [touchBar release];
    }
# else
    sdl1_hax_make_touch_bar_set_callback(macosx_on_make_touch_bar);
# endif
#endif
}

#if !defined(C_SDL2)
extern "C" void sdl1_hax_set_dock_menu(NSMenu *menu);
#endif

void macosx_init_dock_menu(void) {
#if !defined(C_SDL2)
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];

    {
        NSString *title = [[NSString alloc] initWithUTF8String: "Mapper editor"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(DOSBoxXMenuActionMapper:) keyEquivalent:@""];
        [menu addItem:item];
        [title release];
        [item release];
    }

    {
        NSString *title = [[NSString alloc] initWithUTF8String: "Configuration tool"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(DOSBoxXMenuActionCfgGUI:) keyEquivalent:@""];
        [menu addItem:item];
        [title release];
        [item release];
    }

    {
	    NSMenuItem *item = [NSMenuItem separatorItem];
        [menu addItem:item];
    }

    {
        NSString *title = [[NSString alloc] initWithUTF8String: "Pause emulation"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(DOSBoxXMenuActionPause:) keyEquivalent:@""];
        [menu addItem:item];
        [title release];
        [item release];
    }

    {
        bool enable = false;
        extern std::string MacOSXEXEPath;
        if (!MacOSXEXEPath.empty()) {
            if (MacOSXEXEPath.at(0) == '/') {
                enable = true;
            }
        }

        if (enable) {
            {
                NSMenuItem *item = [NSMenuItem separatorItem];
                [menu addItem:item];
            }

            NSString *title = [[NSString alloc] initWithUTF8String: "Start new instance"];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(DOSBoxXMenuActionNewInstance:) keyEquivalent:@""];
            [menu addItem:item];
            [title release];
            [item release];
        }
    }

    sdl1_hax_set_dock_menu(menu);

    [menu release];
#endif
}

#if !defined(C_SDL2)
extern "C" int sdl1_hax_macosx_window_to_monitor_and_update(CGDirectDisplayID *did);
#endif

static int my_quartz_match_window_to_monitor(CGDirectDisplayID *new_id, NSWindow *wnd);

void macosx_GetWindowDPI(ScreenSizeInfo &info) {
    NSWindow *wnd = macosx_active_window();

    info.clear();

    if (wnd != nil) {
        CGDirectDisplayID did = 0;

        if (my_quartz_match_window_to_monitor(&did,wnd) >= 0) {
            CGRect drct = CGDisplayBounds(did);
            CGSize dsz = CGDisplayScreenSize(did);
            CGDisplayModeRef mode = CGDisplayCopyDisplayMode(did);

            info.method = METHOD_COREGRAPHICS;

            info.screen_position_pixels.x        = drct.origin.x;
            info.screen_position_pixels.y        = drct.origin.y;

            /*
             * CGDisplayBounds follows the logical desktop coordinate space,
             * which is what window/fullscreen layout needs. Physical DPI,
             * however, must use the mode's backing-pixel dimensions on Retina
             * displays rather than those logical dimensions.
             */
            info.screen_dimensions_pixels.width  = drct.size.width;
            info.screen_dimensions_pixels.height = drct.size.height;

            const double backing_width = mode ? (double)CGDisplayModeGetPixelWidth(mode)
                                              : (double)drct.size.width;
            const double backing_height = mode ? (double)CGDisplayModeGetPixelHeight(mode)
                                               : (double)drct.size.height;

            /* According to Apple documentation, this function CAN return zero */
            if (dsz.width > 0 && dsz.height > 0) {
                info.screen_dimensions_mm.width      = dsz.width;
                info.screen_dimensions_mm.height     = dsz.height;

                if (info.screen_dimensions_mm.width > 0)
                    info.screen_dpi.width =
                        ((backing_width * 25.4) /
                         ((double)info.screen_dimensions_mm.width));

                if (info.screen_dimensions_mm.height > 0)
                    info.screen_dpi.height =
                        ((backing_height * 25.4) /
                         ((double)info.screen_dimensions_mm.height));
            }

            if (mode)
                CGDisplayModeRelease(mode);
        }
    }
}

static int my_quartz_match_window_to_monitor(CGDirectDisplayID *new_id, NSWindow *wnd) {
    if (new_id == NULL || wnd == nil)
        return -1;

    /*
     * NSWindow.screen is AppKit's authoritative display assignment and avoids
     * translating the window center through the primary display coordinate
     * system. It can be nil only while a window is entirely off-screen.
     */
    NSScreen *screen = [wnd screen];
    if (screen != nil) {
        NSNumber *screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
        if (screenNumber != nil) {
            *new_id = (CGDirectDisplayID)[screenNumber unsignedIntValue];
            return 0;
        }
    }

    /* Off-screen fallback: match the window center in global display space. */
    NSRect frame = [wnd frame];
    NSPoint center = NSMakePoint(NSMidX(frame), NSMidY(frame));
    CGRect mainBounds = CGDisplayBounds(CGMainDisplayID());
    CGPoint cgPoint = CGPointMake(center.x,
                                  CGRectGetMaxY(mainBounds) - center.y);
    uint32_t count = 1;
    CGDirectDisplayID display = 0;
    if (CGGetDisplaysWithPoint(cgPoint, 1, &display, &count) == kCGErrorSuccess &&
        count > 0) {
        *new_id = display;
        return 0;
    }

    *new_id = CGMainDisplayID();
    return 0;
}

#if !defined(C_SDL2)
extern "C" int (*sdl1_hax_quartz_match_window_to_monitor)(CGDirectDisplayID *new_id,NSWindow *wnd);
#endif

void qz_set_match_monitor_cb(void) {
#if !defined(C_SDL2)
    sdl1_hax_quartz_match_window_to_monitor = my_quartz_match_window_to_monitor;
#endif
}

// WARNING! You must initialize the SDL Video subsystem *FIRST*
// before calling this function, or else strange errors and
// malfunctions occur in the Cocoa framework (at least in Big Sur).
// You can quit the SDL Video subsystem and reinitialize later
// after this function is done.
std::string macosx_prompt_folder(const char *default_folder) {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    NSModalResponse r;
    std::string res;

    [panel setPrompt:@"Choose"];
    [panel setCanChooseFiles:false];
    [panel setCanChooseDirectories:true];
    [panel setAllowsMultipleSelection:false];
    [panel setMessage:@"Select folder where to run emulation, which will become DOSBox-X's working directory:"];
    [panel setCanCreateDirectories:true]; /* sure, why not? */
    if (default_folder != NULL) [panel setDirectoryURL:[NSURL fileURLWithPath:[NSString stringWithFormat:@"%s",default_folder]]];

    r = [panel runModal];
    if (r == NSModalResponseOK) {
        NSArray *urls = [panel URLs];
        if ([urls count] > 0) {
            NSURL *url = urls[0];
            if ([[url scheme] isEqual: @"file"]) {
                /* NTS: /path/to/file is returned as file:///path/to/file */
                res = [[url relativePath] UTF8String];
            }
            else {
                fprintf(stderr,"WARNING: Rejecting returned protocol '%s', no selection accepted\n",
                    [[url scheme] UTF8String]);
            }
        }
    }

    return res;
}

void macosx_alert(const char *title, const char *message) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:title ? [NSString stringWithUTF8String:title] : @""];
    [alert setInformativeText:message ? [NSString stringWithUTF8String:message] : @""];
    [alert setAlertStyle:NSAlertStyleInformational];
    [alert runModal];
    [alert release];
}

int macosx_yesno(const char *title, const char *message) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    [alert setMessageText:title ? [NSString stringWithUTF8String:title] : @""];
    [alert setInformativeText:message ? [NSString stringWithUTF8String:message] : @""];
    [alert setAlertStyle:NSAlertStyleInformational];
    const NSModalResponse response = [alert runModal];
    [alert release];
    return response == NSAlertFirstButtonReturn ? 1 : 0;
}

int macosx_yesnocancel(const char *title, const char *message) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert setMessageText:title ? [NSString stringWithUTF8String:title] : @""];
    [alert setInformativeText:message ? [NSString stringWithUTF8String:message] : @""];
    [alert setAlertStyle:NSAlertStyleInformational];
    const NSModalResponse response = [alert runModal];
    [alert release];
    return response == NSAlertFirstButtonReturn
                   ? 1
                   : (response == NSAlertSecondButtonReturn ? 0 : -1);
}

#if DOSBOXMENU_TYPE == DOSBOXMENU_NSMENU /* Mac OS X NSMenu / NSMenuItem handle */

void *sdl_hax_nsMenuItemFromTag(void *nsMenu, unsigned int tag) {
	NSMenuItem *ns_item = [((NSMenu*)nsMenu) itemWithTag: tag];
	return (ns_item != nil) ? ns_item : NULL;
}

void sdl_hax_nsMenuItemUpdateFromItem(void *nsMenuItem, DOSBoxMenu::item &item) {
    if (item.has_changed()) {
        NSMenuItem *ns_item = (NSMenuItem*)nsMenuItem;

        [ns_item setEnabled:(item.is_enabled() ? YES : NO)];
        [ns_item setHidden:(item.is_hidden() ? YES : NO)];
        [ns_item setState:(item.is_checked() ? NSOnState : NSOffState)];

        const std::string &it = item.get_text();
        const std::string &st = item.get_shortcut_text();
        std::string ft;

        int cp = dos.loaded_codepage;
        InitCodePage();

        if (CodePageGuestToHostUTF8(tempstr,it.c_str()))
            ft += tempstr;
        else
            ft += it;

        NSMutableAttributedString *titleas;
        {
            NSString *title;
            title = [[NSString alloc] initWithUTF8String:ft.c_str()];
            titleas = [[NSMutableAttributedString alloc] initWithString:title];
            [title release];
        }

        if (!st.empty()) {
            ft = " [" + st + "]";

            {
                NSString *title;
                NSMutableAttributedString *as;
                title = [[NSString alloc] initWithUTF8String:ft.c_str()];
                as = [[NSMutableAttributedString alloc] initWithString:title attributes:@{
                    NSForegroundColorAttributeName: [NSColor linkColor]//FIXME: Got any better ideas?
                }];
                [titleas appendAttributedString:as];
                [title release];
                [as release];
            }
        }

        [ns_item setAttributedTitle:titleas];
        [titleas release];

        dos.loaded_codepage = cp;

        item.clear_changed();
    }
}

void* sdl_hax_nsMenuAlloc(const char *initWithText) {
	NSString *title;
    int cp = dos.loaded_codepage;
    InitCodePage();
    if (CodePageGuestToHostUTF8(tempstr,initWithText))
        title = [[NSString alloc] initWithUTF8String:tempstr];
    else
        title = [[NSString alloc] initWithString:[NSString stringWithFormat:@"%s",initWithText]];
    dos.loaded_codepage = cp;
	NSMenu *menu = [[NSMenu alloc] initWithTitle: title];
	[title release];
	[menu setAutoenablesItems:NO];
	return (void*)menu;
}

void sdl_hax_nsMenuRelease(void *nsMenu) {
	[((NSMenu*)nsMenu) release];
}

void sdl_hax_macosx_setmenu(void *nsMenu) {
	if (nsMenu != NULL) {
        /* switch to the menu object given */
		[NSApp setMainMenu:((NSMenu*)nsMenu)];
	}
	else {
#if !defined(C_SDL2)
		/* switch back to the menu SDL 1.x made */
		[NSApp setMainMenu:((NSMenu*)sdl1_hax_stock_macosx_menu())];
#endif
	}
}

void sdl_hax_nsMenuItemSetTag(void *nsMenuItem, unsigned int new_id) {
	[((NSMenuItem*)nsMenuItem) setTag:new_id];
}

void sdl_hax_nsMenuItemSetSubmenu(void *nsMenuItem,void *nsMenu) {
	[((NSMenuItem*)nsMenuItem) setSubmenu:((NSMenu*)nsMenu)];
}

void* sdl_hax_nsMenuItemAlloc(const char *initWithText) {
	NSString *title;
    int cp = dos.loaded_codepage;
    InitCodePage();
    if (CodePageGuestToHostUTF8(tempstr,initWithText))
        title = [[NSString alloc] initWithUTF8String:tempstr];
    else
        title = [[NSString alloc] initWithString:[NSString stringWithFormat:@"%s",initWithText]];
    dos.loaded_codepage = cp;
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: title action:@selector(DOSBoxXMenuAction:) keyEquivalent:@""];
	[title release];
	return (void*)item;
}

void sdl_hax_nsMenuAddItem(void *nsMenu,void *nsMenuItem) {
	[((NSMenu*)nsMenu) addItem:((NSMenuItem*)nsMenuItem)];
}

void* sdl_hax_nsMenuAllocSeparator(void) {
    return (void *)[[NSMenuItem separatorItem] retain];
}

void sdl_hax_nsMenuItemRelease(void *nsMenuItem) {
	[((NSMenuItem*)nsMenuItem) release];
}

void sdl_hax_nsMenuAddApplicationMenu(void *nsMenu) {
#if defined(C_SDL2)
	/* make up an Application menu and stick it in first.
	   the caller should have passed us an empty menu */
	NSMenu *appMenu;
	NSMenuItem *appMenuItem;

	appMenu = [[NSMenu alloc] initWithTitle:@""];
	[appMenu addItemWithTitle:@"About DOSBox-X" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];

	appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
	[appMenuItem setSubmenu:appMenu];
	[((NSMenu*)nsMenu) addItem:appMenuItem];
	[appMenuItem release];
	[appMenu release];
#else
    /* Re-use the application menu from SDL1 */
    sdl1_hax_stock_macosx_menu_additem((NSMenu*)nsMenu);
#endif
}

static DOSBoxMenu *altMenu = NULL;

void menu_macosx_set_menuobj(DOSBoxMenu *new_altMenu) {
    if (new_altMenu != NULL && new_altMenu != &mainMenu)
        altMenu = new_altMenu;
    else
        altMenu = NULL;
}

@implementation NSApplication (DOSBoxX)
- (void)DOSBoxXMenuAction:(id)sender
{
    if (altMenu != NULL) {
        altMenu->mainMenuAction([sender tag]);
    }
    else {
        if ((is_paused && pause_menu_item_tag != [sender tag]) || MAPPER_IsRunning() || GUI_IsRunning()) return;
        /* sorry! */
        mainMenu.mainMenuAction([sender tag]);
    }
}

- (void)DOSBoxXMenuActionNewInstance:(id)sender
{
    (void)sender;
    if (is_paused || MAPPER_IsRunning() || GUI_IsRunning()) return;
    NewInstanceEvent(true);
}

- (void)DOSBoxXMenuActionMapper:(id)sender
{
    (void)sender;
    if (is_paused || MAPPER_IsRunning() || GUI_IsRunning()) return;
    MAPPER_Run(false);
}

- (void)DOSBoxXMenuActionCapMouse:(id)sender
{
    (void)sender;
    if (is_paused || MAPPER_IsRunning() || GUI_IsRunning()) return;
    MapperCapCursorToggle();
}

- (void)DOSBoxXMenuActionCfgGUI:(id)sender
{
    (void)sender;
    if (is_paused || MAPPER_IsRunning() || GUI_IsRunning()) return;
    GUI_Run(false);
}

- (void)DOSBoxXMenuActionPause:(id)sender
{
    (void)sender;

    if (MAPPER_IsRunning() || GUI_IsRunning()) return;

    if (is_paused) {
        PushDummySDL();
        unpause_now = true;
    }
    else {
        PauseDOSBox(true);
    }
}
@end
#endif
#endif
