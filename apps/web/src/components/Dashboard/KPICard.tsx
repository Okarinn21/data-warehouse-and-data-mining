interface Props {
  title: string;
  value: string | number;
  subtitle?: string;
  color?: string;
  colorLight?: string;
  icon: string;
}

function formatNumber(v: number): string {
  if (v >= 1_000_000_000) return (v / 1_000_000_000).toFixed(1) + 'B';
  if (v >= 1_000_000) return (v / 1_000_000).toFixed(1) + 'M';
  if (v >= 1_000) return (v / 1_000).toFixed(1) + 'K';
  return v.toLocaleString();
}

export default function KPICard({ title, value, subtitle, color = 'var(--primary)', colorLight = 'var(--primary-light)', icon }: Props) {
  const display = typeof value === 'number' ? formatNumber(value) : value;

  return (
    <div style={{
      background: 'var(--card-bg)',
      borderRadius: 'var(--radius-lg)',
      padding: '20px 24px',
      boxShadow: 'var(--shadow-sm)',
      display: 'flex',
      alignItems: 'flex-start',
      gap: 16,
      flex: '1 1 200px',
      minWidth: 0,
    }}>
      <div style={{
        width: 44,
        height: 44,
        borderRadius: 10,
        background: colorLight,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 20,
        flexShrink: 0,
      }}>
        {icon}
      </div>
      <div style={{ minWidth: 0 }}>
        <div style={{ fontSize: 12, color: 'var(--text-muted)', fontWeight: 500, marginBottom: 4 }}>
          {title}
        </div>
        <div style={{ fontSize: 26, fontWeight: 700, color, lineHeight: 1.1, letterSpacing: '-0.5px' }}>
          {display}
        </div>
        {subtitle && (
          <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
            {subtitle}
          </div>
        )}
      </div>
    </div>
  );
}
