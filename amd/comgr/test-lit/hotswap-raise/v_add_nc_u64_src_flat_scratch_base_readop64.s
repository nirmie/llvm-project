; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_add_nc_u64_flat_scratch_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; gfx1250 kernels that compute scratch-relative addresses use
; `v_add_nc_u64_e32 vdst, src_flat_scratch_base_lo, vsrc` where
; src_flat_scratch_base_lo (HW enc 230) is the low 32-bit half of the
; gfx1250 flat-scratch aperture base and the hardware zero-extends it to
; 64 bits when used as a VOP2 64-bit src0 operand.
;
; Before the fix (commit 1f929cb6), SRC_FLAT_SCRATCH_BASE_LO was not in the
; APERTURE arm of parseReg's switch so readOp64 classified it as OTHER and
; emitted the failure:
;   "readOp64 saw unmodeled register 'SRC_FLAT_SCRATCH_BASE_LO' in v_add_nc_u64"
;
; The fix classifies SRC_FLAT_SCRATCH_BASE_LO and SRC_FLAT_SCRATCH_BASE_HI
; as ParsedReg::APERTURE so readOp64 returns i64 0, making the instruction
; lower to an identity add (x + 0).

; CHECK-LABEL: define amdgpu_kernel void @v_add_nc_u64_flat_scratch_kernel(
; CHECK: add i64 0, {{.*}}

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_add_nc_u64_flat_scratch_kernel
	.p2align	8
	.type	v_add_nc_u64_flat_scratch_kernel,@function
v_add_nc_u64_flat_scratch_kernel:
	s_load_b64 s[0:1], s[0:1], 0x0
	; Compute a 64-bit address using src_flat_scratch_base_lo as the base
	; (encodes as VOP2 64-bit src0 = HW 0xE6).  On gfx950 the aperture base
	; is 0 so this is effectively v[2:3] + 0.
	v_mov_b32_e32 v2, 0x100
	v_mov_b32_e32 v3, 0x0
	v_add_nc_u64_e32 v[2:3], src_flat_scratch_base_lo, v[2:3]
	s_wait_kmcnt 0x0
	global_store_b64 v[2:3], v[2:3], off
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_add_nc_u64_flat_scratch_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
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
    .name:           v_add_nc_u64_flat_scratch_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         v_add_nc_u64_flat_scratch_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
