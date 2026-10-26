module unirate

// Live test suite — hits the real UniRate API. Compiled out by default; only
// the `-d unirate_live` build flag includes these bodies, so the standard
// `v test .` runs the mock suite with zero network access. Each test also
// no-ops unless UNIRATE_API_KEY is set.
//
//   v -d unirate_live test .     # with UNIRATE_API_KEY exported
//
// Only free-tier endpoints are exercised (rates / convert / currencies / VAT);
// historical and timeseries are Pro-gated and would 403.
import os

fn live_client() ?Client {
	key := os.getenv('UNIRATE_API_KEY')
	if key == '' {
		return none
	}
	return new_client(key) or { panic(err) }
}

fn test_live_get_rate() {
	$if unirate_live ? {
		c := live_client() or { return }
		rate := c.get_rate('USD', 'EUR') or { panic(err) }
		assert rate > 0
	}
}

fn test_live_get_all_rates() {
	$if unirate_live ? {
		c := live_client() or { return }
		rates := c.get_all_rates('USD') or { panic(err) }
		assert rates.len > 0
		assert rates['EUR'] > 0
	}
}

fn test_live_convert() {
	$if unirate_live ? {
		c := live_client() or { return }
		out := c.convert(100, 'USD', 'EUR') or { panic(err) }
		assert out > 0
	}
}

fn test_live_get_supported_currencies() {
	$if unirate_live ? {
		c := live_client() or { return }
		codes := c.get_supported_currencies() or { panic(err) }
		assert codes.len > 0
		assert 'USD' in codes
	}
}

fn test_live_get_vat_rates() {
	$if unirate_live ? {
		c := live_client() or { return }
		vat := c.get_vat_rates() or { panic(err) }
		assert vat.vat_rates.len > 0
	}
}

fn test_live_get_vat_rate() {
	$if unirate_live ? {
		c := live_client() or { return }
		vat := c.get_vat_rate('DE') or { panic(err) }
		assert vat.vat_data.country_code == 'DE'
		assert vat.vat_data.vat_rate > 0
	}
}
