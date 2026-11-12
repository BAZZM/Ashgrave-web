KNIGHT RPG - GODOT 3D TEXTURE STARTER PACK
=========================================
8 original medieval-fantasy material image designs

CONTENTS
--------
Godot_1024/      8 PNG textures resized to 1024 x 1024 for convenient in-engine use.
Original_1254/   8 generated PNG textures at their original 1254 x 1254 resolution.
PREVIEW.png      Labelled contact sheet of all eight materials.
TEXTURE_INDEX.csv Filenames, category, and suggested application.

HOW TO USE IN GODOT 4
---------------------
1. Extract the ZIP into your project's asset folder (e.g. res://assets/textures/).
2. Select a 3D mesh and create/assign a StandardMaterial3D.
3. Assign a PNG from Godot_1024 to Albedo > Texture.
4. Set the material's UV scaling / mesh UVs as needed, and enable repeat when tiling.
5. Tune metallic and roughness values to suit the material and scene lighting.

TEXTURE NOTES
-------------
* These are colour/albedo-like image textures only; they are NOT complete PBR sets.
* No validated normal, height, metallic, ambient occlusion or roughness maps are included.
* Seamless tiling was requested during image creation but is NOT mathematically guaranteed.
  Inspect joins before using across large repeated surfaces; stone/ground are the most natural
  candidates to tile, while the armour and decorative patterns may need UV placement.
* The resized 1024px versions are convenient for texture workflows, and the 1254px originals
  preserve the generated images for future processing.
* Images contain baked-looking material highlights/shading in places. For a more realistic
  physically based workflow, consider separate PBR maps and calibrated lighting.
