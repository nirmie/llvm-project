; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=global_atomic_add_f64_rtn_kernel 2>/dev/null | %FileCheck %s
;
; Pins GLOBAL global_atomic_add_f64 RTN form (returned-old-value variant):
; gfx1250 emits GLOBAL_ATOMIC_ADD_F64_RTN_gfx1250 when the old value is
; consumed (numDefs > 0).  rocBLAS symv double-buffered kernels use this form.
; The lifted IR must be an `atomicrmw fadd ... double` with the result written
; back to a VGPR pair.
;
; Also covers Bug-Id: 2026-05-26T04-13-44Z_qwen2.5-7b-instruct-002
; (5 RTN-form global_atomic_add_f64 UnsupportedOpcode hits across 5 kernels in
; the rocBLAS run on 2026-05-26).
; Also covers Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-002
; (duplicate: same 5 RTN-form global_atomic_add_f64 hits in a later rocBLAS run,
; sample kernel=_ZL54rocblas_symv_kernel_upper_double_buffered_non_diagonalILi32...).

; CHECK-LABEL: define amdgpu_kernel void @global_atomic_add_f64_rtn_kernel(
; CHECK: bitcast i64 %{{.*}} to double
; CHECK: atomicrmw fadd ptr addrspace(1) %{{.*}}, double %{{.*}}
; CHECK: bitcast double %{{.*}} to i64

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_atomic_add_f64_rtn_kernel
	.p2align	8
	.type	global_atomic_add_f64_rtn_kernel,@function
global_atomic_add_f64_rtn_kernel:
	s_load_b128 s[0:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, 0
	v_mov_b32_e32 v2, s2
	v_mov_b32_e32 v3, s3
	global_atomic_add_f64 v[4:5], v0, v[2:3], s[0:1] th:TH_ATOMIC_RETURN scope:SCOPE_DEV
	global_store_b64 v0, v[4:5], s[0:1]
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_atomic_add_f64_rtn_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 6
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
    .name: global_atomic_add_f64_rtn_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: global_atomic_add_f64_rtn_kernel.kd
    .vgpr_count: 6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
