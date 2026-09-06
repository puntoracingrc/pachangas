import { supabase } from '../supabaseClient';
import type { Loot } from './roulette';
export type RouletteChest = { id: string; rarity: number };
export type RouletteSnapshot = {
  balance: number; freeSpins: number; cost: number; odds: number[]; enabled: boolean;
  queue: RouletteChest[]; owned: string[]; history: number[];
  pools: { rarity: number; kind: string; weight: number; min: number; max: number; key: string | null; duplicatePoints: number }[];
};
export type RouletteResponse = { snapshot: RouletteSnapshot; chest?: RouletteChest;
  entries?: { chest: RouletteChest; loot: Loot }[]; points?: number };
export type RouletteOperation = { action: 'spin' | 'open' | 'open_all'; id: string; ids: string[] | null };
export async function rouletteRequest(operation?: RouletteOperation): Promise<RouletteResponse> {
  if (!supabase) throw new Error('No se ha podido conectar con tus recompensas.');
  const { data, error } = await supabase.rpc('pachanga_roulette_v1', {
    p_action: operation?.action ?? 'snapshot', p_operation_id: operation?.id ?? null, p_box_ids: operation?.ids ?? null,
  });
  if (error) throw error;
  if (operation && typeof window !== 'undefined') window.dispatchEvent(new Event('pachangas:rewards-updated'));
  return operation ? data as RouletteResponse : { snapshot: data as RouletteSnapshot };
}
