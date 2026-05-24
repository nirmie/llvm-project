; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=c4_saveexec_forward_branch_kernel 2>&1 \
; RUN:   | %FileCheck %s
;
; Regression for the forward-branch false positive in the C4
; SaveExecFromLaneId classifier.  The taint tracker must not propagate
; mbcnt-derived taint through a block that is skipped by an unconditional
; forward branch.
;
; Scenario (mirrors the rocblas gemvt false positive):
;   1. v_mbcnt_lo produces a lane-ID-derived value in v2.
;   2. v_cmp_ne puts a mbcnt-tainted mask in s2.
;   3. s_branch forwards over the loop back-edge block.
;   4. [skipped] s_or_b32 exec_lo, exec_lo, s2  <- would taint exec_lo
;   5. [branch target] s_and_saveexec_b32 s4, s6  <- source is s6, NOT s2
;   6. s_and_not1_saveexec_b32 s5, s4  <- should NOT be flagged
;
; Without the fix, the taint from step 4 (skipped block) flows into exec_lo,
; which then propagates to s4 in step 5, causing step 6 to fire falsely.
; With the fix, the snapshot is restored at the branch target, discarding
; the spurious exec_lo taint.

; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK-LABEL: define amdgpu_kernel void @c4_saveexec_forward_branch_kernel(

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	c4_saveexec_forward_branch_kernel
	.p2align	8
	.type	c4_saveexec_forward_branch_kernel,@function
c4_saveexec_forward_branch_kernel:
	;;#ASMSTART
	; Step 1: produce mbcnt-derived lane id in v2
	v_mbcnt_lo_u32_b32 v2, -1, 0
	; Step 2: compare lane id to 31 -> tainted mask in s2
	v_cmp_ne_u32_e64 s2, 31, v2
	; Step 3: unconditional forward branch — skips the back-edge block below
	s_branch .Lbranch_target
	; Step 4 [SKIPPED]: this block is only reached via loop back-edge in the
	; real kernel; the forward branch above skips it entirely.  Without the fix,
	; the linear taint tracker would walk through this and taint exec_lo via s2.
	s_or_b32 exec_lo, exec_lo, s2
.Lbranch_target:
	; Step 5: s_and_saveexec_b32 — source is s6 (not s2, not exec-tainted)
	s_mov_b32 s6, 0xff00ff00
	s_and_saveexec_b32 s4, s6
	; Step 6: s_and_not1_saveexec_b32 — if exec_lo were wrongly tainted this fires
	s_xor_b32 s5, exec_lo, s4
	s_and_not1_saveexec_b32 s5, s5
	s_mov_b32 exec_lo, s4
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel c4_saveexec_forward_branch_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 3
		.amdhsa_next_free_sgpr 7
		.amdhsa_float_denorm_mode_32 3
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:           []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           c4_saveexec_forward_branch_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     7
    .symbol:         c4_saveexec_forward_branch_kernel.kd
    .vgpr_count:     3
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
