#pragma once

#if defined(MACOSX)

#include <string>

#include "menu.h"

class ScreenSizeInfo;

extern bool has_touch_bar_support;

bool macosx_detect_nstouchbar(void);
void macosx_init_touchbar(void);
void macosx_reload_touchbar(void);
void macosx_init_dock_menu(void);
void macosx_GetWindowDPI(ScreenSizeInfo &info);
void qz_set_match_monitor_cb(void);

#if defined(C_NATIVE_MACOS) && C_NATIVE_MACOS
/* AppKit object remains opaque outside Objective-C++ translation units. */
void *macosx_native_content_view(void);
#endif

std::string macosx_prompt_folder(const char *default_folder);
void macosx_alert(const char *title, const char *message);
int macosx_yesno(const char *title, const char *message);
int macosx_yesnocancel(const char *title, const char *message);

#if DOSBOXMENU_TYPE == DOSBOXMENU_NSMENU
void sdl_hax_nsMenuAddApplicationMenu(void *nsMenu);
void *sdl_hax_nsMenuItemFromTag(void *nsMenu, unsigned int tag);
void sdl_hax_nsMenuItemUpdateFromItem(void *nsMenuItem, DOSBoxMenu::item &item);
void sdl_hax_nsMenuItemSetTag(void *nsMenuItem, unsigned int id);
void sdl_hax_nsMenuItemSetSubmenu(void *nsMenuItem, void *nsMenu);
void sdl_hax_nsMenuAddItem(void *nsMenu, void *nsMenuItem);
void *sdl_hax_nsMenuAllocSeparator(void);
void *sdl_hax_nsMenuAlloc(const char *initWithText);
void sdl_hax_nsMenuRelease(void *nsMenu);
void *sdl_hax_nsMenuItemAlloc(const char *initWithText);
void sdl_hax_nsMenuItemRelease(void *nsMenuItem);
void sdl_hax_macosx_setmenu(void *nsMenu);
void menu_macosx_set_menuobj(DOSBoxMenu *new_altMenu);
#endif

#endif
