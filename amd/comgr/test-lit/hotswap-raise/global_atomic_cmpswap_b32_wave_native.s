; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=global_atomic_cmpswap_b32_kernel 2>/dev/null | %FileCheck %s
;
; Pins global_atomic_cmpswap_b32 wave-native exemption: under
; WaveNativeProjection (the default for wave32→wave64 cross-widening) the
; Class 3 NonCommutativeAtomic obstruction is NOT raised because each
; target lane has a unique workitem-id-derived address and the SPE
; `emitUnderExec` diamond gates the atomic through `br i1 %lane_active`.
; The lane-i vs lane-i+W_s replica race modeled by the classifier is a
; modulo-replication artefact; wave-native's independent-half model has
; no replicas. The kernel must lift to `cmpxchg` IR without refusing.
;
; Regression guard for the fix in wave-size-obstruction.cpp that passes
; EnableWaveNative=true to buildObstructionReport(), suppressing the
; NonCommutativeAtomic site for vector atomics under WaveNative.
;
; See also c3_atomic_cas.s which pins the MODREP refusal
; (--disable-wave-native) alongside the WaveNative pass.

; CHECK-LABEL: define amdgpu_kernel void @global_atomic_cmpswap_b32_kernel(
; Under wave-native the handler emits a flat-pointer `cmpxchg`; no
; pre-translation abort may appear.
; CHECK: cmpxchg ptr addrspace(1)
; Negative: no MODREP refusal diagnostic.
; CHECK-NOT: cross-wave-replica-race
; CHECK-NOT: NonCommutativeAtomic

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_atomic_cmpswap_b32_kernel
	.p2align	8
	.type	global_atomic_cmpswap_b32_kernel,@function
global_atomic_cmpswap_b32_kernel:
	; Minimal kernel: load a global pointer from kernargs, do a cmpswap
	; (cmp=v1, new=v0, no RTN form), then end.
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_dual_mov_b32 v2, 0 :: v_dual_mov_b32 v1, 0
	v_mov_b32_e32 v0, 1
	global_atomic_cmpswap_b32 v2, v[0:1], s[0:1] scope:SCOPE_DEV
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_atomic_cmpswap_b32_kernel
		.amdhsa_kernarg_size 264
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 3
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
    .kernarg_segment_size: 264
    .max_flat_workgroup_size: 1024
    .name:           global_atomic_cmpswap_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         global_atomic_cmpswap_b32_kernel.kd
    .vgpr_count:     3
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
