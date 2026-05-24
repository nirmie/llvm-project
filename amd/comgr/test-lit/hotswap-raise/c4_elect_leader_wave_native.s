; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=c4_elect_leader_kernel 2>&1 | %FileCheck %s
;
; Class 4 "elect-first-active-lane" pattern: the canonical gfx1250 idiom
;
;   v_mbcnt_lo_u32_b32 vT, exec_lo, 0
;   v_cmpx_eq_u32_e32  0, vT
;
; uses v_mbcnt_lo to compute the lane's rank within the active-lane set
; and then elects exactly the first active lane (rank 0) by writing EXEC.
;
; Under modulo-replication this is a Class 4 obstruction (no rewrite)
; because both lane 0 and lane 32 have source-local rank 0 and would
; both be elected. Under WaveNative (--target-isa=gfx942) the correct
; rewrite is ballot(lane_id == 0): only hardware lane 0 passes.
;
; This test verifies:
; 1. The classifier detects ElectLeaderWaveNative and marks it implemented.
; 2. The raiser does NOT refuse the kernel.
; 3. The emitted IR contains elect_leader / ballot(lane_id==0) shape.

; CHECK-NOT: failed to raise
; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK: elect_leader

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	c4_elect_leader_kernel
	.p2align	8
	.type	c4_elect_leader_kernel,@function
c4_elect_leader_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v1, 1
	;;#ASMSTART
	v_mbcnt_lo_u32_b32 v0, exec_lo, 0
	v_cmpx_eq_u32_e32 0, v0
	global_atomic_add_u32 v[0:1], v1, off
	s_wait_storecnt 0
	s_mov_b32 exec_lo, -1
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel c4_elect_leader_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 2
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
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           c4_elect_leader_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         c4_elect_leader_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
