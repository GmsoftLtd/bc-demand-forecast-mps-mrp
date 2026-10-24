/// <summary>
/// The forecasting model sent to the Business Central time series service.
/// The ordinals match the TimeSeriesModel option of codeunit 2000 "Time Series Management"
/// (ARIMA, ETS, STL, ETS+ARIMA, ETS+STL, ALL, TBATS), so the value is passed as AsInteger().
/// </summary>
enum 50500 "Time Series Model"
{
    Extensible = false;
    Caption = 'Time Series Model';

    value(0; ARIMA)
    {
        Caption = 'ARIMA';
    }
    value(1; ETS)
    {
        Caption = 'ETS (Exponential Smoothing)';
    }
    value(2; STL)
    {
        Caption = 'STL (Seasonal Decomposition - needs 2+ years)';
    }
    value(3; "ETS+ARIMA")
    {
        Caption = 'ETS + ARIMA (average)';
    }
    value(4; "ETS+STL")
    {
        Caption = 'ETS + STL (average)';
    }
    value(5; All)
    {
        Caption = 'All models (lowest MAPE wins)';
    }
    value(6; TBATS)
    {
        Caption = 'TBATS';
    }
}
