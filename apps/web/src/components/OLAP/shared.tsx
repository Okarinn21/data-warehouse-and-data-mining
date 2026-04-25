interface PanelHeaderProps {
  title: string;
  description: string;
  badge: string;
}

export function PanelHeader({ title, description, badge }: PanelHeaderProps) {
  return (
    <div style={{ marginBottom: 20 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
        <h2 style={{ fontSize: 18, fontWeight: 700, color: 'var(--text)', margin: 0 }}>{title}</h2>
        <span style={{
          fontSize: 10, fontWeight: 600, padding: '2px 8px',
          background: 'var(--primary-light)', color: 'var(--primary)',
          borderRadius: 20, letterSpacing: '0.05em',
        }}>
          {badge}
        </span>
      </div>
      <p style={{ fontSize: 13, color: 'var(--text-muted)', lineHeight: 1.6, maxWidth: 700 }}>
        {description}
      </p>
    </div>
  );
}

interface SelectFieldProps {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}

export function SelectField({ label, value, onChange, options }: SelectFieldProps) {
  return (
    <div>
      <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-muted)', marginBottom: 4, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
        {label}
      </div>
      <select value={value} onChange={e => onChange(e.target.value)} style={{ width: '100%' }}>
        {options.map(o => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </div>
  );
}
