#pragma once

#include <cstdint>

bool InitCodePage(void);
bool isDBCSCP(void);
bool isSupportedCP(int codepage);

bool CodePageHostToGuestUTF8(char *dst, const char *src);
bool CodePageGuestToHostUTF8(char *dst, const char *src);
bool CodePageHostToGuestUTF16(char *dst, const uint16_t *src);
bool CodePageGuestToHostUTF16(uint16_t *dst, const char *src);
