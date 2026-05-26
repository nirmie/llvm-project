; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=global_atomic_cmpswap_b32_rtn_kernel 2>/dev/null | %FileCheck %s
;
; Pins global_atomic_cmpswap_b32 RTN (return-old-value) form under
; WaveNativeProjection (the default for wave32->wave64 cross-widening).
; The RTN variant uses th:TH_ATOMIC_RETURN and writes the previous memory
; value back to a destination VGPR.  rocsolver bdsqr_init (and related
; bdsqr family kernels) use this pattern: 32 sites across 8 kernels in
; fatbin_co_0134.co (hotswap commit 8f2db5ec2edc).
;
; The NonCommutativeAtomic obstruction must NOT fire under WaveNative because
; the SPE emitUnderExec diamond gates each atomic through br i1 %lane_active,
; eliminating the lane-i vs lane-i+W_s replica race that triggers Class 3
; under ModuloReplication.  The lifted IR must contain `cmpxchg` with the
; returned value extracted via ExtractValue.
;
; See also:
;   global_atomic_cmpswap_b32_wave_native.s -- non-RTN WaveNative pin
;   global_atomic_cmpswap_b32_multi_site.s  -- multi-site WaveNative pin
;   c3_atomic_cas.s                         -- MODREP refusal (--disable-wave-native)
;
; Pins Bug-Id: 2026-05-26T15-20-57Z_qwen2.5-7b-instruct-003
; 32 global_atomic_cmpswap_b32 RTN hits across 8 rocsolver bdsqr kernels
; (fatbin_co_0134.co) reported as UnsupportedOpcode/cross-wave-replica-race.
; WaveNative obstruction suppression for NonCommutativeAtomic/Class-3 sites
; in wave-size-obstruction.cpp resolves this; all 45 kernels raise cleanly.

; CHECK-LABEL: define amdgpu_kernel void @global_atomic_cmpswap_b32_rtn_kernel(
; RTN form: old value is extracted from the cmpxchg pair and written to vgpr.
; CHECK: cmpxchg ptr addrspace(1)
; CHECK: extractvalue { i32, i1 }
; Negative: no MODREP refusal diagnostic.
; CHECK-NOT: cross-wave-replica-race
; CHECK-NOT: NonCommutativeAtomic

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_atomic_cmpswap_b32_rtn_kernel
	.p2align	8
	.type	global_atomic_cmpswap_b32_rtn_kernel,@function
global_atomic_cmpswap_b32_rtn_kernel:
	; Mimics the rocsolver bdsqr_init addressing pattern:
	;   s[0:1] = kernarg ptr
	;   s[2:3] = global buffer pointer loaded from kernargs
	;   v0     = workitem-id-derived lane-unique offset
	;   v[4:5] = cmpswap (cmp, new) data pair (must not overlap vdst v3)
	;   v3     = RTN destination (receives old value)
	s_load_b64 s[2:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	; v0 = workitem id (lane-unique offset for WaveNative to pass)
	v_mov_b32_e32 v0, 0
	; v[4:5] = (cmp=1, new=0) — RTN: store old into v3
	v_mov_b32_e32 v4, 1
	v_mov_b32_e32 v5, 0
	global_atomic_cmpswap_b32 v3, v0, v[4:5], s[2:3] th:TH_ATOMIC_RETURN scope:SCOPE_DEV
	s_wait_loadcnt 0x0
	; Use v3 (returned old value) to prevent dead-code elimination.
	global_store_b32 v0, v3, s[2:3]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_atomic_cmpswap_b32_rtn_kernel
		.amdhsa_kernarg_size 264
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 6
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
    .name:           global_atomic_cmpswap_b32_rtn_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         global_atomic_cmpswap_b32_rtn_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
