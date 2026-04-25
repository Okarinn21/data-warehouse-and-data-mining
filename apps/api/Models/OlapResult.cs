namespace api.Models;

public record OlapResult(
    string OperationType,
    List<string> ColumnHeaders,
    List<Dictionary<string, object?>> Rows
);

public record KpiData(
    decimal TotalRevenue,
    long TotalQuantity,
    int TotalCustomers,
    int TotalProducts,
    long TotalTransactions
);
