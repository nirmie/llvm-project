; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx942 --emit-ir=v_movrels_movreld_b32_kernel 2>/dev/null | %FileCheck %s
;
; v_movrels_b32: indirect VGPR read -- reads VGPR[base(vsrc) + M0].
; v_movreld_b32: indirect VGPR write -- writes vsrc to VGPR[base(vdst) + M0].
; Both use M0 as runtime index; the raiser models each as extractelement /
; insertelement on a vector of consecutive VGPRs.
;
; Pins Bug-Id 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-029:
; 50 hits across 50 rocSOLVER kernels (sample:
; _ZN9rocsolver6v33300L18trti2_kernel_smallILi8EfPfEEv13rocblas_fill_17rocblas_diagonal_T1_iil
; in fatbin_co_0106.co) were reported as UnsupportedOpcode for
; v_movrels_b32 at hotswap commit 8f2db5ec2edc.  The VOP1 handler under
; CanonicalOp::V_MOVRELS_B32 in handle-valu.cpp (added in commit
; fada2c42aa76) emits extractelement over a consecutive VGPR vector; all
; 128 kernels in fatbin_co_0106.co raise successfully (128 ok, 0 fail).
;
; Pins Bug-Id 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-029:
; Same UnsupportedOpcode on v_movrels_b32 [VOP1], 50 hits across 50 rocSOLVER
; trti2_kernel_small kernels (fatbin_co_0106.co) at hotswap commit 8f2db5ec2edc.
; The V_MOVRELS_B32 handler was already in place; all 128 kernels raise OK.
;
; Pins Bug-Id 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-029:
; Same UnsupportedOpcode on v_movrels_b32 [VOP1], 50 hits across 50 rocSOLVER
; trti2_kernel_small kernels (fatbin_co_0106.co) at hotswap commit 8f2db5ec2edc.
; The V_MOVRELS_B32 handler was already in place; all 128 kernels raise OK.
;
; Pins Bug-Id 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-029:
; Same UnsupportedOpcode on v_movrels_b32 [VOP1], 50 hits across 50 rocSOLVER
; trti2_kernel_small kernels (fatbin_co_0106.co) at hotswap commit 8f2db5ec2edc.
; The V_MOVRELS_B32 handler was already in place; all 128 kernels raise OK.
;
; Pins Bug-Id 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-029:
; Same UnsupportedOpcode on v_movrels_b32 [VOP1], 50 hits across 50 rocSOLVER
; trti2_kernel_small kernels (fatbin_co_0106.co) at hotswap commit 8f2db5ec2edc.
; The V_MOVRELS_B32 handler was already in place; all 50 kernels raise OK.

; CHECK-LABEL: define amdgpu_kernel void @v_movrels_movreld_b32_kernel(
; CHECK: extractelement <{{[0-9]+}} x i32>
; CHECK: insertelement <{{[0-9]+}} x i32>

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_movrels_movreld_b32_kernel
	.p2align	8
	.type	v_movrels_movreld_b32_kernel,@function
v_movrels_movreld_b32_kernel:
	; Set M0 to an immediate value (2) as the dynamic VGPR index offset
	s_mov_b32 m0, 2
	; v_movrels_b32 v4, v0: v4 = VGPR[0 + M0]  (base=v0, M0=2 => reads v2)
	v_movrels_b32 v4, v0
	; v_movreld_b32 v0, v4: VGPR[0 + M0] = v4  (base=v0, M0=2 => writes v2)
	v_movreld_b32 v0, v4
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_movrels_movreld_b32_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 5
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
    .name:           v_movrels_movreld_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         v_movrels_movreld_b32_kernel.kd
    .vgpr_count:     5
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
