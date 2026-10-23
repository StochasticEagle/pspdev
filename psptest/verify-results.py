#!/usr/bin/env python3
"""Validate PSPTEST results captured on PSP hardware, with optional modules."""
import argparse
from pathlib import Path

VALID = {"PASS", "FAIL", "SKIP", "INTERACTIVE_PASS", "INTERACTIVE_FAIL"}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--required", type=Path, required=True)
    args = parser.parse_args()

    required = {line.strip() for line in args.required.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("#")}
    manifest = args.manifest.read_text().splitlines()
    if not manifest or manifest[0] != "PSPTEST_MANIFEST\t1":
        parser.error("Invalid PSPTEST manifest")

    modules = {}
    for row in manifest[1:]:
        parts = row.split("\t")
        if len(parts) not in (4, 5) or parts[0] != "TEST" or parts[3] != "module":
            parser.error(f"Invalid manifest record: {row}")
        module = parts[1]
        policy = parts[4] if len(parts) == 5 else "required"
        if policy not in {"required", "optional"} or module in modules:
            parser.error(f"Duplicate module or invalid policy: {module}")
        modules[module] = policy

    if required - modules.keys():
        parser.error("Missing required modules: " + ", ".join(sorted(required - modules.keys())))
    if any(modules[name] == "optional" for name in required):
        parser.error("Required module incorrectly marked optional")

    errors = []
    checked = passed = skipped = absent_optional = 0
    for module, policy in sorted(modules.items()):
        path = args.results / (module + ".log")
        if not path.is_file():
            if module in required:
                errors.append(f"{module}: missing runtime result")
            else:
                absent_optional += 1
            continue

        lines = path.read_text(errors="replace").splitlines()
        if len(lines) < 4 or lines[0] != "PSPTEST\t1" or lines[1] != "SUITE\t" + module:
            errors.append(f"{module}: invalid result header")
            continue
        cases = [line.split("\t") for line in lines if line.startswith("CASE\t")]
        summaries = [line for line in lines if line.startswith("SUMMARY\t")]
        if not cases or len(summaries) != 1 or any(len(case) < 3 for case in cases):
            errors.append(f"{module}: missing cases or summary")
            continue
        statuses = [case[1] for case in cases]
        if any(status not in VALID for status in statuses):
            errors.append(f"{module}: unknown status")
            continue
        fail_count = sum(status in {"FAIL", "INTERACTIVE_FAIL"} for status in statuses)
        skip_count = sum(status == "SKIP" for status in statuses)
        pass_count = len(cases) - fail_count - skip_count

        if fail_count:
            errors.append(f"{module}: {fail_count} runtime failures")
        if module in required and skip_count:
            skip_names = [case[2] for case in cases if case[1] == "SKIP"]
            # The framework self-test explicitly exercises the skip path.
            if module != "pspsdk/framework" or skip_names != ["skip_is_recorded"]:
                errors.append(f"{module}: required test was skipped")

        summary = {}
        for part in summaries[0].split("\t")[1:]:
            key, sep, value = part.partition("=")
            if sep and value.isdigit():
                summary[key] = int(value)
        if any((summary.get("total") != len(cases),
                summary.get("pass") != pass_count,
                summary.get("fail") != fail_count,
                summary.get("skip") != skip_count)):
            errors.append(f"{module}: summary totals do not match case records")

        checked += 1
        passed += pass_count
        skipped += skip_count

    if errors:
        parser.error("\n".join(errors))
    print(f"PSP runtime PASS: {checked} tested modules; {passed} passed cases, "
          f"{skipped} skipped cases, {absent_optional} unrun optional modules")

if __name__ == "__main__":
    main()
