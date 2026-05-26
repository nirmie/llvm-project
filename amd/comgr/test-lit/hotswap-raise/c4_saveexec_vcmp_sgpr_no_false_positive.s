; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=c4_saveexec_vcmp_sgpr_no_false_positive_kernel 2>&1 \
; RUN:   | %FileCheck %s
;
; Regression for Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-007.
;
; 156 kernels in rocblas fatbin_co_0012.co (e.g.
; _ZL23rocblas_gemvt_sn_reduceILi256ELi8EfPKf16rocblas_bfloat16Evi...)
; were incorrectly refused with cross-wave-lane-predicated-exec on
; s_and_saveexec_b32.
;
; Root cause: the taint tracker in findLanePredicatedExecSites() propagated
; mbcnt-derived taint through V_CMP (non-cmpx) results written to SGPRs/VCC.
; In the rocblas gemvt_sn_reduce kernel the pattern is:
;
;   1. v_mbcnt_lo_u32_b32 v_rank, -1, 0    -- absolute lane rank in v_rank
;   2. v_cmp_gt_u32_e32 vcc_lo, K, v_rank  -- bounds-check: VCC <- (v_rank < K)
;                                            -- VCC is a boolean, NOT a lane-ID
;   3. v_cmp_gt_i32_e64 s_mask, s_bound, v_col  -- range predicate into SGPR
;                                            -- s_mask is a boolean, NOT a lane-ID
;   4. s_and_saveexec_b32 s_old, s_mask    -- EXEC narrowed to active column lanes
;
; V_CMP outputs a per-lane boolean predicate (one bit per lane), not a raw
; lane-ID.  The same lanes satisfy the same scalar comparison regardless of
; wave width, so the SGPR/VCC result is wave-size-independent.  Propagating
; mbcnt taint through V_CMP into the comparison result caused the
; s_and_saveexec at step 4 to be falsely classified as SaveExecFromLaneId.
;
; Fix (commit 51658b96e47c): V_CMP always sets ExplicitDefsTainted = false.
;
; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK-LABEL: define amdgpu_kernel void @c4_saveexec_vcmp_sgpr_no_false_positive_kernel(
; CHECK: %new_exec = and i64

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	c4_saveexec_vcmp_sgpr_no_false_positive_kernel
	.p2align	8
	.type	c4_saveexec_vcmp_sgpr_no_false_positive_kernel,@function
c4_saveexec_vcmp_sgpr_no_false_positive_kernel:
	s_clause 0x1
	s_load_b64 s[2:3], s[0:1], 0x0
	s_load_b32 s4, s[0:1], 0x8
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: compute absolute lane rank in v1 (mbcnt-derived)
	v_mbcnt_lo_u32_b32 v1, -1, 0
	; Step 2: bounds check -- VCC = (v1 < 24), a boolean NOT a lane-ID
	; The V_CMP output is wave-size-independent and must NOT carry taint.
	v_cmp_gt_u32_e32 vcc_lo, 24, v1
	; Step 3: range predicate into SGPR -- s5 is a boolean, NOT a lane-ID
	v_cmp_gt_i32_e64 s5, s4, v0
	; Step 4: s_and_saveexec using SGPR predicate -- must NOT be SaveExecFromLaneId
	s_and_saveexec_b32 s0, s5
	; Gated store
	v_mov_b32_e32 v2, 1
	global_store_b32 v1, v2, s[2:3] scale_offset
	s_wait_storecnt 0
	; Restore EXEC
	s_mov_b32 exec_lo, s0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel c4_saveexec_vcmp_sgpr_no_false_positive_kernel
		.amdhsa_kernarg_size 280
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
      - { .offset:         8, .size:           4, .value_kind:     by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 280
    .max_flat_workgroup_size: 1024
    .name:           c4_saveexec_vcmp_sgpr_no_false_positive_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     6
    .symbol:         c4_saveexec_vcmp_sgpr_no_false_positive_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
