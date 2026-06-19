#pragma once

static const char* RCKMetalFieldKernelsSource = R"RCK_METAL(
#include <metal_stdlib>
using namespace metal;

static inline bool ge_p(ulong r0, ulong r1, ulong r2, ulong r3) {
  const ulong p0 = 0xFFFFFFFEFFFFFC2FUL;
  const ulong p1 = 0xFFFFFFFFFFFFFFFFUL;
  const ulong p2 = 0xFFFFFFFFFFFFFFFFUL;
  const ulong p3 = 0xFFFFFFFFFFFFFFFFUL;
  if (r3 != p3) return r3 > p3;
  if (r2 != p2) return r2 > p2;
  if (r1 != p1) return r1 > p1;
  return r0 >= p0;
}

static inline ulong add_carry(ulong carry, ulong a, ulong b, thread ulong& out) {
  ulong sum = a + b;
  ulong carry_ab = sum < a ? 1UL : 0UL;
  ulong with_carry = sum + carry;
  ulong carry_c = with_carry < sum ? 1UL : 0UL;
  out = with_carry;
  return (carry_ab || carry_c) ? 1UL : 0UL;
}

static inline ulong sub_borrow(ulong borrow, ulong a, ulong b, thread ulong& out) {
  ulong sub = b + borrow;
  out = a - sub;
  return ((a < b) || (borrow && a == b)) ? 1UL : 0UL;
}

static inline void sub_p(thread ulong& r0, thread ulong& r1, thread ulong& r2, thread ulong& r3) {
  const ulong p0 = 0xFFFFFFFEFFFFFC2FUL;
  const ulong p1 = 0xFFFFFFFFFFFFFFFFUL;
  const ulong p2 = 0xFFFFFFFFFFFFFFFFUL;
  const ulong p3 = 0xFFFFFFFFFFFFFFFFUL;
  ulong b = 0;
  b = sub_borrow(b, r0, p0, r0);
  b = sub_borrow(b, r1, p1, r1);
  b = sub_borrow(b, r2, p2, r2);
  sub_borrow(b, r3, p3, r3);
}

static inline void sub_p5(thread ulong* v) {
  const ulong p0 = 0xFFFFFFFEFFFFFC2FUL;
  const ulong p1 = 0xFFFFFFFFFFFFFFFFUL;
  const ulong p2 = 0xFFFFFFFFFFFFFFFFUL;
  const ulong p3 = 0xFFFFFFFFFFFFFFFFUL;
  ulong b = 0;
  b = sub_borrow(b, v[0], p0, v[0]);
  b = sub_borrow(b, v[1], p1, v[1]);
  b = sub_borrow(b, v[2], p2, v[2]);
  b = sub_borrow(b, v[3], p3, v[3]);
  sub_borrow(b, v[4], 0, v[4]);
}

static inline void mul64(ulong a, ulong b, thread ulong& lo, thread ulong& hi) {
  const ulong mask = 0xFFFFFFFFUL;
  ulong a0 = a & mask;
  ulong a1 = a >> 32;
  ulong b0 = b & mask;
  ulong b1 = b >> 32;
  ulong p0 = a0 * b0;
  ulong p1 = a0 * b1;
  ulong p2 = a1 * b0;
  ulong p3 = a1 * b1;
  ulong middle = (p0 >> 32) + (p1 & mask) + (p2 & mask);
  lo = (p0 & mask) | (middle << 32);
  hi = p3 + (p1 >> 32) + (p2 >> 32) + (middle >> 32);
}

static inline void mul256_by_64(thread ulong* input, ulong multiplier, thread ulong* result) {
  ulong h1 = 0, h2 = 0, lo = 0;
  mul64(input[0], multiplier, result[0], h1);
  mul64(input[1], multiplier, lo, h2);
  ulong carry = add_carry(0, lo, h1, result[1]);
  mul64(input[2], multiplier, lo, h1);
  carry = add_carry(carry, lo, h2, result[2]);
  mul64(input[3], multiplier, lo, h2);
  carry = add_carry(carry, lo, h1, result[3]);
  add_carry(carry, 0, h2, result[4]);
}

static inline void add320_to_256(thread ulong* in_out, thread ulong* val) {
  ulong carry = add_carry(0, in_out[0], val[0], in_out[0]);
  carry = add_carry(carry, in_out[1], val[1], in_out[1]);
  carry = add_carry(carry, in_out[2], val[2], in_out[2]);
  carry = add_carry(carry, in_out[3], val[3], in_out[3]);
  add_carry(carry, 0, val[4], in_out[4]);
}

static inline void field_mul_values(ulong a0, ulong a1, ulong a2, ulong a3,
                                    ulong b0, ulong b1, ulong b2, ulong b3,
                                    thread ulong& r0, thread ulong& r1,
                                    thread ulong& r2, thread ulong& r3) {
  const ulong p_rev = 0x00000001000003D1UL;
  thread ulong av[4] = {a0, a1, a2, a3};
  thread ulong bv[4] = {b0, b1, b2, b3};
  thread ulong buff[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  thread ulong tmp[5] = {0, 0, 0, 0, 0};
  thread ulong reduced[5] = {0, 0, 0, 0, 0};
  ulong high = 0, lo = 0;

  mul256_by_64(bv, av[0], buff);
  mul256_by_64(bv, av[1], tmp);
  add320_to_256(buff + 1, tmp);
  mul256_by_64(bv, av[2], tmp);
  add320_to_256(buff + 2, tmp);
  mul256_by_64(bv, av[3], tmp);
  add320_to_256(buff + 3, tmp);

  mul256_by_64(buff + 4, p_rev, tmp);
  ulong carry = add_carry(0, buff[0], tmp[0], buff[0]);
  carry = add_carry(carry, buff[1], tmp[1], buff[1]);
  carry = add_carry(carry, buff[2], tmp[2], buff[2]);
  tmp[4] += add_carry(carry, buff[3], tmp[3], buff[3]);

  mul64(tmp[4], p_rev, lo, high);
  carry = add_carry(0, buff[0], lo, reduced[0]);
  carry = add_carry(carry, buff[1], high, reduced[1]);
  carry = add_carry(carry, 0, buff[2], reduced[2]);
  reduced[4] = add_carry(carry, buff[3], 0, reduced[3]);

  while (reduced[4] || ge_p(reduced[0], reduced[1], reduced[2], reduced[3])) {
    sub_p5(reduced);
  }

  r0 = reduced[0];
  r1 = reduced[1];
  r2 = reduced[2];
  r3 = reduced[3];
}

kernel void field_add_mod_p(device const ulong* a [[buffer(0)]],
                            device const ulong* b [[buffer(1)]],
                            device ulong* out [[buffer(2)]],
                            constant uint& count [[buffer(3)]],
                            uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint base = id * 4;
  ulong a0 = a[base + 0], a1 = a[base + 1], a2 = a[base + 2], a3 = a[base + 3];
  ulong b0 = b[base + 0], b1 = b[base + 1], b2 = b[base + 2], b3 = b[base + 3];
  ulong r0 = a0 + b0;
  ulong c = r0 < a0 ? 1UL : 0UL;
  ulong t = a1 + b1; ulong c1 = t < a1 ? 1UL : 0UL; ulong r1 = t + c; c = (c1 || (r1 < t)) ? 1UL : 0UL;
  t = a2 + b2; c1 = t < a2 ? 1UL : 0UL; ulong r2 = t + c; c = (c1 || (r2 < t)) ? 1UL : 0UL;
  t = a3 + b3; c1 = t < a3 ? 1UL : 0UL; ulong r3 = t + c; c = (c1 || (r3 < t)) ? 1UL : 0UL;
  if (c || ge_p(r0, r1, r2, r3)) sub_p(r0, r1, r2, r3);
  out[base + 0] = r0; out[base + 1] = r1; out[base + 2] = r2; out[base + 3] = r3;
}

kernel void field_mul_mod_p(device const ulong* a [[buffer(0)]],
                            device const ulong* b [[buffer(1)]],
                            device ulong* out [[buffer(2)]],
                            constant uint& count [[buffer(3)]],
                            uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint base = id * 4;
  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  field_mul_values(a[base + 0], a[base + 1], a[base + 2], a[base + 3],
                   b[base + 0], b[base + 1], b[base + 2], b[base + 3],
                   r0, r1, r2, r3);
  out[base + 0] = r0; out[base + 1] = r1; out[base + 2] = r2; out[base + 3] = r3;
}
)RCK_METAL";
