//===- handle-sopp.cpp - Hotswap transpiler -------------------------------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "handlers.h"

using namespace llvm;

namespace COMGR::hotswap {

Expected<HandlerResult> handleSOPP(RaiseContext &Ctx, const DecodedInst &Di,
                                   OpResolver &Op) {
  (void)Op;
  HandlerResult Hr;

  // s_endpgm terminates the kernel's control flow with a return.
  if (Di.CanonOp == CanonicalOp::S_ENDPGM) {
    Ctx.B.CreateRetVoid();
    Hr.Handled = true;
    return Hr;
  }

  // Scheduling / memory-ordering hints with no architectural data effect. The
  // raised IR re-derives its own dependencies and the backend re-inserts the
  // waits/clauses it needs for the target, so lifting these to nothing is
  // correct. s_setreg_imm32_b32 writes a mode/scheduler register the
  // transpiler does not model (WAVE_MODE); dropping the write matches the
  // s_getreg IB_STS2/MODE read-as-zero policy (see handle-sopk).
  switch (Di.CanonOp) {
  case CanonicalOp::S_CLAUSE:
  case CanonicalOp::S_DELAY_ALU:
  case CanonicalOp::S_WAIT_KMCNT:
  case CanonicalOp::S_WAIT_LOADCNT:
  case CanonicalOp::S_WAIT_XCNT:
  case CanonicalOp::S_SETREG_IMM32_B32:
    Hr.Handled = true;
    return Hr;
  default:
    break;
  }

  return RaiseFailure::unsupportedInstructionForm(
      strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset, "SOPP");
}

} // namespace COMGR::hotswap
