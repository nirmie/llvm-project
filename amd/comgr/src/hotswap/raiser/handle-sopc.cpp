//===- handle-sopc.cpp - Hotswap transpiler -------------------------------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// SOPC (scalar compare) lifting. A SOPC opcode has no destination register; it
// writes only SCC. This PoC covers s_cmp_eq_u32 (the thread-index dispatch
// predicate); other compares refuse until their handlers land.
//
//===----------------------------------------------------------------------===//

#include "handlers.h"

#include "hotswap/decoder/mc-state.h"

using namespace llvm;

namespace COMGR::hotswap {

Expected<HandlerResult> handleSOPC(RaiseContext &Ctx, const DecodedInst &Di,
                                   OpResolver &Op) {
  HandlerResult Hr;

  // s_cmp_eq_u32 src0, src1: SCC = (src0 == src1).
  if (Di.CanonOp == CanonicalOp::S_CMP_EQ_U32) {
    Ctx.Regs.storeSCC(Ctx.B, Ctx.B.CreateICmpEQ(Op.src(0), Op.src(1), "scmp"));
    Hr.SccHandled = true;
    Hr.Handled = true;
    return Hr;
  }

  return RaiseFailure::unsupportedInstructionForm(
      strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset, "SOPC");
}

} // namespace COMGR::hotswap
