; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --write-hsaco=%t.out --kernel=no_b0_revision_kernel 2>&1 | %FileCheck %s --check-prefix=PIPE
; RUN: %llvm-objdump -s --section=.note %t.out 2>&1 | %FileCheck %s --check-prefix=NOTE
;
; Regression test for: GCNSubtarget enables FeatureGFX1250B0 unconditionally
; (cl::init(true) in GCNSubtarget.cpp), which caused llc to emit
; `.gfx1250_revision: B0` in the .note section of every produced code object
; regardless of target ISA.  The ROCm 7.x HSA runtime rejects code objects
; with that field on non-gfx1250 hardware (empty_output failure).
; The fix passes -amdgpu-gfx1250-b0-specific=false to llc for non-gfx1250
; targets in pipeline.cpp::raiseAndCompileKernel.

; PIPE: raise_cli: wrote
; PIPE-SAME: no_b0_revision_kernel

; NOTE-NOT: gfx1250_revision

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	no_b0_revision_kernel
	.p2align	8
	.type	no_b0_revision_kernel,@function
no_b0_revision_kernel:
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, 42
	global_store_b32 v1, v0, s[0:1] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel no_b0_revision_kernel
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
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name: no_b0_revision_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 2
    .symbol: no_b0_revision_kernel.kd
    .vgpr_count: 2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
