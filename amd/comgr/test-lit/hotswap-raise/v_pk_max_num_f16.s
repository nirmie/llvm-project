; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx1250 --emit-ir=v_pk_max_num_f16_basic_kernel 2>/dev/null | %FileCheck %s --check-prefix=BASIC
; RUN: raise_cli %t.hsaco --target-isa=gfx1250 --emit-ir=v_pk_max_num_f16_clamp_kernel 2>/dev/null | %FileCheck %s --check-prefix=CLAMP
; RUN: raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=v_pk_max_num_f16_basic_kernel 2>/dev/null | %FileCheck %s --check-prefix=CROSS
;
; Pins VOP3P v_pk_max_num_f16 (gfx12 spelling of v_pk_max_f16): packed
; `<2 x half>` lane selection comes from the decoded srcN_modifiers and the
; arithmetic lowers to `llvm.maxnum.v2f16`.  Clamp is post-applied via
; maxnum/minnum.  The opcode-map collapses _num_ back onto V_PK_MAX_F16 on
; gfx950 so the cross-target lift still produces the same intrinsic.
;
; Pins Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-031:
; 48 hits across 48 rocBLAS geam_min_plus kernels (sample:
; _ZN12_GLOBAL__N_120geam_min_plus_kernelIDF16_Dv2_DF16_S1_Li8ELi32ELi64ELi128E...
; in fatbin_co_0034.co) were reported as UnsupportedOpcode for v_pk_max_num_f16
; at hotswap commit 8f2db5ec2edc.  The VOP3P handler under
; CanonicalOp::V_PK_MAX_NUM_F16 in handle-valu-vop3p.cpp emits llvm.maxnum.v2f16
; with op_sel / neg_lo / neg_hi modifier support (added in 66f1a93b62de); all
; 306 kernels in fatbin_co_0034.co raise successfully (306 ok, 0 fail).
;
; Pins Bug-Id 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-031:
; Same UnsupportedOpcode on v_pk_max_num_f16 [VOP3P], 48 hits across 48 rocBLAS
; geam_min_plus_kernel kernels (fatbin_co_0034.co) at hotswap commit
; 8f2db5ec2edc.  The V_PK_MAX_NUM_F16 handler was already in place;
; all 306 kernels in fatbin_co_0034.co raise OK (306 ok, 0 fail).

; BASIC-LABEL: define amdgpu_kernel void @v_pk_max_num_f16_basic_kernel(
; BASIC: call <2 x half> @llvm.maxnum.v2f16(
; BASIC-NOT: fmul <2 x half>

; CLAMP-LABEL: define amdgpu_kernel void @v_pk_max_num_f16_clamp_kernel(
; CLAMP: [[M:%[^ ]+]] = call <2 x half> @llvm.maxnum.v2f16(
; CLAMP: call <2 x half> @llvm.maxnum.v2f16(<2 x half> [[M]],
; CLAMP: call <2 x half> @llvm.minnum.v2f16(

; CROSS-LABEL: define amdgpu_kernel void @v_pk_max_num_f16_basic_kernel(
; CROSS: call <2 x half> @llvm.maxnum.v2f16(
; CROSS-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_pk_max_num_f16_basic_kernel
	.p2align	8
	.type	v_pk_max_num_f16_basic_kernel,@function
v_pk_max_num_f16_basic_kernel:
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_pk_max_num_f16 v3, v0, v1
	s_endpgm

	.globl	v_pk_max_num_f16_clamp_kernel
	.p2align	8
	.type	v_pk_max_num_f16_clamp_kernel,@function
v_pk_max_num_f16_clamp_kernel:
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_pk_max_num_f16 v3, v0, v1 clamp
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_pk_max_num_f16_basic_kernel
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
	.amdhsa_kernel v_pk_max_num_f16_clamp_kernel
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
    .name: v_pk_max_num_f16_basic_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: v_pk_max_num_f16_basic_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
  - .args:
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name: v_pk_max_num_f16_clamp_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: v_pk_max_num_f16_clamp_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
