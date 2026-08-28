@RestResource(urlMapping='/application/*')
/**
 * REST API for returning application configuration details from custom metadata.
 */
global with sharing class ApplicationMetadataAPI {

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
        ChronarPay_App_Config__mdt config = getApplicationConfigurationMetadata();

        if (config != null) {
            response.allowRegistration = config.Allow_Registration__c;
            response.privacyPolicy = config.Privacy_Policy_URL__c;
            response.termsAndConditions = config.Terms_Conditions_URL__c;
            response.contactUs = config.Contact_Us_URL__c;
            response.addressValidationOptions = config.Address_Validation_Options__c;
            response.allowGuestPayment = config.Allow_Guest_Payment__c;
            response.isAccountLinkingEnabled = config.Is_Account_Linking_Enabled__c;
            response.maxPaymentAllowed =
                String.valueOf(config.Max_Payment_Allowed__c.intValue());
            
            response.maxECheckPaymentAllowed =
                String.valueOf(config.Max_ECheck_Payment_Allowed__c.intValue());
            response.copyrightYear = Integer.valueOf(config.Copyright_Year__c);
            response.paymentIntegrationType = config.Payment_Integration_Type__c;
            response.enablePreAuth = config.Enable_Pre_Auth__c;
        } else {
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
        }

        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    /**
     * Retrieves the default configuration metadata record.
     *
     * @return The metadata record containing application configuration values, or null if none exists.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static ChronarPay_App_Config__mdt getApplicationConfigurationMetadata() {
        List<ChronarPay_App_Config__mdt> configs = [
            SELECT
                Allow_Registration__c,
                Privacy_Policy_URL__c,
                Terms_Conditions_URL__c,
                Contact_Us_URL__c,
                Address_Validation_Options__c,
                Allow_Guest_Payment__c,
                Is_Account_Linking_Enabled__c,
                Max_Payment_Allowed__c,
                Max_ECheck_Payment_Allowed__c,
                Copyright_Year__c,
                Payment_Integration_Type__c,
                Enable_Pre_Auth__c
            FROM ChronarPay_App_Config__mdt
            WHERE DeveloperName = 'Application'
            LIMIT 1
        ];

        return configs.isEmpty() ? null : configs[0];
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