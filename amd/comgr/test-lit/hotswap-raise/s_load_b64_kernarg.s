; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=s_load_b64_kernarg_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression pin for Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-010.
;
; `s_load_b64` (2-dword SMEM load from the kernarg segment) was reported
; as UnsupportedOpcode in the SMEM handler for kernels that fetch a 64-bit
; global pointer at a constant byte offset from the kernarg-segment-ptr pair.
; The canonical pattern is:
;   s_load_b64 s[N:N+1], s[0:1], <imm_byte_offset>
; where s[0:1] is the kernarg-segment-ptr pair and the offset addresses a
; `global_buffer` argument that is a plain 64-bit pointer.
;
; The fix adds CanonicalOp::S_LOAD_B64 to the multi-dword GEP+load arm in
; handle-smem.cpp (LoadDwords=2), producing two consecutive `load i32` ops
; against a `ptr addrspace(1)` cast of `amdgcn_kernarg_segment_ptr`.
;
; Test shape:
;   kernarg layout: [i32 by_value @ 0] [i64 global_ptr @ 8]
;   instruction under test: s_load_b64 s[2:3], s[0:1], 0x8
;   expected IR: two `load i32` from kernarg_segment_ptr + 8 / + 12
;   both results must flow into phi-under-EXEC shapes (proves the lift
;   succeeded rather than stubbing the kernel body).

; CHECK-LABEL: define amdgpu_kernel void @s_load_b64_kernarg_kernel(

; Kernarg fetches go through `llvm.amdgcn.kernarg.segment.ptr` + a
; real load on `ptr addrspace(1)`.
; CHECK: call ptr addrspace(4) @llvm.amdgcn.kernarg.segment.ptr()
; CHECK: load i32, ptr addrspace(1) %{{[^,]+}}, align 4

; Both dwords of the s_load_b64 result must flow into phi-under-EXEC
; shapes (proves the lift didn't refuse and stub the kernel body).
; CHECK-DAG: phi i32 [ %smem_load{{[0-9]*}}, %{{[a-zA-Z_0-9]+}}
; CHECK-DAG: phi i32 [ %smem_load{{[0-9]*}}, %{{[a-zA-Z_0-9]+}}

; A zero/undef substitution on the active arm would indicate a silent miss.
; CHECK-NOT: phi i32 [ i32 0, %{{[a-zA-Z_0-9]+}}
; CHECK-NOT: phi i32 [ i32 undef, %{{[a-zA-Z_0-9]+}}

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b64_kernarg_kernel
	.p2align	8
	.type	s_load_b64_kernarg_kernel,@function
s_load_b64_kernarg_kernel:              ; @s_load_b64_kernarg_kernel
; %bb.0:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; s[0:1] is the kernarg-segment-ptr pair (enable_sgpr_kernarg_segment_ptr=1).
	; Load the by_value i32 arg at offset 0 and the global_buffer ptr at offset 8.
	s_clause 0x1
	s_load_b32 s4, s[0:1], 0x0
	;;#ASMSTART
	s_load_b64 s[2:3], s[0:1], 0x8
	s_wait_kmcnt 0
	;;#ASMEND
	s_wait_kmcnt 0x0
	; Store both dwords of the loaded pointer so they reach the phi.
	v_dual_mov_b32 v0, s2 :: v_dual_mov_b32 v1, s3
	v_mov_b32_e32 v2, 0
	global_store_b64 v2, v[0:1], s[2:3]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b64_kernarg_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 3
		.amdhsa_next_free_sgpr 5
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
      - .offset:         0
        .size:           4
        .value_kind:     by_value
      - .address_space:  global
        .offset:         8
        .size:           8
        .value_kind:     global_buffer
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name:           s_load_b64_kernarg_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     5
    .symbol:         s_load_b64_kernarg_kernel.kd
    .vgpr_count:     3
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
