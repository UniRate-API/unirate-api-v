module main

import unirate
import os

fn main() {
	key := os.getenv('UNIRATE_API_KEY')
	if key == '' {
		eprintln('Set UNIRATE_API_KEY to run this example. Get a free key at https://unirateapi.com')
		return
	}

	client := unirate.new_client(key) or {
		eprintln('failed to create client: ${err}')
		return
	}

	rate := client.get_rate('USD', 'EUR') or {
		eprintln('error: ${err}')
		return
	}
	println('1 USD = ${rate} EUR')

	amount := client.convert(100, 'USD', 'EUR') or {
		eprintln('error: ${err}')
		return
	}
	println('100 USD = ${amount} EUR')

	currencies := client.get_supported_currencies() or {
		eprintln('error: ${err}')
		return
	}
	println('${currencies.len} currencies supported')
}
