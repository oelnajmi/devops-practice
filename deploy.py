#!/usr/bin/env python3

import argparse   # parse command-line flags like --tag main
import subprocess # run shell commands (helm, kubectl) from Python
import sys        # exit with a proper status code if something fails


def run(cmd: list[str]) -> None:
    """Run a shell command and exit if it fails."""
    print(f"$ {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

def ensure_namespace(ns: str) -> None:
    """Create the namespace if it doesn't already exist."""
    yaml_output = subprocess.run(
        ["kubectl", "create", "namespace", ns, "--dry-run=client", "-o", "yaml"],
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(["kubectl", "apply", "-f", "-"], input=yaml_output.stdout, text=True, check=True)

def helm_deploy(release: str, chart_path: str, namespace: str, image_repo: str, tag: str) -> None:
    """
    Install or upgrade the Helm release with the chosen image.
    - release:     the Helm release name (e.g., 'devops-practice')
    - chart_path:  path to your chart (e.g., './charts/devops-practice')
    - namespace:   target namespace (e.g., 'app')
    - image_repo:  container image repo (e.g., 'ghcr.io/oelnajmi/devops-practice')
    - tag:         image tag to deploy (e.g., 'main' or 'sha-abc1234')
    """
    run([
        "helm", "upgrade", "--install", release, chart_path,
        "--namespace", namespace,
        "--set", f"image.repository={image_repo}",
        "--set", f"image.tag={tag}",
    ])

def wait_for_rollout(release: str, namespace: str) -> None:
    """
    Wait until the Deployment associated with this Helm release finishes rolling out.

    - release:   name of the Helm release (usually the same as the Deployment name)
    - namespace: the Kubernetes namespace where it's deployed
    """
    print(f"Waiting for rollout of deployment/{release} in namespace '{namespace}'...")
    run([
        "kubectl", "rollout", "status", f"deploy/{release}", "-n", namespace
    ])
    print("✅ Rollout completed successfully!")

def diagnose_rollout_failure(release: str, namespace: str) -> None:
    """
    Print helpful debugging info if a rollout fails:
    - pods overview (phase, restarts, node)
    - describe the deployment (events, last-state)
    - last few namespace events (time-ordered)
    """
    print("\n🔎 Gathering diagnostics...")

    # 1) Show pods in the namespace (quick state snapshot)
    try:
        run(["kubectl", "get", "pods", "-n", namespace, "-o", "wide"])
    except subprocess.CalledProcessError:
        print("(!) Could not list pods")

    # 2) Describe the specific deployment (reasons, conditions, events)
    try:
        run(["kubectl", "describe", "deploy", release, "-n", namespace])
    except subprocess.CalledProcessError:
        print(f"(!) Could not describe deployment/{release}")

    # 3) Show recent events (sorted by time); print the last ~30 lines
    try:
        ev = subprocess.run(
            ["kubectl", "get", "events", "-n", namespace, "--sort-by=.lastTimestamp"],
            check=False, capture_output=True, text=True
        )
        lines = (ev.stdout or "").strip().splitlines()
        tail = "\n".join(lines[-30:]) if lines else "(no events)"
        print("\n--- Recent events (tail) ---")
        print(tail)
        print("----------------------------\n")
    except Exception as e:
        print(f"(!) Could not fetch events: {e}")

def main() -> None:
    """
    Tiny CLI:
      1) ensure the namespace exists
      2) helm upgrade --install with the chosen image tag
      3) wait for rollout; if it fails, print diagnostics and exit non-zero
    """
    import argparse, sys, subprocess

    p = argparse.ArgumentParser(description="Minimal Helm deploy helper")
    p.add_argument("--tag", required=True, help="Image tag to deploy (e.g., 'main' or 'sha-abc1234')")
    p.add_argument("--image-repo", default="ghcr.io/oelnajmi/devops-practice", help="Container image repo")
    p.add_argument("--release", default="devops-practice", help="Helm release name")
    p.add_argument("--namespace", default="app", help="Kubernetes namespace")
    p.add_argument("--chart", default="./charts/devops-practice", help="Path to the Helm chart")
    args = p.parse_args()

    try:
        ensure_namespace(args.namespace)
        helm_deploy(args.release, args.chart, args.namespace, args.image_repo, args.tag)
        wait_for_rollout(args.release, args.namespace)
        print("\n✅ Deploy finished successfully.")
        print(f"Try port-forward:\n  kubectl port-forward -n {args.namespace} deploy/{args.release} 3000:3000")
    except subprocess.CalledProcessError as e:
        print(f"\n❌ Deploy failed (exit {e.returncode}).", file=sys.stderr)
        diagnose_rollout_failure(args.release, args.namespace)
        sys.exit(e.returncode)

if __name__ == "__main__":
    main()