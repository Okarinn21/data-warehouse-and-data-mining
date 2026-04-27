import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import type { OlapResult } from '../../types';
import OlapTable from './OlapTable';
import OlapChart from './OlapChart';
import { PanelHeader } from './shared';

interface Breadcrumb {
  label: string;
  parentLevel: string;
  parentKey: string;
}

export default function DrilldownPanel() {
  const [result, setResult] = useState<OlapResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [breadcrumbs, setBreadcrumbs] = useState<Breadcrumb[]>([]);
  const [currentLevel, setCurrentLevel] = useState('year');

  const loadTop = async () => {
    setLoading(true);
    setError(null);
    try {
      setResult(await api.rollup('year'));
      setCurrentLevel('year');
      setBreadcrumbs([]);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { loadTop(); }, []);

  const handleDrill = async (row: Record<string, unknown>, label: string) => {
    if (currentLevel === 'month') return;

    let nextLevel: string;
    let parentKey: string;

    if (currentLevel === 'year') {
      // label = "2010", "2011"
      nextLevel = 'quarter';
      parentKey = label;
    } else {
    // currentLevel === 'quarter'
    // row['Year'] có sẵn từ response API
    const yearStr = String(row['Year'] ?? '');
    const quarterNum = label.replace(/\D/g, ''); // "Q1" → "1"
    nextLevel = 'month';
    parentKey = `${yearStr}:${quarterNum}`; // "2010:1" ✅
  }

    setLoading(true);
    setError(null);
    try {
      const data = await api.drilldown(currentLevel, parentKey);
      setBreadcrumbs(prev => [...prev, { label, parentLevel: currentLevel, parentKey }]);
      setCurrentLevel(nextLevel);
      setResult(data);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  const handleBreadcrumb = async (idx: number) => {
    if (idx < 0) {
      await loadTop();
      return;
    }
    const crumb = breadcrumbs[idx];
    setLoading(true);
    setError(null);
    try {
      const data = await api.drilldown(crumb.parentLevel, crumb.parentKey);
      setBreadcrumbs(prev => prev.slice(0, idx + 1));
      setCurrentLevel(idx === 0 ? 'quarter' : 'month');
      setResult(data);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  const levelLabel = { year: 'Year', quarter: 'Quarter', month: 'Month' }[currentLevel];

  return (
    <div>
      <PanelHeader
        title="Drill-down"
        description="Navigate from a high-level summary to granular detail. Click any row to drill down from Year → Quarter → Month."
        badge="OLAP Operation 2"
      />

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16, fontSize: 13 }}>
        <span
          style={{ color: 'var(--primary)', cursor: 'pointer', fontWeight: 500 }}
          onClick={() => handleBreadcrumb(-1)}
        >
          All Years
        </span>
        {breadcrumbs.map((b, i) => (
          <span key={i} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ color: 'var(--text-muted)' }}>›</span>
            <span
              style={{
                color: i === breadcrumbs.length - 1 ? 'var(--text)' : 'var(--primary)',
                cursor: i < breadcrumbs.length - 1 ? 'pointer' : 'default',
                fontWeight: 500
              }}
              onClick={() => i < breadcrumbs.length - 1 && handleBreadcrumb(i)}
            >
              {b.label}
            </span>
          </span>
        ))}
      </div>

      <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 16 }}>
        Current level: <strong>{levelLabel}</strong>
        {currentLevel !== 'month' && ' — click a row to drill down'}
      </div>

      <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)', marginBottom: 16 }}>
        <OlapChart result={result} valueKey="Total Amount" onBarClick={handleDrill} />
      </div>

      <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)' }}>
        <OlapTable
          result={result}
          loading={loading}
          error={error}
          clickableRows={currentLevel !== 'month'}
          onRowClick={handleDrill}
        />
      </div>
    </div>
  );
}