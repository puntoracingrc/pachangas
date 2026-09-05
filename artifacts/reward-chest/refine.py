import bpy,math
from pathlib import Path
from mathutils import Vector,Quaternion
root=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(root/'artifacts/reward-chest/recovered.blend'))
s=bpy.context.scene
animated=[o for o in bpy.data.objects if o.animation_data and o.animation_data.action]
samples={o.name:[] for o in animated}
# Preserve the authored geometry and choreography; add anticipation, eased opening and settling.
anchors=[(0,0),(12,12),(22,22),(48,36),(72,48),(90,48)]
for f in range(91):
 for (a,x),(b,y) in zip(anchors,anchors[1:]):
  if a<=f<=b:
   u=(f-a)/(b-a);u=u*u*(3-2*u);old=x+(y-x)*u;break
 s.frame_set(int(old),subframe=old-int(old))
 for o in animated:
  loc=o.location.copy();rot=o.rotation_quaternion.copy();scale=o.scale.copy()
  if o.name=='Box_Assembly':
   loc=Vector((0,0,0));rot=Quaternion((1,0,0,0));scale=Vector((1,1,1))
  if o.name=='Box_Lid' and f>=48:
   settle=math.exp(-(f-48)/9)*math.sin((f-48)*math.pi/14)*math.radians(2)
   rot=Quaternion((1,0,0),math.radians(-105)+settle)
  if o.name=='Reward_Card' and f>=72:
   loc.z+=.003*math.exp(-(f-72)/6)*math.sin((f-72)*math.pi/12)
  samples[o.name].append((loc,rot,scale))
for o in animated:o.animation_data_clear()
for o in animated:
 o.rotation_mode='QUATERNION'
 for f,(loc,rot,scale) in enumerate(samples[o.name]):
  o.location=loc;o.rotation_quaternion=rot;o.scale=scale
  for prop in ['location','rotation_quaternion','scale']:o.keyframe_insert(data_path=prop,frame=f,group=o.name)
 o.animation_data.action.name='Reward_Reveal_'+o.name
s.render.fps=30;s.frame_start=0;s.frame_end=90
s.world.color=(.015,.025,.035)
s.camera.location=(.025,-1,.53);s.camera.rotation_euler=(Vector((0,0,.135))-s.camera.location).to_track_quat('-Z','Y').to_euler()
s.camera.data.ortho_scale=.60
for a in bpy.data.screens:
 for area in a.areas:
  if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
s.frame_set(0)
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
 if o.type not in {'CAMERA','LIGHT'}:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(root/'artifacts/reward-chest/reward-box-refined.glb'),use_selection=True,export_format='GLB',export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_frame_range=True,export_draco_mesh_compression_enable=True,export_draco_mesh_compression_level=6)
bpy.ops.wm.save_as_mainfile(filepath=str(root/'artifacts/reward-chest/reward-box-refined.blend'))
for f,label in [(0,'closed'),(40,'opening'),(90,'open')]:
 s.frame_set(f);s.render.filepath=str(root/f'artifacts/reward-chest/refined-{label}.png');bpy.ops.render.render(write_still=True)
