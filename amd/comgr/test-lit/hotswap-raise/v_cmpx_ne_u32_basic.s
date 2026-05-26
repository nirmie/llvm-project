; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_ne_u32_basic_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Basic lowering test for v_cmpx_ne_u32: verifies that the 32-bit unsigned
; NE compare writes EXEC via ballot.i64 + AND, matching the V_CMPX handler
; shape in handle-valu-vcmp.cpp.
;
; Pattern:
;   v_cmpx_ne_u32 0, v0
; Expected IR:
;   %vcmp = icmp ne i32 <v0>, 0
;   %cmpx_ballot = call i64 @llvm.amdgcn.ballot.i64(i1 %vcmp)
;   %cmpx_exec = and i64 <prior_exec>, %cmpx_ballot
;
; Pins Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-015:
; 20 rocBLAS iamax/iamin kernels were refused with UnsupportedOpcode on
; v_cmpx_ne_u32 at hotswap commit 8f2db5ec2edc. The fix added the generic
; V_CMPX handler in handle-valu-vcmp.cpp that routes all V_CMPX_* variants
; through parseVCmpPseudoName() -> CanonicalOp::V_CMPX.
;
; This exercises the opcode-map parser path:
;   V_CMPX_NE_U32 -> CanonicalOp::V_CMPX, VCmpMeta{ICMP_NE, 32, IsFloat=false}
; which drives the 32-bit src loading in handleValuVcmp().

; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_ne_u32_basic_kernel(
; The handler emits ICmp NE (with imm operand first in LLVM canonical order),
; ballot.i64, and AND into EXEC.
; CHECK:      %vcmp = icmp ne i32 0, {{.*}}
; CHECK-NEXT: %cmpx_ballot = call i64 @llvm.amdgcn.ballot.i64(i1 %vcmp)
; CHECK-NEXT: %cmpx_exec = and i64 {{[^,]+}}, %cmpx_ballot

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_ne_u32_basic_kernel
	.p2align	8
	.type	v_cmpx_ne_u32_basic_kernel,@function
v_cmpx_ne_u32_basic_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Load a 32-bit value from memory (not lane-ID-derived).
	; v[2:3] holds the 64-bit global address, v0 receives the loaded value.
	global_load_b32 v0, v[2:3], off
	s_wait_loadcnt 0x0
	; v_cmpx_ne_u32: compare v0 != 0, write result to EXEC.
	v_cmpx_ne_u32_e32 0, v0
	global_store_b32 v[2:3], v0, off
	s_wait_storecnt 0
	s_mov_b32 exec_lo, -1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_ne_u32_basic_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 3
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_cmpx_ne_u32_basic_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     3
    .symbol:         v_cmpx_ne_u32_basic_kernel.kd
    .vgpr_count:     3
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
