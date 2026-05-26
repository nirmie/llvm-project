; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ne_u32_bpermute_data_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for false-positive CmpxFromLaneId / SaveExecFromLaneId on
; v_cmpx_ne_u32 / s_and_saveexec_b32 when the EXEC-writing instruction's
; operands flow through ds_bpermute_b32 DATA (not ADDR).
;
; Root cause: the IsMemLoad guard in findLanePredicatedExecSites() was absent,
; so ds_bpermute_b32's def register inherited taint from the lane-ID-derived
; ADDR operand.  The DATA operand (the actual value being permuted) is
; independent of lane position, so the def is not lane-ID-tainted.
;
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-015
;   20 hit(s) across 20 rocBLAS iamax/iamin kernels (fatbin_co_0041.co).
; Also covers Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-015
;   20 hit(s) across 20 rocBLAS iamax/iamin kernels (fatbin_co_0041.co).
;
; Pattern from rocBLAS iamax/iamin kernels:
;   1. v_mbcnt_lo -> lane_id -> v_lshl_or_b32 -> addr_reg  (addr is tainted)
;   2. ds_bpermute_b32 dst, addr_reg, data_reg              (data is NOT tainted)
;   3. v_cmpx_ne_u32 0, dst                                 (must NOT be flagged)
;   4. s_and_saveexec_b32 sN, sM                            (must NOT be flagged)
;
; Without the fix the kernel refuses with:
;   cross-wave-lane-predicated-exec on 'v_cmpx_ne_u32'
; With the fix, the kernel raises successfully.
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ne_u32_bpermute_data_kernel(
; CHECK-NOT: cross-wave-lane-predicated-exec

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ne_u32_bpermute_data_kernel
	.p2align	8
	.type	v_cmpx_ne_u32_bpermute_data_kernel,@function
v_cmpx_ne_u32_bpermute_data_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: v_mbcnt_lo produces lane ID in v8 (TAINTED).
	v_mbcnt_lo_u32_b32 v8, -1, 0
	; Step 2: compute ds_bpermute ADDR from lane ID -- v15 is TAINTED.
	v_lshl_or_b32 v15, v8, 2, 64
	; Step 3: load data value into v6 from memory (data is NOT lane-ID-derived).
	global_load_b32 v6, v[0:1], off
	s_wait_loadcnt 0x0
	; Step 4: ds_bpermute_b32 -- ADDR (v15) is tainted, DATA (v6) is NOT.
	;         The def v10 should NOT be tainted after this (IsMemLoad fix).
	ds_bpermute_b32 v10, v15, v6
	s_wait_dscnt 0x0
	; Step 5: v_cmpx_ne_u32 sources v10 -- must NOT be flagged as CmpxFromLaneId.
	v_cmpx_ne_u32_e32 0, v10
	global_store_b32 v[0:1], v6, off
	s_wait_storecnt 0
	s_mov_b32 exec_lo, -1
	; Step 6: s_and_saveexec_b32 using a VCC-based mask (not lane-ID-derived).
	v_cmp_ne_u32_e32 vcc_lo, 0, v6
	s_and_saveexec_b32 s2, vcc_lo
	s_or_b32 exec_lo, exec_lo, s2
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ne_u32_bpermute_data_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 16
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
    .name:           v_cmpx_ne_u32_bpermute_data_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     3
    .symbol:         v_cmpx_ne_u32_bpermute_data_kernel.kd
    .vgpr_count:     16
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
