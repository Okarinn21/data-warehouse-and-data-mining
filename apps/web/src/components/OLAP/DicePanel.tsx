import { useState } from 'react';
import { api } from '../../api/client';
import type { OlapResult } from '../../types';
import OlapTable from './OlapTable';
import OlapChart from './OlapChart';
import { PanelHeader, SelectField } from './shared';

const YEARS = ['', '2018','2019','2020','2021','2022','2023','2024','2025'].map(y => ({ value: y, label: y || 'All years' }));
const CUSTOMER_TYPES = [{ value: '', label: 'All types' }, { value: 'DL', label: 'Du lich (DL)' }, { value: 'BP', label: 'Buu dien (BP)' }];
const CITIES = [
  '', 'Ha Noi', 'Ho Chi Minh', 'Da Nang', 'Hai Phong', 'Can Tho',
  'Bien Hoa', 'Hue', 'Nha Trang', 'Vung Tau', 'Quy Nhon',
].map(c => ({ value: c, label: c || 'All cities' }));

const ROW_DIMS = [
  { value: 'city', label: 'City' },
  { value: 'customerType', label: 'Customer Type' },
  { value: 'product', label: 'Product' },
  { value: 'year', label: 'Year' },
  { value: 'quarter', label: 'Quarter' },
];

export default function DicePanel() {
  const [year, setYear] = useState('');
  const [customerType, setCustomerType] = useState('');
  const [city, setCity] = useState('');
  const [rows, setRows] = useState('city');
  const [result, setResult] = useState<OlapResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const run = async () => {
    setLoading(true);
    setError(null);
    try {
      setResult(await api.dice({
        year: year ? parseInt(year) : undefined,
        customerType: customerType || undefined,
        city: city || undefined,
        rows,
      }));
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  const activeFilters = [
    year && `Year = ${year}`,
    customerType && `Type = ${customerType}`,
    city && `City = ${city}`,
  ].filter(Boolean);

  return (
    <div>
      <PanelHeader
        title="Dice"
        description="Apply multiple dimension filters simultaneously. Unlike Slice (one filter), Dice lets you restrict multiple dimensions at once to extract a specific sub-cube."
        badge="OLAP Operation 4"
      />

      <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)', marginBottom: 16 }}>
        <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 12, color: 'var(--text-muted)' }}>
          Apply filters (leave blank to ignore a dimension):
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 16, marginBottom: 16 }}>
          <SelectField label="Year" value={year} onChange={setYear} options={YEARS} />
          <SelectField label="Customer Type" value={customerType} onChange={setCustomerType} options={CUSTOMER_TYPES} />
          <SelectField label="City" value={city} onChange={setCity} options={CITIES} />
          <SelectField label="Show results by" value={rows} onChange={setRows} options={ROW_DIMS} />
        </div>

        {activeFilters.length > 0 && (
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 12 }}>
            <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>Active filters:</span>
            {activeFilters.map((f, i) => (
              <span key={i} style={{
                fontSize: 11, padding: '2px 8px',
                background: 'var(--primary-light)', color: 'var(--primary)',
                borderRadius: 20, fontWeight: 500,
              }}>{f}</span>
            ))}
          </div>
        )}

        <button
          onClick={run}
          style={{ background: 'var(--primary)', color: '#fff', padding: '8px 20px', fontWeight: 600 }}
        >
          Apply Dice
        </button>
      </div>

      {result && (
        <>
          <div style={{ background: 'var(--card-bg)', borderRadius: 'var(--radius-lg)', padding: 20, boxShadow: 'var(--shadow-sm)', marginBottom: 16 }}>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
              {activeFilters.length > 0
                ? `Filtered by: ${activeFilters.join(', ')}`
                : 'No filters applied — showing full data'}
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
