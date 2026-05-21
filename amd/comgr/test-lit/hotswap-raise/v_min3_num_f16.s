; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=v_min3_num_f16_kernel 2>/dev/null | %FileCheck %s --check-prefix=MIN3
; RUN: raise_cli %t.hsaco --target-isa=gfx950 --emit-ir=v_max3_num_f16_kernel 2>/dev/null | %FileCheck %s --check-prefix=MAX3
;
; Pins VOP3 v_min3_num_f16 / v_max3_num_f16 (scalar f16 ternary NaN-pruning
; min/max, gfx12+).  Lifts to two chained llvm.minnum.f16 / llvm.maxnum.f16
; calls: min3(a,b,c) == minnum(minnum(a,b), c).

; MIN3-LABEL: define amdgpu_kernel void @v_min3_num_f16_kernel(
; MIN3: %v_min3_num_f16_inner{{[0-9]*}} = call half @llvm.minnum.f16(half {{%[^,]+}}, half {{%[^)]+}})
; MIN3: %v_min3_num_f16{{[0-9]*}} = call half @llvm.minnum.f16(half %v_min3_num_f16_inner{{[0-9]*}}, half {{%[^)]+}})
; MIN3-NOT: call {{.*}}@llvm.maxnum.f16
; MIN3-NOT: call {{.*}}@llvm.maximum
; MIN3-NOT: call {{.*}}@llvm.minimum

; MAX3-LABEL: define amdgpu_kernel void @v_max3_num_f16_kernel(
; MAX3: %v_max3_num_f16_inner{{[0-9]*}} = call half @llvm.maxnum.f16(half {{%[^,]+}}, half {{%[^)]+}})
; MAX3: %v_max3_num_f16{{[0-9]*}} = call half @llvm.maxnum.f16(half %v_max3_num_f16_inner{{[0-9]*}}, half {{%[^)]+}})
; MAX3-NOT: call {{.*}}@llvm.minnum.f16
; MAX3-NOT: call {{.*}}@llvm.maximum
; MAX3-NOT: call {{.*}}@llvm.minimum

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_min3_num_f16_kernel
	.p2align	8
	.type	v_min3_num_f16_kernel,@function
v_min3_num_f16_kernel:
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_mov_b32_e32 v2, s6
	v_min3_num_f16 v3, v0, v1, v2
	s_endpgm

	.globl	v_max3_num_f16_kernel
	.p2align	8
	.type	v_max3_num_f16_kernel,@function
v_max3_num_f16_kernel:
	s_load_b128 s[4:7], s[0:1], 0x0
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_mov_b32_e32 v2, s6
	v_max3_num_f16 v3, v0, v1, v2
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_min3_num_f16_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel
	.p2align	6, 0x0
	.amdhsa_kernel v_max3_num_f16_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 8
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
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name: v_min3_num_f16_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: v_min3_num_f16_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
  - .args:
      - { .address_space: global, .offset: 0, .size: 8, .value_kind: global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 16
    .max_flat_workgroup_size: 1024
    .name: v_max3_num_f16_kernel
    .private_segment_fixed_size: 0
    .sgpr_count: 8
    .symbol: v_max3_num_f16_kernel.kd
    .vgpr_count: 4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
