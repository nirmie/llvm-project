; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=s_mov_b64_src_shared_base_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T18-08-17Z_qwen2.5-7b-instruct-008.
;
; s_mov_b64 with src_shared_base (and related aperture registers:
; src_shared_limit, src_private_base, src_private_limit) was failing with
; UnsupportedOpcode (format=operand-read) in 626 instances across 182 rocBLAS
; kernels (rocblas_trsm_block_forward/backward_substitution family).
;
; The pattern is: `s_mov_b64 s[pair], src_shared_base` -- reading the 64-bit
; aperture base register into an SGPR pair. The aperture registers are
; available on gfx9+ including gfx950, and the hardware populates the HI 32
; bits with the actual aperture address (the LO 32 bits are architecturally
; zero). The fix emits inline asm `s_mov_b64 $0, src_shared_base` to
; materialise the 64-bit value in the raised IR.

; CHECK-LABEL: define amdgpu_kernel void @s_mov_b64_src_shared_base_kernel(
; The inline asm reading src_shared_base must appear in the raised IR.
; CHECK: call i64 asm sideeffect "s_mov_b64 $0, src_shared_base"

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_mov_b64_src_shared_base_kernel
	.p2align	8
	.type	s_mov_b64_src_shared_base_kernel,@function
s_mov_b64_src_shared_base_kernel:
	; Read the shared memory aperture base into s[2:3].
	; On gfx9+: s[2] = lo (architecturally 0), s[3] = hi (actual base).
	s_mov_b64 s[2:3], src_shared_base
	; Use s[3] (hi = actual aperture hi 32 bits) as a store address so
	; the instruction survives DCE.
	v_mov_b32_e32 v0, s2
	v_mov_b32_e32 v1, s3
	global_store_b64 v[0:1], v[0:1], off
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_mov_b64_src_shared_base_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 8
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           s_mov_b64_src_shared_base_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         s_mov_b64_src_shared_base_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
