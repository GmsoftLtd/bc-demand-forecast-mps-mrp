/// <summary>
/// The bucket for one data point. Week or Month is what planning normally needs.
/// </summary>
enum 50502 "Forecast Period"
{
    Extensible = false;
    Caption = 'Forecast Period';

    value(0; Month)
    {
        Caption = 'Month';
    }
    value(1; Week)
    {
        Caption = 'Week';
    }
}
