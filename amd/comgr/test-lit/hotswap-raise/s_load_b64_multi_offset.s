; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=s_load_b64_multi_offset_kernel 2>/dev/null | %FileCheck %s
;
; Regression pin for Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-010.
;
; `s_load_b64` at large kernarg byte offsets (0x68, 0xa0) reported as
; UnsupportedOpcode in double-precision rocSOLVER stebz_case1_kernel (20 hits).
; The kernel has many global-pointer and scalar args so s_load_b64 targets
; offsets well beyond the first few dwords.
;
; Fix: handle-smem.cpp already dispatches S_LOAD_B64 through the generic
; multi-dword GEP+load path for any byte offset; the test pins that all
; s_load_b64 instances at arbitrary large offsets succeed and produce
; `load i32` pairs from `ptr addrspace(1)`.

; CHECK-LABEL: define amdgpu_kernel void @s_load_b64_multi_offset_kernel(
; Each s_load_b64 pair must emit two consecutive dword loads.
; CHECK: call ptr addrspace(4) @llvm.amdgcn.kernarg.segment.ptr()
; CHECK: load i32, ptr addrspace(1)
; CHECK: load i32, ptr addrspace(1)
; CHECK: load i32, ptr addrspace(1)
; CHECK: load i32, ptr addrspace(1)
; CHECK-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b64_multi_offset_kernel
	.p2align	8
	.type	s_load_b64_multi_offset_kernel,@function
s_load_b64_multi_offset_kernel:
	; s[0:1] = kernarg segment ptr.  Kernel has many args; load pointers
	; at large byte offsets mimicking stebz_case1_kernelIdPdEEv (20 hits).
	s_clause 0x3
	s_load_b64 s[4:5], s[0:1], 0x0          ; ptr arg at offset 0
	s_load_b64 s[6:7], s[0:1], 0x68         ; ptr arg at offset 104
	s_load_b64 s[8:9], s[0:1], 0xa0         ; ptr arg at offset 160
	s_load_b32 s10, s[0:1], 0xa8            ; scalar at offset 168
	s_wait_kmcnt 0x0
	; Use results so the loads are not DCE'd before emit-ir dump.
	v_mov_b32_e32 v0, s6
	v_mov_b32_e32 v1, s7
	v_mov_b32_e32 v2, 0
	global_store_b64 v2, v[0:1], s[4:5]
	v_mov_b32_e32 v0, s8
	v_mov_b32_e32 v1, s9
	global_store_b64 v2, v[0:1], s[4:5]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b64_multi_offset_kernel
		.amdhsa_kernarg_size 176
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 3
		.amdhsa_next_free_sgpr 11
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
      - { .offset:  64, .size: 8, .value_kind: by_value }
      - { .address_space: global, .offset: 104, .size: 8, .value_kind: global_buffer }
      - { .offset: 112, .size: 8, .value_kind: by_value }
      - { .offset: 120, .size: 8, .value_kind: by_value }
      - { .offset: 128, .size: 8, .value_kind: by_value }
      - { .offset: 136, .size: 8, .value_kind: by_value }
      - { .offset: 144, .size: 8, .value_kind: by_value }
      - { .offset: 152, .size: 8, .value_kind: by_value }
      - { .address_space: global, .offset: 160, .size: 8, .value_kind: global_buffer }
      - { .offset: 168, .size: 4, .value_kind: by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 176
    .max_flat_workgroup_size: 1024
    .name:           s_load_b64_multi_offset_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     11
    .symbol:         s_load_b64_multi_offset_kernel.kd
    .vgpr_count:     3
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
