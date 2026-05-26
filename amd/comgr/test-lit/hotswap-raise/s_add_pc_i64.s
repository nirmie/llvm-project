; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=s_add_pc_i64_kernel 2>/dev/null | %FileCheck %s
;
; s_add_pc_i64: gfx1250/gfx13 unconditional PC-relative long-branch trampoline.
; Hardware: PC_next = (PC_after_inst) + sign_extend(imm64).
; The corpus uses this after a conditional branch that skips over it; the
; instruction itself is always an unconditional branch in the raised IR.
;
; Layout (each instruction 4 bytes):
;   offset 0x00: s_cbranch_execnz 3  → br cond to 0x10 (skip the trampoline)
;   offset 0x04: s_add_pc_i64 8      → target = 0x04 + 4 + 8 = 0x10 (same dest)
;   offset 0x08: s_mov_b32 s0, 99   (dead: unreachable via either path)
;   offset 0x0c: s_endpgm           (dead)
;   offset 0x10: s_endpgm           (landing pad for both branches)
;
; The raiser must emit `br label %bb_0x10` for the s_add_pc_i64.
;
; Also covers Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-005
; (142 UnsupportedOpcode hits for s_add_pc_i64 across 142 kernels
; in a rocSOLVER getf2_small run on 2026-05-26).
;
; Pins Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-005
; (142 UnsupportedOpcode hits for s_add_pc_i64 across 142 kernels in
; rocSOLVER getf2_small_kernel on 2026-05-26, fatbin_co_0097.co,
; hotswap commit 8f2db5ec2edc).
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-005
; (142 UnsupportedOpcode hits for s_add_pc_i64 across 142 kernels in
; rocSOLVER getf2_small_kernel on 2026-05-26, fatbin_co_0097.co,
; hotswap commit 8f2db5ec2edc).
; Pins Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-005
; (142 UnsupportedOpcode hits for s_add_pc_i64 across 142 kernels in
; rocSOLVER getf2_small_kernel on 2026-05-26, fatbin_co_0097.co,
; hotswap commit 8f2db5ec2edc).
; Pins Bug-Id: 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-005
; (142 UnsupportedOpcode hits for s_add_pc_i64 across 142 kernels in
; rocSOLVER getf2_small_kernel on 2026-05-26, fatbin_co_0097.co,
; hotswap commit 8f2db5ec2edc).
; Pins Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-005
; (142 UnsupportedOpcode hits for s_add_pc_i64 across 142 kernels in
; rocSOLVER getf2_small_kernel on 2026-05-26, fatbin_co_0097.co,
; hotswap commit 8f2db5ec2edc; all 128 kernels raise cleanly).
; Pins Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-005
; (142 UnsupportedOpcode hits for s_add_pc_i64 across 142 kernels in
; rocSOLVER getf2_small_kernel on 2026-05-26, fatbin_co_0097.co,
; hotswap commit 8f2db5ec2edc; all 128 kernels raise cleanly).
; Pins Bug-Id: 2026-05-26T14-14-07Z_qwen2.5-7b-instruct-005
; (142 UnsupportedOpcode hits for s_add_pc_i64 across 142 kernels in
; rocSOLVER getf2_small_kernel on 2026-05-26, fatbin_co_0097.co,
; hotswap commit 8f2db5ec2edc; all 128 kernels raise cleanly).

; CHECK-LABEL: define amdgpu_kernel void @s_add_pc_i64_kernel(
; CHECK:       bb_0x4:
; CHECK-NEXT:    br label %bb_0x10
; CHECK:       bb_0x10:

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_add_pc_i64_kernel
	.p2align	8
	.type	s_add_pc_i64_kernel,@function
s_add_pc_i64_kernel:
	s_cbranch_execnz 3
	s_add_pc_i64 8
	s_mov_b32 s0, 99
	s_endpgm
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_add_pc_i64_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 0
		.amdhsa_next_free_sgpr 8
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           s_add_pc_i64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         s_add_pc_i64_kernel.kd
    .vgpr_count:     0
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
