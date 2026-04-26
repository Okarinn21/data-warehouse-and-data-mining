using api.Services;
using Microsoft.AspNetCore.Mvc;

namespace api.Controllers;

[ApiController]
[Route("api/dashboard")]
public class DashboardController : ControllerBase
{
    private readonly IOlapService _olap;
    public DashboardController(IOlapService olap) => _olap = olap;

    [HttpGet("kpi")]
    public async Task<IActionResult> Kpi()
    {
        try { return Ok(await _olap.GetKpi()); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }

    [HttpGet("sales-trend")]
    public async Task<IActionResult> SalesTrend([FromQuery] string groupBy = "year")
    {
        try { return Ok(await _olap.GetSalesTrend(groupBy)); }
        catch (ArgumentException ex) { return BadRequest(ex.Message); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }

    [HttpGet("by-city")]
    public async Task<IActionResult> ByCity()
    {
        try { return Ok(await _olap.GetSalesByCity()); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }

    [HttpGet("by-product")]
    public async Task<IActionResult> ByProduct([FromQuery] int? topN)
    {
        try { return Ok(await _olap.GetSalesByProduct(topN)); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }
}
