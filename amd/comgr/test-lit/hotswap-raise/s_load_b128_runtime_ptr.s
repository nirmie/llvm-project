; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=s_load_b128_runtime_ptr_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for Bug-Id: 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-009.
;
; s_load_b128 (S_LOAD_DWORDX4) applied to a generic runtime pointer (loaded
; from kernargs, not the kernarg-segment-ptr itself) with a non-zero byte
; offset (0x18 = 24) previously triggered UnsupportedOpcode in the SMEM
; handler (18 hits across 2 kernel variants of stedcx_mergeUpdate in
; fatbin_co_0142.co).
;
; The generic GEP+load path in handle-smem.cpp handles non-kernarg-pair bases
; by loading the 64-bit pointer from the SGPR pair, casting it to addrspace(1),
; applying the byte offset via GEP, and emitting 4 consecutive i32 loads.
;
; CHECK-LABEL: define amdgpu_kernel void @s_load_b128_runtime_ptr_kernel(
; CHECK: inttoptr i64 %{{[0-9a-z_]+}} to ptr addrspace(1)
; CHECK: getelementptr inbounds i8, ptr addrspace(1) %{{[0-9a-z_]+}}, i64 24
; CHECK: %smem_load = load i32, ptr addrspace(1)
; CHECK: getelementptr inbounds i8, ptr addrspace(1) %{{[0-9a-z_]+}}, i64 4
; CHECK: %smem_load2 = load i32, ptr addrspace(1)
; CHECK: getelementptr inbounds i8, ptr addrspace(1) %{{[0-9a-z_]+}}, i64 8
; CHECK: %smem_load3 = load i32, ptr addrspace(1)
; CHECK: getelementptr inbounds i8, ptr addrspace(1) %{{[0-9a-z_]+}}, i64 12
; CHECK: %smem_load4 = load i32, ptr addrspace(1)

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_load_b128_runtime_ptr_kernel
	.p2align	8
	.type	s_load_b128_runtime_ptr_kernel,@function
s_load_b128_runtime_ptr_kernel:
	s_setreg_imm32_b32 hwreg(HW_REG_WAVE_MODE, 25, 1), 1
	; s[0:1] = kernarg-segment-ptr (user SGPRs: kernarg_segment_ptr enabled)
	; Load a runtime pointer from kernargs[8..15] into s[4:5].
	s_load_b64 s[4:5], s[0:1], 0x8
	s_wait_kmcnt 0
	; Load 4 dwords (16 bytes) from the runtime pointer at offset 0x18 (=24).
	s_load_b128 s[8:11], s[4:5], 0x18
	s_wait_kmcnt 0
	; Use results to prevent DCE.
	v_mov_b32_e32 v0, s8
	v_mov_b32_e32 v1, s9
	v_mov_b32_e32 v2, s10
	v_mov_b32_e32 v3, s11
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_load_b128_runtime_ptr_kernel
		.amdhsa_kernarg_size 64
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_system_sgpr_workgroup_id_x 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 12
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
        .size:           8
        .value_kind:     by_value
      - .offset:         8
        .size:           8
        .value_kind:     by_value
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 64
    .max_flat_workgroup_size: 1024
    .name:           s_load_b128_runtime_ptr_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     12
    .sgpr_spill_count: 0
    .symbol:         s_load_b128_runtime_ptr_kernel.kd
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
