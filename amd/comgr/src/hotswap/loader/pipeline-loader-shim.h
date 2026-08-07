//===- pipeline-loader-shim.h - free-function loader adapters -------------===//
//
// Part of Comgr, under the Apache License v2.0 with LLVM Exceptions. See
// amd/comgr/LICENSE.TXT in this repository for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Free-function adapters over CodeObjectInfo for the transpile pipeline. The
// m0 loader exposes metadata/extent/text queries as CodeObjectInfo methods
// (parse once, query many); the pipeline was written against an earlier
// free-function API. These thin wrappers parse the code object per call and
// forward to the method, keeping the pipeline source unchanged. Per-call
// parsing is acceptable here: the cross-gen path transpiles one kernel per
// dispatch, not a hot loop.
//
//===----------------------------------------------------------------------===//

#ifndef HOTSWAP_TRANSPILER_PIPELINE_LOADER_SHIM_H
#define HOTSWAP_TRANSPILER_PIPELINE_LOADER_SHIM_H

#include "hotswap/loader/code-object-utils.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/MemoryBufferRef.h"

#include <string>

namespace COMGR::hotswap {

llvm::Expected<KernelMeta> extractKernelMeta(llvm::MemoryBufferRef CodeObject,
                                             llvm::StringRef KernelName);

llvm::Expected<KernelSymbolExtent>
findKernelSymbolExtent(llvm::MemoryBufferRef CodeObject,
                       llvm::StringRef KernelName);

llvm::Expected<llvm::SmallVector<KernelSymbolExtent>>
listTextFunctionExtents(llvm::MemoryBufferRef CodeObject);

llvm::Expected<TextSection> extractTextSection(llvm::MemoryBufferRef CodeObject);

llvm::Expected<llvm::SmallVector<std::string>>
listKernelNames(llvm::MemoryBufferRef CodeObject);

} // namespace COMGR::hotswap

#endif
