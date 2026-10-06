export const TIME_ZONE = "Africa/Cairo";

export interface LocalNow {
  year: number;
  month: number; // 1..12
  day: number;
  hour: number;
  weekday: number; // 1 = Monday ... 7 = Sunday (Dart convention)
  dayId: string; // yyyy-MM-dd
}

/** Current wall-clock time in Cairo (or [tz]) without extra dependencies. */
export function localNow(date = new Date(), tz = TIME_ZONE): LocalNow {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
    weekday: "short",
  }).formatToParts(date);
  const get = (t: string) => parts.find((p) => p.type === t)!.value;
  const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const year = Number(get("year"));
  const month = Number(get("month"));
  const day = Number(get("day"));
  return {
    year,
    month,
    day,
    hour: Number(get("hour")),
    weekday: weekdays.indexOf(get("weekday")) + 1,
    dayId: dayId(year, month, day),
  };
}

export const dayId = (y: number, m: number, d: number) =>
  `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;

/** Adds days to a yyyy-MM-dd id (calendar arithmetic in UTC, tz-safe). */
export function addDays(id: string, days: number): string {
  const [y, m, d] = id.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return dayId(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}

export const WEDNESDAY = 3;
export const TUESDAY = 2;

export function displayDate(id: string): string {
  const [y, m, d] = id.split("-");
  return `${d}/${m}/${y}`;
}
