@RestResource(urlMapping='/getPayerDetails/*')
/**
 * Returns Payer account details using the CNBS Payer details contract shape.
 */
global with sharing class GetPayerDetailsAPI {

    @HttpGet
    global static void getPayerDetails() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (req == null) {
            req = new RestRequest();
            RestContext.request = req;
        }
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        PayerDetailResponse responseWrapper = new PayerDetailResponse();
        res.addHeader('Content-Type', 'application/json');

        try {
            String customerNumber = req.params.get('customer_number');
            String companyCode = req.params.get('company_code');
            String payerDetAction = req.params.get('payer_det_action');
            String salesOrganization = req.params.get('sales_organization');
            String distributionChannel = req.params.get('distribution_channel');
            String division = req.params.get('division');

            if (String.isBlank(customerNumber)) {
                throw new CalloutException('customer_number parameter is required.');
            }

            List<Account> payers = [
                SELECT Id, Name, Name_2__c, AccountNumber, account_id__c,
                       sales_organization__c, distribution_channel__c, division__c,
                       company_code__c, BillingCity, District__c, BillingStreet,
                       BillingPostalCode, BillingStateCode, BillingCountryCode, Phone
                FROM Account
                WHERE Type = 'Payer' AND AccountNumber = :customerNumber
                WITH USER_MODE
            ];

            Account payer = selectMatchingPayer(payers, companyCode, salesOrganization, distributionChannel, division);
            if (payer == null) {
                throw new QueryException('Payer account not found.');
            }

            List<Contact> contacts = [
                SELECT Id, AccountId, Phone, Email
                FROM Contact
                WHERE AccountId = :payer.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];

            List<Payment_Method__c> cards = [
                SELECT Id, Account__c, Card_Type__c, Card_Token__c, Cardholder_Name__c,
                       Valid_From__c, Valid_To__c, Is_Default__c, Last_Four__c
                FROM Payment_Method__c
                WHERE Account__c = :payer.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];

            List<Auto_Pay_Enrollment__c> autoPays = [
                SELECT Id, Account__c, Company_Code__c, Payment_Type__c, Is_Enrolled__c
                FROM Auto_Pay_Enrollment__c
                WHERE Account__c = :payer.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];

            List<Account_Relationship__c> relationships = [
                SELECT Id, SoldTo_Account__c, SoldTo_Account__r.AccountNumber,
                       SoldTo_Account__r.Name, SoldTo_Account__r.Name_2__c, SoldTo_Account__r.BillingCity,
                       SoldTo_Account__r.District__c, SoldTo_Account__r.BillingStreet,
                       SoldTo_Account__r.BillingPostalCode, SoldTo_Account__r.BillingStateCode,
                       SoldTo_Account__r.BillingCountryCode, SoldTo_Account__r.sales_organization__c,
                       SoldTo_Account__r.distribution_channel__c, SoldTo_Account__r.division__c
                FROM Account_Relationship__c
                WHERE Payer_Account__c = :payer.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];

            List<SoldToWrapper> soldToList = buildSoldToList(relationships, salesOrganization, distributionChannel, division);

            Detail detail = buildDetail(payer, contacts, cards, autoPays, soldToList);

            Status status = new Status();
            status.message_type = 'S';
            status.message_identification = '/CNBS/X_API';
            status.message_number = 10;
            status.message_line_string = 'Request successfully processed';

            responseWrapper.detail = detail;
            responseWrapper.status = status;
            res.statusCode = 200;
        } catch (Exception e) {
            Status status = new Status();
            status.message_type = 'E';
            status.message_identification = '/CNBS/X_API';
            status.message_number = 500;
            status.message_line_string = e.getMessage();

            responseWrapper.status = status;

            if (e.getMessage().contains('required')) {
                res.statusCode = 400;
            } else if (e.getTypeName() == 'System.QueryException') {
                res.statusCode = 404;
                status.message_line_string = 'Payer account not found.';
            } else {
                res.statusCode = 500;
            }
        }

        res.responseBody = Blob.valueOf(JSON.serialize(responseWrapper));
    }

    private static Account selectMatchingPayer(List<Account> payers, String companyCode, String salesOrganization, String distributionChannel, String division) {
        for (Account payer : payers) {
            Boolean matchesCompany = String.isBlank(companyCode) || payer.company_code__c == companyCode;
            Boolean matchesSalesArea = String.isBlank(salesOrganization) || payer.sales_organization__c == salesOrganization;
            Boolean matchesDistribution = String.isBlank(distributionChannel) || payer.distribution_channel__c == distributionChannel;
            Boolean matchesDivision = String.isBlank(division) || payer.division__c == division;
            if (matchesCompany && matchesSalesArea && matchesDistribution && matchesDivision) {
                return payer;
            }
        }
        return null;
    }

    private static Detail buildDetail(Account payer, List<Contact> contacts, List<Payment_Method__c> cards, List<Auto_Pay_Enrollment__c> autoPays, List<SoldToWrapper> soldToList) {
        Detail detail = new Detail();
        detail.address_data = buildAddressData(payer);
        detail.communication_data = buildCommunicationData(payer, contacts);
        detail.company_data = buildCompanyData(payer);
        detail.payment_cards = buildPaymentCards(cards);
        detail.soldto_list = soldToList;
        detail.auto_pay_status = buildAutoPayStatus(autoPays);
        return detail;
    }

    private static AddressDataWrapper buildAddressData(Account payer) {
        AddressDataWrapper addr = new AddressDataWrapper();
        addr.name = payer.Name;
        addr.name_2 = payer.Name_2__c;
        addr.city = payer.BillingCity;
        addr.district = payer.District__c;
        addr.street = payer.BillingStreet;
        addr.postal_code_city = payer.BillingPostalCode;
        addr.region = payer.BillingStateCode;
        addr.country = payer.BillingCountryCode;
        return addr;
    }

    private static CommunicationDataWrapper buildCommunicationData(Account payer, List<Contact> contacts) {
        CommunicationDataWrapper comm = new CommunicationDataWrapper();
        comm.phone = new List<PhoneWrapper>();
        comm.smtp = new List<SmtpWrapper>();

        if (contacts != null && !contacts.isEmpty()) {
            for (Contact con : contacts) {
                if (String.isNotBlank(con.Phone)) {
                    PhoneWrapper ph = new PhoneWrapper();
                    ph.country_code = payer.BillingCountryCode;
                    ph.standard = 'X';
                    ph.telephone = con.Phone;
                    comm.phone.add(ph);
                }
                if (String.isNotBlank(con.Email)) {
                    SmtpWrapper smtpEntry = new SmtpWrapper();
                    smtpEntry.standard = comm.smtp.isEmpty() ? 'X' : '';
                    smtpEntry.email = con.Email;
                    comm.smtp.add(smtpEntry);
                }
            }
        }

        if (comm.phone.isEmpty() && String.isNotBlank(payer.Phone)) {
            PhoneWrapper ph = new PhoneWrapper();
            ph.country_code = payer.BillingCountryCode;
            ph.standard = 'X';
            ph.telephone = payer.Phone;
            comm.phone.add(ph);
        }

        return comm;
    }

    private static List<CompanyDataWrapper> buildCompanyData(Account payer) {
        List<CompanyDataWrapper> companyData = new List<CompanyDataWrapper>();
        if (String.isNotBlank(payer.company_code__c)) {
            CompanyDataWrapper companyNode = new CompanyDataWrapper();
            CompanyCodeWrapper data = new CompanyCodeWrapper();
            data.company_code = payer.company_code__c;
            companyNode.data = data;
            companyData.add(companyNode);
        }
        return companyData;
    }

    private static List<PaymentCardWrapper> buildPaymentCards(List<Payment_Method__c> cards) {
        List<PaymentCardWrapper> paymentCards = new List<PaymentCardWrapper>();
        if (cards == null || cards.isEmpty()) {
            return paymentCards;
        }

        for (Payment_Method__c card : cards) {
            PaymentCardWrapper pc = new PaymentCardWrapper();
            pc.payment_card_type = card.Card_Type__c;
            pc.payment_card_token = card.Card_Token__c;
            pc.payment_card_name = card.Cardholder_Name__c;
            pc.valid_from = card.Valid_From__c != null ? Datetime.newInstance(card.Valid_From__c.year(), card.Valid_From__c.month(), card.Valid_From__c.day()).format('MM-dd-yyyy') : null;
            pc.valid_to = card.Valid_To__c != null ? Datetime.newInstance(card.Valid_To__c.year(), card.Valid_To__c.month(), card.Valid_To__c.day()).format('MM-dd-yyyy') : null;
            pc.default_x = card.Is_Default__c ? 'X' : '';
            pc.last_four = card.Last_Four__c;
            paymentCards.add(pc);
        }
        return paymentCards;
    }

    private static List<SoldToWrapper> buildSoldToList(List<Account_Relationship__c> relationships, String salesOrganization, String distributionChannel, String division) {
        List<SoldToWrapper> soldToList = new List<SoldToWrapper>();
        if (relationships == null || relationships.isEmpty()) {
            return soldToList;
        }

        for (Account_Relationship__c rel : relationships) {
            if (rel.SoldTo_Account__r == null) {
                continue;
            }

            Account soldTo = rel.SoldTo_Account__r;
            Boolean matchesSalesArea = String.isBlank(salesOrganization) || soldTo.sales_organization__c == salesOrganization;
            Boolean matchesDistribution = String.isBlank(distributionChannel) || soldTo.distribution_channel__c == distributionChannel;
            Boolean matchesDivision = String.isBlank(division) || soldTo.division__c == division;
            if (!(matchesSalesArea && matchesDistribution && matchesDivision)) {
                continue;
            }

            SoldToWrapper soldToWrapper = new SoldToWrapper();
            soldToWrapper.customer_number = soldTo.AccountNumber;
            soldToWrapper.sales_area_data = new SalesAreaDataWrapper();
            soldToWrapper.sales_area_data.sales_organization = soldTo.sales_organization__c;
            soldToWrapper.sales_area_data.distribution_channel = soldTo.distribution_channel__c;
            soldToWrapper.sales_area_data.division = soldTo.division__c;
            soldToWrapper.address_data = new AddressDataWrapper();
            soldToWrapper.address_data.name = soldTo.Name;
            soldToWrapper.address_data.name_2 = soldTo.Name_2__c;
            soldToWrapper.address_data.city = soldTo.BillingCity;
            soldToWrapper.address_data.district = soldTo.District__c;
            soldToWrapper.address_data.street = soldTo.BillingStreet;
            soldToWrapper.address_data.postal_code_city = soldTo.BillingPostalCode;
            soldToWrapper.address_data.region = soldTo.BillingStateCode;
            soldToWrapper.address_data.country = soldTo.BillingCountryCode;
            soldToList.add(soldToWrapper);
        }
        return soldToList;
    }

    private static List<AutoPayStatusWrapper> buildAutoPayStatus(List<Auto_Pay_Enrollment__c> autoPays) {
        List<AutoPayStatusWrapper> statuses = new List<AutoPayStatusWrapper>();
        if (autoPays == null || autoPays.isEmpty()) {
            return statuses;
        }

        for (Auto_Pay_Enrollment__c autoPay : autoPays) {
            AutoPayStatusWrapper statusNode = new AutoPayStatusWrapper();
            statusNode.company_code = autoPay.Company_Code__c;
            statusNode.payment_method = autoPay.Payment_Type__c;
            statusNode.enrolled = autoPay.Is_Enrolled__c;
            statuses.add(statusNode);
        }
        return statuses;
    }

    global class PayerDetailResponse {
        public Detail detail;
        public Status status;
    }

    global class Detail {
        public AddressDataWrapper address_data;
        public CommunicationDataWrapper communication_data;
        public List<CompanyDataWrapper> company_data;
        public List<PaymentCardWrapper> payment_cards;
        public List<SoldToWrapper> soldto_list;
        public List<AutoPayStatusWrapper> auto_pay_status;
    }

    global class AddressDataWrapper {
        public String name;
        public String name_2;
        public String city;
        public String district;
        public String street;
        public String postal_code_city;
        public String region;
        public String country;
    }

    global class CommunicationDataWrapper {
        public List<PhoneWrapper> phone;
        public List<SmtpWrapper> smtp;
    }

    global class PhoneWrapper {
        public String country_code;
        public String standard;
        public String telephone;
    }

    global class SmtpWrapper {
        public String standard;
        public String email;
    }

    global class CompanyDataWrapper {
        public CompanyCodeWrapper data;
    }

    global class CompanyCodeWrapper {
        public String company_code;
    }

    global class PaymentCardWrapper {
        public String payment_card_type;
        public String payment_card_token;
        public String payment_card_name;
        public String valid_from;
        public String valid_to;
        public String default_x;
        public String last_four;
    }

    global class SoldToWrapper {
        public String customer_number;
        public SalesAreaDataWrapper sales_area_data;
        public AddressDataWrapper address_data;
    }

    global class SalesAreaDataWrapper {
        public String sales_organization;
        public String distribution_channel;
        public String division;
    }

    global class AutoPayStatusWrapper {
        public String company_code;
        public String payment_method;
        public Boolean enrolled;
    }

    global class Status {
        public String message_type;
        public String message_identification;
        public Integer message_number;
        public String message_line_string;
    }
}