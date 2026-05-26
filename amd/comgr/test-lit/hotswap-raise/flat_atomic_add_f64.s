; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=flat_atomic_add_f64_kernel 2>/dev/null | %FileCheck %s
;
; Pins FLAT v_flat_atomic_add_f64: gfx940+/gfx950/gfx1250 support a 64-bit
; floating-point add as a flat atomic.  The lifted IR must be an
; `atomicrmw fadd ... double` operating on a flat-address pointer, where the
; data operand is a bitcast of a 64-bit VGPR-pair read to `double`.
;
; Also covers Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-001
; 5 non-RTN flat_atomic_add_f64 UnsupportedOpcode hits across 5 rocBLAS
; symv double-buffered kernels (e.g. rocblas_symv_kernel_upper_double_buffered_non_diagonal
; with rocblas_internal_val_ptr<double> pointer-to-pointer args).  The fix was
; already in 66f1a93b62de; this annotation pins coverage to the bug record.
;
; Pins Bug-Id 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-001:
; Same UnsupportedOpcode on flat_atomic_add_f64 [FLAT], 5 hits across 5 rocBLAS
; symv double-buffered kernels in fatbin_co_0019.co at hotswap commit 8f2db5ec2edc.
; Sample kernel: rocblas_symv_kernel_upper_double_buffered_non_diagonal with
; rocblas_internal_val_ptr<double> pointer-to-pointer args.  All 196 kernels in
; fatbin_co_0019.co raise OK with the current binary (fix in 66f1a93b62de).
;
; Pins Bug-Id 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-001:
; Same UnsupportedOpcode on flat_atomic_add_f64 [FLAT], 5 hits across 5 rocBLAS
; symv double-buffered kernels in fatbin_co_0019.co at hotswap commit 8f2db5ec2edc.
; Sample kernel: rocblas_symv_kernel_upper_double_buffered_non_diagonal with
; rocblas_internal_val_ptr<double> pointer-to-pointer args.  All 196 kernels in
; fatbin_co_0019.co raise OK with the current binary (fix in 66f1a93b62de).
;
; Pins Bug-Id 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-001:
; Same UnsupportedOpcode on flat_atomic_add_f64 [FLAT], 5 hits across 5 rocBLAS
; symv double-buffered kernels in fatbin_co_0019.co at hotswap commit 8f2db5ec2edc.
; Sample kernel: rocblas_symv_kernel_upper_double_buffered_non_diagonal with
; rocblas_internal_val_ptr<double> pointer-to-pointer args.  All 196 kernels in
; fatbin_co_0019.co raise OK with the current binary (fix in 66f1a93b62de).
;
; Pins Bug-Id 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-001:
; Same UnsupportedOpcode on flat_atomic_add_f64 [FLAT], 5 hits across 5 rocBLAS
; symv double-buffered kernels in fatbin_co_0019.co at hotswap commit 8f2db5ec2edc.
; Sample kernel: rocblas_symv_kernel_upper_double_buffered_non_diagonal with
; rocblas_internal_val_ptr<double> pointer-to-pointer args.  All 196 kernels in
; fatbin_co_0019.co raise OK with the current binary (fix in 66f1a93b62de).
;
; Pins Bug-Id 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-001:
; Same UnsupportedOpcode on flat_atomic_add_f64 [FLAT], 5 hits across 5 rocBLAS
; symv double-buffered kernels in fatbin_co_0019.co at hotswap commit 8f2db5ec2edc.
; Sample kernel: rocblas_symv_kernel_upper_double_buffered_non_diagonal with
; rocblas_internal_val_ptr<double> pointer-to-pointer args.  All 196 kernels in
; fatbin_co_0019.co raise OK with the current binary (fix in 66f1a93b62de).
;
; Pins Bug-Id 2026-05-26T14-14-07Z_qwen2.5-7b-instruct-001:
; Same UnsupportedOpcode on flat_atomic_add_f64 [FLAT], 5 hits across 5 rocBLAS
; symv double-buffered kernels in fatbin_co_0019.co at hotswap commit 8f2db5ec2edc.
; Sample kernel: rocblas_symv_kernel_upper_double_buffered_non_diagonal with
; rocblas_internal_val_ptr<double> pointer-to-pointer args.  All 196 kernels in
; fatbin_co_0019.co raise OK with the current binary (fix in 66f1a93b62de).

; CHECK-LABEL: define amdgpu_kernel void @flat_atomic_add_f64_kernel(
; CHECK: bitcast i64 %{{.*}} to double
; CHECK: atomicrmw fadd ptr %{{.*}}, double %{{.*}}

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	flat_atomic_add_f64_kernel
	.p2align	8
	.type	flat_atomic_add_f64_kernel,@function
flat_atomic_add_f64_kernel:
	s_load_b128 s[0:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s0
	v_mov_b32_e32 v1, s1
	v_mov_b32_e32 v2, s2
	v_mov_b32_e32 v3, s3
	flat_atomic_add_f64 v[0:1], v[2:3] scope:SCOPE_DEV
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel flat_atomic_add_f64_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
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
  - .args:
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
      - { .address_space: global, .offset: 8, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name: flat_atomic_add_f64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: flat_atomic_add_f64_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
