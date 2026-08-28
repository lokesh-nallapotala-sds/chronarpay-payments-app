@RestResource(urlMapping='/custom-hardcoded/*')
/**
 * REST API exposing master payment data (generalData, companyCodes, paymentTypes,
 * paymentProviders and paymentCards) as a typed wrapper response.
 */
global with sharing class CustomAPI {

    /**
     * Returns the master data payload used by the payment UI.
     */
    @HttpGet
    global static void getMasterData() {
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

        MasterDataResponse resp = new MasterDataResponse();

        // generalData
        resp.generalData = new GeneralData();
        resp.generalData.isPartialPaymentAllowed = true;
        resp.generalData.cvvUseControl = '1';
        resp.generalData.isCvvUseControlEnabled = true;

        // companyCodes
        resp.companyCodes = new List<CompanyCode>{
            new CompanyCode('1000','EUR','Europe',true,false,false,true,true),
            new CompanyCode('3000','USD','North America',true,false,false,true,true)
        };

        // paymentTypes
        resp.paymentTypes = new List<PaymentType>{
            new PaymentType('D','[Deposits] Direct AR',true,true,true),
            new PaymentType('O','[Payments] Open AR',true,true,true)
        };

        // paymentProviders
        resp.paymentProviders = new List<PaymentProvider>{
            new PaymentProvider('PM','Worldpay',true,'2.2.0')
        };

        // paymentCards
        resp.paymentCards = new List<PaymentCard>{
            new PaymentCard('AMEX','AMEX','AX','PM','3000',false,0),
            new PaymentCard('DC','DC','DC','PM','6000',false,0),
            new PaymentCard('DISC','DISC','DI','PM','7000',false,0),
            new PaymentCard('EC','EC','EC','PM',null,false,0),
            new PaymentCard('JCB','JCB','JC','PM','8000',false,0),
            new PaymentCard('MC','MC','MC','PM','5000',true,0),
            new PaymentCard('VISA','VISA','VI','PM','4000',true,1.00)
        };

        res.statusCode = 200;
        res.addHeader('Content-Type','application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(resp));
    }

    /**
     * Wrapper for the full response
     */
    global class MasterDataResponse {
        public GeneralData generalData;
        public List<CompanyCode> companyCodes;
        public List<PaymentType> paymentTypes;
        public List<PaymentProvider> paymentProviders;
        public List<PaymentCard> paymentCards;
    }

    /** General configuration flags */
    global class GeneralData {
        public Boolean isPartialPaymentAllowed;
        public String cvvUseControl;
        public Boolean isCvvUseControlEnabled;
    }

    /** Company code metadata */
    global class CompanyCode {
        public String companyCode;
        public String currencyKey;
        public String description;
        public Boolean isActive;
        public Boolean is3dsDisabled;
        public Boolean isPaymentDisabled;
        public Boolean isDepositEnabled;
        public Boolean isEcheckEnabled;

        public CompanyCode(String companyCode, String currencyKey, String description, Boolean isActive, Boolean is3dsDisabled, Boolean isPaymentDisabled, Boolean isDepositEnabled, Boolean isEcheckEnabled) {
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

    /** Payment type metadata */
    global class PaymentType {
        public String paymentTypeCode;
        public String description;
        public Boolean isActive;
        public Boolean isReasonNotRequired;
        public Boolean isOverpaymentAllowed;

        public PaymentType(String code, String description, Boolean isActive, Boolean isReasonNotRequired, Boolean isOverpaymentAllowed) {
            this.paymentTypeCode = code;
            this.description = description;
            this.isActive = isActive;
            this.isReasonNotRequired = isReasonNotRequired;
            this.isOverpaymentAllowed = isOverpaymentAllowed;
        }
    }

    /** Payment provider metadata */
    global class PaymentProvider {
        public String provider;
        public String description;
        public Boolean isSecure3dsEnabled;
        public String secure3dsVersion;

        public PaymentProvider(String provider, String description, Boolean isSecure3dsEnabled, String secure3dsVersion) {
            this.provider = provider;
            this.description = description;
            this.isSecure3dsEnabled = isSecure3dsEnabled;
            this.secure3dsVersion = secure3dsVersion;
        }
    }

    /** Payment card metadata */
    global class PaymentCard {
        public String paymentCardType;
        public String sapCardType;
        public String gatewayCardType;
        public String provider;
        public String externalPaymentCardType;
        public Boolean usesPreauthorization;
        public Decimal preauthorizationAmount;

        public PaymentCard(String paymentCardType, String sapCardType, String gatewayCardType, String provider, String externalPaymentCardType, Boolean usesPreauthorization, Decimal preauthorizationAmount) {
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