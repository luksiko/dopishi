#!/usr/bin/env python3
"""Verify that project.pbxproj group entries point at files that exist.

Xcode trusts the project file, so a file referenced from the wrong group
(e.g. a Views/ file filed under the Services group) is a CI build failure
that glob-based command-line builds never catch. Checks performed:

  1. Every PBXFileReference inside a source group must exist at the path
     the group implies (missing files).
  2. Every Swift file on disk must be referenced by some group (orphans).
  3. The test target's Sources phase, the LangSwitcherTests group and the
     LangSwitcherTests directory must agree: same *Tests.swift files, and
     nothing non-test in the phase (silent coverage loss / duplicated
     symbols otherwise).

Usage:
  python3 scripts/verify-pbxproj.py              # check the real project
  python3 scripts/verify-pbxproj.py --self-test  # run drift fixtures

Exit 1 on any problem (self-test: exit 1 if any fixture is missed).
"""

import os
import re
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, "LangSwitcher.xcodeproj", "project.pbxproj")

# Group path -> directory on disk, relative to the project root. Product
# groups have no directory. Assets.xcassets lives outside Sources/ (the
# pbxproj resolves it via the parent LangSwitcher group).
GROUP_DIRS = {
    "App": "LangSwitcher/Sources/App",
    "Views": "LangSwitcher/Sources/Views",
    "Services": "LangSwitcher/Sources/Services",
    "Models": "LangSwitcher/Sources/Models",
    "Localization": "LangSwitcher/Sources/Localization",
    "Resources": "LangSwitcher/Resources",
    "LangSwitcherTests": "LangSwitcherTests",
}

REF = r"([A-F0-9]{24})"


def parse(content):
    """Return (filerefs, groups, phases) parsed from pbxproj text.

    filerefs: {id: name}
    groups:   {id: (group_name, [(child_id, child_name), ...], path_or_None)}
    phases:   {id: [file_name, ...]}   # Sources build phases only
    """
    filerefs = {}
    for ref, name in re.findall(
        REF + r" /\* (.+?) \*/ = \{isa = PBXFileReference;", content
    ):
        filerefs[ref] = name

    groups = {}
    for match in re.finditer(
        REF
        + r" /\* (\w+) \*/ = \{\s*isa = PBXGroup;\s*children = \((.*?)\);\s*(?:path = ([\w.]+);)?",
        content,
        re.S,
    ):
        gid, name, children, path = match.groups()
        pairs = re.findall(REF + r" /\* (.+?) \*/", children)
        groups[gid] = (name, pairs, path)

    phases = {}
    for match in re.finditer(
        REF + r" /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);",
        content,
        re.S,
    ):
        # group(1) is the phase id, group(2) is the file list captured above.
        files = [
            name
            for _, name in re.findall(
                REF + r" /\* (.+?) in Sources \*/", match.group(2)
            )
        ]
        phases[match.group(1)] = files

    return filerefs, groups, phases


def swift_files_on_disk(root):
    on_disk = set()
    sources = os.path.join(root, "LangSwitcher", "Sources")
    if os.path.isdir(sources):
        for _base, _dirs, files in os.walk(sources):
            on_disk.update(f for f in files if f.endswith(".swift"))
    tests_dir = os.path.join(root, "LangSwitcherTests")
    if os.path.isdir(tests_dir):
        on_disk.update(f for f in os.listdir(tests_dir) if f.endswith(".swift"))
    return on_disk


def group_file_names(filerefs, groups):
    """Names referenced by any group mapped to a real directory."""
    referenced = set()
    for _gid, (_name, children, path) in groups.items():
        if path not in GROUP_DIRS:
            continue
        for ref, child in children:
            name = filerefs.get(ref, child)
            if name.endswith((".swift", ".xcassets")):
                referenced.add(name)
    return referenced


def check_project(content, root):
    """Return a list of human-readable problems (empty = healthy)."""
    filerefs, groups, phases = parse(content)
    errors = []
    referenced = set()

    # 1+2. Group children must exist on disk; disk files must be referenced.
    for _gid, (_name, children, path) in groups.items():
        directory = GROUP_DIRS.get(path)
        if directory is None:
            continue
        for ref, child_name in children:
            name = filerefs.get(ref, child_name)
            if not name.endswith((".swift", ".xcassets")):
                continue
            referenced.add(name)
            if not os.path.exists(os.path.join(root, directory, name)):
                errors.append(f"missing: {path}/{name}  (referenced {ref})")

    for orphan in sorted(swift_files_on_disk(root) - referenced):
        errors.append(f"on disk but not in project: {orphan}")

    # 3. Test target consistency: the Sources phase containing
    # *Tests.swift entries is the test target's compile phase.
    test_phases = [
        files for files in phases.values()
        if any(f.endswith("Tests.swift") for f in files)
    ]
    group_by_name = {name: children for name, children, _ in groups.values()}
    tests_group_names = {
        filerefs.get(ref, child)
        for ref, child in group_by_name.get("LangSwitcherTests", [])
    }
    tests_dir_files = {
        f for f in swift_files_on_disk(root) if f.endswith("Tests.swift")
    }

    for files in test_phases:
        phase_set = set(files)
        for name in sorted(phase_set):
            if not name.endswith("Tests.swift"):
                errors.append(f"in test target but not a *Tests.swift file: {name}")
            if name not in tests_dir_files:
                errors.append(f"in test target but not on disk under LangSwitcherTests: {name}")
            if name not in tests_group_names:
                errors.append(f"in test target Sources but missing from LangSwitcherTests group: {name}")
        for name in sorted(tests_group_names - phase_set):
            errors.append(f"in LangSwitcherTests group but missing from test target Sources: {name}")
        for name in sorted(tests_dir_files - phase_set):
            errors.append(f"test file on disk but not in test target: {name}")

    return errors


# --- Self test: miniature pbxproj fixtures with planted drift ---------------

def fid(n):
    """A 24-char uppercase id (the pbxproj format)."""
    return "A%023d" % n


def fixture_project(filerefs, groups, phases):
    parts = ["// !$*UTF8*$!\n{\n"]
    for rid, name in filerefs:
        parts.append(
            f"\t\t{rid} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {name}; "
            f"sourceTree = \"<group>\"; }};\n"
        )
    for gid, name, children, path in groups:
        kids = "".join(f"\t\t\t\t{ref} /* {child} */,\n" for ref, child in children)
        path_line = f"\t\t\tpath = {path};\n" if path else ""
        parts.append(
            f"\t\t{gid} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n{kids}\t\t\t);\n{path_line}"
            f"\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
        )
    for pid, files in phases:
        entries = "".join(
            f"\t\t\t\t{ref} /* {name} in Sources */,\n" for ref, name in files
        )
        parts.append(
            f"\t\t{pid} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n"
            f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{entries}"
            f"\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"
        )
    parts.append("}\n")
    return "".join(parts)


# Shared fixture skeleton: one app view + two test files, all consistent.
VIEW_ID, ALPHA_ID, BETA_ID = fid(1), fid(2), fid(3)
BASE_FILTEREFS = [
    (VIEW_ID, "SomeView.swift"),
    (ALPHA_ID, "AlphaTests.swift"),
    (BETA_ID, "BetaTests.swift"),
]
APP_GROUP = (fid(10), "Views", [(VIEW_ID, "SomeView.swift")], "Views")
TESTS_GROUP = (
    fid(11),
    "LangSwitcherTests",
    [(ALPHA_ID, "AlphaTests.swift"), (BETA_ID, "BetaTests.swift")],
    "LangSwitcherTests",
)
TEST_PHASE = (
    fid(12),
    [(ALPHA_ID, "AlphaTests.swift"), (BETA_ID, "BetaTests.swift")],
)


def run_fixture(root, content, expected_substrings, label):
    errors = check_project(content, root)
    problems = []
    for expected in expected_substrings:
        if not any(expected in error for error in errors):
            problems.append(f"    MISSED: {expected!r} (got: {errors or 'no errors'})")
    print(f"  {'ok  ' if not problems else 'FAIL'} {label}")
    for problem in problems:
        print(problem)
    return not problems


def self_test():
    ok = True
    with tempfile.TemporaryDirectory() as tmp:

        def make_root(test_files, app_files=("LangSwitcher/Sources/Views/SomeView.swift",)):
            root = tempfile.mkdtemp(dir=tmp)
            for rel in list(app_files) + [f"LangSwitcherTests/{f}" for f in test_files]:
                full = os.path.join(root, rel)
                os.makedirs(os.path.dirname(full), exist_ok=True)
                with open(full, "w") as fh:
                    fh.write("// test\n")
            return root

        # 1. Healthy project: no errors.
        root = make_root(["AlphaTests.swift", "BetaTests.swift"])
        ok &= run_fixture(
            root, fixture_project(BASE_FILTEREFS, [APP_GROUP, TESTS_GROUP], [TEST_PHASE]),
            [], "healthy project passes",
        )

        # 2. Test file in phase + group but missing on disk.
        root = make_root(["AlphaTests.swift"])
        ok &= run_fixture(
            root, fixture_project(BASE_FILTEREFS, [APP_GROUP, TESTS_GROUP], [TEST_PHASE]),
            ["missing: LangSwitcherTests/BetaTests.swift",
             "in test target but not on disk under LangSwitcherTests"],
            "phase entry without a file on disk is caught",
        )

        # 3. Test file on disk but registered nowhere.
        root = make_root(["AlphaTests.swift", "BetaTests.swift", "OrphanTests.swift"])
        ok &= run_fixture(
            root, fixture_project(BASE_FILTEREFS, [APP_GROUP, TESTS_GROUP], [TEST_PHASE]),
            ["on disk but not in project: OrphanTests.swift",
             "test file on disk but not in test target: OrphanTests.swift"],
            "unregistered test file is caught twice",
        )

        # 4. Non-test file smuggled into the test phase.
        root = make_root(["AlphaTests.swift", "BetaTests.swift", "Helper.swift"])
        helper = fid(4)
        ok &= run_fixture(
            root,
            fixture_project(
                BASE_FILTEREFS + [(helper, "Helper.swift")],
                [APP_GROUP, (TESTS_GROUP[0], TESTS_GROUP[1],
                             TESTS_GROUP[2] + [(helper, "Helper.swift")],
                             TESTS_GROUP[3])],
                [(TEST_PHASE[0], TEST_PHASE[1] + [(helper, "Helper.swift")])],
            ),
            ["in test target but not a *Tests.swift file: Helper.swift"],
            "non-test file in the test phase is caught",
        )

        # 5. Test file in the group but not compiled into the target.
        root = make_root(["AlphaTests.swift", "BetaTests.swift", "GammaTests.swift"])
        gamma = fid(5)
        ok &= run_fixture(
            root,
            fixture_project(
                BASE_FILTEREFS + [(gamma, "GammaTests.swift")],
                [APP_GROUP, (TESTS_GROUP[0], TESTS_GROUP[1],
                             TESTS_GROUP[2] + [(gamma, "GammaTests.swift")],
                             TESTS_GROUP[3])],
                [TEST_PHASE],
            ),
            ["in LangSwitcherTests group but missing from test target Sources: GammaTests.swift",
             "test file on disk but not in test target: GammaTests.swift"],
            "group member not compiled into the target is caught",
        )

        # 6. Test file in the phase but absent from the group.
        root = make_root(["AlphaTests.swift", "BetaTests.swift", "DeltaTests.swift"])
        delta = fid(6)
        ok &= run_fixture(
            root,
            fixture_project(
                BASE_FILTEREFS + [(delta, "DeltaTests.swift")],
                [APP_GROUP, TESTS_GROUP],
                [(TEST_PHASE[0], TEST_PHASE[1] + [(delta, "DeltaTests.swift")])],
            ),
            ["in test target Sources but missing from LangSwitcherTests group: DeltaTests.swift"],
            "phase entry outside the group is caught",
        )

        # 7. The original drift: a Views file filed under Services.
        root = make_root(["AlphaTests.swift", "BetaTests.swift"])
        services_group = (fid(13), "Services", [(VIEW_ID, "SomeView.swift")], "Services")
        ok &= run_fixture(
            root, fixture_project(BASE_FILTEREFS, [services_group, TESTS_GROUP], [TEST_PHASE]),
            ["missing: Services/SomeView.swift"],
            "file under the wrong group is caught",
        )

    print(f"self-test {'passed' if ok else 'FAILED'}")
    return ok


def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)

    with open(PBX) as fh:
        content = fh.read()
    errors = check_project(content, ROOT)
    for error in errors:
        print(error)
    filerefs, groups, _phases = parse(content)
    referenced = group_file_names(filerefs, groups)
    on_disk = swift_files_on_disk(ROOT)
    print(f"{len(referenced)} referenced, {len(on_disk)} on disk, {len(errors)} problems")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
