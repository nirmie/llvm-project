; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=v_illegal_kernel 2>/dev/null | %FileCheck %s
; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=v_illegal_kernel 2>/dev/null | %FileCheck %s
;
; v_illegal (encoding 0x00000000) is a hardware-trap instruction. The raiser
; must lower it to llvm.trap + unreachable so its fault semantics are preserved
; in the translated binary. This instruction carries no VOP/SOP format
; flag bits in TSFlags, so the dispatch path is handled by a canonical-op check
; before the format-flag dispatch in raiser.cpp.
; Tests both gfx942 and gfx950 targets (wave64 targets for gfx1250 wave32 source).

; CHECK-LABEL: define amdgpu_kernel void @v_illegal_kernel(
; CHECK: call void @llvm.trap()
; CHECK-NEXT: unreachable

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_illegal_kernel
	.p2align	8
	.type	v_illegal_kernel,@function
v_illegal_kernel:
	v_illegal
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_illegal_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_next_free_vgpr 1
		.amdhsa_next_free_sgpr 0
		.amdhsa_float_denorm_mode_32 3
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:             []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_illegal_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_illegal_kernel.kd
    .vgpr_count:     1
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
