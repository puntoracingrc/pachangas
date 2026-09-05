import bpy,json
from mathutils import Vector
from pathlib import Path
root=Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(root/'public/models/rewards/reward-box-blue.glb'))
s=bpy.context.scene
for f in [0,12,24,36,48]:
 s.frame_set(f)
 print('POSE',f,[(n,tuple(bpy.data.objects[n].location),tuple(bpy.data.objects[n].rotation_euler),tuple(bpy.data.objects[n].rotation_quaternion),tuple(bpy.data.objects[n].scale)) for n in ['Box_Assembly','Box_Lid','Front_Latch','Reward_Card']])
s.render.engine='CYCLES';s.cycles.samples=24
s.render.resolution_x=850;s.render.resolution_y=850;s.render.resolution_percentage=100
s.world.color=(0.12,0.12,0.12)
bpy.ops.object.camera_add(location=(.10,-.95,.55));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.14))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=.65;s.camera=cam
for loc,power,size in [((.3,-.4,.8),35,.5),((-.4,-.1,.5),22,.4),((0,.4,.6),40,.3)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,.1))-o.location).to_track_quat('-Z','Y').to_euler()
s.frame_set(48);s.render.filepath=str(root/'artifacts/reward-chest/original-open.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(root/'artifacts/reward-chest/recovered.blend'))
