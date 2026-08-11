from pathlib import Path
import math

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE_OUTPUT = ROOT / "artifacts" / "premium-art-pack-v1" / "source-renders"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block)


def material(name, color, metallic=0.8, roughness=0.24):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1)
    value.use_nodes = True
    shader = next((node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if shader is None:
        raise RuntimeError("Blender did not create a Principled BSDF node")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return value


def polygon(name, points, depth, bevel, surface, z=0):
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata([(x, y, z) for x, y in points], [], [list(range(len(points)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(surface)
    solidify = obj.modifiers.new("Depth", "SOLIDIFY")
    solidify.thickness = depth
    solidify.offset = 0
    edge = obj.modifiers.new("Soft edges", "BEVEL")
    edge.width = bevel
    edge.segments = 4
    return obj


def cube(name, location, scale, surface, bevel=0.08):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(surface)
    edge = obj.modifiers.new("Soft edges", "BEVEL")
    edge.width = bevel
    edge.segments = 5
    return obj


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def configure_scene(asset_name, ortho_scale=5.7):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.filepath = str(SOURCE_OUTPUT / asset_name)
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world.color = (0.008, 0.012, 0.01)

    bpy.ops.object.camera_add(location=(0, -5.8, 8.4))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = ortho_scale
    look_at(camera, (0, 0, 0.2))
    scene.camera = camera

    for name, location, energy, size, color in [
        ("Key", (-4, -3, 7), 1150, 4.2, (1.0, 0.82, 0.55)),
        ("Rim", (4, 1, 5), 900, 3.0, (0.45, 0.92, 1.0)),
        ("Fill", (0, -1, 2), 500, 5.0, (0.72, 0.82, 1.0)),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        look_at(light, (0, 0, 0))


def render_elite_crown():
    clear_scene()
    gold = material("Satin Gold", (0.82, 0.48, 0.08), metallic=0.92, roughness=0.2)
    dark_gold = material("Dark Gold", (0.32, 0.12, 0.025), metallic=0.9, roughness=0.27)
    cyan = material("IQ Gem", (0.05, 0.72, 0.8), metallic=0.28, roughness=0.12)
    crown_points = [
        (-2.25, -0.75), (-2.05, 1.18), (-1.1, 0.35), (0, 1.72),
        (1.1, 0.35), (2.05, 1.18), (2.25, -0.75),
    ]
    polygon("Elite Crown", crown_points, 0.22, 0.1, gold, z=0.04)
    cube("Crown Base", (0, -0.88, 0.04), (2.25, 0.22, 0.18), dark_gold, bevel=0.1)
    cube("Crown Lip", (0, -0.56, 0.12), (2.12, 0.09, 0.13), gold, bevel=0.07)
    for x, y, scale in [(-2.05, 1.18, 0.15), (0, 1.72, 0.2), (2.05, 1.18, 0.15)]:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=scale, location=(x, y, 0.24))
        bpy.context.object.data.materials.append(cyan)
    configure_scene("crown-elite-blender.png", ortho_scale=6.0)
    bpy.ops.render.render(write_still=True)


def star_points(outer=1.7, inner=0.72, count=8):
    points = []
    for index in range(count * 2):
        radius = outer if index % 2 == 0 else inner
        angle = math.pi / 2 + index * math.pi / count
        points.append((math.cos(angle) * radius, math.sin(angle) * radius))
    return points


def render_star_medallion():
    clear_scene()
    silver = material("Brushed Silver", (0.62, 0.69, 0.7), metallic=0.95, roughness=0.24)
    navy = material("Navy Enamel", (0.015, 0.07, 0.14), metallic=0.48, roughness=0.16)
    cyan = material("Future Cyan", (0.04, 0.76, 0.82), metallic=0.42, roughness=0.12)

    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=2.25, depth=0.24, location=(0, 0, 0))
    coin = bpy.context.object
    coin.data.materials.append(silver)
    edge = coin.modifiers.new("Medallion bevel", "BEVEL")
    edge.width = 0.12
    edge.segments = 5

    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=1.91, depth=0.29, location=(0, 0, 0.08))
    inset = bpy.context.object
    inset.data.materials.append(navy)
    edge = inset.modifiers.new("Enamel bevel", "BEVEL")
    edge.width = 0.08
    edge.segments = 4

    polygon("Future Star", star_points(), 0.2, 0.08, cyan, z=0.23)
    bpy.ops.mesh.primitive_torus_add(major_radius=2.05, minor_radius=0.055, major_segments=96, minor_segments=12, location=(0, 0, 0.2))
    bpy.context.object.data.materials.append(cyan)
    configure_scene("star-medallion-blender.png", ortho_scale=5.8)
    bpy.ops.render.render(write_still=True)


def main():
    SOURCE_OUTPUT.mkdir(parents=True, exist_ok=True)
    render_elite_crown()
    render_star_medallion()


if __name__ == "__main__":
    main()
