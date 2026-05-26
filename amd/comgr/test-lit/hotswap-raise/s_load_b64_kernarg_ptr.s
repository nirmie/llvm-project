; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=s_load_b64_kernarg_ptr_kernel 2>/dev/null | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-010.
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-010.
;
; s_load_b64 loading a 64-bit pointer from kernarg space (user arg, not a
; hidden-arg field) previously triggered UnsupportedOpcode in handle-smem.cpp
; when encountered in double-precision rocSOLVER kernels (stebz_case1_kernel).
; 20 instances were seen in a single kernel.
;
; The fix recognises s_load_b64 as a standard 2-dword SMEM load and emits
; an amdgcn_s_buffer_load / kernarg pointer load through the normal
; S_LOAD_B32/B64/... dispatch path.

; CHECK-LABEL: define amdgpu_kernel void @s_load_b64_kernarg_ptr_kernel(
; s_load_b64 on a non-kernarg base emits dword loads from addrspace(1) global ptr
; reconstructed from the SGPR pair (ptrtoint -> zext -> shl -> or -> inttoptr pattern).
; CHECK: inttoptr i64 {{.*}} to ptr addrspace(1)
; CHECK: load i32, ptr addrspace(1)
; CHECK-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b64_kernarg_ptr_kernel
	.p2align	8
	.type	s_load_b64_kernarg_ptr_kernel,@function
s_load_b64_kernarg_ptr_kernel:
	; s[0:1] = kernarg segment ptr (enable_sgpr_kernarg_segment_ptr=1)
	; Load first user arg (global pointer) at offset 0
	s_load_b64 s[2:3], s[0:1], 0x0
	; Load second user arg (double scalar) at offset 8
	s_load_b64 s[4:5], s[0:1], 0x8
	s_wait_kmcnt 0x0
	; Use the loaded values in a store (v2:v3 = data, v4 = offset)
	v_mov_b32_e32 v2, s4
	v_mov_b32_e32 v3, s5
	v_mov_b32_e32 v4, 0
	global_store_b64 v4, v[2:3], s[2:3] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b64_kernarg_ptr_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 5
		.amdhsa_next_free_sgpr 6
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
      - { .offset: 8, .size: 8, .value_kind: by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name:           s_load_b64_kernarg_ptr_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     6
    .symbol:         s_load_b64_kernarg_ptr_kernel.kd
    .vgpr_count:     5
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
