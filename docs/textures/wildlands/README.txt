WILDLANDS - KNIGHT RPG / GODOT 4 ENVIRONMENT TEXTURE PACK
=========================================================
Created: 12 November 2026

WHAT'S INSIDE
-------------
10 original fantasy-environment image assets:
- 4 grassland and shoreline ground textures
- 2 water surface / shallow water appearance textures
- 2 bark textures
- 2 foliage cutout cards with real alpha transparency

Each image is supplied twice:
- Original_1254/ : the 1254 x 1254 PNG originally generated
- Godot_1024/   : a resized 1024 x 1024 PNG suitable for power-of-two workflows

BONUS
-----
- Shader_Extras/wildlands_water.gdshader : translucent rippling water starter shader
- Shader_Extras/wind_foliage.gdshader   : alpha-cutout leaf card wind movement
- Shader_Extras/grassland_blend.gdshader : mixes three ground textures
- Shader_Extras/water_ripple_normal_a.png and b.png : mathematically periodic
  procedural normal maps for animated water ripples
- PREVIEW.png : numbered contact sheet
- ASSET_INDEX.csv : labels, material class, suggested use, file names

USE IN GODOT 4
--------------
1. Extract the ZIP into your Godot project's res://assets/wildlands/ folder.
2. For standard ground/tree bark material: add a StandardMaterial3D to your mesh,
   assign the appropriate Godot_1024 PNG to Albedo > Texture.
3. Ground textures: set UV scaling and texture repeat on the material. Use terrain
   painting / blending for natural transitions between grass, trail and mud.
4. Foliage cards: use QuadMesh planes or custom crossed foliage geometry and apply
   Shader_Extras/wind_foliage.gdshader as ShaderMaterial. Assign the corresponding
   transparent foliage image to `foliage_albedo` in the shader parameter inspector.
   For an actual tree, you STILL need a 3D trunk and branches mesh. These are not
   3D tree models or rigged trees.
5. Water: apply Shader_Extras/wildlands_water.gdshader to a subdivided PlaneMesh.
   Set `water_albedo` to 06_deep_lake_ripples, assign the included wave normals to
   `ripple_normal_a` and `ripple_normal_b`, and tune UV, opacity, wind/ripple speed.
   Consider placing shallow riverbed under water rather than using it as the
   translucent surface itself.
6. Terrain shader: apply Shader_Extras/grassland_blend.gdshader, set lush_grass =
   01, wild_grass = 02, exposed_dirt = 03. This is automatic slope/patch mixing.

IMPORTANT HONEST LIMITATIONS
----------------------------
- These are AI-generated diffuse/color-like textures. They are NOT physically
  measured PBR material sets. No calibrated height, roughness, AO or bark normals.
- Tiling was requested at generation time, but seamless borders were NOT
  guaranteed or independently texture-seam corrected. Check edges before tiling
  large terrain areas. Use blending/decals to disguise obvious repetition.
- Water photographs/textures show baked-in lighting and do NOT replace a real
  water simulation, accurate depth-based color, refraction or screen reflections.
- Two optional water normal maps were generated procedurally, not extracted as
  physical measurements of the illustrated water images.
- Shaders are source examples targeted to Godot 4.x, not a fully tested Godot
  project; shader/mesh orientation and renderer choice may require tuning.
- Foliage cards contain transparency, but are flat images: build or source 3D
  tree/vegetation meshes and LODs to populate an open world.
- For better open-world quality/performance: add terrain LOD, MultiMesh foliage,
  distance culling/LOD, shadow settings and seasonal/light variation.

File labels are designed for direct search in Godot's FileSystem dock.
