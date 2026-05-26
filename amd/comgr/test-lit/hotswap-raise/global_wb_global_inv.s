; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=global_wb_global_inv_kernel 2>/dev/null | %FileCheck %s
;
; Companion test to global_inv_global_wb.s -- emits global_wb BEFORE global_inv,
; matching the order found in rocBLAS trsv kernels (write-back then invalidate).
; Both GFX12+ FLAT cache-maintenance ops are handled by the same code paths
; in handle-flat.cpp added for:
;   Bug-Id: 2026-05-26T18-08-17Z_qwen2.5-7b-instruct-002
;
; global_wb  ->  @llvm.amdgcn.s.dcache.wb     (scalar L2 writeback)
; global_inv ->  @llvm.amdgcn.buffer.wbinvl1  (L1 flush+invalidate)

; CHECK-LABEL: define amdgpu_kernel void @global_wb_global_inv_kernel(
; CHECK: call void @llvm.amdgcn.s.dcache.wb()
; CHECK: call void @llvm.amdgcn.buffer.wbinvl1()

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_wb_global_inv_kernel
	.p2align	8
	.type	global_wb_global_inv_kernel,@function
global_wb_global_inv_kernel:
	global_wb scope:SCOPE_DEV
	global_inv scope:SCOPE_DEV
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_wb_global_inv_kernel
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
    .name:           global_wb_global_inv_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         global_wb_global_inv_kernel.kd
    .vgpr_count:     0
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
