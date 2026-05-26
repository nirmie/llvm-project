; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ngt_f32_global_memload_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for false-positive CmpxFromLaneId on v_cmpx_ngt_f32 when
; the cmpx operands are loaded from global memory (global_load_b64) rather
; than derived from v_mbcnt_*.
;
; Root cause: isMemoryReadOp() was absent from findLanePredicatedExecSites()
; in wave-size-obstruction.cpp.  The LaneIdProvenanceTracker propagated taint
; from a v_mbcnt_lo-derived memory address into the destination registers of
; a global_load_b64 instruction.  Subsequent v_cmpx_ngt_f32 instructions
; sourcing those registers were falsely classified as CmpxFromLaneId, causing
; the kernel to be refused with "cross-wave-lane-predicated-exec".
;
; Pattern from rocBLAS trsv kernels with complex<float> operands:
;   1. v_mbcnt_lo_u32_b32 v20, -1, 0          ; lane ID in v20 (TAINTED)
;   2. ... address arithmetic using v20 ...     ; v[32:33] = lane-indexed addr
;   3. global_load_b64 v[32:33], v[32:33], off ; load 2 floats -- NOT tainted
;   4. v_cmpx_ngt_f32_e64 |v32|, |v33|         ; compare loaded data -- OK
;
; Without the fix the kernel refuses with:
;   cross-wave-lane-predicated-exec on 'v_cmpx_ngt_f32'
; With the fix, the kernel raises successfully.
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ngt_f32_global_memload_kernel(
; CHECK-NOT: cross-wave-lane-predicated-exec

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ngt_f32_global_memload_kernel
	.p2align	8
	.type	v_cmpx_ngt_f32_global_memload_kernel,@function
v_cmpx_ngt_f32_global_memload_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: v_mbcnt_lo produces lane ID in v4 (TAINTED).
	v_mbcnt_lo_u32_b32 v4, -1, 0
	; Step 2: compute lane-indexed address in v[2:3] -- TAINTED.
	v_lshl_add_u64 v[2:3], v[4:5], 3, s[0:1]
	; Step 3: global_load_b64 writes v[2:3] from memory.
	;         The destination holds loaded float values, NOT the address.
	;         Taint must NOT propagate from the address into v2/v3.
	global_load_b64 v[2:3], v[2:3], off
	s_wait_loadcnt 0x0
	s_wait_xcnt 0x0
	; Step 4: v_cmpx_ngt_f32 sources v2 and v3 (loaded floats).
	;         Must NOT be classified as CmpxFromLaneId.
	v_cmpx_ngt_f32_e64 |v2|, |v3|
	global_store_b64 v[0:1], v[2:3], off
	s_wait_storecnt 0
	s_mov_b64 exec, -1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ngt_f32_global_memload_kernel
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
    .name:           v_cmpx_ngt_f32_global_memload_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_ngt_f32_global_memload_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
