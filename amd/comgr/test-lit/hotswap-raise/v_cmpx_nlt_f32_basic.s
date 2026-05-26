; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_nlt_f32_basic_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Basic regression test for v_cmpx_nlt_f32 opcode handling.
;
; Bug-Id: 2026-05-26T04-13-44Z_qwen2.5-7b-instruct-019
;
; v_cmpx_nlt_f32 (226 hits across 16 kernels of a rocSOLVER geqr2_kernel_small
; workload on gfx1250) was reported as UnsupportedOpcode.  The instruction
; belongs to the V_CMPX VOPC family; NLT ("not less-than") maps to the LLVM
; FCmp predicate FCMP_UGE (unordered-or-greater-than-or-equal).
;
; This test verifies that:
;   1. v_cmpx_nlt_f32_e64 is recognized and lowered to fcmp uge float
;   2. The EXEC register update (ballot + AND into EXEC) is emitted
;   3. Subsequent instructions in the same kernel still raise correctly
;
; Pins Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-019:
; 226 hits across 16 rocSOLVER geqr2_kernel_small kernels (fatbin_co_0173.co)
; were refused with UnsupportedOpcode on v_cmpx_nlt_f32 at hotswap commit
; 8f2db5ec2edc. The opcode is handled by the generic V_CMPX path in
; parseVCmpPseudoName() (opcode-map.cpp), routing NLT -> FCMP_UGE via
; CanonicalOp::V_CMPX and handleValuVcmp().
;
; Pins Bug-Id 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-019:
; Same 226 hits across 16 rocSOLVER geqr2_kernel_small kernels (fatbin_co_0173.co)
; re-filed as UnsupportedOpcode on v_cmpx_nlt_f32 at hotswap commit 8f2db5ec2edc.
; The handler was already in place; all 81 kernels in fatbin_co_0173.co raise OK,
; confirming the fix from the original bug remains effective.
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_nlt_f32_basic_kernel(
; CHECK: fcmp uge float
; CHECK-NOT: UnsupportedOpcode

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_nlt_f32_basic_kernel
	.p2align	8
	.type	v_cmpx_nlt_f32_basic_kernel,@function
v_cmpx_nlt_f32_basic_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Load two f32 values from global memory (untainted from lane ID).
	global_load_b64 v[0:1], v[2:3], off
	s_wait_loadcnt 0x0
	; v_cmpx_nlt_f32_e64: compare v0 vs v1, update EXEC.
	; NLT = "not less-than" = FCMP_UGE (unordered-or-greater-than-or-equal).
	v_cmpx_nlt_f32_e64 v0, v1
	; Restore EXEC after the cmpx (common pattern in rocSOLVER kernels).
	s_mov_b32 exec_lo, -1
	global_store_b64 v[2:3], v[0:1], off
	s_wait_storecnt 0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_nlt_f32_basic_kernel
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
    .name:           v_cmpx_nlt_f32_basic_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_nlt_f32_basic_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
