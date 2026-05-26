; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=c4_saveexec_vcmp_sgpr_no_false_positive_kernel 2>&1 \
; RUN:   | %FileCheck %s
;
; Regression for Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-007.
;
; 156 kernels in rocblas fatbin_co_0012.co were incorrectly refused with
; cross-wave-lane-predicated-exec on s_and_saveexec_b32.  The sample kernel
; is _ZL23rocblas_gemvt_sn_reduceILi256ELi8EfPKf16rocblas_bfloat16Evi...
;
; Root cause: the taint tracker in findLanePredicatedExecSites() previously
; propagated mbcnt-derived taint through V_CMP (non-cmpx) results written to
; SGPRs.  In the rocblas reduce kernel the pattern is:
;
;   1. v_mbcnt_lo_u32_b32 v_rank, -1, 0   -- absolute lane rank in v_rank
;   2. v_cmp_gt_u32_e32 vcc_lo, K, v_rank  -- bounds-check: VCC <- (v_rank < K)
;                                            -- VCC is a boolean, NOT a lane-ID
;   3. (intervening instructions using VCC and v_rank)
;   4. v_cmp_gt_i32_e64 s_mask, s_bound, v_col  -- range predicate into SGPR
;                                            -- s_mask is a boolean, NOT a lane-ID
;   5. s_and_saveexec_b32 s_old, s_mask    -- EXEC narrowed to active column lanes
;
; The V_CMP at step 2 and step 4 output a per-lane boolean predicate (one bit
; per lane), not a raw lane-ID value.  The same lanes satisfy the same scalar
; comparison regardless of wave width, so the SGPR / VCC result is wave-size-
; independent.  Propagating mbcnt taint through V_CMP into the comparison
; result caused the s_and_saveexec at step 5 to be falsely classified as
; SaveExecFromLaneId (Class 4: lane-predicated EXEC).
;
; Fix (commit 51658b96e47c): V_CMP always sets ExplicitDefsTainted = false.
;
; Pattern under test:
;   v_mbcnt_lo_u32_b32 v1, -1, 0        -- lane rank -> v1 TAINTED
;   v_cmp_gt_u32_e32 vcc_lo, 24, v1     -- V_CMP: vcc NOT tainted (boolean output)
;   v_cmp_gt_i32_e64 s2, s0, v1         -- V_CMP into SGPR: s2 NOT tainted
;   s_and_saveexec_b32 s3, s2           -- source s2 not tainted -> NOT C4
;
; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK-LABEL: define amdgpu_kernel void @c4_saveexec_vcmp_sgpr_no_false_positive_kernel(

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	c4_saveexec_vcmp_sgpr_no_false_positive_kernel
	.p2align	8
	.type	c4_saveexec_vcmp_sgpr_no_false_positive_kernel,@function
c4_saveexec_vcmp_sgpr_no_false_positive_kernel:
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: compute absolute lane rank in v1 (mbcnt-tainted)
	v_mbcnt_lo_u32_b32 v1, -1, 0
	; Step 2: V_CMP bounds-check -- output goes to VCC (a boolean, NOT a lane-ID)
	; V_CMP must NOT propagate mbcnt taint through its comparison result.
	v_cmp_gt_u32_e32 vcc_lo, 24, v1
	; Step 3: V_CMP bounds-check with SGPR destination -- s2 is a boolean mask
	; Even though v1 is mbcnt-derived, s2 must NOT be tainted.
	v_cmp_gt_i32_e64 s2, s0, v1
	; Step 4: s_and_saveexec_b32 -- source is s2 (non-tainted boolean predicate)
	; This must NOT be flagged as SaveExecFromLaneId / cross-wave-lane-predicated-exec.
	s_and_saveexec_b32 s3, s2
	; Conditional store under narrowed EXEC
	global_store_b32 v0, v1, s[0:1]
	s_wait_storecnt 0
	; Restore EXEC
	s_mov_b32 exec_lo, s3
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel c4_saveexec_vcmp_sgpr_no_false_positive_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 4
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .address_space:  global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           c4_saveexec_vcmp_sgpr_no_false_positive_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         c4_saveexec_vcmp_sgpr_no_false_positive_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
