//===- pipeline-loader-shim.cpp - free-function loader adapters -----------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "pipeline-loader-shim.h"

using namespace llvm;

namespace COMGR::hotswap {

Expected<KernelMeta> extractKernelMeta(MemoryBufferRef CodeObject,
                                       StringRef KernelName) {
  Expected<CodeObjectInfo> InfoOrErr = CodeObjectInfo::create(CodeObject);
  if (!InfoOrErr)
    return InfoOrErr.takeError();
  Expected<const KernelMeta *> MetaOrErr = InfoOrErr->kernel(KernelName);
  if (!MetaOrErr)
    return MetaOrErr.takeError();
  return **MetaOrErr;
}

Expected<KernelSymbolExtent>
findKernelSymbolExtent(MemoryBufferRef CodeObject, StringRef KernelName) {
  Expected<CodeObjectInfo> InfoOrErr = CodeObjectInfo::create(CodeObject);
  if (!InfoOrErr)
    return InfoOrErr.takeError();
  return InfoOrErr->kernelSymbolExtent(KernelName);
}

Expected<SmallVector<KernelSymbolExtent>>
listTextFunctionExtents(MemoryBufferRef CodeObject) {
  Expected<CodeObjectInfo> InfoOrErr = CodeObjectInfo::create(CodeObject);
  if (!InfoOrErr)
    return InfoOrErr.takeError();
  return InfoOrErr->textFunctionExtents();
}

Expected<TextSection> extractTextSection(MemoryBufferRef CodeObject) {
  Expected<CodeObjectInfo> InfoOrErr = CodeObjectInfo::create(CodeObject);
  if (!InfoOrErr)
    return InfoOrErr.takeError();
  return InfoOrErr->textSection();
}

Expected<SmallVector<std::string>>
listKernelNames(MemoryBufferRef CodeObject) {
  Expected<CodeObjectInfo> InfoOrErr = CodeObjectInfo::create(CodeObject);
  if (!InfoOrErr)
    return InfoOrErr.takeError();
  SmallVector<std::string> Names(InfoOrErr->kernelNames().begin(),
                                 InfoOrErr->kernelNames().end());
  return Names;
}

} // namespace COMGR::hotswap
