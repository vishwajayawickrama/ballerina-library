#!/usr/bin/env python3
"""Queue orchestrator for batch trigger documentation generation.

Reads a trigger list from a JSON config file, runs the existing
single-trigger pipeline sequentially for each, archives artifacts
per trigger, and prints a summary with commit instructions.

Usage:
    python batch_run.py --config batch_triggers.json
    python batch_run.py --dry-run
    python batch_run.py --no-resume          # ignore saved state, start fresh
    python batch_run.py --create-prs         # create PRs after all triggers done
    python batch_run.py --timeout 5400       # 90 min per trigger
"""

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
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent  # project root
ARTIFACTS_DIR = ROOT / "artifacts"
ARCHIVE_DIR = ROOT / "artifacts_archive"
STATE_FILE = ROOT / "batch_state.json"
DEFAULT_CONFIG = ROOT / "batch_triggers.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fail(msg: str) -> None:
    print(f"\n[FATAL] {msg}", file=sys.stderr)
    sys.exit(1)


def slugify(name: str) -> str:
    """Mirror the Ballerina slug derivation in main.bal.

    Strips a leading "trigger." prefix and any other dots so that org-qualified
    package names produce dotless, filesystem-friendly slugs that match the
    integration name the WSO2 Integrator UI accepts:
        "trigger.github" → "github"
        "trigger.twilio" → "twilio"
        "kafka"          → "kafka"
    """
    s = name.strip().lower()
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"[^a-z0-9\-.]", "", s)
    s = re.sub(r"^trigger\.", "", s)
    s = s.replace(".", "")
    return s


def config_hash(config: dict) -> str:
    """SHA-256 of the triggers list for change detection."""
    payload = json.dumps(config["triggers"], sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()[:16]


def fmt_duration(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    return f"{m}m {s:02d}s"

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

def load_config(path: Path) -> dict:
    if not path.exists():
        fail(
            f"Config not found: {path}\n"
            f"Copy batch_triggers.json.example to {path.name} and fill it in."
        )
    with open(path) as f:
        data = json.load(f)

    if "triggers" not in data or not isinstance(data["triggers"], list):
        fail(f"Config must have a 'triggers' array.")
    if not data["triggers"]:
        fail("Trigger list is empty.")

    for i, c in enumerate(data["triggers"]):
        if not isinstance(c, dict) or "name" not in c:
            fail(f"triggers[{i}] must be an object with a 'name' field.")

    data.setdefault("docsBranch", "docs/trigger-docs")
    data.setdefault("samplesBranch", "samples/trigger-samples")
    return data

# ---------------------------------------------------------------------------
# State management (resume support)
# ---------------------------------------------------------------------------

def load_state(cfg: dict, cfg_path: Path, no_resume: bool) -> dict:
    empty: dict[str, Any] = {
        "configPath": str(cfg_path),
        "configHash": config_hash(cfg),
        "completed": [],
        "failed": [],
        "inProgress": None,
        "results": [],
    }

    if no_resume or not STATE_FILE.exists():
        return empty

    with open(STATE_FILE) as f:
        state = json.load(f)

    if state.get("configHash") != config_hash(cfg):
        print(
            "[INFO] batch_connectors.json has changed since last run.\n"
            "       Preserving existing completed/failed state and processing new connectors."
        )
        state["configHash"] = config_hash(cfg)
        save_state(state)

    print(f"[INFO] Resuming from saved state ({len(state.get('completed', []))} completed, "
          f"{len(state.get('failed', []))} failed)")
    return state


def save_state(state: dict) -> None:
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

# ---------------------------------------------------------------------------
# Artifact archiving
# ---------------------------------------------------------------------------

def archive_artifacts(slug: str, status: str) -> Path | None:
    """Move artifacts/ to artifacts_archive/{slug}/ (or {slug}_FAILED/)."""
    if not ARTIFACTS_DIR.exists():
        return None

    suffix = "" if status == "OK" else f"_{status}"
    dest = ARCHIVE_DIR / f"{slug}{suffix}"

    # Handle existing archive directory (e.g. from a previous interrupted run)
    if dest.exists():
        ts = datetime.now().strftime("%H%M%S")
        dest = ARCHIVE_DIR / f"{slug}{suffix}_{ts}"

    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    shutil.move(str(ARTIFACTS_DIR), str(dest))
    print(f"[INFO] Archived artifacts to {dest.relative_to(ROOT)}")
    return dest

# ---------------------------------------------------------------------------
# Run-log parsing
# ---------------------------------------------------------------------------

def parse_run_cost(slug: str) -> dict | None:
    """Read the latest run-log JSON for cost/duration data."""
    run_log_dir = ARTIFACTS_DIR / "run-log"
    if not run_log_dir.exists():
        return None

    goal_slug = slug + "-trigger-example"
    logs = sorted(run_log_dir.glob(f"{goal_slug}_*.json"), key=lambda p: p.stat().st_mtime)
    if not logs:
        return None

    with open(logs[-1]) as f:
        data = json.load(f)

    return {
        "totalCostUsd": data.get("totalCombinedCostUsd"),
        "durationSeconds": data.get("durationSeconds"),
    }


def read_created_project_path() -> str | None:
    """Read created-project.txt for the commit instructions."""
    p = ARTIFACTS_DIR / "run-log" / "created-project.txt"
    if p.exists():
        return p.read_text().strip()
    return None

# ---------------------------------------------------------------------------
# Pipeline execution
# ---------------------------------------------------------------------------

def run_pipeline(name: str, package: str, instructions: str, timeout: int) -> bool:
    """Run `make run TRIGGER=<name> [PACKAGE=<pkg>]` and return True on success."""
    cmd = ["make", "run", f"TRIGGER={name}"]
    if package:
        cmd.append(f"PACKAGE={package}")
    if instructions:
        cmd.append(f"ADDITIONAL_INSTRUCTIONS={instructions}")

    print(f"[CMD] {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd,
            cwd=str(ROOT),
            timeout=timeout,
        )
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print(f"[ERROR] Pipeline timed out after {timeout}s")
        return False


def run_make_target(target: str, **kwargs: str) -> bool:
    """Run an arbitrary make target with keyword arguments."""
    cmd = ["make", target]
    for k, v in kwargs.items():
        cmd.append(f"{k}={v}")
    print(f"[CMD] {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(ROOT))
    return result.returncode == 0

# ---------------------------------------------------------------------------
# Summary / instructions
# ---------------------------------------------------------------------------

def print_summary(results: list[dict], config: dict) -> str:
    """Print and return the summary table + commit instructions."""
    lines: list[str] = []

    def out(s: str = "") -> None:
        lines.append(s)
        print(s)

    total_cost = 0.0
    total_duration = 0.0
    ok_count = 0
    fail_count = 0

    out("=" * 70)
    out("BATCH RUN SUMMARY")
    out("=" * 70)
    out(f" {'#':>3}  {'Trigger':<20} {'Status':<10} {'Duration':<12} {'Cost':<10}")
    out(f" {'---':>3}  {'--------------------':<20} {'----------':<10} {'------------':<12} {'----------':<10}")

    for i, r in enumerate(results, 1):
        cost_str = f"${r['cost']:.2f}" if r["cost"] is not None else "n/a"
        dur_str = fmt_duration(r["duration"]) if r["duration"] else "n/a"
        out(f" {i:3d}  {r['name']:<20} {r['status']:<10} {dur_str:<12} {cost_str:<10}")
        if r["cost"] is not None:
            total_cost += r["cost"]
        total_duration += r.get("duration", 0)
        if r["status"] == "OK":
            ok_count += 1
        else:
            fail_count += 1

    out("-" * 70)
    out(f"Total: {len(results)} triggers | {ok_count} OK | {fail_count} failed")
    out(f"Total cost: ${total_cost:.2f}  |  Total time: {fmt_duration(total_duration)}")
    out("=" * 70)

    # Commit instructions for successful connectors
    successful = [r for r in results if r["status"] == "OK"]
    if successful:
        out()
        out("COMMIT INSTRUCTIONS (for approved triggers):")
        out("-" * 70)

        docs_branch = config.get("docsBranch", "docs/trigger-docs")
        samples_branch = config.get("samplesBranch", "samples/trigger-samples")

        for r in successful:
            slug = r["slug"]
            archive_dir = r.get("archiveDir", f"artifacts_archive/{slug}")
            out(f"# {r['name']}")
            out(f"make batch-commit-docs ARTIFACTS_DIR={archive_dir} BRANCH={docs_branch}")
            if r.get("projectPath"):
                out(f"make batch-commit-sample PROJECT_PATH={r['projectPath']} BRANCH={samples_branch}")
            else:
                out(f"# (no created-project.txt found — check {archive_dir}/run-log/)")
            out()

        out("# After reviewing and committing all approved triggers:")
        out(f"make batch-pr-docs BRANCH={docs_branch}")
        out(f"make batch-pr-samples BRANCH={samples_branch}")
        out("=" * 70)

    return "\n".join(lines)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Queue multiple triggers for sequential pipeline execution."
    )
    parser.add_argument(
        "--config",
        default=str(DEFAULT_CONFIG),
        help=f"Path to batch config JSON (default: {DEFAULT_CONFIG.name})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be done without executing",
    )
    parser.add_argument(
        "--no-resume",
        action="store_true",
        help="Ignore existing batch_state.json, start fresh",
    )
    parser.add_argument(
        "--create-prs",
        action="store_true",
        help="Create PRs after all connectors are processed",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=3600,
        help="Max seconds per connector pipeline (default: 3600)",
    )
    parser.add_argument(
        "--per-trigger-cost-cap",
        type=float,
        default=25.0,
        help="Skip remaining triggers if a single trigger costs more than this (USD). "
             "Set to 0 to disable. Default: 25.0",
    )
    parser.add_argument(
        "--total-cost-cap",
        type=float,
        default=150.0,
        help="Stop the batch if cumulative cost exceeds this (USD). "
             "Set to 0 to disable. Default: 150.0",
    )
    args = parser.parse_args()

    cfg_path = Path(args.config).resolve()
    config = load_config(cfg_path)
    connectors = config["triggers"]
    state = load_state(config, cfg_path, args.no_resume)

    # Dry-run mode
    if args.dry_run:
        print("=" * 70)
        print("DRY RUN — no changes will be made")
        print("=" * 70)
        for i, c in enumerate(connectors, 1):
            name = c["name"]
            pkg = c.get("package", f"ballerinax/{name}")
            slug = slugify(name)
            skip = name in state["completed"] or name in state["failed"]
            status = " (skip — already processed)" if skip else ""
            instr = f'  instructions: "{c["instructions"]}"' if c.get("instructions") else ""
            print(f"  {i}. {name} (package: {pkg}) → slug: {slug}{status}")
            if instr:
                print(f"     {instr}")
        print(f"\nDocs branch:    {config['docsBranch']}")
        print(f"Samples branch: {config['samplesBranch']}")
        print(f"Timeout:        {args.timeout}s per trigger")
        print(f"Total:          {len(connectors)} triggers")
        return

    # Set up graceful Ctrl+C handling
    interrupted = False

    def handle_sigint(sig: int, frame: Any) -> None:
        nonlocal interrupted
        interrupted = True
        print("\n[INTERRUPT] Caught Ctrl+C — finishing current connector, then exiting...")

    signal.signal(signal.SIGINT, handle_sigint)

    batch_start = time.time()
    total = len(connectors)
    cumulative_cost = sum(
        r.get("cost") or 0.0 for r in state.get("results", []) if r.get("status") == "OK"
    )

    print("=" * 70)
    print(f"BATCH RUN — {total} triggers queued")
    print(f"Docs branch:    {config['docsBranch']}")
    print(f"Samples branch: {config['samplesBranch']}")
    if args.per_trigger_cost_cap > 0:
        print(f"Per-trigger cost cap: ${args.per_trigger_cost_cap:.2f}")
    if args.total_cost_cap > 0:
        print(f"Total cost cap:       ${args.total_cost_cap:.2f}  (resumed cumulative: ${cumulative_cost:.2f})")
    print("=" * 70)

    for i, c in enumerate(connectors, 1):
        if interrupted:
            print(f"\n[INFO] Stopping queue due to interrupt. {i - 1}/{total} processed.")
            break

        name = c["name"]
        pkg = c.get("package", f"ballerinax/{name}")
        slug = slugify(name)
        instructions = c.get("instructions", "")

        # Skip if already processed
        if name in state["completed"]:
            print(f"\n[SKIP] {i}/{total}: {name} — already completed")
            continue
        if name in state["failed"]:
            print(f"\n[SKIP] {i}/{total}: {name} — previously failed")
            continue

        print(f"\n{'=' * 70}")
        print(f"[{i}/{total}] Processing: {name} (package: {pkg})")
        if instructions:
            print(f"         Instructions: {instructions}")
        print("=" * 70)

        # Update state: in progress
        state["inProgress"] = name
        save_state(state)

        connector_start = time.time()

        # Run pipeline
        success = run_pipeline(name, pkg, instructions, args.timeout)
        connector_duration = time.time() - connector_start

        # Parse cost data
        cost_data = parse_run_cost(slug)
        cost_usd = cost_data["totalCostUsd"] if cost_data else None

        # Read project path before archiving
        project_path = read_created_project_path()

        # Archive artifacts
        status = "OK" if success else "FAILED"
        archive_path = archive_artifacts(slug, status)
        archive_rel = str(archive_path.relative_to(ROOT)) if archive_path else f"artifacts_archive/{slug}"

        # Record result
        result_entry = {
            "name": name,
            "slug": slug,
            "status": status,
            "duration": connector_duration,
            "cost": cost_usd,
            "projectPath": project_path,
            "archiveDir": archive_rel,
        }
        state["results"].append(result_entry)

        if success:
            state["completed"].append(name)
            print(f"\n[OK] {name} completed in {fmt_duration(connector_duration)}")
        else:
            state["failed"].append(name)
            print(f"\n[FAILED] {name} failed after {fmt_duration(connector_duration)}")

        state["inProgress"] = None
        save_state(state)

        # Cost-cap enforcement — stop the batch if a single trigger blew the budget,
        # or if cumulative cost crossed the total cap. This protects the rest of the
        # queue from being silently throttled when one bad run drains the quota.
        if cost_usd is not None:
            cumulative_cost += cost_usd
            if args.per_trigger_cost_cap > 0 and cost_usd > args.per_trigger_cost_cap:
                print(
                    f"\n[ABORT] {name} cost ${cost_usd:.2f} exceeds per-trigger cap "
                    f"${args.per_trigger_cost_cap:.2f}. Stopping batch to protect remaining quota."
                )
                interrupted = True
            elif args.total_cost_cap > 0 and cumulative_cost > args.total_cost_cap:
                print(
                    f"\n[ABORT] Cumulative cost ${cumulative_cost:.2f} exceeds total cap "
                    f"${args.total_cost_cap:.2f}. Stopping batch."
                )
                interrupted = True

    batch_duration = time.time() - batch_start

    # Print summary
    print(f"\n\n")
    summary_text = print_summary(state["results"], config)

    # Save summary to archive
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    summary_path = ARCHIVE_DIR / f"batch_summary_{ts}.txt"
    summary_path.write_text(summary_text)
    print(f"\nSummary saved to: {summary_path.relative_to(ROOT)}")

    # Optionally create PRs
    if args.create_prs:
        successful = [r for r in state["results"] if r["status"] == "OK"]
        if not successful:
            print("\n[WARN] No successful connectors — skipping PR creation.")
        else:
            print("\n[INFO] Creating PRs...")
            run_make_target("batch-pr-docs", BRANCH=config["docsBranch"])
            run_make_target("batch-pr-samples", BRANCH=config["samplesBranch"])

    # Exit code: 1 if any failed, 0 if all OK
    any_failed = any(r["status"] != "OK" for r in state["results"])
    sys.exit(1 if any_failed else 0)


if __name__ == "__main__":
    main()
