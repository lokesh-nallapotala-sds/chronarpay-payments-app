@RestResource(urlMapping='/application-hardcoded/*')
/**
 * REST API for returning application configuration details.
 */
global with sharing class ApplicationAPI {

    /**
     * Returns the application configuration payload for the consumer.
     */
    @HttpGet
    global static void getApplicationConfiguration() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        String isRefresh = req != null ? req.params.get('isRefresh') : null;
        String lang = req != null ? req.params.get('lang') : null;

        if (String.isBlank(isRefresh)) {
            isRefresh = 'true';
        }

        if (String.isBlank(lang)) {
            lang = 'en';
        }

        ApplicationConfigurationResponse response = new ApplicationConfigurationResponse();
        response.allowRegistration = true;
        response.privacyPolicy = 'https://chronarpay.com/';
        response.termsAndConditions = 'https://chronarpay.com/customers/';
        response.contactUs = 'https://chronarpay.com/company/';
        response.addressValidationOptions = 'zip';
        response.allowGuestPayment = true;
        response.isAccountLinkingEnabled = true;
        response.maxPaymentAllowed = '4000';
        response.maxECheckPaymentAllowed = '5000';
        response.copyrightYear = 2026;
        response.paymentIntegrationType = 'iframe';
        response.enablePreAuth = true;

        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    /**
     * Wrapper class for the application configuration response payload.
     */
    global class ApplicationConfigurationResponse {
        public Boolean allowRegistration;
        public String privacyPolicy;
        public String termsAndConditions;
        public String contactUs;
        public String addressValidationOptions;
        public Boolean allowGuestPayment;
        public Boolean isAccountLinkingEnabled;
        public String maxPaymentAllowed;
        public String maxECheckPaymentAllowed;
        public Integer copyrightYear;
        public String paymentIntegrationType;
        public Boolean enablePreAuth;
    }
}