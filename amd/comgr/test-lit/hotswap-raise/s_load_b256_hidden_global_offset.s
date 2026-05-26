; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=s_load_b256_hidden_global_offset_kernel 2>/dev/null | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T18-08-17Z_qwen2.5-7b-instruct-006.
;
; An s_load_b256 (8-dword scalar load) issued from the kernarg segment pointer
; at an offset that starts inside the hidden-arg region.  The 32-byte load
; spans:
;   dwords 0-1: hidden_global_offset_x (i64, 8 bytes, offset 8)
;   dwords 2-3: hidden_global_offset_y (i64, 8 bytes, offset 16)
;   dwords 4-5: hidden_global_offset_z (i64, 8 bytes, offset 24)
;   dwords 6-7: bytes 32-39 - past end of defined hidden_* args (no entry)
;
; Prior to the fix, two bugs caused failure:
;   1. hidden_global_offset_x/y/z were not recognized in the hidden-arg
;      classifier (kernarg-layout.cpp), causing UnsupportedHidden and a
;      "unsupported source hidden argument kind 'hidden_global_offset_x'"
;      error for s_load_b64 at the same offset.
;   2. The per-dword loop in handle-smem.cpp failed with "spans non-hidden
;      bytes" when a wide load (s_load_b256) reached past the last defined
;      hidden_* arg into the implicit-arg block's trailing bytes.
;
; Fix:
;   * kernarg-layout.h/cpp: added HiddenGlobalOffsetX/Y/Z to the enum and
;     classifier.
;   * source-hidden-args.cpp: emitHiddenGlobalOffset() reads the global
;     offset from amdgcn_implicitarg_ptr at byte offsets 0/8/16 for X/Y/Z.
;   * handle-smem.cpp: the per-dword loop now falls back to
;     amdgcn_implicitarg_ptr for unmatched (past-end-of-hidden) dwords
;     instead of failing with "spans non-hidden bytes".

; CHECK-LABEL: define amdgpu_kernel void @s_load_b256_hidden_global_offset_kernel(

; hidden_global_offset_x/y/z are synthesised via amdgcn_implicitarg_ptr.
; CHECK: call ptr addrspace(4) @llvm.amdgcn.implicitarg.ptr()
; CHECK: load i64, ptr addrspace(4)

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b256_hidden_global_offset_kernel
	.p2align	8
	.type	s_load_b256_hidden_global_offset_kernel,@function
s_load_b256_hidden_global_offset_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; s[0:1] = kernarg-segment-ptr pair (enable_sgpr_kernarg_segment_ptr=1)
	;;#ASMSTART
	; Load 32 bytes starting at implicit-args base (byte 8):
	;   bytes  8-15: hidden_global_offset_x (i64)
	;   bytes 16-23: hidden_global_offset_y (i64)
	;   bytes 24-31: hidden_global_offset_z (i64)
	;   bytes 32-39: past end of defined hidden_* args
	s_load_b256 s[4:11], s[0:1], 0x8
	s_wait_kmcnt 0
	;;#ASMEND
	; Use results to prevent DCE.
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	global_store_b64 v2, v[0:1], s[0:1]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b256_hidden_global_offset_kernel
		.amdhsa_kernarg_size 48
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 3
		.amdhsa_next_free_sgpr 12
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
      - .offset:         8
        .size:           8
        .value_kind:     hidden_global_offset_x
      - .offset:         16
        .size:           8
        .value_kind:     hidden_global_offset_y
      - .offset:         24
        .size:           8
        .value_kind:     hidden_global_offset_z
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 48
    .max_flat_workgroup_size: 1024
    .name:           s_load_b256_hidden_global_offset_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     12
    .sgpr_spill_count: 0
    .symbol:         s_load_b256_hidden_global_offset_kernel.kd
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
