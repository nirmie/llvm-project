; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=s_mov_b64_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-011.
; Also pinned for:    Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-011.
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-011.
; Also covers Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-011.
; Also covers Bug-Id: 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-011.
; Also covers Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-011.
; Also covers Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-011.
; Also covers Bug-Id: 2026-05-26T14-14-07Z_qwen2.5-7b-instruct-011.
;
; s_mov_b64 with both immediate-zero and register-pair operands was failing
; with UnsupportedOpcode in 618 instances across 174 rocSOLVER kernels
; (getf2_panel_kernel, getf2_npvt_panel_kernel, getf2_scale_update_kernel).
; The fix wires S_MOV_B64 in the SOP1 handler to call writeReg64, which
; reconstructs the i64 SGPR pair from the source operand.
;
; Variant A: s_mov_b64 s[4:5], 0  -- move immediate zero into a 64-bit SGPR pair.
; Variant B: s_mov_b64 s[6:7], s[2:3] -- copy a 64-bit SGPR pair (the common
;            "save a pointer before calling" pattern in rocSOLVER).

; CHECK-LABEL: define amdgpu_kernel void @s_mov_b64_kernel(
; Variant A: immediate 0 written as zext i32 0
; CHECK: zext i32 0 to i64
; Variant B: SGPR pair copy propagated through or+shl reconstruction
; CHECK: or i64

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_mov_b64_kernel
	.p2align	8
	.type	s_mov_b64_kernel,@function
s_mov_b64_kernel:
	; s[0:1] = kernarg segment ptr
	; Load a 64-bit pointer from kernarg at offset 0
	s_load_b64 s[2:3], s[0:1], 0x0
	; Variant A: move immediate 0 into 64-bit SGPR pair
	s_mov_b64 s[4:5], 0
	; Variant B: copy 64-bit SGPR pair (pointer save pattern)
	s_mov_b64 s[6:7], s[2:3]
	s_wait_kmcnt 0x0
	; Use the zero pair as the store address hi/lo so it survives DCE
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	global_store_b64 v[0:1], v[0:1], off
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_mov_b64_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 8
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           s_mov_b64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         s_mov_b64_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
