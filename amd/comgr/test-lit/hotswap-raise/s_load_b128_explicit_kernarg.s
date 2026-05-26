; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=s_load_b128_explicit_kernel 2>/dev/null | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-009.
;
; `s_load_b128` produced UnsupportedOpcode (18 hits in 2 kernels from
; fatbin_co_0142.co) when the base SGPR pair is the kernarg-segment-ptr
; and the byte offset falls inside the *explicit* kernarg region (below
; ImplicitArgsBase).  The handler must take the generic GEP+load path and
; expand the 4-dword load to 4 consecutive i32 loads from addrspace(1).
;
; The kernel issues s_load_b128 at offset 0x18 (24 bytes) into the kernarg
; segment, which is well within the explicit arg area.  The raiser must
; produce 4 smem_load* ops from addrspace(1) (not an implicitarg_ptr call).

; CHECK-LABEL: define amdgpu_kernel void @s_load_b128_explicit_kernel(

; The 4-dword load expands to 4 individual i32 smem_load* ops
; sourced from addrspace(1) (generic kernarg path, not hidden-arg path).
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4
; CHECK: %smem_load{{[0-9]*}} = load i32, ptr addrspace(1) %{{[^,]+}}, align 4

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b128_explicit_kernel
	.p2align	8
	.type	s_load_b128_explicit_kernel,@function
s_load_b128_explicit_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; s[0:1] is the kernarg-segment-ptr pair (enable_sgpr_kernarg_segment_ptr=1).
	; Load 4 dwords (16 bytes) starting at byte offset 24 — inside the explicit
	; kernarg region (ImplicitArgsBase is 40 for this 96-byte kernarg segment).
	;;#ASMSTART
	s_load_b128 s[4:7], s[0:1], 0x18
	s_wait_kmcnt 0
	;;#ASMEND
	; Use results so the loads are not DCE'd.
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_mov_b32_e32 v2, s6
	v_mov_b32_e32 v3, s7
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b128_explicit_kernel
		.amdhsa_kernarg_size 96
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_system_sgpr_workgroup_id_x 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
		.amdhsa_reserve_vcc 1
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 2
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - .offset:         0
        .size:           4
        .value_kind:     by_value
      - .offset:         4
        .size:           4
        .value_kind:     by_value
      - .offset:         8
        .size:           4
        .value_kind:     by_value
      - .offset:         12
        .size:           4
        .value_kind:     by_value
      - .offset:         16
        .size:           4
        .value_kind:     by_value
      - .offset:         20
        .size:           4
        .value_kind:     by_value
      - .offset:         24
        .size:           4
        .value_kind:     by_value
      - .offset:         28
        .size:           4
        .value_kind:     by_value
      - .offset:         32
        .size:           4
        .value_kind:     by_value
      - .offset:         36
        .size:           4
        .value_kind:     by_value
      - .offset:         40
        .size:           8
        .value_kind:     hidden_block_count_x
      - .offset:         48
        .size:           8
        .value_kind:     hidden_block_count_y
      - .offset:         56
        .size:           8
        .value_kind:     hidden_block_count_z
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 96
    .max_flat_workgroup_size: 1024
    .name:           s_load_b128_explicit_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .sgpr_spill_count: 0
    .symbol:         s_load_b128_explicit_kernel.kd
    .uniform_work_group_size: 1
    .uses_dynamic_stack: false
    .vgpr_count:     4
    .vgpr_spill_count: 0
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version:
  - 1
  - 2
...
	.end_amdgpu_metadata
