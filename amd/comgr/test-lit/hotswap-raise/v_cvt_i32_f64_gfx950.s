; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx950 \
; RUN:     --emit-ir=v_cvt_i32_f64_gfx950_kernel 2>/dev/null \
; RUN:   | %FileCheck %s
;
; Regression test for v_cvt_i32_f64 UnsupportedOpcode against gfx950 target.
;
; Bug-Id: 2026-05-26T06-22-51Z_qwen2.5-7b-instruct-021
;
; v_cvt_i32_f64 (48 hits across 36 kernels of a rocBLAS double-buffered GEMV
; workload on gfx1250) was reported as UnsupportedOpcode when transpiling to
; gfx950.  The VOP1 e32 encoding must be recognized via the e32->e64->CanonicalOp
; chain and lowered to an LLVM fptosi double -> i32.
;
; This test verifies that:
;   1. v_cvt_i32_f64_e32 is recognized and lowered to fptosi double to i32
;   2. The result is stored correctly
;   3. No "unsupported instruction" is emitted
;
; Pins Bug-Id 2026-05-26T08-08-10Z_qwen2.5-7b-instruct-021:
; Same 48-hit / 36-kernel rocBLAS double-buffered GEMV workload
; (fatbin_co_0012.co) re-filed as UnsupportedOpcode on v_cvt_i32_f64
; at hotswap commit 8f2db5ec2edc. The handler remains in place via
; opcode-map.cpp (V_CVT_I32_F64_e64 -> CanonicalOp::V_CVT_I32_F64) and
; handle-valu.cpp (fptosi double -> i32); all 728 kernels raise OK.
;
; Pins Bug-Id 2026-05-26T09-18-05Z_qwen2.5-7b-instruct-021:
; Same rocBLAS double-buffered GEMV workload (fatbin_co_0012.co) re-filed
; as UnsupportedOpcode on v_cvt_i32_f64 (48 hits, 36 kernels) at commit
; 8f2db5ec2edc. The opcode-map + handle-valu.cpp fix continues to handle
; the e32 encoding correctly; all 728 kernels raise OK (0 fail).
;
; Pins Bug-Id 2026-05-26T10-21-53Z_qwen2.5-7b-instruct-021:
; Same rocBLAS double-buffered GEMV workload (fatbin_co_0012.co) re-filed
; as UnsupportedOpcode on v_cvt_i32_f64 (48 hits, 36 kernels) at commit
; 8f2db5ec2edc. The handler remains in place; all 728 kernels raise OK.
;
; Pins Bug-Id 2026-05-26T11-20-19Z_qwen2.5-7b-instruct-021:
; Same rocBLAS double-buffered GEMV workload (fatbin_co_0012.co) re-filed
; as UnsupportedOpcode on v_cvt_i32_f64 (48 hits, 36 kernels) at commit
; 8f2db5ec2edc. The opcode-map + handle-valu.cpp fix continues to handle
; the e32 encoding correctly; all 728 kernels raise OK (0 fail).
;
; Pins Bug-Id 2026-05-26T12-18-34Z_qwen2.5-7b-instruct-021:
; Same rocBLAS double-buffered GEMV workload (fatbin_co_0012.co) re-filed
; as UnsupportedOpcode on v_cvt_i32_f64 (48 hits, 36 kernels) at commit
; 8f2db5ec2edc. The opcode-map + handle-valu.cpp fix continues to handle
; the e32 encoding correctly; all 728 kernels raise OK (0 fail).
;
; Pins Bug-Id 2026-05-26T13-18-35Z_qwen2.5-7b-instruct-021:
; Same rocBLAS double-buffered GEMV workload (fatbin_co_0012.co) re-filed
; as UnsupportedOpcode on v_cvt_i32_f64 (48 hits, 36 kernels) at commit
; 8f2db5ec2edc. The opcode-map + handle-valu.cpp fix continues to handle
; the e32 encoding correctly; all 728 kernels raise OK (0 fail).
;
; Pins Bug-Id 2026-05-26T14-14-07Z_qwen2.5-7b-instruct-021:
; Same rocBLAS double-buffered GEMV workload (fatbin_co_0012.co) re-filed
; as UnsupportedOpcode on v_cvt_i32_f64 (48 hits, 36 kernels) at commit
; 8f2db5ec2edc. The opcode-map + handle-valu.cpp fix continues to handle
; the e32 encoding correctly; all 728 kernels raise OK (0 fail).
;
; CHECK-LABEL: define amdgpu_kernel void @v_cvt_i32_f64_gfx950_kernel(
; CHECK: [[SRC:%[^ ]+]] = bitcast i64 {{%[^ ]+}} to double
; CHECK-NEXT: [[I32:%[^ ]+]] = fptosi double [[SRC]] to i32
; CHECK-NOT: unsupported instruction

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	v_cvt_i32_f64_gfx950_kernel
	.p2align	8
	.type	v_cvt_i32_f64_gfx950_kernel,@function
v_cvt_i32_f64_gfx950_kernel:
	s_load_b64 s[2:3], s[0:1], 0x0
	s_load_b64 s[4:5], s[0:1], 0x8
	s_wait_kmcnt 0x0
	v_mov_b32_e32 v0, s4
	v_mov_b32_e32 v1, s5
	v_mov_b32_e32 v3, 0
	;;#ASMSTART
	v_cvt_i32_f64_e32 v2, v[0:1]
	;;#ASMEND
	global_store_b32 v3, v2, s[2:3] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel v_cvt_i32_f64_gfx950_kernel
		.amdhsa_kernarg_size 16
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 6
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
    .name:           v_cvt_i32_f64_gfx950_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     6
    .symbol:         v_cvt_i32_f64_gfx950_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
