#pragma once

#include <cstdint>

#include "dosbox.h"

#if defined(MACOSX) && C_METAL && defined(C_SDL2)

void metal_init();

void OUTPUT_Metal_Select();
Bitu OUTPUT_Metal_GetBestMode(Bitu flags);
bool OUTPUT_Metal_StartUpdate(uint8_t *&pixels, Bitu &pitch);
void OUTPUT_Metal_EndUpdate(const uint16_t *changedLines);
Bitu OUTPUT_Metal_SetSize(void);
void OUTPUT_Metal_Shutdown();
void OUTPUT_Metal_CheckSourceResolution();

#endif
