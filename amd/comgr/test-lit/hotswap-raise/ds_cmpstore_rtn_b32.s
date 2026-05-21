; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=ds_cmpstore_rtn_b32_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Lift test for ds_cmpstore_rtn_b32 (GFX11+ LDS compare-and-swap with
; return value).  Pins that the opcode-map correctly maps
; DS_CMPSTORE_RTN_B32 to CanonicalOp::DS_CMPSTORE_B32 so the handler
; in handle-ds.cpp fires rather than returning UnsupportedOpcode.
;
; Root cause: DS_CMPSTORE_RTN_B32 has _RTN as an infix (before _B32),
; not a suffix, so buildPseudoAliasMap's suffix _RTN rule does not fire.
; The fix adds an explicit E(DS_CMPSTORE_RTN_B32, DS_CMPSTORE_B32) entry
; to kCanonTable so both the no-return and return-value forms share the
; same handler.  The handler derives "write back old value" from
; Di.NumDefs rather than the opcode, so no handler change is needed.
;
; The instruction takes (vdst=$v1, addr=$v0, new=$v2, cmp=$v3, offset=0).
; The lifted IR must contain a cmpxchg on addrspace(3) (LDS) and write
; back the old value to the destination VGPR.

; CHECK-LABEL: define amdgpu_kernel void @ds_cmpstore_rtn_b32_kernel(
; CHECK: cmpxchg ptr addrspace(3)
; CHECK-NOT: UnsupportedOpcode

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	ds_cmpstore_rtn_b32_kernel
	.p2align	8
	.type	ds_cmpstore_rtn_b32_kernel,@function
ds_cmpstore_rtn_b32_kernel:
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, 0
	v_mov_b32_e32 v2, 42
	v_mov_b32_e32 v3, 0
	ds_cmpstore_rtn_b32 v1, v0, v2, v3 offset:0
	s_wait_dscnt 0x0
	global_store_b32 v0, v1, s[0:1]
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel ds_cmpstore_rtn_b32_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_system_sgpr_workgroup_id_x 1
		.amdhsa_next_free_vgpr 4
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
      - .address_space:  global
        .offset:         0
        .size:           8
        .value_kind:     global_buffer
    .group_segment_fixed_size: 4
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           ds_cmpstore_rtn_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         ds_cmpstore_rtn_b32_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
