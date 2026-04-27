using api.Services;
using Microsoft.AspNetCore.Mvc;

namespace api.Controllers;

[ApiController]
[Route("api/olap")]
public class OlapController : ControllerBase
{
    private readonly IOlapService _olap;
    public OlapController(IOlapService olap) => _olap = olap;

    /// <summary>Roll-up: aggregate to year | quarter | month</summary>
    [HttpGet("rollup")]
    public async Task<IActionResult> RollUp([FromQuery] string level = "year")
    {
        try { return Ok(await _olap.RollUp(level)); }
        catch (ArgumentException ex) { return BadRequest(ex.Message); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }

    /// <summary>Drill-down: parentLevel=year|quarter, parentKey=2024 or 2024:1</summary>
    [HttpGet("drilldown")]
    public async Task<IActionResult> DrillDown(
        [FromQuery] string parentLevel = "year",
        [FromQuery] string parentKey = "2024")
    {
        try { return Ok(await _olap.DrillDown(parentLevel, parentKey)); }
        catch (ArgumentException ex) { return BadRequest(ex.Message); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }

    /// <summary>Slice: fix one dimension, analyze by another</summary>
    [HttpGet("slice")]
    public async Task<IActionResult> Slice(
        [FromQuery] string sliceDim = "year",
        [FromQuery] string sliceKey = "2024",
        [FromQuery] string rows = "city")
    {
        try { return Ok(await _olap.Slice(sliceDim, sliceKey, rows)); }
        catch (ArgumentException ex) { return BadRequest(ex.Message); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }

    /// <summary>Dice: filter by time range (TimeID=YYYYMM), customer type, city</summary>
    [HttpGet("dice")]   
    public async Task<IActionResult> Dice(
        [FromQuery] int? fromTimeId,
        [FromQuery] int? toTimeId,
        [FromQuery] string? customerType,
        [FromQuery] string? city,
        [FromQuery] string rows = "city")
    {
        try { return Ok(await _olap.Dice(fromTimeId, toTimeId, customerType, city, rows)); }
        catch (ArgumentException ex) { return BadRequest(ex.Message); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }

    /// <summary>Pivot: cross-tabulate rowDim vs colDim</summary>
    [HttpGet("pivot")]
    public async Task<IActionResult> Pivot(
        [FromQuery] string rowDim = "customerType",
        [FromQuery] string colDim = "year")
    {
        try { return Ok(await _olap.Pivot(rowDim, colDim)); }
        catch (ArgumentException ex) { return BadRequest(ex.Message); }
        catch (Exception ex) { return StatusCode(500, ex.Message); }
    }
}
