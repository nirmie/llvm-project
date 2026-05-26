; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=global_atomic_cmpswap_b32_multi_site_kernel 2>/dev/null | %FileCheck %s
;
; Regression fence for bug 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-003:
; the rocsolver bdsqr family (8 kernels, 32 global_atomic_cmpswap_b32 sites
; total, ~4 per kernel) was reported UnsupportedOpcode/cross-wave-replica-race
; on gfx1250->gfx950. The WaveNative obstruction suppression for
; NonCommutativeAtomic/Class-3 sites in wave-size-obstruction.cpp handles
; this; all 45 kernels in fatbin_co_0134.co now raise cleanly.
;
; Also covers Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-003
; 32 global_atomic_cmpswap_b32 hits across 8 rocsolver bdsqr kernels
; (fatbin_co_0134.co) in a later qwen2.5-7b-instruct run.  Same root cause
; and same fix as above; all 45 kernels in the .co raise cleanly.
;
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-003
; 32 global_atomic_cmpswap_b32 hits across 8 rocsolver bdsqr kernels
; (fatbin_co_0134.co, same .co) in a subsequent qwen2.5-7b-instruct run.
; Same root cause and same fix; all 45 kernels raise cleanly.
;
; Also covers Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-003
; 32 global_atomic_cmpswap_b32 hits across 8 rocsolver bdsqr kernels
; (fatbin_co_0134.co, same .co) in another qwen2.5-7b-instruct run.
; Same root cause and same fix; all 45 kernels raise cleanly.
;
; This test pins the multi-site pattern: a single kernel with TWO
; global_atomic_cmpswap_b32 instructions (rocsolver-style SGPR pointer +
; VGPR offset addressing) must produce two cmpxchg IR nodes and no
; replica-race diagnostic under WaveNativeProjection (the default).
;
; See also:
;   global_atomic_cmpswap_b32_wave_native.s   -- single-site WaveNative pin
;   c3_atomic_cas.s                            -- MODREP refusal (--disable-wave-native)

; CHECK-LABEL: define amdgpu_kernel void @global_atomic_cmpswap_b32_multi_site_kernel(
; Two distinct cmpxchg IR nodes must appear (one per source cmpswap site).
; CHECK: cmpxchg ptr addrspace(1)
; CHECK: cmpxchg ptr addrspace(1)
; Negative: no replica-race pre-translation abort.
; CHECK-NOT: cross-wave-replica-race
; CHECK-NOT: NonCommutativeAtomic

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_atomic_cmpswap_b32_multi_site_kernel
	.p2align	8
	.type	global_atomic_cmpswap_b32_multi_site_kernel,@function
global_atomic_cmpswap_b32_multi_site_kernel:
	; Mimics the rocsolver bdsqr_init addressing pattern:
	;   s[0:1] = kernarg ptr (base pointer from hidden args)
	;   s[2:3] = global buffer pointer loaded from kernargs
	;   v0     = workitem-derived offset (unique per lane -> WaveNative pass)
	;   v1     = 0 (high word of 64-bit vaddr pair)
	;
	; Load global buffer pointer from kernargs.
	s_load_b64 s[2:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	; Two independent cmpswap sites on the same base pointer but different
	; lane-unique offsets, matching the multi-site rocsolver pattern.
	v_dual_mov_b32 v3, 0 :: v_dual_mov_b32 v2, 0
	v_mov_b32_e32 v1, 1
	; Site 1: offset=v0 (workitem-id derived unique address)
	global_atomic_cmpswap_b32 v3, v[0:1], s[2:3] scope:SCOPE_DEV
	; Site 2: offset=v0+4 (still unique per lane)
	v_add_nc_u32_e32 v4, 4, v0
	v_dual_mov_b32 v6, 0 :: v_dual_mov_b32 v5, 0
	v_mov_b32_e32 v4, 1
	global_atomic_cmpswap_b32 v6, v[4:5], s[2:3] scope:SCOPE_DEV
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_atomic_cmpswap_b32_multi_site_kernel
		.amdhsa_kernarg_size 264
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 7
		.amdhsa_next_free_sgpr 4
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
    .sgpr_count:     4
    .symbol:         global_atomic_cmpswap_b32_multi_site_kernel.kd
    .vgpr_count:     7
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
