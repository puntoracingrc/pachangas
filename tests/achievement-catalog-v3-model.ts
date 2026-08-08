export type GoalRewardComponent = {
  boxRarity: "common" | "rare" | "uncommon";
  goals: 2 | 3 | 4 | 5;
  key: "doblete" | "hat_trick" | "manita" | "poker";
  label: "Doblete" | "Hat-trick" | "Manita" | "Póker";
};

const doblete: GoalRewardComponent = {
  boxRarity: "common", goals: 2, key: "doblete", label: "Doblete",
};
const hatTrick: GoalRewardComponent = {
  boxRarity: "uncommon", goals: 3, key: "hat_trick", label: "Hat-trick",
};
const poker: GoalRewardComponent = {
  boxRarity: "uncommon", goals: 4, key: "poker", label: "Póker",
};
const manita: GoalRewardComponent = {
  boxRarity: "rare", goals: 5, key: "manita", label: "Manita",
};

export function resolveGoalRewardComponents(goals: number): GoalRewardComponent[] {
  let remaining = Math.max(0, Math.floor(goals));
  const components: GoalRewardComponent[] = [];
  if (remaining < 2) return components;

  while (remaining > 10) {
    if (remaining % 10 === 1) {
      components.push(manita, hatTrick, hatTrick);
      remaining -= 11;
    } else {
      components.push(manita, manita);
      remaining -= 10;
    }
  }

  if (remaining === 2) components.push(doblete);
  if (remaining === 3) components.push(hatTrick);
  if (remaining === 4) components.push(poker);
  if (remaining === 5) components.push(manita);
  if (remaining === 6) components.push(hatTrick, hatTrick);
  if (remaining === 7) components.push(manita, doblete);
  if (remaining === 8) components.push(poker, poker);
  if (remaining === 9) components.push(hatTrick, hatTrick, hatTrick);
  if (remaining === 10) components.push(manita, manita);
  return components;
}

export function summarizeComponents(components: GoalRewardComponent[]) {
  return components.reduce<Record<string, number>>((summary, component) => {
    summary[component.key] = (summary[component.key] ?? 0) + 1;
    return summary;
  }, {});
}
