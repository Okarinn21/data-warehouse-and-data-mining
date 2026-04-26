using api.Models;
using Dapper;
using Microsoft.AnalysisServices.AdomdClient;
using Microsoft.Data.SqlClient;

namespace api.Services;

public class OlapService : IOlapService
{
    private readonly string _sqlCs;
    private readonly string _ssasCs;
    private readonly bool _useSsas;
    private readonly ILogger<OlapService> _logger;

    // MDX measure set used in all sale cube queries
    private const string SaleMeasures = "{[Measures].[Total Amount], [Measures].[Quantity]}";

    public OlapService(IConfiguration config, ILogger<OlapService> logger)
    {
        _sqlCs = config.GetConnectionString("SqlServer")!;
        _ssasCs = config.GetConnectionString("SSAS")!;
        _useSsas = config.GetValue<bool>("OlapSettings:UseSsas");
        _logger = logger;
    }

    // ── MDX execution ─────────────────────────────────────────────────────────

    private OlapResult ExecuteMdx(string operationType, string mdx)
    {
        using var conn = new AdomdConnection(_ssasCs);
        conn.Open();
        using var cmd = new AdomdCommand(mdx, conn);
        var cs = cmd.ExecuteCellSet();

        int colCount = cs.Axes[0].Positions.Count;
        var colHeaders = Enumerable.Range(0, colCount)
            .Select(i => cs.Axes[0].Positions[i].Members[0].Caption)
            .ToList();

        int rowCount = cs.Axes[1].Positions.Count;
        var rows = new List<Dictionary<string, object?>>();

        for (int r = 0; r < rowCount; r++)
        {
            var dict = new Dictionary<string, object?>
            {
                ["Label"] = cs.Axes[1].Positions[r].Members[0].Caption
            };
            for (int c = 0; c < colCount; c++)
            {
                var cell = cs.Cells[c + r * colCount];
                dict[colHeaders[c]] = cell.Value == DBNull.Value ? null : cell.Value;
            }
            rows.Add(dict);
        }

        var headers = new List<string> { "Label" };
        headers.AddRange(colHeaders);
        return new OlapResult(operationType, headers, rows);
    }

    // ── SQL helpers ────────────────────────────────────────────────────────────

    private static OlapResult FormatDynamicResult(string operationType, IEnumerable<dynamic> result)
    {
        var list = result.Cast<IDictionary<string, object>>().ToList();
        if (!list.Any())
            return new OlapResult(operationType, [], []);

        var headers = list[0].Keys.ToList();
        var rows = list.Select(r => r.ToDictionary(k => k.Key, k => (object?)k.Value)).ToList();
        return new OlapResult(operationType, headers, rows);
    }

    // ── Roll-up ────────────────────────────────────────────────────────────────

    public async Task<OlapResult> RollUp(string level)
    {
        if (_useSsas)
        {
            try
            {
                string rowSet = level switch
                {
                    "year" => "ORDER([Dim Time].[Year].[Year].Members, [Dim Time].[Year].CurrentMember.Name, ASC)",
                    "quarter" => "ORDER([Dim Time].[Quarter].[Quarter].Members, [Dim Time].[Quarter].CurrentMember.Name, ASC)",
                    "month" => "ORDER([Dim Time].[Month].[Month].Members, [Dim Time].[Month].CurrentMember.Name, ASC)",
                    _ => throw new ArgumentException($"Invalid level: {level}")
                };
                string mdx = "SELECT NON EMPTY " + SaleMeasures + " ON COLUMNS, "
                    + "NON EMPTY " + rowSet + " ON ROWS FROM [sale]";
                return ExecuteMdx("ROLLUP", mdx);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("SSAS MDX failed, using SQL: {msg}", ex.Message);
            }
        }
        return await RollUpSql(level);
    }

    private async Task<OlapResult> RollUpSql(string level)
    {
        string sql = level switch
        {
            "year" => """
                SELECT CAST(t.Year AS NVARCHAR(4)) AS Label,
                    SUM(s.TotalAmount) AS [Total Amount],
                    SUM(s.Quantity) AS Quantity,
                    COUNT(*) AS Transactions
                FROM DataWarehouse.dbo.Fact_Sales s
                JOIN DataWarehouse.dbo.Dim_Time t ON s.TimeID = t.TimeID
                GROUP BY t.Year
                ORDER BY t.Year
                """,
            "quarter" => """
                SELECT CAST(t.Year AS NVARCHAR(4)) + '-Q' + CAST(t.Quarter AS NVARCHAR(1)) AS Label,
                    t.Year, t.Quarter,
                    SUM(s.TotalAmount) AS [Total Amount],
                    SUM(s.Quantity) AS Quantity,
                    COUNT(*) AS Transactions
                FROM DataWarehouse.dbo.Fact_Sales s
                JOIN DataWarehouse.dbo.Dim_Time t ON s.TimeID = t.TimeID
                GROUP BY t.Year, t.Quarter
                ORDER BY t.Year, t.Quarter
                """,
            "month" => """
                SELECT CAST(t.Year AS NVARCHAR(4)) + '-' + RIGHT('0' + CAST(t.Month AS NVARCHAR(2)), 2) AS Label,
                    t.Year, t.Quarter, t.Month,
                    SUM(s.TotalAmount) AS [Total Amount],
                    SUM(s.Quantity) AS Quantity,
                    COUNT(*) AS Transactions
                FROM DataWarehouse.dbo.Fact_Sales s
                JOIN DataWarehouse.dbo.Dim_Time t ON s.TimeID = t.TimeID
                GROUP BY t.Year, t.Quarter, t.Month
                ORDER BY t.Year, t.Quarter, t.Month
                """,
            _ => throw new ArgumentException($"Invalid level: {level}")
        };
        using var conn = new SqlConnection(_sqlCs);
        return FormatDynamicResult("ROLLUP", await conn.QueryAsync(sql));
    }

    // ── Drill-down ─────────────────────────────────────────────────────────────
    // parentKey format: "2024" for year, "2024:1" for year:quarter

    public async Task<OlapResult> DrillDown(string parentLevel, string parentKey)
    {
        if (_useSsas)
        {
            try
            {
                string mdx;
                if (parentLevel == "year")
                {
                    mdx = "SELECT NON EMPTY " + SaleMeasures + " ON COLUMNS, "
                        + $"NON EMPTY [Dim Time].[Hierarchy].[Year].&[{parentKey}].Children ON ROWS FROM [sale]";
                }
                else if (parentLevel == "quarter")
                {
                    var parts = parentKey.Split(':');
                    if (parts.Length != 2) throw new ArgumentException("Quarter key must be year:quarter");
                    mdx = "SELECT NON EMPTY " + SaleMeasures + " ON COLUMNS, "
                        + $"NON EMPTY [Dim Time].[Hierarchy].[Quarter].&[{parts[1]}]&[{parts[0]}].Children ON ROWS FROM [sale]";
                }
                else throw new ArgumentException($"Invalid parentLevel: {parentLevel}");

                return ExecuteMdx("DRILLDOWN", mdx);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("SSAS MDX failed, using SQL: {msg}", ex.Message);
            }
        }
        return await DrillDownSql(parentLevel, parentKey);
    }

    private async Task<OlapResult> DrillDownSql(string parentLevel, string parentKey)
    {
        using var conn = new SqlConnection(_sqlCs);
        if (parentLevel == "year")
        {
            int year = int.Parse(parentKey);
            const string sql = """
                SELECT 'Q' + CAST(t.Quarter AS NVARCHAR(1)) AS Label,
                    t.Quarter,
                    SUM(s.TotalAmount) AS [Total Amount],
                    SUM(s.Quantity) AS Quantity,
                    COUNT(*) AS Transactions
                FROM DataWarehouse.dbo.Fact_Sales s
                JOIN DataWarehouse.dbo.Dim_Time t ON s.TimeID = t.TimeID
                WHERE t.Year = @Year
                GROUP BY t.Quarter
                ORDER BY t.Quarter
                """;
            return FormatDynamicResult("DRILLDOWN", await conn.QueryAsync(sql, new { Year = year }));
        }
        if (parentLevel == "quarter")
        {
            var parts = parentKey.Split(':');
            int year = int.Parse(parts[0]);
            int quarter = int.Parse(parts[1]);
            const string sql = """
                SELECT RIGHT('0' + CAST(t.Month AS NVARCHAR(2)), 2) + '/' + CAST(t.Year AS NVARCHAR(4)) AS Label,
                    t.Month,
                    SUM(s.TotalAmount) AS [Total Amount],
                    SUM(s.Quantity) AS Quantity,
                    COUNT(*) AS Transactions
                FROM DataWarehouse.dbo.Fact_Sales s
                JOIN DataWarehouse.dbo.Dim_Time t ON s.TimeID = t.TimeID
                WHERE t.Year = @Year AND t.Quarter = @Quarter
                GROUP BY t.Month
                ORDER BY t.Month
                """;
            return FormatDynamicResult("DRILLDOWN", await conn.QueryAsync(sql, new { Year = year, Quarter = quarter }));
        }
        throw new ArgumentException($"Invalid parentLevel: {parentLevel}");
    }

    // ── Slice ──────────────────────────────────────────────────────────────────
    // Fix one dimension value and analyze the rest.

    public async Task<OlapResult> Slice(string sliceDim, string sliceKey, string rows)
    {
        if (_useSsas)
        {
            try
            {
                string slicer = sliceDim switch
                {
                    "year" => $"[Dim Time].[Year].&[{sliceKey}]",
                    "customerType" => $"[Dim Customer].[Loai KH].&[{sliceKey}]",
                    "city" => $"[Dim Customer].[Thanh Pho].&[{sliceKey}]",
                    "product" => $"[Dim Product].[Mo Ta].&[{sliceKey}]",
                    _ => throw new ArgumentException($"Invalid sliceDim: {sliceDim}")
                };
                string rowSet = GetMdxMembers(rows);
                string mdx = "SELECT NON EMPTY " + SaleMeasures + " ON COLUMNS, "
                    + "NON EMPTY " + rowSet + " ON ROWS FROM [sale] WHERE " + slicer;
                return ExecuteMdx("SLICE", mdx);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("SSAS MDX failed, using SQL: {msg}", ex.Message);
            }
        }
        return await SliceSql(sliceDim, sliceKey, rows);
    }

    private async Task<OlapResult> SliceSql(string sliceDim, string sliceKey, string rowDim)
    {
        using var conn = new SqlConnection(_sqlCs);
        var (whereClause, param) = BuildWhereForSingleDim(sliceDim, sliceKey);
        var (selectCol, groupOrder) = GetSqlDimExpr(rowDim);
        string joins = BuildJoins(sliceDim, rowDim);

        string sql = $"""
            SELECT {selectCol} AS Label,
                SUM(s.TotalAmount) AS [Total Amount],
                SUM(s.Quantity) AS Quantity,
                COUNT(*) AS Transactions
            FROM DataWarehouse.dbo.Fact_Sales s
            JOIN DataWarehouse.dbo.Dim_Time t ON s.TimeID = t.TimeID
            {joins}
            WHERE {whereClause}
            GROUP BY {groupOrder.GroupBy}
            ORDER BY {groupOrder.OrderBy}
            """;
        return FormatDynamicResult("SLICE", await conn.QueryAsync(sql, param));
    }

    // ── Dice ───────────────────────────────────────────────────────────────────
    // Fix multiple dimension values and analyze.

    // fromTimeId / toTimeId use YYYYMM format matching Dim_Time.TimeID (Year*100+Month)
    public async Task<OlapResult> Dice(int? fromTimeId, int? toTimeId, string? customerType, string? city, string rows)
    {
        // Month-range time filtering is complex in MDX; use SQL path when time range is specified
        bool hasTimeRange = fromTimeId.HasValue || toTimeId.HasValue;
        if (_useSsas && !hasTimeRange)
        {
            try
            {
                var whereParts = new List<string>();
                if (!string.IsNullOrEmpty(customerType)) whereParts.Add($"[Dim Customer].[Loai KH].&[{customerType}]");
                if (!string.IsNullOrEmpty(city)) whereParts.Add($"[Dim Customer].[Thanh Pho].&[{city}]");

                string rowSet = GetMdxMembers(rows);
                string whereClause = whereParts.Count > 0
                    ? " WHERE (" + string.Join(", ", whereParts) + ")"
                    : "";

                string mdx = "SELECT NON EMPTY " + SaleMeasures + " ON COLUMNS, "
                    + "NON EMPTY " + rowSet + " ON ROWS FROM [sale]" + whereClause;
                return ExecuteMdx("DICE", mdx);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("SSAS MDX failed, using SQL: {msg}", ex.Message);
            }
        }
        return await DiceSql(fromTimeId, toTimeId, customerType, city, rows);
    }

    private async Task<OlapResult> DiceSql(int? fromTimeId, int? toTimeId, string? customerType, string? city, string rowDim)
    {
        using var conn = new SqlConnection(_sqlCs);

        var whereParts = new List<string>();
        if (fromTimeId.HasValue && toTimeId.HasValue)
            whereParts.Add("t.TimeID BETWEEN @FromTimeId AND @ToTimeId");
        else if (fromTimeId.HasValue)
            whereParts.Add("t.TimeID >= @FromTimeId");
        else if (toTimeId.HasValue)
            whereParts.Add("t.TimeID <= @ToTimeId");

        if (!string.IsNullOrEmpty(customerType)) whereParts.Add("c.LoaiKH = @CustomerType");
        if (!string.IsNullOrEmpty(city)) whereParts.Add("c.ThanhPho = @City");

        string whereClause = whereParts.Count > 0 ? "WHERE " + string.Join(" AND ", whereParts) : "";
        var (selectCol, groupOrder) = GetSqlDimExpr(rowDim);

        bool needsCustomer = rowDim is "city" or "customerType"
            || !string.IsNullOrEmpty(customerType)
            || !string.IsNullOrEmpty(city);
        bool needsProduct = rowDim == "product";

        string joins = "";
        if (needsCustomer) joins += "JOIN DataWarehouse.dbo.Dim_Customer c ON s.CustomerID = c.CustomerID\n";
        if (needsProduct) joins += "JOIN DataWarehouse.dbo.Dim_Product p ON s.ProductID = p.ProductID\n";

        string sql = $"""
            SELECT {selectCol} AS Label,
                SUM(s.TotalAmount) AS [Total Amount],
                SUM(s.Quantity) AS Quantity,
                COUNT(*) AS Transactions
            FROM DataWarehouse.dbo.Fact_Sales s
            JOIN DataWarehouse.dbo.Dim_Time t ON s.TimeID = t.TimeID
            {joins}
            {whereClause}
            GROUP BY {groupOrder.GroupBy}
            ORDER BY {groupOrder.OrderBy}
            """;
        return FormatDynamicResult("DICE", await conn.QueryAsync(sql,
            new { FromTimeId = fromTimeId, ToTimeId = toTimeId, CustomerType = customerType, City = city }));
    }

    // ── Pivot ──────────────────────────────────────────────────────────────────
    // Cross-tabulate row and column dimensions.

    public async Task<OlapResult> Pivot(string rowDim, string colDim)
    {
        if (_useSsas)
        {
            try
            {
                string rowSet = GetMdxMembers(rowDim);
                string colSet = GetMdxMembers(colDim);
                // WHERE clause specifies the measure as the slicer axis
                string mdx = "SELECT NON EMPTY " + colSet + " ON COLUMNS, "
                    + "NON EMPTY " + rowSet + " ON ROWS FROM [sale] "
                    + "WHERE {[Measures].[Total Amount]}";
                return ExecuteMdx("PIVOT", mdx);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("SSAS MDX failed, using SQL: {msg}", ex.Message);
            }
        }
        return await PivotSql(rowDim, colDim);
    }

    private async Task<OlapResult> PivotSql(string rowDim, string colDim)
    {
        using var conn = new SqlConnection(_sqlCs);
        var (rowSelect, rowGroupOrder) = GetSqlDimExpr(rowDim);
        var (colSelect, colGroupOrder) = GetSqlDimExpr(colDim);

        bool needsCustomer = rowDim is "city" or "customerType" || colDim is "city" or "customerType";
        bool needsProduct = rowDim == "product" || colDim == "product";

        string joins = "";
        if (needsCustomer) joins += "JOIN DataWarehouse.dbo.Dim_Customer c ON s.CustomerID = c.CustomerID\n";
        if (needsProduct) joins += "JOIN DataWarehouse.dbo.Dim_Product p ON s.ProductID = p.ProductID\n";

        string sql = $"""
            SELECT {rowSelect} AS RowKey, {colSelect} AS ColKey,
                SUM(s.TotalAmount) AS TotalAmount
            FROM DataWarehouse.dbo.Fact_Sales s
            JOIN DataWarehouse.dbo.Dim_Time t ON s.TimeID = t.TimeID
            {joins}
            GROUP BY {rowGroupOrder.GroupBy}, {colGroupOrder.GroupBy}
            ORDER BY {rowGroupOrder.GroupBy}, {colGroupOrder.GroupBy}
            """;

        var rawData = (await conn.QueryAsync(sql))
            .Cast<IDictionary<string, object>>()
            .ToList();

        return PivotInMemory(rawData);
    }

    private static OlapResult PivotInMemory(IList<IDictionary<string, object>> data)
    {
        var colValues = data
            .Select(r => r["ColKey"]?.ToString() ?? "")
            .Distinct()
            .OrderBy(x => x)
            .ToList();

        var rows = data
            .GroupBy(r => r["RowKey"]?.ToString() ?? "")
            .Select(g =>
            {
                var row = new Dictionary<string, object?> { ["Label"] = g.Key };
                foreach (var col in colValues)
                {
                    var match = g.FirstOrDefault(r => r["ColKey"]?.ToString() == col);
                    row[col] = match?["TotalAmount"];
                }
                return row;
            })
            .ToList();

        var headers = new List<string> { "Label" };
        headers.AddRange(colValues);
        return new OlapResult("PIVOT", headers, rows);
    }

    // ── Dashboard ──────────────────────────────────────────────────────────────

    public async Task<KpiData> GetKpi()
    {
        using var conn = new SqlConnection(_sqlCs);
        const string sql = """
            SELECT
                COALESCE(SUM(s.TotalAmount), 0) AS TotalRevenue,
                COALESCE(SUM(s.Quantity), 0) AS TotalQuantity,
                COUNT(DISTINCT s.CustomerID) AS TotalCustomers,
                COUNT(DISTINCT s.ProductID) AS TotalProducts,
                COUNT(*) AS TotalTransactions
            FROM DataWarehouse.dbo.Fact_Sales s
            """;
        var r = (IDictionary<string, object>)(await conn.QueryFirstOrDefaultAsync(sql))!;
        return new KpiData(
            Convert.ToDecimal(r["TotalRevenue"]),
            Convert.ToInt64(r["TotalQuantity"]),
            Convert.ToInt32(r["TotalCustomers"]),
            Convert.ToInt32(r["TotalProducts"]),
            Convert.ToInt64(r["TotalTransactions"])
        );
    }

    public Task<OlapResult> GetSalesTrend(string groupBy) => RollUpSql(groupBy);

    public async Task<OlapResult> GetSalesByCity()
    {
        using var conn = new SqlConnection(_sqlCs);
        const string sql = """
            SELECT TOP 10
                c.ThanhPho AS Label,
                SUM(s.TotalAmount) AS [Total Amount],
                SUM(s.Quantity) AS Quantity
            FROM DataWarehouse.dbo.Fact_Sales s
            JOIN DataWarehouse.dbo.Dim_Customer c ON s.CustomerID = c.CustomerID
            GROUP BY c.ThanhPho
            ORDER BY [Total Amount] DESC
            """;
        return FormatDynamicResult("DASHBOARD", await conn.QueryAsync(sql));
    }

    public async Task<OlapResult> GetSalesByProduct(int? topN = null)
    {
        int n = topN ?? 10;
        using var conn = new SqlConnection(_sqlCs);
        string sql = $"""
            SELECT TOP {n}
                p.MoTa AS Label,
                SUM(s.TotalAmount) AS [Total Amount],
                SUM(s.Quantity) AS Quantity
            FROM DataWarehouse.dbo.Fact_Sales s
            JOIN DataWarehouse.dbo.Dim_Product p ON s.ProductID = p.ProductID
            GROUP BY p.MoTa
            ORDER BY [Total Amount] DESC
            """;
        return FormatDynamicResult("DASHBOARD", await conn.QueryAsync(sql));
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private static string GetMdxMembers(string dim) => dim switch
    {
        "year" => "[Dim Time].[Year].[Year].Members",
        "quarter" => "[Dim Time].[Quarter].[Quarter].Members",
        "month" => "[Dim Time].[Month].[Month].Members",
        "customerType" => "[Dim Customer].[Loai KH].[Loai KH].Members",
        "city" => "[Dim Customer].[Thanh Pho].[Thanh Pho].Members",
        "product" => "[Dim Product].[Mo Ta].[Mo Ta].Members",
        _ => throw new ArgumentException($"Invalid dim: {dim}")
    };

    private record GroupOrder(string GroupBy, string OrderBy);

    private static (string SqlExpr, GroupOrder GroupOrder) GetSqlDimExpr(string dim) => dim switch
    {
        "year" => ("CAST(t.Year AS NVARCHAR(4))", new GroupOrder("t.Year", "t.Year")),
        "quarter" => ("CAST(t.Year AS NVARCHAR(4)) + '-Q' + CAST(t.Quarter AS NVARCHAR(1))",
            new GroupOrder("t.Year, t.Quarter", "t.Year, t.Quarter")),
        "month" => ("CAST(t.Year AS NVARCHAR(4)) + '-' + RIGHT('0' + CAST(t.Month AS NVARCHAR(2)), 2)",
            new GroupOrder("t.Year, t.Quarter, t.Month", "t.Year, t.Quarter, t.Month")),
        "customerType" => ("c.LoaiKH", new GroupOrder("c.LoaiKH", "c.LoaiKH")),
        "city" => ("c.ThanhPho", new GroupOrder("c.ThanhPho", "[Total Amount] DESC")),
        "product" => ("p.MoTa", new GroupOrder("p.MoTa", "[Total Amount] DESC")),
        _ => throw new ArgumentException($"Invalid dim: {dim}")
    };

    private static (string Where, object Param) BuildWhereForSingleDim(string sliceDim, string sliceKey)
    {
        return sliceDim switch
        {
            "year" => ("t.Year = @Key", new { Key = (object)int.Parse(sliceKey) }),
            "customerType" => ("c.LoaiKH = @Key", new { Key = (object)sliceKey }),
            "city" => ("c.ThanhPho = @Key", new { Key = (object)sliceKey }),
            "product" => ("p.MoTa = @Key", new { Key = (object)sliceKey }),
            _ => throw new ArgumentException($"Invalid sliceDim: {sliceDim}")
        };
    }

    private static string BuildJoins(string sliceDim, string rowDim)
    {
        bool needsCustomer = sliceDim is "customerType" or "city" || rowDim is "customerType" or "city";
        bool needsProduct = sliceDim == "product" || rowDim == "product";
        string joins = "";
        if (needsCustomer) joins += "JOIN DataWarehouse.dbo.Dim_Customer c ON s.CustomerID = c.CustomerID\n";
        if (needsProduct) joins += "JOIN DataWarehouse.dbo.Dim_Product p ON s.ProductID = p.ProductID\n";
        return joins;
    }
}
