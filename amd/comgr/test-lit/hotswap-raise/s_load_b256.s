; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=s_load_b256_kernel 2>/dev/null | %FileCheck %s
;
; Lift test for `s_load_b256` (S_LOAD_DWORDX8 in pre-gfx11 encoding).
; Pins that the handler emits 8 consecutive i32 loads from a GEP off
; the base SGPR pair and stores them into contiguous SGPR destination
; slots.  The bug that prompted this test: the opcode appeared as
; UnsupportedOpcode at triage time on fatbin_co_0135.co
; (Bug-Id: 2026-05-21T17-54-29Z_qwen2.5-7b-instruct-009).

; CHECK-LABEL: define amdgpu_kernel void @s_load_b256_kernel(

; Kernarg fetch for the base pointer goes through kernarg.segment.ptr.
; CHECK: call ptr addrspace(4) @llvm.amdgcn.kernarg.segment.ptr()

; The 8-dword load expands to 8 individual i32 smem_load* ops
; sourced from the same addrspace(1) base with byte-stride GEPs.
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b256_kernel
	.p2align	8
	.type	s_load_b256_kernel,@function
s_load_b256_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[4:5], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	s_load_b256 s[8:15], s[4:5], 0x0
	s_wait_kmcnt 0
	;;#ASMEND
	v_mov_b32_e32 v1, 0
	global_store_b32 v1, v0, s[4:5]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b256_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 16
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
      - { .actual_access:  read_write, .address_space:  global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           s_load_b256_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     16
    .symbol:         s_load_b256_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
