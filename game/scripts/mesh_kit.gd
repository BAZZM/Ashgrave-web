class_name MeshKit
extends RefCounted


static var _cache := {}


static func tube(points: PackedVector3Array, radii: PackedFloat32Array, segs := 14, sx := 1.0, sz := 1.0) -> ArrayMesh:
	var key := "tube" + str(points) + str(radii) + str([segs, sx, sz])
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var n := points.size()
	var prev_u := Vector3.RIGHT
	for i in n:
		var t := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var u := prev_u - t * prev_u.dot(t)
		if u.length() < 0.001:
			u = t.cross(Vector3.FORWARD)
		u = u.normalized()
		var v := t.cross(u)
		prev_u = u
		for j in segs:
			var ang := TAU * j / segs
			st.set_uv(Vector2(float(j) / segs, float(i) / (n - 1)))
			st.add_vertex(points[i] + (u * cos(ang) * sx + v * sin(ang) * sz) * radii[i])
	for i in n - 1:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			var c := a + segs
			var d := b + segs
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	var built: ArrayMesh = st.commit()
	_cache[key] = built
	return built


static func lathe(profile: Array, segs := 16, sx := 1.0, sz := 1.0) -> ArrayMesh:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for p in profile:
		pts.append(Vector3(0, p[1], 0))
		radii.append(p[0])
	return tube(pts, radii, segs, sx, sz)


static func limb(r0: float, r_mid: float, r1: float) -> ArrayMesh:
	return lathe([[r0 * 0.55, -0.5], [r0, -0.44], [r_mid, -0.1], [r1, 0.4], [r1 * 0.7, 0.5]], 10)


static func blade(length: float, width: float, thick: float, tip: float, taper := 0.8) -> ArrayMesh:
	var key := "blade" + str([length, width, thick, tip, taper])
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ys := [0.0, length - tip]
	var ws := [width, width * taper]
	var rings: Array = []
	for i in 2:
		var w: float = ws[i] * 0.5
		var y: float = ys[i]
		rings.append([Vector3(w, y, 0), Vector3(0, y, thick * 0.5), Vector3(-w, y, 0), Vector3(0, y, -thick * 0.5)])
	var apex := Vector3(0, length, 0)
	for j in 4:
		var a: Vector3 = rings[0][j]
		var b: Vector3 = rings[0][(j + 1) % 4]
		var c: Vector3 = rings[1][j]
		var d: Vector3 = rings[1][(j + 1) % 4]
		for v in [a, c, b, b, c, d, c, apex, d]:
			st.add_vertex(v)
	st.generate_normals()
	var built: ArrayMesh = st.commit()
	_cache[key] = built
	return built


static func cleaver(length: float, width: float, thick: float) -> ArrayMesh:
	var key := "cleaver" + str([length, width, thick])
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	var spine: Array = []
	var edge: Array = []
	for i in n + 1:
		var k := float(i) / n
		var y := k * length
		spine.append(Vector3(-width * 0.25, y, 0))
		edge.append(Vector3(-width * 0.25 + width * (0.55 + 0.45 * sin(k * PI)) * (1.0 - pow(k, 6.0)), y, 0))
	for i in n:
		var mid0: Vector3 = spine[i].lerp(edge[i], 0.35)
		var mid1: Vector3 = spine[i + 1].lerp(edge[i + 1], 0.35)
		for side in [-1.0, 1.0]:
			var off := Vector3(0, 0, thick * 0.5 * side)
			for v in [spine[i], spine[i + 1], mid0 + off, mid0 + off, spine[i + 1], mid1 + off,
					mid0 + off, mid1 + off, edge[i], edge[i], mid1 + off, edge[i + 1]]:
				st.add_vertex(v)
	st.generate_normals()
	var built: ArrayMesh = st.commit()
	_cache[key] = built
	return built


static func shield(width: float, height: float, bulge: float) -> ArrayMesh:
	var key := "shield" + str([width, height, bulge])
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var nx := 8
	var ny := 10
	for iy in ny + 1:
		var ky := float(iy) / ny
		var half := width * 0.5 * (1.0 if ky < 0.35 else sqrt(maxf(1.0 - pow((ky - 0.35) / 0.65, 2.0), 0.0)))
		for ix in nx + 1:
			var kx := float(ix) / nx * 2.0 - 1.0
			st.set_uv(Vector2(kx * 0.5 + 0.5, ky))
			st.add_vertex(Vector3(kx * half, height * (0.5 - ky), -bulge * (1.0 - kx * kx) * (1.0 - ky * 0.5)))
	for iy in ny:
		for ix in nx:
			var a := iy * (nx + 1) + ix
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			for idx in [a, b, c, b, d, c]:
				st.add_index(idx)
	st.generate_normals()
	var built: ArrayMesh = st.commit()
	_cache[key] = built
	return built


static func horn(from: Vector3, to: Vector3, bend: Vector3, radius: float, steps := 7) -> ArrayMesh:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in steps + 1:
		var k := float(i) / steps
		pts.append(from.lerp(to, k) + bend * sin(k * PI))
		radii.append(radius * (1.0 - k * 0.97))
	return tube(pts, radii, 8)
