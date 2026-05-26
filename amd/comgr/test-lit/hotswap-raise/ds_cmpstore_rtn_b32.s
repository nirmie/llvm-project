; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=ds_cmpstore_rtn_b32_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; DS_CMPSTORE_RTN_B32 is the GFX11+ LDS atomic compare-and-swap (32-bit).
; MCInst operand order: addr, data0=new_value, data1=cmp_value, offset, gds.
; (Note: operand order is SWAPPED vs pre-GFX11 DS_CMPST_RTN_B32 where
; data0=cmp, data1=new; see DSAtomicCmpXChg_mc in DSInstructions.td:1245.)
;
; Semantics: if mem[addr+offset] == data1(cmp), store data0(new);
; return old value into vdst.
;
; The lift must lower to LLVM `cmpxchg ptr addrspace(3), cmp, new`.
; Key invariants:
;   1. A cmpxchg is emitted in LDS address space (addrspace 3).
;   2. The old value (extractvalue [...] 0) is written back to vdst.

; CHECK-LABEL: define amdgpu_kernel void @ds_cmpstore_rtn_b32_kernel(
; CHECK: cmpxchg ptr addrspace(3) %{{[^,]+}}, i32 {{[^,]+}}, i32 {{[^,]+}} seq_cst seq_cst
; CHECK: extractvalue { i32, i1 } %{{[^,]+}}, 0

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	ds_cmpstore_rtn_b32_kernel
	.p2align	8
	.type	ds_cmpstore_rtn_b32_kernel,@function
ds_cmpstore_rtn_b32_kernel:
	; v0 = LDS address (thread id * 4)
	; v1 = new value to store (data0 in MCInst)
	; v2 = comparison value (data1 in MCInst)
	; v3 = old value returned by CAS
	v_lshlrev_b32_e32 v0, 2, v0
	v_mov_b32_e32 v1, 42
	v_mov_b32_e32 v2, 0
	ds_cmpstore_rtn_b32 v3, v0, v1, v2
	s_wait_dscnt 0x0
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel ds_cmpstore_rtn_b32_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 0
		.amdhsa_float_denorm_mode_32 3
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:           []
    .group_segment_fixed_size: 256
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 64
    .name:           ds_cmpstore_rtn_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     0
    .symbol:         ds_cmpstore_rtn_b32_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
