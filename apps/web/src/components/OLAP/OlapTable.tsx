import type { OlapResult } from '../../types';

function fmt(v: unknown): string {
  if (v == null) return '—';
  if (typeof v === 'number') {
    if (v >= 1_000_000) return (v / 1_000_000).toFixed(2) + 'M';
    if (v >= 1_000) return (v / 1_000).toFixed(2) + 'K';
    return v.toLocaleString(undefined, { maximumFractionDigits: 2 });
  }
  return String(v);
}

interface Props {
  result: OlapResult | null;
  loading?: boolean;
  error?: string | null;
  onRowClick?: (row: Record<string, unknown>, label: string) => void;
  clickableRows?: boolean;
}

export default function OlapTable({ result, loading, error, onRowClick, clickableRows }: Props) {
  if (loading) {
    return (
      <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>
        Loading...
      </div>
    );
  }
  if (error) {
    return (
      <div style={{ padding: 20, color: 'var(--danger)', background: 'var(--danger-light)', borderRadius: 'var(--radius)', fontSize: 13 }}>
        {error}
      </div>
    );
  }
  if (!result || result.rows.length === 0) {
    return (
      <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>
        No data
      </div>
    );
  }

  return (
    <div style={{ overflowX: 'auto', borderRadius: 'var(--radius)', border: '1px solid var(--border)' }}>
      <table>
        <thead>
          <tr>
            {result.columnHeaders.map(h => (
              <th key={h}>{h}</th>
            ))}
            {clickableRows && <th style={{ width: 60 }}></th>}
          </tr>
        </thead>
        <tbody>
          {result.rows.map((row, i) => (
            <tr
              key={i}
              style={{ cursor: clickableRows ? 'pointer' : undefined }}
              onClick={() => clickableRows && onRowClick?.(row, String(row['Label']))}
            >
              {result.columnHeaders.map(h => (
                <td key={h} style={{ fontWeight: h === 'Label' ? 500 : 400 }}>
                  {h === 'Label' ? String(row[h] ?? '') : fmt(row[h])}
                </td>
              ))}
              {clickableRows && (
                <td style={{ color: 'var(--primary)', fontSize: 12 }}>Drill ▶</td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
