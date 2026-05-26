; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=s_and_not1_saveexec_b32_kernel 2>/dev/null | %FileCheck %s
;
; Regression for Bug-Id 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-006.
; Also covers Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-006
; Also covers Bug-Id: 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-006
; Also covers Bug-Id: 2026-05-26T14-14-07Z_qwen2.5-7b-instruct-006
; Also covers Bug-Id: 2026-05-26T15-20-57Z_qwen2.5-7b-instruct-006
;
; `s_and_not1_saveexec_b32` (GFX11/GFX12/GFX13 assembly rename for
; S_ANDN2_SAVEEXEC_B32) was reported as UnsupportedOpcode in 96 kernels across
; 96 rocBLAS GEMVT workloads.  The handler in handle-sop1.cpp emits:
;   1. load old EXEC into dst SGPR (writeRegExecWidth)
;   2. AND old EXEC with NOT(src) -> new_exec
;   3. store new_exec to EXEC (storeExec)
;
; This test checks that the opcode is handled and the new EXEC SSA value
; (%new_exec) is what guards the predicated store, not the initial -1.

; CHECK-LABEL: define amdgpu_kernel void @s_and_not1_saveexec_b32_kernel(

; v_cmp_lt_u32 produces the lane-mask via ballot.
; CHECK:       %vcmp = icmp ult i32 %tid, 16

; s_and_not1_saveexec_b32 writes `old_exec AND NOT(src)` to EXEC.
; The NOT and AND operate on the widened exec-width value.
; CHECK:       %{{[^ ]+}} = xor i64 %{{[^ ]+}}, -1
; CHECK:       %new_exec = and i64 %saved_exec, %{{[^ ]+}}

; The predicated store is guarded by a bit extracted from %new_exec.
; CHECK:       %[[AT_LANE:[^ ]+]] = lshr i64 %new_exec, %{{[^ ]+}}
; CHECK-NEXT:  %[[BIT:[^ ]+]] = and i64 %[[AT_LANE]], 1
; CHECK-NEXT:  %[[ACTIVE:[^ ]+]] = icmp ne i64 %[[BIT]], 0
; CHECK-NEXT:  br i1 %[[ACTIVE]], label %[[DO:[^ ,]+]], label %{{[^ ,]+}}

; CHECK:       [[DO]]:
; CHECK-NEXT:    store i32 {{.*}}, ptr addrspace(1) %{{[^ ]+}}, align 4

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_and_not1_saveexec_b32_kernel
	.p2align	8
	.type	s_and_not1_saveexec_b32_kernel,@function
s_and_not1_saveexec_b32_kernel:
	s_load_b64 s[0:1], s[0:1], 0x0
	v_mov_b32_e32 v3, 0
	v_lshlrev_b32_e32 v2, 2, v0
	v_mov_b32_e32 v1, 0xcc
	s_wait_kmcnt 0x0
	v_lshl_add_u64 v[2:3], s[0:1], 0, v[2:3]
	;;#ASMSTART
	v_cmp_lt_u32_e64 s4, v0, 16
	s_and_not1_saveexec_b32 s6, s4
	global_store_b32 v[2:3], v1, off
	s_wait_storecnt 0x0
	s_mov_b32 exec_lo, s6
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_and_not1_saveexec_b32_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           s_and_not1_saveexec_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     8
    .symbol:         s_and_not1_saveexec_b32_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
