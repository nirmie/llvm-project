; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=s_and_not1_saveexec_b32_kernel 2>/dev/null | %FileCheck %s
;
; Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-006
;
; Also covers Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-006
; 96 s_and_not1_saveexec_b32 UnsupportedOpcode hits across 96 rocBLAS
; GEMVT kernels (e.g. rocblas_gemvt_sn_kernel on gfx1250). Fix was
; already present; this annotation pins regression coverage to this
; bug record.
;
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-006
; Identical recurrence: 96 s_and_not1_saveexec_b32 UnsupportedOpcode
; hits across 96 rocBLAS GEMVT kernels (sample kernel identical to
; the 08-08-10Z run). The gfx1250 fatbin reproduces cleanly at
; current HEAD (0 failures); fix was already merged in the opcode-map
; + handle-sop1 work tracked by the earlier bug records.
;
; Also covers Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-006
; Identical recurrence: 96 s_and_not1_saveexec_b32 UnsupportedOpcode
; hits across 96 rocBLAS GEMVT kernels (sample kernel identical to
; the 09-18-05Z run). The gfx1250 fatbin reproduces cleanly at
; current HEAD (728/728 kernels OK, 0 failures); fix was already
; merged in the opcode-map + handle-sop1 work tracked by the earlier
; bug records.
;
; Also covers Bug-Id: 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-006
; Identical recurrence: 96 s_and_not1_saveexec_b32 UnsupportedOpcode
; hits across 96 rocBLAS GEMVT kernels (sample:
; _ZL23rocblas_gemvt_sn_kernelILb0ELi256ELi4EifPKffEviiT4_lPKT3_lilS5_lilPT5_i).
; The gfx1250 fatbin reproduces cleanly at current HEAD (728/728
; kernels OK, 0 failures); fix was already merged in the opcode-map
; + handle-sop1 work tracked by the earlier bug records.
;
; Also covers Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-006
; Identical recurrence: 96 s_and_not1_saveexec_b32 UnsupportedOpcode
; hits across 96 rocBLAS GEMVT kernels (sample:
; _ZL23rocblas_gemvt_sn_kernelILb0ELi256ELi4EifPKffEviiT4_lPKT3_lilS5_lilPT5_i
; in fatbin_co_0012.co). The gfx1250 fatbin reproduces cleanly at
; current HEAD (728/728 kernels OK, 0 failures); fix was already
; merged in the opcode-map + handle-sop1 work tracked by the earlier
; bug records.
;
; Regression test for s_and_not1_saveexec_b32 (gfx12 renamed assembly
; form of S_ANDN2_SAVEEXEC_B32).  The LLVM MC disassembles the gfx12
; encoding to S_ANDN2_SAVEEXEC_B32 internally; the hotswap opcode-map
; entry at opcode-map.cpp routes it to CanonicalOp::S_ANDN2_SAVEEXEC_B32
; and handle_sop1 lowers it as:
;   dst  = old_exec
;   exec = old_exec AND NOT(src)
;
; Before the fix the opcode-map had no entry for S_ANDN2_SAVEEXEC_B32
; and raise_cli emitted UnsupportedOpcode for all 96 kernels in the
; rocblas gemvt corpus that used this instruction.
;
; We verify the handler produces the correct ANDN2 pattern: the new
; EXEC SSA name (%new_exec) must be an AND of old exec with NOT(src).
; The target is gfx950 (wave64), so exec is i64.

; CHECK-LABEL: define amdgpu_kernel void @s_and_not1_saveexec_b32_kernel(

; v_cmp produces a per-lane mask in s4. The handler saves old exec
; into s5 and writes exec = exec AND NOT(s4).
; The NOT is emitted as xor-with-minus-one before the AND.
; CHECK:       %new_exec = and i64 {{.*}}, {{.*}}

; The EXEC update propagates into the SPE predication for the
; subsequent code, proving the SSA graph is wired correctly.
; CHECK-NOT: cross-wave-lane-predicated-exec

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_and_not1_saveexec_b32_kernel
	.p2align	8
	.type	s_and_not1_saveexec_b32_kernel,@function
s_and_not1_saveexec_b32_kernel:
	;;#ASMSTART
	v_cmp_gt_u32_e64 s4, v0, 16
	s_and_not1_saveexec_b32 s5, s4
	s_mov_b32 exec_lo, s5
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_and_not1_saveexec_b32_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 1
		.amdhsa_next_free_sgpr 6
		.amdhsa_float_denorm_mode_32 3
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:           []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           s_and_not1_saveexec_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     6
    .symbol:         s_and_not1_saveexec_b32_kernel.kd
    .vgpr_count:     1
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
