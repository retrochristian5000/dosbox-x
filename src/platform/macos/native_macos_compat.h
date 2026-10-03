#pragma once

#define SDL_MAIN_HANDLED 1

/*
 * Native macOS host shim.
 *
 * DOSBox-X still has SDL-shaped host data structures in long-lived code.
 * The native macOS build keeps those compile-time types for now, but maps
 * library entry points to DOSBoxMac_* so the executable does not link to or
 * resolve SDL2 at runtime.  The explicit build-macos-sdl2 backend bypasses
 * this header and retains the legacy SDL2 implementation.
 */

/* Core/error/version */
#define SDL_Init                        DOSBoxMac_Init
#define SDL_InitSubSystem               DOSBoxMac_InitSubSystem
#define SDL_QuitSubSystem               DOSBoxMac_QuitSubSystem
#define SDL_Quit                        DOSBoxMac_Quit
#define SDL_GetError                    DOSBoxMac_GetError
#define SDL_SetError                    DOSBoxMac_SetError
#define SDL_ClearError                  DOSBoxMac_ClearError
#define SDL_Error                       DOSBoxMac_Error
#define SDL_GetVersion                  DOSBoxMac_GetVersion
#define SDL_GetCurrentVideoDriver       DOSBoxMac_GetCurrentVideoDriver
#define SDL_GetCurrentAudioDriver       DOSBoxMac_GetCurrentAudioDriver

/* Timer */
#define SDL_GetTicks                    DOSBoxMac_GetTicks
#define SDL_Delay                       DOSBoxMac_Delay

/* Window/display */
#define SDL_CreateWindow                DOSBoxMac_CreateWindow
#define SDL_DestroyWindow               DOSBoxMac_DestroyWindow
#define SDL_GetWindowFlags              DOSBoxMac_GetWindowFlags
#define SDL_SetWindowTitle              DOSBoxMac_SetWindowTitle
#define SDL_SetWindowPosition           DOSBoxMac_SetWindowPosition
#define SDL_GetWindowPosition           DOSBoxMac_GetWindowPosition
#define SDL_SetWindowSize               DOSBoxMac_SetWindowSize
#define SDL_GetWindowSize               DOSBoxMac_GetWindowSize
#define SDL_SetWindowResizable          DOSBoxMac_SetWindowResizable
#define SDL_MaximizeWindow              DOSBoxMac_MaximizeWindow
#define SDL_SetWindowFullscreen         DOSBoxMac_SetWindowFullscreen
#define SDL_SetWindowOpacity            DOSBoxMac_SetWindowOpacity
#define SDL_SetWindowIcon               DOSBoxMac_SetWindowIcon
#define SDL_GetWindowSurface            DOSBoxMac_GetWindowSurface
#define SDL_UpdateWindowSurface         DOSBoxMac_UpdateWindowSurface
#define SDL_UpdateWindowSurfaceRects    DOSBoxMac_UpdateWindowSurfaceRects
#define SDL_GetWindowPixelFormat        DOSBoxMac_GetWindowPixelFormat
#define SDL_SetWindowDisplayMode        DOSBoxMac_SetWindowDisplayMode
#define SDL_GetWindowDisplayMode        DOSBoxMac_GetWindowDisplayMode
#define SDL_GetDesktopDisplayMode       DOSBoxMac_GetDesktopDisplayMode
#define SDL_GetCurrentDisplayMode       DOSBoxMac_GetCurrentDisplayMode
#define SDL_GetDisplayBounds            DOSBoxMac_GetDisplayBounds
#define SDL_GetNumVideoDisplays         DOSBoxMac_GetNumVideoDisplays
#define SDL_SetWindowKeyboardGrab       DOSBoxMac_SetWindowKeyboardGrab
#define SDL_GetWindowKeyboardGrab       DOSBoxMac_GetWindowKeyboardGrab
#define SDL_GetWindowWMInfo             DOSBoxMac_GetWindowWMInfo
#define SDL_ShowCursor                  DOSBoxMac_ShowCursor
#define SDL_SetRelativeMouseMode        DOSBoxMac_SetRelativeMouseMode

/* Renderer objects referenced by SDL2-era window teardown. */
#define SDL_DestroyRenderer             DOSBoxMac_DestroyRenderer
#define SDL_DestroyTexture              DOSBoxMac_DestroyTexture

/* Events/input */
#define SDL_PumpEvents                  DOSBoxMac_PumpEvents
#define SDL_PollEvent                   DOSBoxMac_PollEvent
#define SDL_WaitEvent                   DOSBoxMac_WaitEvent
#define SDL_PushEvent                   DOSBoxMac_PushEvent
#define SDL_PeepEvents                  DOSBoxMac_PeepEvents
#define SDL_EventState                  DOSBoxMac_EventState
#define SDL_GetModState                 DOSBoxMac_GetModState
#define SDL_GetKeyName                  DOSBoxMac_GetKeyName
#define SDL_GetScancodeName             DOSBoxMac_GetScancodeName
#define SDL_StartTextInput              DOSBoxMac_StartTextInput
#define SDL_StopTextInput               DOSBoxMac_StopTextInput
#define SDL_SetTextInputRect            DOSBoxMac_SetTextInputRect
#define SDL_SetHint                     DOSBoxMac_SetHint
#define SDL_SetHintWithPriority         DOSBoxMac_SetHintWithPriority

/* Software surfaces/pixels */
#define SDL_CreateRGBSurface            DOSBoxMac_CreateRGBSurface
#define SDL_CreateRGBSurfaceFrom        DOSBoxMac_CreateRGBSurfaceFrom
#define SDL_FreeSurface                 DOSBoxMac_FreeSurface
#define SDL_LockSurface                 DOSBoxMac_LockSurface
#define SDL_UnlockSurface               DOSBoxMac_UnlockSurface
#define SDL_UpperBlit                   DOSBoxMac_UpperBlit
#define SDL_UpperBlitScaled             DOSBoxMac_UpperBlitScaled
#define SDL_FillRect                    DOSBoxMac_FillRect
#define SDL_MapRGB                      DOSBoxMac_MapRGB
#define SDL_AllocFormat                 DOSBoxMac_AllocFormat
#define SDL_FreeFormat                  DOSBoxMac_FreeFormat
#define SDL_GetPixelFormatName          DOSBoxMac_GetPixelFormatName
#define SDL_AllocPalette                DOSBoxMac_AllocPalette
#define SDL_FreePalette                 DOSBoxMac_FreePalette
#define SDL_SetPaletteColors            DOSBoxMac_SetPaletteColors
#define SDL_SetSurfacePalette           DOSBoxMac_SetSurfacePalette
#define SDL_SetSurfaceAlphaMod          DOSBoxMac_SetSurfaceAlphaMod
#define SDL_SetSurfaceBlendMode         DOSBoxMac_SetSurfaceBlendMode
#define SDL_SetColorKey                 DOSBoxMac_SetColorKey

/* Audio -> AudioUnit/Core Audio */
#define SDL_OpenAudioDevice             DOSBoxMac_OpenAudioDevice
#define SDL_CloseAudioDevice            DOSBoxMac_CloseAudioDevice
#define SDL_PauseAudioDevice            DOSBoxMac_PauseAudioDevice
#define SDL_LockAudioDevice             DOSBoxMac_LockAudioDevice
#define SDL_UnlockAudioDevice           DOSBoxMac_UnlockAudioDevice

/* Controllers -> IOKit HID */
#define SDL_NumJoysticks                DOSBoxMac_NumJoysticks
#define SDL_JoystickOpen                DOSBoxMac_JoystickOpen
#define SDL_JoystickClose               DOSBoxMac_JoystickClose
#define SDL_JoystickUpdate              DOSBoxMac_JoystickUpdate
#define SDL_JoystickEventState          DOSBoxMac_JoystickEventState
#define SDL_JoystickGetAxis             DOSBoxMac_JoystickGetAxis
#define SDL_JoystickGetButton           DOSBoxMac_JoystickGetButton
#define SDL_JoystickGetHat              DOSBoxMac_JoystickGetHat
#define SDL_JoystickName                DOSBoxMac_JoystickName
#define SDL_JoystickNameForIndex        DOSBoxMac_JoystickNameForIndex
#define SDL_JoystickNumAxes             DOSBoxMac_JoystickNumAxes
#define SDL_JoystickNumButtons          DOSBoxMac_JoystickNumButtons
#define SDL_JoystickNumHats             DOSBoxMac_JoystickNumHats

/* Lightweight services used by in-tree SDL_sound/TTF code. */
#define SDL_CreateMutex                 DOSBoxMac_CreateMutex
#define SDL_DestroyMutex                DOSBoxMac_DestroyMutex
#define SDL_LockMutex                   DOSBoxMac_LockMutex
#define SDL_UnlockMutex                 DOSBoxMac_UnlockMutex
#define SDL_CreateSemaphore             DOSBoxMac_CreateSemaphore
#define SDL_DestroySemaphore            DOSBoxMac_DestroySemaphore
#define SDL_SemWait                     DOSBoxMac_SemWait
#define SDL_SemTryWait                  DOSBoxMac_SemTryWait
#define SDL_SemWaitTimeout              DOSBoxMac_SemWaitTimeout
#define SDL_SemPost                     DOSBoxMac_SemPost
#define SDL_SemValue                    DOSBoxMac_SemValue
#define SDL_CreateThread                DOSBoxMac_CreateThread
#define SDL_CreateThreadWithStackSize   DOSBoxMac_CreateThreadWithStackSize
#define SDL_WaitThread                  DOSBoxMac_WaitThread
#define SDL_DetachThread                DOSBoxMac_DetachThread
#define SDL_AllocRW                     DOSBoxMac_AllocRW
#define SDL_FreeRW                      DOSBoxMac_FreeRW
#define SDL_RWFromFile                  DOSBoxMac_RWFromFile
#define SDL_RWFromMem                   DOSBoxMac_RWFromMem
#define SDL_RWFromConstMem              DOSBoxMac_RWFromConstMem
#define SDL_RWsize                      DOSBoxMac_RWsize
#define SDL_RWseek                      DOSBoxMac_RWseek
#define SDL_RWtell                      DOSBoxMac_RWtell
#define SDL_RWread                      DOSBoxMac_RWread
#define SDL_RWwrite                     DOSBoxMac_RWwrite
#define SDL_RWclose                     DOSBoxMac_RWclose
#define SDL_ThreadID                    DOSBoxMac_ThreadID
#define SDL_getenv                      DOSBoxMac_getenv
#define SDL_setenv                      DOSBoxMac_setenv
