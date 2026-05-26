; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %not raise_cli %t.hsaco --target-isa=gfx942 --disable-wave-native \
; RUN:     --emit-ir=elect_leader_atomic_cas_kernel 2>&1 | %FileCheck %s --check-prefix=MODREP_STDERR
;
; Under WaveNative (default) the elect-leader v_cmpx_eq 0 of v_mbcnt_lo is
; recognized as ElectLeaderWaveNative and the kernel raises cleanly. The
; global_atomic_cmpswap_b32 is not a race under WaveNative either (SPE diamond
; gates it per-lane). The kernel must produce cmpxchg IR.
; RUN: raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=elect_leader_atomic_cas_kernel 2>/dev/null | %FileCheck %s --check-prefix=WAVENATIVE
;
; Regression fence for Bug 2026-05-25T22-08-35Z_qwen2.5-7b-instruct-003:
; v_mbcnt_lo + v_cmpx_eq 0 (elect-leader) combined with
; global_atomic_cmpswap_b32 falsely triggered cross-wave-replica-race under
; WaveNative when CmpxFromLaneId obstruction blocked the raise path.
; The fix: IsElectLeader sites propagate RewriteId::ElectLeaderWaveNative
; (implemented=true) through the second pass of buildObstructionReport when
; EnableWaveNative is set, so the kernel is oblivious and raises cleanly.

; MODREP_STDERR: transpiler: pre-translation abort:
; MODREP_STDERR-SAME: cross-wave-replica-race
; MODREP_STDERR-SAME: cmpswap

; MODREP_STDERR: NonCommutativeAtomic
; MODREP_STDERR-SAME: Class 3
; MODREP_STDERR: outcome: (c) refuse

; MODREP_STDERR: raise_cli: kernel 'elect_leader_atomic_cas_kernel' failed to raise:
; MODREP_STDERR-SAME: cmpswap

; WAVENATIVE-LABEL: define amdgpu_kernel void @elect_leader_atomic_cas_kernel(
; WAVENATIVE: cmpxchg ptr addrspace(1)

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	elect_leader_atomic_cas_kernel
	.p2align	8
	.type	elect_leader_atomic_cas_kernel,@function
elect_leader_atomic_cas_kernel:
	; Kernel args: ptr global @buf [s[0:1]], i32 @cmp [s2], i32 @new_val [s3]
	s_clause 0x3
	s_load_b64 s[4:5], s[0:1], 0x0   ; buf ptr
	s_load_b32 s6, s[0:1], 0x8       ; cmp
	s_load_b32 s7, s[0:1], 0xc       ; new_val
	s_wait_kmcnt 0x0
	; Elect first active lane via mbcnt_lo(*,0) == 0
	v_mbcnt_lo_u32_b32 v1, s4, 0     ; v1 = mbcnt_lo(s4, 0)
	; Save EXEC, gate to elected lane only
	s_mov_b32 s2, exec_lo
	v_cmpx_eq_u32_e32 0, v1          ; EXEC = ballot(v1 == 0)
	; Elected lane performs the atomic cmpswap
	v_mov_b32 v0, 0
	v_mov_b32 v2, s6                  ; cmp value
	v_mov_b32 v3, s7                  ; new value
	global_atomic_cmpswap_b32 v0, v[0:1], s[4:5] scope:SCOPE_DEV
	; Restore EXEC
	s_mov_b32 exec_lo, s2
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel elect_leader_atomic_cas_kernel
		.amdhsa_kernarg_size 280
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
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
      - { .offset:        12, .size:           4, .value_kind:     by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 280
    .max_flat_workgroup_size: 1024
    .name:           elect_leader_atomic_cas_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         elect_leader_atomic_cas_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
