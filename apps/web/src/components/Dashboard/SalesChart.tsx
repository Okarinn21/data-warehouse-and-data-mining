import {
  ResponsiveContainer, BarChart, Bar, LineChart, Line,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  PieChart, Pie, Cell,
} from 'recharts';
import type { OlapResult } from '../../types';

const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#f97316', '#84cc16'];

function fmt(v: number) {
  if (v >= 1_000_000) return (v / 1_000_000).toFixed(1) + 'M';
  if (v >= 1_000) return (v / 1_000).toFixed(1) + 'K';
  return String(Math.round(v));
}

interface ChartCardProps {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}

export function ChartCard({ title, subtitle, children }: ChartCardProps) {
  return (
    <div style={{
      background: 'var(--card-bg)',
      borderRadius: 'var(--radius-lg)',
      padding: '20px 24px',
      boxShadow: 'var(--shadow-sm)',
    }}>
      <div style={{ marginBottom: 16 }}>
        <div style={{ fontWeight: 600, fontSize: 14, color: 'var(--text)' }}>{title}</div>
        {subtitle && <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>{subtitle}</div>}
      </div>
      {children}
    </div>
  );
}

export function SalesTrendChart({ data }: { data: OlapResult }) {
  const chartData = data.rows.map(r => ({
    name: String(r['Label']),
    revenue: Number(r['Total Amount'] ?? 0),
    quantity: Number(r['Quantity'] ?? 0),
  }));

  return (
    <ResponsiveContainer width="100%" height={240}>
      <LineChart data={chartData} margin={{ top: 5, right: 10, left: 0, bottom: 5 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
        <XAxis dataKey="name" tick={{ fontSize: 11 }} />
        <YAxis tickFormatter={fmt} tick={{ fontSize: 11 }} />
        <Tooltip formatter={(v: number, name: string) => [fmt(v), name === 'revenue' ? 'Revenue' : 'Quantity']} />
        <Legend formatter={n => n === 'revenue' ? 'Revenue' : 'Quantity'} />
        <Line type="monotone" dataKey="revenue" stroke="#3b82f6" strokeWidth={2} dot={false} />
        <Line type="monotone" dataKey="quantity" stroke="#10b981" strokeWidth={2} dot={false} />
      </LineChart>
    </ResponsiveContainer>
  );
}

export function CityBarChart({ data }: { data: OlapResult }) {
  const chartData = data.rows.slice(0, 8).map(r => ({
    name: String(r['Label'] ?? '').substring(0, 12),
    revenue: Number(r['Total Amount'] ?? 0),
  }));

  return (
    <ResponsiveContainer width="100%" height={240}>
      <BarChart data={chartData} margin={{ top: 5, right: 10, left: 0, bottom: 5 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
        <XAxis dataKey="name" tick={{ fontSize: 10 }} />
        <YAxis tickFormatter={fmt} tick={{ fontSize: 11 }} />
        <Tooltip formatter={(v: number) => [fmt(v), 'Revenue']} />
        <Bar dataKey="revenue" fill="#3b82f6" radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function ProductPieChart({ data }: { data: OlapResult }) {
  const chartData = data.rows.slice(0, 6).map(r => ({
    name: String(r['Label'] ?? '').substring(0, 20),
    value: Number(r['Total Amount'] ?? 0),
  }));

  return (
    <ResponsiveContainer width="100%" height={240}>
      <PieChart>
        <Pie
          data={chartData}
          cx="50%"
          cy="50%"
          outerRadius={90}
          dataKey="value"
          label={({ name, percent }) => `${name.substring(0, 10)} ${(percent * 100).toFixed(0)}%`}
          labelLine={false}
        >
          {chartData.map((_, i) => (
            <Cell key={i} fill={COLORS[i % COLORS.length]} />
          ))}
        </Pie>
        <Tooltip formatter={(v: number) => fmt(v)} />
      </PieChart>
    </ResponsiveContainer>
  );
}
