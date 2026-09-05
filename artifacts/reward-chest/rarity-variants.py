import bpy,json
from pathlib import Path
root=Path(__file__).resolve().parents[2]
palettes=json.loads((root/'app/reward-rarity-visuals.json').read_text())
output=root/'artifacts/reward-chest/rarities';output.mkdir(exist_ok=True)
def rgba(value):
 def linear(c):return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
 return tuple(linear(int(value[i:i+2],16)/255) for i in (1,3,5))+(1,)
for rarity,p in palettes.items():
 bpy.ops.wm.open_mainfile(filepath=str(root/'artifacts/reward-chest/reward-box-refined.blend'))
 for m in bpy.data.materials:
  color=None
  if m.name=='M_Blue_Sports':color=p['body']
  elif m.name in ['M_Blue_Dark','M_Card_Enamel']:color=p['dark']
  elif m.name in ['M_Blue_Accent','M_Card_Edge']:color=p['accent']
  elif m.name=='M_Brushed_Aluminium':color=p['trim']
  elif any(k in m.name for k in ['Light','Glow','Particle']):color=p['accent']
  if not color:continue
  m.diffuse_color=rgba(color)
  if m.use_nodes:
   for node in m.node_tree.nodes:
    if node.type=='BSDF_PRINCIPLED':
     node.inputs['Base Color'].default_value=rgba(color)
     if any(k in m.name for k in ['Light','Glow','Particle']):
      node.inputs['Emission Color'].default_value=rgba(color);node.inputs['Emission Strength'].default_value=p['glow']
    elif node.type=='EMISSION':node.inputs['Color'].default_value=rgba(color);node.inputs['Strength'].default_value=p['glow']
 s=bpy.context.scene;s.render.resolution_x=640;s.render.resolution_y=640;s.cycles.samples=16
 s.frame_set(0)
 bpy.ops.wm.save_as_mainfile(filepath=str(output/f'cofre-{rarity}.blend'))
 s.frame_set(28);s.render.filepath=str(output/f'cofre-{rarity}.png');bpy.ops.render.render(write_still=True)
