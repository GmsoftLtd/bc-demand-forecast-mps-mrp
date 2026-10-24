/// <summary>
/// Lets a planner run the forecast and write demand forecast entries.
/// </summary>
permissionset 50500 "Time Series Forecast"
{
    Assignable = true;
    Caption = 'Time Series Demand Forecast';

    Permissions = codeunit "Demand Forecast Builder" = X,
                  report "Create Time Series Forecast" = X,
                  tabledata "Production Forecast Name" = RI,
                  tabledata "Production Forecast Entry" = RID,
                  tabledata "Item Ledger Entry" = R,
                  tabledata Item = R,
                  tabledata "Inventory Setup" = RM;
}
