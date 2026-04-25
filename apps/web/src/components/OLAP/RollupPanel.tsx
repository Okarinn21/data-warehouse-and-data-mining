import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import type { OlapResult } from '../../types';
import OlapTable from './OlapTable';
import OlapChart from './OlapChart';
import { PanelHeader } from './shared';

const LEVELS = [
  { value: 'year', label: 'Year (most aggregated)' },
  { value: 'quarter', label: 'Quarter' },
  { value: 'month', label: 'Month (most detailed)' },
];

export default function RollupPanel() {
  const [level, setLevel] = useState('year');
  const [result, setResult] = useState<OlapResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = async (lv: string) => {
    setLoading(true);
    setError(null);
    try {
      setResult(await api.rollup(lv));
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(level); }, [level]);

  return (
    <div>
      <PanelHeader
        title="Roll-up"
        description="Aggregate sales data by climbing up the time hierarchy. Starting from Month detail, roll up to Quarter or Year for a higher-level view."
        badge="OLAP Operation 1"
      />

      <div style={{ display: 'flex', gap: 12, marginBottom: 20, flexWrap: 'wrap' }}>
        {LEVELS.map(lv => (
          <button
            key={lv.value}
            onClick={() => setLevel(lv.value)}
            style={{
              padding: '8px 18px',
              background: level === lv.value ? 'var(--primary)' : '#fff',
              color: level === lv.value ? '#fff' : 'var(--text)',
              border: `1px solid ${level === lv.value ? 'var(--primary)' : 'var(--border)'}`,
              fontWeight: level === lv.value ? 600 : 400,
              boxShadow: level === lv.value ? '0 2px 8px rgba(59,130,246,0.25)' : 'none',
            }}
          >
            {lv.label}
          </button>
        ))}
      </div>

      <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)', marginBottom: 16 }}>
        <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-muted)', marginBottom: 12 }}>
          Total Revenue by {level.charAt(0).toUpperCase() + level.slice(1)}
        </div>
        <OlapChart result={result} valueKey="Total Amount" />
      </div>

      <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)' }}>
        <OlapTable result={result} loading={loading} error={error} />
      </div>
    </div>
  );
}
