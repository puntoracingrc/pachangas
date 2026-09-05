import * as THREE from "three";
import palettes from "./reward-rarity-visuals.json";

export type RewardRarity = keyof typeof palettes;
export const rewardRarityVisuals = palettes;

export function tintRewardMaterial(material: THREE.Material, rarity: RewardRarity) {
  const palette = palettes[rarity];
  if (!(material instanceof THREE.MeshStandardMaterial || material instanceof THREE.MeshBasicMaterial)) return;
  const name = material.name;
  if (name === "M_Blue_Sports") material.color.set(palette.body);
  if (name === "M_Blue_Dark" || name === "M_Card_Enamel") material.color.set(palette.dark);
  if (name === "M_Blue_Accent" || name === "M_Card_Edge") material.color.set(palette.accent);
  if (name === "M_Brushed_Aluminium") material.color.set(palette.trim);
  if (/Light|Glow|Particle/.test(name)) {
    material.color.set(palette.accent);
    if (material instanceof THREE.MeshStandardMaterial) {
      material.emissive.set(palette.accent);
      material.emissiveIntensity = palette.glow;
    }
  }
}

// One instanced draw call for all sparks; all effects subside before reading the card.
export function createRewardEffects(rarity: RewardRarity, reducedMotion: boolean) {
  const palette = palettes[rarity];
  const prestige = rarity === "legendary" ? 2 : rarity === "epic" ? 1 : 0;
  const duration = prestige ? 3.65 : 3;
  const group = new THREE.Group();
  const light = new THREE.PointLight(palette.accent, 0, 1.2, 2);
  light.position.set(0, 0.10, 0.02);
  group.add(light);
  const sparks = new THREE.InstancedMesh(
    new THREE.OctahedronGeometry(0.0028),
    new THREE.MeshBasicMaterial({ color: palette.accent, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending }),
    reducedMotion ? 0 : palette.particles,
  );
  sparks.frustumCulled = false;
  group.add(sparks);
  const rings: THREE.Mesh<THREE.TorusGeometry, THREE.MeshBasicMaterial>[] = [];
  for (let i = 0; i < (reducedMotion ? 0 : palette.rings); i++) {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.13, 0.0013, 6, 64), new THREE.MeshBasicMaterial({ color: palette.accent, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending }));
    ring.rotation.x = Math.PI / 2 + i * 0.25;
    ring.position.y = 0.04;
    group.add(ring);
    rings.push(ring);
  }
  // Faceted rays rise behind the prize, keeping its face unobstructed.
  const rays = new THREE.InstancedMesh(
    new THREE.OctahedronGeometry(1),
    new THREE.MeshBasicMaterial({ color: palette.accent, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending }),
    reducedMotion ? 0 : prestige * 10,
  );
  rays.frustumCulled = false;
  group.add(rays);
  const transform = new THREE.Object3D();
  return {
    group,
    update(time: number) {
      if (time >= duration && !reducedMotion) { group.visible = false; return; }
      if (reducedMotion) { light.intensity = 0.008 * palette.glow; return; }
      const burst = THREE.MathUtils.clamp((time - 1.35) / (duration - 1.35), 0, 1);
      const fade = Math.sin(burst * Math.PI);
      light.intensity = palette.glow * (0.01 + fade * 0.10);
      sparks.material.opacity = fade * 0.85;
      for (let i = 0; i < sparks.count; i++) {
        const angle = i * 2.399963 + burst * (i % 2 ? 1 : -1) * (0.65 + prestige * 1.2);
        const radius = 0.045 + burst * (0.055 + (i % 7) * 0.012 + prestige * 0.025);
        transform.position.set(Math.cos(angle) * radius, 0.05 + burst * (0.06 + (i % 11) * 0.02), Math.sin(angle) * radius);
        transform.rotation.set(angle, burst * 5, angle * 0.5);
        transform.scale.setScalar((0.65 + (i % 4) * 0.24) * fade * (1 + prestige * 0.2));
        transform.updateMatrix();
        sparks.setMatrixAt(i, transform.matrix);
      }
      sparks.instanceMatrix.needsUpdate = true;
      const flare = Math.sin(THREE.MathUtils.clamp((time - 1.7) / (duration - 1.7), 0, 1) * Math.PI);
      rays.material.opacity = flare * 0.30;
      for (let i = 0; i < rays.count; i++) {
        const angle = (i / rays.count) * Math.PI * 2 + burst * 0.24;
        const radius = 0.10 + burst * 0.065;
        transform.position.set(Math.sin(angle) * radius, 0.16 + Math.cos(angle) * radius, -0.075);
        transform.rotation.set(0, 0, -angle);
        transform.scale.set(0.002 + prestige * 0.001, flare * (0.035 + (i % 3) * 0.025), 0.0015);
        transform.updateMatrix();
        rays.setMatrixAt(i, transform.matrix);
      }
      rays.instanceMatrix.needsUpdate = true;
      rings.forEach((ring, i) => {
        const pulse = THREE.MathUtils.clamp((time - 1.45 - i * 0.18) / 1.25, 0, 1);
        ring.scale.setScalar(0.45 + pulse * 1.6);
        ring.material.opacity = Math.sin(pulse * Math.PI) * (0.45 + prestige * 0.08);
        if (prestige) {
          ring.rotation.z = time * (i % 2 ? 0.45 : -0.45);
          ring.position.y = 0.04 + pulse * i * 0.018;
        }
      });
    },
  };
}
