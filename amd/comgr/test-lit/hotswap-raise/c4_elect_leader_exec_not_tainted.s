; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=c4_elect_leader_exec_not_tainted_kernel 2>&1 \
; RUN:   | %FileCheck %s
;
; Regression for Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-027.
;
; After an elect-leader s_and_saveexec_b32 (v_mbcnt_lo == 0 feeding vcc),
; the WaveNative handler rewrites the mask to ballot(lane_id==0), producing a
; wave-size-correct EXEC.  The taint tracker must NOT propagate the mbcnt
; SourceTainted into ExecTainted for elect-leader sites.
;
; Without the fix, the elect-leader saveexec sets ExecTainted=true, which then
; propagates into s0 via s_mov_b32 s0, exec_lo. A subsequent s_xor that combines
; exec_lo with that s0 leaves s0 tainted, and the downstream s_and_not1_saveexec_b32
; fires SaveExecFromLaneId as a false positive.
;
; Pattern:
;   1. v_mbcnt_lo  -> v1 = lane_id (tainted)
;   2. v_cmp_eq 0, v1 -> vcc = elect-leader mask (ElectLeaderVcc)
;   3. s_and_saveexec_b32 s2, vcc  <- elect-leader saveexec;
;      ExecTainted MUST remain false (ballot(lane_id==0) is wave-size-correct)
;   4. s_mov_b32 exec_lo, s2  -- restore exec (exec_lo untainted)
;   5. s_mov_b32 s0, exec_lo  -- save exec into s0; s0 NOT tainted with fix
;   6. s_xor_b32 s0, exec_lo, s0  -- s0 = changed lanes; both sources untainted
;   7. s_and_not1_saveexec_b32 s0, s0 -- must NOT fire SaveExecFromLaneId
;      (without fix: step 3 taints EXEC -> step 5 taints s0 -> step 6 leaves
;       s0 tainted -> step 7 fires falsely)
;
; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK-LABEL: define amdgpu_kernel void @c4_elect_leader_exec_not_tainted_kernel(

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	c4_elect_leader_exec_not_tainted_kernel
	.p2align	8
	.type	c4_elect_leader_exec_not_tainted_kernel,@function
c4_elect_leader_exec_not_tainted_kernel:
	s_load_b64 s[2:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	; Step 1: compute lane rank (tainted)
	v_mbcnt_lo_u32_b32 v1, -1, 0
	; Step 2: elect-leader compare -> vcc (ElectLeaderVcc=true)
	v_cmp_eq_u32_e32 vcc_lo, 0, v1
	; Step 3: elect-leader saveexec -- ExecTainted must remain false after this
	s_and_saveexec_b32 s2, vcc_lo
	; Elected lane does some work
	global_store_b32 v1, v0, s[2:3] scale_offset
	s_wait_storecnt 0
	; Step 4: restore EXEC to full set
	s_mov_b32 exec_lo, s2
	; Step 5: save current (restored) exec -- s0 is NOT tainted if fix is correct
	s_mov_b32 s0, exec_lo
	; Step 6: xor saved exec with current exec -- both sources untainted with fix
	s_xor_b32 s0, exec_lo, s0
	; Step 7: ANDN2 saveexec -- must NOT fire SaveExecFromLaneId
	s_and_not1_saveexec_b32 s0, s0
	global_store_b32 v1, v0, s[2:3] scale_offset
	s_wait_storecnt 0
	; Restore exec
	s_or_b32 exec_lo, exec_lo, s0
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel c4_elect_leader_exec_not_tainted_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 4
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
    .name:           c4_elect_leader_exec_not_tainted_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         c4_elect_leader_exec_not_tainted_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
