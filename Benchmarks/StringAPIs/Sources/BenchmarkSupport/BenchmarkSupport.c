#include "BenchmarkSupport.h"

// Compiled separately without LTO. Swift must materialize all output and cannot
// hoist work past this opaque call. The sink does not scan or retain the buffer.
__attribute__((noinline)) void benchmark_blackhole(const void *data, size_t bytes) {
  __asm__ __volatile__("" : : "r"(data), "r"(bytes) : "memory");
}
__attribute__((noinline)) void benchmark_scalar(uint64_t value) {
  __asm__ __volatile__("" : : "r"(value) : "memory");
}
