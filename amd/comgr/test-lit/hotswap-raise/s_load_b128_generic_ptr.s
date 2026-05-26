; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=s_load_b128_generic_kernel 2>/dev/null | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-009.
;
; Pins that s_load_b128 (S_LOAD_DWORDX4 in pre-gfx11 encoding) is correctly
; handled when the base SGPR pair is a generic runtime pointer (loaded from
; the kernarg segment, not the kernarg-segment-ptr itself), and the byte
; offset is non-zero.  In the failing kernel, 18 s_load_b128 instructions
; across two kernel variants used this pattern to read 16-byte chunks from
; struct fields at offsets like 0x18 (24) and 0x28 (40) from a runtime
; pointer.  The handler must emit 4 consecutive i32 GEP+load pairs from
; addrspace(1), one per destination SGPR.

; CHECK-LABEL: define amdgpu_kernel void @s_load_b128_generic_kernel(

; s_load_b64 fetches the runtime pointer from kernargs.
; CHECK: call ptr addrspace(4) @llvm.amdgcn.kernarg.segment.ptr()

; The 4-dword load at offset 24 expands to 4 individual i32 smem_load ops
; from an addrspace(1) base (the runtime pointer) with byte-stride GEPs.
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b128_generic_kernel
	.p2align	8
	.type	s_load_b128_generic_kernel,@function
s_load_b128_generic_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; Load a runtime pointer from kernarg slot 0 (8 bytes).
	s_load_b64 s[4:5], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Now use s_load_b128 against the runtime pointer at byte offset 0x18 (24).
	s_load_b128 s[8:11], s[4:5], 0x18
	s_wait_kmcnt 0
	;;#ASMEND
	; Use results so the loads are not DCE'd.
	v_mov_b32_e32 v0, s8
	v_mov_b32_e32 v1, s9
	v_mov_b32_e32 v2, s10
	v_mov_b32_e32 v3, s11
	v_mov_b32_e32 v4, 0
	global_store_b128 v4, v[0:3], s[4:5]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b128_generic_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 5
		.amdhsa_next_free_sgpr 12
		.amdhsa_reserve_vcc 1
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 2
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .actual_access:  read_write, .address_space:  global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           s_load_b128_generic_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     12
    .sgpr_spill_count: 0
    .symbol:         s_load_b128_generic_kernel.kd
    .uniform_work_group_size: 1
    .uses_dynamic_stack: false
    .vgpr_count:     5
    .vgpr_spill_count: 0
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version:
  - 1
  - 2
...
	.end_amdgpu_metadata
