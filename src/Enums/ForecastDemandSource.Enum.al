/// <summary>
/// Which history the forecast is built from, and therefore which planning level uses it.
/// Sales: posted sales of the item -> a sales item forecast, independent demand for MPS.
/// Consumption: posted production consumption of the item -> a component forecast,
/// dependent demand for MRP (for example spare parts or components also sold or used outside the BOM).
/// </summary>
enum 50501 "Forecast Demand Source"
{
    Extensible = false;
    Caption = 'Forecast Demand Source';

    value(0; Sales)
    {
        Caption = 'Sales (sales item forecast for MPS)';
    }
    value(1; Consumption)
    {
        Caption = 'Consumption (component forecast for MRP)';
    }
}
