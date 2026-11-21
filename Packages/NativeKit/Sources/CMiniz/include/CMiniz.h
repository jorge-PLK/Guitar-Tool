// Cabecera paraguas del módulo CMiniz: miniz 3.0.2 (MIT, ver LICENSE), fuente vendorizada sin modificar.
// Sustituye a `NSData.decompressed(using: .zlib)` del framework Compression, que es deflate crudo (RFC 1951):
//   tinfl_decompress_mem_to_heap(src, srcLen, &outLen, 0)            → deflate crudo (lo de Apple `.zlib`)
//   tinfl_decompress_mem_to_heap(..., TINFL_FLAG_PARSE_ZLIB_HEADER)  → zlib con cabecera (RFC 1950)
// El resultado se libera con mz_free. Sin stdio, sin hora y sin ZIP; sin nombres compatibles con zlib, para
// no chocar con la zlib que enlaza Foundation.
#ifndef CMINIZ_H
#define CMINIZ_H
#ifndef MINIZ_NO_STDIO
#define MINIZ_NO_STDIO
#endif
#ifndef MINIZ_NO_TIME
#define MINIZ_NO_TIME
#endif
#ifndef MINIZ_NO_ARCHIVE_APIS
#define MINIZ_NO_ARCHIVE_APIS
#endif
#ifndef MINIZ_NO_ZLIB_COMPATIBLE_NAMES
#define MINIZ_NO_ZLIB_COMPATIBLE_NAMES
#endif
#include "miniz.h"
#endif
