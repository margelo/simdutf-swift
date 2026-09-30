#pragma once
#include <stddef.h>
#include <stdint.h>
void benchmark_blackhole(const void *data, size_t bytes);
void benchmark_scalar(uint64_t value);
