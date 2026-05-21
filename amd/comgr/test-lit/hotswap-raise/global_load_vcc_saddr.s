; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=global_load_vcc_saddr_kernel 2>/dev/null | %FileCheck %s
;
; VCC used as the SADDR operand of global_load_b32 and global_load_b64.
;
; The compiler occasionally emits VCC as a general-purpose SGPR64 pair for
; pointer arithmetic (e.g. `s_mul_u64 vcc, ...; s_add_nc_u64 vcc, base, vcc;
; global_load_b32 vdst, voff, vcc`).  Hotswap must read the raw 64-bit scalar
; value that was stored into VCC (via writeReg64(VCC)) rather than going
; through readVCCAsWaveMask, which produces a ballot-derived lane-mask.
;
; CHECK-LABEL: define amdgpu_kernel void @global_load_vcc_saddr_kernel(
; The s_add_nc_u64 that populates VCC appears as a plain sadd64.
; CHECK: %sadd64 = add i64
; The VCC raw 64-bit pointer is used as the SADDR base in saddr_vaddr.
; CHECK: %saddr_vaddr = add i64 %sadd64, %voff_sext
; CHECK: inttoptr i64 %saddr_vaddr to ptr addrspace(1)
; CHECK: load float, ptr addrspace(1)
; CHECK: store i32

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_load_vcc_saddr_kernel
	.p2align	8
	.type	global_load_vcc_saddr_kernel,@function
global_load_vcc_saddr_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; Load base pointer from kernarg into s[2:3]
	s_load_b64 s[2:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	; Use VCC as a general-purpose SGPR64: compute a pointer in VCC
	s_add_nc_u64 vcc, s[2:3], 0x10
	; Per-lane offset in v0
	v_mov_b32_e32 v1, 0
	; global_load_b32 with VCC as saddr
	global_load_b32 v2, v1, vcc
	s_wait_loadcnt 0x0
	; Store result
	s_load_b64 s[4:5], s[0:1], 0x8
	s_wait_kmcnt 0x0
	global_store_b32 v0, v2, s[4:5]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_load_vcc_saddr_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 3
		.amdhsa_next_free_sgpr 6
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
      - { .actual_access:  read_only,  .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
      - { .actual_access:  write_only, .address_space:  global, .offset:         8, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name:           global_load_vcc_saddr_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     6
    .symbol:         global_load_vcc_saddr_kernel.kd
    .vgpr_count:     3
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
