//===- handle-flat.cpp - Hotswap transpiler -------------------------------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// FLAT/GLOBAL memory lifting. This PoC covers the dword load/store forms a
// straight-line vector-add kernel emits (global_load_b32 / global_store_b32);
// sub-dword, vector (DWORDX2/3/4), D16, and scratch/flat-scratch forms refuse
// until their handlers land.
//
//===----------------------------------------------------------------------===//

#include "flat-addr.h"
#include "handlers.h"

#include "hotswap/decoder/mc-state.h"

#include "llvm/IR/DerivedTypes.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace COMGR::hotswap {

Expected<HandlerResult> handleFLAT(RaiseContext &Ctx, const DecodedInst &Di,
                                   OpResolver &Op) {
  HandlerResult Hr;
  const CanonicalOp Sop = Di.CanonOp;

  // global_prefetch_b8 is a scheduling hint with no architectural result;
  // lift it to nothing.
  if (Sop == CanonicalOp::GLOBAL_PREFETCH_B8) {
    Hr.Handled = true;
    return Hr;
  }

  if (Sop == CanonicalOp::GLOBAL_LOAD_DWORD) {
    ParsedReg Dest = Op.dst();
    Expected<FlatAddr> FaOrErr =
        decodeGlobalLoadAddr(Ctx, Di, Op, /*ElemBytes=*/4, "GLOBAL_LOAD dword");
    if (!FaOrErr)
      return FaOrErr.takeError();
    Value *Addr = FaOrErr->Ptr;

    // Gate the dereference on EXEC: inactive / phantom lanes hold undef or
    // stale address VGPRs and would fault (HIP error 700) without the guard.
    Ctx.emitUnderExec([&] {
      Value *Loaded = Ctx.B.CreateLoad(Ctx.F32Ty, Addr, "gload");
      Ctx.Regs.writeReg32(Ctx.B, Dest,
                          Ctx.B.CreateBitCast(Loaded, Ctx.I32Ty));
    });
    Hr.Handled = true;
    return Hr;
  }

  if (Sop == CanonicalOp::GLOBAL_STORE_DWORD) {
    Expected<FlatAddr> FaOrErr = decodeGlobalStoreAddr(
        Ctx, Di, Op, /*ElemBytes=*/4, "GLOBAL_STORE dword");
    if (!FaOrErr)
      return FaOrErr.takeError();
    Value *Addr = FaOrErr->Ptr;
    ParsedReg StData = FaOrErr->StData;

    Ctx.emitUnderExec([&] {
      Value *Data = Ctx.Regs.readReg32(Ctx.B, StData);
      Ctx.B.CreateStore(Ctx.B.CreateBitCast(Data, Ctx.F32Ty), Addr);
    });
    Hr.Handled = true;
    return Hr;
  }

  return RaiseFailure::unsupportedInstructionForm(
      strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset, "FLAT");
}

} // namespace COMGR::hotswap
