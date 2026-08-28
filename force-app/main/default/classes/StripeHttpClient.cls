/**
 * StripeHttpClient
 *
 * Low-level HTTP client for Stripe REST API.
 *
 * Named Credential:
 *     stripe
 *
 * The Named Credential is responsible for authentication.
 *
 * This class does NOT:
 *     - contain Stripe secret keys
 *     - contain business logic
 *     - update Salesforce records
 *
 * It is responsible only for communicating with Stripe.
 */
public with sharing class StripeHttpClient {
	private static final String NAMED_CREDENTIAL = 'stripe';

	private static final String API_VERSION = '2024-06-20';

	private static final Integer TIMEOUT = 30000;

	/**
	 * Creates a PaymentIntent in Stripe.
	 *
	 * Stripe endpoint:
	 * POST /v1/payment_intents
	 *
	 * @param parameters Form encoded Stripe parameters.
	 * @return Stripe HTTP response.
	 */
	public static HttpResponse createPaymentIntent(
		Map<String, String> parameters
	) {
		if (parameters == null || parameters.isEmpty()) {
			throw StripeException.validationError(
				'PaymentIntent parameters cannot be empty.'
			);
		}

		return sendRequest('POST', '/v1/payment_intents', parameters);
	}

	/**
	 * Retrieves a PaymentIntent from Stripe.
	 *
	 * Stripe endpoint:
	 * GET /v1/payment_intents/{paymentIntentId}
	 *
	 * @param paymentIntentId Stripe PaymentIntent ID.
	 * @return Stripe HTTP response.
	 */
	public static HttpResponse getPaymentIntent(String paymentIntentId) {
		validatePaymentIntentId(paymentIntentId);

		return sendRequest(
			'GET',
			'/v1/payment_intents/' +
			EncodingUtil.urlEncode(paymentIntentId, 'UTF-8'),
			null
		);
	}

	/**
	 * Creates a refund.
	 *
	 * Stripe endpoint:
	 * POST /v1/refunds
	 *
	 * @param paymentIntentId Stripe PaymentIntent ID.
	 * @param amount Amount to refund in smallest currency unit.
	 * @return Stripe HTTP response.
	 */
	public static HttpResponse createRefund(
		String paymentIntentId,
		Long amount
	) {
		validatePaymentIntentId(paymentIntentId);

		if (amount != null && amount <= 0) {
			throw StripeException.validationError(
				'Refund amount must be greater than zero.'
			);
		}

		Map<String, String> parameters = new Map<String, String>();

		parameters.put('payment_intent', paymentIntentId);

		if (amount != null) {
			parameters.put('amount', String.valueOf(amount));
		}

		return sendRequest('POST', '/v1/refunds', parameters);
	}

	/**
	 * Generic GET request.
	 */
	public static HttpResponse get(String path) {
		return sendRequest('GET', path, null);
	}

	/**
	 * Generic POST form request.
	 */
	public static HttpResponse postForm(
		String path,
		Map<String, String> parameters
	) {
		return sendRequest('POST', path, parameters);
	}

	/**
	 * Sends HTTP request to Stripe.
	 */
	private static HttpResponse sendRequest(
		String method,
		String path,
		Map<String, String> parameters
	) {
		if (String.isBlank(method)) {
			throw StripeException.validationError(
				'HTTP method cannot be blank.'
			);
		}

		if (String.isBlank(path)) {
			throw StripeException.validationError(
				'Stripe API path cannot be blank.'
			);
		}

		HttpRequest request = new HttpRequest();

		/*
		 * IMPORTANT:
		 *
		 * This is where your Named Credential is used.
		 *
		 * Because your Named Credential API name is:
		 *
		 *     stripe
		 *
		 * Salesforce resolves:
		 *
		 *     callout:stripe
		 *
		 * and applies the authentication configured
		 * in your External Credential.
		 */
		request.setEndpoint('callout:' + NAMED_CREDENTIAL + path);

		request.setMethod(method);

		request.setTimeout(TIMEOUT);

		request.setHeader('Accept', 'application/json');

		request.setHeader('Stripe-Version', API_VERSION);

		/*
		 * Stripe POST APIs such as PaymentIntent
		 * creation expect form-urlencoded data.
		 */
		if (method == 'POST' && parameters != null) {
			request.setHeader(
				'Content-Type',
				'application/x-www-form-urlencoded'
			);

			request.setBody(buildFormBody(parameters));
		}

		Http http = new Http();

		HttpResponse response;

		try {
			response = http.send(request);
		} catch (System.CalloutException ex) {
			throw new StripeException(
				'Unable to connect to Stripe: ' + ex.getMessage()
			);
		}

		/*
		 * Stripe returns 2xx for successful requests.
		 */
		if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
			throw StripeException.fromHttpResponse(response);
		}

		return response;
	}

	/**
	 * Converts a map into
	 * application/x-www-form-urlencoded format.
	 *
	 * Example:
	 *
	 * amount=2500&
	 * currency=usd&
	 * payment_method_types[0]=card
	 */
	private static String buildFormBody(Map<String, String> parameters) {
		List<String> parts = new List<String>();

		for (String key : parameters.keySet()) {
			String value = parameters.get(key);

			if (value == null) {
				value = '';
			}

			parts.add(
				EncodingUtil.urlEncode(key, 'UTF-8') +
					'=' +
					EncodingUtil.urlEncode(value, 'UTF-8')
			);
		}

		return String.join(parts, '&');
	}

	/**
	 * Validates PaymentIntent ID.
	 */
	private static void validatePaymentIntentId(String paymentIntentId) {
		if (String.isBlank(paymentIntentId)) {
			throw StripeException.validationError(
				'Stripe PaymentIntent ID is required.'
			);
		}

		/*
		 * Stripe PaymentIntent IDs normally
		 * begin with "pi_".
		 */
		if (!paymentIntentId.startsWith('pi_')) {
			throw StripeException.validationError(
				'Invalid Stripe PaymentIntent ID.'
			);
		}
	}
}