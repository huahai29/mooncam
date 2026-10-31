# Run inside FreeCAD / FreeCADCmd; uses the real FreeCAD DXF importer and OCCT geometry.
import FreeCAD as App
import Import
import Part
import json, math, hashlib, os
from pathlib import Path
root = Path(os.environ["MOONCAM_CAD_ROOT"]).resolve()
expected = json.loads((root / "expected.json").read_text(encoding="utf-8"))
results = {"application": "FreeCAD", "version": App.Version(), "importer": "Import.readDXF (bundled modern C++ importer)", "generator": expected["generator"], "cases": {}}
results["status"] = "running"
(root / "freecad-results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
for name, reference in expected["cases"].items():
    doc = App.newDocument("MoonCam_" + name)
    path = root / name / "profile.dxf"
    stats = Import.readDXF(str(path))
    doc.recompute()
    objects = [obj for obj in doc.Objects if hasattr(obj, "Shape") and not obj.Shape.isNull()]
    assert len(objects) == 1, (name, [(o.Name, o.TypeId) for o in objects])
    obj = objects[0]
    obj.Label = "MoonCam " + name + " imported DXF"
    shape = obj.Shape
    box = shape.BoundBox
    bounds = {"xmin": box.XMin, "xmax": box.XMax, "ymin": box.YMin, "ymax": box.YMax}
    wires = shape.Wires
    assert len(wires) == 1, (name, len(wires))
    wire = wires[0]
    actual = [(v.Point.x, v.Point.y) for v in shape.Vertexes]
    points = json.loads((root / name / "points.json").read_text(encoding="utf-8"))
    wanted = [(p["x"], p["y"]) for p in points]
    directed = lambda xs, ys: max(min(math.hypot(x-a, y-b) for a,b in ys) for x,y in xs)
    error = max(directed(actual, wanted), directed(wanted, actual))
    area = Part.Face(wire).Area
    result = {"source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "object_type": obj.TypeId, "object_name": obj.Name, "vertices": len(actual), "edges": len(shape.Edges), "wires": len(wires), "closed": wire.isClosed(), "shape_valid": shape.isValid(), "bbox_mm": bounds, "width_mm": box.XLength, "height_mm": box.YLength, "perimeter_mm": shape.Length, "enclosed_area_mm2": area, "bidirectional_vertex_distance_max_mm": error, "mooncam_state": reference["state"]}
    assert result["closed"] and result["shape_valid"], result
    assert result["vertices"] == reference["vertices"], result
    assert result["edges"] == reference["vertices"], result
    assert error <= 1e-7, result
    assert all(abs(bounds[k] - reference["bbox"][k]) <= 1e-7 for k in bounds), result
    assert abs(shape.Length - reference["perimeter_mm"]) <= 1e-7, result
    assert abs(area - reference["area_mm2"]) <= 1e-5, result
    doc.saveAs(str(root / name / (name + ".FCStd")))
    results["cases"][name] = result
    print("CAD_IMPORT_PASS", name, json.dumps(result), flush=True)
results["status"] = "passed"
(root / "freecad-results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
print("ALL_FREECAD_IMPORT_CHECKS_PASS", flush=True)
