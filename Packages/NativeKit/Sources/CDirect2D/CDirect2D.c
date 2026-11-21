#include "CDirect2D.h"
typedef int CDirect2D_empty_translation_unit;

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "ole32.lib")

int d2d_shim_version(void) { return 1; }
#endif
