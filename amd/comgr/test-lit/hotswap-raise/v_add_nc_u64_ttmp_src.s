; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=v_add_nc_u64_ttmp_kernel 2>/dev/null | %FileCheck %s
;
; gfx1250 v_add_nc_u64_e32 with a TTMP-register-pair source (src0 = ttmp[0:1]).
; gfx1250 kernels emitted by rocBLAS (trsv) use `v_add_nc_u64_e32 vdst, ttmp[N:N+1], vsrc`
; to combine workgroup-ID information stored in hardware trap-handler temporaries.
; The TTMP pair is a valid 64-bit read source; reg-file.cpp::readReg64 handles
; ParsedReg::TTMP pairs by loading and combining two adjacent i32 alloca slots.
;
; Pins Bug-Id: 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-013
; (54 UnsupportedOpcode hits across 54 rocBLAS trsv kernels in fatbin_co_0011.co;
; the handler and opcode-map entry were already present; this test pins the TTMP
; source variant that appears throughout the corpus.)

; CHECK-LABEL: define amdgpu_kernel void @v_add_nc_u64_ttmp_kernel(
; CHECK: add i64

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_add_nc_u64_ttmp_kernel
	.p2align	8
	.type	v_add_nc_u64_ttmp_kernel,@function
v_add_nc_u64_ttmp_kernel:
	; ttmp[0:1] holds workgroup ID info on gfx1250 (set by CP).
	; Add it to v[0:1] to compute an address offset.
	v_mov_b32_e32 v0, 0
	v_mov_b32_e32 v1, 0
	v_add_nc_u64_e32 v[0:1], ttmp[0:1], v[0:1]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_add_nc_u64_ttmp_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
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
  - .args: []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           v_add_nc_u64_ttmp_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         v_add_nc_u64_ttmp_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
