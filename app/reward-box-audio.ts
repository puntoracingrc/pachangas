import type { RewardRarity } from "./reward-rarity-effects";

let context: AudioContext | null = null;
let muted = false;
const preferenceKey = "pachangas.reward-sound-muted";

export function rewardSoundMuted() {
  if (typeof window !== "undefined") {
    try { muted = window.localStorage.getItem(preferenceKey) === "true"; } catch { /* Optional preference. */ }
  }
  return muted;
}

// Call directly from a click/tap so browser autoplay restrictions are respected.
export function unlockRewardAudio() {
  if (typeof window === "undefined" || !window.AudioContext) return;
  try {
    context ??= new AudioContext();
    preloadSamples();
    if (context.state === "suspended") void context.resume().catch(() => {});
  } catch { /* Audio is optional; the reveal always works without it. */ }
}

export function setRewardSoundMuted(value: boolean) {
  muted = value;
  try { window.localStorage.setItem(preferenceKey, String(value)); } catch { /* Optional preference. */ }
}

const sampleNames = ["latch", "lid", "air", "glass1", "glass2", "body", "settle"] as const;
type SampleName = typeof sampleNames[number];
const samples = new Map<SampleName, AudioBuffer>();
let sampleLoading: Promise<void> | null = null;
function preloadSamples() {
  const ctx = context;
  if (!ctx || sampleLoading) return;
  sampleLoading = Promise.all(sampleNames.map(async (name) => {
    if (samples.has(name)) return;
    const response = await fetch(`/audio/rewards/${name}.wav`);
    if (!response.ok) throw new Error(`Reward sound unavailable: ${name}`);
    samples.set(name, await ctx.decodeAudioData(await response.arrayBuffer()));
  })).then(() => {}).catch(() => { sampleLoading = null; });
}

export function createRewardAudio(rarity: RewardRarity, reducedMotion: boolean) {
  preloadSamples();
  const prestige = rarity === "legendary" ? 2 : rarity === "epic" ? 1 : 0;
  const count = { common: 0, uncommon: 2, rare: 4, epic: 7, legendary: 10 }[rarity];
  type Cue = { at: number; sample: SampleName; volume: number; rate: number; pan: number };
  const cues: Cue[] = reducedMotion ? [{ at: 0, sample: "settle", volume: 0.20, rate: 1, pan: 0 }] : [
    { at: 0.65, sample: "latch", volume: 0.40, rate: 0.95, pan: 0 },
    { at: 0.97, sample: "lid", volume: 0.35, rate: 0.82, pan: 0 },
    { at: 1.15, sample: "air", volume: 0.20, rate: 0.8, pan: 0 },
    ...Array.from({ length: count }, (_, i): Cue => ({ at: 1.5 + i * (prestige ? 1.8 : 1) / Math.max(1, count), sample: i % 2 ? "glass1" : "glass2", volume: 0.12, rate: [0.88, 1.03, 0.96, 1.1][i % 4], pan: Math.sin(i * 2.4) * 0.55 })),
    ...(prestige ? [{ at: 1.65, sample: "body" as const, volume: 0.23 + prestige * 0.04, rate: 0.65, pan: 0 }, { at: 2.15, sample: "air" as const, volume: 0.14 + prestige * 0.03, rate: 0.65, pan: 0 }] : []),
    { at: 4.18, sample: "settle", volume: 0.20, rate: 0.95, pan: 0 },
  ];
  cues.sort((a, b) => a.at - b.at);
  let next = 0;
  let bus: GainNode | null = null;
  const sources = new Set<AudioBufferSourceNode>();
  const nodes = new Set<AudioNode>();
  return {
    update(time: number) {
      const ctx = context;
      if (ctx && !bus) {
        preloadSamples();
        bus = ctx.createGain(); bus.gain.value = muted ? 0 : 0.48; bus.connect(ctx.destination);
      }
      while (next < cues.length && cues[next].at <= time) {
        const cue = cues[next++];
        const buffer = samples.get(cue.sample);
        if (!ctx || !bus || !buffer || ctx.state !== "running" || muted || document.hidden || time - cue.at > 0.15) continue;
        const source = ctx.createBufferSource();
        const gain = ctx.createGain();
        const pan = ctx.createStereoPanner();
        const filter = ctx.createBiquadFilter();
        source.buffer = buffer; source.playbackRate.value = cue.rate;
        gain.gain.value = cue.volume; pan.pan.value = cue.pan;
        filter.type = "lowpass"; filter.frequency.value = cue.sample.startsWith("glass") ? 6500 : 9000;
        source.connect(filter).connect(gain).connect(pan).connect(bus);
        const voiceNodes: AudioNode[] = [source, filter, gain, pan];
        sources.add(source); voiceNodes.forEach((node) => nodes.add(node));
        source.onended = () => { sources.delete(source); voiceNodes.forEach((node) => { node.disconnect(); nodes.delete(node); }); };
        source.start();
      }
    },
    setMuted(value: boolean) {
      setRewardSoundMuted(value);
      if (bus && context) bus.gain.setTargetAtTime(value ? 0 : 0.48, context.currentTime, 0.015);
    },
    dispose() {
      for (const source of sources) { try { source.stop(); } catch { /* Already ended. */ } }
      for (const node of nodes) node.disconnect();
      sources.clear(); nodes.clear(); bus?.disconnect();
    },
  };
}

// Shared recorded samples and mute preference; one disposable voice group per spin.
export function createRouletteAudio() {
  preloadSamples();
  let disposed = false;
  const voices = new Set<AudioBufferSourceNode>();
  function stopVoices() {
    for (const source of voices) { try { source.stop(); } catch { /* Already ended. */ } }
    voices.clear();
  }
  function play(name: SampleName, volume: number, rate = 1, delay = 0, short = false) {
    const ctx = context;
    const buffer = samples.get(name);
    if (disposed || muted || document.hidden || !ctx || ctx.state !== "running" || !buffer) return;
    const source = ctx.createBufferSource();
    const gain = ctx.createGain();
    source.buffer = buffer;
    source.playbackRate.value = rate;
    const at = ctx.currentTime + delay;
    const length = short ? Math.min(.065, buffer.duration / rate) : buffer.duration / rate;
    gain.gain.setValueAtTime(0, at);
    gain.gain.linearRampToValueAtTime(volume, at + .003);
    gain.gain.setValueAtTime(volume, at + Math.max(.004, length - .02));
    gain.gain.linearRampToValueAtTime(0, at + length);
    source.connect(gain).connect(ctx.destination);
    voices.add(source);
    source.onended = () => { voices.delete(source); source.disconnect(); gain.disconnect(); };
    source.start(at);
    source.stop(at + length);
  }
  const hide = () => { if (document.hidden) stopVoices(); };
  document.addEventListener("visibilitychange", hide);
  return {
    tick(progress: number) { play("latch", .18, 1.12 - progress * .18, 0, true); },
    finish(rarity: RewardRarity) {
      const level = { common: 0, uncommon: 1, rare: 2, epic: 3, legendary: 4 }[rarity];
      play("body", .22, .95 - level * .07);
      play("latch", .13, .85, .06, true);
      const count = [0, 2, 4, 7, 10][level];
      for (let i = 0; i < count; i++) play(i % 2 ? "glass1" : "glass2", .085, [1, .9, 1.07][i % 3], .13 + i * .1);
      if (level >= 3) play("air", .13, .7, .12);
    },
    setMuted(value: boolean) { setRewardSoundMuted(value); if (value) stopVoices(); },
    dispose() { disposed = true; stopVoices(); document.removeEventListener("visibilitychange", hide); },
  };
}
