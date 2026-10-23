#include <stdint.h>
#include <inttypes.h>
#include <stddef.h>
#ifndef PRIi64
#error Missing newlib inttypes integration
#endif
_Static_assert(sizeof(uint32_t) == 4, "PSP uses 32-bit words");
_Static_assert(sizeof(void *) == 4, "PSP O32 ABI expected");
int gcc16_c_probe(uint32_t x) { return (int)__builtin_bswap32(x); }
