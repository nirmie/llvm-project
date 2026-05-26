; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=v_fma_f16_t16_neg_kernel 2>/dev/null \
; RUN:   | %FileCheck %s --check-prefix=NEG
; RUN: %raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=v_fma_f16_t16_neg_abs_kernel 2>/dev/null \
; RUN:   | %FileCheck %s --check-prefix=NEGABS
;
; Regression canary for bug 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-023:
; v_fma_f16 [VOP3] with neg/abs source modifiers on gfx1250 True16 encoding
; reported UnsupportedOpcode when transpiling gfx1250 -> gfx950.
;
; The rocblas_rot kernel used v_fma_f16 with negation (e.g. `v_fma_f16 v0.l,
; -v1.l, v2.l, v3.l`) which exercises the VOP3 source modifier path in
; handle-valu.cpp. The handler reads neg/abs bits from the MC operand's
; modifier flags and emits fneg/llvm.fabs before the llvm.fma.f16 call.
;
; 4 kernels hit this across 4 rocBLAS rot variants (f16 pointer + scalar args).
;
; This test verifies that gfx1250 True16 v_fma_f16 with VOP3 neg and abs source
; modifiers lowers correctly to fneg/fabs + llvm.fma.f16, without emitting any
; "unsupported instruction" diagnostic.

; NEG-LABEL: define amdgpu_kernel void @v_fma_f16_t16_neg_kernel(
; NEG: %neg_f16 = fneg half
; NEG: %fma_f16 = call half @llvm.fma.f16(half %neg_f16,
; NEG-NOT: unsupported instruction

; NEGABS-LABEL: define amdgpu_kernel void @v_fma_f16_t16_neg_abs_kernel(
; NEGABS: %neg_f16 = fneg half
; NEGABS: %abs_f16 = call half @llvm.fabs.f16(half
; NEGABS: %fma_f16 = call half @llvm.fma.f16(half %neg_f16, half {{.*}}, half %abs_f16)
; NEGABS-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_fma_f16_t16_neg_kernel
	.p2align	8
	.type	v_fma_f16_t16_neg_kernel,@function
v_fma_f16_t16_neg_kernel:
	v_fma_f16 v0.l, -v1.l, v2.l, v3.l
	s_endpgm

	.globl	v_fma_f16_t16_neg_abs_kernel
	.p2align	8
	.type	v_fma_f16_t16_neg_abs_kernel,@function
v_fma_f16_t16_neg_abs_kernel:
	v_fma_f16 v0.l, -v1.l, v2.l, |v3.l|
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_fma_f16_t16_neg_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 0
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.p2align	6, 0x0
	.amdhsa_kernel v_fma_f16_t16_neg_abs_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 0
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_fma_f16_t16_neg_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     0
    .symbol:         v_fma_f16_t16_neg_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_fma_f16_t16_neg_abs_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     0
    .symbol:         v_fma_f16_t16_neg_abs_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version: [1, 2]
...
	.end_amdgpu_metadata
