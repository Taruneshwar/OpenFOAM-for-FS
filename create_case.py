from pathlib import Path
from datetime import datetime
import argparse
import csv
import shutil
import sys

from jinja2 import Environment, FileSystemLoader


# =============================================================================
# Paths
# =============================================================================

ROOT = Path(__file__).parent.resolve()

CONTEXT_DIR = ROOT / "pyFlowPilot" / "context"
GEOMETRY_CSV = CONTEXT_DIR / "geometry.csv"
TEMPLATE_DIR = ROOT / "pyFlowPilot" / "template"
CASES_DIR = ROOT / "drivAerFlowCases"


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
    label_text = Style.apply(f"{label:<24}", Style.BOLD, Style.BLUE)
    print(f"{label_text}: {value}")


def ok(message):
    print(f"{Style.apply('[OK]', Style.BOLD, Style.GREEN)} {message}")


def warn(message):
    print(f"{Style.apply('[WARN]', Style.BOLD, Style.YELLOW)} {message}")


def prompt_text(text):
    return Style.apply(text, Style.BOLD, Style.CYAN)


def format_doe(doe_id):
    return f"doe.{doe_id:03d}"


# =============================================================================
# Context reading
# =============================================================================

def read_geometry_rows():
    rows = []

    with GEOMETRY_CSV.open(newline="") as f:
        reader = csv.DictReader(f)

        for row in reader:
            if not row or not row.get("doe_id"):
                continue

            clean = {
                key.strip(): value.strip()
                for key, value in row.items()
                if key is not None and value is not None
            }

            clean["doe_id"] = int(clean["doe_id"])
            clean["part_id"] = clean["stl_file"]
            clean["patch_name"] = Path(clean["stl_file"]).stem

            rows.append(clean)

    return rows


def get_explicit_doe_ids(rows):
    return sorted(
        {
            row["doe_id"]
            for row in rows
            if row["doe_id"] != -1
        }
    )


def discover_doe_ids(rows):
    doe_ids = get_explicit_doe_ids(rows)

    if not doe_ids:
        return [1]

    return doe_ids


def get_geometry_for_doe(rows, doe_id):
    defaults = {}
    overrides = {}

    for row in rows:
        part_id = row["part_id"]

        if row["doe_id"] == -1:
            defaults[part_id] = row

        elif row["doe_id"] == doe_id:
            overrides[part_id] = row

    geometry = defaults.copy()
    geometry.update(overrides)

    if not geometry:
        raise ValueError(f"No geometry found for doe_id={doe_id}")

    return list(geometry.values())


# =============================================================================
# Simulation note
# =============================================================================

def ask_simulation_note():
    section("Simulation Note")

    print("Add a short note describing the purpose of this simulation set.")
    print("This will be saved once as:")
    print(f"  {Style.apply(CASES_DIR / 'simulation.txt', Style.BOLD)}")
    print()
    print(Style.apply("Press Enter to skip.", Style.DIM))

    note = input(prompt_text("\nSimulation purpose: ")).strip()

    if not note:
        return "No simulation purpose specified."

    return note


def read_context_csv_with_line_numbers(csv_path):
    rows = []

    with csv_path.open(newline="") as f:
        reader = csv.DictReader(f)

        if reader.fieldnames is None:
            return [], []

        fieldnames = [field.strip() for field in reader.fieldnames]

        for line_number, row in enumerate(reader, start=2):
            if not row:
                continue

            clean = {
                key.strip(): value.strip()
                for key, value in row.items()
                if key is not None and value is not None
            }

            if not any(clean.values()):
                continue

            clean["_line_number"] = line_number
            rows.append(clean)

    return fieldnames, rows


def find_doe_column(fieldnames):
    if "doe_id" in fieldnames:
        return "doe_id"

    if "doe" in fieldnames:
        return "doe"

    return None


def collect_doe_addition_lines(selected_doe_ids):
    selected_doe_ids = set(selected_doe_ids)
    additions = []

    for csv_path in sorted(CONTEXT_DIR.glob("*.csv")):
        fieldnames, rows = read_context_csv_with_line_numbers(csv_path)
        doe_column = find_doe_column(fieldnames)

        if doe_column is None:
            continue

        for row in rows:
            raw_doe = row.get(doe_column, "")

            try:
                row_doe = int(raw_doe)
            except ValueError:
                continue

            if row_doe == -1:
                continue

            if row_doe not in selected_doe_ids:
                continue

            row_text_parts = []

            for field in fieldnames:
                row_text_parts.append(f"{field}={row.get(field, '')}")

            additions.append(
                {
                    "file": csv_path.name,
                    "line": row["_line_number"],
                    "doe_id": row_doe,
                    "text": " | ".join(row_text_parts),
                }
            )

    return additions


def write_simulation_note(doe_ids, simulation_note):
    CASES_DIR.mkdir(parents=True, exist_ok=True)

    output_path = CASES_DIR / "simulation.txt"
    additions = collect_doe_addition_lines(doe_ids)

    lines = [
        "PyFlowPilot Simulation Note",
        "=" * LINE_WIDTH,
        "",
        f"Created:        {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"Cases folder:   {CASES_DIR}",
        f"DOE IDs:        {', '.join(format_doe(i) for i in doe_ids)}",
        "",
        "Purpose",
        "-" * LINE_WIDTH,
        simulation_note,
        "",
        "Source Setup",
        "-" * LINE_WIDTH,
        f"Context folder: {CONTEXT_DIR}",
        f"Geometry CSV:   {GEOMETRY_CSV}",
        f"Template:       {TEMPLATE_DIR}",
        "",
        "DOE-specific additions / overrides from context CSV files",
        "-" * LINE_WIDTH,
    ]

    if not additions:
        lines.append("No DOE-specific context rows found for the selected DOE IDs.")
        lines.append("These cases may be using only doe_id = -1 default rows.")
    else:
        current_file = None

        for item in additions:
            if item["file"] != current_file:
                current_file = item["file"]
                lines.append("")
                lines.append(f"[{current_file}]")

            lines.append(
                f"line {item['line']}, doe_id={item['doe_id']}: {item['text']}"
            )

    lines.append("")
    output_path.write_text("\n".join(lines))

    ok(f"Wrote simulation note: {output_path}")


# =============================================================================
# Case setup
# =============================================================================

def case_dir_for_doe(doe_id):
    return CASES_DIR / format_doe(doe_id)


def render_template_tree(case_dir, context):
    env = Environment(
        loader=FileSystemLoader(TEMPLATE_DIR),
        trim_blocks=True,
        lstrip_blocks=True,
    )

    copied_count = 0
    rendered_count = 0

    for src_path in TEMPLATE_DIR.rglob("*"):
        if src_path.is_dir():
            continue

        if src_path.name.endswith(":Zone.Identifier"):
            continue

        rel_path = src_path.relative_to(TEMPLATE_DIR)

        if src_path.suffix == ".j2":
            output_rel_path = rel_path.with_suffix("")
            output_path = case_dir / output_rel_path

            template = env.get_template(rel_path.as_posix())
            rendered = template.render(**context)

            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(rendered)

            rendered_count += 1

        else:
            output_path = case_dir / rel_path
            output_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_path, output_path)

            copied_count += 1

    ok(f"Copied static files:   {copied_count}")
    ok(f"Rendered Jinja files:  {rendered_count}")


def create_stl_symlinks(case_dir, geometry):
    tri_surface_dir = case_dir / "constant" / "triSurface"
    tri_surface_dir.mkdir(parents=True, exist_ok=True)

    linked_count = 0

    for part in geometry:
        stl_file = part["stl_file"]

        source_path = (GEOMETRY_CSV.parent / part["stl_path"]).resolve()
        link_path = tri_surface_dir / stl_file

        if not source_path.exists():
            raise FileNotFoundError(
                f"STL source does not exist:\n{source_path}"
            )

        if link_path.exists() or link_path.is_symlink():
            link_path.unlink()

        link_path.symlink_to(source_path)
        linked_count += 1

    ok(f"Created STL symlinks: {linked_count}")


def create_case(rows, doe_id):
    geometry = get_geometry_for_doe(rows, doe_id)
    case_dir = case_dir_for_doe(doe_id)

    context = {
        "doe_id": doe_id,
        "geometry": geometry,
    }

    section(f"Creating {format_doe(doe_id)}")

    info("Case directory", case_dir)
    info("Geometry parts", len(geometry))

    render_template_tree(case_dir, context)
    create_stl_symlinks(case_dir, geometry)

    ok(f"Finished {format_doe(doe_id)}")


def create_cases(rows, doe_ids, simulation_note):
    title("PyFlowPilot Case Setup")

    info("Cases directory", CASES_DIR)
    info("Template", TEMPLATE_DIR)
    info("Geometry CSV", GEOMETRY_CSV)
    info("DOE IDs", ", ".join(format_doe(i) for i in doe_ids))
    info("Simulation note", simulation_note)

    for doe_id in doe_ids:
        create_case(rows, doe_id)

    write_simulation_note(doe_ids, simulation_note)

    title("Case Setup Complete")


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


def ask_doe_ids(rows):
    explicit_doe_ids = get_explicit_doe_ids(rows)
    suggested_doe_ids = discover_doe_ids(rows)

    section("DOE Selection")

    if explicit_doe_ids:
        info("Detected DOE IDs", ", ".join(str(i) for i in explicit_doe_ids))
        print("Press Enter to use detected DOE IDs, or type your own.")
    else:
        warn("No explicit DOE IDs found in geometry.csv.")
        print("Only doe_id = -1 default geometry rows were detected.")
        print("Press Enter to create doe.001, or type your own DOE IDs.")

    while True:
        raw = input(prompt_text("\nEnter DOE IDs separated by spaces: ")).strip()

        if not raw:
            return suggested_doe_ids

        try:
            doe_ids = [int(item) for item in raw.split()]
        except ValueError:
            warn("Please enter integers only, for example: 1 2 3")
            continue

        if not doe_ids:
            warn("Please enter at least one DOE ID.")
            continue

        if any(doe_id < 0 for doe_id in doe_ids):
            warn("Please enter actual DOE IDs only, not -1.")
            continue

        return doe_ids


def clean_case_folders_for_does(doe_ids):
    section("Clean Existing Cases")

    existing_cases = []

    for doe_id in doe_ids:
        case_dir = case_dir_for_doe(doe_id)

        if case_dir.exists():
            existing_cases.append(case_dir)

    if not existing_cases:
        ok("No existing selected case folders found.")
        return

    print("The following case folders already exist:")

    for case_dir in existing_cases:
        print(f"  - {Style.apply(case_dir, Style.BOLD)}")

    if not ask_yes_no("\nDelete these folders before regenerating?", default=False):
        warn("Clean skipped.")
        return

    for case_dir in existing_cases:
        shutil.rmtree(case_dir)
        ok(f"Deleted: {case_dir}")


def interactive_case_setup():
    title("PyFlowPilot - caseSetup")

    rows = read_geometry_rows()
    doe_ids = ask_doe_ids(rows)
    simulation_note = ask_simulation_note()

    section("Setup Options")

    clean_existing = ask_yes_no(
        "Clean selected existing case folders before setup?",
        default=False,
    )

    section("Setup Summary")

    info("Geometry context", GEOMETRY_CSV)
    info("Template folder", TEMPLATE_DIR)
    info("Cases folder", CASES_DIR)
    info("DOE IDs", ", ".join(format_doe(i) for i in doe_ids))
    info("Simulation note", simulation_note)
    info("Clean existing", clean_existing)

    print()

    if not ask_yes_no("Proceed with case setup?", default=True):
        warn("caseSetup cancelled.")
        return

    if clean_existing:
        clean_case_folders_for_does(doe_ids)

    create_cases(rows, doe_ids, simulation_note)


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="PyFlowPilot external aerodynamics case setup tool"
    )

    parser.add_argument(
        "doe_ids",
        nargs="*",
        type=int,
        help="DOE IDs to create directly. Example: python3 create_case.py 1 2",
    )

    parser.add_argument(
        "--note",
        default="No simulation purpose specified.",
        help="Simulation purpose note saved to drivAerFlowCases/simulation.txt.",
    )

    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored console output.",
    )

    args = parser.parse_args()

    if args.no_color:
        Style.USE_COLOR = False

    if args.doe_ids:
        rows = read_geometry_rows()
        create_cases(rows, args.doe_ids, args.note)
        return

    interactive_case_setup()


if __name__ == "__main__":
    main()
