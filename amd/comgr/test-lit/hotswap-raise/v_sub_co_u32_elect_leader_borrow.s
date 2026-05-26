; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_sub_co_u32_elect_leader_borrow_kernel 2>/dev/null | %FileCheck %s
;
; Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-014
;
; Regression test for the v_sub_co_u32 elect-leader borrow idiom followed by a
; lane-iteration s_and_not1_saveexec_b32 pattern.
;
; The elect-leader idiom uses:
;   v_mbcnt_lo_u32_b32 vT, -1, 0     ; vT = abs lane rank (0 for first active lane)
;   v_sub_co_u32 vD, sB, vT, 1       ; borrow sB = ballot(vT < 1) = ballot(vT == 0)
;   s_and_saveexec_b32 sS, sB         ; gate: only first-active-lane proceeds
;
; The borrow sB is the elect-leader mask; s_and_saveexec_b32 whose source is sB
; is the elect-leader gate (IsElectLeader=true).  Under WaveNative the gate is
; wave-size-independent; propagating exec taint from this saveexec into
; downstream s_mov/s_xor chains caused the subsequent s_and_not1_saveexec_b32
; (lane-iteration idiom) to be misclassified as SaveExecFromLaneId
; (cross-wave-lane-predicated-exec), which was a false positive.
;
; The fix suppresses exec-taint propagation for elect-leader saveexec sites
; (IsElectLeader=true), so the lane-iteration s_and_not1_saveexec_b32 that
; follows is no longer flagged.
;
; We verify the kernel raises cleanly to IR (no UnsupportedOpcode / FAIL).
; The s_and_not1_saveexec_b32 at the end must produce a phi for the updated
; exec SSA value, proving the lane-iteration is correctly lowered.
;
; CHECK-LABEL: define amdgpu_kernel void @v_sub_co_u32_elect_leader_borrow_kernel(

; The elect-leader gate defines a new_exec SSA value.
; CHECK: %new_exec{{.*}} = and i64

; The lane-iteration s_and_not1_saveexec_b32 must also emit a new exec value.
; CHECK: %new_exec{{[0-9_]*}} = and i64

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_sub_co_u32_elect_leader_borrow_kernel
	.p2align	8
	.type	v_sub_co_u32_elect_leader_borrow_kernel,@function
v_sub_co_u32_elect_leader_borrow_kernel:
	;;#ASMSTART
	; Elect-leader idiom: vT = abs lane rank, sB = ballot(lane == 0).
	v_mbcnt_lo_u32_b32 v2, -1, 0
	v_sub_co_u32 v3, s2, v2, 1
	s_and_saveexec_b32 s3, s2

	; Inside the elect-leader gate: do some scalar work and restore exec.
	s_or_b32 exec_lo, exec_lo, s3

	; Lane-iteration idiom: iterate over disjoint groups of lanes.
	; s_and_not1_saveexec_b32 should NOT be flagged as cross-wave-lane-
	; predicated-exec because exec is clean (elect-leader gate taint suppressed).
	s_mov_b32 s3, exec_lo
	v_cmpx_lt_i32_e32 6, v0
	s_xor_b32 s3, exec_lo, s3
	s_and_not1_saveexec_b32 s3, s3
	s_or_b32 exec_lo, exec_lo, s3
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_sub_co_u32_elect_leader_borrow_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 4
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
    .name:           v_sub_co_u32_elect_leader_borrow_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         v_sub_co_u32_elect_leader_borrow_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
