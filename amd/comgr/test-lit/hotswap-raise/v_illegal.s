; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_illegal_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; v_illegal (encoding 0x00000000) is an InstSI with no VOP format bits, so
; it falls through all flag-based dispatch arms. The raiser routes it via a
; CanonOp-based arm that calls handleVALU, which emits llvm.trap + unreachable
; to preserve the unconditional-fault semantics of the hardware trap instruction.

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
	;;#ASMSTART
	v_illegal
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_illegal_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 1
		.amdhsa_next_free_sgpr 0
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
    .name:           v_illegal_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     0
    .symbol:         v_illegal_kernel.kd
    .vgpr_count:     1
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
