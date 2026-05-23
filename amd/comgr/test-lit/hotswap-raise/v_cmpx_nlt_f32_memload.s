; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_nlt_f32_memload_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test: v_cmpx_nlt_f32 whose operands come from memory loads must
; NOT be classified as CmpxFromLaneId (cross-wave-lane-predicated-exec refusal).
;
; Root cause (Bug-Id: 2026-05-22T00-58-06Z_qwen2.5-7b-instruct-019): the
; wave-size-obstruction taint tracker incorrectly propagated lane-ID taint
; (from v_mbcnt_lo) through multi-word tuple loads (global_load_b64) when the
; sub-register index walk used a sequential loop that missed sub-registers with
; non-consecutive enum values (e.g. sub1=11 but sub2=21).  This left high
; words of loaded tuples tainted; a subsequent v_cmpx_nlt_f32 sourcing the
; high word was falsely flagged.
;
; Pattern (distilled from rocSOLVER geqr2_kernel_small, gfx1250, 226 hits):
;   1. v_mbcnt_lo -> taint on v2
;   2. v_cndmask writes v3 from v2 -> v3 is tainted
;   3. global_load_b64 writes v[2:3] -> BOTH v2 and v3 must be cleared
;   4. v_cmpx_nlt_f32 sources v3 -> must NOT be flagged as CmpxFromLaneId
;
; v_cmpx_nlt_f32 (NLT = not-less-than) lowers to fcmp uge (unordered-or-GE).
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_nlt_f32_memload_kernel(
; CHECK: fcmp uge float
; CHECK: {{cmpx_ballot[^ ]*}} = call i{{32|64}} @llvm.amdgcn.ballot.i{{32|64}}(i1

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_nlt_f32_memload_kernel
	.p2align	8
	.type	v_cmpx_nlt_f32_memload_kernel,@function
v_cmpx_nlt_f32_memload_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: create taint on v2 via mbcnt_lo
	v_mbcnt_lo_u32_b32 v2, -1, 0
	; Step 2: v_cndmask propagates taint to v3
	v_cmp_gt_u32_e64 vcc_lo, 30, v2
	v_cndmask_b32_e32 v3, 0, v2, vcc_lo
	; Step 3: global_load_b64 writes v[2:3] -- MUST clear taint on both v2 and v3
	global_load_b64 v[2:3], v[0:1], off
	s_wait_loadcnt 0x0
	; Step 4: v_cmpx_nlt_f32 sources v3 -- must NOT be flagged as CmpxFromLaneId
	;         NLT = "not less than" = unordered-or-greater-or-equal (FCMP_UGE)
	v_cmpx_nlt_f32_e64 v2, v3
	global_store_b64 v[0:1], v[2:3], off
	s_wait_storecnt 0
	s_mov_b32 exec_lo, -1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_nlt_f32_memload_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
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
    .name:           v_cmpx_nlt_f32_memload_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_nlt_f32_memload_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
