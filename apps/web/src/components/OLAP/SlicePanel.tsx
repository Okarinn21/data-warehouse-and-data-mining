import { useState } from 'react';
import { api } from '../../api/client';
import type { OlapResult } from '../../types';
import OlapTable from './OlapTable';
import OlapChart from './OlapChart';
import { PanelHeader, SelectField } from './shared';

const SLICE_DIMS = [
  { value: 'year', label: 'Year' },
  { value: 'customerType', label: 'Customer Type' },
  { value: 'city', label: 'City' },
];

const SLICE_KEYS: Record<string, { value: string; label: string }[]> = {
  year: ['2010','2011','2012','2013','2014','2015','2016','2017','2018','2019','2020','2021','2022','2023','2024','2025'].map(y => ({ value: y, label: y })),
  customerType: [{ value: 'DL', label: 'Du lich (DL)' }, { value: 'BP', label: 'Buu dien (BP)' }],
  city: [
    'Ha Noi','Ho Chi Minh','Da Nang','Hai Phong','Can Tho','Bien Hoa','Hue','Nha Trang','Vung Tau','Quy Nhon'
  ].map(c => ({ value: c, label: c })),
};

const ROW_DIMS = [
  { value: 'year', label: 'Year' },
  { value: 'quarter', label: 'Quarter' },
  { value: 'city', label: 'City' },
  { value: 'customerType', label: 'Customer Type' },
  { value: 'product', label: 'Product' },
];

export default function SlicePanel() {
  const [sliceDim, setSliceDim] = useState('year');
  const [sliceKey, setSliceKey] = useState('2024');
  const [rows, setRows] = useState('city');
  const [result, setResult] = useState<OlapResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSliceDimChange = (v: string) => {
    setSliceDim(v);
    setSliceKey(SLICE_KEYS[v]?.[0]?.value ?? '');
    setResult(null);
  };

  const run = async () => {
    if (!sliceKey) return;
    setLoading(true);
    setError(null);
    try {
      setResult(await api.slice(sliceDim, sliceKey, rows));
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  const availableRowDims = ROW_DIMS.filter(r => r.value !== sliceDim);

  return (
    <div>
      <PanelHeader
        title="Slice"
        description="Fix one dimension to a single value and analyze all other dimensions. For example, slice by Year=2024 to see all cities' performance in that year only."
        badge="OLAP Operation 3"
      />

      <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)', marginBottom: 16 }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 16, marginBottom: 16 }}>
          <SelectField
            label="Slice dimension (fixed)"
            value={sliceDim}
            onChange={handleSliceDimChange}
            options={SLICE_DIMS}
          />
          <SelectField
            label="Value to fix"
            value={sliceKey}
            onChange={setSliceKey}
            options={SLICE_KEYS[sliceDim] ?? []}
          />
          <SelectField
            label="Analyze by (rows)"
            value={rows}
            onChange={setRows}
            options={availableRowDims}
          />
        </div>
        <button
          onClick={run}
          style={{ background: 'var(--primary)', color: '#fff', padding: '8px 20px', fontWeight: 600 }}
        >
          Apply Slice
        </button>
      </div>

      {result && (
        <>
          <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)', marginBottom: 16 }}>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
              Revenue when <strong>{SLICE_DIMS.find(d => d.value === sliceDim)?.label}</strong> = <strong>"{sliceKey}"</strong>, grouped by <strong>{ROW_DIMS.find(d => d.value === rows)?.label}</strong>
            </div>
            <OlapChart result={result} valueKey="Total Amount" />
          </div>
          <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)' }}>
            <OlapTable result={result} loading={loading} error={error} />
          </div>
        </>
      )}
      {loading && <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Loading...</div>}
      {error && <div style={{ padding: 16, color: 'var(--danger)', background: 'var(--danger-light)', borderRadius: 'var(--radius)' }}>{error}</div>}
    </div>
  );
}
