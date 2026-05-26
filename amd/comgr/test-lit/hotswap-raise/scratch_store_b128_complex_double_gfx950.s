; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=copy_mat_complex_double_kernel 2>/dev/null | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-012
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-012
; Also covers Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-012
; Also covers Bug-Id: 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-012
; Also covers Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-012
; Also covers Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-012
;
; The copy_mat<rocblas_complex_num<double>, double, true> kernel issues 10
; scratch_store_b128 instructions with private_segment_fixed_size=0.  Each
; store spills a 128-bit (4×i32) complex-double intermediate to the private
; segment.  Hotswap must accept the conservative-65536-byte-frame path for
; all 10 stores rather than failing with UnsupportedOpcode.
;
; Kernel: copy_mat<rocblas_complex_num<double>, double, true>
; Format: FLAT scratch (SCRATCH_STORE_DWORDX4 alias)

; CHECK-LABEL: define {{.*}}copy_mat_complex_double_kernel
; CHECK: source_private_segment = alloca i8, i32 65536, align 4, addrspace(5)
; CHECK: scratch_ptr
; CHECK: store <4 x i32>
; CHECK: store <4 x i32>
; CHECK: store <4 x i32>

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	copy_mat_complex_double_kernel
	.p2align	8
	.type	copy_mat_complex_double_kernel,@function
copy_mat_complex_double_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	; Spill 10 x 128-bit complex-double temporaries via scratch_store_b128.
	; private_segment_fixed_size=0, so Hotswap must use the conservative
	; 65536-byte frame path rather than refusing with UnsupportedOpcode.
	v_mov_b32_e32 v0, 1
	v_mov_b32_e32 v1, 2
	v_mov_b32_e32 v2, 3
	v_mov_b32_e32 v3, 4
	scratch_store_b128 off, v[0:3], off offset:0
	scratch_store_b128 off, v[0:3], off offset:16
	scratch_store_b128 off, v[0:3], off offset:32
	scratch_store_b128 off, v[0:3], off offset:48
	scratch_store_b128 off, v[0:3], off offset:64
	scratch_store_b128 off, v[0:3], off offset:80
	scratch_store_b128 off, v[0:3], off offset:96
	scratch_store_b128 off, v[0:3], off offset:112
	scratch_store_b128 off, v[0:3], off offset:128
	scratch_store_b128 off, v[0:3], off offset:144
	scratch_load_b128  v[0:3], off, off offset:0
	s_wait_kmcnt 0x0
	global_store_b32 v4, v0, s[0:1]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel copy_mat_complex_double_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 5
		.amdhsa_next_free_sgpr 2
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
      - { .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           copy_mat_complex_double_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         copy_mat_complex_double_kernel.kd
    .vgpr_count:     5
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
