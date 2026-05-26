; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=global_inv_global_wb_kernel 2>/dev/null | %FileCheck %s
;
; Pins global_inv and global_wb (GFX12+ standalone cache maintenance ops).
; Both are FLAT-family instructions with a cpol (scope) operand and no
; address or data operand.  rocBLAS trsv kernels emit them as cache
; invalidate/writeback operations after store sequences.
;
; On gfx950:
;   global_inv -> @llvm.amdgcn.buffer.wbinvl1  (L1 cache invalidate+writeback)
;   global_wb  -> @llvm.amdgcn.s.dcache.wb     (scalar L2 writeback)
;
; 404 hits across 373 kernels in fatbin_co_0011.co
; (hotswap commit d5671442ee7c).
;
; Pins Bug-Id: 2026-05-26T18-08-17Z_qwen2.5-7b-instruct-001

; CHECK-LABEL: define amdgpu_kernel void @global_inv_global_wb_kernel(
; CHECK: call void @llvm.amdgcn.buffer.wbinvl1()
; CHECK: call void @llvm.amdgcn.s.dcache.wb()

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_inv_global_wb_kernel
	.p2align	8
	.type	global_inv_global_wb_kernel,@function
global_inv_global_wb_kernel:
	global_inv scope:SCOPE_DEV
	global_wb scope:SCOPE_DEV
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_inv_global_wb_kernel
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
    .name:           global_inv_global_wb_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         global_inv_global_wb_kernel.kd
    .vgpr_count:     0
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
