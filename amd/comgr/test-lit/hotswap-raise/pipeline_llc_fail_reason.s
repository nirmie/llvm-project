; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=float_arith_kernel 2>/dev/null | %FileCheck %s
;
; Regression guard for the pipeline diagnostic fix: when llc or llvm-mc fails
; (e.g. due to timeout under heavy load), the PipelineResult now records
; FailReason=llc_timeout/llc_failed/llvm_mc_failed instead of empty_output,
; making failures diagnosable.
;
; This test ensures the full pipeline (raise -> llc -> llvm-mc -> ld.lld) runs
; to completion for a floating-point kernel without regressing to empty_output.
; It was introduced after co_0094 from the 2026-05-27T14-22-48Z run failed with
; "empty_output" when llc timed out on getf2_small_kernel<30,float>.

; CHECK-LABEL: define amdgpu_kernel void @float_arith_kernel(
; CHECK: fadd float
; CHECK: fmul float
; CHECK-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	float_arith_kernel
	.p2align	8
	.type	float_arith_kernel,@function
float_arith_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_add_f32 v0, v0, v1
	v_mul_f32 v0, v0, v2
	global_store_b32 v[2:3], v0, off
	s_endpgm
.Lfloat_arith_kernel_end:
	.size	float_arith_kernel, .Lfloat_arith_kernel_end-float_arith_kernel
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel float_arith_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 2
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
    .name:           float_arith_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         float_arith_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
