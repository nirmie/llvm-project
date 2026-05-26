; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ngt_f32_mad_addr_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for false-positive CmpxFromLaneId on v_cmpx_ngt_f32 when
; the global_load address is derived from a v_mad_nc_u64_u32 instruction that
; itself uses a lane-index-derived register (indirect taint propagation).
;
; Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-017
;
; Pattern from rocBLAS trsv kernels with complex<float> PKS3 operands:
;   1. v_mbcnt_lo_u32_b32 v4, -1, 0            ; lane ID in v4 (TAINTED)
;   2. v_mad_nc_u64_u32 v[2:3], s0, v6, v[4:5] ; v[2:3] = s0*v6 + v[4:5] (TAINTED)
;   3. v_lshl_add_u64 v[6:7], v[2:3], 3, s[0:1]; address in v[6:7] (TAINTED)
;   4. global_load_b64 v[6:7], v[6:7], off      ; load 2 floats -- NOT tainted
;   5. v_cmpx_ngt_f32_e64 |v6|, |v7|           ; compare loaded data -- OK
;
; Without the fix the kernel refuses with:
;   cross-wave-lane-predicated-exec on 'v_cmpx_ngt_f32'
; With the fix, global_load clears destination taint regardless of address
; taint and the kernel raises successfully.
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ngt_f32_mad_addr_kernel(
; CHECK: fcmp ule float
; CHECK-NOT: cross-wave-lane-predicated-exec

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ngt_f32_mad_addr_kernel
	.p2align	8
	.type	v_cmpx_ngt_f32_mad_addr_kernel,@function
v_cmpx_ngt_f32_mad_addr_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: lane ID in v4 (TAINTED by mbcnt).
	v_mbcnt_lo_u32_b32 v4, -1, 0
	; Step 2: v[2:3] = s0 * v6 + v[4:5] where v4 is tainted.
	; LaneIdProvenanceTracker propagates taint into v[2:3].
	v_mad_nc_u64_u32 v[2:3], s0, v6, v[4:5]
	; Step 3: compute global address from v[2:3] (TAINTED address).
	v_lshl_add_u64 v[6:7], v[2:3], 3, s[0:1]
	; Step 4: global_load_b64 writes v[6:7] with float data from memory.
	; The load destination must NOT inherit address taint.
	global_load_b64 v[6:7], v[6:7], off
	s_wait_loadcnt 0x0
	s_wait_xcnt 0x0
	; Step 5: v_cmpx_ngt_f32 compares the loaded floats.
	; Must NOT be classified as CmpxFromLaneId (loaded memory, not lane index).
	v_cmpx_ngt_f32_e64 |v6|, |v7|
	s_mov_b32 exec_lo, -1
	global_store_b64 v[0:1], v[6:7], off
	s_wait_storecnt 0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ngt_f32_mad_addr_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 8
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
    .name:           v_cmpx_ngt_f32_mad_addr_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_ngt_f32_mad_addr_kernel.kd
    .vgpr_count:     8
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
