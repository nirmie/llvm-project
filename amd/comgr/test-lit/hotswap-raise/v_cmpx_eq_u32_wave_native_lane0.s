; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cmpx_eq_u32_wave_native_lane0_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Bug-Id: 2026-05-27T00-49-13Z_qwen2.5-7b-instruct-002
;
; Pins the CmpxFromLaneId wave-native exemption for the "elect lane 0"
; idiom:
;
;   s_mov_b32 s1, exec_lo                 ; save exec
;   v_mbcnt_lo_u32_b32 v1, exec_lo, 0    ; v1 = lane rank within current exec
;   v_cmpx_eq_u32_e32 0, v1              ; exec = lanes where rank == 0 (lane 0)
;   ...                                  ; only lane 0 executes
;
; Under ModuloReplication (R=2, wave32->wave64) this pattern would let
; BOTH replica lane 0s (lanes 0 and 32) pass the eq-0 test, doubling
; any side-effecting work -- that is the obstruction the classifier was
; designed to catch.
;
; Under WaveNativeProjection (the default for wave32->wave64
; cross-widening) there is only one target wave64.  The phantom lanes
; (bits 32..63 of exec) are hardware-inactive throughout the kernel.
; v_mbcnt_lo(exec_lo, 0) enumerates real lanes 0..W_src-1 only, so
; v_cmpx_eq_u32 0 correctly gates exactly the first real lane.
; There is no second replica; the double-update hazard does not arise.
;
; The fix passes UseWaveNative=true to buildObstructionReport() in
; raiser.cpp (wave-size-obstruction.cpp's second pass is skipped), so
; CmpxFromLaneId sites are not emitted when WaveNativeProjection is used.
;
; The kernel must raise to IR (icmp eq + ballot + and into exec) without
; a pre-translation abort.  The partner test c4_lane_dep_cmpx.s pins
; the MODREP refusal (--disable-wave-native) for the mbcnt-derived
; absolute-lane-position variant.
;
; 33 hits across 9 rocSOLVER bdsqr kernels in fatbin_co_0134.co at
; hotswap commit 688e9c9d1b04.

; CHECK-LABEL: define amdgpu_kernel void @v_cmpx_eq_u32_wave_native_lane0_kernel(
; The v_cmpx_eq_u32 must lower to icmp eq + ballot + and into EXEC.
; CHECK: icmp eq i32
; CHECK: @llvm.amdgcn.ballot
; No pre-translation abort may appear on stdout.
; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK-NOT: CmpxFromLaneId

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cmpx_eq_u32_wave_native_lane0_kernel
	.p2align	8
	.type	v_cmpx_eq_u32_wave_native_lane0_kernel,@function
v_cmpx_eq_u32_wave_native_lane0_kernel:
	; Elect-lane-0 idiom: save exec, compute lane rank within exec,
	; then gate on rank == 0 (only lane 0 proceeds).
	s_mov_b32 s2, exec_lo
	s_wait_xcnt 0x0
	v_mbcnt_lo_u32_b32 v1, s2, 0
	s_mov_b32 s3, exec_lo
	s_wait_xcnt 0x0
	; v_cmpx_eq_u32: compare rank == 0, write result into EXEC.
	v_cmpx_eq_u32_e32 0, v1
	s_cbranch_execz 4
	; Lane 0 work: count active lanes via bcnt and do an atomic add.
	s_bcnt1_i32_b32 s0, s2
	s_delay_alu instid0(SALU_CYCLE_1)
	v_mov_b32_e32 v1, s0
	global_atomic_add_u32 v0, v1, s[0:1] scope:SCOPE_DEV
	s_wait_storecnt 0x0
	; Restore exec.
	s_mov_b32 exec_lo, s3
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cmpx_eq_u32_wave_native_lane0_kernel
		.amdhsa_kernarg_size 264
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 5
		.amdhsa_next_free_sgpr 4
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
    .kernarg_segment_size: 264
    .max_flat_workgroup_size: 1024
    .name:           v_cmpx_eq_u32_wave_native_lane0_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         v_cmpx_eq_u32_wave_native_lane0_kernel.kd
    .vgpr_count:     5
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
