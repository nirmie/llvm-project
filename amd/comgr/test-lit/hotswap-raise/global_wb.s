; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=global_wb_kernel 2>/dev/null | %FileCheck %s
;
; global_wb is a GFX12+ standalone cache writeback instruction (FLAT format).
; It writes dirty L1/L2 cache lines back to the next cache level without
; necessarily invalidating the cache. On gfx950 (HasMfma/GFX940+) the nearest
; equivalent is llvm.amdgcn.s.dcache.wb (gfx9+ scalar D$ writeback).
; Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-004
;
; Also covers Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-004
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-004
; Also covers Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-004
; Also covers Bug-Id: 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-004
; Also covers Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-004
; Also covers Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-004
; Also covers Bug-Id: 2026-05-26T14-14-07Z_qwen2.5-7b-instruct-004
; Also covers Bug-Id: 2026-05-26T15-20-57Z_qwen2.5-7b-instruct-004
; 315 global_wb UnsupportedOpcode hits across 315 rocBLAS TRSV kernels
; (e.g. rocblas_trsv_big_batch_device). Fix was already present; this
; annotation pins regression coverage to this bug record.

; CHECK-LABEL: define amdgpu_kernel void @global_wb_kernel(
; CHECK: call void @llvm.amdgcn.s.dcache.wb()

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_wb_kernel
	.p2align	8
	.type	global_wb_kernel,@function
global_wb_kernel:
	global_wb scope:SCOPE_DEV
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_wb_kernel
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
    .name:           global_wb_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         global_wb_kernel.kd
    .vgpr_count:     0
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
