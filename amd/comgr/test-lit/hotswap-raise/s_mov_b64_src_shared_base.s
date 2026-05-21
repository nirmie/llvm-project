; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=s_mov_b64_src_shared_base_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; `s_mov_b64 s[dst:dst+1], src_shared_base` reads the gfx12 flat-LDS aperture
; base register into a 64-bit SGPR pair.  On gfx950 there is no flat-LDS
; addressing and the base is effectively 0, so the raiser materialises i64 0
; in the destination pair rather than surfacing an unsupportedShape failure.
;
; Regression: before this fix, SRC_SHARED_BASE (the 64-bit register form)
; was not in the APERTURE parseReg switch arm; readOp64 emitted an
; "operand-read" unsupportedShape failure and the kernel failed to raise.
;
; The kernel writes the high word of src_shared_base (always 0 on gfx950)
; to global memory so the SGPR use is not dead-eliminated and the i64 0
; constant is visible in the IR.

; CHECK-LABEL: define amdgpu_kernel void @s_mov_b64_src_shared_base_kernel(
; CHECK: zext i32 0

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_mov_b64_src_shared_base_kernel
	.p2align	8
	.type	s_mov_b64_src_shared_base_kernel,@function
s_mov_b64_src_shared_base_kernel:
	s_load_b64 s[2:3], s[0:1], 0x0
	s_mov_b64 s[0:1], src_shared_base
	s_wait_kmcnt 0x0
	; use the high word (s1) as the address for a global store
	v_mov_b32_e32 v0, s1
	v_mov_b32_e32 v1, s0
	global_store_b32 v[0:1], v0, off
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_mov_b64_src_shared_base_kernel
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
    .name:           s_mov_b64_src_shared_base_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         s_mov_b64_src_shared_base_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
