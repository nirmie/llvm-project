; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=v_add_nc_u64_kernel 2>/dev/null | %FileCheck %s
;
; gfx1250 v_add_nc_u64 (VOP2 e32): per-lane 64-bit no-carry integer add.
; LLVM lowers this via V_ADD_U64_e64 internally; the opcode-map routes it
; to CanonicalOp::V_ADD_NC_U64, and the handler emits a plain i64 add.
;
; Pins Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-013
; (54 UnsupportedOpcode hits for v_add_nc_u64 across 54 kernels in a
; rocBLAS trsv run on 2026-05-26; the handler was already present but
; the opcode-map E(V_ADD_U64_e64, V_ADD_NC_U64) entry ensures routing).
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-013

; CHECK-LABEL: define amdgpu_kernel void @v_add_nc_u64_kernel(
; CHECK: add i64

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_add_nc_u64_kernel
	.p2align	8
	.type	v_add_nc_u64_kernel,@function
v_add_nc_u64_kernel:
	v_mov_b32_e32 v0, 1
	v_mov_b32_e32 v1, 0
	v_mov_b32_e32 v2, 2
	v_mov_b32_e32 v3, 0
	v_add_nc_u64_e32 v[0:1], v[0:1], v[2:3]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_add_nc_u64_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
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
    .name:           v_add_nc_u64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         v_add_nc_u64_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
