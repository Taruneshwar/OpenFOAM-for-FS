from pathlib import Path
import argparse
import subprocess
import sys


# =============================================================================
# Paths
# =============================================================================

CASE_DIR = Path(__file__).parent.resolve()
BASH_DIR = CASE_DIR / "scripts" / "bashJobs"


# =============================================================================
# Run configuration
# =============================================================================

"""
Edit these script names to match your actual bash files.

The idea is:

local mode:
    preMesh      -> local-compatible pre-mesh script
    mesh         -> local meshing script
    solve        -> local solver script
    postProcess  -> local post-processing script

cluster mode:
    preMesh      -> cluster-compatible pre-mesh script
    mesh         -> cluster meshing/job script
    solve        -> cluster solver/job script
    postProcess  -> cluster post-processing/job script
"""

RUN_CONFIG = {
    "local": {
        "preMesh": "scripts/bashJobs/_preMesh.sh",
        "mesh": "scripts/bashJobs/11_mesh_local.sh",
        "solve": "scripts/bashJobs/2_solve_local.sh",
        "postProcess": "scripts/bashJobs/3_postProcess_local.sh",
    },
    "cluster": {
        "preMesh": "scripts/bashJobs/_preMesh.sh",
        "mesh": "scripts/bashJobs/1_mesh.sh",
        "solve": "scripts/bashJobs/2_solve_cluster.sh",
        "postProcess": "scripts/bashJobs/3_postProcess_cluster.sh",
    },
}

RUN_STEP_ORDER = [
    "preMesh",
    "mesh",
    "solve",
    "postProcess",
]


# =============================================================================
# Console formatting
# =============================================================================

LINE_WIDTH = 80


class Style:
    USE_COLOR = sys.stdout.isatty()

    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"

    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"

    @classmethod
    def apply(cls, text, *styles):
        if not cls.USE_COLOR:
            return str(text)

        return "".join(styles) + str(text) + cls.RESET


def line(char="="):
    print(Style.apply(char * LINE_WIDTH, Style.DIM))


def title(text):
    print()
    line("=")
    print(Style.apply(text.center(LINE_WIDTH), Style.BOLD, Style.CYAN))
    line("=")


def section(text):
    print()
    print(Style.apply(text, Style.BOLD, Style.MAGENTA))
    line("-")


def info(label, value):
    label_text = Style.apply(f"{label:<20}", Style.BOLD, Style.BLUE)
    print(f"{label_text}: {value}")


def ok(message):
    print(f"{Style.apply('[OK]', Style.BOLD, Style.GREEN)} {message}")


def warn(message):
    print(f"{Style.apply('[WARN]', Style.BOLD, Style.YELLOW)} {message}")


def fail(message):
    print(f"{Style.apply('[ERROR]', Style.BOLD, Style.RED)} {message}")


def prompt_text(text):
    return Style.apply(text, Style.BOLD, Style.CYAN)


# =============================================================================
# Interactive helpers
# =============================================================================

def ask_yes_no(question, default=True):
    default_text = "Y/n" if default else "y/N"

    while True:
        answer = input(prompt_text(f"{question} [{default_text}]: ")).strip().lower()

        if not answer:
            return default

        if answer in ["y", "yes"]:
            return True

        if answer in ["n", "no"]:
            return False

        warn("Please enter y or n.")


def ask_run_mode():
    section("Select Run Mode")

    modes = ["local", "cluster"]

    for index, mode in enumerate(modes, start=1):
        print(f"[{index}] {mode}")

    while True:
        raw = input(prompt_text("\nRun mode: ")).strip()

        try:
            index = int(raw)
            return modes[index - 1]
        except (ValueError, IndexError):
            warn("Please select 1 or 2.")


def ask_run_steps():
    section("Select Run Steps")

    for index, step in enumerate(RUN_STEP_ORDER, start=1):
        print(f"[{index}] {step}")

    print()
    print("Type step numbers separated by spaces, for example: 1 2")
    print("Type all to select all steps.")

    while True:
        raw = input(prompt_text("\nRun steps: ")).strip().lower()

        if raw == "all":
            return RUN_STEP_ORDER.copy()

        try:
            indexes = [int(item) for item in raw.split()]
            selected_steps = [RUN_STEP_ORDER[index - 1] for index in indexes]
        except (ValueError, IndexError):
            warn("Invalid selection. Use numbers like 1 2, or type all.")
            continue

        if not selected_steps:
            warn("Select at least one run step.")
            continue

        # Keep the selected steps in the standard pipeline order
        selected_step_set = set(selected_steps)
        ordered_steps = [
            step
            for step in RUN_STEP_ORDER
            if step in selected_step_set
        ]

        return ordered_steps


# =============================================================================
# Run logic
# =============================================================================

def get_script_for_step(run_mode, step):
    return RUN_CONFIG[run_mode][step]


def check_selected_scripts_exist(run_mode, selected_steps):
    missing = []

    for step in selected_steps:
        script_rel = get_script_for_step(run_mode, step)
        script_path = CASE_DIR / script_rel

        if not script_path.exists():
            missing.append((step, script_rel, script_path))

    if not missing:
        return True

    section("Missing Bash Scripts")

    for step, script_rel, script_path in missing:
        fail(f"{step}: {script_rel}")
        print(f"      expected at: {script_path}")

    print()
    warn("One or more selected scripts do not exist.")
    warn("Create the missing bash files or edit RUN_CONFIG in run_case.py.")

    return False


def preview_run(run_mode, selected_steps):
    section("Run Preview")

    info("Case directory", CASE_DIR)
    info("Run mode", run_mode)

    print()
    print("Selected commands:")

    for step in selected_steps:
        script_rel = get_script_for_step(run_mode, step)
        print(f"  {Style.apply(step, Style.BOLD):<20} -> bash {script_rel}")


def run_step(run_mode, step):
    script_rel = get_script_for_step(run_mode, step)
    script_path = CASE_DIR / script_rel

    section(f"Running {step}")

    info("Mode", run_mode)
    info("Script", script_rel)

    subprocess.run(
        ["bash", str(script_path)],
        cwd=CASE_DIR,
        check=True,
    )


def run_case_interactive():
    title(f"PyFlowPilot Case Runner - {CASE_DIR.name}")

    run_mode = ask_run_mode()
    selected_steps = ask_run_steps()

    if not check_selected_scripts_exist(run_mode, selected_steps):
        return

    preview_run(run_mode, selected_steps)

    print()
    if not ask_yes_no("Proceed with selected run steps?", default=True):
        warn("Run cancelled.")
        return

    for step in selected_steps:
        run_step(run_mode, step)

    title("Selected Run Steps Complete")


# =============================================================================
# CLI mode
# =============================================================================

def run_case_from_args(args):
    run_mode = args.mode
    selected_steps = args.steps

    if not selected_steps:
        selected_steps = RUN_STEP_ORDER.copy()

    if not check_selected_scripts_exist(run_mode, selected_steps):
        return

    preview_run(run_mode, selected_steps)

    if not args.yes:
        print()
        if not ask_yes_no("Proceed with selected run steps?", default=True):
            warn("Run cancelled.")
            return

    for step in selected_steps:
        run_step(run_mode, step)

    title("Selected Run Steps Complete")


def main():
    parser = argparse.ArgumentParser(
        description="Run selected OpenFOAM steps inside this DOE case."
    )

    parser.add_argument(
        "--mode",
        choices=["local", "cluster"],
        help="Run mode. If omitted, interactive mode is used.",
    )

    parser.add_argument(
        "--steps",
        nargs="*",
        choices=RUN_STEP_ORDER,
        help="Run steps to execute. Example: --steps preMesh mesh",
    )

    parser.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="Skip confirmation prompt.",
    )

    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored console output.",
    )

    args = parser.parse_args()

    if args.no_color:
        Style.USE_COLOR = False

    if args.mode:
        run_case_from_args(args)
    else:
        run_case_interactive()


if __name__ == "__main__":
    main()
