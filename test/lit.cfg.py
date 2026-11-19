import os
import shutil
import sys

import lit.formats

config.name = "fi-harden"
config.test_format = lit.formats.ShTest(execute_external=False)
config.suffixes = [".ll", ".c", ".test"]
config.test_source_root = os.path.dirname(__file__)
config.test_exec_root = os.path.join(config.fi_obj_root, "test")
config.excludes = ["Inputs"]

# Tools must come from the LLVM the plugin was built against: a plugin only loads into the same
# major version, and a system clang may be a different one.
for tool in ["opt", "llc", "clang", "llvm-objdump", "FileCheck", "not", "count"]:
    if not os.path.exists(os.path.join(config.llvm_tools_dir, tool)):
        lit_config.fatal(f"{tool} not found in {config.llvm_tools_dir}")
config.environment["PATH"] = os.pathsep.join([config.llvm_tools_dir, config.environment["PATH"]])

config.substitutions.append(("%fi_plugin", config.fi_plugin))
config.substitutions.append(("%python", f'"{sys.executable}"'))
audit = os.path.join(config.test_source_root, "..", "eval", "audit.py")
config.substitutions.append(("%audit", f'"{sys.executable}" "{audit}"'))

if shutil.which("csmith", path=config.environment["PATH"]):
    config.available_features.add("csmith")

try:  # eval/fisim.py's modules, in the interpreter that runs %python
    import capstone, elftools, unicorn  # noqa: F401
    config.available_features.add("fisim")
except ImportError:
    pass
