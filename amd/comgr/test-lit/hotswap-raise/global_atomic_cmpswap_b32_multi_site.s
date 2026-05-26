; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=global_atomic_cmpswap_b32_multi_site_kernel 2>/dev/null | %FileCheck %s
;
; Regression guard for Bug-Id: 2026-05-26T04-13-44Z_qwen2.5-7b-instruct-003
; (mnemonic: global_atomic_cmpswap_b32, 32 hits across 8 kernels, rocsolver bdsqr_init).
; Also covers Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-003
; (duplicate: same 32-site rocsolver bdsqr_init pattern in a later run, fatbin_co_0134.co).
; Also covers Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-003
; (duplicate: 32 global_atomic_cmpswap_b32 hits across 8 rocsolver bdsqr kernels,
; fatbin_co_0134.co, same cross-wave-replica-race NonCommutativeAtomic root cause).
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-003
; (duplicate: 32 global_atomic_cmpswap_b32 hits across 8 rocsolver bdsqr kernels,
; fatbin_co_0134.co, same .co, same root cause; all 45 kernels raise cleanly).
; Also covers Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-003
; (duplicate: 32 global_atomic_cmpswap_b32 hits across 8 rocsolver bdsqr kernels,
; fatbin_co_0134.co, same .co, same root cause; all 45 kernels raise cleanly).
;
; Pins that a kernel containing MULTIPLE global_atomic_cmpswap_b32 sites is
; raised cleanly under WaveNativeProjection (the default). The prior failure
; was a cross-wave-replica-race NonCommutativeAtomic report triggered when
; multiple cmpswap sites appeared together in a single kernel; the elect-leader
; / WaveNative obstruction fix suppressed all of them.
;
; Both cmpswap sites must produce `cmpxchg` IR, and no replica-race diagnostic
; may appear.

; CHECK-LABEL: define amdgpu_kernel void @global_atomic_cmpswap_b32_multi_site_kernel(
; First cmpswap site.
; CHECK: cmpxchg ptr addrspace(1)
; Second cmpswap site (at least two `cmpxchg` in the IR).
; CHECK: cmpxchg ptr addrspace(1)
; Negative: no cross-wave-replica-race diagnostic.
; CHECK-NOT: cross-wave-replica-race
; CHECK-NOT: NonCommutativeAtomic

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_atomic_cmpswap_b32_multi_site_kernel
	.p2align	8
	.type	global_atomic_cmpswap_b32_multi_site_kernel,@function
global_atomic_cmpswap_b32_multi_site_kernel:
	; Kernel with two global_atomic_cmpswap_b32 sites, each using the same
	; base pointer but separate VGPR groups. Both are no-RTN (result discarded).
	;   site1: cmp=v1(0), new=v0(1)  → v2 = discarded result
	;   site2: cmp=v4(0), new=v3(2)  → v5 = discarded result
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	; Site 1
	v_dual_mov_b32 v2, 0 :: v_dual_mov_b32 v1, 0
	v_mov_b32_e32 v0, 1
	global_atomic_cmpswap_b32 v2, v[0:1], s[0:1] scope:SCOPE_DEV
	; Site 2: use even-aligned pair v[4:5] (new=v4, cmp=v5), result discarded to v3
	v_dual_mov_b32 v5, 0 :: v_dual_mov_b32 v3, 0
	v_mov_b32_e32 v4, 2
	global_atomic_cmpswap_b32 v3, v[4:5], s[0:1] scope:SCOPE_DEV
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_atomic_cmpswap_b32_multi_site_kernel
		.amdhsa_kernarg_size 264
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 6
		.amdhsa_next_free_sgpr 2
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 264
    .max_flat_workgroup_size: 1024
    .name:           global_atomic_cmpswap_b32_multi_site_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         global_atomic_cmpswap_b32_multi_site_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
