"""Independent numerical oracle for the MoonCam JSON contract.

Reference implementation notes
------------------------------
* Polynomial laws are evaluated from the Bernstein (binomial-tail) form and
  differentiated through the product rule on ``u**m * (1-u)**p``.  The library
  uses expanded power polynomials; the two routes share no algebra.
* Pitch-curve curvature is derived from the parametric route ``(px'', py'')``
  instead of the closed-form envelope expression ``(q(q-a)+d(2v-e))/speed**3``
  used by the library.  The reference also compares both of its own routes and
  the published law peak coefficients, so a defect in the reference itself is
  visible instead of silently cancelling a library defect.
* Every emitted point is checked, including segment boundaries and the
  periodic endpoint.  The previous version skipped a window around segment
  boundaries, which is exactly where indexing and continuity defects live.
* The sampled mesh is not reconstructed from a formula: the reference advances
  through the angles the engine actually reports.  Structural properties
  (monotone angles, closure, boundary coverage, interval budget) are checked
  separately, so a one-ulp difference in degree-to-radian conversion cannot
  turn a value check into a false failure.
* Headline metrics use a two-sided band instead of a bare tolerance.  The
  reported maximum is a sample of the same continuous function, so it can
  never exceed an upper bound built from a much finer grid, and it cannot fall
  below it by more than ``L*h/2``, with ``L = max|d(alpha)/d(theta)|`` and ``h``
  the widest actual sample spacing.  The measured deficit feeds a convergence
  table.
* Export artefacts (CSV, DXF, SVG) are parsed back and checked against the same
  reference points, so the export path is covered and not just the kernel.

Only the Python standard library is used.  The engine is driven through files
instead of pipes so the script also runs in sandboxes that deny pipe creation
to child processes.
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "tests" / "engine-runner.mjs"
ARTIFACTS = ROOT / "artifacts"
TAU = 2.0 * math.pi

FAILURES: list[str] = []
FAILURE_COUNT = 0
MAX_STORED_FAILURES = 200
CHECKS = 0


def fail(fmt: str, *args) -> None:
    global FAILURE_COUNT
    FAILURE_COUNT += 1
    if len(FAILURES) < MAX_STORED_FAILURES:
        FAILURES.append(fmt.format(*args) if args else fmt)


def check(condition: bool, fmt: str | None = None, *args) -> bool:
    """Check a condition; the message is formatted only when it fails."""
    global CHECKS
    CHECKS += 1
    if not condition:
        fail(fmt or "unnamed check", *args)
        return False
    return True


# ---------------------------------------------------------------------------
# Motion laws: independent Bernstein formulation
# ---------------------------------------------------------------------------


def law_shape(law: str) -> tuple[int, int]:
    if law == "345":
        return 5, 3
    if law == "4567":
        return 7, 4
    raise ValueError(f"unknown polynomial law {law!r}")


def product_derivatives(amplitude: float, m: int, p: int, u: float) -> tuple[float, float, float]:
    """f, f', f'' for f(u) = amplitude * u**m * (1-u)**p."""
    terms = [(amplitude, m, p)]
    out: list[float] = []
    for order in range(3):
        if order:
            following: list[tuple[float, int, int]] = []
            for coefficient, a, b in terms:
                if a > 0:
                    following.append((coefficient * a, a - 1, b))
                if b > 0:
                    following.append((-coefficient * b, a, b - 1))
            terms = following
        value = 0.0
        for coefficient, a, b in terms:
            value += coefficient * (u**a) * ((1.0 - u) ** b)
        out.append(value)
    return out[0], out[1], out[2]


def normalized(law: str, u: float) -> tuple[float, float, float, float]:
    """Normalized lift and its first three derivatives at phase u."""
    if law == "cycloidal":
        return (
            u - math.sin(TAU * u) / TAU,
            1.0 - math.cos(TAU * u),
            TAU * math.sin(TAU * u),
            TAU * TAU * math.cos(TAU * u),
        )
    n, k0 = law_shape(law)
    # s = sum_{k>=k0} C(n,k) u^k (1-u)^(n-k)
    s = sum(math.comb(n, k) * u**k * (1.0 - u) ** (n - k) for k in range(k0, n + 1))
    # ds/du = n * C(n-1, k0-1) u^(k0-1) (1-u)^(n-k0)
    m = k0 - 1
    p = n - 1 - m
    amplitude = n * math.comb(n - 1, m)
    v, a, j = product_derivatives(amplitude, m, p, u)
    return s, v, a, j


# Peak coefficients of the normalized laws.  Cycloidal and 3-4-5 are closed
# forms; 4-5-6-7 has interior peaks whose values follow from the factored
# derivatives below, so nothing is copied from the library under test.
TEXTBOOK_PEAKS = {
    "cycloidal": (2.0, TAU, TAU * TAU),
    "345": (1.875, 10.0 / math.sqrt(3.0), 60.0),
}


def peak_coefficients(law: str) -> tuple[float, float, float]:
    """(v_peak, a_peak, j_peak) of the normalized law, derived independently."""
    if law in TEXTBOOK_PEAKS:
        return TEXTBOOK_PEAKS[law]
    # 4-5-6-7: v peaks at u=1/2; a = 420 u^2 (1-u)^2 (1-2u) and
    # j = 840 u (1 - 6u + 10u^2 - 5u^3) after factoring.
    def a_of(u: float) -> float:
        return 420.0 * u * u * (1.0 - u) ** 2 * (1.0 - 2.0 * u)

    def da_of(u: float) -> float:
        return (
            2.0 * u * (1.0 - u) ** 2 * (1.0 - 2.0 * u)
            - 2.0 * u * u * (1.0 - u) * (1.0 - 2.0 * u)
            - 2.0 * u * u * (1.0 - u) ** 2
        )

    def j_of(u: float) -> float:
        return 840.0 * u * (1.0 - 6.0 * u + 10.0 * u * u - 5.0 * u**3)

    def dj_of(u: float) -> float:
        return 840.0 * (1.0 - 12.0 * u + 30.0 * u * u - 20.0 * u**3)

    def bisect(f, lo: float, hi: float) -> float:
        f_lo = f(lo)
        for _ in range(200):
            mid = 0.5 * (lo + hi)
            if (f_lo < 0.0) == (f(mid) < 0.0):
                lo, f_lo = mid, f(mid)
            else:
                hi = mid
        return 0.5 * (lo + hi)

    return (2.1875, abs(a_of(bisect(da_of, 0.2, 0.4))), abs(j_of(bisect(dj_of, 0.05, 0.15))))


def verify_law_anchors() -> dict:
    """The reference derivatives must reproduce published peak coefficients."""
    worst = 0.0
    for law in ("cycloidal", "345", "4567"):
        v_peak, a_peak, j_peak = peak_coefficients(law)
        # Endpoints matter: the jerk peaks of cycloidal and 3-4-5 sit at u=0/1,
        # so a grid that skips them under-reports the peak.
        grid = [i / 10000.0 for i in range(0, 10001)]
        measured_v = max(abs(normalized(law, u)[1]) for u in grid)
        measured_a = max(abs(normalized(law, u)[2]) for u in grid)
        # The published jerk coefficient is the signed positive peak.  4-5-6-7
        # also has a larger negative peak at u=1/2 (|j| = 52.5); the library
        # reports max|jerk|, so that branch is covered by the point checks.
        measured_j = max(normalized(law, u)[3] for u in grid)
        for measured, expected, name in (
            (measured_v, v_peak, "velocity"),
            (measured_a, a_peak, "acceleration"),
            (measured_j, j_peak, "jerk"),
        ):
            relative = abs(measured - expected) / max(1e-12, abs(expected))
            worst = max(worst, relative)
            check(
                relative < 5e-5,
                "law anchor {}: {} peak {:.12g} != reference {:.12g}",
                law,
                name,
                measured,
                expected,
            )
    return {"worst_relative_error": worst}


# ---------------------------------------------------------------------------
# Program and geometry reference
# ---------------------------------------------------------------------------


class Program:
    def __init__(self, segments: list[dict]):
        self.segments = segments
        self.starts: list[float] = []
        self.heights: list[float] = []
        angle = 0.0
        lift = 0.0
        for segment in segments:
            self.starts.append(angle)
            self.heights.append(lift)
            angle += math.radians(segment["angle_deg"])
            lift += segment["lift_mm"]
        if abs(angle - TAU) > 1e-9:
            raise ValueError("segment angles must sum to one revolution")
        if abs(lift) > 1e-9:
            raise ValueError("program must return to zero lift")

    def segment_at(self, theta: float) -> int:
        t = theta - math.floor(theta / TAU) * TAU
        for index in range(len(self.segments) - 1, -1, -1):
            if t >= self.starts[index] - 1e-12:
                return index
        return 0

    def motion(self, theta: float) -> tuple[float, float, float, float, int]:
        index = self.segment_at(theta)
        segment = self.segments[index]
        angle = math.radians(segment["angle_deg"])
        t = theta - math.floor(theta / TAU) * TAU
        u = min(max((t - self.starts[index]) / angle, 0.0), 1.0)
        s, v, a, j = normalized(segment["law"], u)
        lift = segment["lift_mm"]
        return (
            self.heights[index] + lift * s,
            lift * v / angle,
            lift * a / (angle * angle),
            lift * j / (angle**3),
            index,
        )


def zero_height(base: float, roller: float, offset: float) -> float:
    return math.sqrt((base + roller) ** 2 - offset**2)


def geometry_point(base: float, roller: float, offset: float, theta: float, program: Program) -> dict:
    s, v, a, j, index = program.motion(theta)
    q = zero_height(base, roller, offset) + s
    d = v - offset
    sin_t = math.sin(theta)
    cos_t = math.cos(theta)
    px = q * sin_t + offset * cos_t
    py = q * cos_t - offset * sin_t
    dpx = v * sin_t + q * cos_t - offset * sin_t
    dpy = v * cos_t - q * sin_t - offset * cos_t
    ddpx = a * sin_t + 2.0 * v * cos_t - q * sin_t - offset * cos_t
    ddpy = a * cos_t - 2.0 * v * sin_t - q * cos_t + offset * sin_t
    speed = math.hypot(dpx, dpy)
    nx = -dpy / speed
    ny = dpx / speed
    # The cam parameter increases clockwise, so the parametric curvature of the
    # pitch curve carries the opposite sign to the library's envelope form.
    curvature_param = -(dpx * ddpy - dpy * ddpx) / speed**3
    curvature_closed = (q * (q - a) + d * (2.0 * v - offset)) / speed**3
    return {
        "s": s,
        "v": v,
        "a": a,
        "j": j,
        "segment_index": index,
        "px": px,
        "py": py,
        "x": px - roller * nx,
        "y": py - roller * ny,
        "pressure": math.atan2(d, q),
        "curvature": curvature_param,
        "curvature_closed": curvature_closed,
        "offset_factor": 1.0 - roller * curvature_param,
        "speed": speed,
    }


def pressure_of(base: float, roller: float, offset: float, program: Program, theta: float) -> float:
    s, v, _a, _j, _i = program.motion(theta)
    return abs(math.atan2(v - offset, zero_height(base, roller, offset) + s))


def pressure_derivative(base: float, roller: float, offset: float, program: Program, theta: float) -> float:
    s, v, a, _j, _i = program.motion(theta)
    q = zero_height(base, roller, offset) + s
    d = v - offset
    return (a * q - d * v) / (q * q + d * d)


def reference_band(
    base: float,
    roller: float,
    offset: float,
    program: Program,
    resolution: int,
    factor: int,
    h_coarse: float,
) -> dict:
    """Observed bands using a sampled derivative estimate; NOT certified supremum bounds."""
    steps = resolution * factor
    grid_max = 0.0
    lipschitz = 0.0
    for k in range(steps):
        theta = TAU * k / steps
        value = pressure_of(base, roller, offset, program, theta)
        if value > grid_max:
            grid_max = value
        derivative = abs(pressure_derivative(base, roller, offset, program, theta))
        if derivative > lipschitz:
            lipschitz = derivative
    h_fine = TAU / steps
    return {
        "grid_max_deg": math.degrees(grid_max),
        "upper_deg": math.degrees(grid_max + lipschitz * h_fine / 2.0),
        "lower_deg": math.degrees(grid_max - lipschitz * h_fine / 2.0 - lipschitz * h_coarse / 2.0),
        "lipschitz_deg_per_rad": math.degrees(lipschitz),
        "certified": False,
        "grid_points": steps,
    }


# ---------------------------------------------------------------------------
# Engine driver: file based, no pipes
# ---------------------------------------------------------------------------


def run_engine_payloads(payloads: list[str]) -> tuple[list[str], str]:
    with tempfile.TemporaryDirectory(prefix="mooncam-oracle-") as tmp:
        request = Path(tmp) / "request.jsonl"
        response = Path(tmp) / "response.jsonl"
        request.write_text("\n".join(payloads) + "\n", encoding="utf-8")
        with request.open("rb") as stdin, response.open("wb") as stdout:
            completed = subprocess.run(
                [os.environ.get("NODE", "node"), str(ENGINE)],
                stdin=stdin,
                stdout=stdout,
                stderr=subprocess.PIPE,
                cwd=ROOT,
            )
        stderr = completed.stderr.decode("utf-8", "replace")
        if completed.returncode != 0:
            raise SystemExit("engine runner failed:\n" + stderr)
        lines = [line for line in response.read_text(encoding="utf-8").splitlines() if line]
    return lines, stderr


def run_engine(cases: list[dict]) -> list[dict]:
    lines, _stderr = run_engine_payloads([json.dumps(case) for case in cases])
    if len(lines) != len(cases):
        raise SystemExit(f"engine returned {len(lines)} results for {len(cases)} cases")
    return [json.loads(line) for line in lines]


# ---------------------------------------------------------------------------
# Case families
# ---------------------------------------------------------------------------


def symmetric_program(law: str) -> dict:
    return {
        "segments": [
            {"angle_deg": 90, "lift_mm": 20, "law": law},
            {"angle_deg": 90, "lift_mm": 0, "law": law},
            {"angle_deg": 90, "lift_mm": -20, "law": law},
            {"angle_deg": 90, "lift_mm": 0, "law": law},
        ]
    }


def uneven_program(law: str) -> dict:
    return {
        "segments": [
            {"angle_deg": 55, "lift_mm": 12, "law": law},
            {"angle_deg": 35, "lift_mm": 0, "law": law},
            {"angle_deg": 110, "lift_mm": -12, "law": law},
            {"angle_deg": 25, "lift_mm": 0, "law": law},
            {"angle_deg": 95, "lift_mm": 8, "law": law},
            {"angle_deg": 40, "lift_mm": -8, "law": law},
        ]
    }


def dense_program(law: str) -> dict:
    return {
        "segments": [
            {"angle_deg": 45, "lift_mm": 5, "law": law},
            {"angle_deg": 45, "lift_mm": -5, "law": law},
            {"angle_deg": 45, "lift_mm": 5, "law": law},
            {"angle_deg": 45, "lift_mm": 0, "law": law},
            {"angle_deg": 45, "lift_mm": -5, "law": law},
            {"angle_deg": 45, "lift_mm": 5, "law": law},
            {"angle_deg": 45, "lift_mm": -5, "law": law},
            {"angle_deg": 45, "lift_mm": 0, "law": law},
        ]
    }


def base_case(program: dict, base: float, roller: float, offset: float, resolution: int) -> dict:
    return {
        "action": "analyze",
        "units": "mm",
        "base_radius_mm": base,
        "roller_radius_mm": roller,
        "offset_mm": offset,
        "rpm": 60,
        "resolution": resolution,
        "pressure_limit_deg": 30,
        "outputs": ["points"],
        **program,
    }


def build_cases() -> list[dict]:
    cases: list[dict] = []
    for law in ("cycloidal", "345", "4567"):
        program = symmetric_program(law)
        for base in (25.0, 40.0, 60.0, 120.0):
            for roller in (2.0, 4.0, 8.0):
                for offset in (-8.0, -3.0, 0.0, 3.0, 8.0):
                    cases.append(base_case(program, base, roller, offset, 720))
    for law in ("cycloidal", "345", "4567"):
        for program in (uneven_program(law), dense_program(law)):
            for base, roller, offset in ((40.0, 4.0, 0.0), (40.0, 4.0, 6.0), (18.0, 3.0, -2.0)):
                cases.append(base_case(program, base, roller, offset, 720))
    for resolution in (360, 720, 1440, 3600):
        cases.append(base_case(symmetric_program("4567"), 40.0, 4.0, 0.0, resolution))
    for base, roller, offset in ((1e-3, 1e-3, 0.0), (1e4, 1e2, 1e3), (1e-6, 1e-6, 0.0)):
        cases.append(base_case(symmetric_program("345"), base, roller, offset, 360))
    return cases


# ---------------------------------------------------------------------------
# Per-case verification
# ---------------------------------------------------------------------------


def label_of(case: dict) -> str:
    return "{}:rb{}:rr{}:e{}:r{}:n{}".format(
        case["segments"][0]["law"],
        case["base_radius_mm"],
        case["roller_radius_mm"],
        case["offset_mm"],
        case["resolution"],
        len(case["segments"]),
    )


def verify_mesh(label: str, case: dict, points: list[dict], program: Program) -> float:
    """Structural checks that do not depend on how radians are rounded."""
    thetas = [float(point["theta_rad"]) for point in points]
    check(abs(thetas[0]) <= 1e-15, "{}: first sample angle {} is not zero", label, thetas[0])
    check(abs(thetas[-1] - TAU) <= 1e-15, "{}: last sample angle {!r} is not 2*pi", label, thetas[-1])
    spacings = [thetas[index + 1] - thetas[index] for index in range(len(thetas) - 1)]
    check(min(spacings) > 0.0, "{}: sample angles are not strictly increasing", label)
    nominal = TAU / case["resolution"]
    widest = max(spacings)
    check(
        widest <= nominal * (1.0 + 1e-9),
        "{}: widest spacing {!r} exceeds nominal {!r}",
        label,
        widest,
        nominal,
    )
    intervals = len(points) - 1
    check(
        case["resolution"] <= intervals <= case["resolution"] + len(case["segments"]),
        "{}: {} intervals outside [{}, {}]",
        label,
        intervals,
        case["resolution"],
        case["resolution"] + len(case["segments"]),
    )
    for boundary in program.starts[1:] + [TAU]:
        nearest = min(abs(theta - boundary) for theta in thetas)
        check(
            nearest <= 1e-12,
            "{}: no sample within 1e-12 rad of segment boundary {!r} (nearest {!r})",
            label,
            boundary,
            nearest,
        )
    return widest


def verify_case(label: str, case: dict, result: dict) -> dict:
    if not check(result.get("ok") is True, "{}: engine rejected the case: {}", label, result):
        return {}
    report = result["result"]
    program = Program(case["segments"])
    base, roller, offset = case["base_radius_mm"], case["roller_radius_mm"], case["offset_mm"]
    omega = case["rpm"] * TAU / 60.0
    points = report.get("points")
    if not check(isinstance(points, list) and len(points) >= 4, "{}: missing points array", label):
        return {}
    thetas = [float(point["theta_rad"]) for point in points]
    widest = verify_mesh(label, case, points, program)

    check(
        report["sample_count"] == len(points),
        "{}: sample_count {} != {}",
        label,
        report["sample_count"],
        len(points),
    )
    check(
        report["sampling"]["actual_intervals"] == len(points) - 1,
        "{}: actual_intervals {} != {}",
        label,
        report["sampling"]["actual_intervals"],
        len(points) - 1,
    )
    check(
        report["state"] in ("accepted_sampled", "rejected", "incomplete"),
        "{}: unknown state {!r}",
        label,
        report["state"],
    )
    check(
        report["sampled_feasible"] == (report["state"] == "accepted_sampled"),
        "{}: sampled_feasible {} disagrees with state {}",
        label,
        report["sampled_feasible"],
        report["state"],
    )

    boundaries = program.starts[1:] + [TAU]
    worst = {
        "contact_mm": 0.0,
        "pitch_mm": 0.0,
        "pressure_deg": 0.0,
        "curvature_rel": 0.0,
        "offset_factor_abs": 0.0,
        "lift_mm": 0.0,
        "velocity_abs": 0.0,
        "velocity_scale": 1.0,
        "acceleration_abs": 0.0,
        "acceleration_scale": 1.0,
        "jerk_abs": 0.0,
        "jerk_scale": 1.0,
        "reference_routes_rel": 0.0,
        "sample_spacing_rad": widest,
    }
    for index, point in enumerate(points):
        theta = float(point["theta_rad"])
        ref = geometry_point(base, roller, offset, theta, program)
        scale = max(1.0, abs(ref["x"]), abs(ref["y"]), abs(ref["px"]), abs(ref["py"]))
        contact_error = math.hypot(point["x"] - ref["x"], point["y"] - ref["y"])
        pitch_error = math.hypot(point["pitch_x"] - ref["px"], point["pitch_y"] - ref["py"])
        worst["contact_mm"] = max(worst["contact_mm"], contact_error)
        worst["pitch_mm"] = max(worst["pitch_mm"], pitch_error)
        if contact_error > 1e-11 * scale:
            fail(
                "{}[{}]: contact ({!r}, {!r}) vs reference ({!r}, {!r})".format(
                    label, index, point["x"], point["y"], ref["x"], ref["y"]
                )
            )
        if pitch_error > 1e-11 * scale:
            fail(
                "{}[{}]: pitch ({!r}, {!r}) vs reference ({!r}, {!r})".format(
                    label, index, point["pitch_x"], point["pitch_y"], ref["px"], ref["py"]
                )
            )
        pressure_deg = ref["pressure"] * 180.0 / math.pi
        pressure_error = abs(point["pressure_deg"] - pressure_deg)
        worst["pressure_deg"] = max(worst["pressure_deg"], pressure_error)
        if pressure_error > 1e-9:
            fail("{}[{}]: pressure {!r} vs reference {!r}", label, index, point["pressure_deg"], pressure_deg)
        curvature_scale = max(1e-9, abs(ref["curvature"]))
        curvature_error = abs(point["pitch_curvature"] - ref["curvature"]) / curvature_scale
        worst["curvature_rel"] = max(worst["curvature_rel"], curvature_error)
        if curvature_error > 1e-8:
            fail(
                "{}[{}]: curvature {!r} vs parametric reference {!r}",
                label,
                index,
                point["pitch_curvature"],
                ref["curvature"],
            )
        factor_error = abs(point["offset_factor"] - ref["offset_factor"])
        worst["offset_factor_abs"] = max(worst["offset_factor_abs"], factor_error)
        if factor_error > 1e-9:
            fail(
                "{}[{}]: offset_factor {!r} vs reference {!r}",
                label,
                index,
                point["offset_factor"],
                ref["offset_factor"],
            )
        lift_error = abs(point["lift_mm"] - ref["s"])
        worst["lift_mm"] = max(worst["lift_mm"], lift_error)
        if lift_error > 1e-11:
            fail("{}[{}]: lift {!r} vs reference {!r}", label, index, point["lift_mm"], ref["s"])
        for field, expected, key in (
            ("velocity_mm_s", ref["v"] * omega, "velocity"),
            ("acceleration_mm_s2", ref["a"] * omega * omega, "acceleration"),
            ("jerk_mm_s3", ref["j"] * omega * omega * omega, "jerk"),
        ):
            difference = abs(point[field] - expected)
            worst[key + "_abs"] = max(worst.get(key + "_abs", 0.0), difference)
            worst[key + "_scale"] = max(worst.get(key + "_scale", 1.0), abs(expected))
        # Segment attribution is only meaningful away from a shared boundary.
        if index != len(points) - 1 and min(abs(theta - item) for item in boundaries) > 1e-9:
            check(
                point["segment_index"] == ref["segment_index"],
                "{}[{}]: segment_index {} != {}",
                label,
                index,
                point["segment_index"],
                ref["segment_index"],
            )
        route_error = abs(ref["curvature_closed"] - ref["curvature"]) / curvature_scale
        worst["reference_routes_rel"] = max(worst["reference_routes_rel"], route_error)
        if route_error > 1e-9:
            fail(
                "{}[{}]: reference routes disagree: closed {!r} param {!r}",
                label,
                index,
                ref["curvature_closed"],
                ref["curvature"],
            )

    # Derivative tolerances are scaled by the largest value in the case, not by
    # the local value: a jerk that legitimately crosses zero must not be
    # compared with its own near-zero magnitude.
    for key, tolerance in (("velocity", 5e-10), ("acceleration", 5e-10), ("jerk", 5e-9)):
        scale = worst.get(key + "_scale", 1.0)
        check(
            worst.get(key + "_abs", 0.0) <= tolerance * scale,
            "{}: {} differs from the reference by {!r} on scale {!r}",
            label,
            key,
            worst.get(key + "_abs", 0.0),
            scale,
        )

    sampled_max = max(abs(point["pressure_deg"]) for point in points)
    check(
        abs(sampled_max - report["max_pressure_deg"]) <= 1e-9,
        "{}: max_pressure_deg {} != max|point| {}",
        label,
        report["max_pressure_deg"],
        sampled_max,
    )
    worst_index = max(range(len(points)), key=lambda i: abs(points[i]["pressure_deg"]))
    # worst_pressure_angle_deg is the *angle* at which the maximum is reached,
    # reported in degrees, not the pressure value itself.
    check(
        abs(thetas[worst_index] * 180.0 / math.pi - report["worst_pressure_angle_deg"]) <= 1e-9,
        "{}: worst_pressure_angle_deg {} != sample angle {}",
        label,
        report["worst_pressure_angle_deg"],
        thetas[worst_index] * 180.0 / math.pi,
    )
    factor_index = min(range(len(points)), key=lambda i: points[i]["offset_factor"])
    sampled_min_factor = points[factor_index]["offset_factor"]
    check(
        abs(sampled_min_factor - report["min_offset_factor"]) <= 1e-12,
        "{}: min_offset_factor {} != {}",
        label,
        report["min_offset_factor"],
        sampled_min_factor,
    )
    check(
        abs(thetas[factor_index] - report["min_offset_factor_angle_rad"]) <= 1e-12,
        "{}: min_offset_factor_angle_rad {} != sample angle {}",
        label,
        report["min_offset_factor_angle_rad"],
        thetas[factor_index],
    )
    summary_worst = {
        key: worst[key]
        for key in (
            "contact_mm",
            "pitch_mm",
            "pressure_deg",
            "curvature_rel",
            "offset_factor_abs",
            "lift_mm",
            "reference_routes_rel",
            "sample_spacing_rad",
        )
    }
    for key in ("velocity", "acceleration", "jerk"):
        summary_worst[key + "_rel"] = worst[key + "_abs"] / max(1e-12, worst[key + "_scale"])
    summary_worst["points"] = float(len(points))
    return summary_worst


def verify_sandwich(label: str, case: dict, result: dict, h_coarse: float, factor: int = 32) -> dict:
    report = result["result"]
    program = Program(case["segments"])
    band = reference_band(
        case["base_radius_mm"],
        case["roller_radius_mm"],
        case["offset_mm"],
        program,
        case["resolution"],
        factor,
        h_coarse,
    )
    reported = report["max_pressure_deg"]
    check(
        reported <= band["upper_deg"] + 1e-9,
        "{}: reported {} exceeds upper bound {}",
        label,
        reported,
        band["upper_deg"],
    )
    check(
        reported >= band["lower_deg"] - 1e-9,
        "{}: reported {} below lower bound {}",
        label,
        reported,
        band["lower_deg"],
    )
    return {
        "label": label,
        "resolution": case["resolution"],
        "reported_deg": reported,
        "reference_grid_max_deg": band["grid_max_deg"],
        "observed_upper_band_deg": band["upper_deg"],
        "observed_lower_band_deg": band["lower_deg"],
        "sampling_deficit_deg": band["grid_max_deg"] - reported,
        "lipschitz_deg_per_rad": band["lipschitz_deg_per_rad"],
        "reference_grid_points": band["grid_points"],
        "certified": False,
    }


def verify_exports(label: str, case: dict, result: dict) -> None:
    report = result["result"]
    program = Program(case["segments"])
    base, roller, offset = case["base_radius_mm"], case["roller_radius_mm"], case["offset_mm"]
    points = report["points"]
    thetas = [float(point["theta_rad"]) for point in points]

    rows = report["csv"].strip().split("\n")
    header = rows[0].split(",")
    expected_header = [
        "theta_rad",
        "lift",
        "ds_dtheta",
        "d2s_dtheta2",
        "d3s_dtheta3",
        "pitch_x",
        "pitch_y",
        "cam_x",
        "cam_y",
        "pressure_rad",
        "pitch_curvature",
        "offset_factor",
    ]
    check(header == expected_header, "{}: csv header changed: {}", label, header)
    check(len(rows) - 1 == len(points), "{}: csv rows {} != {}", label, len(rows) - 1, len(points))
    for index in range(len(points)):
        values = [float(item) for item in rows[index + 1].split(",")]
        ref = geometry_point(base, roller, offset, thetas[index], program)
        check(
            abs(values[7] - ref["x"]) <= 1e-9 * max(1.0, abs(ref["x"])),
            "{}: csv cam_x[{}] {} != {}", label, index, values[7], ref["x"],
        )
        check(
            abs(values[8] - ref["y"]) <= 1e-9 * max(1.0, abs(ref["y"])),
            "{}: csv cam_y[{}] {} != {}", label, index, values[8], ref["y"],
        )
        check(
            abs(values[9] - ref["pressure"]) <= 1e-12,
            "{}: csv pressure[{}] {} != {}", label, index, values[9], ref["pressure"],
        )
        check(
            abs(values[10] - ref["curvature"]) <= 1e-9 * max(1.0, abs(ref["curvature"])),
            "{}: csv curvature[{}] mismatch", label, index,
        )

    dxf = report["dxf"].split("\n")
    check("AC1015" in dxf, "{}: dxf header missing AC1015", label)
    check("LWPOLYLINE" in dxf, "{}: dxf is not a polyline", label)
    units_index = dxf.index("$INSUNITS")
    check(dxf[units_index + 2] == "4", "{}: dxf INSUNITS {} != 4", label, dxf[units_index + 2])
    count_index = dxf.index("90")
    declared = int(dxf[count_index + 1])
    check(declared == len(points) - 1, "{}: dxf vertices {} != {}", label, declared, len(points) - 1)
    closed_index = dxf.index("70", count_index)
    check(dxf[closed_index + 1] == "1", "{}: dxf polyline not closed", label)
    check(dxf[-2] == "EOF", "{}: dxf does not end with EOF", label)
    coordinates_start = count_index + 5
    coordinates_end = coordinates_start + 4 * declared
    xs = [float(value) for value in dxf[coordinates_start:coordinates_end:4]]
    ys = [float(value) for value in dxf[coordinates_start + 2 : coordinates_end + 2 : 4]]
    check(len(xs) == declared and len(ys) == declared, "{}: dxf coordinate count mismatch", label)
    step = max(1, declared // 37)
    for index in range(0, min(declared, len(xs)), step):
        ref = geometry_point(base, roller, offset, thetas[index], program)
        check(
            abs(xs[index] - ref["x"]) <= 1e-9 * max(1.0, abs(ref["x"])),
            "{}: dxf x[{}] {} != {}", label, index, xs[index], ref["x"],
        )
        check(
            abs(ys[index] - ref["y"]) <= 1e-9 * max(1.0, abs(ref["y"])),
            "{}: dxf y[{}] {} != {}", label, index, ys[index], ref["y"],
        )

    svg = report["svg"]
    check(svg.startswith("<svg"), "{}: svg missing root element", label)
    marker = 'points="'
    start = svg.index(marker) + len(marker)
    end = svg.index('"', start)
    pairs = [item.split(",") for item in svg[start:end].split() if item]
    check(len(pairs) == len(points), "{}: svg points {} != {}", label, len(pairs), len(points))
    step = max(1, len(pairs) // 29)
    for index in range(0, min(len(pairs), len(points)), step):
        ref = geometry_point(base, roller, offset, thetas[index], program)
        check(
            abs(float(pairs[index][0]) - ref["x"]) <= 1e-9 * max(1.0, abs(ref["x"])),
            "{}: svg x[{}] mismatch", label, index,
        )
        check(
            abs(float(pairs[index][1]) + ref["y"]) <= 1e-9 * max(1.0, abs(ref["y"])),
            "{}: svg y[{}] mismatch", label, index,
        )


def verify_error_contract() -> None:
    workshop = json.loads((ROOT / "examples" / "workshop.json").read_text(encoding="utf-8"))
    payloads = [
        "{not json",
        json.dumps({**workshop, "resolution": 36.5}),
        json.dumps({**workshop, "segments": []}),
        json.dumps({**workshop, "base_radius_mm": 0}),
        json.dumps({**workshop, "offset_mm": 1000}),
        json.dumps({**workshop, "surprise": 1}),
        json.dumps({**workshop, "action": "bogus"}),
        json.dumps({**workshop, "padding": "x" * 200_001}),
        json.dumps(
            {
                **workshop,
                "action": "search",
                "search": {"lower_mm": 5, "upper_mm": 6, "intervals": 0},
            }
        ),
        json.dumps(
            {
                **workshop,
                "action": "search",
                "search": {"lower_mm": 5, "upper_mm": 6, "intervals": 257},
            }
        ),
    ]
    expected = [
        "invalid_json",
        "invalid_input",
        "invalid_input",
        "invalid_input",
        "invalid_input",
        "invalid_input",
        "invalid_input",
        "input_too_large",
        "invalid_input",
        "invalid_input",
    ]
    lines, _stderr = run_engine_payloads(payloads)
    for want, line in zip(expected, lines):
        parsed = json.loads(line)
        if not check(parsed.get("ok") is False, "error contract: {} was accepted", want):
            continue
        check(
            parsed.get("error_code") == want,
            "error contract: expected {}, got {}",
            want,
            parsed.get("error_code"),
        )


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    anchors = verify_law_anchors()
    cases = build_cases()
    export_cases = [dict(case, outputs=["points", "csv", "svg", "dxf"]) for case in cases[:6]]
    results = run_engine(cases + export_cases)

    worst: dict[str, float] = {}
    sandwiches: list[dict] = []
    for index, (case, result) in enumerate(zip(cases, results[: len(cases)])):
        label = label_of(case)
        case_worst = verify_case(label, case, result)
        spacing = case_worst.get("sample_spacing_rad", TAU / case["resolution"])
        for key, value in case_worst.items():
            if key == "sample_spacing_rad":
                continue
            worst[key] = max(worst.get(key, 0.0), value)
        # The band check is the expensive one: representative subset plus the
        # whole resolution sweep.
        if index % 15 == 0 or case["resolution"] != 720:
            sandwiches.append(verify_sandwich(label, case, result, spacing))
    for case, result in zip(export_cases, results[len(cases) :]):
        verify_exports("exports:{}".format(case["segments"][0]["law"]), case, result)
    verify_error_contract()

    sweep = [
        item
        for item in sandwiches
        if item["label"].startswith("4567:rb40.0:rr4.0:e0.0") and item["label"].endswith(":n4")
    ]
    if len(sweep) >= 4:
        sweep.sort(key=lambda item: item["resolution"])
        deficits = [abs(item["sampling_deficit_deg"]) for item in sweep]
        check(
            deficits[-1] <= max(deficits[0], 1e-12) / 2.0,
            "convergence: resolution 3600 deficit {} did not shrink below half of {}",
            deficits[-1],
            deficits[0],
        )
        check(
            deficits[-1] < 1e-3,
            "convergence: resolution 3600 sampling deficit {} still above 1e-3 deg",
            deficits[-1],
        )

    summary = {
        "cases": len(cases),
        "points_checked": sum(
            len(result["result"]["points"]) for result in results[: len(cases)] if result.get("ok")
        ),
        "checks": CHECKS,
        "failures": FAILURE_COUNT,
        "law_anchors": anchors,
        "worst_error": {key: worst[key] for key in sorted(worst)},
        "band_checks": len(sandwiches),
        "max_sampling_deficit_deg": max(
            (abs(item["sampling_deficit_deg"]) for item in sandwiches), default=0.0
        ),
        "convergence": [
            {
                "resolution": item["resolution"],
                "reported_deg": item["reported_deg"],
                "reference_deg": item["reference_grid_max_deg"],
                "sampling_deficit_deg": item["sampling_deficit_deg"],
            }
            for item in sorted(sweep, key=lambda item: item["resolution"])
        ],
    }
    (ARTIFACTS / "oracle-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    (ARTIFACTS / "oracle-convergence.json").write_text(
        json.dumps(
            {
                "note": "reported maximum vs a 32x finer reference grid; deficit is the sampling loss",
                "band_checks": sandwiches,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2))
    if FAILURE_COUNT:
        print(f"\n{FAILURE_COUNT} failure(s):", file=sys.stderr)
        for message in FAILURES[:20]:
            print("  - " + message, file=sys.stderr)
        if FAILURE_COUNT > 20:
            print(f"  ... {FAILURE_COUNT - 20} more", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
