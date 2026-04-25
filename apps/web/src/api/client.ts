import type { KpiData, OlapResult } from '../types';

const BASE = '/api';

async function get<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `HTTP ${res.status}`);
  }
  return res.json();
}

export const api = {
  // Dashboard
  kpi: () => get<KpiData>('/dashboard/kpi'),
  salesTrend: (groupBy: string) => get<OlapResult>(`/dashboard/sales-trend?groupBy=${groupBy}`),
  byCity: () => get<OlapResult>('/dashboard/by-city'),
  byProduct: (topN?: number) => get<OlapResult>(`/dashboard/by-product${topN ? `?topN=${topN}` : ''}`),
  inventory: (year?: number) => get<OlapResult>(`/dashboard/inventory${year ? `?year=${year}` : ''}`),

  // OLAP
  rollup: (level: string) => get<OlapResult>(`/olap/rollup?level=${level}`),

  drilldown: (parentLevel: string, parentKey: string) =>
    get<OlapResult>(`/olap/drilldown?parentLevel=${parentLevel}&parentKey=${encodeURIComponent(parentKey)}`),

  slice: (sliceDim: string, sliceKey: string, rows: string) =>
    get<OlapResult>(`/olap/slice?sliceDim=${sliceDim}&sliceKey=${encodeURIComponent(sliceKey)}&rows=${rows}`),

  dice: (params: { fromTimeId?: number; toTimeId?: number; customerType?: string; city?: string; rows: string }) => {
    const qs = new URLSearchParams({ rows: params.rows });
    if (params.fromTimeId) qs.set('fromTimeId', String(params.fromTimeId));
    if (params.toTimeId) qs.set('toTimeId', String(params.toTimeId));
    if (params.customerType) qs.set('customerType', params.customerType);
    if (params.city) qs.set('city', params.city);
    return get<OlapResult>(`/olap/dice?${qs}`);
  },

  pivot: (rowDim: string, colDim: string) =>
    get<OlapResult>(`/olap/pivot?rowDim=${rowDim}&colDim=${colDim}`),
};
