#!/usr/bin/env python3
# Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""Unified pipeline command for batch generation, reviewed commits, and PRs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import signal
import subprocess
import sys
import time
from collections.abc import Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import publish_docs as docs
import publish_sample as samples

ROOT = Path(__file__).resolve().parent.parent
ARTIFACTS_DIR = ROOT / "artifacts"
ARCHIVE_DIR = ROOT / "artifacts_archive"
STATE_FILE = ROOT / "batch_state.json"
DEFAULT_CONFIG = ROOT / "batch_connectors.json"


def fail(msg: str) -> None:
    print(f"\n[ERROR] {msg}", file=sys.stderr)
    sys.exit(1)


def slugify(name: str) -> str:
    slug = name.strip().lower()
    slug = re.sub(r"\s+", "-", slug)
    return re.sub(r"[^a-z0-9\-.]", "", slug)


def fmt_duration(seconds: float) -> str:
    minutes, secs = divmod(int(seconds), 60)
    return f"{minutes}m {secs:02d}s"


def batch_items(config: dict[str, Any]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for connector in config.get("connectors", []):
        item = dict(connector)
        item.setdefault("type", "connector")
        items.append(item)
    for trigger in config.get("triggers", []):
        item = dict(trigger)
        item.setdefault("type", "trigger")
        items.append(item)
    for configured_item in config.get("items", []):
        item = dict(configured_item)
        item.setdefault("type", "connector")
        items.append(item)
    return items


def config_hash(config: dict[str, Any]) -> str:
    payload = json.dumps(batch_items(config), sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()[:16]


def load_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        fail(f"Config not found: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    items = batch_items(data)
    if not items:
        fail("Config must include at least one item in 'connectors', 'triggers', or 'items'.")
    for i, item in enumerate(items):
        if not isinstance(item, dict) or "name" not in item:
            fail(f"Batch item {i} must be an object with a 'name' field.")
        if item.get("type") not in ("connector", "trigger"):
            fail(f"Batch item {i} has unsupported type: {item.get('type')}")
    data.setdefault("docsBranch", "docs/connector-docs")
    data.setdefault("samplesBranch", "samples/connector-samples")
    return data


def load_state(config: dict[str, Any], config_path: Path, no_resume: bool) -> dict[str, Any]:
    empty: dict[str, Any] = {
        "configPath": str(config_path),
        "configHash": config_hash(config),
        "completed": [],
        "failed": [],
        "inProgress": None,
        "results": [],
    }
    if no_resume or not STATE_FILE.exists():
        return empty
    state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    if state.get("configHash") != config_hash(config):
        print("[INFO] Batch config changed; preserving existing completed/failed state.")
        state["configHash"] = config_hash(config)
        save_state(state)
    print(
        f"[INFO] Resuming from saved state ({len(state.get('completed', []))} completed, "
        f"{len(state.get('failed', []))} failed)"
    )
    return state


def save_state(state: dict[str, Any]) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")


def archive_artifacts(slug: str, status: str) -> Path | None:
    if not ARTIFACTS_DIR.exists():
        return None
    suffix = "" if status == "OK" else f"_{status}"
    dest = ARCHIVE_DIR / f"{slug}{suffix}"
    if dest.exists():
        dest = ARCHIVE_DIR / f"{slug}{suffix}_{datetime.now().strftime('%H%M%S')}"
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    shutil.move(str(ARTIFACTS_DIR), str(dest))
    print(f"[INFO] Archived artifacts to {dest.relative_to(ROOT)}")
    return dest


def parse_run_cost(slug: str) -> dict[str, Any] | None:
    run_log_dir = ARTIFACTS_DIR / "run-log"
    if not run_log_dir.exists():
        return None
    logs = sorted(run_log_dir.glob(f"{slug}-*_*.json"), key=lambda p: p.stat().st_mtime)
    if not logs:
        logs = sorted(run_log_dir.glob("*.json"), key=lambda p: p.stat().st_mtime)
    if not logs:
        return None
    data = json.loads(logs[-1].read_text(encoding="utf-8"))
    return {
        "totalCostUsd": data.get("totalCombinedCostUsd"),
        "durationSeconds": data.get("durationSeconds"),
    }


def read_created_project_path() -> str | None:
    path = ARTIFACTS_DIR / "run-log" / "created-project.txt"
    return path.read_text(encoding="utf-8").strip() if path.exists() else None


def run_pipeline_item(item_type: str, name: str, instructions: str, package: str, timeout: int) -> bool:
    key = "TRIGGER" if item_type == "trigger" else "CONNECTOR"
    cmd = ["make", "run", f"{key}={name}"]
    if package:
        cmd.append(f"PACKAGE={package}")
    if instructions:
        cmd.append(f"ADDITIONAL_INSTRUCTIONS={instructions}")
    print(f"[CMD] {' '.join(cmd)}")
    try:
        return subprocess.run(cmd, cwd=str(ROOT), timeout=timeout).returncode == 0
    except subprocess.TimeoutExpired:
        print(f"[ERROR] Pipeline timed out after {timeout}s")
        return False


def print_batch_summary(results: list[dict[str, Any]], config: dict[str, Any]) -> str:
    lines: list[str] = []

    def out(line: str = "") -> None:
        lines.append(line)
        print(line)

    total_cost = 0.0
    total_duration = 0.0
    ok_count = 0
    fail_count = 0

    out("=" * 70)
    out("BATCH RUN SUMMARY")
    out("=" * 70)
    out(f" {'#':>3}  {'Item':<20} {'Status':<10} {'Duration':<12} {'Cost':<10}")
    out(f" {'---':>3}  {'--------------------':<20} {'----------':<10} {'------------':<12} {'----------':<10}")
    for i, result in enumerate(results, 1):
        cost = result.get("cost")
        cost_str = f"${cost:.2f}" if cost is not None else "n/a"
        duration = result.get("duration", 0)
        out(f" {i:3d}  {result['name']:<20} {result['status']:<10} {fmt_duration(duration):<12} {cost_str:<10}")
        if cost is not None:
            total_cost += cost
        total_duration += duration
        if result["status"] == "OK":
            ok_count += 1
        else:
            fail_count += 1

    out("-" * 70)
    out(f"Total: {len(results)} items | {ok_count} OK | {fail_count} failed")
    out(f"Total cost: ${total_cost:.2f}  |  Total time: {fmt_duration(total_duration)}")
    out("=" * 70)

    successful = [r for r in results if r["status"] == "OK"]
    if successful:
        docs_branch = config.get("docsBranch", "docs/connector-docs")
        samples_branch = config.get("samplesBranch", "samples/connector-samples")
        out()
        out("COMMIT INSTRUCTIONS (for approved items):")
        out("-" * 70)
        for result in successful:
            archive_dir = result.get("archiveDir", f"artifacts_archive/{result['slug']}")
            out(f"# {result['name']}")
            out(f"python python/pipeline.py commit-docs --artifacts-dir {archive_dir} --branch {docs_branch}")
            if result.get("projectPath"):
                out(
                    "python python/pipeline.py commit-sample "
                    f"--project-path {result['projectPath']} --branch {samples_branch}"
                )
            else:
                out(f"# (no created-project.txt found — check {archive_dir}/run-log/)")
            out()
        out("# After reviewing and committing all approved items:")
        out(f"python python/pipeline.py pr-docs --branch {docs_branch}")
        out(f"python python/pipeline.py pr-samples --branch {samples_branch}")
        out("=" * 70)

    return "\n".join(lines)


def branch_exists_on_origin(repo: Path, branch: str, run_func) -> bool:
    try:
        return bool(run_func(["git", "ls-remote", "--heads", "origin", branch], cwd=repo).strip())
    except subprocess.CalledProcessError:
        return False


def checkout_or_create_batch_branch(
    repo: Path,
    branch: str,
    dry_run: bool,
    upstream_slug: str,
    base_branch: str,
    run_func,
    label: str,
) -> None:
    remotes = run_func(["git", "remote"], cwd=repo).split()
    if "upstream" not in remotes:
        fail(
            f"'upstream' remote not found in {label} repo.\n"
            f"Add it with: git remote add upstream https://github.com/{upstream_slug}.git"
        )
    if dry_run:
        docs.dry(f"git fetch origin upstream  (in {repo})")
        if branch_exists_on_origin(repo, branch, run_func):
            docs.dry(f"Branch '{branch}' exists on origin — git checkout -B {branch} origin/{branch}")
        else:
            docs.dry(f"Branch '{branch}' not found on origin — create from upstream/{base_branch}")
            docs.dry(f"git checkout {base_branch} && git merge upstream/{base_branch} --ff-only")
            docs.dry(f"git checkout -b {branch}")
        docs.dry(f"git merge upstream/{base_branch} --no-edit")
        docs.dry(f"git push origin {branch}")
        return

    docs.info("Fetching origin and upstream...")
    subprocess.run(["git", "fetch", "origin"], cwd=str(repo), check=True)
    subprocess.run(["git", "fetch", "upstream"], cwd=str(repo), check=True)
    if branch_exists_on_origin(repo, branch, run_func):
        docs.info(f"Batch branch '{branch}' already exists — checking out...")
        subprocess.run(["git", "checkout", "-B", branch, f"origin/{branch}"], cwd=str(repo), check=True)
    else:
        docs.info(f"Batch branch '{branch}' not found on origin — creating from upstream/{base_branch}...")
        subprocess.run(["git", "checkout", base_branch], cwd=str(repo), check=True)
        try:
            subprocess.run(["git", "merge", f"upstream/{base_branch}", "--ff-only"], cwd=str(repo), check=True)
        except subprocess.CalledProcessError:
            fail(f"Could not fast-forward fork's {base_branch} to upstream/{base_branch}.")
        subprocess.run(["git", "checkout", "-b", branch], cwd=str(repo), check=True)
    try:
        subprocess.run(["git", "merge", f"upstream/{base_branch}", "--no-edit"], cwd=str(repo), check=True)
    except subprocess.CalledProcessError:
        fail(f"Merge conflict when pulling upstream/{base_branch} into '{branch}'.")
    subprocess.run(["git", "push", "origin", branch], cwd=str(repo), check=True)


def checkout_branch(repo: Path, branch: str, dry_run: bool) -> None:
    if dry_run:
        docs.dry(f"git fetch origin  (in {repo})")
        docs.dry(f"git checkout {branch}")
        return
    docs.info("Fetching origin...")
    subprocess.run(["git", "fetch", "origin"], cwd=str(repo), check=True)
    docs.info(f"Checking out branch: {branch}")
    subprocess.run(["git", "checkout", branch], cwd=str(repo), check=True)


def read_names_from_branch(repo: Path, base_branch: str, pattern: str, label: str, run_func) -> list[str]:
    try:
        last_merge = run_func(["git", "log", "--merges", "-n", "1", "--pretty=format:%H", "HEAD"], cwd=repo).strip()
    except subprocess.CalledProcessError:
        last_merge = ""
    log_range = f"{last_merge}..HEAD" if last_merge else f"origin/{base_branch}..HEAD"
    try:
        log = run_func(["git", "log", log_range, "--pretty=format:%s"], cwd=repo)
    except subprocess.CalledProcessError:
        docs.warn(f"Could not read git log for {log_range}. Trying HEAD~20...")
        log = run_func(["git", "log", "HEAD~20..HEAD", "--pretty=format:%s"], cwd=repo)
    names = []
    for subject in log.splitlines():
        match = re.match(pattern, subject, re.IGNORECASE)
        if match:
            names.append(match.group(1))
    if not names:
        docs.warn(f"No {label} commit messages found in branch log.")
    return names


def build_docs_batch_pr_body(connector_names: list[str], branch: str) -> str:
    connector_list = "\n".join(f"- {name}" for name in connector_names) if connector_names else "- (could not detect connector names from git log)"
    summary = f"the following {len(connector_names)} connector(s)" if connector_names else "multiple connectors"
    return f"""\
## Purpose

Adds step-by-step example guides for {summary}:

{connector_list}

Each guide covers connection setup and the primary operation with embedded screenshots.

## Approach

Content generated by the connector-docs-automations pipeline and committed to
branch `{branch}` via `pipeline.py commit-docs`.

## Connectors included

{connector_list}

## Release note

Added connector example guides for: {", ".join(connector_names) if connector_names else "multiple connectors"}.

## Security checks

- Followed secure coding standards: N/A (documentation only)
- Ran FindSecurityBugs plugin: N/A (documentation only)
"""


def build_samples_batch_pr_body(sample_names: list[str]) -> str:
    sample_list = "\n".join(f"- `connectors/{name}/`" for name in sample_names) if sample_names else "- (could not detect sample names from git log)"
    summary = f"the following {len(sample_names)} connector(s)" if sample_names else "multiple connectors"
    return f"""\
## Purpose

Adds runnable Ballerina connector integration samples for {summary}:

{sample_list}

Each sample demonstrates end-to-end connector usage in WSO2 Integrator.

## Approach

Samples generated by the connector-docs-automations pipeline and committed via
`pipeline.py commit-sample`.

## Samples included

{sample_list}

## Release note

Added Ballerina connector integration samples for: {", ".join(f"`{n}`" for n in sample_names) if sample_names else "multiple connectors"}.

## Automation tests

- Unit tests: N/A (sample projects)
- Integration tests: N/A (sample projects)

## Security checks

- Ran FindSecurityBugs plugin: N/A (Ballerina projects)
"""


def create_batch_pr(fork: str, upstream: str, base_branch: str, branch: str, title: str, body: str, dry_run: bool) -> str:
    head = f"{fork.split('/')[0]}:{branch}"
    if dry_run:
        docs.dry(f"gh pr create --repo {upstream} --head {head} --base {base_branch}")
        docs.dry(f"  Title: {title}")
        return "(dry run — no PR created)"
    docs.info(f"Creating PR: {upstream} ← {head}")
    try:
        result = subprocess.run(
            ["gh", "pr", "create", "--repo", upstream, "--head", head, "--base", base_branch, "--title", title, "--body", body],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as exc:
        fail(f"Failed to create PR:\n{exc.stderr.strip()}")


def run_batch(argv: Sequence[str]) -> None:
    parser = argparse.ArgumentParser(description="Queue multiple connectors or triggers for sequential pipeline execution.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG), help=f"Path to batch config JSON (default: {DEFAULT_CONFIG.name})")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-resume", action="store_true")
    parser.add_argument("--create-prs", action="store_true")
    parser.add_argument("--timeout", type=int, default=3600)
    args = parser.parse_args(argv)

    config_path = Path(args.config).resolve()
    config = load_config(config_path)
    items = batch_items(config)
    state = load_state(config, config_path, args.no_resume)

    if args.dry_run:
        print("=" * 70)
        print("DRY RUN — no changes will be made")
        print("=" * 70)
        for i, item in enumerate(items, 1):
            name = item["name"]
            item_type = item.get("type", "connector")
            status = " (skip — already processed)" if name in state["completed"] or name in state["failed"] else ""
            print(f"  {i}. {item_type}: {name} → slug: {slugify(name)}{status}")
            if item.get("instructions"):
                print(f"     instructions: \"{item['instructions']}\"")
            if item.get("package"):
                print(f"     package: \"{item['package']}\"")
        print(f"\nDocs branch:    {config['docsBranch']}")
        print(f"Samples branch: {config['samplesBranch']}")
        print(f"Timeout:        {args.timeout}s per item")
        print(f"Total:          {len(items)} items")
        return

    interrupted = False

    def handle_sigint(sig: int, frame: Any) -> None:
        nonlocal interrupted
        interrupted = True
        print("\n[INTERRUPT] Caught Ctrl+C — finishing current item, then exiting...")

    signal.signal(signal.SIGINT, handle_sigint)
    batch_start = time.time()
    print("=" * 70)
    print(f"BATCH RUN — {len(items)} items queued")
    print(f"Docs branch:    {config['docsBranch']}")
    print(f"Samples branch: {config['samplesBranch']}")
    print("=" * 70)

    for i, item in enumerate(items, 1):
        if interrupted:
            break
        name = item["name"]
        if name in state["completed"] or name in state["failed"]:
            print(f"\n[SKIP] {i}/{len(items)}: {name} — already processed")
            continue
        item_type = item.get("type", "connector")
        print(f"\n{'=' * 70}")
        print(f"[{i}/{len(items)}] Processing {item_type}: {name}")
        print("=" * 70)
        state["inProgress"] = name
        save_state(state)

        start = time.time()
        success = run_pipeline_item(
            item_type,
            name,
            item.get("instructions", ""),
            item.get("package", ""),
            args.timeout,
        )
        duration = time.time() - start
        cost_data = parse_run_cost(slugify(name))
        project_path = read_created_project_path()
        status = "OK" if success else "FAILED"
        archive_path = archive_artifacts(slugify(name), status)
        archive_rel = str(archive_path.relative_to(ROOT)) if archive_path else f"artifacts_archive/{slugify(name)}"
        result = {
            "name": name,
            "type": item_type,
            "slug": slugify(name),
            "status": status,
            "duration": duration,
            "cost": cost_data["totalCostUsd"] if cost_data else None,
            "projectPath": project_path,
            "archiveDir": archive_rel,
        }
        state["results"].append(result)
        state["completed" if success else "failed"].append(name)
        state["inProgress"] = None
        save_state(state)
        print(f"\n[{status}] {name} completed in {fmt_duration(duration)}")

    summary_text = print_batch_summary(state["results"], config)
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    summary_path = ARCHIVE_DIR / f"batch_summary_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.txt"
    summary_path.write_text(summary_text, encoding="utf-8")
    print(f"\nSummary saved to: {summary_path.relative_to(ROOT)}")

    if args.create_prs and any(r["status"] == "OK" for r in state["results"]):
        pr_docs(["--branch", config["docsBranch"]])
        pr_samples(["--branch", config["samplesBranch"]])
    sys.exit(1 if any(r["status"] != "OK" for r in state["results"]) else 0)


def commit_docs(argv: Sequence[str]) -> None:
    parser = argparse.ArgumentParser(description="Commit generated docs to a shared batch branch.")
    parser.add_argument("--branch", default="docs/connector-docs")
    parser.add_argument("--docs-repo", default=str(docs.DEFAULT_DOCS_REPO))
    parser.add_argument("--fork", default=None)
    parser.add_argument("--upstream", default=docs.DEFAULT_UPSTREAM)
    parser.add_argument("--base-branch", default=docs.DEFAULT_BASE_BRANCH)
    parser.add_argument("--category")
    parser.add_argument("--artifacts-dir", default="./artifacts")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    artifacts_dir = Path(args.artifacts_dir).resolve()
    docs_repo = Path(args.docs_repo).resolve()
    if args.dry_run:
        print("=" * 79)
        print("DRY RUN — no changes will be made")
        print("=" * 79)
    source_doc_path, doc_content = docs.find_latest_doc(artifacts_dir)
    connector_name, connector_slug, _ = docs.extract_connector_info(doc_content, artifacts_dir)
    screenshot_files = docs.find_screenshots(artifacts_dir)
    docs.validate_docs_repo(docs_repo)
    fork = args.fork or docs.infer_fork(docs_repo)
    docs.info(f"Fork: {fork}  |  Upstream: {args.upstream}  |  Base branch: {args.base_branch}")
    category = docs.detect_category(connector_slug, args.category)
    checkout_or_create_batch_branch(docs_repo, args.branch, args.dry_run, args.upstream, args.base_branch, docs.run, "docs")
    docs.run_claude_code_placement(
        docs_repo,
        category,
        connector_slug,
        connector_name,
        source_doc_path,
        screenshot_files,
        args.dry_run,
    )
    generated_paths = [
        docs_repo / "en" / "docs" / "connectors" / "catalog" / category / connector_slug / "example.md",
        docs_repo / "en" / "static" / "img" / "connectors" / "catalog" / category / connector_slug,
        docs_repo / "en" / "sidebars.ts",
    ]
    docs.commit_and_push(docs_repo, connector_name, args.branch, args.dry_run, generated_paths)
    print(f"\nDone! '{connector_name}' committed to docs branch: {args.branch}")


def commit_sample(argv: Sequence[str]) -> None:
    parser = argparse.ArgumentParser(description="Commit generated sample to a shared batch branch.")
    parser.add_argument("--branch", default="samples/connector-samples")
    parser.add_argument("--samples-repo", default=str(samples.DEFAULT_SAMPLES_REPO))
    parser.add_argument("--upstream", default=samples.DEFAULT_UPSTREAM_REPO)
    parser.add_argument("--base-branch", default=samples.DEFAULT_BASE_BRANCH)
    parser.add_argument("--url", default=f"http://localhost:{samples.DEFAULT_CODE_SERVER_PORT}")
    parser.add_argument("--project-path")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    samples_repo = Path(args.samples_repo).resolve()
    if args.dry_run:
        print("=" * 79)
        print("DRY RUN — no changes will be made")
        print("=" * 79)
    if args.project_path:
        path_file = Path(samples.PROJECT_PATH_FILE)
        if args.dry_run:
            samples.info(f"[dry-run] Would write project path to {samples.PROJECT_PATH_FILE}")
        else:
            path_file.parent.mkdir(parents=True, exist_ok=True)
            path_file.write_text(args.project_path.strip(), encoding="utf-8")
    project = samples.read_project_path()
    if not (samples_repo / ".git").exists():
        fail(f"{samples_repo} is not a git repository.")
    fork = samples.infer_fork(samples_repo)
    actual_project = samples.find_ballerina_project(project)
    project_name = actual_project.name
    samples.info(f"Fork: {fork}  |  Upstream: {args.upstream}  |  Project: {project_name}")
    checkout_or_create_batch_branch(
        samples_repo,
        args.branch,
        args.dry_run,
        args.upstream,
        args.base_branch,
        samples.run,
        "integration-samples",
    )
    samples.patch_ballerina_toml(actual_project, args.dry_run)
    samples.copy_sample(samples_repo, actual_project, project_name, args.dry_run)
    samples.commit_and_push(samples_repo, project_name, args.branch, args.dry_run)
    samples.write_sample_log(project_name, args.dry_run)
    print(f"\nDone! '{project_name}' committed to samples branch: {args.branch}")
    samples.delete_project(project, args.dry_run)
    samples.close_editor_tabs(args.url, args.dry_run)


def pr_docs(argv: Sequence[str]) -> None:
    parser = argparse.ArgumentParser(description="Create a docs PR from a shared batch branch.")
    parser.add_argument("--branch", required=True)
    parser.add_argument("--docs-repo", default=str(docs.DEFAULT_DOCS_REPO))
    parser.add_argument("--fork", default=None)
    parser.add_argument("--upstream", default=docs.DEFAULT_UPSTREAM)
    parser.add_argument("--base-branch", default=docs.DEFAULT_BASE_BRANCH)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    docs_repo = Path(args.docs_repo).resolve()
    docs.validate_docs_repo(docs_repo)
    fork = args.fork or docs.infer_fork(docs_repo)
    checkout_branch(docs_repo, args.branch, args.dry_run)
    names = [] if args.dry_run else read_names_from_branch(
        docs_repo,
        args.base_branch,
        r"docs: add (.+) connector example guide",
        "connector",
        docs.run,
    )
    pr_url = create_batch_pr(
        fork,
        args.upstream,
        args.base_branch,
        args.branch,
        f"docs: adding docs from {args.branch}",
        build_docs_batch_pr_body(names, args.branch),
        args.dry_run,
    )
    print(f"\nDone! PR: {pr_url}")


def pr_samples(argv: Sequence[str]) -> None:
    parser = argparse.ArgumentParser(description="Create a samples PR from a shared batch branch.")
    parser.add_argument("--branch", required=True)
    parser.add_argument("--samples-repo", default=str(samples.DEFAULT_SAMPLES_REPO))
    parser.add_argument("--upstream", default=samples.DEFAULT_UPSTREAM_REPO)
    parser.add_argument("--base-branch", default=samples.DEFAULT_BASE_BRANCH)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    samples_repo = Path(args.samples_repo).resolve()
    if not (samples_repo / ".git").exists():
        fail(f"{samples_repo} is not a git repository.")
    fork = samples.infer_fork(samples_repo)
    checkout_branch(samples_repo, args.branch, args.dry_run)
    names = [] if args.dry_run else read_names_from_branch(
        samples_repo,
        args.base_branch,
        r"samples: add (.+) connector integration sample",
        "sample",
        samples.run,
    )
    pr_url = create_batch_pr(
        fork,
        args.upstream,
        args.base_branch,
        args.branch,
        f"samples: adding samples from {args.branch}",
        build_samples_batch_pr_body(names),
        args.dry_run,
    )
    print(f"\nDone! PR: {pr_url}")


def commit_both(argv: Sequence[str]) -> None:
    parser = argparse.ArgumentParser(description="Commit reviewed generated docs and samples to shared batch branches.")
    parser.add_argument("--docs-branch", default="docs/connector-docs")
    parser.add_argument("--samples-branch", default="samples/connector-samples")
    parser.add_argument("--artifacts-dir", default="./artifacts")
    parser.add_argument("--project-path")
    parser.add_argument("--category")
    parser.add_argument("--docs-repo")
    parser.add_argument("--samples-repo")
    parser.add_argument("--docs-upstream")
    parser.add_argument("--samples-upstream")
    parser.add_argument("--docs-base-branch")
    parser.add_argument("--samples-base-branch")
    parser.add_argument("--url")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    docs_args = ["--branch", args.docs_branch, "--artifacts-dir", args.artifacts_dir]
    if args.category:
        docs_args += ["--category", args.category]
    if args.docs_repo:
        docs_args += ["--docs-repo", args.docs_repo]
    if args.docs_upstream:
        docs_args += ["--upstream", args.docs_upstream]
    if args.docs_base_branch:
        docs_args += ["--base-branch", args.docs_base_branch]
    if args.dry_run:
        docs_args.append("--dry-run")

    sample_args = ["--branch", args.samples_branch]
    if args.project_path:
        sample_args += ["--project-path", args.project_path]
    if args.samples_repo:
        sample_args += ["--samples-repo", args.samples_repo]
    if args.samples_upstream:
        sample_args += ["--upstream", args.samples_upstream]
    if args.samples_base_branch:
        sample_args += ["--base-branch", args.samples_base_branch]
    if args.url:
        sample_args += ["--url", args.url]
    if args.dry_run:
        sample_args.append("--dry-run")

    commit_docs(docs_args)
    commit_sample(sample_args)


def pr_both(argv: Sequence[str]) -> None:
    parser = argparse.ArgumentParser(description="Create docs and sample PRs from shared batch branches.")
    parser.add_argument("--docs-branch", default="docs/connector-docs")
    parser.add_argument("--samples-branch", default="samples/connector-samples")
    parser.add_argument("--docs-repo")
    parser.add_argument("--samples-repo")
    parser.add_argument("--docs-upstream")
    parser.add_argument("--samples-upstream")
    parser.add_argument("--docs-base-branch")
    parser.add_argument("--samples-base-branch")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    docs_args = ["--branch", args.docs_branch]
    if args.docs_repo:
        docs_args += ["--docs-repo", args.docs_repo]
    if args.docs_upstream:
        docs_args += ["--upstream", args.docs_upstream]
    if args.docs_base_branch:
        docs_args += ["--base-branch", args.docs_base_branch]
    if args.dry_run:
        docs_args.append("--dry-run")

    sample_args = ["--branch", args.samples_branch]
    if args.samples_repo:
        sample_args += ["--samples-repo", args.samples_repo]
    if args.samples_upstream:
        sample_args += ["--upstream", args.samples_upstream]
    if args.samples_base_branch:
        sample_args += ["--base-branch", args.samples_base_branch]
    if args.dry_run:
        sample_args.append("--dry-run")

    pr_docs(docs_args)
    pr_samples(sample_args)


COMMANDS = {
    "batch-run": run_batch,
    "commit-docs": commit_docs,
    "commit-sample": commit_sample,
    "commit": commit_both,
    "pr-docs": pr_docs,
    "pr-samples": pr_samples,
    "pr": pr_both,
}


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] in COMMANDS:
        COMMANDS[sys.argv[1]](sys.argv[2:])
        return
    parser = argparse.ArgumentParser(
        description="Unified pipeline command for batch generation, commits, and PRs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Commands:
  batch-run       Run batch connector/trigger generation from JSON
  commit-docs     Commit reviewed docs artifacts to a docs branch
  commit-sample   Commit reviewed sample project to a samples branch
  commit          Commit both docs and sample
  pr-docs         Create a docs PR from a branch
  pr-samples      Create a samples PR from a branch
  pr              Create both docs and sample PRs
""",
    )
    parser.add_argument("command", choices=sorted(COMMANDS))
    parser.parse_args()


if __name__ == "__main__":
    main()
