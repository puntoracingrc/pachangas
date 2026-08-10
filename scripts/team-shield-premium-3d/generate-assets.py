from pathlib import Path
import math

import bpy
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[2]
PUBLIC_DIR = REPO_ROOT / "public" / "team-shield-premium-3d"
ARTIFACT_DIR = REPO_ROOT / "artifacts" / "team-shield-premium-3d-lab"
PUBLIC_DIR.mkdir(parents=True, exist_ok=True)
ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.curves, bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name, color, metallic=0.0, roughness=0.4):
    value = bpy.data.materials.get(name) or bpy.data.materials.new(name=name)
    value.diffuse_color = (*color, 1.0)
    value.use_nodes = True
    principled = next((node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if principled is None:
        principled = value.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        output = next((node for node in value.node_tree.nodes if node.type == "OUTPUT_MATERIAL"), None)
        if output is None:
            output = value.node_tree.nodes.new("ShaderNodeOutputMaterial")
        value.node_tree.links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    principled.inputs["Base Color"].default_value = (*color, 1.0)
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    return value


def set_material(value, color, metallic, roughness):
    value.diffuse_color = (*color, 1.0)
    principled = next(node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    principled.inputs["Base Color"].default_value = (*color, 1.0)
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness


def mark_kit(obj):
    obj["premium_shield_kit"] = True
    return obj


def polygon_curve(name, points, value, depth=0.1, bevel=0.035, z=0.0):
    curve_data = bpy.data.curves.new(name=f"{name}Geometry", type="CURVE")
    curve_data.dimensions = "2D"
    curve_data.resolution_u = 2
    curve_data.fill_mode = "BOTH"
    curve_data.extrude = depth
    curve_data.bevel_depth = bevel
    curve_data.bevel_resolution = 3
    spline = curve_data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, (x, y) in zip(spline.points, points):
        point.co = (x, y, 0.0, 1.0)
    spline.use_cyclic_u = True
    obj = mark_kit(bpy.data.objects.new(name, curve_data))
    obj.location.z = z
    curve_data.materials.append(value)
    bpy.context.collection.objects.link(obj)
    return obj


def outline_curve(name, points, value, bevel=0.1, z=0.2):
    curve_data = bpy.data.curves.new(name=f"{name}Geometry", type="CURVE")
    curve_data.dimensions = "3D"
    curve_data.resolution_u = 2
    curve_data.bevel_depth = bevel
    curve_data.bevel_resolution = 4
    spline = curve_data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, (x, y) in zip(spline.points, points):
        point.co = (x, y, 0.0, 1.0)
    spline.use_cyclic_u = True
    obj = mark_kit(bpy.data.objects.new(name, curve_data))
    obj.location.z = z
    curve_data.materials.append(value)
    bpy.context.collection.objects.link(obj)
    return obj


def create_ball(name, center, pearl, navy, cyan, radius=0.82, rotation=0.0, mark=True):
    root = bpy.data.objects.new(name, None)
    root.location = center
    root.rotation_euler = (0.15, rotation, rotation * 0.28)
    if mark:
        mark_kit(root)
    bpy.context.collection.objects.link(root)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=radius, location=(0, 0, 0))
    sphere = bpy.context.object
    sphere.name = f"{name}Core"
    sphere.parent = root
    sphere.data.materials.append(pearl)
    sphere.data.materials.append(navy)
    sphere.data.materials.append(cyan)
    for face in sphere.data.polygons:
        if face.index % 17 == 0 or face.index % 23 == 3:
            face.material_index = 1
        elif face.index % 29 == 7:
            face.material_index = 2
        else:
            face.material_index = 0
    bevel = sphere.modifiers.new(name="FacetBevel", type="BEVEL")
    bevel.width = 0.018
    bevel.segments = 2
    if mark:
        mark_kit(sphere)

    for index, rotation_xyz in enumerate(((0, 0, 0), (math.pi / 2, 0, 0), (0, math.pi / 2, 0))):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=radius * 0.72,
            minor_radius=radius * 0.025,
            major_segments=48,
            minor_segments=8,
            location=(0, 0, 0),
            rotation=rotation_xyz,
        )
        ring = bpy.context.object
        ring.name = f"{name}Seam{index + 1}"
        ring.parent = root
        ring.data.materials.append(cyan)
        if mark:
            mark_kit(ring)
    return root


def point_camera(camera, target=(0.0, 0.1, 0.0)):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def configure_render(scene, camera, resolution_x, resolution_y):
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = resolution_x
    scene.render.resolution_y = resolution_y
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "WEBP"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.quality = 92
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"


def render(scene, path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def set_render_visibility(root, visible):
    root.hide_render = not visible
    for child in root.children_recursive:
        child.hide_render = not visible


clear_scene()
scene = bpy.context.scene

navy = material("ShieldNavy", (0.018, 0.055, 0.12), metallic=0.22, roughness=0.3)
navy_inner = material("ShieldNavyInner", (0.008, 0.025, 0.065), metallic=0.3, roughness=0.25)
cyan = material("IQCyan", (0.03, 0.67, 0.76), metallic=0.72, roughness=0.18)
pearl = material("BallPearl", (0.88, 0.96, 0.94), metallic=0.28, roughness=0.18)
frame_material = material("PremiumFrameMaterial", (0.83, 0.55, 0.11), metallic=0.94, roughness=0.16)
crown_material = material("PremiumCrownMaterial", (0.9, 0.63, 0.13), metallic=0.96, roughness=0.13)

shield_points = [(-2.28, 2.75), (2.28, 2.75), (2.62, 2.18), (2.28, -1.66), (0.0, -3.35), (-2.28, -1.66), (-2.62, 2.18)]
inner_points = [(-1.98, 2.46), (1.98, 2.46), (2.28, 1.95), (1.98, -1.42), (0.0, -2.98), (-1.98, -1.42), (-2.28, 1.95)]

backing = polygon_curve("PremiumShieldBacking", shield_points, navy, depth=0.12, bevel=0.06, z=-0.22)
inner = polygon_curve("PremiumShieldInner", inner_points, navy_inner, depth=0.09, bevel=0.035, z=0.02)
frame = outline_curve("PremiumFrame", shield_points, frame_material, bevel=0.115, z=0.34)

accent_points = [(0.35, 2.42), (1.98, 2.42), (2.25, 1.93), (1.95, -1.38), (0.25, -2.72), (-0.08, -2.5), (0.68, 0.0), (-0.35, 0.75)]
accent = polygon_curve("PremiumIQAccent", accent_points, cyan, depth=0.045, bevel=0.02, z=0.19)

ball = create_ball("PremiumBall", (0.0, 0.48, 0.78), pearl, navy, cyan, radius=0.83)

crown_points = [(-1.12, 0.0), (-0.98, 0.66), (-0.42, 0.3), (0.0, 0.92), (0.42, 0.3), (0.98, 0.66), (1.12, 0.0)]
crown = polygon_curve("PremiumCrown", crown_points, crown_material, depth=0.12, bevel=0.055, z=0.42)
crown.location.y = 3.02

camera_data = bpy.data.cameras.new("PremiumCamera")
camera = bpy.data.objects.new("PremiumCamera", camera_data)
bpy.context.collection.objects.link(camera)
camera.location = (0.0, -0.25, 13.2)
camera.data.type = "ORTHO"
camera.data.ortho_scale = 8.6
point_camera(camera)

world = scene.world or bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.008, 0.015, 0.025, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.18

def area_light(name, location, energy, color, size):
    data = bpy.data.lights.new(name=name, type="AREA")
    data.energy = energy
    data.color = color
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    point_camera(obj)
    bpy.context.collection.objects.link(obj)
    return obj


area_light("KeyLight", (4.5, 5.8, 8.0), 1000, (1.0, 0.87, 0.66), 4.5)
area_light("CyanRim", (-4.6, 1.2, 5.8), 850, (0.25, 0.78, 1.0), 3.2)
area_light("SoftFill", (0.0, -4.0, 4.2), 620, (0.72, 0.84, 1.0), 5.0)

configure_render(scene, camera, 768, 768)

variants = {
    "shield-premium-copper.webp": ((0.72, 0.26, 0.08), 0.9, 0.22),
    "shield-premium-silver.webp": ((0.66, 0.73, 0.78), 0.95, 0.16),
    "shield-premium-gold.webp": ((0.84, 0.55, 0.08), 0.96, 0.14),
    "shield-premium-chrome.webp": ((0.82, 0.9, 0.95), 1.0, 0.06),
    "shield-premium-carbon.webp": ((0.045, 0.055, 0.065), 0.48, 0.34),
}

for filename, (color, metallic, roughness) in variants.items():
    set_material(frame_material, color, metallic, roughness)
    set_material(crown_material, color, metallic, max(0.07, roughness - 0.02))
    render(scene, PUBLIC_DIR / filename)
    set_render_visibility(ball, False)
    set_render_visibility(crown, False)
    render(scene, PUBLIC_DIR / filename.replace(".webp", "-base.webp"))
    set_render_visibility(ball, True)
    set_render_visibility(crown, True)

set_material(frame_material, variants["shield-premium-gold.webp"][0], 0.96, 0.14)
set_material(crown_material, (0.7, 0.78, 0.84), 0.96, 0.22)
render(scene, PUBLIC_DIR / "shield-premium-crown-chrome.webp")

for obj in (backing, inner, frame, accent, ball):
    set_render_visibility(obj, False)
set_render_visibility(crown, True)
render(scene, PUBLIC_DIR / "crown-premium-chrome-overlay.webp")
set_material(crown_material, (0.9, 0.63, 0.13), 0.96, 0.16)
render(scene, PUBLIC_DIR / "crown-premium-gold-overlay.webp")
for obj in (backing, inner, frame, accent, ball, crown):
    set_render_visibility(obj, True)

kit_objects = [obj for obj in scene.objects if obj.get("premium_shield_kit")]
for obj in scene.objects:
    obj.select_set(False)
for obj in kit_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = backing
bpy.ops.export_scene.gltf(
    filepath=str(PUBLIC_DIR / "team-shield-premium-kit.glb"),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_animations=False,
    export_cameras=False,
    export_lights=False,
)

for obj in kit_objects:
    obj.hide_render = True

sprite_ball = create_ball("SpriteBall", (0.0, 0.0, 0.0), pearl, navy, cyan, radius=0.86, mark=False)

camera.data.ortho_scale = 3.25
camera.location = (0.0, 0.0, 13.0)
point_camera(camera, (0.0, 0.0, 0.0))
configure_render(scene, camera, 256, 256)
for index in range(8):
    angle = (index / 8) * math.tau
    sprite_ball.rotation_euler = (0.15, angle, angle * 0.28)
    render(scene, PUBLIC_DIR / f"ball-premium-frame-{index}.webp")

for child in list(sprite_ball.children):
    bpy.data.objects.remove(child, do_unlink=True)
bpy.data.objects.remove(sprite_ball, do_unlink=True)
for obj in kit_objects:
    obj.hide_render = False

camera.data.ortho_scale = 8.6
camera.location = (0.0, -0.25, 13.2)
point_camera(camera)
configure_render(scene, camera, 768, 768)

bpy.ops.wm.save_as_mainfile(filepath=str(ARTIFACT_DIR / "team-shield-premium-kit.blend"))
print(f"Generated premium shield assets in {PUBLIC_DIR}")
