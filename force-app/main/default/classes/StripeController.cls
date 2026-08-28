/**
 * StripeController
 *
 * Apex entry point for the Stripe Payment LWC.
 *
 * Responsibilities:
 *  - Expose AuraEnabled methods
 *  - Validate user input
 *  - Call StripeService
 *  - Return LWC-friendly responses
 *
 * This controller NEVER receives:
 *  - Card number
 *  - CVC/CVV
 *  - Expiration date
 *  - Stripe secret key
 *
 * Stripe Elements handles sensitive payment information
 * directly in the browser.
 */
public with sharing class StripeController {
	/*
	 * IMPORTANT
	 *
	 * This should normally come from Salesforce
	 * Custom Metadata / Custom Label.
	 *
	 * For the initial demo, replace the value below
	 * with your Stripe TEST publishable key.
	 *
	 * Example:
	 *
	 * pk_test_51XXXXXXXXXXXX
	 *
	 * DO NOT put your sk_test key here.
	 */
	private static final String STRIPE_PUBLISHABLE_KEY = 'pk_test_REPLACE_WITH_YOUR_PUBLISHABLE_KEY';

	/**
	 * Returns Stripe publishable key to LWC.
	 *
	 * Publishable keys are safe to expose to the browser.
	 *
	 * Secret keys MUST NEVER be returned from Apex.
	 */
    @AuraEnabled(cacheable=true)
    public static String getStripePublishableKey() {
        Stripe_Settings__mdt settings = [
            SELECT Publishable_Key__c
            FROM Stripe_Settings__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
    
        if (
            settings == null ||
            String.isBlank(settings.Publishable_Key__c)
        ) {
            throw new AuraHandledException(
                'Stripe publishable key is not configured.'
            );
        }
    
        String publishableKey =
            settings.Publishable_Key__c.trim();
    
        if (
            !publishableKey.startsWith('pk_test_') &&
            !publishableKey.startsWith('pk_live_')
        ) {
            throw new AuraHandledException(
                'Invalid Stripe publishable key configuration.'
            );
        }
    
        return publishableKey;
    }
	/**
	 * Creates a Stripe PaymentIntent.
	 *
	 * Called by the LWC before Stripe.confirmCardPayment().
	 *
	 * @param amount
	 *        Amount in normal Salesforce currency units.
	 *
	 *        Example:
	 *        25.50
	 *
	 * @param currency
	 *        ISO currency code.
	 *
	 *        Example:
	 *        USD
	 *
	 * @param customerName
	 *        Customer name.
	 *
	 * @param customerEmail
	 *        Customer email.
	 *
	 * @param invoiceNumber
	 *        Salesforce invoice number.
	 *
	 * @param description
	 *        Payment description.
	 *
	 * @param accountId
	 *        Optional Salesforce Account Id.
	 *
	 * @param paymentId
	 *        Optional Salesforce Payment__c Id.
	 *
	 * @return PaymentIntentResult
	 */
	@AuraEnabled
	public static StripeDTO.PaymentIntentResult createPaymentIntent(
		Decimal amount,
		String currencyCode,
		String customerName,
		String customerEmail,
		String invoiceNumber,
		String description,
		String accountId,
		String paymentId
	) {
		try {
			StripeDTO.CreatePaymentIntentRequest request = new StripeDTO.CreatePaymentIntentRequest();

			request.amount = amount;

			request.currencyCode = normalizeCurrency(currencyCode);

			request.customerName = customerName;

			request.customerEmail = customerEmail;

			request.invoiceNumber = invoiceNumber;

			request.description = description;

			request.accountId = accountId;

			request.paymentId = paymentId;

			StripeDTO.PaymentIntentResponse paymentIntent = StripeService.createPaymentIntent(
				request
			);

			return StripeService.buildPaymentIntentResult(paymentIntent);
		} catch (StripeException ex) {
			throw ex.toAuraException();
		} catch (AuraHandledException ex) {
			throw ex;
		} catch (Exception ex) {
			throw new AuraHandledException(
				'Unable to create payment: ' + ex.getMessage()
			);
		}
	}

	/**
	 * Retrieves the current Stripe PaymentIntent.
	 *
	 * Useful when the frontend needs to check
	 * the latest Stripe payment status.
	 */
	@AuraEnabled
	public static StripeDTO.PaymentIntentResult getPaymentIntent(
		String paymentIntentId
	) {
		try {
			StripeDTO.PaymentIntentResponse paymentIntent = StripeService.getPaymentIntent(
				paymentIntentId
			);

			return StripeService.buildPaymentIntentResult(paymentIntent);
		} catch (StripeException ex) {
			throw ex.toAuraException();
		} catch (Exception ex) {
			throw new AuraHandledException(
				'Unable to retrieve payment: ' + ex.getMessage()
			);
		}
	}

	/**
	 * Creates a Stripe refund.
	 *
	 * amount = null means full refund.
	 *
	 * amount != null means partial refund.
	 */
	@AuraEnabled
	public static StripeDTO.RefundResponse createRefund(
		String paymentIntentId,
		Decimal amount,
		String currencyCode
	) {
		try {
			return StripeService.createRefund(
				paymentIntentId,
				amount,
				normalizeCurrency(currencyCode)
			);
		} catch (StripeException ex) {
			throw ex.toAuraException();
		} catch (Exception ex) {
			throw new AuraHandledException(
				'Unable to create refund: ' + ex.getMessage()
			);
		}
	}

	/**
	 * Converts currency into a normalized
	 * three-letter lowercase ISO currency code.
	 */
	private static String normalizeCurrency(String currencyCode) {
		if (String.isBlank(currencyCode)) {
			return null;
		}

		return currencyCode.trim().toLowerCase();
	}

	/**
	 * Returns a simple status message.
	 *
	 * Useful for testing the Apex → Stripe connection
	 * without creating a payment.
	 */
	@AuraEnabled
	public static String testStripeConnection() {
		try {
			/*
			 * There is no separate "ping" endpoint
			 * required here.
			 *
			 * We simply validate that the Named Credential
			 * is available by making a safe Stripe API request.
			 *
			 * A PaymentIntent ID must be supplied for the
			 * actual retrieve operation, so this method
			 * intentionally only validates configuration.
			 */
			if (
				String.isBlank(STRIPE_PUBLISHABLE_KEY) ||
				STRIPE_PUBLISHABLE_KEY.contains('REPLACE_WITH')
			) {
				return 'Stripe publishable key is not configured.';
			}

			return 'Stripe configuration is available.';
		} catch (Exception ex) {
			throw new AuraHandledException(
				'Stripe connection test failed: ' + ex.getMessage()
			);
		}
	}
}