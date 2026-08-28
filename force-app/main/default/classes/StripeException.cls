/**
 * StripeException
 *
 * Custom exception framework for Salesforce Stripe Integration.
 *
 * Responsibilities:
 *  - Handle Stripe API failures
 *  - Convert HTTP failures into readable errors
 *  - Preserve Stripe error details
 */
public with sharing class StripeException extends Exception {
    /**
     * Stripe HTTP Status Code
     */
    public Integer httpStatusCode;

    /**
     * Stripe error type
     */
    public String errorType;

    /**
     * Stripe error code
     */
    public String errorCode;

    /**
     * Stripe request identifier
     */
    public String requestId;

    /**
     * Full constructor
     */
    public StripeException(
        String message,
        Integer httpStatusCode,
        String errorType,
        String errorCode,
        String requestId
    ) {
        this.httpStatusCode = httpStatusCode;
        this.errorType = errorType;
        this.errorCode = errorCode;
        this.requestId = requestId;
    }

    /**
     * Creates Stripe exception from HTTP Response
     */
    public static StripeException fromHttpResponse(HttpResponse response) {
        Integer statusCode = response.getStatusCode();

        String body = response.getBody();

        StripeDTO.StripeErrorResponse errorResponse;

        String message = 'Stripe API request failed';

        String errorType;
        String errorCode;

        try {
            errorResponse = (StripeDTO.StripeErrorResponse) JSON.deserialize(
                body,
                StripeDTO.StripeErrorResponse.class
            );

            if (errorResponse != null && errorResponse.error != null) {
                message = errorResponse.error.message;

                errorType = errorResponse.error.type;

                errorCode = errorResponse.error.code;
            }
        } catch (Exception ex) {
            message = 'Stripe Error: ' + body;
        }

        return new StripeException(
            message,
            statusCode,
            errorType,
            errorCode,
            response.getHeader('Request-Id')
        );
    }

    /**
     * Converts exception into LWC friendly error
     */
    public AuraHandledException toAuraException() {
        String message = this.getMessage();

        if (String.isBlank(message)) {
            message = 'Unknown Stripe error occurred';
        }

        return new AuraHandledException(message);
    }

    /**
     * Creates a generic Stripe validation exception
     */
    public static StripeException validationError(String message) {
        return new StripeException(
            message,
            400,
            'validation_error',
            null,
            null
        );
    }

    /**
     * Creates authentication error
     */
    public static StripeException authenticationError() {
        return new StripeException(
            'Unable to authenticate with Stripe. Check Named Credential configuration.',
            401,
            'authentication_error',
            null,
            null
        );
    }

    /**
     * Creates configuration error
     */
    public static StripeException configurationError(String message) {
        return new StripeException(
            message,
            500,
            'configuration_error',
            null,
            null
        );
    }

    /**
     * Returns log-friendly information
     */
    public Map<String, Object> getErrorDetails() {
        return new Map<String, Object>{
            'message' => this.getMessage(),
            'httpStatusCode' => this.httpStatusCode,
            'errorType' => this.errorType,
            'errorCode' => this.errorCode,
            'requestId' => this.requestId
        };
    }
}