"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import type { PremiumTilt } from "./use-premium-motion";

export type PremiumFrameMaterial = "carbon" | "chrome" | "copper" | "gold" | "silver";
export type PremiumCrownMaterial = "chrome" | "gold" | "none";

type MaterialPreset = { color: number; metalness: number; roughness: number };

const MODEL_URL = "/team-shield-premium-3d/team-shield-premium-kit.glb";
const FRAME_MATERIALS: Record<PremiumFrameMaterial, MaterialPreset> = {
  carbon: { color: 0x151a1f, metalness: 0.48, roughness: 0.34 },
  chrome: { color: 0xc9e2ec, metalness: 1, roughness: 0.08 },
  copper: { color: 0xb84a16, metalness: 0.9, roughness: 0.22 },
  gold: { color: 0xd98e18, metalness: 0.96, roughness: 0.14 },
  silver: { color: 0xa8bbc7, metalness: 0.95, roughness: 0.16 },
};
const CROWN_MATERIALS: Record<Exclude<PremiumCrownMaterial, "none">, MaterialPreset> = {
  chrome: { color: 0xb4c8d4, metalness: 0.96, roughness: 0.22 },
  gold: { color: 0xe5a129, metalness: 0.96, roughness: 0.16 },
};

function replaceMaterial(mesh: THREE.Mesh, preset: MaterialPreset) {
  const previous = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
  const next = previous.map((material) => {
    const clone = material.clone();
    if (clone instanceof THREE.MeshStandardMaterial) {
      clone.color.setHex(preset.color);
      clone.metalness = preset.metalness;
      clone.roughness = preset.roughness;
      clone.needsUpdate = true;
    }
    return clone;
  });
  mesh.material = Array.isArray(mesh.material) ? next : next[0];
  previous.forEach((material) => material.dispose());
}

export function PremiumShield3D({
  crown,
  material,
  reduced,
  tilt,
}: {
  crown: PremiumCrownMaterial;
  material: PremiumFrameMaterial;
  reduced: boolean;
  tilt: PremiumTilt;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const modelRef = useRef<THREE.Group | null>(null);
  const drawRef = useRef<(() => void) | null>(null);
  const crownRef = useRef(crown);
  const materialRef = useRef(material);
  const tiltRef = useRef(tilt);
  const [phase, setPhase] = useState<"error" | "loading" | "ready">("loading");

  useEffect(() => {
    crownRef.current = crown;
    materialRef.current = material;
    const model = modelRef.current;
    if (!model) return;
    model.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      if (child.name.includes("PremiumFrame")) replaceMaterial(child, FRAME_MATERIALS[material]);
      if (child.name.includes("PremiumCrown")) {
        child.visible = crown !== "none";
        if (crown !== "none") replaceMaterial(child, CROWN_MATERIALS[crown]);
      }
    });
    drawRef.current?.();
  }, [crown, material]);

  useEffect(() => {
    tiltRef.current = tilt;
  }, [tilt]);

  useEffect(() => {
    if (!canvasRef.current || !stageRef.current) return;
    let disposed = false;
    let canvasChecked = false;
    let frameId = 0;
    let renderedFrames = 0;
    const canvas = canvasRef.current;
    const stage = stageRef.current;
    const renderer = new THREE.WebGLRenderer({
      alpha: true,
      antialias: true,
      canvas,
      powerPreference: "high-performance",
      preserveDrawingBuffer: true,
    });
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.18;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(31, 1, 0.01, 100);
    scene.add(new THREE.HemisphereLight(0xeaf8ff, 0x07131c, 2.7));
    const key = new THREE.DirectionalLight(0xfff2d7, 4.4);
    key.position.set(4.4, 5.2, 7.2);
    scene.add(key);
    const cyan = new THREE.DirectionalLight(0x54d8ff, 3.1);
    cyan.position.set(-4.8, 1.2, 5.4);
    scene.add(cyan);
    const fill = new THREE.DirectionalLight(0xffffff, 1.6);
    fill.position.set(0, -4, 5);
    scene.add(fill);

    const modelRoot = new THREE.Group();
    scene.add(modelRoot);
    modelRef.current = modelRoot;

    const resize = () => {
      const width = Math.max(1, stage.clientWidth);
      const height = Math.max(1, stage.clientHeight);
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, window.matchMedia("(pointer: coarse)").matches ? 1.5 : 2));
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      drawRef.current?.();
    };

    const draw = () => {
      if (disposed) return;
      const targetX = THREE.MathUtils.degToRad(reduced ? 0 : tiltRef.current.x);
      const targetY = THREE.MathUtils.degToRad(reduced ? 0 : tiltRef.current.y);
      modelRoot.rotation.x = reduced ? 0 : THREE.MathUtils.lerp(modelRoot.rotation.x, targetX, 0.14);
      modelRoot.rotation.y = reduced ? 0 : THREE.MathUtils.lerp(modelRoot.rotation.y, targetY, 0.14);
      renderer.render(scene, camera);
      renderedFrames += 1;
      canvas.dataset.renderedFrames = String(renderedFrames);
      if (!canvasChecked && modelRoot.children.length > 0) {
        canvasChecked = true;
        canvas.dataset.canvasNonblank = canvas.toDataURL("image/png").length > 2000 ? "true" : "false";
      }
    };
    drawRef.current = draw;

    const animate = () => {
      if (disposed) return;
      draw();
      frameId = window.requestAnimationFrame(animate);
    };

    const observer = new ResizeObserver(resize);
    observer.observe(stage);
    resize();

    const loader = new GLTFLoader();
    loader.load(
      MODEL_URL,
      (gltf) => {
        if (disposed) return;
        const model = gltf.scene;
        model.traverse((child) => {
          if (!(child instanceof THREE.Mesh)) return;
          child.castShadow = false;
          child.receiveShadow = false;
          if (child.name.includes("PremiumFrame")) replaceMaterial(child, FRAME_MATERIALS[materialRef.current]);
          if (child.name.includes("PremiumCrown")) {
            child.visible = crownRef.current !== "none";
            if (crownRef.current !== "none") replaceMaterial(child, CROWN_MATERIALS[crownRef.current]);
          }
        });
        // glTF convierte el eje Z vertical de Blender a Y; el kit necesita volver a mirar a cámara.
        model.rotation.x = Math.PI / 2;
        model.updateMatrixWorld(true);
        const box = new THREE.Box3().setFromObject(model);
        const center = box.getCenter(new THREE.Vector3());
        model.position.sub(center);
        modelRoot.add(model);
        const radius = new THREE.Box3().setFromObject(model).getBoundingSphere(new THREE.Sphere()).radius;
        const distance = (radius / Math.sin(THREE.MathUtils.degToRad(camera.fov) / 2)) * 1.08;
        camera.position.set(0, -0.18, distance);
        camera.lookAt(0, 0, 0);
        camera.near = Math.max(0.01, distance / 100);
        camera.far = distance * 8;
        camera.updateProjectionMatrix();
        setPhase("ready");
        draw();
      },
      undefined,
      () => {
        if (!disposed) setPhase("error");
      },
    );

    if (!reduced) animate();

    return () => {
      disposed = true;
      window.cancelAnimationFrame(frameId);
      observer.disconnect();
      modelRef.current = null;
      drawRef.current = null;
      scene.traverse((object) => {
        if (!(object instanceof THREE.Mesh)) return;
        object.geometry.dispose();
        const materials = Array.isArray(object.material) ? object.material : [object.material];
        materials.forEach((entry) => entry.dispose());
      });
      renderer.dispose();
    };
  }, [reduced]);

  useEffect(() => {
    if (reduced) drawRef.current?.();
  }, [reduced, tilt]);

  return (
    <div className="premium-three-stage" data-phase={phase} ref={stageRef}>
      <canvas
        aria-label="Escudo premium tridimensional"
        data-pipeline="C"
        data-reduced-motion={reduced}
        ref={canvasRef}
      />
      {phase === "loading" ? <span role="status">Cargando modelo 3D</span> : null}
      {phase === "error" ? <span role="alert">Vista 3D no disponible</span> : null}
    </div>
  );
}
