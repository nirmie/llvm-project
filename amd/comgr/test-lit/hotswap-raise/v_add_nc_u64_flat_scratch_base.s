; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=v_add_nc_u64_flat_scratch_base_kernel 2>/dev/null | %FileCheck %s
;
; SRC_FLAT_SCRATCH_BASE_LO holds the base of globally-addressable scratch on
; gfx1250. gfx950 has no globally-addressable scratch so the base is 0
; (APERTURE treatment). v_add_nc_u64 with src_flat_scratch_base_lo as a
; source operand must lower cleanly -- previously it crashed with
; "readOp64 saw unmodeled register 'SRC_FLAT_SCRATCH_BASE_LO'".

; CHECK-LABEL: define amdgpu_kernel void @v_add_nc_u64_flat_scratch_base_kernel(
; CHECK: add i64
; CHECK: ret void

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_add_nc_u64_flat_scratch_base_kernel
	.p2align	8
	.type	v_add_nc_u64_flat_scratch_base_kernel,@function
v_add_nc_u64_flat_scratch_base_kernel:
	v_add_nc_u64_e32 v[0:1], src_flat_scratch_base_lo, v[0:1]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_add_nc_u64_flat_scratch_base_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
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
    .name:           v_add_nc_u64_flat_scratch_base_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         v_add_nc_u64_flat_scratch_base_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
