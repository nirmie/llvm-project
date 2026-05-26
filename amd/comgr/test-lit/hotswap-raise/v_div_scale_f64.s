; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=v_div_scale_f64_kernel 2>/dev/null | %FileCheck %s
;
; Lift test for v_div_scale_f64. Pins that the VOP3 F64 IEEE-divide scale
; instruction lowers to `llvm.amdgcn.div.scale.f64`, and that the
; scale-numerator (src0==src2) and scale-denominator (src0==src1) operand
; shapes are decoded correctly.  The handler lives in
; src/hotswap/handle-valu.cpp under
; `if (Sop == CanonicalOp::V_DIV_SCALE_F64) { ... }`.
;
; Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-022

; CHECK-LABEL: define amdgpu_kernel void @v_div_scale_f64_kernel(

; Scale-numerator call: (n, d, n) shape → flag=true.
; CHECK: call { double, i1 } @llvm.amdgcn.div.scale.f64(double {{.*}}, double {{.*}}, i1 true)

; Scale-denominator call: (d, d, n) shape → flag=false.
; CHECK: call { double, i1 } @llvm.amdgcn.div.scale.f64(double {{.*}}, double {{.*}}, i1 false)

; Intrinsic declaration must be present (proves the calls use the right overload).
; CHECK-DAG: declare {{.*}}{ double, i1 } @llvm.amdgcn.div.scale.f64(double, double, i1 immarg)

; Pins Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-022:
; 1612 hits across 1037 kernels (sample: rocblas_trtri_small_kernel<16,double>
; in fatbin_co_0008.co) were refused with UnsupportedOpcode on v_div_scale_f64
; at hotswap commit 8f2db5ec2edc.  The VOP3b handler in handle-valu.cpp under
; CanonicalOp::V_DIV_SCALE_F64 decodes the (src0==src2) numerator-scale and
; (src0==src1) denominator-scale operand shapes and lowers both to
; llvm.amdgcn.div.scale.f64 with the correct immarg flag.
;
; Pins Bug-Id 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-022:
; Same workload re-reported: 1612 hits across 1037 rocBLAS trtri kernels
; (fatbin_co_0008.co) at hotswap commit 8f2db5ec2edc. The handler remains in
; place; all 32 kernels in the .co raise OK, confirming the fix is effective.
;
; Pins Bug-Id 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-022:
; Same workload re-reported again: 1612 hits across 1037 rocBLAS trtri kernels
; (fatbin_co_0008.co) at hotswap commit 8f2db5ec2edc. The VOP3b handler in
; handle-valu.cpp under CanonicalOp::V_DIV_SCALE_F64 remains in place; all
; 32 kernels raise OK, confirming the fix is effective.
;
; Pins Bug-Id 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-022:
; Same workload re-reported again: 1612 hits across 1037 rocBLAS trtri kernels
; (fatbin_co_0008.co) at hotswap commit 8f2db5ec2edc. The VOP3b handler in
; handle-valu.cpp under CanonicalOp::V_DIV_SCALE_F64 remains in place; all
; 32 kernels raise OK, confirming the fix is effective.

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_div_scale_f64_kernel
	.p2align	8
	.type	v_div_scale_f64_kernel,@function
v_div_scale_f64_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_clause 0x1
	s_load_b32 s2, s[0:1], 0x1c
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_xcnt 0x0
	s_bfe_u32 s0, ttmp6, 0x4000c
	s_and_b32 s1, ttmp6, 15
	s_add_co_i32 s0, s0, 1
	s_getreg_b32 s3, hwreg(HW_REG_IB_STS2, 6, 4)
	s_mul_i32 s0, ttmp9, s0
	s_delay_alu instid0(SALU_CYCLE_1) | instskip(SKIP_4) | instid1(SALU_CYCLE_1)
	s_add_co_i32 s1, s1, s0
	s_wait_kmcnt 0x0
	s_and_b32 s2, s2, 0xffff
	s_cmp_eq_u32 s3, 0
	s_cselect_b32 s0, ttmp9, s1
	v_mad_u32 v4, s0, s2, v0
	global_load_b64 v[0:1], v4, s[6:7] scale_offset
	global_load_b64 v[2:3], v4, s[6:7] scale_offset
	s_wait_loadcnt 0x0
	;;#ASMSTART
	; Scale-numerator shape: (n, d, n) → src0 == src2, flag=true.
	v_div_scale_f64 v[6:7], vcc_lo, v[0:1], v[2:3], v[0:1]
	; Scale-denominator shape: (d, d, n) → src0 == src1, flag=false.
	v_div_scale_f64 v[8:9], null, v[2:3], v[2:3], v[0:1]

	;;#ASMEND
	global_store_b64 v4, v[6:7], s[4:5] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_div_scale_f64_kernel
		.amdhsa_kernarg_size 272
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 10
		.amdhsa_next_free_sgpr 8
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
      - { .address_space:  global, .offset:         8, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 272
    .max_flat_workgroup_size: 1024
    .name:           v_div_scale_f64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         v_div_scale_f64_kernel.kd
    .vgpr_count:     10
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
