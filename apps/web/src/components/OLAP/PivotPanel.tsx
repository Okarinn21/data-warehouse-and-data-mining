import { useState } from 'react';
import { api } from '../../api/client';
import type { OlapResult } from '../../types';
import OlapTable from './OlapTable';
import { GroupedBarChart } from './OlapChart';
import { PanelHeader, SelectField } from './shared';

const DIMS = [
  { value: 'year', label: 'Year' },
  { value: 'quarter', label: 'Quarter' },
  { value: 'customerType', label: 'Customer Type' },
  { value: 'city', label: 'City' },
];

function fmt(v: unknown): string {
  if (v == null) return '—';
  const n = Number(v);
  if (isNaN(n)) return String(v);
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1_000) return (n / 1_000).toFixed(1) + 'K';
  return n.toFixed(0);
}

function HeatTable({ result }: { result: OlapResult }) {
  if (!result.rows.length) return null;
  const cols = result.columnHeaders.filter(h => h !== 'Label');
  const allVals = result.rows.flatMap(r => cols.map(c => Number(r[c] ?? 0)));
  const maxVal = Math.max(...allVals, 1);

  return (
    <div style={{ overflowX: 'auto', borderRadius: 'var(--radius)', border: '1px solid var(--border)' }}>
      <table>
        <thead>
          <tr>
            {result.columnHeaders.map(h => <th key={h}>{h}</th>)}
          </tr>
        </thead>
        <tbody>
          {result.rows.map((row, i) => (
            <tr key={i}>
              {result.columnHeaders.map(h => {
                if (h === 'Label') return <td key={h} style={{ fontWeight: 600 }}>{String(row[h] ?? '')}</td>;
                const val = Number(row[h] ?? 0);
                const intensity = Math.round((val / maxVal) * 255);
                const bg = `rgba(59,130,246,${(val / maxVal * 0.7).toFixed(2)})`;
                return (
                  <td key={h} style={{
                    background: val > 0 ? bg : 'transparent',
                    color: intensity > 160 ? '#fff' : 'var(--text)',
                    textAlign: 'right',
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

export default function PivotPanel() {
  const [rowDim, setRowDim] = useState('customerType');
  const [colDim, setColDim] = useState('year');
  const [result, setResult] = useState<OlapResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<'heatmap' | 'chart'>('heatmap');

  const run = async () => {
    if (rowDim === colDim) return;
    setLoading(true);
    setError(null);
    try {
      setResult(await api.pivot(rowDim, colDim));
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  const availableCols = DIMS.filter(d => d.value !== rowDim);

  return (
    <div>
      <PanelHeader
        title="Pivot"
        description="Rotate the data view by cross-tabulating two dimensions. The result is a matrix where each cell shows the Total Amount at the intersection of a row and column dimension."
        badge="OLAP Operation 5"
      />

      <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)', marginBottom: 16 }}>
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-end', flexWrap: 'wrap' }}>
          <SelectField
            label="Row dimension"
            value={rowDim}
            onChange={v => { setRowDim(v); if (v === colDim) setColDim(DIMS.find(d => d.value !== v)!.value); setResult(null); }}
            options={DIMS}
          />
          <div style={{ fontSize: 22, color: 'var(--text-muted)', paddingBottom: 8 }}>×</div>
          <SelectField
            label="Column dimension"
            value={colDim}
            onChange={v => { setColDim(v); setResult(null); }}
            options={availableCols}
          />
          <button
            onClick={run}
            disabled={rowDim === colDim}
            style={{ background: 'var(--primary)', color: '#fff', padding: '8px 20px', fontWeight: 600, marginBottom: 0, alignSelf: 'flex-end' }}
          >
            Generate Pivot
          </button>
        </div>
      </div>

      {result && (
        <>
          <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
            <span style={{ fontSize: 12, color: 'var(--text-muted)', alignSelf: 'center' }}>View:</span>
            {(['heatmap', 'chart'] as const).map(v => (
              <button
                key={v}
                onClick={() => setView(v)}
                style={{
                  padding: '4px 12px',
                  background: view === v ? 'var(--primary)' : '#fff',
                  color: view === v ? '#fff' : 'var(--text)',
                  border: `1px solid ${view === v ? 'var(--primary)' : 'var(--border)'}`,
                  fontSize: 12,
                }}
              >
                {v.charAt(0).toUpperCase() + v.slice(1)}
              </button>
            ))}
          </div>

          <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)', marginBottom: 16 }}>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 12 }}>
              Total Amount: <strong>{DIMS.find(d => d.value === rowDim)?.label}</strong> (rows) × <strong>{DIMS.find(d => d.value === colDim)?.label}</strong> (columns)
            </div>
            {view === 'heatmap' ? (
              <HeatTable result={result} />
            ) : (
              <GroupedBarChart result={result} height={320} />
            )}
          </div>
        </>
      )}
      {loading && <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Loading...</div>}
      {error && <div style={{ padding: 16, color: 'var(--danger)', background: 'var(--danger-light)', borderRadius: 'var(--radius)' }}>{error}</div>}
    </div>
  );
}
