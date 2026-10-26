module unirate

// Mock-transport test suite. Covers all eleven public methods and every error
// mapping. No test touches the network — the client's HTTP layer is replaced
// with MockTransport via dependency injection.

// Calls records what the client sent, so tests can assert on the built URL
// and headers.
struct Calls {
mut:
	url     string
	headers map[string]string
}

fn (mut c Calls) record(url string, headers map[string]string) {
	c.url = url
	c.headers = headers.clone()
}

// MockTransport returns a canned (status, body) and, if given a `calls`
// recorder, captures the request it received.
struct MockTransport {
	status int
	body   string
mut:
	calls &Calls = unsafe { nil }
}

fn (t MockTransport) send(url string, headers map[string]string, timeout_s int) !HttpResponse {
	if !isnil(t.calls) {
		mut rec := t.calls
		rec.record(url, headers)
	}
	return HttpResponse{
		status: t.status
		body:   t.body
	}
}

fn make_client(t Transport) Client {
	return new_client('test-key', transport: t) or { panic(err) }
}

fn ok(body string) Client {
	return make_client(MockTransport{ status: 200, body: body })
}

// --- happy paths -------------------------------------------------------

fn test_get_rate() ! {
	c := ok('{"rate":"0.92"}')
	rate := c.get_rate('usd', 'eur')!
	assert rate == 0.92
}

fn test_get_rate_requires_to() {
	c := ok('{"rate":"0.92"}')
	c.get_rate('USD', '') or {
		assert err is UniRateError
		if err is UniRateError {
			assert err.kind == .invalid_currency
		}
		return
	}
	assert false, 'expected an error for an empty "to"'
}

fn test_get_all_rates() ! {
	c := ok('{"rates":{"EUR":"0.92","GBP":"0.79"}}')
	rates := c.get_all_rates('USD')!
	assert rates['EUR'] == 0.92
	assert rates['GBP'] == 0.79
}

fn test_convert() ! {
	c := ok('{"result":"92.50"}')
	out := c.convert(100, 'USD', 'EUR')!
	assert out == 92.50
}

fn test_get_supported_currencies() ! {
	c := ok('{"currencies":["USD","EUR","GBP"]}')
	codes := c.get_supported_currencies()!
	assert codes.len == 3
	assert codes[0] == 'USD'
	assert codes[2] == 'GBP'
}

fn test_get_historical_rate() ! {
	c := ok('{"rate":"0.88"}')
	rate := c.get_historical_rate('2024-01-01', 'USD', 'EUR')!
	assert rate == 0.88
}

fn test_get_historical_rates() ! {
	c := ok('{"rates":{"EUR":"0.88"}}')
	rates := c.get_historical_rates('2024-01-01', 'USD')!
	assert rates['EUR'] == 0.88
}

fn test_convert_historical() ! {
	c := ok('{"result":"88.00"}')
	out := c.convert_historical(100, 'USD', 'EUR', '2024-01-01')!
	assert out == 88.00
}

fn test_get_time_series() ! {
	c := ok('{"data":{"2024-01-01":{"EUR":0.92,"GBP":0.79},"2024-01-02":{"EUR":0.93,"GBP":0.80}}}')
	series := c.get_time_series('2024-01-01', '2024-01-02', 'USD', [], 1)!
	assert series.len == 2
	assert series['2024-01-01']['EUR'] == 0.92
	assert series['2024-01-02']['GBP'] == 0.80
}

fn test_get_historical_limits() ! {
	c := ok('{"total_currencies":170,"data_source":"example","currencies":{"USD":{"earliest_date":"1999-01-01","latest_date":"2026-04-22","total_days":9000,"description":"US Dollar"}}}')
	limits := c.get_historical_limits()!
	assert limits.total_currencies == 170
	assert limits.data_source == 'example'
	assert limits.currencies['USD'].earliest_date == '1999-01-01'
	assert limits.currencies['USD'].total_days == 9000
}

fn test_get_vat_rates() ! {
	c := ok('{"total_countries":2,"date":"2026-04-22","vat_rates":{"DE":{"country_code":"DE","country_name":"Germany","vat_rate":19.0}}}')
	vat := c.get_vat_rates()!
	assert vat.total_countries == 2
	assert vat.date == '2026-04-22'
	assert vat.vat_rates['DE'].country_name == 'Germany'
	assert vat.vat_rates['DE'].vat_rate == 19.0
}

fn test_get_vat_rate() ! {
	c := ok('{"country":"DE","vat_data":{"country_code":"DE","country_name":"Germany","vat_rate":19.0}}')
	vat := c.get_vat_rate('de')!
	assert vat.country == 'DE'
	assert vat.vat_data.country_code == 'DE'
	assert vat.vat_data.vat_rate == 19.0
}

// --- request building --------------------------------------------------

fn test_sends_accept_and_user_agent_headers() ! {
	calls := &Calls{}
	c := make_client(MockTransport{ status: 200, body: '{"rate":"1.0"}', calls: calls })
	c.get_rate('USD', 'EUR')!
	assert calls.headers['Accept'] == 'application/json'
	assert calls.headers['User-Agent'] == 'unirate-v/${version}'
}

fn test_uppercases_currencies_and_appends_api_key() ! {
	calls := &Calls{}
	c := make_client(MockTransport{ status: 200, body: '{"rate":"1.0"}', calls: calls })
	c.get_rate('usd', 'eur')!
	assert calls.url.contains('from=USD')
	assert calls.url.contains('to=EUR')
	assert calls.url.contains('api_key=test-key')
}

// --- error mapping -----------------------------------------------------

fn expect_error(c Client, kind ErrorKind, status int) {
	c.get_rate('USD', 'EUR') or {
		assert err is UniRateError
		if err is UniRateError {
			assert err.kind == kind
			assert err.status == status
		}
		return
	}
	assert false, 'expected an error'
}

fn test_error_400() {
	expect_error(make_client(MockTransport{ status: 400, body: '{}' }), .invalid_date,
		400)
}

fn test_error_401() {
	expect_error(make_client(MockTransport{ status: 401, body: '{}' }), .authentication,
		401)
}

fn test_error_403() {
	expect_error(make_client(MockTransport{ status: 403, body: '{}' }), .api, 403)
}

fn test_error_404() {
	expect_error(make_client(MockTransport{ status: 404, body: '{}' }), .invalid_currency,
		404)
}

fn test_error_429() {
	expect_error(make_client(MockTransport{ status: 429, body: '{}' }), .rate_limit, 429)
}

fn test_error_503() {
	expect_error(make_client(MockTransport{ status: 503, body: '{}' }), .api, 503)
}

fn test_error_500_generic() {
	c := make_client(MockTransport{ status: 500, body: 'boom' })
	c.get_rate('USD', 'EUR') or {
		assert err is UniRateError
		if err is UniRateError {
			assert err.kind == .api
			assert err.status == 500
			assert err.body == 'boom'
		}
		return
	}
	assert false, 'expected an error'
}

fn test_empty_api_key_rejected() {
	new_client('') or {
		assert err is UniRateError
		if err is UniRateError {
			assert err.kind == .authentication
		}
		return
	}
	assert false, 'expected an error for an empty api key'
}

fn test_malformed_missing_field() {
	c := ok('{"something_else":"x"}')
	c.get_rate('USD', 'EUR') or {
		assert err is UniRateError
		if err is UniRateError {
			assert err.kind == .malformed
		}
		return
	}
	assert false, 'expected a malformed-response error'
}
