// Module unirate is the official V client for the UniRate API
// (https://unirateapi.com) — free currency exchange rates, historical data,
// and VAT rates.
//
// It depends only on the V standard library (`net.http` for HTTP and
// `x.json2` for decoding) — zero third-party dependencies. The HTTP layer is
// injectable via the Transport interface so tests run offline.
module unirate

import net.urllib
import x.json2

// version is the client version, kept in sync with v.mod.
pub const version = '0.1.0'

// default_base_url is the UniRate API base URL.
pub const default_base_url = 'https://api.unirateapi.com'

// default_timeout_s is the default request timeout, in seconds.
pub const default_timeout_s = 30

// Client is a UniRate API client. Create one with `new_client`, then call any
// of the public methods. A Client is immutable and safe to reuse.
pub struct Client {
	api_key    string
	base_url   string
	timeout_s  int
	user_agent string
	transport  Transport
}

// ClientConfig holds the optional settings for `new_client`, passed as named
// arguments.
@[params]
pub struct ClientConfig {
pub:
	base_url  string    = default_base_url
	timeout_s int       = default_timeout_s
	transport Transport = DefaultTransport{}
}

// new_client creates a client with the given API key. Optional settings are
// passed as named arguments:
//   c := unirate.new_client('your-api-key')!
//   c := unirate.new_client('your-api-key', timeout_s: 10)!
pub fn new_client(api_key string, config ClientConfig) !Client {
	if api_key == '' {
		return UniRateError{
			kind:    .authentication
			message: 'api_key is required'
		}
	}
	return Client{
		api_key:    api_key
		base_url:   strip_trailing_slash(config.base_url)
		timeout_s:  config.timeout_s
		user_agent: 'unirate-v/${version}'
		transport:  config.transport
	}
}

// param is one query-string parameter. An empty value is omitted from the URL.
struct Param {
	name  string
	value string
}

// -----------------------------------------------------------------------
// Current rates and conversion (free tier)
// -----------------------------------------------------------------------

// get_rate returns the current exchange rate from `from` to `to` (how many
// `to` one `from` buys). Pass an empty `from` to default to "USD".
pub fn (c Client) get_rate(from string, to string) !f64 {
	if to == '' {
		return UniRateError{
			kind:    .invalid_currency
			message: 'to is required'
		}
	}
	m := c.request('/api/rates', [
		Param{'from', up_or_default(from)},
		Param{'to', to.to_upper()},
	])!
	return to_f64(get_field(m, 'rate')!, 'rate')!
}

// get_all_rates returns every current exchange rate for a base currency as a
// map of currency code to rate. Pass an empty `from` to default to "USD".
pub fn (c Client) get_all_rates(from string) !map[string]f64 {
	m := c.request('/api/rates', [
		Param{'from', up_or_default(from)},
	])!
	return to_f64_map(get_field(m, 'rates')!, 'rates')!
}

// convert converts `amount` from `from` to `to` at the current rate. Pass an
// empty `from` to default to "USD".
pub fn (c Client) convert(amount f64, from string, to string) !f64 {
	if to == '' {
		return UniRateError{
			kind:    .invalid_currency
			message: 'to is required'
		}
	}
	m := c.request('/api/convert', [
		Param{'from', up_or_default(from)},
		Param{'to', to.to_upper()},
		Param{'amount', format_amount(amount)},
	])!
	return to_f64(get_field(m, 'result')!, 'result')!
}

// get_supported_currencies returns the list of supported currency codes.
pub fn (c Client) get_supported_currencies() ![]string {
	m := c.request('/api/currencies', [])!
	arr := get_field(m, 'currencies')!
	if arr !is []json2.Any {
		return UniRateError{
			kind:    .malformed
			message: "Malformed response: 'currencies' is not an array"
		}
	}
	mut out := []string{}
	for item in arr.as_array() {
		out << item.str()
	}
	return out
}

// -----------------------------------------------------------------------
// Historical data (Pro-gated: returns a 403 APIError on the free tier)
// -----------------------------------------------------------------------

// get_historical_rate returns the historical exchange rate from `from` to `to`
// on `date` (YYYY-MM-DD). Pass an empty `from` to default to "USD". Pro-gated.
pub fn (c Client) get_historical_rate(date string, from string, to string) !f64 {
	if date == '' {
		return UniRateError{
			kind:    .invalid_date
			message: 'date is required'
		}
	}
	if to == '' {
		return UniRateError{
			kind:    .invalid_currency
			message: 'to is required'
		}
	}
	m := c.request('/api/historical/rates', [
		Param{'date', date},
		Param{'amount', '1'},
		Param{'from', up_or_default(from)},
		Param{'to', to.to_upper()},
	])!
	return to_f64(get_field(m, 'rate')!, 'rate')!
}

// get_historical_rates returns every historical exchange rate for a base
// currency on `date` (YYYY-MM-DD). Pass an empty `base` to default to "USD".
// Pro-gated.
pub fn (c Client) get_historical_rates(date string, base string) !map[string]f64 {
	if date == '' {
		return UniRateError{
			kind:    .invalid_date
			message: 'date is required'
		}
	}
	m := c.request('/api/historical/rates', [
		Param{'date', date},
		Param{'amount', '1'},
		Param{'from', up_or_default(base)},
	])!
	return to_f64_map(get_field(m, 'rates')!, 'rates')!
}

// convert_historical converts `amount` from `from` to `to` using the rate on
// `date` (YYYY-MM-DD). Pro-gated.
pub fn (c Client) convert_historical(amount f64, from string, to string, date string) !f64 {
	if from == '' || to == '' || date == '' {
		return UniRateError{
			kind:    .invalid_date
			message: 'from, to and date are required'
		}
	}
	m := c.request('/api/historical/rates', [
		Param{'date', date},
		Param{'amount', format_amount(amount)},
		Param{'from', from.to_upper()},
		Param{'to', to.to_upper()},
	])!
	return to_f64(get_field(m, 'result')!, 'result')!
}

// get_time_series returns a time series of exchange rates between `start_date`
// and `end_date` (YYYY-MM-DD, up to a 5-year span) as a nested map
// {date -> {currency -> rate}}. Pass an empty `base` to default to "USD", an
// empty `currencies` for every currency, and `amount` <= 0 to default to 1.
// Pro-gated.
pub fn (c Client) get_time_series(start_date string, end_date string, base string, currencies []string, amount f64) !map[string]map[string]f64 {
	if start_date == '' || end_date == '' {
		return UniRateError{
			kind:    .invalid_date
			message: 'start_date and end_date are required'
		}
	}
	amt := if amount <= 0 { f64(1) } else { amount }
	mut params := [
		Param{'start_date', start_date},
		Param{'end_date', end_date},
		Param{'amount', format_amount(amt)},
		Param{'base', up_or_default(base)},
	]
	if currencies.len > 0 {
		mut up := []string{}
		for cur in currencies {
			up << cur.to_upper()
		}
		params << Param{'currencies', up.join(',')}
	}
	m := c.request('/api/historical/timeseries', params)!
	data := get_field(m, 'data')!
	if data !is map[string]json2.Any {
		return UniRateError{
			kind:    .malformed
			message: "Malformed response: missing 'data'"
		}
	}
	mut out := map[string]map[string]f64{}
	for date_key, day in data.as_map() {
		out[date_key] = to_f64_map(day, date_key)!
	}
	return out
}

// get_historical_limits returns per-currency historical-data coverage.
// Pro-gated.
pub fn (c Client) get_historical_limits() !HistoricalLimitsResponse {
	m := c.request('/api/historical/limits', [])!
	mut currencies := map[string]HistoricalLimit{}
	if cur := m['currencies'] {
		if cur is map[string]json2.Any {
			for code, entry in cur {
				em := entry.as_map()
				currencies[code] = HistoricalLimit{
					earliest_date: to_str(em, 'earliest_date')
					latest_date:   to_str(em, 'latest_date')
					total_days:    to_int(em, 'total_days')
					description:   to_str(em, 'description')
				}
			}
		}
	}
	return HistoricalLimitsResponse{
		total_currencies: to_int(m, 'total_currencies')
		data_source:      to_str(m, 'data_source')
		currencies:       currencies
	}
}

// -----------------------------------------------------------------------
// VAT (free tier)
// -----------------------------------------------------------------------

// get_vat_rates returns VAT rates for every supported country.
pub fn (c Client) get_vat_rates() !VatRatesResponse {
	m := c.request('/api/vat/rates', [])!
	mut rates := map[string]VatRate{}
	if vr := m['vat_rates'] {
		if vr is map[string]json2.Any {
			for code, entry in vr {
				rates[code] = parse_vat_rate(entry)!
			}
		}
	}
	return VatRatesResponse{
		total_countries: to_int(m, 'total_countries')
		date:            to_str(m, 'date')
		vat_rates:       rates
	}
}

// get_vat_rate returns VAT data for a single ISO-3166 alpha-2 country code
// (e.g. "DE").
pub fn (c Client) get_vat_rate(country string) !VatCountryResponse {
	if country == '' {
		return UniRateError{
			kind:    .invalid_currency
			message: 'country is required'
		}
	}
	m := c.request('/api/vat/rates', [
		Param{'country', country.to_upper()},
	])!
	return VatCountryResponse{
		country:  to_str(m, 'country')
		vat_data: parse_vat_rate(get_field(m, 'vat_data')!)!
	}
}

// -----------------------------------------------------------------------
// Internals
// -----------------------------------------------------------------------

// request performs a GET to `path` with `params` (plus the api_key), maps a
// non-2xx status to a typed error, and returns the decoded top-level JSON
// object.
fn (c Client) request(path string, params []Param) !map[string]json2.Any {
	url := c.build_url(path, params)
	headers := {
		'Accept':     'application/json'
		'User-Agent': c.user_agent
	}
	resp := c.transport.send(url, headers, c.timeout_s)!
	if resp.status < 200 || resp.status >= 300 {
		return error_for_status(resp.status, resp.body)
	}
	decoded := json2.decode[json2.Any](resp.body) or {
		return UniRateError{
			kind:    .malformed
			message: 'Failed to parse response JSON: ${err.msg()}'
		}
	}
	return decoded.as_map()
}

// build_url assembles the request URL, url-encoding every name and value and
// appending the api_key last.
fn (c Client) build_url(path string, params []Param) string {
	mut parts := []string{}
	for p in params {
		if p.value != '' {
			parts << '${urllib.query_escape(p.name)}=${urllib.query_escape(p.value)}'
		}
	}
	parts << 'api_key=${urllib.query_escape(c.api_key)}'
	return '${c.base_url}${path}?${parts.join('&')}'
}

// get_field returns m[key] or a malformed-response error if the key is absent.
fn get_field(m map[string]json2.Any, key string) !json2.Any {
	return m[key] or {
		return UniRateError{
			kind:    .malformed
			message: "Malformed response: missing '${key}'"
		}
	}
}

// to_f64 coerces a JSON value (string like "0.92" or a JSON number) to f64.
fn to_f64(v json2.Any, field string) !f64 {
	match v {
		f64 {
			return v
		}
		f32 {
			return f64(v)
		}
		int {
			return f64(v)
		}
		i64 {
			return f64(v)
		}
		string {
			if v.trim_space() == '' {
				return UniRateError{
					kind:    .malformed
					message: "Malformed response: '${field}' is empty"
				}
			}
			return v.f64()
		}
		else {
			return UniRateError{
				kind:    .malformed
				message: "Malformed response: '${field}' is not numeric"
			}
		}
	}
}

// to_f64_map coerces a JSON object of {code -> number-or-string} to
// map[string]f64.
fn to_f64_map(v json2.Any, field string) !map[string]f64 {
	if v !is map[string]json2.Any {
		return UniRateError{
			kind:    .malformed
			message: "Malformed response: missing or invalid '${field}' map"
		}
	}
	mut out := map[string]f64{}
	for k, val in v.as_map() {
		out[k] = to_f64(val, k)!
	}
	return out
}

// parse_vat_rate decodes a single VAT-rate object.
fn parse_vat_rate(v json2.Any) !VatRate {
	if v !is map[string]json2.Any {
		return UniRateError{
			kind:    .malformed
			message: 'Malformed response: missing VAT data'
		}
	}
	o := v.as_map()
	return VatRate{
		country_code: to_str(o, 'country_code')
		country_name: to_str(o, 'country_name')
		vat_rate:     to_f64(get_field(o, 'vat_rate')!, 'vat_rate')!
	}
}

// to_str returns m[key] coerced to a string, or "" if absent.
fn to_str(m map[string]json2.Any, key string) string {
	v := m[key] or { return '' }
	return v.str()
}

// to_int returns m[key] coerced to an int, or 0 if absent.
fn to_int(m map[string]json2.Any, key string) int {
	v := m[key] or { return 0 }
	return v.int()
}

// up_or_default upper-cases a currency code, defaulting an empty value to "USD".
fn up_or_default(s string) string {
	if s == '' {
		return 'USD'
	}
	return s.to_upper()
}

// strip_trailing_slash removes a single trailing "/" from a base URL.
fn strip_trailing_slash(s string) string {
	if s.ends_with('/') {
		return s#[..-1]
	}
	return s
}

// format_amount renders a number for a query string without a spurious
// trailing ".0" for whole values.
fn format_amount(v f64) string {
	if v == f64(int(v)) && v > -2147483648.0 && v < 2147483647.0 {
		return int(v).str()
	}
	return v.str()
}
