using api.Models;

namespace api.Services;

public interface IOlapService
{
    Task<OlapResult> RollUp(string level);
    Task<OlapResult> DrillDown(string parentLevel, string parentKey);
    Task<OlapResult> Slice(string sliceDim, string sliceKey, string rows);
    Task<OlapResult> Dice(int? fromTimeId, int? toTimeId, string? customerType, string? city, string rows);
    Task<OlapResult> Pivot(string rowDim, string colDim);
    Task<KpiData> GetKpi();
    Task<OlapResult> GetSalesTrend(string groupBy);
    Task<OlapResult> GetSalesByCity();
    Task<OlapResult> GetSalesByProduct(int? topN = null);
}
