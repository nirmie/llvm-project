; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=smem_load_vcc_hi_dest_kernel 2>/dev/null | %FileCheck %s
;
; s_load_b32 with vcc_hi as the destination register. gfx1250 wave32 uses
; vcc_hi (encoding 107, just above SGPR_32's range of 0..105) as an extra
; SGPR slot. The raiser's parseReg maps vcc_hi to ParsedReg::VCC (BaseIdx=-1);
; a naive storeSGPR32(BaseIdx+D) call crashed with SIGSEGV. The fix routes
; non-SGPR single-dword SMEM destinations through writeReg32 which handles
; VCC correctly.

; CHECK-LABEL: define amdgpu_kernel void @smem_load_vcc_hi_dest_kernel(
; CHECK: load i32, ptr addrspace({{[0-9]+}})

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	smem_load_vcc_hi_dest_kernel
	.p2align	8
	.type	smem_load_vcc_hi_dest_kernel,@function
smem_load_vcc_hi_dest_kernel:
	; Load a kernarg dword into vcc_hi (used as an extra scalar register on
	; gfx1250 wave32). s[0:1] = kernarg segment pointer (user-SGPR 0).
	s_load_b32 vcc_hi, s[0:1], 0x0
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel smem_load_vcc_hi_dest_kernel
		.amdhsa_kernarg_size 4
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 0
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
      - .offset:         0
        .size:           4
        .value_kind:     by_value
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 4
    .max_flat_workgroup_size: 1024
    .name:           smem_load_vcc_hi_dest_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         smem_load_vcc_hi_dest_kernel.kd
    .vgpr_count:     0
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
