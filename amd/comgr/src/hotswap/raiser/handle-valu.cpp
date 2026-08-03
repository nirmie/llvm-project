//===- handle-valu.cpp - Hotswap transpiler -------------------------------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// VALU (vector ALU) lifting. This PoC covers the vector ops a straight-line
// vector-add kernel emits: the f32 add, the unsigned multiply-add used to
// compute the global thread index, and the no-op. Other VALU opcodes refuse
// until their handlers land.
//
//===----------------------------------------------------------------------===//

#include "handlers.h"

#include "hotswap/decoder/mc-state.h"

using namespace llvm;

namespace COMGR::hotswap {

Expected<HandlerResult> handleVALU(RaiseContext &Ctx, const DecodedInst &Di,
                                   OpResolver &Op) {
  HandlerResult Hr;
  const CanonicalOp Sop = Di.CanonOp;

  // v_nop: no architectural effect.
  if (Sop == CanonicalOp::V_NOP) {
    Hr.Handled = true;
    return Hr;
  }

  // v_mad_u32: dst = src0 * src1 + src2 (unsigned, low 32 bits).
  if (Sop == CanonicalOp::V_MAD_U32) {
    Ctx.Regs.writeReg32(
        Ctx.B, Op.dst(),
        Ctx.B.CreateAdd(Ctx.B.CreateMul(Op.src(0), Op.src(1)), Op.src(2),
                        "vmad_u32"));
    Hr.Handled = true;
    return Hr;
  }

  // v_add_f32: dst = src0 + src1 (f32). srcF applies VOP3 neg/abs modifiers.
  if (Sop == CanonicalOp::V_ADD_F32) {
    Value *S0 = Op.srcF(0), *S1 = Op.srcF(1);
    if (S0->getType() != Ctx.F32Ty)
      S0 = Ctx.B.CreateBitCast(S0, Ctx.F32Ty);
    if (S1->getType() != Ctx.F32Ty)
      S1 = Ctx.B.CreateBitCast(S1, Ctx.F32Ty);
    Ctx.Regs.writeReg32(
        Ctx.B, Op.dst(),
        Ctx.B.CreateBitCast(Ctx.B.CreateFAdd(S0, S1, "fadd"), Ctx.I32Ty));
    Hr.Handled = true;
    return Hr;
  }

  return RaiseFailure::unsupportedInstructionForm(
      strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset, "VALU");
}

} // namespace COMGR::hotswap
