; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=s_and_saveexec_b32_kernel 2>&1 \
; RUN:   | %FileCheck %s
;
; Pin Bug-Id 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-007
;
; Also covers Bug-Id: 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-007
; Also covers Bug-Id: 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-007
; Also covers Bug-Id: 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-007
; Identical recurrence: 156 s_and_saveexec_b32 UnsupportedOpcode hits across
; 93 rocBLAS GEMVT kernels (sample: rocblas_gemvt_sn_reduce on gfx1250).
; The gfx1250 fatbin reproduces cleanly at current HEAD (0 failures); fix
; was already merged in the handle-sop1 + opcode-map work tracked by the
; earlier bug record.
;
; Regression for UnsupportedOpcode: s_and_saveexec_b32 on gfx1250 (wave32).
; This is the standard exec-narrowing pattern used in 156 instances across
; 93 rocblas gemvt kernels.  The transpiler must:
;   (a) save old EXEC into the destination SGPR,
;   (b) write (old_exec AND src) to EXEC as %new_exec,
;   (c) use %new_exec as the exec guard for the lane-predicated store.
;
; Pattern (mirrors rocblas_gemvt_sn_reduce):
;   v_cmp_lt_u32 vcc_lo, v0, threshold   -- narrow to active lanes
;   s_and_saveexec_b32 s2, vcc_lo        -- old exec -> s2, exec = exec & vcc
;   global_store_b32 ...                  -- guarded store
;   s_mov_b32 exec_lo, s2                -- restore exec

; CHECK-LABEL: define amdgpu_kernel void @s_and_saveexec_b32_kernel(

; The saveexec saves old EXEC and ANDs with the vcc_ballot to produce %new_exec.
; v_cmp_lt_u32_e32 vcc_lo, 16, v0 assembles with reversed operands: icmp ult i32 16, %tid.
; CHECK:       %vcmp = icmp ult i32 16, %tid
; CHECK-NEXT:  %vcc_ballot = call i64 @llvm.amdgcn.ballot.i64(i1 %vcmp)
; CHECK:       %new_exec = and i64 %{{[^ ]+}}, %vcc_ballot

; %new_exec gates the lane-active check for the guarded store.
; CHECK:       %[[AT_LANE:[^ ]+]] = lshr i64 %new_exec, %{{[^ ]+}}
; CHECK-NEXT:  %[[BIT:[^ ]+]] = and i64 %[[AT_LANE]], 1
; CHECK-NEXT:  %[[ACTIVE:[^ ]+]] = icmp ne i64 %[[BIT]], 0
; CHECK-NEXT:  br i1 %[[ACTIVE]], label %[[DO:[^ ,]+]], label %{{[^ ,]+}}

; The guarded store is inside the narrowed exec region.
; CHECK:       [[DO]]:
; CHECK-NEXT:    store i32 {{.*}}, ptr addrspace(1) %{{[^ ]+}}, align 4

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	s_and_saveexec_b32_kernel
	.p2align	8
	.type	s_and_saveexec_b32_kernel,@function
s_and_saveexec_b32_kernel:
	s_clause 0x1
	s_load_b64 s[0:1], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v1, 0xcc
	;;#ASMSTART
	; Narrow exec: lanes where tid < 16
	v_cmp_lt_u32_e32 vcc_lo, 16, v0
	s_and_saveexec_b32 s2, vcc_lo
	; Guarded store (only active lanes)
	global_store_b32 v0, v1, s[0:1] scale_offset
	s_wait_storecnt 0
	; Restore EXEC
	s_mov_b32 exec_lo, s2
	;;#ASMEND
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel s_and_saveexec_b32_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 3
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
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           s_and_saveexec_b32_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     3
    .symbol:         s_and_saveexec_b32_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
