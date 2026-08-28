@RestResource(urlMapping='/getSoldToDetails/*')
/**
 * Returns Sold-To account details using the CNBS Sold-To details contract shape.
 */
global with sharing class GetSoldToDetailsAPI {

    @HttpGet
    global static void getSoldToDetails() {
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

        SoldToDetailResponse responseWrapper = new SoldToDetailResponse();
        res.addHeader('Content-Type', 'application/json');

        try {
            String customerNumber = req.params.get('customer_number');
            String salesOrganization = req.params.get('sales_organization');
            String distributionChannel = req.params.get('distribution_channel');
            String division = req.params.get('division');

            if (String.isBlank(customerNumber)) {
                throw new CalloutException('customer_number parameter is required.');
            }

            List<Account> soldTos = [
                SELECT Id, Name, Name_2__c, AccountNumber,
                       account_id__c, sales_organization__c, distribution_channel__c,
                       division__c, company_code__c, BillingCity, District__c,
                       BillingStreet, BillingPostalCode, BillingStateCode,
                       BillingCountryCode, Phone
                FROM Account
                WHERE Type = 'Sold-To' AND AccountNumber = :customerNumber
                WITH USER_MODE
            ];

            Account soldTo = selectMatchingSoldTo(soldTos, salesOrganization, distributionChannel, division);
            if (soldTo == null) {
                throw new QueryException('Sold-To account not found.');
            }

            List<Contact> contacts = [
                SELECT Id, AccountId, Phone, Email
                FROM Contact
                WHERE AccountId = :soldTo.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];

            List<Account_Relationship__c> relationships = [
                SELECT Id, Payer_Account__c, Payer_Account__r.AccountNumber,
                       Payer_Account__r.Name, Payer_Account__r.BillingCity,
                       Payer_Account__r.District__c, Payer_Account__r.BillingStreet,
                       Payer_Account__r.BillingPostalCode, Payer_Account__r.BillingStateCode,
                       Payer_Account__r.BillingCountryCode
                FROM Account_Relationship__c
                WHERE SoldTo_Account__c = :soldTo.Id
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];

            Detail detail = buildDetail(soldTo, contacts, relationships);

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
                status.message_line_string = 'Sold-To account not found.';
            } else {
                res.statusCode = 500;
            }
        }

        res.responseBody = Blob.valueOf(JSON.serialize(responseWrapper));
    }

    private static Account selectMatchingSoldTo(List<Account> soldTos, String salesOrganization, String distributionChannel, String division) {
        for (Account soldTo : soldTos) {
            Boolean matchesSalesArea = String.isBlank(salesOrganization) || soldTo.sales_organization__c == salesOrganization;
            Boolean matchesDistribution = String.isBlank(distributionChannel) || soldTo.distribution_channel__c == distributionChannel;
            Boolean matchesDivision = String.isBlank(division) || soldTo.division__c == division;
            if (matchesSalesArea && matchesDistribution && matchesDivision) {
                return soldTo;
            }
        }
        return null;
    }

    private static Detail buildDetail(Account soldTo, List<Contact> contacts, List<Account_Relationship__c> relationships) {
        Detail detail = new Detail();
        detail.address_data = buildAddressData(soldTo);
        detail.communication_data = buildCommunicationData(soldTo, contacts);
        detail.sales_data = new List<SalesDataWrapper>();

        SalesDataWrapper salesBlock = new SalesDataWrapper();
        salesBlock.data = new SalesDataInner();
        salesBlock.data.sales_organization = soldTo.sales_organization__c;
        salesBlock.data.distribution_channel = soldTo.distribution_channel__c;
        salesBlock.data.division = soldTo.division__c;
        salesBlock.data.terms_of_payment = null;
        salesBlock.data.deletion_flag = null;
        salesBlock.data.customer_order_block = null;
        salesBlock.data.manual_invoice_maintenance = null;
        salesBlock.data.company_code = soldTo.company_code__c;
        salesBlock.data.currency_key = null;
        salesBlock.partner = buildPartnerData(relationships);
        detail.sales_data.add(salesBlock);
        return detail;
    }

    private static AddressDataWrapper buildAddressData(Account soldTo) {
        AddressDataWrapper addr = new AddressDataWrapper();
        addr.name = soldTo.Name;
        addr.name_2 = soldTo.Name_2__c;
        addr.city = soldTo.BillingCity;
        addr.district = soldTo.District__c;
        addr.street = soldTo.BillingStreet;
        addr.postal_code_city = soldTo.BillingPostalCode;
        addr.region = soldTo.BillingStateCode;
        addr.country = soldTo.BillingCountryCode;
        return addr;
    }

    private static CommunicationDataWrapper buildCommunicationData(Account soldTo, List<Contact> contacts) {
        CommunicationDataWrapper comm = new CommunicationDataWrapper();
        comm.phone = new List<PhoneWrapper>();
        comm.smtp = new List<SmtpWrapper>();

        if (contacts != null && !contacts.isEmpty()) {
            for (Contact con : contacts) {
                if (String.isNotBlank(con.Phone)) {
                    PhoneWrapper ph = new PhoneWrapper();
                    ph.country_code = soldTo.BillingCountryCode;
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

        if (comm.phone.isEmpty() && String.isNotBlank(soldTo.Phone)) {
            PhoneWrapper ph = new PhoneWrapper();
            ph.country_code = soldTo.BillingCountryCode;
            ph.standard = 'X';
            ph.telephone = soldTo.Phone;
            comm.phone.add(ph);
        }

        return comm;
    }

    private static List<PartnerWrapper> buildPartnerData(List<Account_Relationship__c> relationships) {
        List<PartnerWrapper> partners = new List<PartnerWrapper>();
        if (relationships == null || relationships.isEmpty()) {
            return partners;
        }

        for (Account_Relationship__c rel : relationships) {
            if (rel.Payer_Account__r == null) {
                continue;
            }
            PartnerWrapper partner = new PartnerWrapper();
            partner.partner_function = 'AG';
            partner.partner_number = rel.Payer_Account__r.AccountNumber;
            partner.partner_counter = null;
            partner.address_data = new AddressDataWrapper();
            partner.address_data.name = rel.Payer_Account__r.Name;
            partner.address_data.city = rel.Payer_Account__r.BillingCity;
            partner.address_data.district = rel.Payer_Account__r.District__c;
            partner.address_data.street = rel.Payer_Account__r.BillingStreet;
            partner.address_data.postal_code_city = rel.Payer_Account__r.BillingPostalCode;
            partner.address_data.region = rel.Payer_Account__r.BillingStateCode;
            partner.address_data.country = rel.Payer_Account__r.BillingCountryCode;
            partners.add(partner);
        }
        return partners;
    }

    global class SoldToDetailResponse {
        public Detail detail;
        public Status status;
    }

    global class Detail {
        public AddressDataWrapper address_data;
        public CommunicationDataWrapper communication_data;
        public List<SalesDataWrapper> sales_data;
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

    global class SalesDataWrapper {
        public SalesDataInner data;
        public List<PartnerWrapper> partner;
    }

    global class SalesDataInner {
        public String sales_organization;
        public String distribution_channel;
        public String division;
        public String terms_of_payment;
        public String deletion_flag;
        public String customer_order_block;
        public String manual_invoice_maintenance;
        public String company_code;
        public String currency_key;
    }

    global class PartnerWrapper {
        public String partner_function;
        public Integer partner_counter;
        public String partner_number;
        public AddressDataWrapper address_data;
    }

    global class Status {
        public String message_type;
        public String message_identification;
        public Integer message_number;
        public String message_line_string;
    }
}