; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=s_load_b128_span_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-25T22-08-35Z_qwen2.5-7b-instruct-009.
;
; Also covers Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-009
; Also covers Bug-Id: 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-009
; Also covers Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-009
; Also covers Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-009
; Identical recurrence: 18 s_load_b128 UnsupportedOpcode hits across 2
; rocsolver kernels (sample: _ZN9rocsolver6v33300L25stedcx_mergeUpdate_kernelIfEEviiPT_lS3_iilS3_S3_Pi
; on gfx1250). The fatbin reproduces cleanly at current HEAD (37/37
; kernels OK, 0 failures); fix was already merged in the smem-b128-hidden-arg-span
; work tracked by the earlier bug records.
;
; An s_load_b128 (4-dword = 16-byte SMEM load) whose base is the
; kernarg-segment-ptr pair and whose byte offset falls within the source
; ISA's implicit-args block previously failed with "source hidden-arg SMEM
; load spans non-hidden bytes" (UnsupportedShape/UnsupportedOpcode) when a
; dword inside the 16-byte window straddles a hidden-arg/gap boundary --
; i.e. byte 0 of that dword is inside a classified hidden-arg field but a
; later byte falls in unclassified padding.
;
; Fix: SourceHiddenArgValue gains IsGapSpan=true to flag this case.  In
; handle-smem.cpp the multi-dword loop now falls back to an
; amdgcn_implicitarg_ptr load (at the dword's rebased offset) instead of
; emitting a hard unsupportedShape failure.
;
; Layout (ImplicitArgsBase = 8):
;   offset  8: hidden_block_count_x (4 bytes)  → fully classified
;   offset 12: hidden_group_size_x  (2 bytes)  → bytes 12-13 classified,
;                                                 bytes 14-15 unclassified gap
;   offset 16: hidden_global_offset_x (8 bytes)→ classified
;
; s_load_b128 at byte offset 8 loads dwords D=0..3 (bytes 8-23):
;   D=0 (bytes  8-11): hidden_block_count_x — fully classified → dispatch.ptr
;   D=1 (bytes 12-15): bytes 12-13 = hidden_group_size_x, bytes 14-15 = gap
;                       → IsGapSpan=true → implicitarg_ptr at rebased offset 4
;   D=2 (bytes 16-19): hidden_global_offset_x[0..3] → implicitarg_ptr
;   D=3 (bytes 20-23): hidden_global_offset_x[4..7] → implicitarg_ptr

; CHECK-LABEL: define amdgpu_kernel void @s_load_b128_span_kernel(
; D=0 is a fully classified dword; it comes from dispatch.ptr.
; CHECK: call ptr addrspace(4) @llvm.amdgcn.dispatch.ptr()
; D=1 is the spanning dword; it must use implicitarg_ptr (not a hard failure).
; CHECK: call ptr addrspace(4) @llvm.amdgcn.implicitarg.ptr()
; CHECK: %impl_span{{[a-z_0-9]*}}load = load i32, ptr addrspace(4)

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b128_span_kernel
	.p2align	8
	.type	s_load_b128_span_kernel,@function
s_load_b128_span_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; s[0:1] is the kernarg-segment-ptr pair (enable_sgpr_kernarg_segment_ptr=1).
	; Load 4 dwords (16 bytes) starting at ImplicitArgsBase (offset 8).
	;;#ASMSTART
	s_load_b128 s[4:7], s[0:1], 0x8
	s_wait_kmcnt 0
	;;#ASMEND
	; Use results so the loads are not DCE'd.
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_mov_b32_e32 v2, s6
	v_mov_b32_e32 v3, s7
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b128_span_kernel
		.amdhsa_kernarg_size 128
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_system_sgpr_workgroup_id_x 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
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
      - .offset:         0
        .size:           8
        .value_kind:     by_value
      - .offset:         8
        .size:           4
        .value_kind:     hidden_block_count_x
      - .offset:         12
        .size:           2
        .value_kind:     hidden_group_size_x
      - .offset:         16
        .size:           8
        .value_kind:     hidden_global_offset_x
      - .offset:         24
        .size:           8
        .value_kind:     hidden_global_offset_y
      - .offset:         32
        .size:           8
        .value_kind:     hidden_global_offset_z
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 128
    .max_flat_workgroup_size: 1024
    .name:           s_load_b128_span_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .sgpr_spill_count: 0
    .symbol:         s_load_b128_span_kernel.kd
    .uniform_work_group_size: 1
    .uses_dynamic_stack: false
    .vgpr_count:     4
    .vgpr_spill_count: 0
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version:
  - 1
  - 2
...
	.end_amdgpu_metadata
