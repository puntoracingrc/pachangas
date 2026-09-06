"use client";

import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { createPortal } from "react-dom";
import * as THREE from "three";
import { DRACOLoader } from "three/examples/jsm/loaders/DRACOLoader.js";
import { GLTFLoader, type GLTF } from "three/examples/jsm/loaders/GLTFLoader.js";
import { CSS3DObject, CSS3DRenderer } from "three/examples/jsm/renderers/CSS3DRenderer.js";
import { createRewardEffects, tintRewardMaterial, rewardRarityVisuals, type RewardRarity } from "./reward-rarity-effects";
import { createRewardAudio, rewardSoundMuted, unlockRewardAudio } from "./reward-box-audio";
import styles from "./reward-box-demo.module.css";

type RewardBoxDemoProps = {
  pendingChests?: { id: string; rarity: RewardRarity }[];
  currentChestId?: string;
  onSelectChest?: (id: string) => void;
  onRevealComplete?: () => void;
  rarity?: RewardRarity;
  continueLabel?: string;
  onContinue?: () => void;
  remainingCount?: number;
  actionDisabled?: boolean;
  actionLabel?: string;
  description?: string;
  rewardPreview?: ReactNode;
  achievementLabel?: string;
  achievementDescription?: string;
  eyebrow?: string;
  onAction?: () => void;
  onClose: () => void;
  onSecondaryAction?: () => void;
  open: boolean;
  secondaryActionProminent?: boolean;
  secondaryActionDisabled?: boolean;
  secondaryActionLabel?: string;
  title?: string;
};

type DemoPhase = "loading" | "ready" | "error";

const modelUrl = "/models/rewards/reward-box-refined.glb";

// Decode once per page, then give each reveal independently disposable resources.
let cachedRewardModel: Promise<GLTF> | null = null;
function loadRewardModel() {
  if (!cachedRewardModel) {
    const draco = new DRACOLoader();
    draco.setDecoderPath("/draco/");
    draco.setDecoderConfig({ type: "wasm" });
    draco.setWorkerLimit(1);
    const loader = new GLTFLoader();
    loader.setDRACOLoader(draco);
    cachedRewardModel = new Promise<GLTF>((resolve, reject) => {
      const timeout = window.setTimeout(() => reject(new Error("Reward model loading timed out")), 15000);
      loader.load(modelUrl, (model) => { clearTimeout(timeout); resolve(model); }, undefined, (error) => { clearTimeout(timeout); reject(error); });
    }).catch((error) => { cachedRewardModel = null; throw error; }).finally(() => draco.dispose());
  }
  return cachedRewardModel;
}

function fitCameraToBox(camera: THREE.PerspectiveCamera, box: THREE.Box3) {
  const verticalFov = THREE.MathUtils.degToRad(camera.fov);
  const horizontalFov = 2 * Math.atan(Math.tan(verticalFov / 2) * camera.aspect);
  const limitingFov = Math.min(verticalFov, horizontalFov);
  const radius = box.getBoundingSphere(new THREE.Sphere()).radius;
  const distance = Math.max(0.38, (radius / Math.sin(limitingFov / 2)) * 1.10);
  const viewDirection = new THREE.Vector3(0.035, 0.39, 1).normalize();

  camera.position.copy(viewDirection.multiplyScalar(distance));
  camera.near = Math.max(0.001, distance / 100);
  camera.far = Math.max(20, distance * 30);
  camera.updateProjectionMatrix();
  camera.lookAt(0, 0, 0);
}

export function RewardBoxDemo({
  pendingChests,
  currentChestId,
  onSelectChest,
  onRevealComplete,
  rarity = "rare",
  continueLabel,
  onContinue,
  remainingCount,
  actionDisabled = false,
  actionLabel,
  description,
  rewardPreview,
  achievementLabel,
  achievementDescription,
  eyebrow,
  onAction,
  onClose,
  onSecondaryAction,
  open,
  secondaryActionProminent = false,
  secondaryActionDisabled = false,
  secondaryActionLabel,
  title,
}: RewardBoxDemoProps) {
  const revealCallbackRef = useRef(onRevealComplete);
  useEffect(() => { revealCallbackRef.current = onRevealComplete; }, [onRevealComplete]);
  const palette = rewardRarityVisuals[rarity];
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const [previewHost, setPreviewHost] = useState<HTMLDivElement | null>(null);
  const faceContentRef = useRef<HTMLDivElement | null>(null);
  const rewardTextRef = useRef({ title, description, eyebrow, achievementLabel, achievementDescription });
  const audioRef = useRef<ReturnType<typeof createRewardAudio> | null>(null);
  const [muted, setMuted] = useState(rewardSoundMuted);
  useEffect(() => {
    document.addEventListener("pointerdown", unlockRewardAudio, true);
    document.addEventListener("keydown", unlockRewardAudio, true);
    return () => {
      document.removeEventListener("pointerdown", unlockRewardAudio, true);
      document.removeEventListener("keydown", unlockRewardAudio, true);
    };
  }, []);
  const [leaving, setLeaving] = useState(false);
  const transitionTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => {
    if (transitionTimerRef.current !== null) clearTimeout(transitionTimerRef.current);
  }, []);
  const transitionTo = (action: () => void) => {
    if (transitionTimerRef.current !== null || actionDisabled) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { action(); return; }
    setLeaving(true);
    transitionTimerRef.current = setTimeout(() => {
      transitionTimerRef.current = null;
      setLeaving(false);
      action();
    }, 280);
  };
  const [revealed, setRevealed] = useState(false);
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [phase, setPhase] = useState<DemoPhase>("loading");

  useEffect(() => {
    rewardTextRef.current = { title, description, eyebrow, achievementLabel, achievementDescription };
    const face = faceContentRef.current;
    if (!face) return;
    face.querySelector("[data-achievement]")!.textContent = achievementLabel ? `Conseguido por: ${achievementLabel}` : "";
    face.querySelector("[data-achievement-description]")!.textContent = achievementDescription ?? "";
    face.querySelector("h2")!.textContent = title ?? "Tu recompensa";
    face.querySelector("p")!.textContent = description ?? "Consulta el detalle de tu premio en tus logros.";
    face.querySelector("[data-reward-eyebrow]")!.textContent = eyebrow ?? "Pachangas IQ";
  }, [title, description, eyebrow, achievementLabel, achievementDescription, phase]);

  useEffect(() => {
    if (!open) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus({ preventScroll: true });
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
    if (!open || !stageRef.current) return;

    let disposed = false;
    let revealReported = false;
    let frameId = 0;
    let mixer: THREE.AnimationMixer | null = null;
    let framingBox: THREE.Box3 | null = null;
    const clock = new THREE.Clock();
    let rewardCard: THREE.Object3D | undefined;
    let revealDuration = Infinity;
    let revealElapsed = 0;
    let entranceElapsed = 0;
    let approachOrigin: THREE.Vector3 | null = null;
    let approachRotation: THREE.Quaternion | null = null;
    const destination = new THREE.Vector3();
    const forward = new THREE.Vector3();
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const stage = stageRef.current;
    const canvas = document.createElement("canvas");
    canvas.className = styles.canvas;
    canvas.setAttribute("aria-label", "Maletín de recompensa animado en tres dimensiones");
    stage.prepend(canvas);
    setPhase("loading");
    setRevealed(false);

    let renderer: THREE.WebGLRenderer;
    try { renderer = new THREE.WebGLRenderer({
      alpha: true,
      antialias: true,
      canvas,
      powerPreference: "high-performance",
    }); } catch (error) {
      console.error("Reward renderer initialization failed", error);
      canvas.remove();
      // Report a failed external WebGL initialization so the retry UI is available.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setPhase("error");
      return;
    }
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.15;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    const textRenderer = new CSS3DRenderer();
    textRenderer.domElement.className = styles.rewardTextLayer;
    stage.appendChild(textRenderer.domElement);

    const scene = new THREE.Scene();
    const effects = createRewardEffects(rarity, reducedMotion);
    const sound = createRewardAudio(rarity, reducedMotion);
    audioRef.current = sound;
    const camera = new THREE.PerspectiveCamera(34, 1, 0.001, 100);

    scene.add(new THREE.HemisphereLight(0xe8f8ff, 0x06120e, 2.35));
    const keyLight = new THREE.DirectionalLight(0xffffff, 4.1);
    keyLight.position.set(3.2, 4.8, 4.2);
    keyLight.castShadow = true;
    scene.add(keyLight);
    const rimLight = new THREE.DirectionalLight(palette.accent, 2.4 + palette.glow);
    rimLight.position.set(-4, 2.1, -2.8);
    scene.add(rimLight);
    const fillLight = new THREE.DirectionalLight(palette.trim, 1.25);
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
      textRenderer.setSize(width, height);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      if (framingBox) fitCameraToBox(camera, framingBox);
    };
    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(stage);
    resize();

    loadRewardModel().then((gltf) => {
        if (disposed) return;
        const model = gltf.scene.clone(true);
        model.traverse((child) => {
          if (!(child instanceof THREE.Mesh)) return;
          child.geometry = child.geometry.clone();
          child.material = Array.isArray(child.material) ? child.material.map((material) => material.clone()) : child.material.clone();
          if (child.name.startsWith("Particle_Blue")) child.visible = false;
          child.castShadow = true;
          child.receiveShadow = true;
          const materials = Array.isArray(child.material) ? child.material : [child.material];
          for (const material of materials) {
            tintRewardMaterial(material, rarity);
            if ("envMapIntensity" in material) material.envMapIntensity = 1.05;
          }
        });
        // Center a wrapper so animation tracks cannot overwrite the framing offset.
        const centeredModel = new THREE.Group();
        centeredModel.add(model);
        scene.add(centeredModel);
        rewardCard = model.getObjectByName("Reward_Card");
        if (rewardCard) {
          // Live HTML follows the actual 3D card, keeping reward copy sharp and accessible.
          for (const child of rewardCard.children) child.visible = false;
          const face = document.createElement("div");
          face.className = styles.rewardFace;
          face.style.setProperty("--reward-accent", palette.accent);
          face.style.setProperty("--reward-dark", palette.dark);
          face.setAttribute("aria-live", "polite");
          const badge = document.createElement("strong");
          badge.className = styles.rarityBadge;
          badge.textContent = palette.label;
          const label = document.createElement("span");
          label.dataset.rewardEyebrow = "true";
          const heading = document.createElement("h2");
          const detail = document.createElement("p");
          label.textContent = rewardTextRef.current.eyebrow ?? "Pachangas IQ";
          heading.textContent = rewardTextRef.current.title ?? "Tu recompensa";
          detail.textContent = rewardTextRef.current.description ?? "Consulta el detalle de tu premio en tus logros.";
          const preview = document.createElement("div");
          preview.className = styles.rewardPreview;
          const reason = document.createElement("small");
          reason.dataset.achievement = "true";
          reason.textContent = rewardTextRef.current.achievementLabel ? `Conseguido por: ${rewardTextRef.current.achievementLabel}` : "";
          const explanation = document.createElement("div");
          explanation.dataset.achievementDescription = "true";
          explanation.className = styles.achievementDescription;
          explanation.textContent = rewardTextRef.current.achievementDescription ?? "";
          face.append(badge, label, preview, heading, detail, reason, explanation);
          setPreviewHost(preview);
          faceContentRef.current = face;
          const faceObject = new CSS3DObject(face);
          faceObject.position.z = 0.004;
          faceObject.scale.setScalar(0.092 / 700);
          rewardCard.add(faceObject);
          // CSS3D is composited above WebGL; reveal it only once clear of the lid.
          face.style.visibility = "hidden";
        }
        const clip = gltf.animations[0];
        revealDuration = clip?.duration ?? 0;
        framingBox = new THREE.Box3().setFromObject(model);
        if (clip) {
          const modelMixer = new THREE.AnimationMixer(model);
          mixer = modelMixer;
          const action = modelMixer.clipAction(clip);
          action.setLoop(THREE.LoopOnce, 1);
          action.clampWhenFinished = true;
          action.play();
          // Sample the active action, including the moving lid, card and particles.
          for (let sample = 0; sample <= 60; sample += 1) {
            action.reset().play();
            modelMixer.setTime((clip.duration * sample) / 60);
            model.updateMatrixWorld(true);
            framingBox.union(new THREE.Box3().setFromObject(model));
          }
          action.reset().play();
          modelMixer.setTime(0);
          if (reducedMotion) {
            modelMixer.setTime(clip.duration);
          }
        }
        const center = framingBox.getCenter(new THREE.Vector3());
        centeredModel.position.sub(center);
        framingBox.translate(center.negate());
        fitCameraToBox(camera, framingBox);
        floor.position.y = framingBox.min.y - 0.002;
        floor.scale.setScalar(Math.max(1, framingBox.getSize(new THREE.Vector3()).x / 0.26));

        centeredModel.add(effects.group);
        revealElapsed = 0;
        setPhase("ready");
      }).catch((error) => {
        console.error("Reward reveal failed", error);
        if (!disposed) setPhase("error");
      });

    const render = () => {
      if (disposed) return;
      frameId = window.requestAnimationFrame(render);
      const delta = Math.min(clock.getDelta(), 0.05);
      if (Number.isFinite(revealDuration)) entranceElapsed += delta;
      const animationDelta = reducedMotion || entranceElapsed >= 0.35 ? delta : 0;
      if (Number.isFinite(revealDuration)) revealElapsed += animationDelta;
      mixer?.update(animationDelta);
      effects.update(revealElapsed);
      if (Number.isFinite(revealDuration)) sound.update(revealElapsed);
      if (rewardCard && (reducedMotion || revealElapsed >= revealDuration)) {
        if (!approachOrigin) {
          // Stop advancing the authored clip before taking over its card transform.
          mixer = null;
          scene.attach(rewardCard);
          approachOrigin = rewardCard.position.clone();
          approachRotation = rewardCard.quaternion.clone();
          if (faceContentRef.current) faceContentRef.current.style.visibility = "visible";
        }
        const progress = reducedMotion ? 1 : THREE.MathUtils.clamp((revealElapsed - revealDuration) / 1.25, 0, 1);
        const eased = progress * progress * (3 - 2 * progress);
        if (progress === 1 && !revealReported) {
          revealReported = true;
          setRevealed(true);
          revealCallbackRef.current?.();
        }
        const halfFov = Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2);
        // Fit the readable card into 78% of the available width AND height.
        const distance = Math.max(0.14 / (2 * halfFov * 0.78), 0.10 / (2 * halfFov * camera.aspect * 0.78));
        camera.getWorldDirection(forward);
        destination.copy(camera.position).addScaledVector(forward, distance);
        rewardCard.position.lerpVectors(approachOrigin, destination, eased);
        rewardCard.quaternion.slerpQuaternions(approachRotation!, camera.quaternion, eased);
      }
      renderer.render(scene, camera);
      textRenderer.render(scene, camera);
    };
    render();

    return () => {
      disposed = true;
      sound.dispose();
      audioRef.current = null;
      window.cancelAnimationFrame(frameId);
      resizeObserver.disconnect();
      textRenderer.domElement.remove();
      faceContentRef.current = null;

      scene.traverse((object) => {
        if (!(object instanceof THREE.Mesh)) return;
        object.geometry.dispose();
        const materials = Array.isArray(object.material) ? object.material : [object.material];
        for (const material of materials) material.dispose();
      });
      renderer.dispose();
      renderer.forceContextLoss();
      canvas.remove();
    };
  }, [open, rarity, palette, loadAttempt]);

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div className={styles.backdrop} style={{ "--reward-accent": palette.accent, "--reward-dark": palette.dark } as CSSProperties} data-rarity={rarity} role="dialog" aria-modal="true" aria-label="Cofre de recompensa">
      {previewHost && rewardPreview ? createPortal(rewardPreview, previewHost) : null}
      <div className={styles.stage} data-leaving={leaving || undefined} aria-busy={leaving}>
        <div className={styles.viewport} ref={stageRef} data-reveal-state={phase}>

        </div>
        {phase === "loading" ? <div className={styles.status} role="status">Preparando animación...</div> : null}
        {phase === "error" ? <div className={`${styles.status} ${styles.error}`} role="alert">No se pudo cargar la animación. <button type="button" onClick={() => setLoadAttempt((attempt) => attempt + 1)}>Reintentar este cofre</button></div> : null}
        <button className={styles.soundToggle} type="button" aria-label={muted ? "Activar sonido" : "Silenciar sonido"} aria-pressed={!muted}
          onClick={() => { unlockRewardAudio(); audioRef.current?.setMuted(!muted); setMuted(!muted); }}>
          {muted ? "Sonido desactivado" : "Sonido activado"}
        </button>
        <button className={styles.close} ref={closeButtonRef} type="button" onClick={onClose} aria-label="Cerrar animación">
          <span aria-hidden="true">×</span>
        </button>
        {actionLabel || continueLabel || remainingCount !== undefined ? (
          <div className={styles.revealPanel} style={{ visibility: pendingChests?.length || revealed || phase === "error" || (actionLabel && onAction) ? "visible" : "hidden" }}>
            {pendingChests ? (
              <div className={styles.chestQueue} role="group" aria-label="Cofres pendientes: elige cuál abrir">
                {pendingChests.map((chest, i) => (
                  <button key={chest.id} type="button" className={styles.queuedChest}
                    style={{ "--chest-color": rewardRarityVisuals[chest.rarity].accent } as CSSProperties}
                    disabled={leaving || actionDisabled || !revealed || chest.id === currentChestId}
                    aria-label={`Abrir cofre ${i + 1}: ${rewardRarityVisuals[chest.rarity].label}`}
                    aria-current={chest.id === currentChestId ? "step" : undefined}
                    onClick={() => { if (onSelectChest) transitionTo(() => onSelectChest(chest.id)); }}>
                    {/* Existing Blender renders identify the chest without revealing its contents. */}
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={`/models/rewards/thumbnails/cofre-${chest.rarity}.png`} alt="" width={80} height={64} />
                    <span>{rewardRarityVisuals[chest.rarity].label}</span>
                  </button>
                ))}
              </div>
            ) : null}
            {remainingCount !== undefined ? (
              <p className={styles.remaining} role="status" style={{ visibility: revealed ? "visible" : "hidden" }}>
                {remainingCount > 0
                  ? `Quedan ${remainingCount} ${remainingCount === 1 ? "cofre por abrir" : "cofres por abrir"}`
                  : "¡Has abierto todos los cofres!"}
              </p>
            ) : null}
            {(continueLabel && onContinue) || (actionLabel && onAction) ? (
              <div className={styles.revealActions}>
                {continueLabel && onContinue ? (
                  <button type="button" style={{ visibility: revealed || phase === "error" ? "visible" : "hidden" }} disabled={!revealed && phase !== "error" || leaving || actionDisabled} onClick={() => transitionTo(onContinue)}>{continueLabel}</button>
                ) : null}
                {actionLabel && onAction ? <button className={continueLabel ? styles.secondaryAction : undefined} type="button" disabled={leaving || actionDisabled} onClick={onAction}>{actionLabel}</button> : null}
                {secondaryActionLabel && onSecondaryAction ? (
                  <button className={secondaryActionProminent ? undefined : styles.secondaryAction} style={secondaryActionProminent ? { visibility: revealed || phase === "error" ? "visible" : "hidden" } : undefined} type="button" disabled={leaving || secondaryActionDisabled || (secondaryActionProminent && !revealed && phase !== "error")} onClick={onSecondaryAction}>
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
