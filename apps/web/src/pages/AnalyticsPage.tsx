import { useState, useEffect, useCallback } from 'react';
import {
  ResponsiveContainer, LineChart, Line, XAxis, YAxis,
  CartesianGrid, Tooltip, Legend, PieChart, Pie, Cell,
} from 'recharts';
import { api } from '../api/client';
import type { KpiData, OlapResult } from '../types';
import KPICard from '../components/Dashboard/KPICard';

// ── helpers ───────────────────────────────────────────────────────────────────

function fmt(v: number) {
  if (v >= 1_000_000_000) return (v / 1_000_000_000).toFixed(1) + 'B';
  if (v >= 1_000_000) return (v / 1_000_000).toFixed(1) + 'M';
  if (v >= 1_000) return (v / 1_000).toFixed(1) + 'K';
  return v.toLocaleString(undefined, { maximumFractionDigits: 1 });
}

function fmtCell(v: unknown): string {
  if (v == null) return '—';
  const n = Number(v);
  if (!isNaN(n)) return fmt(n);
  return String(v);
}

const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ef4444', '#06b6d4', '#f97316', '#84cc16'];

// ── types ─────────────────────────────────────────────────────────────────────

type DrillState =
  | { type: 'none' }
  | { type: 'year'; year: number; label: string }
  | { type: 'quarter'; year: number; quarter: number; label: string };

const GROUP_OPTIONS = [
  { value: 'year', label: 'Year', isTime: true },
  { value: 'quarter', label: 'Quarter', isTime: true },
  { value: 'month', label: 'Month', isTime: true },
  { value: 'city', label: 'City', isTime: false },
  { value: 'customerType', label: 'Customer Type', isTime: false },
  { value: 'product', label: 'Product', isTime: false },
];

const MONTH_NAMES = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

function buildMonthOptions() {
  const opts = [{ value: '', label: 'Any' }];
  for (let y = 2010; y <= 2011; y++)
    for (let m = 1; m <= 12; m++)
      opts.push({ value: String(y * 100 + m), label: `${MONTH_NAMES[m - 1]} ${y}` });
  return opts;
}
const MONTH_OPTIONS = buildMonthOptions();

function timeIdLabel(id: string) {
  if (!id) return '';
  const n = parseInt(id);
  return `${MONTH_NAMES[(n % 100) - 1]} ${Math.floor(n / 100)}`;
}

const CUSTOMER_TYPES = [
  { value: '', label: 'All' },
  { value: 'DL', label: 'Du lich (DL)' },
  { value: 'BD', label: 'Buu dien (BD)' },
  { value: 'CA', label: 'Ca hai (CA)' },
];
const CITIES = ['', 'London', 'Manchester', 'Birmingham', 'Leeds'];

const PIVOT_DIMS = [
  { value: 'year', label: 'Year' },
  { value: 'customerType', label: 'Customer Type' },
  { value: 'city', label: 'City' },
  { value: 'quarter', label: 'Quarter' },
];

// ── sub-components ────────────────────────────────────────────────────────────

function Card({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div style={{
      background: 'var(--card-bg)',
      borderRadius: 'var(--radius-lg)',
      boxShadow: 'var(--shadow-sm)',
      overflow: 'hidden',
      ...style,
    }}>
      {children}
    </div>
  );
}

function CardHeader({ title, subtitle, right }: { title: string; subtitle?: string; right?: React.ReactNode }) {
  return (
    <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
      <div>
        <div style={{ fontWeight: 600, fontSize: 14 }}>{title}</div>
        {subtitle && <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>{subtitle}</div>}
      </div>
      {right}
    </div>
  );
}

function Dropdown({ label, value, onChange, options, minWidth = 120 }: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
  minWidth?: number;
}) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <span style={{ fontSize: 12, color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>{label}</span>
      <select
        value={value}
        onChange={e => onChange(e.target.value)}
        style={{ minWidth, fontSize: 12, padding: '5px 8px' }}
      >
        {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </div>
  );
}

function Breadcrumb({ drill, onNavigate }: {
  drill: DrillState;
  onNavigate: (to: DrillState) => void;
}) {
  if (drill.type === 'none') return null;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, padding: '8px 20px', background: '#f8fafc', borderBottom: '1px solid var(--border)' }}>
      <span
        onClick={() => onNavigate({ type: 'none' })}
        style={{ color: 'var(--primary)', cursor: 'pointer', fontWeight: 500 }}
      >
        All Data
      </span>
      <span style={{ color: 'var(--text-muted)' }}>›</span>
      {drill.type === 'quarter' ? (
        <>
          <span
            onClick={() => onNavigate({ type: 'year', year: drill.year, label: String(drill.year) })}
            style={{ color: 'var(--primary)', cursor: 'pointer', fontWeight: 500 }}
          >
            {drill.year}
          </span>
          <span style={{ color: 'var(--text-muted)' }}>›</span>
          <span style={{ fontWeight: 600, color: 'var(--text)' }}>{drill.label}</span>
        </>
      ) : (
        <span style={{ fontWeight: 600, color: 'var(--text)' }}>{drill.label}</span>
      )}
      <span style={{ marginLeft: 8, fontSize: 11, color: 'var(--text-muted)', background: '#e2e8f0', borderRadius: 20, padding: '1px 8px' }}>
        {drill.type === 'year' ? 'Quarters' : 'Months'}
      </span>
    </div>
  );
}

function MainChart({
  data,
  drill,
  groupBy,
  loading,
  onBarClick,
}: {
  data: OlapResult | null;
  drill: DrillState;
  groupBy: string;
  loading: boolean;
  onBarClick: (row: Record<string, unknown>) => void;
}) {
  if (loading) return <div style={{ height: 280, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)' }}>Loading…</div>;
  if (!data || data.rows.length === 0) return <div style={{ height: 200, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)' }}>No data — adjust filters</div>;

  const canDrill = (drill.type === 'none' && groupBy === 'year') || drill.type === 'year';
  const chartData = data.rows.map(r => ({
    name: String(r['Label'] ?? '').substring(0, 14),
    Revenue: Number(r['Total Amount'] ?? 0),
    Quantity: Number(r['Quantity'] ?? 0),
    _row: r,
  }));

  return (
    <div>
      {canDrill && (
        <div style={{ padding: '6px 20px 0', fontSize: 11, color: 'var(--primary)', display: 'flex', alignItems: 'center', gap: 4 }}>
          <span>▶</span>
          <span>Click a point to zoom in</span>
        </div>
      )}
      <div style={{ padding: '8px 12px 16px' }}>
        <ResponsiveContainer width="100%" height={280}>
          <LineChart
            data={chartData}
            margin={{ top: 5, right: 20, left: 0, bottom: 30 }}
            onClick={e => {
              if (!canDrill || !e?.activePayload?.[0]) return;
              const row = (e.activePayload[0].payload as { _row: Record<string, unknown> })._row;
              onBarClick(row);
            }}
          >
            <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
            <XAxis dataKey="name" tick={{ fontSize: 11 }} angle={-20} textAnchor="end" height={45} />
            <YAxis tickFormatter={fmt} tick={{ fontSize: 11 }} width={55} />
            <Tooltip
              formatter={(v: number, name: string) => [fmt(v), name]}
            />
            <Legend wrapperStyle={{ fontSize: 12, paddingTop: 8 }} />
            <Line
              type="monotone"
              dataKey="Revenue"
              stroke="#3b82f6"
              strokeWidth={2}
              dot={{ r: 4, fill: '#3b82f6' }}
              activeDot={{
                r: 6,
                cursor: canDrill ? 'pointer' : undefined,
                onClick: canDrill ? (_: unknown, payload: any) => {
                  if (!payload?.payload?._row) return;
                  onBarClick(payload.payload._row);
                } : undefined,
              }}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

function HeatMatrix({ data, loading }: { data: OlapResult | null; loading: boolean }) {
  if (loading) return <div style={{ padding: 32, textAlign: 'center', color: 'var(--text-muted)' }}>Loading…</div>;
  if (!data || data.rows.length === 0) return <div style={{ padding: 32, textAlign: 'center', color: 'var(--text-muted)' }}>Click Generate</div>;

  const cols = data.columnHeaders.filter(h => h !== 'Label');
  const allVals = data.rows.flatMap(r => cols.map(c => Number(r[c] ?? 0)));
  const maxVal = Math.max(...allVals, 1);

  return (
    <div style={{ overflowX: 'auto', fontSize: 12 }}>
      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr>
            {data.columnHeaders.map(h => (
              <th key={h} style={{
                padding: '6px 10px', textAlign: h === 'Label' ? 'left' : 'right',
                fontSize: 11, fontWeight: 600, color: 'var(--text-muted)',
                borderBottom: '1px solid var(--border)', whiteSpace: 'nowrap',
              }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.rows.map((row, i) => (
            <tr key={i}>
              {data.columnHeaders.map(h => {
                if (h === 'Label') return (
                  <td key={h} style={{ padding: '5px 10px', fontWeight: 500, borderBottom: '1px solid #f1f5f9', whiteSpace: 'nowrap' }}>
                    {String(row[h] ?? '')}
                  </td>
                );
                const val = Number(row[h] ?? 0);
                const alpha = val > 0 ? (val / maxVal) * 0.75 : 0;
                return (
                  <td key={h} style={{
                    padding: '5px 10px', textAlign: 'right',
                    background: val > 0 ? `rgba(59,130,246,${alpha.toFixed(2)})` : 'transparent',
                    color: alpha > 0.55 ? '#fff' : 'var(--text)',
                    borderBottom: '1px solid #f1f5f9',
                    fontVariantNumeric: 'tabular-nums',
                  }}>
                    {val > 0 ? fmt(val) : '—'}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function CityChart({ data, loading }: { data: OlapResult | null; loading: boolean }) {
  if (loading) return <div style={{ padding: 32, textAlign: 'center', color: 'var(--text-muted)' }}>Loading…</div>;
  if (!data || data.rows.length === 0) return <div style={{ padding: 32, textAlign: 'center', color: 'var(--text-muted)' }}>No data</div>;

  const chartData = data.rows.slice(0, 8).map(r => ({
    name: String(r['Label'] ?? ''),
    value: Number(r['Total Amount'] ?? 0),
  }));

  const renderLabel = ({ name, percent }: { name: string; percent: number }) =>
    percent > 0.05 ? `${name} ${(percent * 100).toFixed(0)}%` : '';

  return (
    <div style={{ padding: '8px 12px 16px' }}>
      <ResponsiveContainer width="100%" height={240}>
        <PieChart>
          <Pie
            data={chartData}
            dataKey="value"
            nameKey="name"
            cx="50%"
            cy="50%"
            outerRadius={90}
            label={renderLabel}
            labelLine={false}
          >
            {chartData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
          </Pie>
          <Tooltip formatter={(v: number) => [fmt(v), 'Revenue']} />
          <Legend iconType="circle" iconSize={10} wrapperStyle={{ fontSize: 12 }} />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
}

function DataTable({ data, loading }: { data: OlapResult | null; loading: boolean }) {
  if (loading) return <div style={{ padding: 32, textAlign: 'center', color: 'var(--text-muted)' }}>Loading…</div>;
  if (!data || data.rows.length === 0) return <div style={{ padding: 20, textAlign: 'center', color: 'var(--text-muted)' }}>No data</div>;
  return (
    <div style={{ overflowX: 'auto' }}>
      <table>
        <thead>
          <tr>{data.columnHeaders.map(h => <th key={h}>{h}</th>)}</tr>
        </thead>
        <tbody>
          {data.rows.map((row, i) => (
            <tr key={i}>
              {data.columnHeaders.map(h => (
                <td key={h} style={{ fontWeight: h === 'Label' ? 500 : 400, textAlign: h === 'Label' ? 'left' : 'right' }}>
                  {h === 'Label' ? String(row[h] ?? '') : fmtCell(row[h])}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── main page ─────────────────────────────────────────────────────────────────

export default function AnalyticsPage() {
  const [kpi, setKpi] = useState<KpiData | null>(null);

  // Analysis controls
  const [groupBy, setGroupBy] = useState('year');
  const [filterMonthFrom, setFilterMonthFrom] = useState('');
  const [filterMonthTo, setFilterMonthTo] = useState('');
  const [filterType, setFilterType] = useState('');
  const [filterCity, setFilterCity] = useState('');
  const [drill, setDrill] = useState<DrillState>({ type: 'none' });

  // Data
  const [mainData, setMainData] = useState<OlapResult | null>(null);
  const [mainLoading, setMainLoading] = useState(false);
  const [cityData, setCityData] = useState<OlapResult | null>(null);
  const [cityLoading, setCityLoading] = useState(true);

  // Pivot
  const [pivotRow, setPivotRow] = useState('customerType');
  const [pivotCol, setPivotCol] = useState('year');
  const [pivotData, setPivotData] = useState<OlapResult | null>(null);
  const [pivotLoading, setPivotLoading] = useState(false);

  const [error, setError] = useState<string | null>(null);

  // ── load KPI + city (once) ────────────────────────────────────────────────
  useEffect(() => {
    api.kpi().then(setKpi).catch(e => setError(String(e)));
    api.byCity().then(setCityData).catch(() => null).finally(() => setCityLoading(false));
  }, []);

  // ── load main chart data ──────────────────────────────────────────────────
  const loadMain = useCallback(async () => {
    setMainLoading(true);
    setError(null);
    try {
      if (drill.type === 'year') {
        setMainData(await api.drilldown('year', String(drill.year)));
        return;
      }
      if (drill.type === 'quarter') {
        setMainData(await api.drilldown('quarter', `${drill.year}:${drill.quarter}`));
        return;
      }
      const hasFilters = filterMonthFrom || filterMonthTo || filterType || filterCity;
      if (hasFilters) {
        setMainData(await api.dice({
          fromTimeId: filterMonthFrom ? parseInt(filterMonthFrom) : undefined,
          toTimeId: filterMonthTo ? parseInt(filterMonthTo) : undefined,
          customerType: filterType || undefined,
          city: filterCity || undefined,
          rows: groupBy,
        }));
      } else {
        setMainData(await api.rollup(groupBy));
      }
    } catch (e) {
      setError(String(e));
    } finally {
      setMainLoading(false);
    }
  }, [groupBy, filterMonthFrom, filterMonthTo, filterType, filterCity, drill]);

  useEffect(() => { loadMain(); }, [loadMain]);

  // ── drill-down handler ───────────────────────────────────────────────────
  const handleBarClick = (row: Record<string, unknown>) => {
    if (drill.type === 'none' && groupBy === 'year') {
      const label = String(row['Label'] ?? '');
      const year = parseInt(label);
      if (!isNaN(year)) setDrill({ type: 'year', year, label });
    } else if (drill.type === 'year') {
      const label = String(row['Label'] ?? '');
      const quarter = parseInt(label.replace('Q', ''));
      if (!isNaN(quarter)) setDrill({ type: 'quarter', year: drill.year, quarter, label: `${drill.year} ${label}` });
    }
  };

  const resetFilters = () => {
    setFilterMonthFrom(''); setFilterMonthTo(''); setFilterType(''); setFilterCity('');
    setDrill({ type: 'none' });
  };

  const handlePivot = async () => {
    if (pivotRow === pivotCol) return;
    setPivotLoading(true);
    try { setPivotData(await api.pivot(pivotRow, pivotCol)); }
    catch (e) { setError(String(e)); }
    finally { setPivotLoading(false); }
  };

  const activeFilters = [
    (filterMonthFrom || filterMonthTo) && `Period: ${timeIdLabel(filterMonthFrom) || '…'} → ${timeIdLabel(filterMonthTo) || '…'}`,
    filterType && `Type: ${filterType}`,
    filterCity && `City: ${filterCity}`,
  ].filter(Boolean);

  const isDrilling = drill.type !== 'none';
  const drillTitle = drill.type === 'year'
    ? `${drill.year} — Quarterly Breakdown`
    : drill.type === 'quarter'
      ? `${(drill as { label: string }).label} — Monthly Breakdown`
      : null;

  // ── render ─────────────────────────────────────────────────────────────────
  if (error && !kpi && !mainData) {
    return (
      <div style={{ padding: 32 }}>
        <div style={{ padding: 20, background: 'var(--danger-light)', color: 'var(--danger)', borderRadius: 'var(--radius)', fontSize: 13 }}>
          <strong>Cannot connect to API.</strong> {error}
          <br /><small style={{ marginTop: 6, display: 'block' }}>Start the backend: <code>cd apps/api && dotnet run</code></small>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>

      {/* KPI Row */}
      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
        <KPICard title="Total Revenue" value={kpi?.totalRevenue ?? 0} icon="💰" color="var(--primary)" colorLight="var(--primary-light)" />
        <KPICard title="Total Quantity" value={kpi?.totalQuantity ?? 0} icon="📦" color="var(--success)" colorLight="var(--success-light)" />
        <KPICard title="Customers" value={kpi?.totalCustomers ?? 0} icon="👥" color="var(--warning)" colorLight="var(--warning-light)" />
        <KPICard title="Products" value={kpi?.totalProducts ?? 0} icon="🏷️" color="var(--purple)" colorLight="var(--purple-light)" />
        <KPICard title="Transactions" value={kpi?.totalTransactions ?? 0} icon="📋" color="#06b6d4" colorLight="#ecfeff" />
      </div>

      {/* Main Analysis */}
      <Card>
        <CardHeader
          title={isDrilling ? drillTitle! : 'Revenue Analysis'}
          subtitle={isDrilling ? 'Click breadcrumb to go back' : 'Select dimensions and filters below'}
          right={
            <button
              onClick={resetFilters}
              style={{ fontSize: 12, padding: '5px 12px', background: activeFilters.length > 0 || isDrilling ? 'var(--danger-light)' : '#f8fafc', color: activeFilters.length > 0 || isDrilling ? 'var(--danger)' : 'var(--text-muted)', border: '1px solid var(--border)' }}
            >
              Reset
            </button>
          }
        />

        {/* Controls row */}
        {!isDrilling && (
          <div style={{ padding: '12px 20px', borderBottom: '1px solid var(--border)', display: 'flex', flexWrap: 'wrap', gap: 14, alignItems: 'center' }}>
            <Dropdown
              label="Analyze by"
              value={groupBy}
              onChange={v => { setGroupBy(v); setDrill({ type: 'none' }); }}
              options={GROUP_OPTIONS}
              minWidth={130}
            />
            <div style={{ width: 1, height: 20, background: 'var(--border)' }} />
            <Dropdown
              label="From"
              value={filterMonthFrom}
              onChange={setFilterMonthFrom}
              options={MONTH_OPTIONS}
              minWidth={110}
            />
            <Dropdown
              label="To"
              value={filterMonthTo}
              onChange={setFilterMonthTo}
              options={MONTH_OPTIONS}
              minWidth={110}
            />
            <Dropdown
              label="Customer type"
              value={filterType}
              onChange={setFilterType}
              options={CUSTOMER_TYPES}
              minWidth={130}
            />
            <Dropdown
              label="City"
              value={filterCity}
              onChange={setFilterCity}
              options={CITIES.map(c => ({ value: c, label: c || 'All cities' }))}
              minWidth={120}
            />
            {activeFilters.length > 0 && (
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginLeft: 4 }}>
                {activeFilters.map((f, i) => (
                  <span key={i} style={{ fontSize: 11, padding: '2px 8px', background: 'var(--primary-light)', color: 'var(--primary)', borderRadius: 20, fontWeight: 500 }}>
                    {f}
                  </span>
                ))}
              </div>
            )}
          </div>
        )}

        <Breadcrumb drill={drill} onNavigate={setDrill} />

        <MainChart data={mainData} drill={drill} groupBy={groupBy} loading={mainLoading} onBarClick={handleBarClick} />
      </Card>

      {/* Secondary row: City chart + Pivot matrix */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.4fr', gap: 20 }}>

        {/* City chart */}
        <Card>
          <CardHeader title="Revenue by City" subtitle="Top 8 cities" />
          <CityChart data={cityData} loading={cityLoading} />
        </Card>

        {/* Pivot matrix */}
        <Card>
          <CardHeader
            title="Revenue Matrix"
            subtitle="Cross-tabulate any two dimensions"
            right={
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <Dropdown
                  label="Rows"
                  value={pivotRow}
                  onChange={v => { setPivotRow(v); setPivotData(null); }}
                  options={PIVOT_DIMS}
                  minWidth={100}
                />
                <Dropdown
                  label="Cols"
                  value={pivotCol}
                  onChange={v => { setPivotCol(v); setPivotData(null); }}
                  options={PIVOT_DIMS.filter(d => d.value !== pivotRow)}
                  minWidth={100}
                />
                <button
                  onClick={handlePivot}
                  style={{ background: 'var(--primary)', color: '#fff', padding: '5px 12px', fontSize: 12, fontWeight: 600 }}
                >
                  Generate
                </button>
              </div>
            }
          />
          <div style={{ padding: '4px 0' }}>
            <HeatMatrix data={pivotData} loading={pivotLoading} />
          </div>
        </Card>
      </div>

      {/* Data table */}
      <Card>
        <CardHeader
          title="Detail Data"
          subtitle={mainData ? `${mainData.rows.length} rows` : undefined}
        />
        <DataTable data={mainData} loading={mainLoading} />
      </Card>

    </div>
  );
}
