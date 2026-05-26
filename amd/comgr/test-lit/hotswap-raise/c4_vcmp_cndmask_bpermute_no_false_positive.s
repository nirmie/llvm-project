; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=c4_vcmp_cndmask_bpermute_no_false_positive_kernel 2>&1 \
; RUN:   | %FileCheck %s
;
; Regression guard for the false-positive taint chain that previously caused
; a spurious CmpxFromLaneId / SaveExecFromLaneId refusal in rocBLAS
; iamax/iamin kernels (bug 2026-05-23T19-19-07Z_qwen2.5-7b-instruct-017).
;
; The taint chain under the old classifier:
;
;   v_mbcnt_lo_u32_b32 v4, -1, 0         ; lane rank → v4 TAINTED
;   v_cmp_gt_u32_e32 vcc_lo, 24, v4      ; bounds check: VCC TAINTED (old)
;   v_dual_cndmask_b32 v5, v0, v1, vcc_lo  ; VCC predicate tainted → v5 TAINTED (old)
;   ds_bpermute_b32 v6, v7, v5           ; DATA0=v5 → v6 TAINTED (old)
;   ds_bpermute_b32 v8, v7, v5           ; DATA0=v5 → v8 TAINTED (old)
;   v_cmpx_ne_u64 v[6:7], v[8:9]         ; false CmpxFromLaneId (old bug)
;
; Correctness argument:
;
;   * v_cmp_gt_u32 outputs a boolean per-lane predicate, NOT a raw lane-ID.
;     The same lanes satisfy the same bounds test regardless of wave width.
;     V_CMP must NOT propagate mbcnt taint through its comparison output.
;
;   * v_dual_cndmask_b32 uses VCC as the *selection predicate*, not as a
;     data source.  The output carries src0 or src1 (data values), not a
;     lane-ID, even if VCC was derived from an mbcnt comparison.  VCC taint
;     must NOT propagate into vDST for cndmask.
;
;   * ds_bpermute_b32 already clears taint from its ADDR operand (only DATA0
;     matters for the destination value).  After the two fixes above, DATA0
;     is clean, so the destination is clean too.
;
;   * v_cmpx_ne_u64 compares shuffled data values, not lane-index-derived
;     values.  It must NOT be classified as CmpxFromLaneId.
;
; The kernel should raise successfully (no cross-wave-lane-predicated-exec).

; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK-NOT: CmpxFromLaneId
; CHECK-NOT: SaveExecFromLaneId
; CHECK-LABEL: define amdgpu_kernel void @c4_vcmp_cndmask_bpermute_no_false_positive_kernel(
; The cndmask should lower to a `select` (not a raw cndmask intrinsic), with
; the condition coming from the bounds-check icmp.
; CHECK: [[BOUNDS_CMP:%[[:alnum:]_.]+]] = icmp ugt i32 24,
; CHECK: %vopd_cndmask = select i1 [[BOUNDS_CMP]],
; The v_cmpx_ne_u64 should lower to an icmp + ballot (not a cross-wave refusal).
; CHECK: = icmp ne i64
; CHECK: = call i64 @llvm.amdgcn.ballot.i64

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	c4_vcmp_cndmask_bpermute_no_false_positive_kernel
	.p2align	8
	.type	c4_vcmp_cndmask_bpermute_no_false_positive_kernel,@function
c4_vcmp_cndmask_bpermute_no_false_positive_kernel:
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Load two data values per lane (the "current" and "candidate" in an iamax reduction)
	global_load_b64 v[0:1], v0, s[0:1]
	global_load_b64 v[2:3], v0, s[0:1] offset:8
	s_wait_loadcnt 0x0
	; Compute lane rank within the source wave (wave32: lane 0..31)
	v_mbcnt_lo_u32_b32 v4, -1, 0
	; Bounds check: select between current and candidate based on whether this
	; lane's rank is below 24 (a compile-time reduction threshold, NOT a lane-
	; ID comparison that gates EXEC in a wave-size-sensitive way).
	v_cmp_gt_u32_e32 vcc_lo, 24, v4
	; VOPD: select data value (not a lane index) using the bounds-check predicate.
	; VCC is the selection predicate; the output carries v0 or v2 (data), not a
	; lane-ID, even though VCC was derived from an mbcnt comparison.
	v_dual_cndmask_b32 v5, v0, v2, vcc_lo :: v_dual_add_nc_u32 v6, 1, v4
	; Build a bpermute address (lane_rank * 4 gives a byte offset within LDS)
	v_lshlrev_b32_e32 v7, 2, v4
	; Shuffle: gather the selected data value from a peer lane via ds_bpermute.
	; ADDR (v7) is derived from v_mbcnt but only selects *which* lane's DATA0
	; to return; the returned value is whatever DATA0 holds, not a lane index.
	ds_bpermute_b32 v8, v7, v5
	s_wait_dscnt 0x0
	; Also shuffle the high half.
	ds_bpermute_b32 v9, v7, v1
	s_wait_dscnt 0x0
	; Compare the two gathered values for inequality.  The operands are data
	; values (not lane-index-derived), so this v_cmpx must NOT be classified
	; as CmpxFromLaneId.
	v_cmpx_ne_u64 v[8:9], v[0:1]
	global_store_b64 v[8:9], v[8:9], off
	s_wait_storecnt 0
	s_mov_b32 exec_lo, -1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel c4_vcmp_cndmask_bpermute_no_false_positive_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 10
		.amdhsa_next_free_sgpr 2
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
    .name:           c4_vcmp_cndmask_bpermute_no_false_positive_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         c4_vcmp_cndmask_bpermute_no_false_positive_kernel.kd
    .vgpr_count:     10
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
