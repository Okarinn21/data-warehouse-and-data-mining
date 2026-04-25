import AnalyticsPage from './pages/AnalyticsPage';

export default function App() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh' }}>
      <header style={{
        background: '#0f172a',
        color: '#fff',
        padding: '0 24px',
        height: 52,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        flexShrink: 0,
      }}>
        <span style={{ fontWeight: 700, fontSize: 15 }}>DataWarehouse Analytics</span>
        <span style={{ fontSize: 12, color: '#94a3b8' }}>{new Date().toLocaleDateString()}</span>
      </header>
      <main style={{ flex: 1, overflowY: 'auto', background: 'var(--bg)', padding: '20px 24px' }}>
        <AnalyticsPage />
      </main>
    </div>
  );
}
