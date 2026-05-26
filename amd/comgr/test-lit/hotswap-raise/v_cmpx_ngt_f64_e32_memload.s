; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ngt_f64_e32_memload_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for false-positive CmpxFromLaneId on v_cmpx_ngt_f64_e32
; (VOP2/VOPC encoding, no explicit destination) when the cmpx operands are
; loaded from memory via global_load_b128.
;
; This is the e32 variant of v_cmpx_ngt_f64_memload.s, matching the exact
; encoding seen in rocBLAS lange_one_columns / lange_inf_rows kernels for
; rocblas_complex_num<double> (Bug-Id: 2026-05-23T19-19-07Z_qwen2.5-7b-instruct-019).
;
; The fix (tuple sub-register taint tracking in appendCanonicalRegLanes)
; correctly clears taint on all four sub-registers of the global_load_b128
; destination tuple v[2:5], so the subsequent v_cmpx_ngt_f64_e32 is NOT
; classified as CmpxFromLaneId.
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ngt_f64_e32_memload_kernel(

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ngt_f64_e32_memload_kernel
	.p2align	8
	.type	v_cmpx_ngt_f64_e32_memload_kernel,@function
v_cmpx_ngt_f64_e32_memload_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: create taint on v4 and v5 via mbcnt_lo -> cndmask
	v_mbcnt_lo_u32_b32 v6, -1, 0
	v_cmp_gt_u32_e64 vcc_lo, 30, v6
	v_cndmask_b32_e32 v4, 0, v6, vcc_lo
	v_cndmask_b32_e32 v5, 0, v6, vcc_lo
	; Step 2: global_load_b128 writes v[2:5] -- must clear taint on v4 AND v5
	global_load_b128 v[2:5], v[0:1], off
	s_wait_loadcnt 0x0
	; Step 3: v_cmpx_ngt_f64_e32 (VOPC) sources v[4:5] as src1, v[2:3] as src0
	; This should NOT be classified as CmpxFromLaneId.
	v_cmpx_ngt_f64_e32 v[2:3], v[4:5]
	global_store_b128 v[0:1], v[2:5], off
	s_wait_storecnt 0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ngt_f64_e32_memload_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 7
		.amdhsa_next_free_sgpr 2
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           v_cmpx_ngt_f64_e32_memload_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_ngt_f64_e32_memload_kernel.kd
    .vgpr_count:     7
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
