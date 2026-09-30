#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#define SIMDUTF_SWIFT_NOEXCEPT noexcept
#else
#define SIMDUTF_SWIFT_NOEXCEPT
#endif

// All functions use counted buffers, preserve embedded nulls, and allocate no
// memory. UTF-16 units use native endianness. A zero count permits null pointers;
// otherwise buffers must cover the documented input and output capacities.
// Buffers are borrowed only for the duration of a call and are never retained.
// Conversion input and output buffers must not overlap.

// Requires UTF8 and UTF16. Replaces each unpaired UTF-16 surrogate with U+FFFD.
// The output must hold at least count * 3 bytes. Returns UTF-8 bytes written.
size_t simdutf_swift_utf16_to_utf8(const uint16_t* input, size_t count, uint8_t* output) SIMDUTF_SWIFT_NOEXCEPT;

// Requires UTF8 and UTF16. Input must be valid UTF-8. The output must hold at
// least count UTF-16 units. Returns the number of UTF-16 units written.
size_t simdutf_swift_valid_utf8_to_utf16(const uint8_t* input, size_t count, uint16_t* output) SIMDUTF_SWIFT_NOEXCEPT;

// Requires UTF16. Returns whether every surrogate belongs to a well-formed pair.
bool simdutf_swift_validate_utf16(const uint16_t* input, size_t count) SIMDUTF_SWIFT_NOEXCEPT;

// Requires UTF16. Copies count units, replacing unpaired surrogates with U+FFFD.
// The output must hold count units. Exact in-place repair (input == output) is
// allowed; otherwise the input and output buffers must not overlap.
void simdutf_swift_repair_utf16(const uint16_t* input, size_t count, uint16_t* output) SIMDUTF_SWIFT_NOEXCEPT;

#ifdef __cplusplus
}
#endif

#undef SIMDUTF_SWIFT_NOEXCEPT
