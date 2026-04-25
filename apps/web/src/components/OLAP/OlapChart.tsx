import {
  ResponsiveContainer, BarChart, Bar, XAxis, YAxis,
  CartesianGrid, Tooltip, Legend,
} from 'recharts';
import type { OlapResult } from '../../types';

const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#f97316'];

function fmt(v: number): string {
  if (v >= 1_000_000) return (v / 1_000_000).toFixed(1) + 'M';
  if (v >= 1_000) return (v / 1_000).toFixed(1) + 'K';
  return String(Math.round(v));
}

interface Props {
  result: OlapResult | null;
  valueKey?: string;
  height?: number;
  highlightLabel?: string;
}

export default function OlapChart({ result, valueKey, height = 260, highlightLabel }: Props) {
  if (!result || result.rows.length === 0) return null;

  const numericHeaders = result.columnHeaders.filter(h => h !== 'Label');
  const displayKey = valueKey ?? numericHeaders[0] ?? 'Total Amount';

  const chartData = result.rows.map(r => ({
    name: String(r['Label'] ?? '').substring(0, 16),
    value: Number(r[displayKey] ?? 0),
    fill: String(r['Label']) === highlightLabel ? '#f59e0b' : '#3b82f6',
  }));

  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={chartData} margin={{ top: 5, right: 10, left: 0, bottom: 20 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
        <XAxis
          dataKey="name"
          tick={{ fontSize: 10 }}
          angle={-25}
          textAnchor="end"
          interval={0}
          height={50}
        />
        <YAxis tickFormatter={fmt} tick={{ fontSize: 11 }} />
        <Tooltip formatter={(v: number) => [fmt(v), displayKey]} />
        <Bar dataKey="value" radius={[4, 4, 0, 0]} fill="#3b82f6" />
      </BarChart>
    </ResponsiveContainer>
  );
}

interface GroupedProps {
  result: OlapResult | null;
  height?: number;
}

export function GroupedBarChart({ result, height = 300 }: GroupedProps) {
  if (!result || result.rows.length === 0) return null;

  const colKeys = result.columnHeaders.filter(h => h !== 'Label');
  const chartData = result.rows.map(r => {
    const row: Record<string, unknown> = { name: String(r['Label'] ?? '').substring(0, 14) };
    colKeys.forEach(k => { row[k] = Number(r[k] ?? 0); });
    return row;
  });

  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={chartData} margin={{ top: 5, right: 10, left: 0, bottom: 20 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
        <XAxis dataKey="name" tick={{ fontSize: 11 }} angle={-15} textAnchor="end" height={40} />
        <YAxis tickFormatter={fmt} tick={{ fontSize: 11 }} />
        <Tooltip formatter={(v: number, n: string) => [fmt(v), n]} />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        {colKeys.slice(0, 7).map((k, i) => (
          <Bar key={k} dataKey={k} fill={COLORS[i % COLORS.length]} radius={[3, 3, 0, 0]} />
        ))}
      </BarChart>
    </ResponsiveContainer>
  );
}
