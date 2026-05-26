; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=c4_saveexec_interleaved_cmpx_kernel 2>&1 \
; RUN:   | %FileCheck %s
;
; Regression for bug 2026-05-26T04-13-44Z_qwen2.5-7b-instruct-014.
;
; A v_cmpx_eq_u32 that does NOT write VCC (GFX11+ nosdst/e64 form) was
; unconditionally clearing ElectLeaderVcc in findLanePredicatedExecSites.
; When such a v_cmpx appears between the elect-leader v_cmp_eq (that wrote
; vcc_lo) and the downstream s_and_saveexec_b32, the saveexec was not
; recognized as an elect-leader site and the kernel was refused with
; cross-wave-lane-predicated-exec.
;
; Pattern (mirrors the rocprim lookback-scan generic kernel):
;   1. v_mbcnt_lo_u32_b32 vT, -1, 0       -- elect-leader candidate
;   2. v_cmp_eq_u32 vcc, 0, vT            -- sets ElectLeaderVcc=true
;   3. v_cmpx_eq_u32_e64 s0, vA           -- unrelated cmpx; does NOT write VCC
;                                          -- MUST NOT clear ElectLeaderVcc
;   4. s_and_saveexec_b32 sN, vcc         -- should be recognized as elect-leader
;
; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK-LABEL: define amdgpu_kernel void @c4_saveexec_interleaved_cmpx_kernel(
; CHECK: vcc_ballot

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	c4_saveexec_interleaved_cmpx_kernel
	.p2align	8
	.type	c4_saveexec_interleaved_cmpx_kernel,@function
c4_saveexec_interleaved_cmpx_kernel:
	s_clause 0x1
	s_load_b64 s[2:3], s[0:1], 0x0
	s_load_b32 s4, s[0:1], 0x8
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: compute lane rank
	v_mbcnt_lo_u32_b32 v1, -1, 0
	; Step 2: elect-leader compare into VCC
	v_cmp_eq_u32_e32 vcc_lo, 0, v1
	; Step 3: unrelated v_cmpx (e64, writes s0 not VCC) -- must NOT clear ElectLeaderVcc
	v_cmpx_eq_u32_e64 s0, v0
	; Step 4: s_and_saveexec reads VCC (elect-leader mask)
	s_and_saveexec_b32 s1, vcc_lo
	; Elected lane stores result
	v_mov_b32_e32 v2, 1
	global_store_b32 v1, v2, s[2:3] scale_offset
	s_wait_storecnt 0
	; Restore EXEC
	s_mov_b32 exec_lo, s1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel c4_saveexec_interleaved_cmpx_kernel
		.amdhsa_kernarg_size 280
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
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
      - { .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
      - { .offset:         8, .size:           4, .value_kind:     by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 280
    .max_flat_workgroup_size: 1024
    .name:           c4_saveexec_interleaved_cmpx_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     5
    .symbol:         c4_saveexec_interleaved_cmpx_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
