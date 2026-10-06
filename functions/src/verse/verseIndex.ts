/** Deterministic day index so every day gets a verse, cycling through the pool. */
export function verseIndexFor(dayId: string, poolSize: number): number {
  const [y, m, d] = dayId.split("-").map(Number);
  const days = Math.floor(Date.UTC(y, m - 1, d) / 86400000);
  return ((days % poolSize) + poolSize) % poolSize;
}

