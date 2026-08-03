//===- handle-sop2.cpp - Hotswap transpiler -------------------------------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// SOP2 (scalar ALU, two inputs) lifting. This PoC covers the scalar integer /
// bitfield / select opcodes a thread-index computation emits. Each SCC-writing
// opcode leaves HandlerResult::SccResult set to its i32 result; the raiser
// derives SCC = (result != 0) unless the handler set SccHandled.
//
//===----------------------------------------------------------------------===//

#include "handlers.h"

#include "hotswap/decoder/mc-state.h"

#include "llvm/IR/Constants.h"

using namespace llvm;

namespace COMGR::hotswap {

Expected<HandlerResult> handleSOP2(RaiseContext &Ctx, const DecodedInst &Di,
                                   OpResolver &Op) {
  HandlerResult Hr;
  const CanonicalOp Sop = Di.CanonOp;

  // s_add_i32 (gfx12 s_add_co_i32): dst = src0 + src1; SCC = signed overflow.
  // The raiser's default SCC derivation (result != 0) is wrong for add, so
  // compute the carry explicitly and mark SCC handled.
  if (Sop == CanonicalOp::S_ADD_I32) {
    Value *Src0 = Op.src(0), *Src1 = Op.src(1);
    Ctx.Regs.writeReg32(Ctx.B, Op.dst(), Ctx.B.CreateAdd(Src0, Src1, "add"));
    Value *Ov = Ctx.B.CreateExtractValue(
        Ctx.B.CreateBinaryIntrinsic(Intrinsic::sadd_with_overflow, Src0, Src1),
        1, "add_ov");
    Ctx.Regs.storeSCC(Ctx.B, Ov);
    Hr.SccHandled = true;
    Hr.Handled = true;
    return Hr;
  }

  // s_and_b32: dst = src0 & src1; SCC = (dst != 0).
  if (Sop == CanonicalOp::S_AND_B32) {
    Hr.SccResult = Ctx.B.CreateAnd(Op.src(0), Op.src(1), "and");
    Ctx.Regs.writeReg32(Ctx.B, Op.dst(), Hr.SccResult);
    Hr.Handled = true;
    return Hr;
  }

  // s_mul_i32: dst = src0 * src1; does not write SCC.
  if (Sop == CanonicalOp::S_MUL_I32) {
    Ctx.Regs.writeReg32(Ctx.B, Op.dst(),
                        Ctx.B.CreateMul(Op.src(0), Op.src(1), "mul"));
    Hr.Handled = true;
    return Hr;
  }

  // s_cselect_b32: dst = SCC ? src0 : src1; does not write SCC.
  if (Sop == CanonicalOp::S_CSELECT_B32) {
    Ctx.Regs.writeReg32(Ctx.B, Op.dst(),
                        Ctx.B.CreateSelect(Ctx.Regs.loadSCC(Ctx.B), Op.src(0),
                                           Op.src(1), "csel"));
    Hr.Handled = true;
    return Hr;
  }

  // s_bfe_u32: unsigned scalar bitfield extract.
  //   offset = ctrl[4:0]; width = ctrl[22:16]; dst = (src >> offset) & mask.
  // SCC = (dst != 0).
  if (Sop == CanonicalOp::S_BFE_U32) {
    Value *Src = Op.src(0), *Ctrl = Op.src(1);
    Value *Offset = Ctx.B.CreateAnd(Ctrl, ConstantInt::get(Ctx.I32Ty, 0x1F));
    Value *Width = Ctx.B.CreateAnd(Ctx.B.CreateLShr(Ctrl, 16),
                                   ConstantInt::get(Ctx.I32Ty, 0x7F));
    Value *SafeWidth =
        Ctx.B.CreateAnd(Width, ConstantInt::get(Ctx.I32Ty, 0x1F));
    Value *Shifted = Ctx.B.CreateLShr(Src, Offset);
    Value *Mask = Ctx.B.CreateSub(
        Ctx.B.CreateShl(ConstantInt::get(Ctx.I32Ty, 1), SafeWidth),
        ConstantInt::get(Ctx.I32Ty, 1));
    Value *IsGE32 = Ctx.B.CreateICmpUGE(Width, ConstantInt::get(Ctx.I32Ty, 32));
    Mask =
        Ctx.B.CreateSelect(IsGE32, ConstantInt::getSigned(Ctx.I32Ty, -1), Mask);
    Value *IsZero = Ctx.B.CreateICmpEQ(Width, ConstantInt::get(Ctx.I32Ty, 0));
    Hr.SccResult = Ctx.B.CreateSelect(IsZero, ConstantInt::get(Ctx.I32Ty, 0),
                                      Ctx.B.CreateAnd(Shifted, Mask, "bfe"));
    Ctx.Regs.writeReg32(Ctx.B, Op.dst(), Hr.SccResult);
    Hr.Handled = true;
    return Hr;
  }

  return RaiseFailure::unsupportedInstructionForm(
      strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset, "SOP2");
}

} // namespace COMGR::hotswap
