@RestResource(urlMapping='/custom/*')
/**
 * REST API exposing custom payment data from custom metadata records.
 */
global with sharing class CustomDataMetadataAPI {

    /**
     * Returns the custom data payload used by the payment UI.
     */
    @HttpGet
    global static void getCustomData() {
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

        MasterDataResponse response = new MasterDataResponse();
        response.generalData = buildGeneralData();
        response.companyCodes = buildCompanyCodes();
        response.paymentTypes = buildPaymentTypes();
        response.paymentProviders = buildPaymentProviders();
        response.paymentCards = buildPaymentCards();

        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    private static GeneralData buildGeneralData() {
        List<ChronarPay_General_Data__mdt> configs = getGeneralDataRecords();
        GeneralData data = new GeneralData();
        if (!configs.isEmpty()) {
            ChronarPay_General_Data__mdt config = configs[0];
            data.isPartialPaymentAllowed = config.Is_Partial_Payment_Allowed__c;
            data.cvvUseControl = config.CVV_Use_Control__c;
            data.isCvvUseControlEnabled = config.Is_CVV_Use_Control_Enabled__c;
        }
        return data;
    }

    private static List<CompanyCode> buildCompanyCodes() {
        List<CompanyCode> result = new List<CompanyCode>();
        for (ChronarPay_Company_Code__mdt record : getCompanyCodeRecords()) {
            result.add(new CompanyCode(
                record.Company_Code__c,
                record.Currency_Key__c,
                record.Description__c,
                record.Is_Active__c,
                record.Is_3DS_Disabled__c,
                record.Is_Payment_Disabled__c,
                record.Is_Deposit_Enabled__c,
                record.Is_Echeck_Enabled__c
            ));
        }
        return result;
    }

    private static List<PaymentType> buildPaymentTypes() {
        List<PaymentType> result = new List<PaymentType>();
        for (ChronarPay_Payment_Type__mdt record : getPaymentTypeRecords()) {
            result.add(new PaymentType(
                record.Payment_Type_Code__c,
                record.Description__c,
                record.Is_Active__c,
                record.Is_Reason_Not_Required__c,
                record.Is_Overpayment_Allowed__c
            ));
        }
        return result;
    }

    private static List<PaymentProvider> buildPaymentProviders() {
        List<PaymentProvider> result = new List<PaymentProvider>();
        for (ChronarPay_Payment_Provider__mdt record : getPaymentProviderRecords()) {
            result.add(new PaymentProvider(
                record.Provider__c,
                record.Description__c,
                record.Is_Secure_3DS_Enabled__c,
                record.Secure_3DS_Version__c
            ));
        }
        return result;
    }

    private static List<PaymentCard> buildPaymentCards() {
        List<PaymentCard> result = new List<PaymentCard>();
        for (ChronarPay_Payment_Card__mdt record : getPaymentCardRecords()) {
            result.add(new PaymentCard(
                record.Payment_Card_Type__c,
                record.SAP_Card_Type__c,
                record.Gateway_Card_Type__c,
                record.Provider__c,
                record.External_Payment_Card_Type__c,
                record.Uses_Preauthorization__c,
                record.Preauthorization_Amount__c
            ));
        }
        return result;
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static List<ChronarPay_General_Data__mdt> getGeneralDataRecords() {
        return [
            SELECT
                Is_Partial_Payment_Allowed__c,
                CVV_Use_Control__c,
                Is_CVV_Use_Control_Enabled__c
            FROM ChronarPay_General_Data__mdt
            LIMIT 1
        ];
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static List<ChronarPay_Company_Code__mdt> getCompanyCodeRecords() {
        return [
            SELECT
                Company_Code__c,
                Currency_Key__c,
                Description__c,
                Is_Active__c,
                Is_3DS_Disabled__c,
                Is_Payment_Disabled__c,
                Is_Deposit_Enabled__c,
                Is_Echeck_Enabled__c
            FROM ChronarPay_Company_Code__mdt
        ];
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static List<ChronarPay_Payment_Type__mdt> getPaymentTypeRecords() {
        return [
            SELECT
                Payment_Type_Code__c,
                Description__c,
                Is_Active__c,
                Is_Reason_Not_Required__c,
                Is_Overpayment_Allowed__c
            FROM ChronarPay_Payment_Type__mdt
        ];
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static List<ChronarPay_Payment_Provider__mdt> getPaymentProviderRecords() {
        return [
            SELECT
                Provider__c,
                Description__c,
                Is_Secure_3DS_Enabled__c,
                Secure_3DS_Version__c
            FROM ChronarPay_Payment_Provider__mdt
        ];
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static List<ChronarPay_Payment_Card__mdt> getPaymentCardRecords() {
        return [
            SELECT
                Payment_Card_Type__c,
                SAP_Card_Type__c,
                Gateway_Card_Type__c,
                Provider__c,
                External_Payment_Card_Type__c,
                Uses_Preauthorization__c,
                Preauthorization_Amount__c
            FROM ChronarPay_Payment_Card__mdt
        ];
    }

    /**
     * Wrapper for the full response.
     */
    global class MasterDataResponse {
        public GeneralData generalData;
        public List<CompanyCode> companyCodes;
        public List<PaymentType> paymentTypes;
        public List<PaymentProvider> paymentProviders;
        public List<PaymentCard> paymentCards;
    }

    /**
     * General configuration flags.
     */
    global class GeneralData {
        public Boolean isPartialPaymentAllowed;
        public String cvvUseControl;
        public Boolean isCvvUseControlEnabled;
    }

    /**
     * Company code metadata.
     */
    global class CompanyCode {
        /**
         * Creates a company code value object.
         *
         * @param companyCode The company code.
         * @param currencyKey The currency key.
         * @param description The company description.
         * @param isActive Whether the company code is active.
         * @param is3dsDisabled Whether 3DS is disabled.
         * @param isPaymentDisabled Whether payments are disabled.
         * @param isDepositEnabled Whether deposits are enabled.
         * @param isEcheckEnabled Whether e-check is enabled.
         */
        public String companyCode;
        public String currencyKey;
        public String description;
        public Boolean isActive;
        public Boolean is3dsDisabled;
        public Boolean isPaymentDisabled;
        public Boolean isDepositEnabled;
        public Boolean isEcheckEnabled;

        public CompanyCode(String companyCode, String currencyKey, String description, Boolean isActive,
                Boolean is3dsDisabled, Boolean isPaymentDisabled, Boolean isDepositEnabled, Boolean isEcheckEnabled) {
            this.companyCode = companyCode;
            this.currencyKey = currencyKey;
            this.description = description;
            this.isActive = isActive;
            this.is3dsDisabled = is3dsDisabled;
            this.isPaymentDisabled = isPaymentDisabled;
            this.isDepositEnabled = isDepositEnabled;
            this.isEcheckEnabled = isEcheckEnabled;
        }
    }

    /**
     * Payment type metadata.
     */
    global class PaymentType {
        /**
         * Creates a payment type value object.
         *
         * @param code The payment type code.
         * @param description The payment type description.
         * @param isActive Whether the payment type is active.
         * @param isReasonNotRequired Whether a reason is not required.
         * @param isOverpaymentAllowed Whether overpayment is allowed.
         */
        public String paymentTypeCode;
        public String description;
        public Boolean isActive;
        public Boolean isReasonNotRequired;
        public Boolean isOverpaymentAllowed;

        public PaymentType(String code, String description, Boolean isActive, Boolean isReasonNotRequired,
                Boolean isOverpaymentAllowed) {
            this.paymentTypeCode = code;
            this.description = description;
            this.isActive = isActive;
            this.isReasonNotRequired = isReasonNotRequired;
            this.isOverpaymentAllowed = isOverpaymentAllowed;
        }
    }

    /**
     * Payment provider metadata.
     */
    global class PaymentProvider {
        /**
         * Creates a payment provider value object.
         *
         * @param provider The provider code.
         * @param description The provider description.
         * @param isSecure3dsEnabled Whether 3DS is enabled.
         * @param secure3dsVersion The 3DS version.
         */
        public String provider;
        public String description;
        public Boolean isSecure3dsEnabled;
        public String secure3dsVersion;

        public PaymentProvider(String provider, String description, Boolean isSecure3dsEnabled,
                String secure3dsVersion) {
            this.provider = provider;
            this.description = description;
            this.isSecure3dsEnabled = isSecure3dsEnabled;
            this.secure3dsVersion = secure3dsVersion;
        }
    }

    /**
     * Payment card metadata.
     */
    global class PaymentCard {
        /**
         * Creates a payment card value object.
         *
         * @param paymentCardType The payment card type.
         * @param sapCardType The SAP card type.
         * @param gatewayCardType The gateway card type.
         * @param provider The provider code.
         * @param externalPaymentCardType The external payment card type.
         * @param usesPreauthorization Whether the card uses preauthorization.
         * @param preauthorizationAmount The preauthorization amount.
         */
        public String paymentCardType;
        public String sapCardType;
        public String gatewayCardType;
        public String provider;
        public String externalPaymentCardType;
        public Boolean usesPreauthorization;
        public Decimal preauthorizationAmount;

        public PaymentCard(String paymentCardType, String sapCardType, String gatewayCardType, String provider,
                String externalPaymentCardType, Boolean usesPreauthorization, Decimal preauthorizationAmount) {
            this.paymentCardType = paymentCardType;
            this.sapCardType = sapCardType;
            this.gatewayCardType = gatewayCardType;
            this.provider = provider;
            this.externalPaymentCardType = externalPaymentCardType;
            this.usesPreauthorization = usesPreauthorization;
            this.preauthorizationAmount = preauthorizationAmount;
        }
    }
}