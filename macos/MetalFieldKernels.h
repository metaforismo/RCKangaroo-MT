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

static inline void add_p(thread ulong& r0, thread ulong& r1, thread ulong& r2, thread ulong& r3) {
  const ulong p0 = 0xFFFFFFFEFFFFFC2FUL;
  const ulong p1 = 0xFFFFFFFFFFFFFFFFUL;
  const ulong p2 = 0xFFFFFFFFFFFFFFFFUL;
  const ulong p3 = 0xFFFFFFFFFFFFFFFFUL;
  ulong c = 0;
  c = add_carry(c, r0, p0, r0);
  c = add_carry(c, r1, p1, r1);
  c = add_carry(c, r2, p2, r2);
  add_carry(c, r3, p3, r3);
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

static inline void add128_to_512(thread ulong* in_out, uint offset, ulong lo, ulong hi) {
  ulong carry = add_carry(0, in_out[offset], lo, in_out[offset]);
  carry = add_carry(carry, in_out[offset + 1], hi, in_out[offset + 1]);
  for (uint i = offset + 2; carry && i < 8; i++) {
    carry = add_carry(0, in_out[i], carry, in_out[i]);
  }
}

static inline void add_mul64_to_512(thread ulong* in_out, uint offset, ulong a, ulong b) {
  ulong lo = 0, hi = 0;
  mul64(a, b, lo, hi);
  add128_to_512(in_out, offset, lo, hi);
}

static inline void add_double_mul64_to_512(thread ulong* in_out, uint offset, ulong a, ulong b) {
  ulong lo = 0, hi = 0;
  mul64(a, b, lo, hi);
  add128_to_512(in_out, offset, lo, hi);
  add128_to_512(in_out, offset, lo, hi);
}

static inline void reduce512_mod_p(thread ulong* buff,
                                   thread ulong& r0, thread ulong& r1,
                                   thread ulong& r2, thread ulong& r3) {
  const ulong p_rev = 0x00000001000003D1UL;
  thread ulong tmp[5] = {0, 0, 0, 0, 0};
  thread ulong reduced[5] = {0, 0, 0, 0, 0};
  ulong high = 0, lo = 0;

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

static inline void field_mul_values(ulong a0, ulong a1, ulong a2, ulong a3,
                                    ulong b0, ulong b1, ulong b2, ulong b3,
                                    thread ulong& r0, thread ulong& r1,
                                    thread ulong& r2, thread ulong& r3) {
  thread ulong av[4] = {a0, a1, a2, a3};
  thread ulong bv[4] = {b0, b1, b2, b3};
  thread ulong buff[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  thread ulong tmp[5] = {0, 0, 0, 0, 0};

  mul256_by_64(bv, av[0], buff);
  mul256_by_64(bv, av[1], tmp);
  add320_to_256(buff + 1, tmp);
  mul256_by_64(bv, av[2], tmp);
  add320_to_256(buff + 2, tmp);
  mul256_by_64(bv, av[3], tmp);
  add320_to_256(buff + 3, tmp);

  reduce512_mod_p(buff, r0, r1, r2, r3);
}

static inline void field_square_values(ulong a0, ulong a1, ulong a2, ulong a3,
                                       thread ulong& r0, thread ulong& r1,
                                       thread ulong& r2, thread ulong& r3) {
  thread ulong buff[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  add_mul64_to_512(buff, 0, a0, a0);
  add_double_mul64_to_512(buff, 1, a0, a1);
  add_double_mul64_to_512(buff, 2, a0, a2);
  add_double_mul64_to_512(buff, 3, a0, a3);
  add_mul64_to_512(buff, 2, a1, a1);
  add_double_mul64_to_512(buff, 3, a1, a2);
  add_double_mul64_to_512(buff, 4, a1, a3);
  add_mul64_to_512(buff, 4, a2, a2);
  add_double_mul64_to_512(buff, 5, a2, a3);
  add_mul64_to_512(buff, 6, a3, a3);
  reduce512_mod_p(buff, r0, r1, r2, r3);
}

static inline bool field_is_zero(ulong a0, ulong a1, ulong a2, ulong a3) {
  return (a0 | a1 | a2 | a3) == 0;
}

static inline void field_add_values(ulong a0, ulong a1, ulong a2, ulong a3,
                                    ulong b0, ulong b1, ulong b2, ulong b3,
                                    thread ulong& r0, thread ulong& r1,
                                    thread ulong& r2, thread ulong& r3) {
  r0 = a0 + b0;
  ulong c = r0 < a0 ? 1UL : 0UL;
  ulong t = a1 + b1; ulong c1 = t < a1 ? 1UL : 0UL; r1 = t + c; c = (c1 || (r1 < t)) ? 1UL : 0UL;
  t = a2 + b2; c1 = t < a2 ? 1UL : 0UL; r2 = t + c; c = (c1 || (r2 < t)) ? 1UL : 0UL;
  t = a3 + b3; c1 = t < a3 ? 1UL : 0UL; r3 = t + c; c = (c1 || (r3 < t)) ? 1UL : 0UL;
  if (c || ge_p(r0, r1, r2, r3)) sub_p(r0, r1, r2, r3);
}

static inline void field_sub_values(ulong a0, ulong a1, ulong a2, ulong a3,
                                    ulong b0, ulong b1, ulong b2, ulong b3,
                                    thread ulong& r0, thread ulong& r1,
                                    thread ulong& r2, thread ulong& r3) {
  ulong borrow = 0;
  borrow = sub_borrow(borrow, a0, b0, r0);
  borrow = sub_borrow(borrow, a1, b1, r1);
  borrow = sub_borrow(borrow, a2, b2, r2);
  borrow = sub_borrow(borrow, a3, b3, r3);
  if (borrow) add_p(r0, r1, r2, r3);
}

static inline void field_double_values(ulong a0, ulong a1, ulong a2, ulong a3,
                                       thread ulong& r0, thread ulong& r1,
                                       thread ulong& r2, thread ulong& r3) {
  r0 = a0 + a0;
  ulong c = r0 < a0 ? 1UL : 0UL;
  ulong t = a1 + a1; ulong c1 = t < a1 ? 1UL : 0UL; r1 = t + c; c = (c1 || (r1 < t)) ? 1UL : 0UL;
  t = a2 + a2; c1 = t < a2 ? 1UL : 0UL; r2 = t + c; c = (c1 || (r2 < t)) ? 1UL : 0UL;
  t = a3 + a3; c1 = t < a3 ? 1UL : 0UL; r3 = t + c; c = (c1 || (r3 < t)) ? 1UL : 0UL;
  if (c || ge_p(r0, r1, r2, r3)) sub_p(r0, r1, r2, r3);
}

static inline void store_jacobian(device ulong* out_xyz,
                                  uint base,
                                  ulong x0, ulong x1, ulong x2, ulong x3,
                                  ulong y0, ulong y1, ulong y2, ulong y3,
                                  ulong z0, ulong z1, ulong z2, ulong z3,
                                  device uint* out_infinity,
                                  uint id,
                                  uint infinity) {
  out_xyz[base + 0] = x0; out_xyz[base + 1] = x1; out_xyz[base + 2] = x2; out_xyz[base + 3] = x3;
  out_xyz[base + 4] = y0; out_xyz[base + 5] = y1; out_xyz[base + 6] = y2; out_xyz[base + 7] = y3;
  out_xyz[base + 8] = z0; out_xyz[base + 9] = z1; out_xyz[base + 10] = z2; out_xyz[base + 11] = z3;
  out_infinity[id] = infinity;
}

static inline void store_jacobian_xyz_only(device ulong* out_xyz,
                                           uint base,
                                           ulong x0, ulong x1, ulong x2, ulong x3,
                                           ulong y0, ulong y1, ulong y2, ulong y3,
                                           ulong z0, ulong z1, ulong z2, ulong z3) {
  out_xyz[base + 0] = x0; out_xyz[base + 1] = x1; out_xyz[base + 2] = x2; out_xyz[base + 3] = x3;
  out_xyz[base + 4] = y0; out_xyz[base + 5] = y1; out_xyz[base + 6] = y2; out_xyz[base + 7] = y3;
  out_xyz[base + 8] = z0; out_xyz[base + 9] = z1; out_xyz[base + 10] = z2; out_xyz[base + 11] = z3;
}

static inline void jacobian_double_values(ulong x0, ulong x1, ulong x2, ulong x3,
                                          ulong y0, ulong y1, ulong y2, ulong y3,
                                          ulong z0, ulong z1, ulong z2, ulong z3,
                                          thread ulong& ox0, thread ulong& ox1,
                                          thread ulong& ox2, thread ulong& ox3,
                                          thread ulong& oy0, thread ulong& oy1,
                                          thread ulong& oy2, thread ulong& oy3,
                                          thread ulong& oz0, thread ulong& oz1,
                                          thread ulong& oz2, thread ulong& oz3,
                                          thread uint& infinity) {
  if (field_is_zero(y0, y1, y2, y3)) {
    ox0 = 0; ox1 = 0; ox2 = 0; ox3 = 0;
    oy0 = 0; oy1 = 0; oy2 = 0; oy3 = 0;
    oz0 = 0; oz1 = 0; oz2 = 0; oz3 = 0;
    infinity = 1;
    return;
  }

  ulong xx0 = 0, xx1 = 0, xx2 = 0, xx3 = 0;
  ulong yy0 = 0, yy1 = 0, yy2 = 0, yy3 = 0;
  ulong yyyy0 = 0, yyyy1 = 0, yyyy2 = 0, yyyy3 = 0;
  ulong xyy0 = 0, xyy1 = 0, xyy2 = 0, xyy3 = 0;
  ulong tmp0 = 0, tmp1 = 0, tmp2 = 0, tmp3 = 0;
  ulong s0 = 0, s1 = 0, s2 = 0, s3 = 0;
  ulong m0 = 0, m1 = 0, m2 = 0, m3 = 0;
  ulong t0 = 0, t1 = 0, t2 = 0, t3 = 0;
  ulong two_s0 = 0, two_s1 = 0, two_s2 = 0, two_s3 = 0;
  ulong eight0 = 0, eight1 = 0, eight2 = 0, eight3 = 0;
  ulong s_minus_t0 = 0, s_minus_t1 = 0, s_minus_t2 = 0, s_minus_t3 = 0;
  ulong ymul0 = 0, ymul1 = 0, ymul2 = 0, ymul3 = 0;
  ulong yz0 = 0, yz1 = 0, yz2 = 0, yz3 = 0;
  ulong zz0 = 0, zz1 = 0, zz2 = 0, zz3 = 0;

  field_square_values(x0, x1, x2, x3, xx0, xx1, xx2, xx3);
  field_square_values(y0, y1, y2, y3, yy0, yy1, yy2, yy3);
  field_square_values(yy0, yy1, yy2, yy3, yyyy0, yyyy1, yyyy2, yyyy3);
  field_add_values(x0, x1, x2, x3, yy0, yy1, yy2, yy3, xyy0, xyy1, xyy2, xyy3);
  field_square_values(xyy0, xyy1, xyy2, xyy3, tmp0, tmp1, tmp2, tmp3);
  field_sub_values(tmp0, tmp1, tmp2, tmp3, xx0, xx1, xx2, xx3, tmp0, tmp1, tmp2, tmp3);
  field_sub_values(tmp0, tmp1, tmp2, tmp3, yyyy0, yyyy1, yyyy2, yyyy3, tmp0, tmp1, tmp2, tmp3);
  field_double_values(tmp0, tmp1, tmp2, tmp3, s0, s1, s2, s3);
  field_double_values(xx0, xx1, xx2, xx3, m0, m1, m2, m3);
  field_add_values(m0, m1, m2, m3, xx0, xx1, xx2, xx3, m0, m1, m2, m3);
  field_square_values(m0, m1, m2, m3, t0, t1, t2, t3);
  field_double_values(s0, s1, s2, s3, two_s0, two_s1, two_s2, two_s3);
  field_sub_values(t0, t1, t2, t3, two_s0, two_s1, two_s2, two_s3, t0, t1, t2, t3);
  field_double_values(yyyy0, yyyy1, yyyy2, yyyy3, eight0, eight1, eight2, eight3);
  field_double_values(eight0, eight1, eight2, eight3, eight0, eight1, eight2, eight3);
  field_double_values(eight0, eight1, eight2, eight3, eight0, eight1, eight2, eight3);
  field_sub_values(s0, s1, s2, s3, t0, t1, t2, t3, s_minus_t0, s_minus_t1, s_minus_t2, s_minus_t3);
  field_mul_values(m0, m1, m2, m3, s_minus_t0, s_minus_t1, s_minus_t2, s_minus_t3, ymul0, ymul1, ymul2, ymul3);
  field_sub_values(ymul0, ymul1, ymul2, ymul3, eight0, eight1, eight2, eight3, oy0, oy1, oy2, oy3);
  field_add_values(y0, y1, y2, y3, z0, z1, z2, z3, yz0, yz1, yz2, yz3);
  field_square_values(yz0, yz1, yz2, yz3, oz0, oz1, oz2, oz3);
  field_square_values(z0, z1, z2, z3, zz0, zz1, zz2, zz3);
  field_sub_values(oz0, oz1, oz2, oz3, yy0, yy1, yy2, yy3, oz0, oz1, oz2, oz3);
  field_sub_values(oz0, oz1, oz2, oz3, zz0, zz1, zz2, zz3, oz0, oz1, oz2, oz3);
  ox0 = t0; ox1 = t1; ox2 = t2; ox3 = t3;
  infinity = 0;
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

kernel void field_sub_mod_p(device const ulong* a [[buffer(0)]],
                            device const ulong* b [[buffer(1)]],
                            device ulong* out [[buffer(2)]],
                            constant uint& count [[buffer(3)]],
                            uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint base = id * 4;
  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  ulong borrow = 0;
  borrow = sub_borrow(borrow, a[base + 0], b[base + 0], r0);
  borrow = sub_borrow(borrow, a[base + 1], b[base + 1], r1);
  borrow = sub_borrow(borrow, a[base + 2], b[base + 2], r2);
  borrow = sub_borrow(borrow, a[base + 3], b[base + 3], r3);
  if (borrow) add_p(r0, r1, r2, r3);
  out[base + 0] = r0; out[base + 1] = r1; out[base + 2] = r2; out[base + 3] = r3;
}

kernel void field_double_mod_p(device const ulong* a [[buffer(0)]],
                               device const ulong* b [[buffer(1)]],
                               device ulong* out [[buffer(2)]],
                               constant uint& count [[buffer(3)]],
                               uint id [[thread_position_in_grid]]) {
  (void)b;
  if (id >= count) return;
  uint base = id * 4;
  ulong a0 = a[base + 0], a1 = a[base + 1], a2 = a[base + 2], a3 = a[base + 3];
  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  field_double_values(a0, a1, a2, a3, r0, r1, r2, r3);
  out[base + 0] = r0; out[base + 1] = r1; out[base + 2] = r2; out[base + 3] = r3;
}

kernel void field_mul4_mod_p(device const ulong* a [[buffer(0)]],
                             device const ulong* b [[buffer(1)]],
                             device ulong* out [[buffer(2)]],
                             constant uint& count [[buffer(3)]],
                             uint id [[thread_position_in_grid]]) {
  (void)b;
  if (id >= count) return;
  uint base = id * 4;
  ulong d0 = 0, d1 = 0, d2 = 0, d3 = 0;
  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  field_double_values(a[base + 0], a[base + 1], a[base + 2], a[base + 3],
                      d0, d1, d2, d3);
  field_double_values(d0, d1, d2, d3, r0, r1, r2, r3);
  out[base + 0] = r0; out[base + 1] = r1; out[base + 2] = r2; out[base + 3] = r3;
}

kernel void field_neg_mod_p(device const ulong* a [[buffer(0)]],
                            device const ulong* b [[buffer(1)]],
                            device ulong* out [[buffer(2)]],
                            constant uint& count [[buffer(3)]],
                            uint id [[thread_position_in_grid]]) {
  (void)b;
  if (id >= count) return;
  uint base = id * 4;
  ulong a0 = a[base + 0], a1 = a[base + 1], a2 = a[base + 2], a3 = a[base + 3];
  if ((a0 | a1 | a2 | a3) == 0) {
    out[base + 0] = 0; out[base + 1] = 0; out[base + 2] = 0; out[base + 3] = 0;
    return;
  }

  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  ulong borrow = 0;
  borrow = sub_borrow(borrow, 0xFFFFFFFEFFFFFC2FUL, a0, r0);
  borrow = sub_borrow(borrow, 0xFFFFFFFFFFFFFFFFUL, a1, r1);
  borrow = sub_borrow(borrow, 0xFFFFFFFFFFFFFFFFUL, a2, r2);
  sub_borrow(borrow, 0xFFFFFFFFFFFFFFFFUL, a3, r3);
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

kernel void field_square_mod_p(device const ulong* a [[buffer(0)]],
                               device const ulong* b [[buffer(1)]],
                               device ulong* out [[buffer(2)]],
                               constant uint& count [[buffer(3)]],
                               uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint base = id * 4;
  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  field_square_values(a[base + 0], a[base + 1], a[base + 2], a[base + 3],
                      r0, r1, r2, r3);
  out[base + 0] = r0; out[base + 1] = r1; out[base + 2] = r2; out[base + 3] = r3;
}

struct JacobianValue {
  ulong x0, x1, x2, x3;
  ulong y0, y1, y2, y3;
  ulong z0, z1, z2, z3;
  uint inf;
};

struct AffineJumpValue {
  ulong x0, x1, x2, x3;
  ulong y0, y1, y2, y3;
};

struct XyzzValue {
  ulong x0, x1, x2, x3;
  ulong y0, y1, y2, y3;
  ulong zz0, zz1, zz2, zz3;
  ulong zzz0, zzz1, zzz2, zzz3;
  uint inf;
};

kernel void field_square_mul_mod_p(device const ulong* a [[buffer(0)]],
                                   device const ulong* b [[buffer(1)]],
                                   device ulong* out [[buffer(2)]],
                                   constant uint& count [[buffer(3)]],
                                   uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint base = id * 4;
  ulong s0 = 0, s1 = 0, s2 = 0, s3 = 0;
  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  field_square_values(a[base + 0], a[base + 1], a[base + 2], a[base + 3],
                      s0, s1, s2, s3);
  field_mul_values(s0, s1, s2, s3,
                   b[base + 0], b[base + 1], b[base + 2], b[base + 3],
                   r0, r1, r2, r3);
  out[base + 0] = r0; out[base + 1] = r1; out[base + 2] = r2; out[base + 3] = r3;
}

static inline JacobianValue jacobian_add_affine_finite_values(ulong x0, ulong x1, ulong x2, ulong x3,
                                                              ulong y0, ulong y1, ulong y2, ulong y3,
                                                              ulong z0, ulong z1, ulong z2, ulong z3,
                                                              ulong qx0, ulong qx1, ulong qx2, ulong qx3,
                                                              ulong qy0, ulong qy1, ulong qy2, ulong qy3) {
  JacobianValue out;
  ulong z20 = 0, z21 = 0, z22 = 0, z23 = 0;
  ulong z30 = 0, z31 = 0, z32 = 0, z33 = 0;
  ulong u20 = 0, u21 = 0, u22 = 0, u23 = 0;
  ulong s20 = 0, s21 = 0, s22 = 0, s23 = 0;
  ulong h0 = 0, h1 = 0, h2 = 0, h3 = 0;
  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  field_square_values(z0, z1, z2, z3, z20, z21, z22, z23);
  field_mul_values(z20, z21, z22, z23, z0, z1, z2, z3, z30, z31, z32, z33);
  field_mul_values(qx0, qx1, qx2, qx3, z20, z21, z22, z23, u20, u21, u22, u23);
  field_mul_values(qy0, qy1, qy2, qy3, z30, z31, z32, z33, s20, s21, s22, s23);
  field_sub_values(u20, u21, u22, u23, x0, x1, x2, x3, h0, h1, h2, h3);
  field_sub_values(s20, s21, s22, s23, y0, y1, y2, y3, r0, r1, r2, r3);

  if (field_is_zero(h0, h1, h2, h3)) {
    ulong ox0 = 0, ox1 = 0, ox2 = 0, ox3 = 0;
    ulong oy0 = 0, oy1 = 0, oy2 = 0, oy3 = 0;
    ulong oz0 = 0, oz1 = 0, oz2 = 0, oz3 = 0;
    uint infinity = 0;
    if (field_is_zero(r0, r1, r2, r3)) {
      jacobian_double_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                             ox0, ox1, ox2, ox3, oy0, oy1, oy2, oy3,
                             oz0, oz1, oz2, oz3, infinity);
      out.x0 = ox0; out.x1 = ox1; out.x2 = ox2; out.x3 = ox3;
      out.y0 = oy0; out.y1 = oy1; out.y2 = oy2; out.y3 = oy3;
      out.z0 = oz0; out.z1 = oz1; out.z2 = oz2; out.z3 = oz3;
      out.inf = infinity;
      return out;
    }
    out.x0 = 0; out.x1 = 0; out.x2 = 0; out.x3 = 0;
    out.y0 = 0; out.y1 = 0; out.y2 = 0; out.y3 = 0;
    out.z0 = 0; out.z1 = 0; out.z2 = 0; out.z3 = 0;
    out.inf = 1;
    return out;
  }

  ulong hh0 = 0, hh1 = 0, hh2 = 0, hh3 = 0;
  ulong hhh0 = 0, hhh1 = 0, hhh2 = 0, hhh3 = 0;
  ulong v0 = 0, v1 = 0, v2 = 0, v3 = 0;
  ulong x30 = 0, x31 = 0, x32 = 0, x33 = 0;
  ulong two_v0 = 0, two_v1 = 0, two_v2 = 0, two_v3 = 0;
  ulong v_minus_x0 = 0, v_minus_x1 = 0, v_minus_x2 = 0, v_minus_x3 = 0;
  ulong y_mul_hhh0 = 0, y_mul_hhh1 = 0, y_mul_hhh2 = 0, y_mul_hhh3 = 0;
  ulong y30 = 0, y31 = 0, y32 = 0, y33 = 0;
  ulong z_out0 = 0, z_out1 = 0, z_out2 = 0, z_out3 = 0;

  field_square_values(h0, h1, h2, h3, hh0, hh1, hh2, hh3);
  field_mul_values(hh0, hh1, hh2, hh3, h0, h1, h2, h3, hhh0, hhh1, hhh2, hhh3);
  field_mul_values(x0, x1, x2, x3, hh0, hh1, hh2, hh3, v0, v1, v2, v3);
  field_square_values(r0, r1, r2, r3, x30, x31, x32, x33);
  field_sub_values(x30, x31, x32, x33, hhh0, hhh1, hhh2, hhh3, x30, x31, x32, x33);
  field_double_values(v0, v1, v2, v3, two_v0, two_v1, two_v2, two_v3);
  field_sub_values(x30, x31, x32, x33, two_v0, two_v1, two_v2, two_v3, x30, x31, x32, x33);
  field_sub_values(v0, v1, v2, v3, x30, x31, x32, x33, v_minus_x0, v_minus_x1, v_minus_x2, v_minus_x3);
  field_mul_values(r0, r1, r2, r3, v_minus_x0, v_minus_x1, v_minus_x2, v_minus_x3, y30, y31, y32, y33);
  field_mul_values(y0, y1, y2, y3, hhh0, hhh1, hhh2, hhh3, y_mul_hhh0, y_mul_hhh1, y_mul_hhh2, y_mul_hhh3);
  field_sub_values(y30, y31, y32, y33, y_mul_hhh0, y_mul_hhh1, y_mul_hhh2, y_mul_hhh3, y30, y31, y32, y33);
  field_mul_values(z0, z1, z2, z3, h0, h1, h2, h3, z_out0, z_out1, z_out2, z_out3);
  out.x0 = x30; out.x1 = x31; out.x2 = x32; out.x3 = x33;
  out.y0 = y30; out.y1 = y31; out.y2 = y32; out.y3 = y33;
  out.z0 = z_out0; out.z1 = z_out1; out.z2 = z_out2; out.z3 = z_out3;
  out.inf = 0;
  return out;
}

static inline JacobianValue jacobian_add_affine_values(ulong x0, ulong x1, ulong x2, ulong x3,
                                                       ulong y0, ulong y1, ulong y2, ulong y3,
                                                       ulong z0, ulong z1, ulong z2, ulong z3,
                                                       uint p_infinity,
                                                       ulong qx0, ulong qx1, ulong qx2, ulong qx3,
                                                       ulong qy0, ulong qy1, ulong qy2, ulong qy3) {
  if (p_infinity) {
    JacobianValue out;
    out.x0 = qx0; out.x1 = qx1; out.x2 = qx2; out.x3 = qx3;
    out.y0 = qy0; out.y1 = qy1; out.y2 = qy2; out.y3 = qy3;
    out.z0 = 1; out.z1 = 0; out.z2 = 0; out.z3 = 0;
    out.inf = 0;
    return out;
  }
  return jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3,
                                           z0, z1, z2, z3,
                                           qx0, qx1, qx2, qx3,
                                           qy0, qy1, qy2, qy3);
}

static inline XyzzValue jacobian_double_xyzz_values(ulong x0, ulong x1, ulong x2, ulong x3,
                                                    ulong y0, ulong y1, ulong y2, ulong y3,
                                                    ulong zz0, ulong zz1, ulong zz2, ulong zz3,
                                                    ulong zzz0, ulong zzz1, ulong zzz2, ulong zzz3) {
  XyzzValue out;
  if (field_is_zero(y0, y1, y2, y3)) {
    out.x0 = 0; out.x1 = 0; out.x2 = 0; out.x3 = 0;
    out.y0 = 0; out.y1 = 0; out.y2 = 0; out.y3 = 0;
    out.zz0 = 0; out.zz1 = 0; out.zz2 = 0; out.zz3 = 0;
    out.zzz0 = 0; out.zzz1 = 0; out.zzz2 = 0; out.zzz3 = 0;
    out.inf = 1;
    return out;
  }

  ulong xx0 = 0, xx1 = 0, xx2 = 0, xx3 = 0;
  ulong yy0 = 0, yy1 = 0, yy2 = 0, yy3 = 0;
  ulong yyyy0 = 0, yyyy1 = 0, yyyy2 = 0, yyyy3 = 0;
  ulong xyy0 = 0, xyy1 = 0, xyy2 = 0, xyy3 = 0;
  ulong tmp0 = 0, tmp1 = 0, tmp2 = 0, tmp3 = 0;
  ulong s0 = 0, s1 = 0, s2 = 0, s3 = 0;
  ulong m0 = 0, m1 = 0, m2 = 0, m3 = 0;
  ulong t0 = 0, t1 = 0, t2 = 0, t3 = 0;
  ulong two_s0 = 0, two_s1 = 0, two_s2 = 0, two_s3 = 0;
  ulong eight0 = 0, eight1 = 0, eight2 = 0, eight3 = 0;
  ulong s_minus_t0 = 0, s_minus_t1 = 0, s_minus_t2 = 0, s_minus_t3 = 0;
  ulong ymul0 = 0, ymul1 = 0, ymul2 = 0, ymul3 = 0;
  ulong four_yy0 = 0, four_yy1 = 0, four_yy2 = 0, four_yy3 = 0;
  ulong yyy0 = 0, yyy1 = 0, yyy2 = 0, yyy3 = 0;
  ulong eight_yyy0 = 0, eight_yyy1 = 0, eight_yyy2 = 0, eight_yyy3 = 0;

  field_square_values(x0, x1, x2, x3, xx0, xx1, xx2, xx3);
  field_square_values(y0, y1, y2, y3, yy0, yy1, yy2, yy3);
  field_square_values(yy0, yy1, yy2, yy3, yyyy0, yyyy1, yyyy2, yyyy3);
  field_add_values(x0, x1, x2, x3, yy0, yy1, yy2, yy3, xyy0, xyy1, xyy2, xyy3);
  field_square_values(xyy0, xyy1, xyy2, xyy3, tmp0, tmp1, tmp2, tmp3);
  field_sub_values(tmp0, tmp1, tmp2, tmp3, xx0, xx1, xx2, xx3, tmp0, tmp1, tmp2, tmp3);
  field_sub_values(tmp0, tmp1, tmp2, tmp3, yyyy0, yyyy1, yyyy2, yyyy3, tmp0, tmp1, tmp2, tmp3);
  field_double_values(tmp0, tmp1, tmp2, tmp3, s0, s1, s2, s3);
  field_double_values(xx0, xx1, xx2, xx3, m0, m1, m2, m3);
  field_add_values(m0, m1, m2, m3, xx0, xx1, xx2, xx3, m0, m1, m2, m3);
  field_square_values(m0, m1, m2, m3, t0, t1, t2, t3);
  field_double_values(s0, s1, s2, s3, two_s0, two_s1, two_s2, two_s3);
  field_sub_values(t0, t1, t2, t3, two_s0, two_s1, two_s2, two_s3, t0, t1, t2, t3);
  field_double_values(yyyy0, yyyy1, yyyy2, yyyy3, eight0, eight1, eight2, eight3);
  field_double_values(eight0, eight1, eight2, eight3, eight0, eight1, eight2, eight3);
  field_double_values(eight0, eight1, eight2, eight3, eight0, eight1, eight2, eight3);
  field_sub_values(s0, s1, s2, s3, t0, t1, t2, t3, s_minus_t0, s_minus_t1, s_minus_t2, s_minus_t3);
  field_mul_values(m0, m1, m2, m3, s_minus_t0, s_minus_t1, s_minus_t2, s_minus_t3, ymul0, ymul1, ymul2, ymul3);
  field_sub_values(ymul0, ymul1, ymul2, ymul3, eight0, eight1, eight2, eight3, out.y0, out.y1, out.y2, out.y3);
  field_double_values(yy0, yy1, yy2, yy3, four_yy0, four_yy1, four_yy2, four_yy3);
  field_double_values(four_yy0, four_yy1, four_yy2, four_yy3, four_yy0, four_yy1, four_yy2, four_yy3);
  field_mul_values(four_yy0, four_yy1, four_yy2, four_yy3, zz0, zz1, zz2, zz3, out.zz0, out.zz1, out.zz2, out.zz3);
  field_mul_values(yy0, yy1, yy2, yy3, y0, y1, y2, y3, yyy0, yyy1, yyy2, yyy3);
  field_double_values(yyy0, yyy1, yyy2, yyy3, eight_yyy0, eight_yyy1, eight_yyy2, eight_yyy3);
  field_double_values(eight_yyy0, eight_yyy1, eight_yyy2, eight_yyy3, eight_yyy0, eight_yyy1, eight_yyy2, eight_yyy3);
  field_double_values(eight_yyy0, eight_yyy1, eight_yyy2, eight_yyy3, eight_yyy0, eight_yyy1, eight_yyy2, eight_yyy3);
  field_mul_values(eight_yyy0, eight_yyy1, eight_yyy2, eight_yyy3, zzz0, zzz1, zzz2, zzz3, out.zzz0, out.zzz1, out.zzz2, out.zzz3);
  out.x0 = t0; out.x1 = t1; out.x2 = t2; out.x3 = t3;
  out.inf = 0;
  return out;
}

static inline XyzzValue jacobian_add_affine_xyzz_values(ulong x0, ulong x1, ulong x2, ulong x3,
                                                        ulong y0, ulong y1, ulong y2, ulong y3,
                                                        ulong zz0, ulong zz1, ulong zz2, ulong zz3,
                                                        ulong zzz0, ulong zzz1, ulong zzz2, ulong zzz3,
                                                        uint p_infinity,
                                                        ulong qx0, ulong qx1, ulong qx2, ulong qx3,
                                                        ulong qy0, ulong qy1, ulong qy2, ulong qy3) {
  XyzzValue out;
  if (p_infinity) {
    out.x0 = qx0; out.x1 = qx1; out.x2 = qx2; out.x3 = qx3;
    out.y0 = qy0; out.y1 = qy1; out.y2 = qy2; out.y3 = qy3;
    out.zz0 = 1; out.zz1 = 0; out.zz2 = 0; out.zz3 = 0;
    out.zzz0 = 1; out.zzz1 = 0; out.zzz2 = 0; out.zzz3 = 0;
    out.inf = 0;
    return out;
  }

  ulong u20 = 0, u21 = 0, u22 = 0, u23 = 0;
  ulong s20 = 0, s21 = 0, s22 = 0, s23 = 0;
  ulong h0 = 0, h1 = 0, h2 = 0, h3 = 0;
  ulong r0 = 0, r1 = 0, r2 = 0, r3 = 0;
  field_mul_values(qx0, qx1, qx2, qx3, zz0, zz1, zz2, zz3, u20, u21, u22, u23);
  field_mul_values(qy0, qy1, qy2, qy3, zzz0, zzz1, zzz2, zzz3, s20, s21, s22, s23);
  field_sub_values(u20, u21, u22, u23, x0, x1, x2, x3, h0, h1, h2, h3);
  field_sub_values(s20, s21, s22, s23, y0, y1, y2, y3, r0, r1, r2, r3);

  if (field_is_zero(h0, h1, h2, h3)) {
    if (field_is_zero(r0, r1, r2, r3))
      return jacobian_double_xyzz_values(x0, x1, x2, x3, y0, y1, y2, y3, zz0, zz1, zz2, zz3, zzz0, zzz1, zzz2, zzz3);
    out.x0 = 0; out.x1 = 0; out.x2 = 0; out.x3 = 0;
    out.y0 = 0; out.y1 = 0; out.y2 = 0; out.y3 = 0;
    out.zz0 = 0; out.zz1 = 0; out.zz2 = 0; out.zz3 = 0;
    out.zzz0 = 0; out.zzz1 = 0; out.zzz2 = 0; out.zzz3 = 0;
    out.inf = 1;
    return out;
  }

  ulong hh0 = 0, hh1 = 0, hh2 = 0, hh3 = 0;
  ulong hhh0 = 0, hhh1 = 0, hhh2 = 0, hhh3 = 0;
  ulong v0 = 0, v1 = 0, v2 = 0, v3 = 0;
  ulong x30 = 0, x31 = 0, x32 = 0, x33 = 0;
  ulong two_v0 = 0, two_v1 = 0, two_v2 = 0, two_v3 = 0;
  ulong v_minus_x0 = 0, v_minus_x1 = 0, v_minus_x2 = 0, v_minus_x3 = 0;
  ulong y_mul_hhh0 = 0, y_mul_hhh1 = 0, y_mul_hhh2 = 0, y_mul_hhh3 = 0;
  ulong y30 = 0, y31 = 0, y32 = 0, y33 = 0;
  ulong zz_out0 = 0, zz_out1 = 0, zz_out2 = 0, zz_out3 = 0;
  ulong zzz_out0 = 0, zzz_out1 = 0, zzz_out2 = 0, zzz_out3 = 0;

  field_square_values(h0, h1, h2, h3, hh0, hh1, hh2, hh3);
  field_mul_values(hh0, hh1, hh2, hh3, h0, h1, h2, h3, hhh0, hhh1, hhh2, hhh3);
  field_mul_values(x0, x1, x2, x3, hh0, hh1, hh2, hh3, v0, v1, v2, v3);
  field_square_values(r0, r1, r2, r3, x30, x31, x32, x33);
  field_sub_values(x30, x31, x32, x33, hhh0, hhh1, hhh2, hhh3, x30, x31, x32, x33);
  field_double_values(v0, v1, v2, v3, two_v0, two_v1, two_v2, two_v3);
  field_sub_values(x30, x31, x32, x33, two_v0, two_v1, two_v2, two_v3, x30, x31, x32, x33);
  field_sub_values(v0, v1, v2, v3, x30, x31, x32, x33, v_minus_x0, v_minus_x1, v_minus_x2, v_minus_x3);
  field_mul_values(r0, r1, r2, r3, v_minus_x0, v_minus_x1, v_minus_x2, v_minus_x3, y30, y31, y32, y33);
  field_mul_values(y0, y1, y2, y3, hhh0, hhh1, hhh2, hhh3, y_mul_hhh0, y_mul_hhh1, y_mul_hhh2, y_mul_hhh3);
  field_sub_values(y30, y31, y32, y33, y_mul_hhh0, y_mul_hhh1, y_mul_hhh2, y_mul_hhh3, y30, y31, y32, y33);
  field_mul_values(zz0, zz1, zz2, zz3, hh0, hh1, hh2, hh3, zz_out0, zz_out1, zz_out2, zz_out3);
  field_mul_values(zzz0, zzz1, zzz2, zzz3, hhh0, hhh1, hhh2, hhh3, zzz_out0, zzz_out1, zzz_out2, zzz_out3);
  out.x0 = x30; out.x1 = x31; out.x2 = x32; out.x3 = x33;
  out.y0 = y30; out.y1 = y31; out.y2 = y32; out.y3 = y33;
  out.zz0 = zz_out0; out.zz1 = zz_out1; out.zz2 = zz_out2; out.zz3 = zz_out3;
  out.zzz0 = zzz_out0; out.zzz1 = zzz_out1; out.zzz2 = zzz_out2; out.zzz3 = zzz_out3;
  out.inf = 0;
  return out;
}

kernel void jacobian_add_affine(device const ulong* p_xyz [[buffer(0)]],
                                device const ulong* q_xy [[buffer(1)]],
                                device const uint* p_infinity [[buffer(2)]],
                                device ulong* out_xyz [[buffer(3)]],
                                device uint* out_infinity [[buffer(4)]],
                                constant uint& count [[buffer(5)]],
                                uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id * 12;
  uint q_base = id * 8;
  uint out_base = id * 12;

  JacobianValue out = jacobian_add_affine_values(p_xyz[p_base + 0], p_xyz[p_base + 1], p_xyz[p_base + 2], p_xyz[p_base + 3],
                                                 p_xyz[p_base + 4], p_xyz[p_base + 5], p_xyz[p_base + 6], p_xyz[p_base + 7],
                                                 p_xyz[p_base + 8], p_xyz[p_base + 9], p_xyz[p_base + 10], p_xyz[p_base + 11],
                                                 p_infinity[id],
                                                 q_xy[q_base + 0], q_xy[q_base + 1], q_xy[q_base + 2], q_xy[q_base + 3],
                                                 q_xy[q_base + 4], q_xy[q_base + 5], q_xy[q_base + 6], q_xy[q_base + 7]);
  store_jacobian(out_xyz, out_base, out.x0, out.x1, out.x2, out.x3, out.y0, out.y1, out.y2, out.y3,
                 out.z0, out.z1, out.z2, out.z3, out_infinity, id, out.inf);
}

kernel void jacobian_affine_walk_fixed(device const ulong* p_xyz [[buffer(0)]],
                                       device const ulong* q_xy [[buffer(1)]],
                                       device const uint* p_infinity [[buffer(2)]],
                                       device ulong* out_xyz [[buffer(3)]],
                                       device uint* out_infinity [[buffer(4)]],
                                       constant uint& count [[buffer(5)]],
                                       constant uint& steps [[buffer(6)]],
                                       uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id * 12;
  uint q_base = id * 8;
  uint out_base = id * 12;
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  ulong qx0 = q_xy[q_base + 0], qx1 = q_xy[q_base + 1], qx2 = q_xy[q_base + 2], qx3 = q_xy[q_base + 3];
  ulong qy0 = q_xy[q_base + 4], qy1 = q_xy[q_base + 5], qy2 = q_xy[q_base + 6], qy3 = q_xy[q_base + 7];
  uint inf = p_infinity[id];

  for (uint step = 0; step < steps; step++) {
    JacobianValue out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                                   qx0, qx1, qx2, qx3, qy0, qy1, qy2, qy3);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian(out_xyz, out_base, x0, x1, x2, x3, y0, y1, y2, y3,
                 z0, z1, z2, z3, out_infinity, id, inf);
}

kernel void jacobian_affine_walk_jump_table(constant ulong* p_xyz [[buffer(0)]],
                                            constant ulong* q_xy [[buffer(1)]],
                                            constant uint* p_infinity [[buffer(2)]],
                                            device ulong* out_xyz [[buffer(3)]],
                                            device uchar* out_flags [[buffer(4)]],
                                            constant uint& count [[buffer(5)]],
                                            constant uint& steps [[buffer(6)]],
                                            constant uchar* jump_indices [[buffer(7)]],
                                            constant ulong* jump_distances [[buffer(8)]],
                                            device ulong* out_distances [[buffer(9)]],
                                            constant ulong& dp_mask [[buffer(10)]],
                                            uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  uint out_base = p_base;
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  uint inf = p_infinity[id];
  uint jump_base = id * steps;
  ulong distance = 0;

  for (uint step = 0; step < steps; step++) {
    uint jump_index = jump_indices[jump_base + step];
    distance += jump_distances[jump_index];
    uint q_base = jump_index << 3;
    JacobianValue out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                                   q_xy[q_base + 0], q_xy[q_base + 1], q_xy[q_base + 2], q_xy[q_base + 3],
                                                   q_xy[q_base + 4], q_xy[q_base + 5], q_xy[q_base + 6], q_xy[q_base + 7]);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(out_xyz, out_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  out_distances[id] = distance;
  out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & dp_mask) == 0)) ? 2 : 0);
}

kernel void jacobian_affine_walk_jump_table_steps8(constant ulong* p_xyz [[buffer(0)]],
                                                   constant ulong* q_xy [[buffer(1)]],
                                                   constant uint* p_infinity [[buffer(2)]],
                                                   device ulong* out_xyz [[buffer(3)]],
                                                   device uchar* out_flags [[buffer(4)]],
                                                   constant uint& count [[buffer(5)]],
                                                   constant uint& steps [[buffer(6)]],
                                                   constant uchar* jump_indices [[buffer(7)]],
                                                   constant ulong* jump_distances [[buffer(8)]],
                                                   device ulong* out_distances [[buffer(9)]],
                                                   constant ulong& dp_mask [[buffer(10)]],
                                                   uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  uint out_base = p_base;
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  uint inf = p_infinity[id];
  uint jump_base = id << 3;
  ulong distance = 0;

  for (uint step = 0; step < 8; step++) {
    uint jump_index = jump_indices[jump_base + step];
    distance += jump_distances[jump_index];
    uint q_base = jump_index << 3;
    JacobianValue out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                                   q_xy[q_base + 0], q_xy[q_base + 1], q_xy[q_base + 2], q_xy[q_base + 3],
                                                   q_xy[q_base + 4], q_xy[q_base + 5], q_xy[q_base + 6], q_xy[q_base + 7]);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(out_xyz, out_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  out_distances[id] = distance;
  out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & dp_mask) == 0)) ? 2 : 0);
}

kernel void jacobian_affine_walk_jump_table_steps8_dp4(constant ulong* p_xyz [[buffer(0)]],
                                                       constant AffineJumpValue* q_xy [[buffer(1)]],
                                                       constant uchar* p_infinity [[buffer(2)]],
                                                       device ulong* out_xyz [[buffer(3)]],
                                                       device uchar* out_flags [[buffer(4)]],
                                                       constant uint& count [[buffer(5)]],
                                                       constant uint& steps [[buffer(6)]],
                                                       constant uchar* jump_indices [[buffer(7)]],
                                                       constant ulong* jump_distances [[buffer(8)]],
                                                       device ulong* out_distances [[buffer(9)]],
                                                       uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  uint out_base = p_base;
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint jump_base = id << 3;
  ulong distance = 0;

  for (uint step = 0; step < 8; step++) {
    uint jump_index = jump_indices[jump_base + step];
    distance += jump_distances[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                       q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                              q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(out_xyz, out_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  out_distances[id] = distance;
  out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & 0xFUL) == 0)) ? 2 : 0);
}

kernel void jacobian_affine_walk_dynamic_jump_table(constant ulong* p_xyz [[buffer(0)]],
                                                    constant ulong* q_xy [[buffer(1)]],
                                                    constant uint* p_infinity [[buffer(2)]],
                                                    device ulong* out_xyz [[buffer(3)]],
                                                    device uchar* out_flags [[buffer(4)]],
                                                    constant uint& count [[buffer(5)]],
                                                    constant uint& steps [[buffer(6)]],
                                                    constant ulong* jump_distances [[buffer(7)]],
                                                    device ulong* out_distances [[buffer(8)]],
                                                    constant ulong& dp_mask [[buffer(9)]],
                                                    constant uint& jump_count [[buffer(10)]],
                                                    uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  uint out_base = p_base;
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  uint inf = p_infinity[id];
  ulong distance = 0;

  for (uint step = 0; step < steps; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = ((jump_count & (jump_count - 1)) == 0)
      ? (uint)(mixed & (ulong)(jump_count - 1))
      : (uint)(mixed % (ulong)jump_count);
    distance += jump_distances[jump_index];
    uint q_base = jump_index << 3;
    JacobianValue out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                                   q_xy[q_base + 0], q_xy[q_base + 1], q_xy[q_base + 2], q_xy[q_base + 3],
                                                   q_xy[q_base + 4], q_xy[q_base + 5], q_xy[q_base + 6], q_xy[q_base + 7]);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(out_xyz, out_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  out_distances[id] = distance;
  out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & dp_mask) == 0)) ? 2 : 0);
}

kernel void jacobian_affine_walk_dynamic_jump_table_steps8_dp4(constant ulong* p_xyz [[buffer(0)]],
                                                               constant AffineJumpValue* q_xy [[buffer(1)]],
                                                               constant uchar* p_infinity [[buffer(2)]],
                                                               device ulong* out_xyz [[buffer(3)]],
                                                               device uchar* out_flags [[buffer(4)]],
                                                               constant uint& count [[buffer(5)]],
                                                               constant uint& steps [[buffer(6)]],
                                                               constant ulong* jump_distances [[buffer(7)]],
                                                               device ulong* out_distances [[buffer(8)]],
                                                               constant uint& jump_count [[buffer(9)]],
                                                               uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  uint out_base = p_base;
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  ulong distance = 0;

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = ((jump_count & (jump_count - 1)) == 0)
      ? (uint)(mixed & (ulong)(jump_count - 1))
      : (uint)(mixed % (ulong)jump_count);
    distance += jump_distances[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                       q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                              q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(out_xyz, out_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  out_distances[id] = distance;
  out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & 0xFUL) == 0)) ? 2 : 0);
}

kernel void jacobian_affine_walk_dynamic_jump_table_steps8_dp4_pow2(constant ulong* p_xyz [[buffer(0)]],
                                                                    constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                    constant uchar* p_infinity [[buffer(2)]],
                                                                    device ulong* out_xyz [[buffer(3)]],
                                                                    device uchar* out_flags [[buffer(4)]],
                                                                    constant uint& count [[buffer(5)]],
                                                                    constant uint& steps [[buffer(6)]],
                                                                    constant ulong* jump_distances [[buffer(7)]],
                                                                    device ulong* out_distances [[buffer(8)]],
                                                                    constant uint& jump_mask [[buffer(9)]],
                                                                    uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  uint out_base = p_base;
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  ulong distance = 0;

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += jump_distances[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                       q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                              q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(out_xyz, out_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  out_distances[id] = distance;
  out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & 0xFUL) == 0)) ? 2 : 0);
}

kernel void jacobian_affine_walk_dynamic_dp_compact_steps8_dp4_pow2(constant ulong* p_xyz [[buffer(0)]],
                                                                    constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                    constant uchar* p_infinity [[buffer(2)]],
                                                                    device uchar* out_flags [[buffer(4)]],
                                                                    constant uint& count [[buffer(5)]],
                                                                    constant uint& steps [[buffer(6)]],
                                                                    constant ulong* jump_distances [[buffer(7)]],
                                                                    device ulong* out_distances [[buffer(8)]],
                                                                    device ulong* out_dp_terms [[buffer(9)]],
                                                                    constant uint& jump_mask [[buffer(10)]],
                                                                    uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  ulong distance = 0;

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += jump_distances[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                       q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                              q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  out_distances[id] = distance;
  out_dp_terms[id] = (!inf && ((x0 & 0xFUL) == 0)) ? (x0 ^ (y0 << 1) ^ (z0 << 7)) : 0UL;
  out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & 0xFUL) == 0)) ? 2 : 0);
}

kernel void jacobian_affine_walk_dynamic_dp_stream_steps8_dp4_pow2(constant ulong* p_xyz [[buffer(0)]],
                                                                   constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                   constant uchar* p_infinity [[buffer(2)]],
                                                                   device atomic_uint* out_dp_count [[buffer(4)]],
                                                                   device uint* out_indices [[buffer(5)]],
                                                                   constant uint& count [[buffer(6)]],
                                                                   constant uint& steps [[buffer(7)]],
                                                                   constant ulong* jump_distances [[buffer(8)]],
                                                                   device ulong* out_distances [[buffer(9)]],
                                                                   device ulong* out_dp_terms [[buffer(10)]],
                                                                   constant uint& jump_mask [[buffer(11)]],
                                                                   constant uint& dp_capacity [[buffer(12)]],
                                                                   device atomic_uint* out_overflow [[buffer(13)]],
                                                                   uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  ulong distance = 0;

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       jump.x0, jump.x1, jump.x2, jump.x3,
                                       jump.y0, jump.y1, jump.y2, jump.y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              jump.x0, jump.x1, jump.x2, jump.x3,
                                              jump.y0, jump.y1, jump.y2, jump.y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  if (!inf && ((x0 & 0xFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    if (slot < dp_capacity) {
      out_indices[slot] = id;
      out_distances[slot] = distance;
      out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
    } else {
      atomic_store_explicit(out_overflow, 1U, memory_order_relaxed);
    }
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_steps8_pow2_mask(constant ulong* p_xyz [[buffer(0)]],
                                                                    constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                    constant uchar* p_infinity [[buffer(2)]],
                                                                    device atomic_uint* out_dp_count [[buffer(4)]],
                                                                    device uint* out_indices [[buffer(5)]],
                                                                    constant uint& count [[buffer(6)]],
                                                                    constant uint& steps [[buffer(7)]],
                                                                    constant ulong* jump_distances [[buffer(8)]],
                                                                    device ulong* out_distances [[buffer(9)]],
                                                                    device ulong* out_dp_terms [[buffer(10)]],
                                                                    constant uint& jump_mask [[buffer(11)]],
                                                                    constant uint& dp_capacity [[buffer(12)]],
                                                                    device atomic_uint* out_overflow [[buffer(13)]],
                                                                    constant ulong& dp_mask [[buffer(14)]],
                                                                    uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  ulong distance = 0;

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += jump_distances[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                       q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                              q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  if (!inf && ((x0 & dp_mask) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    if (slot < dp_capacity) {
      out_indices[slot] = id;
      out_distances[slot] = distance;
      out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
    } else {
      atomic_store_explicit(out_overflow, 1U, memory_order_relaxed);
    }
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_steps8_pow2_mask_u32_distance(constant ulong* p_xyz [[buffer(0)]],
                                                                                 constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                 constant uchar* p_infinity [[buffer(2)]],
                                                                                 device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                 device uint* out_indices [[buffer(5)]],
                                                                                 constant uint& count [[buffer(6)]],
                                                                                 constant uint& steps [[buffer(7)]],
                                                                                 constant ulong* jump_distances [[buffer(8)]],
                                                                                 device ulong* out_distances [[buffer(9)]],
                                                                                 device ulong* out_dp_terms [[buffer(10)]],
                                                                                 constant uint& jump_mask [[buffer(11)]],
                                                                                 constant uint& dp_capacity [[buffer(12)]],
                                                                                 device atomic_uint* out_overflow [[buffer(13)]],
                                                                                 constant ulong& dp_mask [[buffer(14)]],
                                                                                 uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                       q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                              q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  if (!inf && ((x0 & dp_mask) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    if (slot < dp_capacity) {
      out_indices[slot] = id;
      out_distances[slot] = (ulong)distance;
      out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
    } else {
      atomic_store_explicit(out_overflow, 1U, memory_order_relaxed);
    }
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_steps8_dp8_pow2_u32_distance(constant ulong* p_xyz [[buffer(0)]],
                                                                                constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                constant uchar* p_infinity [[buffer(2)]],
                                                                                device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                device uint* out_indices [[buffer(5)]],
                                                                                constant uint& count [[buffer(6)]],
                                                                                constant ulong* jump_distances [[buffer(8)]],
                                                                                device ulong* out_distances [[buffer(9)]],
                                                                                device ulong* out_dp_terms [[buffer(10)]],
                                                                                constant uint& jump_mask [[buffer(11)]],
                                                                                uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       jump.x0, jump.x1, jump.x2, jump.x3,
                                       jump.y0, jump.y1, jump.y2, jump.y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              jump.x0, jump.x1, jump.x2, jump.x3,
                                              jump.y0, jump.y1, jump.y2, jump.y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_inplace_steps8_dp8_pow2_u32_distance(device ulong* p_xyz [[buffer(0)]],
                                                                                        constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                        device uchar* p_infinity [[buffer(2)]],
                                                                                        device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                        device uint* out_indices [[buffer(5)]],
                                                                                        constant uint& count [[buffer(6)]],
                                                                                        constant ulong* jump_distances [[buffer(8)]],
                                                                                        device ulong* out_distances [[buffer(9)]],
                                                                                        device ulong* out_dp_terms [[buffer(10)]],
                                                                                        constant uint& jump_mask [[buffer(11)]],
                                                                                        uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       jump.x0, jump.x1, jump.x2, jump.x3,
                                       jump.y0, jump.y1, jump.y2, jump.y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              jump.x0, jump.x1, jump.x2, jump.x3,
                                              jump.y0, jump.y1, jump.y2, jump.y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(p_xyz, p_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  p_infinity[id] = inf ? 1 : 0;

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_inplace_steps16_dp8_pow2_u32_distance(device ulong* p_xyz [[buffer(0)]],
                                                                                         constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                         device uchar* p_infinity [[buffer(2)]],
                                                                                         device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                         device uint* out_indices [[buffer(5)]],
                                                                                         constant uint& count [[buffer(6)]],
                                                                                         constant ulong* jump_distances [[buffer(8)]],
                                                                                         device ulong* out_distances [[buffer(9)]],
                                                                                         device ulong* out_dp_terms [[buffer(10)]],
                                                                                         constant uint& jump_mask [[buffer(11)]],
                                                                                         uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 16; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       jump.x0, jump.x1, jump.x2, jump.x3,
                                       jump.y0, jump.y1, jump.y2, jump.y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              jump.x0, jump.x1, jump.x2, jump.x3,
                                              jump.y0, jump.y1, jump.y2, jump.y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(p_xyz, p_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  p_infinity[id] = inf ? 1 : 0;

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_inplace_steps32_dp8_pow2_u32_distance(device ulong* p_xyz [[buffer(0)]],
                                                                                         constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                         device uchar* p_infinity [[buffer(2)]],
                                                                                         device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                         device uint* out_indices [[buffer(5)]],
                                                                                         constant uint& count [[buffer(6)]],
                                                                                         constant ulong* jump_distances [[buffer(8)]],
                                                                                         device ulong* out_distances [[buffer(9)]],
                                                                                         device ulong* out_dp_terms [[buffer(10)]],
                                                                                         constant uint& jump_mask [[buffer(11)]],
                                                                                         uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 32; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       jump.x0, jump.x1, jump.x2, jump.x3,
                                       jump.y0, jump.y1, jump.y2, jump.y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              jump.x0, jump.x1, jump.x2, jump.x3,
                                              jump.y0, jump.y1, jump.y2, jump.y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(p_xyz, p_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  p_infinity[id] = inf ? 1 : 0;

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_inplace_steps64_dp8_pow2_u32_distance(device ulong* p_xyz [[buffer(0)]],
                                                                                         constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                         device uchar* p_infinity [[buffer(2)]],
                                                                                         device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                         device uint* out_indices [[buffer(5)]],
                                                                                         constant uint& count [[buffer(6)]],
                                                                                         constant ulong* jump_distances [[buffer(8)]],
                                                                                         device ulong* out_distances [[buffer(9)]],
                                                                                         device ulong* out_dp_terms [[buffer(10)]],
                                                                                         constant uint& jump_mask [[buffer(11)]],
                                                                                         uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 64; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       jump.x0, jump.x1, jump.x2, jump.x3,
                                       jump.y0, jump.y1, jump.y2, jump.y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              jump.x0, jump.x1, jump.x2, jump.x3,
                                              jump.y0, jump.y1, jump.y2, jump.y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(p_xyz, p_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  p_infinity[id] = inf ? 1 : 0;

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_inplace_steps128_dp8_pow2_u32_distance(device ulong* p_xyz [[buffer(0)]],
                                                                                          constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                          device uchar* p_infinity [[buffer(2)]],
                                                                                          device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                          device uint* out_indices [[buffer(5)]],
                                                                                          constant uint& count [[buffer(6)]],
                                                                                          constant ulong* jump_distances [[buffer(8)]],
                                                                                          device ulong* out_distances [[buffer(9)]],
                                                                                          device ulong* out_dp_terms [[buffer(10)]],
                                                                                          constant uint& jump_mask [[buffer(11)]],
                                                                                          uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 128; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       jump.x0, jump.x1, jump.x2, jump.x3,
                                       jump.y0, jump.y1, jump.y2, jump.y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              jump.x0, jump.x1, jump.x2, jump.x3,
                                              jump.y0, jump.y1, jump.y2, jump.y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(p_xyz, p_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  p_infinity[id] = inf ? 1 : 0;

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_inplace_steps256_dp8_pow2_u32_distance(device ulong* p_xyz [[buffer(0)]],
                                                                                          constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                          device uchar* p_infinity [[buffer(2)]],
                                                                                          device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                          device uint* out_indices [[buffer(5)]],
                                                                                          constant uint& count [[buffer(6)]],
                                                                                          constant ulong* jump_distances [[buffer(8)]],
                                                                                          device ulong* out_distances [[buffer(9)]],
                                                                                          device ulong* out_dp_terms [[buffer(10)]],
                                                                                          constant uint& jump_mask [[buffer(11)]],
                                                                                          uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 256; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       jump.x0, jump.x1, jump.x2, jump.x3,
                                       jump.y0, jump.y1, jump.y2, jump.y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              jump.x0, jump.x1, jump.x2, jump.x3,
                                              jump.y0, jump.y1, jump.y2, jump.y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  store_jacobian_xyz_only(p_xyz, p_base, x0, x1, x2, x3, y0, y1, y2, y3,
                          z0, z1, z2, z3);
  p_infinity[id] = inf ? 1 : 0;

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp8_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                       constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                       device uchar* p_infinity [[buffer(2)]],
                                                                                       device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                       device uint* out_indices [[buffer(5)]],
                                                                                       constant uint& count [[buffer(6)]],
                                                                                       constant ulong* jump_distances [[buffer(8)]],
                                                                                       device ulong* out_distances [[buffer(9)]],
                                                                                       device ulong* out_dp_terms [[buffer(10)]],
                                                                                       constant uint& jump_mask [[buffer(11)]],
                                                                                       uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  ulong x0 = p_xyzz[p_base + 0], x1 = p_xyzz[p_base + 1], x2 = p_xyzz[p_base + 2], x3 = p_xyzz[p_base + 3];
  ulong y0 = p_xyzz[p_base + 4], y1 = p_xyzz[p_base + 5], y2 = p_xyzz[p_base + 6], y3 = p_xyzz[p_base + 7];
  ulong zz0 = p_xyzz[p_base + 8], zz1 = p_xyzz[p_base + 9], zz2 = p_xyzz[p_base + 10], zz3 = p_xyzz[p_base + 11];
  ulong zzz0 = p_xyzz[p_base + 12], zzz1 = p_xyzz[p_base + 13], zzz2 = p_xyzz[p_base + 14], zzz3 = p_xyzz[p_base + 15];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 256; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ zz0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    XyzzValue out = jacobian_add_affine_xyzz_values(x0, x1, x2, x3,
                                                    y0, y1, y2, y3,
                                                    zz0, zz1, zz2, zz3,
                                                    zzz0, zzz1, zzz2, zzz3,
                                                    inf,
                                                    jump.x0, jump.x1, jump.x2, jump.x3,
                                                    jump.y0, jump.y1, jump.y2, jump.y3);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    zz0 = out.zz0; zz1 = out.zz1; zz2 = out.zz2; zz3 = out.zz3;
    zzz0 = out.zzz0; zzz1 = out.zzz1; zzz2 = out.zzz2; zzz3 = out.zzz3;
    inf = out.inf;
  }

  p_xyzz[p_base + 0] = x0; p_xyzz[p_base + 1] = x1; p_xyzz[p_base + 2] = x2; p_xyzz[p_base + 3] = x3;
  p_xyzz[p_base + 4] = y0; p_xyzz[p_base + 5] = y1; p_xyzz[p_base + 6] = y2; p_xyzz[p_base + 7] = y3;
  p_xyzz[p_base + 8] = zz0; p_xyzz[p_base + 9] = zz1; p_xyzz[p_base + 10] = zz2; p_xyzz[p_base + 11] = zz3;
  p_xyzz[p_base + 12] = zzz0; p_xyzz[p_base + 13] = zzz1; p_xyzz[p_base + 14] = zzz2; p_xyzz[p_base + 15] = zzz3;
  p_infinity[id] = inf ? 1 : 0;

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (zz0 << 7) ^ (zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp8_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                       constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                       device uchar* p_infinity [[buffer(2)]],
                                                                                       device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                       device uint* out_indices [[buffer(5)]],
                                                                                       constant uint& count [[buffer(6)]],
                                                                                       constant ulong* jump_distances [[buffer(8)]],
                                                                                       device ulong* out_distances [[buffer(9)]],
                                                                                       device ulong* out_dp_terms [[buffer(10)]],
                                                                                       constant uint& jump_mask [[buffer(11)]],
                                                                                       uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  ulong x0 = p_xyzz[p_base + 0], x1 = p_xyzz[p_base + 1], x2 = p_xyzz[p_base + 2], x3 = p_xyzz[p_base + 3];
  ulong y0 = p_xyzz[p_base + 4], y1 = p_xyzz[p_base + 5], y2 = p_xyzz[p_base + 6], y3 = p_xyzz[p_base + 7];
  ulong zz0 = p_xyzz[p_base + 8], zz1 = p_xyzz[p_base + 9], zz2 = p_xyzz[p_base + 10], zz3 = p_xyzz[p_base + 11];
  ulong zzz0 = p_xyzz[p_base + 12], zzz1 = p_xyzz[p_base + 13], zzz2 = p_xyzz[p_base + 14], zzz3 = p_xyzz[p_base + 15];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 512; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ zz0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    XyzzValue out = jacobian_add_affine_xyzz_values(x0, x1, x2, x3,
                                                    y0, y1, y2, y3,
                                                    zz0, zz1, zz2, zz3,
                                                    zzz0, zzz1, zzz2, zzz3,
                                                    inf,
                                                    jump.x0, jump.x1, jump.x2, jump.x3,
                                                    jump.y0, jump.y1, jump.y2, jump.y3);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    zz0 = out.zz0; zz1 = out.zz1; zz2 = out.zz2; zz3 = out.zz3;
    zzz0 = out.zzz0; zzz1 = out.zzz1; zzz2 = out.zzz2; zzz3 = out.zzz3;
    inf = out.inf;
  }

  p_xyzz[p_base + 0] = x0; p_xyzz[p_base + 1] = x1; p_xyzz[p_base + 2] = x2; p_xyzz[p_base + 3] = x3;
  p_xyzz[p_base + 4] = y0; p_xyzz[p_base + 5] = y1; p_xyzz[p_base + 6] = y2; p_xyzz[p_base + 7] = y3;
  p_xyzz[p_base + 8] = zz0; p_xyzz[p_base + 9] = zz1; p_xyzz[p_base + 10] = zz2; p_xyzz[p_base + 11] = zz3;
  p_xyzz[p_base + 12] = zzz0; p_xyzz[p_base + 13] = zzz1; p_xyzz[p_base + 14] = zzz2; p_xyzz[p_base + 15] = zzz3;
  p_infinity[id] = inf ? 1 : 0;

  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (zz0 << 7) ^ (zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp8_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                             constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                             device uchar* p_infinity [[buffer(2)]],
                                                                                             device ulong* cumulative_distances [[buffer(3)]],
                                                                                             device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                             device uint* out_indices [[buffer(5)]],
                                                                                             constant uint& count [[buffer(6)]],
                                                                                             constant ulong* jump_distances [[buffer(8)]],
                                                                                             device ulong* out_distances [[buffer(9)]],
                                                                                             device ulong* out_dp_terms [[buffer(10)]],
                                                                                             constant uint& jump_mask [[buffer(11)]],
                                                                                             constant uint& packet_index_base [[buffer(12)]],
                                                                                             uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  ulong x0 = p_xyzz[p_base + 0], x1 = p_xyzz[p_base + 1], x2 = p_xyzz[p_base + 2], x3 = p_xyzz[p_base + 3];
  ulong y0 = p_xyzz[p_base + 4], y1 = p_xyzz[p_base + 5], y2 = p_xyzz[p_base + 6], y3 = p_xyzz[p_base + 7];
  ulong zz0 = p_xyzz[p_base + 8], zz1 = p_xyzz[p_base + 9], zz2 = p_xyzz[p_base + 10], zz3 = p_xyzz[p_base + 11];
  ulong zzz0 = p_xyzz[p_base + 12], zzz1 = p_xyzz[p_base + 13], zzz2 = p_xyzz[p_base + 14], zzz3 = p_xyzz[p_base + 15];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 256; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ zz0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    XyzzValue out = jacobian_add_affine_xyzz_values(x0, x1, x2, x3,
                                                    y0, y1, y2, y3,
                                                    zz0, zz1, zz2, zz3,
                                                    zzz0, zzz1, zzz2, zzz3,
                                                    inf,
                                                    jump.x0, jump.x1, jump.x2, jump.x3,
                                                    jump.y0, jump.y1, jump.y2, jump.y3);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    zz0 = out.zz0; zz1 = out.zz1; zz2 = out.zz2; zz3 = out.zz3;
    zzz0 = out.zzz0; zzz1 = out.zzz1; zzz2 = out.zzz2; zzz3 = out.zzz3;
    inf = out.inf;
  }

  p_xyzz[p_base + 0] = x0; p_xyzz[p_base + 1] = x1; p_xyzz[p_base + 2] = x2; p_xyzz[p_base + 3] = x3;
  p_xyzz[p_base + 4] = y0; p_xyzz[p_base + 5] = y1; p_xyzz[p_base + 6] = y2; p_xyzz[p_base + 7] = y3;
  p_xyzz[p_base + 8] = zz0; p_xyzz[p_base + 9] = zz1; p_xyzz[p_base + 10] = zz2; p_xyzz[p_base + 11] = zz3;
  p_xyzz[p_base + 12] = zzz0; p_xyzz[p_base + 13] = zzz1; p_xyzz[p_base + 14] = zzz2; p_xyzz[p_base + 15] = zzz3;
  p_infinity[id] = inf ? 1 : 0;

  ulong cumulative_distance = cumulative_distances[id] + (ulong)distance;
  cumulative_distances[id] = cumulative_distance;
  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = packet_index_base + id;
    out_distances[slot] = cumulative_distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (zz0 << 7) ^ (zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp8_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                             constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                             device uchar* p_infinity [[buffer(2)]],
                                                                                             device ulong* cumulative_distances [[buffer(3)]],
                                                                                             device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                             device uint* out_indices [[buffer(5)]],
                                                                                             constant uint& count [[buffer(6)]],
                                                                                             constant ulong* jump_distances [[buffer(8)]],
                                                                                             device ulong* out_distances [[buffer(9)]],
                                                                                             device ulong* out_dp_terms [[buffer(10)]],
                                                                                             constant uint& jump_mask [[buffer(11)]],
                                                                                             constant uint& packet_index_base [[buffer(12)]],
                                                                                             uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  ulong x0 = p_xyzz[p_base + 0], x1 = p_xyzz[p_base + 1], x2 = p_xyzz[p_base + 2], x3 = p_xyzz[p_base + 3];
  ulong y0 = p_xyzz[p_base + 4], y1 = p_xyzz[p_base + 5], y2 = p_xyzz[p_base + 6], y3 = p_xyzz[p_base + 7];
  ulong zz0 = p_xyzz[p_base + 8], zz1 = p_xyzz[p_base + 9], zz2 = p_xyzz[p_base + 10], zz3 = p_xyzz[p_base + 11];
  ulong zzz0 = p_xyzz[p_base + 12], zzz1 = p_xyzz[p_base + 13], zzz2 = p_xyzz[p_base + 14], zzz3 = p_xyzz[p_base + 15];
  bool inf = p_infinity[id];
  uint distance = 0;

  for (uint step = 0; step < 512; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ zz0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    XyzzValue out = jacobian_add_affine_xyzz_values(x0, x1, x2, x3,
                                                    y0, y1, y2, y3,
                                                    zz0, zz1, zz2, zz3,
                                                    zzz0, zzz1, zzz2, zzz3,
                                                    inf,
                                                    jump.x0, jump.x1, jump.x2, jump.x3,
                                                    jump.y0, jump.y1, jump.y2, jump.y3);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    zz0 = out.zz0; zz1 = out.zz1; zz2 = out.zz2; zz3 = out.zz3;
    zzz0 = out.zzz0; zzz1 = out.zzz1; zzz2 = out.zzz2; zzz3 = out.zzz3;
    inf = out.inf;
  }

  p_xyzz[p_base + 0] = x0; p_xyzz[p_base + 1] = x1; p_xyzz[p_base + 2] = x2; p_xyzz[p_base + 3] = x3;
  p_xyzz[p_base + 4] = y0; p_xyzz[p_base + 5] = y1; p_xyzz[p_base + 6] = y2; p_xyzz[p_base + 7] = y3;
  p_xyzz[p_base + 8] = zz0; p_xyzz[p_base + 9] = zz1; p_xyzz[p_base + 10] = zz2; p_xyzz[p_base + 11] = zz3;
  p_xyzz[p_base + 12] = zzz0; p_xyzz[p_base + 13] = zzz1; p_xyzz[p_base + 14] = zzz2; p_xyzz[p_base + 15] = zzz3;
  p_infinity[id] = inf ? 1 : 0;

  ulong cumulative_distance = cumulative_distances[id] + (ulong)distance;
  cumulative_distances[id] = cumulative_distance;
  if (!inf && ((x0 & 0xFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = packet_index_base + id;
    out_distances[slot] = cumulative_distance;
    out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (zz0 << 7) ^ (zzz0 << 13);
  }
}

struct XyzzDistanceValue {
  ulong x0, x1, x2, x3;
  ulong y0, y1, y2, y3;
  ulong zz0, zz1, zz2, zz3;
  ulong zzz0, zzz1, zzz2, zzz3;
  bool inf;
  uint distance;
};

inline XyzzDistanceValue xyzz_walk_pow2_u32_distance(ulong x0, ulong x1, ulong x2, ulong x3,
                                                     ulong y0, ulong y1, ulong y2, ulong y3,
                                                     ulong zz0, ulong zz1, ulong zz2, ulong zz3,
                                                     ulong zzz0, ulong zzz1, ulong zzz2, ulong zzz3,
                                                     bool inf,
                                                     constant AffineJumpValue* q_xy,
                                                     constant ulong* jump_distances,
                                                     uint jump_mask,
                                                     uint steps_per_sample) {
  uint distance = 0;
  for (uint step = 0; step < steps_per_sample; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ zz0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    distance += (uint)jump_distances[jump_index];
    AffineJumpValue jump = q_xy[jump_index];
    XyzzValue out = jacobian_add_affine_xyzz_values(x0, x1, x2, x3,
                                                    y0, y1, y2, y3,
                                                    zz0, zz1, zz2, zz3,
                                                    zzz0, zzz1, zzz2, zzz3,
                                                    inf,
                                                    jump.x0, jump.x1, jump.x2, jump.x3,
                                                    jump.y0, jump.y1, jump.y2, jump.y3);
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    zz0 = out.zz0; zz1 = out.zz1; zz2 = out.zz2; zz3 = out.zz3;
    zzz0 = out.zzz0; zzz1 = out.zzz1; zzz2 = out.zzz2; zzz3 = out.zzz3;
    inf = out.inf;
  }

  XyzzDistanceValue result;
  result.x0 = x0; result.x1 = x1; result.x2 = x2; result.x3 = x3;
  result.y0 = y0; result.y1 = y1; result.y2 = y2; result.y3 = y3;
  result.zz0 = zz0; result.zz1 = zz1; result.zz2 = zz2; result.zz3 = zz3;
  result.zzz0 = zzz0; result.zzz1 = zzz1; result.zzz2 = zzz2; result.zzz3 = zzz3;
  result.inf = inf;
  result.distance = distance;
  return result;
}

inline void store_xyzz_distance_value(device ulong* p_xyzz, uint p_base, XyzzDistanceValue value) {
  p_xyzz[p_base + 0] = value.x0; p_xyzz[p_base + 1] = value.x1; p_xyzz[p_base + 2] = value.x2; p_xyzz[p_base + 3] = value.x3;
  p_xyzz[p_base + 4] = value.y0; p_xyzz[p_base + 5] = value.y1; p_xyzz[p_base + 6] = value.y2; p_xyzz[p_base + 7] = value.y3;
  p_xyzz[p_base + 8] = value.zz0; p_xyzz[p_base + 9] = value.zz1; p_xyzz[p_base + 10] = value.zz2; p_xyzz[p_base + 11] = value.zz3;
  p_xyzz[p_base + 12] = value.zzz0; p_xyzz[p_base + 13] = value.zzz1; p_xyzz[p_base + 14] = value.zzz2; p_xyzz[p_base + 15] = value.zzz3;
}

kernel void jacobian_affine_walk_dynamic_xyzz_steps256_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                         constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                         device uchar* p_infinity [[buffer(2)]],
                                                                         device ulong* out_distances [[buffer(4)]],
                                                                         constant uint& count [[buffer(6)]],
                                                                         constant ulong* jump_distances [[buffer(8)]],
                                                                         constant uint& jump_mask [[buffer(11)]],
                                                                         uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 256);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;
  out_distances[id] = (ulong)out.distance;
}

kernel void jacobian_affine_walk_dynamic_xyzz_steps512_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                         constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                         device uchar* p_infinity [[buffer(2)]],
                                                                         device ulong* out_distances [[buffer(4)]],
                                                                         constant uint& count [[buffer(6)]],
                                                                         constant ulong* jump_distances [[buffer(8)]],
                                                                         constant uint& jump_mask [[buffer(11)]],
                                                                         uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 512);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;
  out_distances[id] = (ulong)out.distance;
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                   constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                   device uchar* p_infinity [[buffer(2)]],
                                                                                   device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                   device uint* out_indices [[buffer(5)]],
                                                                                   constant uint& count [[buffer(6)]],
                                                                                   constant ulong* jump_distances [[buffer(8)]],
                                                                                   device ulong* out_distances [[buffer(9)]],
                                                                                   device ulong* out_dp_terms [[buffer(10)]],
                                                                                   constant uint& jump_mask [[buffer(11)]],
                                                                                   constant ulong& dp_mask [[buffer(14)]],
                                                                                   uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 256);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  if (!out.inf && ((out.x0 & dp_mask) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)out.distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                   constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                   device uchar* p_infinity [[buffer(2)]],
                                                                                   device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                   device uint* out_indices [[buffer(5)]],
                                                                                   constant uint& count [[buffer(6)]],
                                                                                   constant ulong* jump_distances [[buffer(8)]],
                                                                                   device ulong* out_distances [[buffer(9)]],
                                                                                   device ulong* out_dp_terms [[buffer(10)]],
                                                                                   constant uint& jump_mask [[buffer(11)]],
                                                                                   constant ulong& dp_mask [[buffer(14)]],
                                                                                   uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 512);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  if (!out.inf && ((out.x0 & dp_mask) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)out.distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                         constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                         device uchar* p_infinity [[buffer(2)]],
                                                                                         device ulong* cumulative_distances [[buffer(3)]],
                                                                                         device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                         device uint* out_indices [[buffer(5)]],
                                                                                         constant uint& count [[buffer(6)]],
                                                                                         constant ulong* jump_distances [[buffer(8)]],
                                                                                         device ulong* out_distances [[buffer(9)]],
                                                                                         device ulong* out_dp_terms [[buffer(10)]],
                                                                                         constant uint& jump_mask [[buffer(11)]],
                                                                                         constant uint& packet_index_base [[buffer(12)]],
                                                                                         constant ulong& dp_mask [[buffer(14)]],
                                                                                         uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 256);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  ulong cumulative_distance = cumulative_distances[id] + (ulong)out.distance;
  cumulative_distances[id] = cumulative_distance;
  if (!out.inf && ((out.x0 & dp_mask) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = packet_index_base + id;
    out_distances[slot] = cumulative_distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                         constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                         device uchar* p_infinity [[buffer(2)]],
                                                                                         device ulong* cumulative_distances [[buffer(3)]],
                                                                                         device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                         device uint* out_indices [[buffer(5)]],
                                                                                         constant uint& count [[buffer(6)]],
                                                                                         constant ulong* jump_distances [[buffer(8)]],
                                                                                         device ulong* out_distances [[buffer(9)]],
                                                                                         device ulong* out_dp_terms [[buffer(10)]],
                                                                                         constant uint& jump_mask [[buffer(11)]],
                                                                                         constant uint& packet_index_base [[buffer(12)]],
                                                                                         constant ulong& dp_mask [[buffer(14)]],
                                                                                         uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 512);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  ulong cumulative_distance = cumulative_distances[id] + (ulong)out.distance;
  cumulative_distances[id] = cumulative_distance;
  if (!out.inf && ((out.x0 & dp_mask) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = packet_index_base + id;
    out_distances[slot] = cumulative_distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp12_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                        constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                        device uchar* p_infinity [[buffer(2)]],
                                                                                        device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                        device uint* out_indices [[buffer(5)]],
                                                                                        constant uint& count [[buffer(6)]],
                                                                                        constant ulong* jump_distances [[buffer(8)]],
                                                                                        device ulong* out_distances [[buffer(9)]],
                                                                                        device ulong* out_dp_terms [[buffer(10)]],
                                                                                        constant uint& jump_mask [[buffer(11)]],
                                                                                        uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 256);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  if (!out.inf && ((out.x0 & 0xFFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)out.distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp12_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                        constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                        device uchar* p_infinity [[buffer(2)]],
                                                                                        device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                        device uint* out_indices [[buffer(5)]],
                                                                                        constant uint& count [[buffer(6)]],
                                                                                        constant ulong* jump_distances [[buffer(8)]],
                                                                                        device ulong* out_distances [[buffer(9)]],
                                                                                        device ulong* out_dp_terms [[buffer(10)]],
                                                                                        constant uint& jump_mask [[buffer(11)]],
                                                                                        uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 512);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  if (!out.inf && ((out.x0 & 0xFFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)out.distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp12_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                              constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                              device uchar* p_infinity [[buffer(2)]],
                                                                                              device ulong* cumulative_distances [[buffer(3)]],
                                                                                              device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                              device uint* out_indices [[buffer(5)]],
                                                                                              constant uint& count [[buffer(6)]],
                                                                                              constant ulong* jump_distances [[buffer(8)]],
                                                                                              device ulong* out_distances [[buffer(9)]],
                                                                                              device ulong* out_dp_terms [[buffer(10)]],
                                                                                              constant uint& jump_mask [[buffer(11)]],
                                                                                              constant uint& packet_index_base [[buffer(12)]],
                                                                                              uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 256);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  ulong cumulative_distance = cumulative_distances[id] + (ulong)out.distance;
  cumulative_distances[id] = cumulative_distance;
  if (!out.inf && ((out.x0 & 0xFFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = packet_index_base + id;
    out_distances[slot] = cumulative_distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp12_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                              constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                              device uchar* p_infinity [[buffer(2)]],
                                                                                              device ulong* cumulative_distances [[buffer(3)]],
                                                                                              device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                              device uint* out_indices [[buffer(5)]],
                                                                                              constant uint& count [[buffer(6)]],
                                                                                              constant ulong* jump_distances [[buffer(8)]],
                                                                                              device ulong* out_distances [[buffer(9)]],
                                                                                              device ulong* out_dp_terms [[buffer(10)]],
                                                                                              constant uint& jump_mask [[buffer(11)]],
                                                                                              constant uint& packet_index_base [[buffer(12)]],
                                                                                              uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 512);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  ulong cumulative_distance = cumulative_distances[id] + (ulong)out.distance;
  cumulative_distances[id] = cumulative_distance;
  if (!out.inf && ((out.x0 & 0xFFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = packet_index_base + id;
    out_distances[slot] = cumulative_distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp16_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                        constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                        device uchar* p_infinity [[buffer(2)]],
                                                                                        device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                        device uint* out_indices [[buffer(5)]],
                                                                                        constant uint& count [[buffer(6)]],
                                                                                        constant ulong* jump_distances [[buffer(8)]],
                                                                                        device ulong* out_distances [[buffer(9)]],
                                                                                        device ulong* out_dp_terms [[buffer(10)]],
                                                                                        constant uint& jump_mask [[buffer(11)]],
                                                                                        uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 256);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  if (!out.inf && ((out.x0 & 0xFFFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)out.distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp16_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                        constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                        device uchar* p_infinity [[buffer(2)]],
                                                                                        device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                        device uint* out_indices [[buffer(5)]],
                                                                                        constant uint& count [[buffer(6)]],
                                                                                        constant ulong* jump_distances [[buffer(8)]],
                                                                                        device ulong* out_distances [[buffer(9)]],
                                                                                        device ulong* out_dp_terms [[buffer(10)]],
                                                                                        constant uint& jump_mask [[buffer(11)]],
                                                                                        uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 512);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  if (!out.inf && ((out.x0 & 0xFFFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = id;
    out_distances[slot] = (ulong)out.distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp16_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                              constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                              device uchar* p_infinity [[buffer(2)]],
                                                                                              device ulong* cumulative_distances [[buffer(3)]],
                                                                                              device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                              device uint* out_indices [[buffer(5)]],
                                                                                              constant uint& count [[buffer(6)]],
                                                                                              constant ulong* jump_distances [[buffer(8)]],
                                                                                              device ulong* out_distances [[buffer(9)]],
                                                                                              device ulong* out_dp_terms [[buffer(10)]],
                                                                                              constant uint& jump_mask [[buffer(11)]],
                                                                                              constant uint& packet_index_base [[buffer(12)]],
                                                                                              uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 256);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  ulong cumulative_distance = cumulative_distances[id] + (ulong)out.distance;
  cumulative_distances[id] = cumulative_distance;
  if (!out.inf && ((out.x0 & 0xFFFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = packet_index_base + id;
    out_distances[slot] = cumulative_distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp16_pow2_u32_distance(device ulong* p_xyzz [[buffer(0)]],
                                                                                              constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                                              device uchar* p_infinity [[buffer(2)]],
                                                                                              device ulong* cumulative_distances [[buffer(3)]],
                                                                                              device atomic_uint* out_dp_count [[buffer(4)]],
                                                                                              device uint* out_indices [[buffer(5)]],
                                                                                              constant uint& count [[buffer(6)]],
                                                                                              constant ulong* jump_distances [[buffer(8)]],
                                                                                              device ulong* out_distances [[buffer(9)]],
                                                                                              device ulong* out_dp_terms [[buffer(10)]],
                                                                                              constant uint& jump_mask [[buffer(11)]],
                                                                                              constant uint& packet_index_base [[buffer(12)]],
                                                                                              uint id [[thread_position_in_grid]]) {
  if (id >= count) return;
  uint p_base = id << 4;
  XyzzDistanceValue out = xyzz_walk_pow2_u32_distance(p_xyzz[p_base + 0], p_xyzz[p_base + 1], p_xyzz[p_base + 2], p_xyzz[p_base + 3],
                                                     p_xyzz[p_base + 4], p_xyzz[p_base + 5], p_xyzz[p_base + 6], p_xyzz[p_base + 7],
                                                     p_xyzz[p_base + 8], p_xyzz[p_base + 9], p_xyzz[p_base + 10], p_xyzz[p_base + 11],
                                                     p_xyzz[p_base + 12], p_xyzz[p_base + 13], p_xyzz[p_base + 14], p_xyzz[p_base + 15],
                                                     p_infinity[id], q_xy, jump_distances, jump_mask, 512);
  store_xyzz_distance_value(p_xyzz, p_base, out);
  p_infinity[id] = out.inf ? 1 : 0;

  ulong cumulative_distance = cumulative_distances[id] + (ulong)out.distance;
  cumulative_distances[id] = cumulative_distance;
  if (!out.inf && ((out.x0 & 0xFFFFUL) == 0)) {
    uint slot = atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
    out_indices[slot] = packet_index_base + id;
    out_distances[slot] = cumulative_distance;
    out_dp_terms[slot] = out.x0 ^ (out.y0 << 1) ^ (out.zz0 << 7) ^ (out.zzz0 << 13);
  }
}

kernel void jacobian_affine_walk_dynamic_dp_count_steps8_pow2_mask(constant ulong* p_xyz [[buffer(0)]],
                                                                   constant AffineJumpValue* q_xy [[buffer(1)]],
                                                                   constant uchar* p_infinity [[buffer(2)]],
                                                                   device atomic_uint* out_dp_count [[buffer(4)]],
                                                                   constant uint& count [[buffer(5)]],
                                                                   constant uint& steps [[buffer(6)]],
                                                                   constant uint& jump_mask [[buffer(7)]],
                                                                   constant ulong& dp_mask [[buffer(10)]],
                                                                   uint id [[thread_position_in_grid]]) {
  (void)steps;
  if (id >= count) return;
  uint p_base = (id << 3) + (id << 2);
  ulong x0 = p_xyz[p_base + 0], x1 = p_xyz[p_base + 1], x2 = p_xyz[p_base + 2], x3 = p_xyz[p_base + 3];
  ulong y0 = p_xyz[p_base + 4], y1 = p_xyz[p_base + 5], y2 = p_xyz[p_base + 6], y3 = p_xyz[p_base + 7];
  ulong z0 = p_xyz[p_base + 8], z1 = p_xyz[p_base + 9], z2 = p_xyz[p_base + 10], z3 = p_xyz[p_base + 11];
  bool inf = p_infinity[id];

  for (uint step = 0; step < 8; step++) {
    ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;
    mixed ^= mixed >> 33;
    mixed *= 0xff51afd7ed558ccdUL;
    mixed ^= mixed >> 33;
    uint jump_index = (uint)(mixed & (ulong)jump_mask);
    JacobianValue out;
    if (inf) {
      out = jacobian_add_affine_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3, inf,
                                       q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                       q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    } else {
      out = jacobian_add_affine_finite_values(x0, x1, x2, x3, y0, y1, y2, y3, z0, z1, z2, z3,
                                              q_xy[jump_index].x0, q_xy[jump_index].x1, q_xy[jump_index].x2, q_xy[jump_index].x3,
                                              q_xy[jump_index].y0, q_xy[jump_index].y1, q_xy[jump_index].y2, q_xy[jump_index].y3);
    }
    x0 = out.x0; x1 = out.x1; x2 = out.x2; x3 = out.x3;
    y0 = out.y0; y1 = out.y1; y2 = out.y2; y3 = out.y3;
    z0 = out.z0; z1 = out.z1; z2 = out.z2; z3 = out.z3;
    inf = out.inf;
  }

  if (!inf && ((x0 & dp_mask) == 0)) {
    atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed);
  }
}

struct TargetLookupKey {
  ulong x[4];
  uint parity;
};

struct TargetLookupBucket {
  TargetLookupKey key;
  uint target_index;
  uint occupied;
};

struct TargetLookupCompactBucket {
  ulong hash;
  uint target_index;
  uint occupied;
};

struct TargetLookupTag32Bucket {
  uint tag;
  uint target_index;
};

static inline ulong target_lookup_mix(ulong v) {
  v ^= v >> 33;
  v *= 0xff51afd7ed558ccdUL;
  v ^= v >> 33;
  v *= 0xc4ceb9fe1a85ec53UL;
  v ^= v >> 33;
  return v;
}

static inline ulong target_lookup_hash(thread const TargetLookupKey& key) {
  ulong h = 0x9e3779b97f4a7c15UL;
  h = target_lookup_mix(h ^ key.x[0]);
  h = target_lookup_mix(h ^ key.x[1]);
  h = target_lookup_mix(h ^ key.x[2]);
  h = target_lookup_mix(h ^ key.x[3]);
  return target_lookup_mix(h ^ (ulong)key.parity);
}

static inline uint target_lookup_filter_tag(ulong hash) {
  return ((uint)(hash >> 32)) | 1U;
}

static inline ushort target_lookup_filter_tag16(ulong hash) {
  return ((ushort)(hash >> 48)) | (ushort)1U;
}

static inline bool target_lookup_key_equals(thread const TargetLookupKey& a, thread const TargetLookupKey& b) {
  return a.parity == b.parity &&
         a.x[0] == b.x[0] &&
         a.x[1] == b.x[1] &&
         a.x[2] == b.x[2] &&
         a.x[3] == b.x[3];
}

static inline bool target_lookup_key_equals(device const TargetLookupKey& a, thread const TargetLookupKey& b) {
  return a.parity == b.parity &&
         a.x[0] == b.x[0] &&
         a.x[1] == b.x[1] &&
         a.x[2] == b.x[2] &&
         a.x[3] == b.x[3];
}

kernel void target_lookup_exact256(device const TargetLookupBucket* target_buckets [[buffer(0)]],
                                   device const TargetLookupKey* query_keys [[buffer(1)]],
                                   device uint* out_target_indices [[buffer(2)]],
                                   device atomic_uint* out_hit_count [[buffer(3)]],
                                   constant uint& bucket_count [[buffer(4)]],
                                   constant uint& query_count [[buffer(5)]],
                                   uint id [[thread_position_in_grid]]) {
  if (id >= query_count) return;
  TargetLookupKey query = query_keys[id];
  uint slot = (uint)(target_lookup_hash(query) & (ulong)(bucket_count - 1));
  uint probes = 0;
  uint found = 0xFFFFFFFFU;

  while (probes < bucket_count) {
    TargetLookupBucket bucket = target_buckets[slot];
    if (!bucket.occupied) {
      break;
    }
    if (target_lookup_key_equals(bucket.key, query)) {
      found = bucket.target_index;
      atomic_fetch_add_explicit(out_hit_count, 1U, memory_order_relaxed);
      break;
    }
    slot = (slot + 1U) & (bucket_count - 1U);
    probes++;
  }

  out_target_indices[id] = found;
}

kernel void target_lookup_compact_exact256(device const TargetLookupCompactBucket* target_buckets [[buffer(0)]],
                                           device const TargetLookupKey* target_keys [[buffer(1)]],
                                           device const TargetLookupKey* query_keys [[buffer(2)]],
                                           device uint* out_target_indices [[buffer(3)]],
                                           device atomic_uint* out_hit_count [[buffer(4)]],
                                           constant uint& bucket_count [[buffer(5)]],
                                           constant uint& query_count [[buffer(6)]],
                                           uint id [[thread_position_in_grid]]) {
  if (id >= query_count) return;
  TargetLookupKey query = query_keys[id];
  ulong hash = target_lookup_hash(query);
  uint slot = (uint)(hash & (ulong)(bucket_count - 1));
  uint probes = 0;
  uint found = 0xFFFFFFFFU;

  while (probes < bucket_count) {
    TargetLookupCompactBucket bucket = target_buckets[slot];
    if (!bucket.occupied) {
      break;
    }
    if (bucket.hash == hash && target_lookup_key_equals(target_keys[bucket.target_index], query)) {
      found = bucket.target_index;
      atomic_fetch_add_explicit(out_hit_count, 1U, memory_order_relaxed);
      break;
    }
    slot = (slot + 1U) & (bucket_count - 1U);
    probes++;
  }

  out_target_indices[id] = found;
}

kernel void target_lookup_tag32_filter256(device const uint* target_filter_buckets [[buffer(0)]],
                                          device const TargetLookupKey* query_keys [[buffer(1)]],
                                          device uint* out_positive_query_indices [[buffer(2)]],
                                          device atomic_uint* out_filter_positive_count [[buffer(3)]],
                                          constant uint& bucket_count [[buffer(4)]],
                                          constant uint& query_count [[buffer(5)]],
                                          uint id [[thread_position_in_grid]]) {
  if (id >= query_count) return;
  TargetLookupKey query = query_keys[id];
  ulong hash = target_lookup_hash(query);
  uint filter_tag = target_lookup_filter_tag(hash);
  uint slot = (uint)(hash & (ulong)(bucket_count - 1));
  uint probes = 0;

  while (probes < bucket_count) {
    uint bucket_tag = target_filter_buckets[slot];
    if (bucket_tag == 0U) {
      break;
    }
    if (bucket_tag == filter_tag) {
      uint out_slot = atomic_fetch_add_explicit(out_filter_positive_count, 1U, memory_order_relaxed);
      if (out_slot < query_count) {
        out_positive_query_indices[out_slot] = id;
      }
      break;
    }
    slot = (slot + 1U) & (bucket_count - 1U);
    probes++;
  }
}

kernel void target_lookup_tag16_filter256(device const ushort* target_filter_buckets [[buffer(0)]],
                                          device const TargetLookupKey* query_keys [[buffer(1)]],
                                          device uint* out_positive_query_indices [[buffer(2)]],
                                          device atomic_uint* out_filter_positive_count [[buffer(3)]],
                                          constant uint& bucket_count [[buffer(4)]],
                                          constant uint& query_count [[buffer(5)]],
                                          uint id [[thread_position_in_grid]]) {
  if (id >= query_count) return;
  TargetLookupKey query = query_keys[id];
  ulong hash = target_lookup_hash(query);
  ushort filter_tag = target_lookup_filter_tag16(hash);
  uint slot = (uint)(hash & (ulong)(bucket_count - 1));
  uint probes = 0;

  while (probes < bucket_count) {
    ushort bucket_tag = target_filter_buckets[slot];
    if (bucket_tag == (ushort)0U) {
      break;
    }
    if (bucket_tag == filter_tag) {
      uint out_slot = atomic_fetch_add_explicit(out_filter_positive_count, 1U, memory_order_relaxed);
      if (out_slot < query_count) {
        out_positive_query_indices[out_slot] = id;
      }
      break;
    }
    slot = (slot + 1U) & (bucket_count - 1U);
    probes++;
  }
}

kernel void target_lookup_tag32_exact256(device const TargetLookupTag32Bucket* target_buckets [[buffer(0)]],
                                         device const TargetLookupKey* target_keys [[buffer(1)]],
                                         device const TargetLookupKey* query_keys [[buffer(2)]],
                                         device uint* out_target_indices [[buffer(3)]],
                                         device atomic_uint* out_hit_count [[buffer(4)]],
                                         constant uint& bucket_count [[buffer(5)]],
                                         constant uint& query_count [[buffer(6)]],
                                         uint id [[thread_position_in_grid]]) {
  if (id >= query_count) return;
  TargetLookupKey query = query_keys[id];
  ulong hash = target_lookup_hash(query);
  uint tag = (uint)(hash >> 32);
  uint slot = (uint)(hash & (ulong)(bucket_count - 1));
  uint probes = 0;
  uint found = 0xFFFFFFFFU;

  while (probes < bucket_count) {
    TargetLookupTag32Bucket bucket = target_buckets[slot];
    if (bucket.target_index == 0xFFFFFFFFU) {
      break;
    }
    if (bucket.target_index != 0xFFFFFFFFU && bucket.tag == tag && target_lookup_key_equals(target_keys[bucket.target_index], query)) {
      found = bucket.target_index;
      atomic_fetch_add_explicit(out_hit_count, 1U, memory_order_relaxed);
      break;
    }
    slot = (slot + 1U) & (bucket_count - 1U);
    probes++;
  }

  out_target_indices[id] = found;
}
)RCK_METAL";
