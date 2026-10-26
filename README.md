# UniRate API — V client

Official [V](https://vlang.io) client for the [UniRate API](https://unirateapi.com) —
free currency exchange rates, historical data, and VAT rates.

- **Zero dependencies.** HTTP via `net.http`, JSON via `x.json2`, URL encoding
  via `net.urllib` — all in the V standard library. Nothing else is pulled in
  (`dependencies: []` in `v.mod`).
- **Injectable transport**, so your tests never touch the network.
- Typed errors with a `kind` you can branch on.

## Install

```sh
v install unirate
```

Then `import unirate` in your code.

## Quick start

```v
import unirate

fn main() {
	client := unirate.new_client('your-api-key')!

	// Current rate
	rate := client.get_rate('USD', 'EUR')! // 0.92

	// Convert an amount
	eur := client.convert(100, 'USD', 'EUR')! // 92.5

	// All rates for a base currency
	all := client.get_all_rates('USD')! // map[string]f64

	// Supported currency codes
	codes := client.get_supported_currencies()! // ['USD', 'EUR', ...]

	println('${rate} ${eur} ${all.len} ${codes.len}')
}
```

Get a free API key at [unirateapi.com](https://unirateapi.com).

## API

Construct a client with your API key, plus optional named settings (base URL,
timeout in seconds, and a custom `Transport`):

```v
client := unirate.new_client('your-api-key', timeout_s: 10)!
```

### Current rates & conversion (free tier)

| Method | Returns |
|---|---|
| `get_rate(from, to)` | `f64` — rate from `from` to `to` |
| `get_all_rates(from)` | `map[string]f64` — every rate for a base (pass `''` for `USD`) |
| `convert(amount, from, to)` | `f64` — converted amount |
| `get_supported_currencies()` | `[]string` — supported currency codes |

### Historical data (Pro tier)

These require a UniRate Pro subscription and return a `403` `UniRateError`
(`kind: .api`, `status: 403`) on the free tier.

| Method | Returns |
|---|---|
| `get_historical_rate(date, from, to)` | `f64` |
| `get_historical_rates(date, base)` | `map[string]f64` |
| `convert_historical(amount, from, to, date)` | `f64` |
| `get_time_series(start_date, end_date, base, currencies, amount)` | `map[string]map[string]f64` |
| `get_historical_limits()` | `HistoricalLimitsResponse` |

### VAT (free tier)

| Method | Returns |
|---|---|
| `get_vat_rates()` | `VatRatesResponse` — every supported country |
| `get_vat_rate(country)` | `VatCountryResponse` — one ISO-3166 alpha-2 country |

Currency and country codes are upper-cased before they are sent, and an empty
`from`/`base` defaults to `USD`.

## Error handling

Every method propagates a `UniRateError` via V's `!` result type. Recover it in
an `or {}` block and branch on `kind`:

```v
import unirate

fn main() {
	client := unirate.new_client('your-api-key')!
	rate := client.get_rate('USD', 'ZZZ') or {
		if err is unirate.UniRateError {
			match err.kind {
				.authentication { eprintln('check your API key') }
				.invalid_currency { eprintln('unknown currency') }
				.rate_limit { eprintln('slow down') }
				else { eprintln('API error ${err.status}: ${err.msg()}') }
			}
		}
		return
	}
	println(rate)
}
```

| `kind` | HTTP | Meaning |
|---|---|---|
| `.invalid_date` | 400 | Invalid request parameters |
| `.authentication` | 401 | Missing or invalid API key |
| `.api` | 403 | Endpoint requires a Pro subscription |
| `.invalid_currency` | 404 | Currency/country not found |
| `.rate_limit` | 429 | Rate limit exceeded |
| `.api` | 503 / other | Service unavailable / generic |
| `.network` | — | Transport failure |
| `.malformed` | — | Unexpected response body |

## Rate limits

The free tier is rate-limited; a `429` surfaces as `UniRateError{ kind: .rate_limit }`.
See [unirateapi.com](https://unirateapi.com) for current limits and Pro plans.

## Testing

```sh
v test .                     # mock suite, no network
v -d unirate_live test .     # also run the live suite (needs UNIRATE_API_KEY)
```

The HTTP layer is the `Transport` interface, so your own tests can inject a
fake and stay offline.

## Related clients

UniRate ships official clients for many languages and platforms — Python,
Node.js, Go, Rust, Java, Swift, Ruby, PHP, Elixir, Haxe, and more. See
[unirateapi.com](https://unirateapi.com).

## License

MIT — see [LICENSE](LICENSE).
