; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=v_frexp_exp_i32_f64_kernel 2>/dev/null | %FileCheck %s --check-prefix=IR
; RUN: %raise_cli %t.hsaco --target-isa=gfx942 --write-hsaco=%t.out --kernel=v_frexp_exp_i32_f64_kernel 2>&1 | %FileCheck %s --check-prefix=PIPE
;
; Lift test for v_frexp_exp_i32_f64 (VOP1 e32 encoding on gfx1250).
;
; v_frexp_exp_i32_f64 extracts the biased exponent from a F64 value,
; returning it as an I32.  It is defined in VOP1Instructions.td under
; VOP1_Real_gfx6_gfx7_gfx10_NO_DPP_gfx11_gfx13_with_DPP16_gfx12
; and on gfx1250 the disassembler produces the _gfx12 real MC opcode
; (V_FREXP_EXP_I32_F64_e32_gfx12).  The opcode-map collapses this
; through the e32->e64->CanonicalOp chain to V_FREXP_EXP_I32_F64.
;
; Regression target for UnsupportedOpcode failure observed in the
; rocSOLVER stedcj_solve kernel (float variant, 109 hits across 9 kernels).
; Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-025

; IR-LABEL: define amdgpu_kernel void @v_frexp_exp_i32_f64_kernel(
; IR: call i32 @llvm.amdgcn.frexp.exp.i32.f64(double
; IR-NOT: unsupported instruction

; PIPE: raise_cli: wrote
; PIPE-SAME: v_frexp_exp_i32_f64_kernel

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_frexp_exp_i32_f64_kernel
	.p2align	8
	.type	v_frexp_exp_i32_f64_kernel,@function
v_frexp_exp_i32_f64_kernel:
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
	.amdhsa_kernel v_frexp_exp_i32_f64_kernel
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
    .name:           v_frexp_exp_i32_f64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     6
    .symbol:         v_frexp_exp_i32_f64_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
