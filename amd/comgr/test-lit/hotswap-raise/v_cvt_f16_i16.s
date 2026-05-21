; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=v_cvt_f16_i16_kernel 2>/dev/null | %FileCheck %s --check-prefix=IR
;
; v_cvt_f16_i16: signed 16-bit integer -> f16.  Lower as SIToFP.
; v_cvt_i16_f16: f16 -> signed 16-bit integer.  Lower as FPToSI.

; IR-LABEL: define amdgpu_kernel void @v_cvt_f16_i16_kernel(
; IR: [[TRUNC:%[^ ]+]] = trunc i32 {{%[^ ]+}} to i16
; IR-NEXT: [[F16:%[^ ]+]] = sitofp i16 [[TRUNC]] to half
; IR: [[I16:%[^ ]+]] = fptosi half {{%[^ ]+}} to i16
; IR-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cvt_f16_i16_kernel
	.p2align	8
	.type	v_cvt_f16_i16_kernel,@function
v_cvt_f16_i16_kernel:
	s_load_b32 s2, s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s2
	;;#ASMSTART
	v_cvt_f16_i16_e64 v1, v0
	v_cvt_i16_f16_e64 v2, v1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cvt_f16_i16_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 3
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
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           v_cvt_f16_i16_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         v_cvt_f16_i16_kernel.kd
    .vgpr_count:     3
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
