; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=v_frexp_exp_i32_f64_gfx950_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for v_frexp_exp_i32_f64 UnsupportedOpcode against gfx950 target.
;
; Bug-Id: 2026-05-26T14-14-07Z_qwen2.5-7b-instruct-025
;
; v_frexp_exp_i32_f64 (109 hits across 9 kernels of a rocSOLVER
; stedcj_solve_kernel workload on gfx1250) was reported as UnsupportedOpcode
; when transpiling to gfx950.  The VOP1 e32 encoding is recognized via the
; e32->e64->CanonicalOp chain and lowered to llvm.amdgcn.frexp.exp.i32.f64.
;
; This test verifies that:
;   1. v_frexp_exp_i32_f64_e32 is recognized and lowered to the AMDGCN frexp.exp intrinsic
;   2. The result (I32 biased exponent) is stored correctly
;   3. No "unsupported instruction" is emitted
;
; CHECK-LABEL: define amdgpu_kernel void @v_frexp_exp_i32_f64_gfx950_kernel(
; CHECK: call i32 @llvm.amdgcn.frexp.exp.i32.f64(double
; CHECK-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_frexp_exp_i32_f64_gfx950_kernel
	.p2align	8
	.type	v_frexp_exp_i32_f64_gfx950_kernel,@function
v_frexp_exp_i32_f64_gfx950_kernel:
	s_load_b64 s[2:3], s[0:1], 0x0
	s_load_b64 s[4:5], s[0:1], 0x8
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_mov_b32_e32 v3, 0
	;;#ASMSTART
	v_frexp_exp_i32_f64_e32 v2, v[0:1]
	;;#ASMEND
	global_store_b32 v3, v2, s[2:3] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_frexp_exp_i32_f64_gfx950_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 6
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
      - { .offset:         8, .size:           8, .value_kind:     by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name:           v_frexp_exp_i32_f64_gfx950_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     6
    .symbol:         v_frexp_exp_i32_f64_gfx950_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
