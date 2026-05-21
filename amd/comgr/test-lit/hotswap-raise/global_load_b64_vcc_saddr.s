; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=global_load_b64_vcc_saddr_kernel 2>/dev/null | %FileCheck %s
;
; global_load_b64 (GLOBAL_LOAD_DWORDX2) with VCC as the SADDR operand.
;
; The rocblas hemvn kernels compute a 64-bit base pointer into VCC via 64-bit
; scalar ops (s_mul_u64, s_lshl_b64, s_add_nc_u64), then issue global_load_b64
; with VCC as saddr.  Hotswap must read the raw 64-bit scalar stored in VCC
; via the VccRaw64 shadow alloca (written by writeReg64(VCC)) rather than
; routing through readVCCAsWaveMask.
;
; Bug-Id: 2026-05-21T17-54-29Z_qwen2.5-7b-instruct-004
;
; CHECK-LABEL: define amdgpu_kernel void @global_load_b64_vcc_saddr_kernel(
; s_mul_u64 lowered as a 64-bit multiply.
; CHECK: %smul64 = mul i64
; s_lshl_b64 by 3 lowered as shl (result written to VCC shadow → vcc_ballot).
; CHECK: %shl64 = shl i64 %vcc_ballot
; s_add_nc_u64 into VCC lowered as add; written to VccRaw64 shadow.
; CHECK: %sadd64 = add i64
; The VCC raw 64-bit pointer is read back (vcc_ballot9) for the SADDR base.
; CHECK: %saddr_vaddr = add i64 %sadd64, %voff_sext
; Two i32 elements are loaded as a <2 x i32> vector from global addrspace.
; CHECK: %gload = load <2 x i32>, ptr addrspace(1)
; Both halves are extracted and written to the destination VGPR pair.
; CHECK: extractelement <2 x i32> %gload
; CHECK: extractelement <2 x i32> %gload

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	global_load_b64_vcc_saddr_kernel
	.p2align	8
	.type	global_load_b64_vcc_saddr_kernel,@function
global_load_b64_vcc_saddr_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; Load base pointer from kernarg into s[2:3]
	s_load_b64 s[2:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	; Compute a 64-bit stride in VCC: vcc = base * lane_stride << 3
	s_mul_u64 vcc, s[2:3], s[4:5]
	s_lshl_b64 vcc, vcc, 3
	; Add base pointer into VCC to form a 64-bit row pointer
	s_add_nc_u64 vcc, s[2:3], vcc
	; Per-lane byte offset in v0 (set to 0 for simplicity)
	v_mov_b32_e32 v1, 0
	; global_load_b64 with VCC as saddr -- the bug case
	global_load_b64 v[2:3], v1, vcc
	s_wait_loadcnt 0x0
	; Store the two loaded dwords back via a plain SGPR64 saddr
	s_load_b64 s[6:7], s[0:1], 0x8
	s_wait_kmcnt 0x0
	global_store_b32 v0, v2, s[6:7]
	global_store_b32 v0, v3, s[6:7] offset:4
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_load_b64_vcc_saddr_kernel
		.amdhsa_kernarg_size 24
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
      - { .actual_access:  read_only,  .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
      - { .actual_access:  read_only,  .address_space:  global, .offset:         8, .size:           8, .value_kind:     global_buffer }
      - { .actual_access:  write_only, .address_space:  global, .offset:        16, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 24
    .max_flat_workgroup_size: 1024
    .name:           global_load_b64_vcc_saddr_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         global_load_b64_vcc_saddr_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
