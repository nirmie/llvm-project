; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ngt_f32_scratch_memload_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for UnsupportedOpcode / false CmpxFromLaneId on
; v_cmpx_ngt_f32 when the cmpx operands are loaded from scratch (private)
; memory rather than derived from v_mbcnt_*.
;
; Pattern from rocBLAS trsv kernels with rocblas_complex_num<float> operands
; (Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-017):
;   1. scratch_store_b64 stores two f32 values into private segment
;   2. scratch_load_b64 reads them back — NOT lane-indexed data
;   3. v_cmpx_ngt_f32_e64 |v0|, |v1| compares |real| vs |imag|
;      -- must NOT be flagged as CmpxFromLaneId, must lower to fcmp ule
;
; Without the fix the kernel refuses with UnsupportedOpcode on v_cmpx_ngt_f32.
; With the fix the kernel raises successfully and emits fcmp ule.
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ngt_f32_scratch_memload_kernel(
; CHECK: fcmp ule float

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ngt_f32_scratch_memload_kernel
	.p2align	8
	.type	v_cmpx_ngt_f32_scratch_memload_kernel,@function
v_cmpx_ngt_f32_scratch_memload_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: move two float constants (real=1.0, imag=2.0) into v[0:1].
	;         These represent a rocblas_complex_num<float> pair.
	v_mov_b32_e32 v0, 0x3f800000
	v_mov_b32_e32 v1, 0x40000000
	; Step 2: store the complex float pair to scratch (private) memory.
	scratch_store_b64 off, v[0:1], off offset:0
	s_wait_storecnt 0x0
	; Step 3: load the complex float pair back from scratch into v[0:1].
	;         The destination holds memory content, NOT lane indices.
	scratch_load_b64 v[0:1], off, off offset:0
	s_wait_loadcnt 0x0
	; Step 4: v_cmpx_ngt_f32 |v0|, |v1| — compares |real| vs |imag|.
	;         Operands are scratch-memory values, NOT lane-index-derived.
	;         Must NOT be classified as CmpxFromLaneId.
	;         NGT == not-greater-than == unordered-less-or-equal (FCMP_ULE).
	v_cmpx_ngt_f32_e64 |v0|, |v1|
	global_store_b64 v[2:3], v[0:1], off
	s_wait_storecnt 0
	s_mov_b64 exec, -1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ngt_f32_scratch_memload_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 2
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
		.amdhsa_private_segment_fixed_size 8
		.amdhsa_enable_private_segment 1
	.end_amdhsa_kernel
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
    .name:           v_cmpx_ngt_f32_scratch_memload_kernel
    .private_segment_fixed_size: 8
    .sgpr_count:     2
    .symbol:         v_cmpx_ngt_f32_scratch_memload_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
