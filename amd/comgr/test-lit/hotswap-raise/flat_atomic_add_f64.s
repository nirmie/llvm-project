; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=flat_atomic_add_f64_kernel 2>/dev/null | %FileCheck %s --check-prefix=FLAT
; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=global_atomic_add_f64_rtn_kernel 2>/dev/null | %FileCheck %s --check-prefix=GLOBAL
;
; Regression pin for Bug-Id: 2026-05-26T17-19-37Z_qwen2.5-7b-instruct-001
;
; flat_atomic_add_f64 and global_atomic_add_f64 were absent from kCanonTable
; (opcode-map.cpp) and the CanonicalOp enum, causing UnsupportedOpcode on
; 11 kernels in fatbin_co_0019.co.  The fix adds both opcodes to the enum,
; name table, opcode map, and handle-flat.cpp handler.
;
; f64 atomics use a VGPR pair (v[N:N+1]) for data and RTN result; the raiser
; must use readReg64/writeReg64 and bitcast i64<->f64 around the fadd atomicrmw.
;
; flat_atomic_add_f64 (non-RTN, no destination register)
;   addr=v[0:1], data=v[2:3], no vdst
; global_atomic_add_f64 RTN (writes old value to v[4:5])
;   addr=v0, data=v[2:3], saddr=s[2:3], vdst=v[4:5]

; FLAT-LABEL: define amdgpu_kernel void @flat_atomic_add_f64_kernel(
; FLAT: atomicrmw fadd ptr
; FLAT: double
; FLAT-NOT: UnsupportedOpcode

; GLOBAL-LABEL: define amdgpu_kernel void @global_atomic_add_f64_rtn_kernel(
; GLOBAL: atomicrmw fadd ptr addrspace(1)
; GLOBAL: double
; GLOBAL-NOT: UnsupportedOpcode

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text

	;;; ---------- flat_atomic_add_f64_kernel (non-RTN) ----------
	.globl	flat_atomic_add_f64_kernel
	.p2align	8
	.type	flat_atomic_add_f64_kernel,@function
flat_atomic_add_f64_kernel:
	; s[0:1] = kernarg ptr; kernargs: flat ptr (8 bytes), f64 addend (8 bytes)
	s_load_b128 s[0:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	; v[0:1] = flat address from s[0:1]
	v_mov_b32_e32 v0, s0
	v_mov_b32_e32 v1, s1
	; v[2:3] = f64 addend from s[2:3]
	v_mov_b32_e32 v2, s2
	v_mov_b32_e32 v3, s3
	flat_atomic_add_f64 v[0:1], v[2:3] scope:SCOPE_DEV
	s_wait_storecnt 0x0
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel flat_atomic_add_f64_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 4
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480

	;;; ---------- global_atomic_add_f64_rtn_kernel (RTN) ----------
	.globl	global_atomic_add_f64_rtn_kernel
	.p2align	8
	.type	global_atomic_add_f64_rtn_kernel,@function
global_atomic_add_f64_rtn_kernel:
	; s[0:1] = kernarg ptr; kernargs: global ptr (8 bytes), f64 addend (8 bytes)
	s_load_b128 s[0:3], s[0:1], 0x0
	s_wait_kmcnt 0x0
	; saddr = s[2:3] (global base), vaddr = v0 (lane offset = 0)
	v_mov_b32_e32 v0, 0
	; v[2:3] = f64 addend
	v_mov_b32_e32 v2, s2
	v_mov_b32_e32 v3, s3
	; RTN: returns old value into v[4:5]
	global_atomic_add_f64 v[4:5], v0, v[2:3], s[0:1] th:TH_ATOMIC_RETURN scope:SCOPE_DEV
	s_wait_loadcnt 0x0
	; Store RTN result to prevent DCE
	global_store_b64 v0, v[4:5], s[0:1]
	s_wait_storecnt 0x0
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_atomic_add_f64_rtn_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 6
		.amdhsa_next_free_sgpr 4
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
      - { .offset:         8, .size:           8, .value_kind:     by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name:           flat_atomic_add_f64_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         flat_atomic_add_f64_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
  - .args:
      - { .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
      - { .offset:         8, .size:           8, .value_kind:     by_value }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name:           global_atomic_add_f64_rtn_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         global_atomic_add_f64_rtn_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
