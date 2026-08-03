//===- handle-sopk.cpp - Hotswap transpiler -------------------------------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// s_getreg_b32 lifting. Reads a hardware register field into a scalar. This
// PoC models only the scheduler / mode registers whose observable value is
// architecturally zero for a freshly-dispatched wave (IB_STS2, IB_STS, MODE);
// the gfx1250 thread-index prologue reads IB_STS2[6:4] and branches on it, so
// producing zero here selects the normal accelerated-launch workgroup-id path.
// Reading any load-bearing register (STATUS, HW_ID, ...) refuses rather than
// return a value the transpiler does not carry.
//
//===----------------------------------------------------------------------===//

#include "handlers.h"

#include "hotswap/decoder/mc-state.h"

#include "SIDefines.h"
#include "llvm/IR/Constants.h"

using namespace llvm;

namespace COMGR::hotswap {

Expected<HandlerResult> handleSOPK(RaiseContext &Ctx, const DecodedInst &Di,
                                   OpResolver &Op) {
  HandlerResult Hr;

  // s_setreg_imm32_b32 (SOPK-encoded) writes a mode/scheduler hardware register
  // the transpiler does not model (e.g. WAVE_MODE). Dropping the write matches
  // the s_getreg IB_STS2/MODE read-as-zero policy below: the raised IR runs
  // under the target's default mode and the backend re-establishes whatever it
  // needs.
  if (Di.CanonOp == CanonicalOp::S_SETREG_IMM32_B32) {
    Hr.Handled = true;
    return Hr;
  }

  if (Di.CanonOp == CanonicalOp::S_GETREG_B32) {
    // Operand layout: dst(0), simm16(1). The hwreg id is the low 6 bits.
    if (Op.nSrcs() < 1 || !Di.isImm(Op.srcIdx(0))) {
      return RaiseFailure::unsupportedInstructionForm(
          strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset,
          "s_getreg_b32 (expected simm16 immediate)");
    }
    // The hwreg id occupies the low 6 bits of the simm16 encoding.
    unsigned HwregId = static_cast<unsigned>(Op.srcImm(0)) & 0x3F;

    switch (HwregId) {
    case AMDGPU::Hwreg::ID_MODE:
    case AMDGPU::Hwreg::ID_IB_STS:
    case AMDGPU::Hwreg::ID_IB_STS2:
      Ctx.Regs.writeReg32(Ctx.B, Op.dst(), ConstantInt::get(Ctx.I32Ty, 0));
      Hr.Handled = true;
      return Hr;
    default:
      return RaiseFailure::unsupportedInstructionForm(
          strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset,
          "s_getreg_b32 (reads a load-bearing hardware register the "
          "transpiler does not carry)");
    }
  }

  return RaiseFailure::unsupportedInstructionForm(
      strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset, "SOPK");
}

} // namespace COMGR::hotswap
