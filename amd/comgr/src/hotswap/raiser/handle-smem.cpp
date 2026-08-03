//===- handle-smem.cpp - Hotswap transpiler -------------------------------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// SMEM scalar-load lifting. This PoC covers the dword-width s_load_b{32,64,128}
// forms a kernel uses to pull its kernarg segment into SGPRs. The base is a
// uniform SGPR64 pointer (kernarg_segment_ptr or dispatch_ptr, seeded at entry)
// plus an immediate byte offset; the load lowers to a generic addrspace(1)
// GEP+load whose result dwords land in consecutive destination SGPRs. Buffer
// descriptors, source-image constant tables, implicit-arg reroute, and dynamic
// SGPR offsets are not modelled here and refuse until their handlers land.
//
//===----------------------------------------------------------------------===//

#include "handlers.h"

#include "hotswap/decoder/mc-state.h"

#include "MCTargetDesc/AMDGPUMCTargetDesc.h"
#include "Utils/AMDGPUBaseInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DerivedTypes.h"

using namespace llvm;

namespace COMGR::hotswap {

Expected<HandlerResult> handleSMEM(RaiseContext &Ctx, const DecodedInst &Di,
                                   OpResolver &Op) {
  HandlerResult Hr;
  const CanonicalOp Sop = Di.CanonOp;

  int LoadDwords = 0;
  switch (Sop) {
  case CanonicalOp::S_LOAD_B32:
    LoadDwords = 1;
    break;
  case CanonicalOp::S_LOAD_B64:
    LoadDwords = 2;
    break;
  case CanonicalOp::S_LOAD_B128:
    LoadDwords = 4;
    break;
  default:
    return RaiseFailure::unsupportedInstructionForm(
        strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset, "SMEM");
  }

  // Base is the first logical source: an SGPR pair holding a byte address.
  if (Op.nSrcs() < 1 || !Op.isSrcReg(0) ||
      Op.srcReg(0).RegKind != ParsedReg::SGPR) {
    return RaiseFailure::unsupportedInstructionForm(
        strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset,
        "SMEM (expected SGPR64 base)");
  }
  ParsedReg Base = Op.srcReg(0);
  ParsedReg Dest = Op.dst();

  // A dynamic SGPR soffset is not modelled; only a static immediate byte
  // offset (OpName::offset) is supported for this PoC.
  unsigned Opc = Di.Inst.getOpcode();
  int SOffsetIdx = AMDGPU::getNamedOperandIdx(Opc, AMDGPU::OpName::soffset);
  if (SOffsetIdx >= 0 &&
      static_cast<unsigned>(SOffsetIdx) < Di.Inst.getNumOperands() &&
      Di.Inst.getOperand(static_cast<unsigned>(SOffsetIdx)).isReg() &&
      Di.Inst.getOperand(static_cast<unsigned>(SOffsetIdx)).getReg() !=
          MCRegister::NoRegister) {
    return RaiseFailure::unsupportedInstructionForm(
        strippedMnemonic(Ctx.Mc, Di.Inst), Di.Offset,
        "SMEM (dynamic SGPR soffset not modelled)");
  }

  int64_t ByteOffset = 0;
  int OffsetIdx = AMDGPU::getNamedOperandIdx(Opc, AMDGPU::OpName::offset);
  if (OffsetIdx >= 0 &&
      static_cast<unsigned>(OffsetIdx) < Di.Inst.getNumOperands() &&
      Di.Inst.getOperand(static_cast<unsigned>(OffsetIdx)).isImm())
    ByteOffset = Di.Inst.getOperand(static_cast<unsigned>(OffsetIdx)).getImm();

  // Generic GEP + load against addrspace(1). The base pointer is uniform; the
  // AMDGPU backend re-selects a scalar-memory load from the pointer's
  // uniformity and provenance.
  Value *BaseAddr = Ctx.Regs.loadSGPR64(Ctx.B, Base.BaseIdx);
  Value *Ptr = Ctx.B.CreateIntToPtr(BaseAddr, Ctx.PtrGlobalTy, "smem_base_ptr");
  if (ByteOffset != 0)
    Ptr = Ctx.B.CreateGEP(Ctx.I8Ty, Ptr, Ctx.B.getInt64(ByteOffset),
                          "smem_ptr");

  for (int D = 0; D < LoadDwords; D++) {
    Value *ElemPtr =
        D == 0 ? Ptr
               : Ctx.B.CreateGEP(Ctx.I8Ty, Ptr, Ctx.B.getInt64(D * 4),
                                 "smem_dw_ptr");
    Ctx.Regs.storeSGPR32(Ctx.B, Dest.BaseIdx + D,
                         Ctx.B.CreateLoad(Ctx.I32Ty, ElemPtr, "smem_load"));
  }
  Ctx.noteSgprMemoryLoadForKernargProvenance(Dest.BaseIdx, LoadDwords);

  Hr.Handled = true;
  return Hr;
}

} // namespace COMGR::hotswap
