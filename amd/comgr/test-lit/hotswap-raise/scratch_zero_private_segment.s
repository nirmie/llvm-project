; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=scratch_zero_pvt_seg_kernel 2>/dev/null | %FileCheck %s
;
; Regression test for scratch_load_b64 / scratch_load_b128 / scratch_store_b64 /
; scratch_store_b128 when the source KD has private_segment_fixed_size=0.
;
; gfx1250 kernels compiled with the flat-scratch aperture ABI (runtime-managed
; scratch ring) emit scratch instructions but report zero private_segment_fixed_size
; in the KD. Hotswap must lower these with a conservative 4096-byte fallback
; alloca rather than refusing with an unsupportedShape error.
;
; The alloca size (4096) comes from the per-thread fallback in
; getOrCreateSourcePrivateSegment (handle-flat.cpp). The target backend will
; re-derive the actual private_segment_fixed_size from the lowered alloca.

; CHECK-LABEL: define {{.*}}scratch_zero_pvt_seg_kernel
; CHECK: source_private_segment = alloca i8, i32 4096, align 4, addrspace(5)
; CHECK: store <4 x i32>
; CHECK: load <4 x i32>
; CHECK: store <2 x i32>
; CHECK: load <2 x i32>

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	scratch_zero_pvt_seg_kernel
	.p2align	8
	.type	scratch_zero_pvt_seg_kernel,@function
scratch_zero_pvt_seg_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	; Store 4 DWORDs (b128) to scratch at offset 0 -- private_segment_fixed_size=0
	scratch_store_b128 off, v[0:3], off offset:0
	s_wait_kmcnt 0x0
	; Load 4 DWORDs (b128) back
	scratch_load_b128 v[0:3], off, off offset:0
	s_wait_kmcnt 0x0
	; Store 2 DWORDs (b64) to scratch at offset 16
	scratch_store_b64 off, v[4:5], off offset:16
	s_wait_kmcnt 0x0
	; Load 2 DWORDs (b64) back
	scratch_load_b64 v[4:5], off, off offset:16
	s_wait_kmcnt 0x0
	global_store_b128 v0, v[0:3], s[0:1] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel scratch_zero_pvt_seg_kernel
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
    .name:           scratch_zero_pvt_seg_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         scratch_zero_pvt_seg_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
