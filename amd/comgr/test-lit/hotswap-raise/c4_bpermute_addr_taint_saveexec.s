; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && raise_cli %t.hsaco --target-isa=gfx942 \
; RUN:     --emit-ir=c4_bpermute_addr_taint_saveexec_kernel 2>&1 \
; RUN:   | %FileCheck %s
;
; Regression: the C4 provenance taint tracker must NOT propagate the taint of
; ds_bpermute_b32's *addr/selector* operand (SrcMap[0], typically mbcnt-derived)
; into the destination register.  Only the *data* operand (SrcMap[1]) determines
; whether the output carries lane-id provenance.
;
; This pattern appears in bfloat16/fp16 rocBLAS reduction kernels:
;   1. v_mbcnt_lo_u32_b32 seeds a lane-local byte offset (addr).
;   2. ds_bpermute_b32 gathers a reduction partial sum (data value, not lane-id).
;   3. The gathered data is compared (v_cmp) to detect inf/NaN, producing vcc_lo.
;   4. s_and_saveexec_b32 gates the rounding path on the comparison result.
;
; Before the fix, step 2 tainted the destination with the addr taint, making step 3
; look like "mbcnt flows into saveexec source" and triggering a false-positive
; SaveExecFromLaneId refusal.
;
; Bug-Id: 2026-05-27T00-49-13Z_qwen2.5-7b-instruct-001
;
; CHECK-NOT: cross-wave-lane-predicated-exec
; CHECK-LABEL: define amdgpu_kernel void @c4_bpermute_addr_taint_saveexec_kernel(

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	c4_bpermute_addr_taint_saveexec_kernel
	.p2align	8
	.type	c4_bpermute_addr_taint_saveexec_kernel,@function
c4_bpermute_addr_taint_saveexec_kernel:
	; Compute a mbcnt-derived lane selector (byte-addressed, standard idiom).
	v_mbcnt_lo_u32_b32 v1, -1, 0
	v_lshlrev_b32_e32 v2, 2, v1        ; v2 = addr (mbcnt-derived byte offset)

	; Gather a data value from another lane. v0 holds a per-lane f32.
	; v3 = gathered value -- content is NOT derived from the lane index.
	ds_bpermute_b32 v3, v2, v0
	s_wait_dscnt 0x0

	; Compare the gathered value to detect infinity.
	; vcc_lo depends on the f32 content, NOT on mbcnt.
	v_cmp_ne_u32_e32 vcc_lo, 0x7f800000, v3

	; saveexec: gates on the infinity check result, not on a lane id.
	; Must NOT be classified as SaveExecFromLaneId.
	s_and_saveexec_b32 s0, vcc_lo
	s_cbranch_execz .Ldone

	; Rounding path (only for non-infinity lanes).
	v_add_f32_e32 v3, 1.0, v3

.Ldone:
	s_or_b32 exec_lo, exec_lo, s0
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel c4_bpermute_addr_taint_saveexec_kernel
		.amdhsa_kernarg_size 0
		.amdhsa_user_sgpr_count 0
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 4
		.amdhsa_next_free_sgpr 1
		.amdhsa_float_denorm_mode_32 3
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:           []
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 0
    .max_flat_workgroup_size: 1024
    .name:           c4_bpermute_addr_taint_saveexec_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     1
    .symbol:         c4_bpermute_addr_taint_saveexec_kernel.kd
    .vgpr_count:     4
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
