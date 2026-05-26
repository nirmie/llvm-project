; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=s_load_b64_after_b512_kernel 2>/dev/null | %FileCheck %s
;
; Regression pin for Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-010.
;
; `s_load_b64` reported as UnsupportedOpcode (20 hits) in the double-precision
; rocSOLVER stebz_case1_kernelIdPdEEv kernel.  In that kernel, an s_load_b512
; loads most kernarg slots in one instruction, then a standalone s_load_b64 at
; offset 0x68 fetches a later pointer argument.  The SMEM handler must handle
; S_LOAD_B64 in all positions within a block, not just kernarg-segment loads
; that appear first.
;
; Fix: handle-smem.cpp dispatches S_LOAD_B64 through the generic multi-dword
; GEP+load path regardless of clause position or preceding loads.  The test
; pins that s_load_b64 at offset 0x68 after an s_load_b512 at 0x28 both
; succeed and produce `load i32` pairs from `ptr addrspace(1)`.

; CHECK-LABEL: define amdgpu_kernel void @s_load_b64_after_b512_kernel(
; CHECK: call ptr addrspace(4) @llvm.amdgcn.kernarg.segment.ptr()
; The s_load_b512 at 0x28 must produce dword loads.
; CHECK: load i32, ptr addrspace(1)
; CHECK: load i32, ptr addrspace(1)
; The s_load_b64 at 0x68 must also produce two dword loads.
; CHECK: load i32, ptr addrspace(1)
; CHECK: load i32, ptr addrspace(1)
; CHECK-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b64_after_b512_kernel
	.p2align	8
	.type	s_load_b64_after_b512_kernel,@function
s_load_b64_after_b512_kernel:
	; s[0:1] = kernarg segment ptr.
	; Load 16 dwords (512 bits) from offset 0x28 into s[4:19].
	s_load_b512 s[4:19], s[0:1], 0x28
	s_wait_kmcnt 0x0
	; Now load a 64-bit ptr from offset 0x68 (after the 512-bit block).
	; This is the pattern that triggered the UnsupportedOpcode bug.
	s_clause 0x0
	s_load_b64 s[20:21], s[0:1], 0x68
	s_wait_kmcnt 0x0
	; Use results to prevent DCE.
	v_mov_b32_e32 v0, s20
	v_mov_b32_e32 v1, s21
	v_mov_b32_e32 v2, 0
	global_store_b64 v2, v[0:1], s[4:5]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b64_after_b512_kernel
		.amdhsa_kernarg_size 120
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 3
		.amdhsa_next_free_sgpr 22
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
      - { .address_space: global, .offset:   0, .size: 8, .value_kind: global_buffer }
      - { .offset:   8, .size: 8, .value_kind: by_value }
      - { .offset:  16, .size: 8, .value_kind: by_value }
      - { .offset:  24, .size: 8, .value_kind: by_value }
      - { .offset:  32, .size: 8, .value_kind: by_value }
      - { .offset:  40, .size: 8, .value_kind: by_value }
      - { .offset:  48, .size: 8, .value_kind: by_value }
      - { .offset:  56, .size: 8, .value_kind: by_value }
      - { .address_space: global, .offset: 104, .size: 8, .value_kind: global_buffer }
      - { .offset: 112, .size: 4, .value_kind: by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 120
    .max_flat_workgroup_size: 1024
    .name:           s_load_b64_after_b512_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     22
    .symbol:         s_load_b64_after_b512_kernel.kd
    .vgpr_count:     3
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
