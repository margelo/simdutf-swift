#include "SimdUTFConfig.h"
#include "SimdUTFBridge.h"

#include <simdutf.h>

static_assert(sizeof(uint16_t) == sizeof(char16_t));
static_assert(alignof(uint16_t) == alignof(char16_t));

#if SIMDUTF_FEATURE_UTF8 && SIMDUTF_FEATURE_UTF16
size_t simdutf_swift_utf16_to_utf8(const uint16_t* input, size_t count, uint8_t* output) noexcept {
  if (count == 0) {
    return 0;
  }
  return simdutf::convert_utf16_to_utf8_with_replacement(reinterpret_cast<const char16_t*>(input), count, reinterpret_cast<char*>(output));
}

size_t simdutf_swift_valid_utf8_to_utf16(const uint8_t* input, size_t count, uint16_t* output) noexcept {
  if (count == 0) {
    return 0;
  }
  return simdutf::convert_valid_utf8_to_utf16(reinterpret_cast<const char*>(input), count, reinterpret_cast<char16_t*>(output));
}
#endif

#if SIMDUTF_FEATURE_UTF16
bool simdutf_swift_validate_utf16(const uint16_t* input, size_t count) noexcept {
  return count == 0 || simdutf::validate_utf16(reinterpret_cast<const char16_t*>(input), count);
}

void simdutf_swift_repair_utf16(const uint16_t* input, size_t count, uint16_t* output) noexcept {
  if (count != 0) {
    simdutf::to_well_formed_utf16(reinterpret_cast<const char16_t*>(input), count, reinterpret_cast<char16_t*>(output));
  }
}
#endif
