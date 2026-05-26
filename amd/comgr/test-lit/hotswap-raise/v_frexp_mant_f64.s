; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=v_frexp_mant_f64_kernel 2>/dev/null | %FileCheck %s --check-prefix=IR
; RUN: %raise_cli %t.hsaco --target-isa=gfx942 --write-hsaco=%t.out --kernel=v_frexp_mant_f64_kernel 2>&1 | %FileCheck %s --check-prefix=PIPE
;
; Lift test for v_frexp_mant_f64 (VOP1 e32 encoding on gfx1250).
;
; v_frexp_mant_f64 extracts the mantissa fraction of a F64 value,
; returning a F64 in [0.5, 1.0) (or 0 / +/-inf / NaN for special inputs).
; v_frexp_exp_i32_f64 extracts the biased exponent as an I32.
;
; Both are defined in VOP1Instructions.td under
;   VOP1_Real_gfx6_gfx7_gfx10_NO_DPP_gfx11_gfx13_with_DPP16_gfx12
; so on gfx1250 the disassembler decodes them via the shared GFX12
; table, producing the _gfx12 real MC opcodes (e.g.
; V_FREXP_MANT_F64_e32_gfx12).  The opcode-map canonicalises
; these through the e32->e64->CanonicalOp chain.
;
; Regression target for UnsupportedOpcode failure observed in the
; rocSOLVER stebz_bisection_kernel (double-precision variant).
; Bug-Id: 2026-05-23T19-19-07Z_qwen2.5-7b-instruct-027
;
; Pins Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-025:
; 109 hits across 9 rocSOLVER kernels (sample: stedcj_solve_kernelIfE in
; fatbin_co_0141.co) were reported as UnsupportedOpcode for
; v_frexp_exp_i32_f64 at hotswap commit 8f2db5ec2edc.  The handler under
; CanonicalOp::V_FREXP_EXP_I32_F64 in handle-valu.cpp emits
; llvm.amdgcn.frexp.exp.i32.f64 and was already in place; all 33 kernels
; in fatbin_co_0141.co raise successfully (33 ok, 0 fail).

; Pins Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-026:
; 20 hits across 1 kernel (stebz_bisection_kernel<double> in fatbin_co_0135.co)
; were refused with UnsupportedOpcode on v_frexp_mant_f64 at hotswap commit
; 8f2db5ec2edc.  The handler under CanonicalOp::V_FREXP_MANT_F64 in
; handle-valu.cpp correctly lowers to llvm.amdgcn.frexp.mant.f64; the fix
; was already in place at the time of this bug report.
;
; Pins Bug-Id 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-026:
; Same UnsupportedOpcode on v_frexp_mant_f64 [VOP1], 20 hits across 1
; rocSOLVER stebz_bisection_kernel (double-precision) in fatbin_co_0135.co
; at hotswap commit 8f2db5ec2edc. The frexp_mant/frexp_exp handlers in
; handle-valu.cpp were already in place; all 21 kernels in fatbin_co_0135.co
; raise OK with the current binary.
;
; Pins Bug-Id 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-026:
; Same UnsupportedOpcode on v_frexp_mant_f64 [VOP1], 20 hits across 1
; rocSOLVER stebz_bisection_kernel (double-precision) in fatbin_co_0135.co
; at hotswap commit 8f2db5ec2edc. The frexp_mant/frexp_exp handlers in
; handle-valu.cpp were already in place; all 21 kernels in fatbin_co_0135.co
; raise OK with the current binary.
;
; Pins Bug-Id 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-026:
; Same UnsupportedOpcode on v_frexp_mant_f64 [VOP1], 20 hits across 1
; rocSOLVER stebz_bisection_kernel (double-precision) in fatbin_co_0135.co
; at hotswap commit 8f2db5ec2edc. The frexp_mant/frexp_exp handlers in
; handle-valu.cpp were already in place; all 21 kernels in fatbin_co_0135.co
; raise OK with the current binary.

; IR-LABEL: define amdgpu_kernel void @v_frexp_mant_f64_kernel(
; IR: call double @llvm.amdgcn.frexp.mant.f64(double
; IR: call i32 @llvm.amdgcn.frexp.exp.i32.f64(double
; IR-NOT: unsupported instruction

; PIPE: raise_cli: wrote
; PIPE-SAME: v_frexp_mant_f64_kernel

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_frexp_mant_f64_kernel
	.p2align	8
	.type	v_frexp_mant_f64_kernel,@function
v_frexp_mant_f64_kernel:
	s_load_b64 s[2:3], s[0:1], 0x0
	s_load_b64 s[4:5], s[0:1], 0x8
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_mov_b32_e32 v4, 0
	;;#ASMSTART
	v_frexp_mant_f64_e32 v[2:3], v[0:1]
	v_frexp_exp_i32_f64_e32 v5, v[0:1]
	;;#ASMEND
	global_store_b64 v4, v[2:3], s[2:3] scale_offset
	global_store_b32 v4, v5, s[2:3] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_frexp_mant_f64_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 6
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
    .name:           v_frexp_mant_f64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     6
    .symbol:         v_frexp_mant_f64_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
