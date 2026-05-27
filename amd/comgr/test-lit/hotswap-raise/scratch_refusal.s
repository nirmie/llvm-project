; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=scratch_refusal_kernel 2>/dev/null | %FileCheck %s
;
; Verify that a gfx1250 kernel with zero private_segment_fixed_size that uses
; scratch_* instructions is lifted successfully using a 64 KB synthetic
; scratch frame. On gfx1250, the hardware manages scratch allocation via
; FLAT_SCRATCH registers initialized by the runtime; the compiler may emit
; scratch_* with private_segment_fixed_size=0 in the KD. Hotswap now accepts
; this and allocates a conservatively large addrspace(5) alloca so the lifted
; IR has a valid private-segment base, letting the AMDGPU backend produce a
; properly-sized target KD.
;
; The refusal guard (UnsupportedShape when private_segment_fixed_size==0) is
; retained for non-gfx1250 source ISAs where hardware-managed scratch does not
; apply. Since raise_cli always decodes the source ISA from the code object
; (gfx1250 here), this fixture tests the new gfx1250-specific acceptance path.

; CHECK-LABEL: define {{.*}}scratch_refusal_kernel
; CHECK: alloca i8, i32 65536, align 4, addrspace(5)
; CHECK: store i32
; CHECK: load i32

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	scratch_refusal_kernel
	.p2align	8
	.type	scratch_refusal_kernel,@function
scratch_refusal_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	v_mul_u32_u24_e32 v1, 3, v0
	;;#ASMSTART
	scratch_store_b32 off, v1, off offset:0
	scratch_load_b32  v1, off, off offset:0
	
	;;#ASMEND
	s_wait_kmcnt 0x0
	global_store_b32 v0, v1, s[0:1] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel scratch_refusal_kernel
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
    .name:           scratch_refusal_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         scratch_refusal_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
