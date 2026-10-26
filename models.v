module unirate

// VatRate is VAT data for a single country.
pub struct VatRate {
pub:
	country_code string
	country_name string
	vat_rate     f64
}

// VatRatesResponse is the result of `get_vat_rates()` — VAT data for every
// supported country, keyed by ISO-3166 alpha-2 country code.
pub struct VatRatesResponse {
pub:
	total_countries int
	date            string
	vat_rates       map[string]VatRate
}

// VatCountryResponse is the result of `get_vat_rate(country)` — VAT data for
// one country.
pub struct VatCountryResponse {
pub:
	country  string
	vat_data VatRate
}

// HistoricalLimit is the historical-data coverage for a single currency.
pub struct HistoricalLimit {
pub:
	earliest_date string
	latest_date   string
	total_days    int
	description   string
}

// HistoricalLimitsResponse is the result of `get_historical_limits()` —
// per-currency coverage, keyed by currency code.
pub struct HistoricalLimitsResponse {
pub:
	total_currencies int
	data_source      string
	currencies       map[string]HistoricalLimit
}
