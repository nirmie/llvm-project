; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ngt_f64_memload_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for false-positive CmpxFromLaneId on v_cmpx_ngt_f64 when
; the cmpx operands are loaded from memory (global_load_b128) rather than
; derived from v_mbcnt_*.
;
; Root cause: appendCanonicalRegLanes() in wave-size-obstruction.cpp iterated
; sub-register indices sequentially from AMDGPU::sub1 (=11). Because the
; AMDGPU sub-register index enum is non-sequential (sub1=11, sub1_hi16=12,
; sub1_lo16=13, sub2=21, sub3=31, ...), the loop would pick up fractional
; sub-registers and break before reaching sub2/sub3. For a 4-wide VGPR tuple
; v[2:5] written by global_load_b128, the tracker only saw sub0(v2) and
; sub1(v3); v4 and v5 were never marked as untainted. A prior v_mbcnt_lo
; feeding v_cndmask into v5 left v5 tainted; the load did not clear it; then
; v_cmpx_ngt_f64 sourcing v5 was falsely flagged.
;
; This test constructs the minimal trigger:
;   1. v_mbcnt_lo -> v_cndmask writes v5 (v5 tainted)
;   2. global_load_b128 writes v[2:5] (should clear taint on v4 AND v5)
;   3. v_cmpx_ngt_f64 sources v[4:5] (should NOT be flagged as CmpxFromLaneId)
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ngt_f64_memload_kernel(

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ngt_f64_memload_kernel
	.p2align	8
	.type	v_cmpx_ngt_f64_memload_kernel,@function
v_cmpx_ngt_f64_memload_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: create taint on v5 via mbcnt_lo -> cndmask
	v_mbcnt_lo_u32_b32 v4, -1, 0
	v_cmp_gt_u32_e64 vcc_lo, 30, v4
	v_cndmask_b32_e32 v5, 0, v4, vcc_lo
	; Step 2: global_load_b128 writes v[2:5] -- must clear taint on v4 AND v5
	global_load_b128 v[2:5], v[0:1], off
	s_wait_loadcnt 0x0
	; Step 3: v_cmpx_ngt_f64 sources v[4:5] -- should NOT be CmpxFromLaneId
	v_cmpx_ngt_f64_e64 v[2:3], v[4:5]
	global_store_b128 v[0:1], v[2:5], off
	s_wait_storecnt 0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ngt_f64_memload_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 6
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
    .name:           v_cmpx_ngt_f64_memload_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_ngt_f64_memload_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
