#!/usr/bin/env python3
"""Validate persisted PSPTEST results from real PSP execution."""
import argparse
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--required", type=Path, required=True)
    args = parser.parse_args()
    required = set(line.strip() for line in args.required.read_text().splitlines()
                   if line.strip() and not line.lstrip().startswith("#"))
    manifests = args.manifest.read_text().splitlines()
    if not manifests or manifests[0] != "PSPTEST_MANIFEST\t1":
        parser.error("Invalid manifest")
    available = {line.split("\t")[1] for line in manifests[1:]
                 if line.startswith("TEST\t") and len(line.split("\t")) == 4}
    if required - available:
        parser.error("Missing required modules in manifest: " + ", ".join(sorted(required-available)))
    errors = []
    checked = 0
    for module in sorted(required):
        result_file = args.results / (module + ".log")
        if not result_file.is_file():
            errors.append(f"{module}: missing runtime result")
            continue
        lines = result_file.read_text(errors="replace").splitlines()
        if len(lines) < 4 or lines[0] != "PSPTEST\t1" or lines[1] != "SUITE\t" + module:
            errors.append(f"{module}: invalid result format")
            continue
        cases = [line.split("\t") for line in lines if line.startswith("CASE\t")]
        summary = [line for line in lines if line.startswith("SUMMARY\t")]
        if len(summary) != 1 or not cases:
            errors.append(f"{module}: missing case records or summary")
            continue
        case_statuses = [case[1] for case in cases if len(case) > 2]
        if len(case_statuses) != len(cases):
            errors.append(f"{module}: malformed case records")
            continue
        if any(status in {"FAIL", "INTERACTIVE_FAIL", "SKIP"} for status in case_statuses):
            # The historical framework module intentionally contains a skip
            # self-test; only that explicit expected skip is allowed.
            if module != "pspsdk/framework" or case_statuses.count("SKIP") != 1 or any(
                status in {"FAIL", "INTERACTIVE_FAIL"} for status in case_statuses
            ):
                errors.append(f"{module}: failing or skipped runtime case")
        if any(status not in {"PASS", "INTERACTIVE_PASS", "SKIP"} for status in case_statuses):
            errors.append(f"{module}: unknown case status")
        summary_fields = {}
        for part in summary[0].split("\t")[1:]:
            key, sep, value = part.partition("=")
            if sep and value.isdigit():
                summary_fields[key] = int(value)
        if summary_fields.get("total") != len(cases) or summary_fields.get("fail") != 0:
            errors.append(f"{module}: inconsistent or failing summary")
        if summary_fields.get("pass", 0) + summary_fields.get("skip", 0) != len(cases):
            errors.append(f"{module}: summary counts do not reconcile")
        checked += len(cases)
    if errors:
        parser.error("\n".join(errors))
    print(f"PASS: {len(required)} required modules, {checked} cases verified from hardware-generated results")

if __name__ == "__main__":
    main()
