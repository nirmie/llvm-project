; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ne_u64_bpermute_taint_clear_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for false-positive CmpxFromLaneId on v_cmpx_ne_u64 when
; a pair of VGPRs that was transiently tainted by v_mbcnt_* is subsequently
; overwritten by untainted values and then used as ds_bpermute_b32 DATA.
;
; Root cause pattern (from rocBLAS iamax/iamin kernels, bug
; 2026-05-25T22-08-35Z_qwen2.5-7b-instruct-016):
;
;   1. v_mbcnt_lo -> v8 (TAINTED)
;   2. v_add_co_ci_u32_e64 v13, null, 0, v8, vcc  -> v13 TAINTED (from v8)
;   3. v_mov_b64_e32 v[12:13], 0                   -> v[12:13] cleared (NOT TAINTED)
;   4. global_load + v_add -> v[12:13] = untainted values
;   5. v_lshl_or_b32 v15, v8, 2, 64               -> v15 TAINTED (addr for bpermute)
;   6. ds_bpermute_b32 v14, v15, v12               -> v14 NOT TAINTED (DATA=v12 clean)
;   7. ds_bpermute_b32 v15, v15, v13               -> v15 NOT TAINTED (DATA=v13 clean
;                                                      after step 3 cleared the taint)
;   8. v_cmpx_ne_u64_e32 0, v[14:15]              -> must NOT be flagged as CmpxFromLaneId
;
; The 64-bit compare sources a VGPR PAIR (v[14:15]) via two separate ds_bpermute_b32
; instructions. The taint tracker must correctly track that both v14 and v15 are
; untainted after the bpermutes use untainted DATA operands -- even if the shared ADDR
; register (v15/v_addr) is lane-ID-derived.
;
; Without the forward-branch-aware snapshot restore fix, a stale snapshot containing
; the transient taint of v13 (from step 2) could be restored at the loop header,
; causing v13 to appear tainted for the second bpermute's DATA, which in turn taints
; v15 and causes a spurious CmpxFromLaneId refusal.
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ne_u64_bpermute_taint_clear_kernel(
; CHECK-NOT: cross-wave-lane-predicated-exec

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ne_u64_bpermute_taint_clear_kernel
	.p2align	8
	.type	v_cmpx_ne_u64_bpermute_taint_clear_kernel,@function
v_cmpx_ne_u64_bpermute_taint_clear_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: v_mbcnt_lo produces lane ID in v8 (TAINTED).
	v_mbcnt_lo_u32_b32 v8, -1, 0

	; Step 2: v13 = 0 + v8 + VCC-carry (TAINTED from v8).
	v_cmp_ne_u32_e32 vcc_lo, 31, v8
	v_add_co_ci_u32_e64 v13, null, 0, v8, vcc_lo

	; Step 3: Clear v[12:13] taint by overwriting with immediate 0.
	;         This is the key fix: v13 was tainted in step 2, but
	;         v_mov_b64_e32 overwrites BOTH v12 and v13 with untainted 0.
	v_mov_b64_e32 v[12:13], 0

	; Step 4: Load untainted values and assign to v[12:13].
	global_load_b64 v[10:11], v[0:1], off
	s_wait_loadcnt 0x0
	v_add_nc_u64_e32 v[12:13], 1, v[10:11]

	; Step 5: Compute tainted ADDR for bpermute from lane ID.
	v_lshl_or_b32 v16, v8, 2, 64

	; Step 6: Two ds_bpermute_b32 gather the 64-bit pair via TAINTED ADDR,
	;         but DATA (v12 and v13) is NOT TAINTED.
	;         v14 and v15 should NOT be tainted after these.
	ds_bpermute_b32 v14, v16, v12
	ds_bpermute_b32 v15, v16, v13
	s_wait_dscnt 0x0

	; Step 7: v_cmpx_ne_u64 sources the 64-bit pair v[14:15].
	;         Must NOT be flagged as CmpxFromLaneId since v[14:15]
	;         flows through bpermute DATA (not ADDR).
	v_cmpx_ne_u64_e32 0, v[14:15]
	global_store_b64 v[0:1], v[10:11], off
	s_wait_storecnt 0
	s_mov_b32 exec_lo, -1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ne_u64_bpermute_taint_clear_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 17
		.amdhsa_next_free_sgpr 3
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
    .name:           v_cmpx_ne_u64_bpermute_taint_clear_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     3
    .symbol:         v_cmpx_ne_u64_bpermute_taint_clear_kernel.kd
    .vgpr_count:     17
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
