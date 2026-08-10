"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import * as THREE from "three";
import { DRACOLoader } from "three/examples/jsm/loaders/DRACOLoader.js";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import styles from "./reward-box-demo.module.css";

type RewardBoxDemoProps = {
  actionDisabled?: boolean;
  actionLabel?: string;
  description?: string;
  eyebrow?: string;
  onAction?: () => void;
  onClose: () => void;
  onSecondaryAction?: () => void;
  open: boolean;
  secondaryActionDisabled?: boolean;
  secondaryActionLabel?: string;
  title?: string;
};

type DemoPhase = "loading" | "ready" | "error";

const modelUrl = "/models/rewards/reward-box-blue.glb";

function fitCameraToBox(camera: THREE.PerspectiveCamera, controls: OrbitControls, box: THREE.Box3) {
  const verticalFov = THREE.MathUtils.degToRad(camera.fov);
  const horizontalFov = 2 * Math.atan(Math.tan(verticalFov / 2) * camera.aspect);
  const limitingFov = Math.min(verticalFov, horizontalFov);
  const radius = box.getBoundingSphere(new THREE.Sphere()).radius;
  const distance = Math.max(0.38, (radius / Math.sin(limitingFov / 2)) * 0.98);
  const viewDirection = new THREE.Vector3(1.08, 0.72, 1.24).normalize();

  camera.position.copy(viewDirection.multiplyScalar(distance));
  camera.near = Math.max(0.001, distance / 100);
  camera.far = Math.max(20, distance * 30);
  camera.updateProjectionMatrix();
  controls.target.set(0, 0, 0);
  controls.minDistance = distance * 0.62;
  controls.maxDistance = distance * 1.65;
  controls.update();
}

export function RewardBoxDemo({
  actionDisabled = false,
  actionLabel,
  description,
  eyebrow,
  onAction,
  onClose,
  onSecondaryAction,
  open,
  secondaryActionDisabled = false,
  secondaryActionLabel,
  title,
}: RewardBoxDemoProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const [phase, setPhase] = useState<DemoPhase>("loading");

  useEffect(() => {
    if (!open) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", closeOnEscape);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", closeOnEscape);
    };
  }, [onClose, open]);

  useEffect(() => {
    if (!open || !canvasRef.current || !stageRef.current) return;

    let disposed = false;
    let frameId = 0;
    let mixer: THREE.AnimationMixer | null = null;
    const clock = new THREE.Clock();
    const canvas = canvasRef.current;
    const stage = stageRef.current;
    setPhase("loading");

    const renderer = new THREE.WebGLRenderer({
      alpha: true,
      antialias: true,
      canvas,
      powerPreference: "high-performance",
    });
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.15;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(34, 1, 0.001, 100);
    const controls = new OrbitControls(camera, canvas);
    controls.enableDamping = true;
    controls.dampingFactor = 0.07;
    controls.enablePan = false;
    controls.rotateSpeed = 0.65;
    controls.zoomSpeed = 0.7;
    controls.touches = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_ROTATE };

    scene.add(new THREE.HemisphereLight(0xe8f8ff, 0x06120e, 2.35));
    const keyLight = new THREE.DirectionalLight(0xffffff, 4.1);
    keyLight.position.set(3.2, 4.8, 4.2);
    keyLight.castShadow = true;
    scene.add(keyLight);
    const rimLight = new THREE.DirectionalLight(0x4ba3ff, 3.2);
    rimLight.position.set(-4, 2.1, -2.8);
    scene.add(rimLight);
    const fillLight = new THREE.DirectionalLight(0xb7f452, 1.25);
    fillLight.position.set(1.2, -1.4, 3.6);
    scene.add(fillLight);

    const floor = new THREE.Mesh(
      new THREE.CircleGeometry(0.32, 72),
      new THREE.ShadowMaterial({ color: 0x000000, opacity: 0.34 }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -0.118;
    floor.receiveShadow = true;
    scene.add(floor);

    const resize = () => {
      const width = Math.max(1, stage.clientWidth);
      const height = Math.max(1, stage.clientHeight);
      const pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
      renderer.setPixelRatio(pixelRatio);
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    };
    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(stage);
    resize();

    const dracoLoader = new DRACOLoader();
    dracoLoader.setDecoderPath("/draco/");
    dracoLoader.setDecoderConfig({ type: "wasm" });
    const loader = new GLTFLoader();
    loader.setDRACOLoader(dracoLoader);

    loader.load(
      modelUrl,
      (gltf) => {
        if (disposed) return;
        const model = gltf.scene;
        model.traverse((child) => {
          if (!(child instanceof THREE.Mesh)) return;
          child.castShadow = true;
          child.receiveShadow = true;
          const materials = Array.isArray(child.material) ? child.material : [child.material];
          for (const material of materials) {
            if ("envMapIntensity" in material) material.envMapIntensity = 1.05;
          }
        });
        scene.add(model);

        const clip = gltf.animations[0];
        let framingBox = new THREE.Box3().setFromObject(model);
        if (clip) {
          const modelMixer = new THREE.AnimationMixer(model);
          mixer = modelMixer;
          modelMixer.setTime(clip.duration);
          model.updateMatrixWorld(true);
          framingBox = framingBox.union(new THREE.Box3().setFromObject(model));
          modelMixer.setTime(0);
        }

        const center = framingBox.getCenter(new THREE.Vector3());
        model.position.sub(center);
        model.updateMatrixWorld(true);
        framingBox = new THREE.Box3().setFromObject(model);
        fitCameraToBox(camera, controls, framingBox);
        floor.position.y = framingBox.min.y - 0.002;
        floor.scale.setScalar(Math.max(1, framingBox.getSize(new THREE.Vector3()).x / 0.26));

        if (clip) {
          const modelMixer = mixer as THREE.AnimationMixer;
          const action = modelMixer.clipAction(clip);
          action.setLoop(THREE.LoopOnce, 1);
          action.clampWhenFinished = true;
          if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            modelMixer.setTime(clip.duration);
          } else {
            action.reset().play();
          }
        }
        setPhase("ready");
      },
      undefined,
      () => {
        if (!disposed) setPhase("error");
      },
    );

    const render = () => {
      if (disposed) return;
      frameId = window.requestAnimationFrame(render);
      const delta = Math.min(clock.getDelta(), 0.05);
      mixer?.update(delta);
      controls.update();
      renderer.render(scene, camera);
    };
    render();

    return () => {
      disposed = true;
      window.cancelAnimationFrame(frameId);
      resizeObserver.disconnect();
      controls.dispose();
      dracoLoader.dispose();
      scene.traverse((object) => {
        if (!(object instanceof THREE.Mesh)) return;
        object.geometry.dispose();
        const materials = Array.isArray(object.material) ? object.material : [object.material];
        for (const material of materials) material.dispose();
      });
      renderer.dispose();
    };
  }, [open]);

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div className={styles.backdrop} role="dialog" aria-modal="true" aria-label={title ?? "Animación de logro de prueba"}>
      <div className={styles.stage} ref={stageRef}>
        <canvas className={styles.canvas} ref={canvasRef} aria-label="Maletín de recompensa animado en tres dimensiones" />
        {phase === "loading" ? <div className={styles.status} role="status">Preparando animación...</div> : null}
        {phase === "error" ? <div className={`${styles.status} ${styles.error}`} role="alert">No se pudo cargar la animación.</div> : null}
        <button className={styles.close} ref={closeButtonRef} type="button" onClick={onClose} aria-label="Cerrar animación">
          <span aria-hidden="true">×</span>
        </button>
        {title || description || actionLabel ? (
          <div className={styles.revealPanel}>
            {eyebrow ? <span>{eyebrow}</span> : null}
            {title ? <strong>{title}</strong> : null}
            {description ? <p>{description}</p> : null}
            {actionLabel && onAction ? (
              <div className={styles.revealActions}>
                <button type="button" disabled={actionDisabled} onClick={onAction}>{actionLabel}</button>
                {secondaryActionLabel && onSecondaryAction ? (
                  <button className={styles.secondaryAction} type="button" disabled={secondaryActionDisabled} onClick={onSecondaryAction}>
                    {secondaryActionLabel}
                  </button>
                ) : null}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
    </div>,
    document.body,
  );
}
