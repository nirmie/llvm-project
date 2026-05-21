; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=s_cmp_o_f32_kernel 2>/dev/null | %FileCheck %s --check-prefix=IR
;
; s_cmp_o_f32: scalar ordered f32 compare (true iff neither operand is NaN).
; Lowered as FCmpORD.  s_cmp_u_f32 is the complementary unordered variant.

; IR-LABEL: define amdgpu_kernel void @s_cmp_o_f32_kernel(
; IR: fcmp ord float
; IR-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_cmp_o_f32_kernel
	.p2align	8
	.type	s_cmp_o_f32_kernel,@function
s_cmp_o_f32_kernel:
	s_load_b32 s2, s[0:1], 0x0
	s_load_b32 s3, s[0:1], 0x4
	s_wait_kmcnt 0x0
	;;#ASMSTART
	s_cmp_o_f32 s2, s3
	;;#ASMEND
	v_mov_b32_e32 v0, 0
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_cmp_o_f32_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 1
		.amdhsa_next_free_sgpr 4
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
  - .args:
      - { .address_space:  global, .offset: 0, .size: 4, .value_kind: by_value }
      - { .offset: 4, .size: 4, .value_kind: by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           s_cmp_o_f32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         s_cmp_o_f32_kernel.kd
    .vgpr_count:     1
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
