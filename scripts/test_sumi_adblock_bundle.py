#!/usr/bin/env python3
from pathlib import Path
import importlib.util
import sys


SCRIPT = Path(__file__).resolve().with_name("sumi_adblock_bundle.py")
SPEC = importlib.util.spec_from_file_location("sumi_adblock_bundle", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["sumi_adblock_bundle"] = MODULE
SPEC.loader.exec_module(MODULE)


if __name__ == "__main__":
    MODULE.self_test()
    print("sumi_adblock_bundle self-test passed")
