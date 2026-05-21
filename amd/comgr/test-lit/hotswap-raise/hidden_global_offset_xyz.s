; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=global_offset_read 2>/dev/null \
; RUN:   | %FileCheck %s
;
; hidden_global_offset_{x,y,z} are 64-bit values placed at the start of the
; implicit-arg block by the HSA runtime on both gfx9 and gfx12.  They carry
; the host-side global work offset (e.g. clEnqueueNDRangeKernel's third
; argument).  The source and target implicit-arg layouts agree for these
; fields, so the raiser synthesises the value by loading from the target's
; amdgcn_implicitarg_ptr rather than attempting dispatch-packet arithmetic.
;
; This fixture loads all three offset dimensions via s_load_b64 within the
; implicit-args region.  The emitted IR must call amdgcn_implicitarg_ptr and
; must NOT call amdgcn_dispatch_ptr for the offset loads.

; CHECK-LABEL: define amdgpu_kernel void @global_offset_read(
; CHECK: call ptr addrspace(4) @llvm.amdgcn.implicitarg.ptr()
; CHECK-NOT: call ptr addrspace(4) @llvm.amdgcn.dispatch.ptr()

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.protected	global_offset_read
	.globl	global_offset_read
	.p2align	8
	.type	global_offset_read,@function
global_offset_read:
	; Load hidden_global_offset_x (i64, at kernarg offset 0x10 = implicit base 0x10)
	s_load_b64 s[2:3], s[0:1], 0x10
	; Load hidden_global_offset_y (i64, at kernarg offset 0x18)
	s_load_b64 s[4:5], s[0:1], 0x18
	; Load hidden_global_offset_z (i64, at kernarg offset 0x20)
	s_load_b64 s[6:7], s[0:1], 0x20
	s_wait_kmcnt 0x0
	; Use the values so they aren't DCE'd
	v_mov_b32_e32 v0, s2
	v_mov_b32_e32 v1, s4
	v_mov_b32_e32 v2, s6
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel global_offset_read
		.amdhsa_kernarg_size 128
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_system_sgpr_workgroup_id_x 1
		.amdhsa_next_free_vgpr 3
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
      - .address_space:  global
        .offset:         0
        .size:           8
        .value_kind:     global_buffer
      - .offset:         16
        .size:           8
        .value_kind:     hidden_global_offset_x
      - .offset:         24
        .size:           8
        .value_kind:     hidden_global_offset_y
      - .offset:         32
        .size:           8
        .value_kind:     hidden_global_offset_z
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 128
    .max_flat_workgroup_size: 1024
    .name:           global_offset_read
    .private_segment_fixed_size: 0
    .sgpr_count:     10
    .sgpr_spill_count: 0
    .symbol:         global_offset_read.kd
    .uniform_work_group_size: 1
    .uses_dynamic_stack: false
    .vgpr_count:     3
    .vgpr_spill_count: 0
    .wavefront_size: 32
amdhsa.target:   amdgcn-amd-amdhsa--gfx1250
amdhsa.version:
  - 1
  - 2
...
	.end_amdgpu_metadata
