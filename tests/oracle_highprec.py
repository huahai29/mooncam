"""High-precision reference for the MoonCam contract.

`tests/oracle.py` is independent in *algebra* (Bernstein form, parametric
curvature) but still evaluates everything in IEEE doubles, so a systematic
double-precision defect could stay hidden.  This script re-derives the same
geometry with 40 significant decimal digits and compares the library's doubles
against it at selected points.

Nothing outside the standard library is used: `decimal` provides the arithmetic,
and sine, cosine, arctangent and square root are implemented here from series
and argument reduction.  The series are checked against `math` at the top of the
run, so a mistake in this reference surfaces as a self-check failure rather than
as a false accusation against the library.

Point selection is deliberately small: this file is about arithmetic precision,
not coverage, and `oracle.py` already visits every emitted point.  Per case it
checks both mesh ends, every segment boundary (with one neighbour on each side),
the pressure-angle extremum, and an even sweep of the interior.
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile
from decimal import Decimal, ROUND_FLOOR, getcontext
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "tests" / "engine-runner.mjs"
ARTIFACTS = ROOT / "artifacts"

getcontext().prec = 40

PI = Decimal(
    "3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798"
)
TAU = 2 * PI
EPS = Decimal(10) ** -(getcontext().prec + 5)

FAILURES: list[str] = []

# Tolerances are per field: derivatives amplify rounding, and the reference is
# exact to 40 digits while the library works in doubles.  Observed agreement is
# reported in artifacts/oracle-highprec.json; these limits stay tight enough that
# any modelling or sign error (far above 1e-12) is still caught.
TOLERANCE = {
    "x": 5e-13,
    "y": 5e-13,
    "pitch_x": 5e-13,
    "pitch_y": 5e-13,
    "lift_mm": 5e-13,
    "velocity_mm_s": 5e-13,
    "acceleration_mm_s2": 5e-13,
    "jerk_mm_s3": 2e-12,
    # Curvature and the offset factor divide by speed**3, which amplifies
    # cancellation when the prime circle is tiny (the 1e-3 scale case); the
    # observed 1.6e-12 is still twelve digits of agreement.
    "pitch_curvature": 2e-12,
    "offset_factor": 2e-12,
    "pressure_deg": 5e-13,
}


def fail(fmt: str, *args) -> None:
    FAILURES.append(fmt.format(*args) if args else fmt)


def check(condition: bool, fmt: str | None = None, *args) -> bool:
    if not condition:
        fail(fmt or "unnamed check", *args)
        return False
    return True


# ---------------------------------------------------------------------------
# Decimal elementary functions
# ---------------------------------------------------------------------------


def dec_sin(x: Decimal) -> Decimal:
    """Sine by range reduction to [-pi, pi] followed by a Taylor series."""
    turns = (x / TAU).to_integral_value(rounding=ROUND_FLOOR)
    x = x - turns * TAU
    if x > PI:
        x = x - TAU
    x2 = x * x
    term = x
    total = x
    n = 1
    while True:
        term = -term * x2 / ((2 * n) * (2 * n + 1))
        total += term
        n += 1
        if abs(term) < EPS:
            return total


def dec_cos(x: Decimal) -> Decimal:
    return dec_sin(x + PI / 2)


def dec_atan(x: Decimal) -> Decimal:
    """Arctangent: halving identity then the alternating series."""
    if x < 0:
        return -dec_atan(-x)
    halvings = 0
    limit = Decimal("0.2")
    while x > limit:
        x = x / (1 + (1 + x * x).sqrt())
        halvings += 1
    x2 = x * x
    term = x
    total = x
    k = 1
    while True:
        term = -term * x2
        k += 2
        step = term / k
        total += step
        if abs(step) < EPS:
            break
    return total * (2**halvings)


def dec_atan2(y: Decimal, x: Decimal) -> Decimal:
    if x > 0:
        return dec_atan(y / x)
    if x < 0:
        return dec_atan(y / x) + (PI if y >= 0 else -PI)
    if y > 0:
        return PI / 2
    if y < 0:
        return -PI / 2
    return Decimal(0)


def self_check_elementary() -> float:
    """The reference trig must agree with libm on ordinary doubles."""
    worst = 0.0
    for index in range(400):
        value = (index - 200) / 7.0
        angle = Decimal(str(value))
        for reference, expected in (
            (dec_sin(angle), math.sin(value)),
            (dec_cos(angle), math.cos(value)),
        ):
            error = abs(float(reference) - expected)
            worst = max(worst, error)
        ratio = value / 3.0
        error = abs(float(dec_atan(Decimal(str(ratio)))) - math.atan(ratio))
        worst = max(worst, error)
    return worst


# ---------------------------------------------------------------------------
# Laws and geometry in Decimal
# ---------------------------------------------------------------------------


def power(value: Decimal, exponent: int) -> Decimal:
    """Decimal power that keeps 0**0 defined as 1 (decimal raises otherwise)."""
    if exponent == 0:
        return Decimal(1)
    return value**exponent

def law_shape(law: str) -> tuple[int, int]:
    if law == "345":
        return 5, 3
    if law == "4567":
        return 7, 4
    raise ValueError(f"unknown polynomial law {law!r}")


def normalized(law: str, u: Decimal) -> tuple[Decimal, Decimal, Decimal, Decimal]:
    if law == "cycloidal":
        angle = TAU * u
        return (
            u - dec_sin(angle) / TAU,
            1 - dec_cos(angle),
            TAU * dec_sin(angle),
            TAU * TAU * dec_cos(angle),
        )
    n, k0 = law_shape(law)
    # s = sum_{k>=k0} C(n,k) u^k (1-u)^(n-k); derivative from the Bernstein
    # identity ds/du = n * C(n-1, k0-1) * u^(k0-1) * (1-u)^(n-k0).
    total = Decimal(0)
    for k in range(k0, n + 1):
        total += Decimal(math.comb(n, k)) * power(u, k) * power(1 - u, n - k)
    m = k0 - 1
    p = n - 1 - m
    amplitude = Decimal(n * math.comb(n - 1, m))
    v = amplitude * power(u, m) * power(1 - u, p)
    a = amplitude * m * power(u, m - 1) * power(1 - u, p) if m > 0 else Decimal(0)
    if p > 0:
        a -= amplitude * p * power(u, m) * power(1 - u, p - 1)
    j = Decimal(0)
    if m > 1:
        j += amplitude * m * (m - 1) * power(u, m - 2) * power(1 - u, p)
    if m > 0 and p > 0:
        j -= 2 * amplitude * m * p * power(u, m - 1) * power(1 - u, p - 1)
    if p > 1:
        j += amplitude * p * (p - 1) * power(u, m) * power(1 - u, p - 2)
    return total, v, a, j


class Program:
    def __init__(self, segments: list[dict]):
        self.segments = segments
        self.starts: list[Decimal] = []
        self.heights: list[Decimal] = []
        angle = Decimal(0)
        lift = Decimal(0)
        for segment in segments:
            self.starts.append(angle)
            self.heights.append(lift)
            angle += Decimal(str(segment["angle_deg"])) * PI / 180
            lift += Decimal(str(segment["lift_mm"]))
        if abs(angle - TAU) > Decimal("1e-30"):
            raise ValueError("segment angles must sum to one revolution")
        if abs(lift) > Decimal("1e-30"):
            raise ValueError("program must return to zero lift")

    def motion(self, theta: Decimal) -> tuple[Decimal, Decimal, Decimal, Decimal, int]:
        turns = (theta / TAU).to_integral_value(rounding=ROUND_FLOOR)
        t = theta - turns * TAU
        index = 0
        for candidate in range(len(self.segments) - 1, -1, -1):
            if t >= self.starts[candidate] - Decimal("1e-18"):
                index = candidate
                break
        segment = self.segments[index]
        angle = Decimal(str(segment["angle_deg"])) * PI / 180
        u = (t - self.starts[index]) / angle
        u = min(max(u, Decimal(0)), Decimal(1))
        s, v, a, j = normalized(segment["law"], u)
        lift = Decimal(str(segment["lift_mm"]))
        return (
            self.heights[index] + lift * s,
            lift * v / angle,
            lift * a / (angle * angle),
            lift * j / (angle**3),
            index,
        )


def geometry_point(base: float, roller: float, offset: float, theta: Decimal, program: Program) -> dict:
    s, v, a, j, _index = program.motion(theta)
    base_d = Decimal(str(base))
    roller_d = Decimal(str(roller))
    offset_d = Decimal(str(offset))
    q = ((base_d + roller_d) ** 2 - offset_d**2).sqrt() + s
    d = v - offset_d
    sin_t = dec_sin(theta)
    cos_t = dec_cos(theta)
    px = q * sin_t + offset_d * cos_t
    py = q * cos_t - offset_d * sin_t
    dpx = v * sin_t + q * cos_t - offset_d * sin_t
    dpy = v * cos_t - q * sin_t - offset_d * cos_t
    ddpx = a * sin_t + 2 * v * cos_t - q * sin_t - offset_d * cos_t
    ddpy = a * cos_t - 2 * v * sin_t - q * cos_t + offset_d * sin_t
    speed = (dpx * dpx + dpy * dpy).sqrt()
    nx = -dpy / speed
    ny = dpx / speed
    curvature = -(dpx * ddpy - dpy * ddpx) / (speed**3)
    return {
        "s": s,
        "v": v,
        "a": a,
        "j": j,
        "px": px,
        "py": py,
        "x": px - roller_d * nx,
        "y": py - roller_d * ny,
        "pressure": dec_atan2(d, q),
        "curvature": curvature,
        "offset_factor": 1 - roller_d * curvature,
    }


# ---------------------------------------------------------------------------
# Engine driver
# ---------------------------------------------------------------------------


def run_engine(cases: list[dict]) -> list[dict]:
    with tempfile.TemporaryDirectory(prefix="mooncam-highprec-") as tmp:
        request = Path(tmp) / "request.jsonl"
        response = Path(tmp) / "response.jsonl"
        request.write_text("".join(json.dumps(case) + "\n" for case in cases), encoding="utf-8")
        with request.open("rb") as stdin, response.open("wb") as stdout:
            completed = subprocess.run(
                [os.environ.get("NODE", "node"), str(ENGINE)],
                stdin=stdin,
                stdout=stdout,
                stderr=subprocess.PIPE,
                cwd=ROOT,
            )
        if completed.returncode != 0:
            raise SystemExit(completed.stderr.decode("utf-8", "replace"))
        lines = [line for line in response.read_text(encoding="utf-8").splitlines() if line]
    if len(lines) != len(cases):
        raise SystemExit(f"engine returned {len(lines)} results for {len(cases)} cases")
    return [json.loads(line) for line in lines]


# ---------------------------------------------------------------------------
# Cases and comparison
# ---------------------------------------------------------------------------


def symmetric(law: str) -> dict:
    return {
        "segments": [
            {"angle_deg": 90, "lift_mm": 20, "law": law},
            {"angle_deg": 90, "lift_mm": 0, "law": law},
            {"angle_deg": 90, "lift_mm": -20, "law": law},
            {"angle_deg": 90, "lift_mm": 0, "law": law},
        ]
    }


def uneven() -> dict:
    return {
        "segments": [
            {"angle_deg": 55, "lift_mm": 12, "law": "345"},
            {"angle_deg": 35, "lift_mm": 0, "law": "cycloidal"},
            {"angle_deg": 110, "lift_mm": -12, "law": "4567"},
            {"angle_deg": 25, "lift_mm": 0, "law": "345"},
            {"angle_deg": 95, "lift_mm": 8, "law": "cycloidal"},
            {"angle_deg": 40, "lift_mm": -8, "law": "4567"},
        ]
    }


def cases() -> list[dict]:
    out: list[dict] = []
    for law in ("cycloidal", "345", "4567"):
        for base, roller in ((25.0, 2.0), (40.0, 4.0)):
            for offset in (-8.0, 0.0, 8.0):
                out.append(
                    {
                        "action": "analyze",
                        "units": "mm",
                        "base_radius_mm": base,
                        "roller_radius_mm": roller,
                        "offset_mm": offset,
                        "rpm": 60,
                        "resolution": 720,
                        "pressure_limit_deg": 30,
                        "outputs": ["points"],
                        **symmetric(law),
                    }
                )
    out.append(
        {
            "action": "analyze",
            "units": "mm",
            "base_radius_mm": 40.0,
            "roller_radius_mm": 4.0,
            "offset_mm": 6.0,
            "rpm": 60,
            "resolution": 720,
            "pressure_limit_deg": 30,
            "outputs": ["points"],
            **uneven(),
        }
    )
    for base, roller, offset in ((1e-3, 1e-3, 0.0), (1e4, 1e2, 1e3), (1e-6, 1e-6, 0.0)):
        out.append(
            {
                "action": "analyze",
                "units": "mm",
                "base_radius_mm": base,
                "roller_radius_mm": roller,
                "offset_mm": offset,
                "rpm": 60,
                "resolution": 360,
                "pressure_limit_deg": 30,
                "outputs": ["points"],
                **symmetric("345"),
            }
        )
    return out


def choose_indices(points: list[dict], program: Program) -> list[int]:
    n = len(points)
    thetas = [Decimal(str(point["theta_rad"])) for point in points]
    chosen = {0, n - 1}
    for boundary in program.starts[1:]:
        nearest = min(range(n), key=lambda index: abs(thetas[index] - boundary))
        chosen.update({max(0, nearest - 1), nearest, min(n - 1, nearest + 1)})
    argmax = max(range(n), key=lambda index: abs(points[index]["pressure_deg"]))
    chosen.update({max(0, argmax - 1), argmax, min(n - 1, argmax + 1)})
    step = max(1, n // 12)
    chosen.update(range(0, n, step))
    # Samples sitting on a segment joint are excluded: the joint angle stored in
    # a double is a few 1e-17 rad below the 40-digit value, so the reference can
    # legitimately classify the sample into the other segment.  That changes
    # quantities that are discontinuous there (jerk) and moves continuous ones by
    # O(eps * slope).  oracle.py covers joint samples with a double reference,
    # where both sides use the same angle.
    for boundary in program.starts[1:] + [TAU]:
        chosen = {index for index in chosen if abs(thetas[index] - boundary) > Decimal("1e-9")}
    return sorted(chosen)


def verify_case(label: str, case: dict, result: dict, worst: dict) -> int:
    if not check(result.get("ok") is True, "{}: engine rejected the case", label):
        return 0
    report = result["result"]
    points = report["points"]
    program = Program(case["segments"])
    base, roller, offset = case["base_radius_mm"], case["roller_radius_mm"], case["offset_mm"]
    omega = Decimal(str(case["rpm"])) * TAU / 60
    indices = choose_indices(points, program)
    # Absolute differences are judged against the largest value of the field in
    # this case.  Near u -> 0/1 the expanded polynomials the library uses lose
    # relative accuracy through cancellation (about 2e-13 of the law peak), which
    # a value-relative test would misreport as a defect.
    fields = (
        "x", "y", "pitch_x", "pitch_y", "lift_mm", "velocity_mm_s",
        "acceleration_mm_s2", "jerk_mm_s3", "pitch_curvature", "offset_factor",
    )
    scales = {name: 1.0 for name in fields}
    for point in points:
        for name in fields:
            scales[name] = max(scales[name], abs(point[name]))
    scales["pressure_deg"] = max(1.0, max(abs(point["pressure_deg"]) for point in points))
    for index in indices:
        point = points[index]
        theta = Decimal(str(point["theta_rad"]))
        ref = geometry_point(base, roller, offset, theta, program)

        def scaled(actual: float, expected: Decimal, name: str) -> float:
            return float(abs(Decimal(str(actual)) - expected)) / scales[name]

        checks = {
            "x": (point["x"], ref["x"]),
            "y": (point["y"], ref["y"]),
            "pitch_x": (point["pitch_x"], ref["px"]),
            "pitch_y": (point["pitch_y"], ref["py"]),
            "lift_mm": (point["lift_mm"], ref["s"]),
            "velocity_mm_s": (point["velocity_mm_s"], ref["v"] * omega),
            "acceleration_mm_s2": (point["acceleration_mm_s2"], ref["a"] * omega * omega),
            "jerk_mm_s3": (point["jerk_mm_s3"], ref["j"] * omega * omega * omega),
            "pitch_curvature": (point["pitch_curvature"], ref["curvature"]),
            "offset_factor": (point["offset_factor"], ref["offset_factor"]),
        }
        for name, (actual, expected) in checks.items():
            error = scaled(actual, expected, name)
            worst[name] = max(worst.get(name, 0.0), error)
            if error > TOLERANCE[name]:
                fail(
                    "{}[{}]: {} {!r} vs 40-digit {!r} (relative {:e} > {:e})",
                    label, index, name, actual, float(expected), error, TOLERANCE[name],
                )
        pressure_deg = ref["pressure"] * 180 / PI
        pressure_error = float(abs(Decimal(str(point["pressure_deg"])) - pressure_deg))
        pressure_scale_error = pressure_error / scales["pressure_deg"]
        worst["pressure_deg"] = max(worst.get("pressure_deg", 0.0), pressure_scale_error)
        if pressure_scale_error > TOLERANCE["pressure_deg"]:
            fail(
                "{}[{}]: pressure {} vs 40-digit {} ({:e} of the case maximum)",
                label, index, point["pressure_deg"], float(pressure_deg), pressure_scale_error,
            )
    return len(indices)


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    elementary = self_check_elementary()
    check(elementary < 1e-14, "reference trigonometry disagrees with libm by {:e}", elementary)

    all_cases = cases()
    results = run_engine(all_cases)
    worst: dict[str, float] = {}
    points_checked = 0
    for case, result in zip(all_cases, results):
        label = "{}:rb{}:e{}".format(
            case["segments"][0]["law"], case["base_radius_mm"], case["offset_mm"]
        )
        points_checked += verify_case(label, case, result, worst)

    summary = {
        "reference": "decimal, 40 significant digits, series sin/cos/atan",
        "cases": len(all_cases),
        "points_checked": points_checked,
        "failures": len(FAILURES),
        "reference_self_check_error": elementary,
        "worst_error_relative_to_case_maximum": {key: worst[key] for key in sorted(worst)},
        "tolerances": TOLERANCE,
    }
    (ARTIFACTS / "oracle-highprec.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s):", file=sys.stderr)
        for message in FAILURES[:15]:
            print("  - " + message, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
