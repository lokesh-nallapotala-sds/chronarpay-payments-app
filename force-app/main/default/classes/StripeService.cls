/**
 * StripeService
 *
 * Business/service layer for Salesforce -> Stripe integration.
 *
 * Responsibilities:
 *  - Validate payment data
 *  - Build Stripe PaymentIntent parameters
 *  - Convert currency amounts
 *  - Add Stripe metadata
 *  - Call StripeHttpClient
 *  - Deserialize Stripe responses
 *  - Return DTOs to the controller
 *
 * This class does NOT:
 *  - Render UI
 *  - Handle Stripe.js
 *  - Receive card information
 *  - Store Stripe secret keys
 *
 * Card information is handled by Stripe Elements in the LWC.
 */
public with sharing class StripeService {
	/*
	 * Stripe uses the smallest currency unit.
	 *
	 * Examples:
	 *
	 * USD  -> cents
	 * EUR  -> cents
	 * GBP  -> pence
	 * INR  -> paise
	 *
	 * Zero-decimal currencies such as JPY
	 * should not be multiplied by 100.
	 */
	private static final Set<String> ZERO_DECIMAL_CURRENCIES = new Set<String>{
		'bif',
		'clp',
		'djf',
		'gnf',
		'jpy',
		'kmf',
		'krw',
		'mga',
		'pyg',
		'rwf',
		'ugx',
		'vnd',
		'vuv',
		'xaf',
		'xof',
		'xpf'
	};

	/**
	 * Creates a Stripe PaymentIntent.
	 *
	 * @param request PaymentIntent request DTO.
	 * @return PaymentIntent response DTO.
	 */
	public static StripeDTO.PaymentIntentResponse createPaymentIntent(
		StripeDTO.CreatePaymentIntentRequest request
	) {
		validateCreatePaymentIntentRequest(request);

		Long stripeAmount = convertToStripeAmount(
			request.amount,
			request.currencyCode
		);

		Map<String, String> parameters = new Map<String, String>();

		/*
		 * Required Stripe parameters.
		 */
		parameters.put('amount', String.valueOf(stripeAmount));

		parameters.put('currencyCode', request.currencyCode.toLowerCase());

		/*
		 * We are using Stripe Payment Element /
		 * Stripe Elements on the frontend.
		 *
		 * Automatic payment methods allows Stripe
		 * to determine eligible payment methods.
		 */
		parameters.put('automatic_payment_methods[enabled]', 'true');

		/*
		 * Description.
		 */
		if (!String.isBlank(request.description)) {
			parameters.put('description', request.description);
		} else if (!String.isBlank(request.invoiceNumber)) {
			parameters.put(
				'description',
				'Payment for invoice ' + request.invoiceNumber
			);
		}

		/*
		 * Stripe metadata.
		 *
		 * Metadata is extremely useful when
		 * troubleshooting transactions in Stripe Dashboard.
		 */
		if (!String.isBlank(request.invoiceNumber)) {
			parameters.put('metadata[invoiceNumber]', request.invoiceNumber);
		}

		if (!String.isBlank(request.paymentId)) {
			parameters.put('metadata[paymentId]', request.paymentId);
		}

		if (!String.isBlank(request.accountId)) {
			parameters.put('metadata[accountId]', request.accountId);
		}

		if (!String.isBlank(request.customerName)) {
			parameters.put('metadata[customerName]', request.customerName);
		}

		if (!String.isBlank(request.customerEmail)) {
			parameters.put('metadata[customerEmail]', request.customerEmail);
		}

		/*
		 * Call Stripe.
		 */
		HttpResponse response = StripeHttpClient.createPaymentIntent(
			parameters
		);

		/*
		 * Convert Stripe JSON response
		 * into Salesforce DTO.
		 */
		return deserializePaymentIntent(response.getBody());
	}

	/**
	 * Retrieves an existing PaymentIntent.
	 *
	 * @param paymentIntentId Stripe PaymentIntent ID.
	 * @return PaymentIntent response.
	 */
	public static StripeDTO.PaymentIntentResponse getPaymentIntent(
		String paymentIntentId
	) {
		if (String.isBlank(paymentIntentId)) {
			throw StripeException.validationError(
				'PaymentIntent ID is required.'
			);
		}

		HttpResponse response = StripeHttpClient.getPaymentIntent(
			paymentIntentId
		);

		return deserializePaymentIntent(response.getBody());
	}

	/**
	 * Creates a Stripe refund.
	 *
	 * @param paymentIntentId Stripe PaymentIntent ID.
	 * @param amount Amount in Salesforce currency units.
	 *               Null = full refund.
	 * @param currency Currency code.
	 * @return Stripe refund DTO.
	 */
	public static StripeDTO.RefundResponse createRefund(
		String paymentIntentId,
		Decimal amount,
		String currencyCode
	) {
		if (String.isBlank(paymentIntentId)) {
			throw StripeException.validationError(
				'PaymentIntent ID is required.'
			);
		}

		Long stripeAmount;

		if (amount != null) {
			if (String.isBlank(currencyCode)) {
				throw StripeException.validationError(
					'Currency is required when refund amount is provided.'
				);
			}

			stripeAmount = convertToStripeAmount(amount, currencyCode);
		} else {
			stripeAmount = null;
		}

		HttpResponse response = StripeHttpClient.createRefund(
			paymentIntentId,
			stripeAmount
		);

		return deserializeRefund(response.getBody());
	}

	/**
	 * Converts Salesforce currency amount
	 * to Stripe smallest currency unit.
	 *
	 * Example:
	 *
	 * 25.50 USD
	 *
	 * becomes:
	 *
	 * 2550
	 */
	public static Long convertToStripeAmount(Decimal amount, String currencyCode) {
		if (amount == null) {
			throw StripeException.validationError(
				'Payment amount is required.'
			);
		}

		if (amount <= 0) {
			throw StripeException.validationError(
				'Payment amount must be greater than zero.'
			);
		}

		if (String.isBlank(currencyCode)) {
			throw StripeException.validationError('Currency is required.');
		}

		String normalizedCurrency = currencyCode.trim().toLowerCase();

		if (normalizedCurrency.length() != 3) {
			throw StripeException.validationError(
				'Currency must be a valid three-letter ISO currency code.'
			);
		}

		/*
		 * Stripe amounts must be integers.
		 */
		Decimal stripeAmount;

		if (ZERO_DECIMAL_CURRENCIES.contains(normalizedCurrency)) {
			stripeAmount = amount.setScale(0, System.RoundingMode.HALF_UP);
		} else {
			stripeAmount = (amount * 100)
				.setScale(0, System.RoundingMode.HALF_UP);
		}

		if (stripeAmount <= 0) {
			throw StripeException.validationError(
				'Payment amount is too small for the selected currency.'
			);
		}

		return stripeAmount.longValue();
	}

	/**
	 * Deserializes Stripe PaymentIntent response.
	 */
	private static StripeDTO.PaymentIntentResponse deserializePaymentIntent(
		String responseBody
	) {
		if (String.isBlank(responseBody)) {
			throw new StripeException('Stripe returned an empty response.');
		}

		try {
			return (StripeDTO.PaymentIntentResponse) JSON.deserialize(
				responseBody,
				StripeDTO.PaymentIntentResponse.class
			);
		} catch (Exception ex) {
			throw new StripeException(
				'Unable to parse Stripe PaymentIntent response: ' +
				ex.getMessage()
			);
		}
	}

	/**
	 * Deserializes Stripe refund response.
	 */
	private static StripeDTO.RefundResponse deserializeRefund(
		String responseBody
	) {
		if (String.isBlank(responseBody)) {
			throw new StripeException(
				'Stripe returned an empty refund response.'
			);
		}

		try {
			return (StripeDTO.RefundResponse) JSON.deserialize(
				responseBody,
				StripeDTO.RefundResponse.class
			);
		} catch (Exception ex) {
			throw new StripeException(
				'Unable to parse Stripe refund response: ' + ex.getMessage()
			);
		}
	}

	/**
	 * Validates PaymentIntent creation request.
	 */
	private static void validateCreatePaymentIntentRequest(
		StripeDTO.CreatePaymentIntentRequest request
	) {
		if (request == null) {
			throw StripeException.validationError(
				'PaymentIntent request cannot be null.'
			);
		}

		if (request.amount == null) {
			throw StripeException.validationError(
				'Payment amount is required.'
			);
		}

		if (request.amount <= 0) {
			throw StripeException.validationError(
				'Payment amount must be greater than zero.'
			);
		}

		if (String.isBlank(request.currencyCode)) {
			throw StripeException.validationError('Currency is required.');
		}

		if (request.currencyCode.trim().length() != 3) {
			throw StripeException.validationError(
				'Currency must contain exactly three characters.'
			);
		}

		if (!String.isBlank(request.customerEmail)) {
			validateEmail(request.customerEmail);
		}
	}

	/**
	 * Basic email validation.
	 */
	private static void validateEmail(String email) {
		if (String.isBlank(email)) {
			return;
		}

		Pattern emailPattern = Pattern.compile(
			'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'
		);

		if (!emailPattern.matcher(email.trim()).matches()) {
			throw StripeException.validationError(
				'Invalid customer email address.'
			);
		}
	}

	/**
	 * Utility method used by the controller
	 * to return a clean payment response.
	 */
	public static StripeDTO.PaymentIntentResult buildPaymentIntentResult(
		StripeDTO.PaymentIntentResponse paymentIntent
	) {
		if (paymentIntent == null) {
			throw new StripeException(
				'Stripe PaymentIntent response is empty.'
			);
		}
		StripeDTO.PaymentIntentResult result = new StripeDTO.PaymentIntentResult();
		result.paymentIntentId = paymentIntent.id;
		result.clientSecret = paymentIntent.client_secret;
		result.status = paymentIntent.status;
		result.amount = paymentIntent.amount;
		result.amountReceived = paymentIntent.amount_received;
		result.currencyCode = paymentIntent.currencyCode;
		result.description = paymentIntent.description;
		return result;
	}
}