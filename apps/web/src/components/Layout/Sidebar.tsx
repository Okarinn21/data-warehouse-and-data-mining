import type { Page } from '../../types';

interface NavItem {
  id: Page;
  label: string;
  icon: string;
  group?: string;
}

const NAV: NavItem[] = [
  { id: 'dashboard', label: 'Dashboard', icon: '▦', group: 'Overview' },
  { id: 'rollup', label: 'Roll-up', icon: '▲', group: 'OLAP Operations' },
  { id: 'drilldown', label: 'Drill-down', icon: '▼', group: 'OLAP Operations' },
  { id: 'slice', label: 'Slice', icon: '◧', group: 'OLAP Operations' },
  { id: 'dice', label: 'Dice', icon: '⬡', group: 'OLAP Operations' },
  { id: 'pivot', label: 'Pivot', icon: '⇄', group: 'OLAP Operations' },
];

interface Props {
  current: Page;
  onChange: (p: Page) => void;
}

export default function Sidebar({ current, onChange }: Props) {
  let lastGroup = '';

  return (
    <aside style={{
      width: 'var(--sidebar-width)',
      minWidth: 'var(--sidebar-width)',
      background: 'var(--sidebar-bg)',
      display: 'flex',
      flexDirection: 'column',
      height: '100vh',
      overflow: 'hidden',
    }}>
      {/* Logo */}
      <div style={{ padding: '20px 20px 16px', borderBottom: '1px solid rgba(255,255,255,0.07)' }}>
        <div style={{ color: '#fff', fontWeight: 700, fontSize: 15, letterSpacing: '-0.3px' }}>
          DataWarehouse
        </div>
        <div style={{ color: 'var(--sidebar-text)', fontSize: 11, marginTop: 2 }}>
          OLAP Analytics Dashboard
        </div>
      </div>

      {/* Nav */}
      <nav style={{ flex: 1, overflowY: 'auto', padding: '8px 0' }}>
        {NAV.map(item => {
          const showGroup = item.group !== lastGroup;
          lastGroup = item.group ?? '';
          const isActive = current === item.id;

          return (
            <div key={item.id}>
              {showGroup && (
                <div style={{
                  padding: '12px 20px 4px',
                  fontSize: 10,
                  fontWeight: 600,
                  textTransform: 'uppercase',
                  letterSpacing: '0.1em',
                  color: 'rgba(148,163,184,0.5)',
                }}>
                  {item.group}
                </div>
              )}
              <button
                onClick={() => onChange(item.id)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10,
                  width: '100%',
                  padding: '9px 20px',
                  background: isActive ? 'rgba(59,130,246,0.15)' : 'transparent',
                  color: isActive ? '#fff' : 'var(--sidebar-text)',
                  borderRadius: 0,
                  borderLeft: isActive ? '3px solid var(--sidebar-accent)' : '3px solid transparent',
                  textAlign: 'left',
                  fontSize: 13.5,
                  fontWeight: isActive ? 600 : 400,
                  transition: 'all 0.15s',
                }}
                onMouseEnter={e => {
                  if (!isActive) (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.05)';
                }}
                onMouseLeave={e => {
                  if (!isActive) (e.currentTarget as HTMLButtonElement).style.background = 'transparent';
                }}
              >
                <span style={{ fontSize: 15, width: 18, textAlign: 'center' }}>{item.icon}</span>
                {item.label}
              </button>
            </div>
          );
        })}
      </nav>

      {/* Footer */}
      <div style={{ padding: '12px 20px', borderTop: '1px solid rgba(255,255,255,0.07)', fontSize: 11, color: 'rgba(148,163,184,0.5)' }}>
        SQL Server Analysis Services
      </div>
    </aside>
  );
}
