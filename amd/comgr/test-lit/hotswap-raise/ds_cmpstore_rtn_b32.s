; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=ds_cmpstore_rtn_b32_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Lift test for the GFX11+ LDS compare-and-store atomic
; `ds_cmpstore_rtn_b32`. The gfx1250 encoding uses opcode 0x030 and
; the GFX11+ operand order: (vdst, addr, data0=cmpval, data1=newval).
; Note: pre-GFX11 `ds_cmpst_rtn_b32` had the src/cmp operands swapped.
;
; Pins Bug-Id 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-000:
; Also covers Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-000
; 510 hits across 454 rocSOLVER getri kernels (sample:
; _ZN9rocsolver6v33300L18getri_kernel_smallILi1E19rocblas_complex_numIfEPS3_EEvT1_iilPiilS6_bb
; in fatbin_co_0104.co) were reported as UnsupportedOpcode for ds_cmpstore_rtn_b32
; at hotswap commit 8f2db5ec2edc.  The DS handler under
; CanonicalOp::DS_CMPSTORE_RTN_B32 in handle-ds.cpp emits a seq_cst cmpxchg on
; an LDS addrspace(3) pointer wrapped in an emitUnderExec diamond; all 128 kernels
; in fatbin_co_0104.co raise successfully.
;
; Cross-target lift (gfx1250 → gfx950): lower to `cmpxchg` on an
; LDS addrspace(3) pointer. The RTN variant returns the original
; value, extracted from the `{oldval, success}` struct returned by
; `cmpxchg`. The `cmpxchg` is wrapped in an emitUnderExec diamond
; so phantom lanes on sub-wave-width launches don't issue LDS stores
; to addresses outside the workgroup's LDS allocation.
;
; Invariants:
;
;   1. The lowering uses LLVM `cmpxchg` on an LDS pointer (not a
;      flat-pointer cmpxchg or a raw-buffer intrinsic).
;   2. The compare value is data0 (v2) and the new value is data1 (v3)
;      in the instruction's operand order.
;   3. The original value from the cmpxchg is written to the vdst register.

; CHECK-LABEL: define amdgpu_kernel void @ds_cmpstore_rtn_b32_kernel(
; CHECK:         cmpxchg ptr addrspace(3)
; CHECK-SAME:    seq_cst seq_cst
; CHECK:         extractvalue
; CHECK-NOT:     atomicrmw

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	ds_cmpstore_rtn_b32_kernel
	.p2align	8
	.type	ds_cmpstore_rtn_b32_kernel,@function
ds_cmpstore_rtn_b32_kernel:       ; @ds_cmpstore_rtn_b32_kernel
; %bb.0:
	; v0 = workitem id, v1 = LDS addr (offset into group segment)
	; v2 = compare value, v3 = new value
	v_lshlrev_b32_e32 v1, 2, v0
	v_mov_b32_e32 v2, 42
	v_mov_b32_e32 v3, 99
	;;#ASMSTART
	ds_cmpstore_rtn_b32 v4, v1, v2, v3
	s_wait_dscnt 0x0
	;;#ASMEND
	global_store_b32 v[0:1], v4, off
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel ds_cmpstore_rtn_b32_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_system_sgpr_workgroup_id_x 1
		.amdhsa_next_free_vgpr 5
		.amdhsa_next_free_sgpr 2
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
		.amdhsa_group_segment_fixed_size 128
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args: []
    .group_segment_fixed_size: 128
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           ds_cmpstore_rtn_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         ds_cmpstore_rtn_b32_kernel.kd
    .vgpr_count:     5
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
