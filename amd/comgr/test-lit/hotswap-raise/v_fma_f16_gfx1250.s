; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=v_fma_f16_t16_basic_kernel 2>/dev/null \
; RUN:   | %FileCheck %s --check-prefix=BASIC
; RUN: %raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=v_fma_f16_t16_opsel_kernel 2>/dev/null \
; RUN:   | %FileCheck %s --check-prefix=OPSEL
; RUN: %raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=v_fma_f16_t16_dsthi_kernel 2>/dev/null \
; RUN:   | %FileCheck %s --check-prefix=DSTHI
;
; Regression canary for bug 2026-05-23T19-19-07Z_qwen2.5-7b-instruct-024:
; v_fma_f16 [VOP3] raised UnsupportedOpcode when transpiling gfx1250 -> gfx950
; because the True16 pseudo (V_FMA_F16_gfx9_t16_e64) was not listed in
; kCanonTable in opcode-map.cpp.
;
; gfx1250 uses True16 encoding where registers carry .l/.h suffixes (VGPR_16
; register class). The raise path must decode the real MC opcode
; (V_FMA_F16V_FMA_F16_gfx9_t16_e64_gfx12) -> pseudo V_FMA_F16_gfx9_t16_e64
; -> CanonicalOp::V_FMA_F16 and dispatch to the existing fma.f16 handler.

; BASIC-LABEL: define amdgpu_kernel void @v_fma_f16_t16_basic_kernel(
; BASIC-DAG: trunc i32 {{.*}} to i16
; BASIC-DAG: bitcast i16 {{.*}} to half
; BASIC: %fma_f16 = call half @llvm.fma.f16(
; BASIC: bitcast half %fma_f16 to i16
; BASIC: zext i16 {{.*}} to i32
; BASIC: and i32 {{.*}}, -65536
; BASIC: %f16_merge_lo = or i32
; BASIC-NOT: unsupported instruction

; OPSEL-LABEL: define amdgpu_kernel void @v_fma_f16_t16_opsel_kernel(
; OPSEL-DAG: %f16_src_hi = lshr i32 {{.*}}, 16
; OPSEL: %fma_f16 = call half @llvm.fma.f16(
; OPSEL: %f16_merge_lo = or i32
; OPSEL-NOT: unsupported instruction

; DSTHI-LABEL: define amdgpu_kernel void @v_fma_f16_t16_dsthi_kernel(
; DSTHI: %fma_f16 = call half @llvm.fma.f16(
; DSTHI: bitcast half %fma_f16 to i16
; DSTHI: zext i16 {{.*}} to i32
; DSTHI: and i32 {{.*}}, 65535
; DSTHI: shl i32 {{.*}}, 16
; DSTHI: %f16_merge_hi = or i32
; DSTHI-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_fma_f16_t16_basic_kernel
	.p2align	8
	.type	v_fma_f16_t16_basic_kernel,@function
v_fma_f16_t16_basic_kernel:
	v_fma_f16 v0.l, v1.l, v2.l, v3.l
	s_endpgm

	.globl	v_fma_f16_t16_opsel_kernel
	.p2align	8
	.type	v_fma_f16_t16_opsel_kernel,@function
v_fma_f16_t16_opsel_kernel:
	v_fma_f16 v0.l, v1.h, v2.l, v3.l
	s_endpgm

	.globl	v_fma_f16_t16_dsthi_kernel
	.p2align	8
	.type	v_fma_f16_t16_dsthi_kernel,@function
v_fma_f16_t16_dsthi_kernel:
	v_fma_f16 v0.h, v1.l, v2.l, v3.l
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_fma_f16_t16_basic_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 0
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.p2align	6, 0x0
	.amdhsa_kernel v_fma_f16_t16_opsel_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 0
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.p2align	6, 0x0
	.amdhsa_kernel v_fma_f16_t16_dsthi_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 0
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_fma_f16_t16_basic_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     0
    .symbol:         v_fma_f16_t16_basic_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_fma_f16_t16_opsel_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     0
    .symbol:         v_fma_f16_t16_opsel_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_fma_f16_t16_dsthi_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     0
    .symbol:         v_fma_f16_t16_dsthi_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version: [1, 2]
...
	.end_amdgpu_metadata
