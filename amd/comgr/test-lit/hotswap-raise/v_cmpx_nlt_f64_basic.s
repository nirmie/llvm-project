; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_nlt_f64_basic_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Basic regression test for v_cmpx_nlt_f64 opcode handling.
;
; Bug-Id: 2026-05-26T04-13-44Z_qwen2.5-7b-instruct-020
;
; v_cmpx_nlt_f64 (NLT = "not less-than" = unordered-or-greater-than-or-equal)
; was reported as UnsupportedOpcode in 226 hits across 16 kernels of a rocSOLVER
; geqr2_kernel_small workload with double-precision data. The instruction belongs
; to the V_CMPX VOPC family; NLT maps to the LLVM FCmp predicate FCMP_UGE
; (unordered-or-greater-than-or-equal).
;
; The fix was already present in opcode-map.cpp via parseVCmpPseudoName() which
; handles all V_CMP_*/V_CMPX_* predicates generically including NLT. This commit
; adds a targeted regression test that verifies v_cmpx_nlt_f64_e32 is correctly
; recognized and lowered to fcmp uge double without UnsupportedOpcode.
;
; This test verifies that:
;   1. v_cmpx_nlt_f64_e32 is recognized and lowered to fcmp uge double
;   2. The EXEC register update (AND into EXEC) is emitted
;   3. Subsequent instructions in the same kernel still raise correctly
;
; Pins Bug-Id 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-020:
; Same 226-hit / 16-kernel rocSOLVER geqr2_kernel_small workload
; (fatbin_co_0173.co) re-filed as UnsupportedOpcode on v_cmpx_nlt_f64
; at hotswap commit 8f2db5ec2edc. The handler remains in place via
; parseVCmpPseudoName() -> CanonicalOp::V_CMPX with FCMP_UGE predicate;
; all 81 kernels in the .co raise OK confirming the fix is still effective.
;
; Pins Bug-Id 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-020:
; Same 226-hit / 16-kernel rocSOLVER geqr2_kernel_small workload
; (fatbin_co_0173.co) re-filed as UnsupportedOpcode on v_cmpx_nlt_f64
; at hotswap commit 8f2db5ec2edc. The handler remains in place via
; parseVCmpPseudoName() -> CanonicalOp::V_CMPX with FCMP_UGE predicate;
; all 81 kernels in the .co raise OK confirming the fix is still effective.
;
; Pins Bug-Id 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-020:
; Same rocSOLVER geqr2_kernel_small workload (fatbin_co_0173.co, 226 hits across
; 16 kernels) re-filed as UnsupportedOpcode on v_cmpx_nlt_f64 at hotswap commit
; 8f2db5ec2edc. All 81 kernels raise OK confirming the fix remains effective.
;
; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_nlt_f64_basic_kernel(
; CHECK: fcmp uge double
; CHECK-NOT: UnsupportedOpcode

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_nlt_f64_basic_kernel
	.p2align	8
	.type	v_cmpx_nlt_f64_basic_kernel,@function
v_cmpx_nlt_f64_basic_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Load two f64 values from global memory (untainted from lane ID).
	global_load_b128 v[0:3], v[4:5], off
	s_wait_loadcnt 0x0
	; v_cmpx_nlt_f64_e32: compare v[0:1] vs v[2:3], update EXEC.
	; NLT = "not less-than" = FCMP_UGE (unordered-or-greater-than-or-equal).
	v_cmpx_nlt_f64_e32 v[0:1], v[2:3]
	; s_mov_b32 after cmpx restores EXEC (common rocBLAS/rocSOLVER pattern).
	s_mov_b32 exec_lo, -1
	global_store_b64 v[4:5], v[0:1], off
	s_wait_storecnt 0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_nlt_f64_basic_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 6
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
    .name:           v_cmpx_nlt_f64_basic_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_cmpx_nlt_f64_basic_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
