module unirate

// ErrorKind classifies a UniRateError so callers can branch on the kind of
// failure without string-matching messages.
pub enum ErrorKind {
	authentication   // 401 — missing or invalid API key
	invalid_currency // 404 — currency/country not found or no data available
	invalid_date     // 400 — invalid request parameters (bad date, etc.)
	rate_limit       // 429 — rate limit exceeded
	api              // 403 / 503 / any other non-2xx status
	network          // transport failure (no HTTP status received)
	malformed        // unexpected or unparseable response body
}

// UniRateError is the single error type raised by the client. It implements
// V's `IError`, so it is returned from the `!`-propagating methods and can be
// recovered in an `or {}` block with `if err is UniRateError { ... }`.
//
// `kind` carries the semantic classification, `status` the HTTP status code
// (0 when there was no HTTP response), and `body` the raw response body when
// the server returned one for a non-2xx status.
pub struct UniRateError {
pub:
	kind    ErrorKind
	status  int
	body    string
	message string
}

// msg implements IError.
pub fn (e UniRateError) msg() string {
	return e.message
}

// code implements IError — the HTTP status, or 0 for non-HTTP failures.
pub fn (e UniRateError) code() int {
	return e.status
}

// error_for_status maps a non-2xx HTTP status to the matching UniRateError,
// mirroring the shared error-mapping table across all UniRate clients.
fn error_for_status(status int, body string) UniRateError {
	return match status {
		400 {
			UniRateError{
				kind:    .invalid_date
				status:  400
				body:    body
				message: 'Invalid request parameters'
			}
		}
		401 {
			UniRateError{
				kind:    .authentication
				status:  401
				body:    body
				message: 'Missing or invalid API key'
			}
		}
		403 {
			UniRateError{
				kind:    .api
				status:  403
				body:    body
				message: 'Endpoint requires a Pro subscription'
			}
		}
		404 {
			UniRateError{
				kind:    .invalid_currency
				status:  404
				body:    body
				message: 'Currency not found or no data available'
			}
		}
		429 {
			UniRateError{
				kind:    .rate_limit
				status:  429
				body:    body
				message: 'Rate limit exceeded'
			}
		}
		503 {
			UniRateError{
				kind:    .api
				status:  503
				body:    body
				message: 'Service unavailable'
			}
		}
		else {
			UniRateError{
				kind:    .api
				status:  status
				body:    body
				message: 'API error (status ${status}): ${body}'
			}
		}
	}
}
