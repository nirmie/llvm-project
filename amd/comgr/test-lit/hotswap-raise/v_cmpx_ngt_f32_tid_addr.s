; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ngt_f32_tid_addr_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for false-positive CmpxFromLaneId on v_cmpx_ngt_f32 when
; the global_load address is derived from workitem ID arithmetic (lshlrev +
; lshl_add_u64) rather than from v_mbcnt_lo lane-index arithmetic.
;
; Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-017
;
; Pattern from rocBLAS trsv kernels with complex<float> PKPS1 (pointer-to-
; pointer-const) operands.  The address registers v[12:13] are built via a
; multi-step chain that starts from the thread-ID register (v0, v_tid):
;
;   1. v_and_b32   v12, tid, mask          ; workitem-index extract (NOT tainted)
;   2. v_lshlrev_b32 v12, 9, v12            ; byte-offset in complex array
;   3. v_lshl_add_u64 v[12:13], v[12:13], 3, s[0:1]  ; final global address
;   4. global_load_b64 v[12:13], v[12:13], off        ; load real+imag floats
;   5. v_cmpx_ngt_f32_e64 |v12|, |v13|               ; compare |real| vs |imag|
;
; The older taint tracker confused v_lshlrev_b32 with a lane-ID instruction
; and tainted v12, leading to a false cross-wave-lane-predicated-exec error.
; After the isMemoryReadOp() fix in wave-size-obstruction.cpp the load
; destination taint is cleared regardless of address taint, so the comparison
; is correctly identified as a non-lane-predicated EXEC update.
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ngt_f32_tid_addr_kernel(
; CHECK: fcmp ule float
; CHECK-NOT: cross-wave-lane-predicated-exec

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ngt_f32_tid_addr_kernel
	.p2align	8
	.type	v_cmpx_ngt_f32_tid_addr_kernel,@function
v_cmpx_ngt_f32_tid_addr_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: extract workitem column index from tid (NOT a lane-ID op).
	; v12 = tid & 0x3ff -- workitem-local index within a tile row.
	v_and_b32_e32 v12, 0x3ff, v0
	; Step 2: multiply by 8 (sizeof complex<float>) to get byte offset.
	; v[12:13] is purely workitem-ID-derived; it must NOT be tainted as a
	; lane ID even though v_lshlrev_b32 resembles an mbcnt-like shift.
	v_lshlrev_b32_e32 v12, 3, v12
	v_mov_b32_e32 v13, 0
	; Step 3: add the base pointer from kernargs: v[12:13] = base + offset.
	v_lshl_add_u64 v[12:13], v[12:13], 0, s[0:1]
	; Step 4: global_load_b64 loads real and imaginary parts of complex<float>.
	; The destination v[12:13] receives memory content (not address taint).
	global_load_b64 v[12:13], v[12:13], off
	s_wait_loadcnt 0x0
	s_wait_xcnt 0x0
	; Step 5: v_cmpx_ngt_f32 compares |real| vs |imag|.  This is NOT a
	; CmpxFromLaneId obstruction: both operands are loaded from global memory.
	; NGT ("not-greater-than") = FCMP_ULE (unordered-or-less-or-equal).
	v_cmpx_ngt_f32_e64 |v12|, |v13|
	s_mov_b32 exec_lo, -1
	global_store_b64 v[0:1], v[12:13], off
	s_wait_storecnt 0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ngt_f32_tid_addr_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 14
		.amdhsa_next_free_sgpr 2
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
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
    .name:           v_cmpx_ngt_f32_tid_addr_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_ngt_f32_tid_addr_kernel.kd
    .vgpr_count:     14
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
