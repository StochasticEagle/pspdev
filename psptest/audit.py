#!/usr/bin/env python3
"""Static PSPTEST coverage inventory and required binary validation."""
import argparse
import json
import re
from pathlib import Path

def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--packages", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--required", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    sdk = args.sdk.resolve()
    required = [line.strip() for line in args.required.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("#")]
    if not required or len(required) != len(set(required)):
        parser.error("Missing or duplicated required module definitions")

    modules = {}
    records = args.manifest.read_text().splitlines()
    if not records or records[0] != "PSPTEST_MANIFEST\t1":
        parser.error("Invalid PSPTEST manifest")
    for line in records[1:]:
        parts = line.split("\t")
        if len(parts) not in (4, 5) or parts[0] != "TEST" or parts[3] != "module" or (len(parts) == 5 and parts[4] not in ("required", "optional")):
            parser.error(f"Invalid PSPTEST manifest record: {line}")
        name, path = parts[1:3]
        if name in modules:
            parser.error(f"Duplicate module: {name}")
        binary = (args.manifest.parent / path).resolve()
        if not binary.is_relative_to(args.manifest.parent.resolve()):
            parser.error(f"Unsafe module path: {path}")
        if not binary.is_file() or binary.stat().st_size == 0:
            parser.error(f"Missing PRX: {binary}")
        modules[name] = {"path": path, "policy": parts[4] if len(parts) == 5 else "required"}

    missing = sorted(set(required) - modules.keys())
    incorrectly_optional = sorted(name for name in required if name in modules and modules[name]["policy"] == "optional")
    if incorrectly_optional:
        parser.error("Core modules incorrectly marked optional: " + ", ".join(incorrectly_optional))
    if missing:
        parser.error(f"Missing mandatory PSPTEST modules: {', '.join(missing)}")

    covered_by = {}
    case_count = 0
    for root in [sdk / "psptest", args.packages / "psptest"]:
        if not root.exists():
            continue
        for source in sorted(root.glob("*/main.*")):
            if source.suffix not in {".c", ".cpp", ".cc"}:
                continue
            namespace = "pspsdk" if root == sdk / "psptest" else "packages"
            module = f"{namespace}/{source.parent.name}"
            if module not in modules:
                continue
            code = strip_comments(source.read_text(errors="replace"))
            # Optimization variants include the canonical Allegrex tests.
            # Count the instantiated cases, not only source definitions.
            for included in re.findall(r'#include\s+"(\.\./[^"]+\.c)"', code):
                target = (source.parent / included).resolve()
                if not target.is_relative_to(root.resolve()) or not target.is_file():
                    parser.error(f"Invalid test include: {source}: {included}")
                code += "\n" + strip_comments(target.read_text(errors="replace"))
            case_count += len(re.findall(r"\bPSPTEST_CASE\s*\(", code))
            case_count += len(re.findall(r"\bPSPTEST_INTERACTIVE_CASE\s*\(", code))
            for function in re.findall(r"\bPSPTEST_COVERS\s*\(\s*([A-Za-z_]\w*)\s*\)", code):
                covered_by.setdefault(function, set()).add(module)

    # The exported API inventory is based on SDK declaration headers.
    # C comments are stripped to avoid counting example calls as exports.
    api_headers = {}
    for header in sorted((sdk / "src").rglob("*.h")):
        code = strip_comments(header.read_text(errors="replace"))
        for name in re.findall(r"\b(sce[A-Z]\w*)\s*\(", code):
            api_headers.setdefault(name, set()).add(str(header.relative_to(sdk)))

    sdk_names = set(api_headers)
    covered = sorted(sdk_names & covered_by.keys())
    uncovered = sorted(sdk_names - covered_by.keys())
    result = {
        "schema": 1,
        "scope": "static API and module inventory; PSP execution not verified",
        "module_count": len(modules),
        "required_module_count": len(required),
        "case_declarations": case_count,
        "sdk_api_declarations": len(sdk_names),
        "sdk_api_marked": len(covered),
        "sdk_api_unmarked": len(uncovered),
        "module_names": sorted(modules),
        "module_policy": {name: entry["policy"] for name, entry in sorted(modules.items())},
        "optional_module_count": sum(e["policy"] == "optional" for e in modules.values()),
        "required": required,
        "covered": [{"api": name, "modules": sorted(covered_by[name])} for name in covered],
        "uncovered": [{"api": name, "headers": sorted(api_headers[name])} for name in uncovered],
        "non_sdk_markers": sorted(covered_by.keys() - sdk_names)
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if case_count < 53:
        parser.error(f"Required regression tests missing: found {case_count} cases, expected at least 53")
    print(f"PSPTEST: {len(modules)} linked PRXs, {case_count} case declarations, "
          f"{len(covered)}/{len(sdk_names)} declared SDK APIs marked; "
          f"{len(uncovered)} SDK APIs unmarked")
    print(f"Coverage report: {args.output}")

if __name__ == "__main__":
    main()
