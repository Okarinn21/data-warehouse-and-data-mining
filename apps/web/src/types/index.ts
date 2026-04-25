export interface OlapResult {
  operationType: string;
  columnHeaders: string[];
  rows: Record<string, unknown>[];
}

export interface KpiData {
  totalRevenue: number;
  totalQuantity: number;
  totalCustomers: number;
  totalProducts: number;
  totalTransactions: number;
}

export type Page =
  | 'dashboard'
  | 'rollup'
  | 'drilldown'
  | 'slice'
  | 'dice'
  | 'pivot';
