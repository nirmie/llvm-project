; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx1250 --emit-ir=v_pk_mul_f16_basic_kernel 2>/dev/null | %FileCheck %s --check-prefix=BASIC
; RUN: raise_cli %t.hsaco --target-isa=gfx1250 --emit-ir=v_pk_mul_f16_mod_kernel 2>/dev/null | %FileCheck %s --check-prefix=MOD
; RUN: raise_cli %t.hsaco --target-isa=gfx1250 --emit-ir=v_pk_mul_f16_clamp_kernel 2>/dev/null | %FileCheck %s --check-prefix=CLAMP
; RUN: raise_cli %t.hsaco --target-isa=gfx1250 --emit-ir=v_pk_mul_f16_imm_kernel 2>/dev/null | %FileCheck %s --check-prefix=IMM
; RUN: raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=v_pk_mul_f16_imm_kernel 2>/dev/null | %FileCheck %s --check-prefix=CROSS
;
; Pins VOP3P `v_pk_mul_f16`: packed `<2 x half>` lane selection and negation
; come from the decoded srcN_modifiers operands, arithmetic lowers to a lane-wise
; `fmul <2 x half>`, and clamp is applied after the multiply via min/max.
;
; Pins Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-032:
; 36 hits across 20 rocBLAS sscal/scal kernels (sample:
; _ZL22rocblas_sscal_2_kernelILi256EDF16_DF16_PKDF16_PDF16_EviT2_lT3_lli
; in fatbin_co_0050.co) were reported as UnsupportedOpcode for v_pk_mul_f16
; at hotswap commit 8f2db5ec2edc.  The VOP3P handler under
; CanonicalOp::V_PK_MUL_F16 in handle-valu-vop3p.cpp emits lane-wise fmul
; with op_sel / neg_lo / neg_hi modifier support; all kernels in
; fatbin_co_0050.co raise successfully.
;
; Pins Bug-Id 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-032:
; 36 hits across 20 rocBLAS sscal/scal kernels (sample:
; _ZL22rocblas_sscal_2_kernelILi256EDF16_DF16_PKDF16_PDF16_EviT2_lT3_lli
; in fatbin_co_0050.co) were reported as UnsupportedOpcode for v_pk_mul_f16
; at hotswap commit 8f2db5ec2edc.  The VOP3P handler under
; CanonicalOp::V_PK_MUL_F16 in handle-valu-vop3p.cpp emits lane-wise fmul
; with op_sel / neg_lo / neg_hi modifier support; all kernels in
; fatbin_co_0050.co raise successfully (100 ok, 0 fail).
;
; Pins Bug-Id 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-032:
; v_pk_mul_f16 [VOP3P] reported as UnsupportedOpcode with 36 hits across
; 20 rocBLAS sscal kernels (fatbin_co_0050.co) at hotswap commit 8f2db5ec2edc.
; The V_PK_MUL_F16 handler in handle-valu-vop3p.cpp was already in place;
; all 100 kernels in the .co raise OK with the current binary on gfx950.
;
; Pins Bug-Id 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-032:
; Duplicate report: v_pk_mul_f16 [VOP3P] UnsupportedOpcode with 36 hits across
; 20 rocBLAS sscal kernels (fatbin_co_0050.co) at hotswap commit 8f2db5ec2edc.
; The V_PK_MUL_F16 handler was already present; all 100 kernels raise OK on
; gfx950 with the current binary.
;
; Pins Bug-Id 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-032:
; Duplicate report: v_pk_mul_f16 [VOP3P] UnsupportedOpcode with 36 hits across
; 20 rocBLAS sscal kernels (fatbin_co_0050.co) at hotswap commit 8f2db5ec2edc.
; The V_PK_MUL_F16 handler was already present; all 100 kernels raise OK on
; gfx950 with the current binary.
;
; Pins Bug-Id 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-032:
; Duplicate report: v_pk_mul_f16 [VOP3P] UnsupportedOpcode with 36 hits across
; 20 rocBLAS sscal kernels (fatbin_co_0050.co) at hotswap commit 8f2db5ec2edc.
; The V_PK_MUL_F16 handler was already present; all 100 kernels raise OK on
; gfx950 with the current binary.

; BASIC-LABEL: define amdgpu_kernel void @v_pk_mul_f16_basic_kernel(
; BASIC: fmul <2 x half>
; BASIC-NOT: call <2 x half> @llvm.fma.v2f16(
; BASIC-NOT: fadd <2 x half>

; MOD-LABEL: define amdgpu_kernel void @v_pk_mul_f16_mod_kernel(
; MOD: [[SRC0:%[^ ]+]] = bitcast i32 %{{[^ ]+}} to <2 x half>
; MOD-DAG: [[SRC0_LO:%[^ ]+]] = extractelement <2 x half> [[SRC0]], i64 0
; MOD-DAG: [[SRC0_HI:%[^ ]+]] = extractelement <2 x half> [[SRC0]], i64 1
; MOD: [[NEG_LO:%[^ ]+]] = fneg half [[SRC0_HI]]
; MOD: insertelement <2 x half> {{.*}}, half [[NEG_LO]], i64 0
; MOD: insertelement <2 x half> {{.*}}, half [[SRC0_LO]], i64 1
; MOD: fneg half
; MOD: fmul <2 x half>

; CLAMP-LABEL: define amdgpu_kernel void @v_pk_mul_f16_clamp_kernel(
; CLAMP: [[MUL:%[^ ]+]] = fmul <2 x half>
; CLAMP: call <2 x half> @llvm.maxnum.v2f16(<2 x half> [[MUL]],
; CLAMP: call <2 x half> @llvm.minnum.v2f16(

; IMM-LABEL: define amdgpu_kernel void @v_pk_mul_f16_imm_kernel(
; IMM-NOT: call <2 x half> @llvm.fma.v2f16(
; IMM-NOT: fadd <2 x half>
; IMM: [[MUL:%[^ ]+]] = fmul <2 x half>
; IMM-SAME: bitcast (<1 x i32> splat (i32 17408) to <2 x half>)

; CROSS-LABEL: define amdgpu_kernel void @v_pk_mul_f16_imm_kernel(
; CROSS: fmul <2 x half>
; CROSS-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_pk_mul_f16_basic_kernel
	.p2align	8
	.type	v_pk_mul_f16_basic_kernel,@function
v_pk_mul_f16_basic_kernel:
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_pk_mul_f16 v3, v0, v1
	s_endpgm

	.globl	v_pk_mul_f16_mod_kernel
	.p2align	8
	.type	v_pk_mul_f16_mod_kernel,@function
v_pk_mul_f16_mod_kernel:
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_pk_mul_f16 v3, v0, v1 op_sel:[1,0] op_sel_hi:[0,1] neg_lo:[1,0] neg_hi:[0,1]
	s_endpgm

	.globl	v_pk_mul_f16_clamp_kernel
	.p2align	8
	.type	v_pk_mul_f16_clamp_kernel,@function
v_pk_mul_f16_clamp_kernel:
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_pk_mul_f16 v3, v0, v1 clamp
	s_endpgm

	.globl	v_pk_mul_f16_imm_kernel
	.p2align	8
	.type	v_pk_mul_f16_imm_kernel,@function
v_pk_mul_f16_imm_kernel:
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	; LLVM codegen uses op_sel_hi:[*,0] to broadcast scalar f16 inline
	; constants into the high packed lane.
	v_pk_mul_f16 v3, v0, 4.0 op_sel_hi:[1,0]
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_pk_mul_f16_basic_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.p2align	6, 0x0
	.amdhsa_kernel v_pk_mul_f16_mod_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.p2align	6, 0x0
	.amdhsa_kernel v_pk_mul_f16_clamp_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.p2align	6, 0x0
	.amdhsa_kernel v_pk_mul_f16_imm_kernel
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
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name: v_pk_mul_f16_basic_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: v_pk_mul_f16_basic_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
  - .args:
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name: v_pk_mul_f16_mod_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: v_pk_mul_f16_mod_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
  - .args:
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name: v_pk_mul_f16_clamp_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: v_pk_mul_f16_clamp_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
  - .args:
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name: v_pk_mul_f16_imm_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: v_pk_mul_f16_imm_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
