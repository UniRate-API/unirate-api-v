module unirate

import net.http
import time

// HttpResponse is the minimal result a Transport returns: the HTTP status
// code and the raw response body.
pub struct HttpResponse {
pub:
	status int
	body   string
}

// Transport abstracts the HTTP layer so tests can run without touching the
// network. Implement `send` to perform a GET for the given URL and headers
// and return an HttpResponse (including for 4xx/5xx — only genuine transport
// failures should return an error).
pub interface Transport {
	send(url string, headers map[string]string, timeout_s int) !HttpResponse
}

// DefaultTransport is the production Transport, backed by V's `net.http`.
pub struct DefaultTransport {}

// send performs the HTTP GET. A non-2xx status is returned as a normal
// HttpResponse (the client maps it to a typed error); only a genuine
// transport failure (connection refused, timeout, TLS error) returns an error.
pub fn (t DefaultTransport) send(url string, headers map[string]string, timeout_s int) !HttpResponse {
	mut req := http.Request{
		method:       .get
		url:          url
		read_timeout: time.Duration(i64(timeout_s) * i64(time.second))
	}
	for k, v in headers {
		req.add_custom_header(k, v) or {}
	}
	resp := req.do() or {
		return UniRateError{
			kind:    .network
			message: 'Network error: ${err.msg()}'
		}
	}
	return HttpResponse{
		status: resp.status_code
		body:   resp.body
	}
}
