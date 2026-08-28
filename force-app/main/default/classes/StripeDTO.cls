public with sharing class StripeDTO {

    /***********************************************************************
     * Generic Stripe Error
     ***********************************************************************/
    public class StripeErrorResponse {
        public StripeError error;
    }

    public class StripeError {
        public String type;
        public String code;
        public String message;
        public String decline_code;
        public String param;
        public String doc_url;
    }

    /***********************************************************************
     * PaymentIntent Create Request
     ***********************************************************************/
    public class CreatePaymentIntentRequest {
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public String currencyCode;
        @AuraEnabled
        public String customerName;
        @AuraEnabled
        public String customerEmail;
        @AuraEnabled
        public String invoiceNumber;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String accountId;
        @AuraEnabled
        public String paymentId;
        public CreatePaymentIntentRequest() {
        }

        public CreatePaymentIntentRequest(
            Decimal amount,
            String currencyCode,
            String customerName,
            String customerEmail,
            String invoiceNumber,
            String description
        ){
            this.amount = amount;
            this.currencyCode = currencyCode;
            this.customerName = customerName;
            this.customerEmail = customerEmail;
            this.invoiceNumber = invoiceNumber;
            this.description = description;
        }
    }

    /***********************************************************************
     * PaymentIntent Response
     ***********************************************************************/
    public class PaymentIntentResponse {
        public String id;
        public String objectMap;
        public Integer amount;
        public Integer amount_capturable;
        public Integer amount_received;
        public String client_secret;
        public String currencyCode;
        public String customer;
        public String description;
        public Boolean livemode;
        public String status;
        public Long created;
        public Metadata metadata;
        public AutomaticPaymentMethods automatic_payment_methods;
        public Charges charges;
    }

    /***********************************************************************
     * Automatic Payment Methods
     ***********************************************************************/
    public class AutomaticPaymentMethods{
        public Boolean enabled;
    }

    /***********************************************************************
     * Metadata
     ***********************************************************************/
    public class Metadata{
        public String invoiceNumber;
        public String paymentId;
        public String accountId;
    }

    /***********************************************************************
     * Charges
     ***********************************************************************/
    public class Charges{
        public String objectMap;
        public Integer total_count;
        public Boolean has_more;
        public List<Charge> data;
    }

    /***********************************************************************
     * Charge
     ***********************************************************************/
    public class Charge{
        public String id;
        public Integer amount;
        public Integer amount_captured;
        public Integer amount_refunded;
        public String balance_transaction;
        public BillingDetails billing_details;
        public String currencyCode;
        public Boolean captured;
        public Boolean paid;
        public Boolean refunded;
        public String payment_method;
        public String receipt_url;
        public String status;
    }

    /***********************************************************************
     * Billing Details
     ***********************************************************************/
    public class BillingDetails{
        public Address address;
        public String email;
        public String name;
        public String phone;
    }

    /***********************************************************************
     * Address
     ***********************************************************************/
    public class Address{
        public String city;
        public String country;
        public String line1;
        public String line2;
        public String postal_code;
        public String state;
    }

    /***********************************************************************
     * Retrieve Payment Response
     ***********************************************************************/
    public class RetrievePaymentResponse{
        public String id;
        public Integer amount;
        public Integer amount_received;
        public String currencyCode;
        public String customer;
        public String description;
        public String client_secret;
        public String status;
        public Charges charges;
    }
    public class PaymentIntentResult {
        @AuraEnabled
        public String paymentIntentId;
        @AuraEnabled
        public String clientSecret;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Integer amount;
        @AuraEnabled
        public Integer amountReceived;
        @AuraEnabled
        public String currencyCode;
        @AuraEnabled
        public String description;
    }
    public class RefundResponse {
        public String id;
        public String objectMap;
        public Integer amount;
        public Integer amount_captured;
        public Integer amount_refunded;
        public String currencyCode;
        public String payment_intent;
        public String status;
        public Boolean paid;
        public Boolean refunded;
        public String reason;
        public Long created;
        public String receipt_number;
        public String failure_reason;
    }
}