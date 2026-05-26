; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ne_u32_basic_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Basic lowering test for v_cmpx_ne_u32: verifies that the 32-bit unsigned
; NE compare-and-write-EXEC lowers to icmp ne + ballot + and.
;
; Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-015
; Also covers Bug-Id: 2026-05-26T15-20-57Z_qwen2.5-7b-instruct-015
;
; rocBLAS iamax/iamin kernels (fatbin_co_0041.co, 20 hits across 20 kernels)
; were reported as UnsupportedOpcode for v_cmpx_ne_u32.  The instruction
; belongs to the V_CMPX VOPC family; NE maps to LLVM ICmpInst::ICMP_NE on
; 32-bit unsigned integers.
;
; This test verifies that:
;   1. v_cmpx_ne_u32_e32 is recognized and lowered to icmp ne i32
;   2. The EXEC register update (ballot + AND into EXEC) is emitted
;   3. Subsequent instructions in the same kernel still raise correctly
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ne_u32_basic_kernel(
; CHECK: icmp ne i32
; CHECK: @llvm.amdgcn.ballot
; CHECK-NOT: UnsupportedOpcode

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ne_u32_basic_kernel
	.p2align	8
	.type	v_cmpx_ne_u32_basic_kernel,@function
v_cmpx_ne_u32_basic_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Load a 32-bit value from memory (untainted from lane ID).
	global_load_b32 v0, v[2:3], off
	s_wait_loadcnt 0x0
	; v_cmpx_ne_u32_e32: compare v0 != 0, write result into EXEC.
	; NE = ICMP_NE on unsigned 32-bit integers.
	v_cmpx_ne_u32_e32 0, v0
	; Restore EXEC after the cmpx (common pattern in rocBLAS kernels).
	s_mov_b32 exec_lo, -1
	global_store_b32 v[2:3], v0, off
	s_wait_storecnt 0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ne_u32_basic_kernel
		.amdhsa_kernarg_size 0
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
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_cmpx_ne_u32_basic_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_ne_u32_basic_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
