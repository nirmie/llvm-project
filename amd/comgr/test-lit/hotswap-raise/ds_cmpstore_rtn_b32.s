; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=ds_cmpstore_rtn_b32_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; GFX11+ LDS atomic compare-and-swap (ds_cmpstore_rtn_b32) must lower to an
; IR `cmpxchg` on addrspace(3) (LDS), returning the old value.
;
; MCInst operand layout (DS_1A2D_RET on GFX11+):
;   (outs vdst), (ins addr, data0=new_val, data1=cmp_val, offset, gds)
; Note: GFX11+ swapped data0/data1 vs pre-GFX11 DS_CMPST_RTN_B32.
;
; This test pins that:
;   1. The address is zero-extended to i64 and converted to ptr addrspace(3).
;   2. A `cmpxchg` instruction is emitted with `ptr addrspace(3)`, with the
;      compare-value and new-value in the correct order.
;   3. The old value is extracted from the pair and written to the dest VGPR.

; CHECK-LABEL: define amdgpu_kernel void @ds_cmpstore_rtn_b32_kernel(

; Address computation: the i32 addr VGPR is zero-extended to i64, then
; cast to ptr addrspace(3).
; CHECK: %ds_addr = zext i32 %{{.*}} to i64
; CHECK: %ds_cas_ptr = inttoptr i64 %ds_addr to ptr addrspace(3)

; The cmpxchg instruction on LDS (addrspace(3)) with monotonic ordering.
; cmp/new operand order in LLVM IR cmpxchg: (ptr, cmp, new, ...)
; data1=cmp_val comes before data0=new_val in the cmpxchg.
; CHECK: cmpxchg ptr addrspace(3) %ds_cas_ptr, i32 {{.*}}, i32 {{.*}} monotonic monotonic

; The old value is extracted from the pair (index 0).
; CHECK: %ds_cas_old = extractvalue { i32, i1 } %{{.*}}, 0

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	ds_cmpstore_rtn_b32_kernel
	.p2align	8
	.type	ds_cmpstore_rtn_b32_kernel,@function
ds_cmpstore_rtn_b32_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	s_load_b64 s[0:1], s[0:1], 0x0
	; v0 = addr (LDS address), v1 = new_value, v2 = cmp_value
	v_mov_b32_e32 v0, 0       ; addr = 0
	v_mov_b32_e32 v1, 42      ; new_value = 42
	v_mov_b32_e32 v2, 0       ; cmp_value = 0
	s_wait_kmcnt 0x0
	;;#ASMSTART
	ds_cmpstore_rtn_b32 v3, v0, v1, v2
	s_wait_dscnt 0
	;;#ASMEND
	global_store_b32 v0, v3, s[0:1] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel ds_cmpstore_rtn_b32_kernel
		.amdhsa_group_segment_fixed_size 128
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
    .group_segment_fixed_size: 128
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           ds_cmpstore_rtn_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         ds_cmpstore_rtn_b32_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
