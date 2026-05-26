; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=global_atomic_add_f64_kernel 2>/dev/null | %FileCheck %s
;
; Pins GLOBAL v_global_atomic_add_f64: gfx940+/gfx950/gfx1250 support a 64-bit
; floating-point add as a global atomic.  The lifted IR must be an
; `atomicrmw fadd ... double` operating on a global-address pointer (addrspace
; 1 in the original; flat after addrspacecast), with the data operand a
; bitcast of a 64-bit VGPR-pair read to `double`.
;
; Validates the fix for Bug-Id: 2026-05-23T19-19-07Z_qwen2.5-7b-instruct-003
; (rocblas_symv double-buffered kernels used global_atomic_add_f64 [FLAT] which
; was UnsupportedOpcode on gfx1250->gfx950 transpilation before this handler
; was added).
; Also covers Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-002
; (5 non-RTN global_atomic_add_f64 hits across 5 rocblas_symv double-buffered
; kernels; same root cause, re-triggered on a later run).

; CHECK-LABEL: define amdgpu_kernel void @global_atomic_add_f64_kernel(
; CHECK: bitcast i64 %{{.*}} to double
; CHECK: atomicrmw fadd ptr addrspace(1) %{{.*}}, double %{{.*}}

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_atomic_add_f64_kernel
	.p2align	8
	.type	global_atomic_add_f64_kernel,@function
global_atomic_add_f64_kernel:
	s_load_b128 s[0:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, 0
	v_mov_b32_e32 v2, s2
	v_mov_b32_e32 v3, s3
	global_atomic_add_f64 v0, v[2:3], s[0:1] scope:SCOPE_DEV
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_atomic_add_f64_kernel
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
    .name: global_atomic_add_f64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: global_atomic_add_f64_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
