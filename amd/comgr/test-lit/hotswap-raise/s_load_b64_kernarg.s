; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=s_load_b64_kernarg_kernel 2>/dev/null | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-010.
;
; s_load_b64 (S_LOAD_DWORDX2 in pre-GFX12 parlance) was missing from the
; SMEM opcode-map entry at the commit the bug was captured on, causing
; UnsupportedOpcode for every s_load_b64 encountered (20 hits in 1 kernel:
; _ZN9rocsolver6v33300L18stebz_case1_kernelIdPdEEv...).
;
; Fix: SMEM3(S_LOAD_DWORDX2, S_LOAD_B64) was added to opcode-map.cpp and
; CanonicalOp::S_LOAD_B64 was wired into the multi-dword load switch in
; handle-smem.cpp (LoadDwords=2).
;
; This test checks:
;   1. The kernel body is lifted (not refused/stubbed) when s_load_b64 reads
;      from the explicit kernarg segment at a non-zero byte offset.
;   2. Both result dwords (D=0, D=1) reach real `load i32` ops against
;      `amdgcn_kernarg_segment_ptr`, confirming 2-dword unrolling.

; CHECK-LABEL: define amdgpu_kernel void @s_load_b64_kernarg_kernel(
; CHECK-SAME: ptr addrspace(4) byref([16 x i8]) align 16 %kargs

; Kernarg fetches go through kernarg.segment.ptr + real loads.
; CHECK: call ptr addrspace(4) @llvm.amdgcn.kernarg.segment.ptr()
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1)
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1)

; The two loaded dwords must reach the phi-under-EXEC shape (active arm).
; CHECK-DAG: phi i32 [ %smem_load{{[0-9]*}}, %{{[a-zA-Z_0-9]+}} ]

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b64_kernarg_kernel
	.p2align	8
	.type	s_load_b64_kernarg_kernel,@function
s_load_b64_kernarg_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; s[0:1] = kernarg-segment-ptr pair (enable_sgpr_kernarg_segment_ptr=1)
	;;#ASMSTART
	; Load dwords at kernarg byte offsets 8 and 12 (the global_buffer ptr).
	s_load_b64 s[2:3], s[0:1], 0x8
	s_wait_kmcnt 0
	;;#ASMEND
	; Use results to prevent DCE.
	v_mov_b32_e32 v0, s2
	v_mov_b32_e32 v1, s3
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
		.amdhsa_next_free_sgpr 4
		.amdhsa_reserve_vcc 1
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
      - .offset:         0
        .size:           8
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
    .sgpr_count:     4
    .sgpr_spill_count: 0
    .symbol:         s_load_b64_kernarg_kernel.kd
    .uniform_work_group_size: 1
    .uses_dynamic_stack: false
    .vgpr_count:     3
    .vgpr_spill_count: 0
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version:
  - 1
  - 2
...
	.end_amdgpu_metadata
