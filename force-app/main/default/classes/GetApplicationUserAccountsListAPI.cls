@RestResource(urlMapping='/getApplicationUserAccountsList/*')
/**
 * REST API for exposing many-to-many account information to external consumers.
 */
global with sharing class GetApplicationUserAccountsListAPI {

    global class ResponseWrapper {
        public List<DataWrapper> data;
        public StatusWrapper status;
    }

    global class StatusWrapper {
        public String message_type;
        public String message_identification;
        public Integer message_number;
        public String message_line_string;
    }

    global class DataWrapper {
        public String application_id;
        public String account_id;
        public String user_id;
        public String account_type;
        public String primary_account;
        public String sales_organization;
        public String distribution_channel;
        public String division;
        public String company_code;
        public PayerDetWrapper payer_det;
    }

    global class PayerDetWrapper {
        public AddressDataWrapper address_data;
        public CommunicationDataWrapper communcation_data;
        public List<CompanyDataWrapper> company_data;
        public List<PaymentCardWrapper> payment_cards;
        public List<SoldToWrapper> soldto_list;
        public List<AutoPayStatusWrapper> auto_pay_status;
    }

    global class AddressDataWrapper {
        public String name;
        public String city;
        public String street;
        public String postal_code_city;
        public String region;
        public String country;
        public String district;
    }

    global class CommunicationDataWrapper {
        public List<PhoneWrapper> phone;
    }

    global class PhoneWrapper {
        public String country_code;
        public String standard;
        public String telephone;
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
        public String payment_card_token;
    }

    @HttpGet
    global static void getAccountDetails() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        ResponseWrapper responseObj = new ResponseWrapper();
        
        try {
            //String accountId = req.params.get('accountId');
            String userId = req.params.get('userId');
            
            if (String.isBlank(userId)) {
                throw new CalloutException('userId parameter is required.');
            }

            String primaryAccountType = null;
            List<Application_User_Account__c> primaryJunction = [
                SELECT Chronarpay_User__r.primary_account_type__c
                FROM Application_User_Account__c 
                WHERE Chronarpay_User__c = :userId AND Is_Primary__c = true 
                LIMIT 1
            ];
            /*if (!primaryJunction.isEmpty() && primaryJunction[0].Account__r != null) {
                primaryAccountType = primaryJunction[0].Account__r.Type;
            }*/
            primaryAccountType = primaryJunction[0].Chronarpay_User__r.primary_account_type__c;

            List<Application_User_Account__c> junctionRecords;
            junctionRecords = [
                SELECT Account__c, Is_Primary__c, Chronarpay_User__c
                FROM Application_User_Account__c
                WHERE Chronarpay_User__c = :userId
            ];
            
            Set<Id> directAccountIds = new Set<Id>();
            for(Application_User_Account__c aua : junctionRecords) {
                if (aua.Account__c != null) {
                    directAccountIds.add(aua.Account__c);
                }
            }
            
            Map<Id, Account> allDirectAccounts = new Map<Id, Account>();
            if (!directAccountIds.isEmpty()) {
                allDirectAccounts = new Map<Id, Account>([
                    SELECT Id, Type, OwnerId, AccountNumber, account_id__c, sales_organization__c, distribution_channel__c, 
                           division__c, company_code__c, Name, BillingCity, BillingStreet, BillingPostalCode, 
                           BillingStateCode, BillingCountryCode, District__c, Phone
                    FROM Account 
                    WHERE Id IN :directAccountIds
                ]);
            }

            Set<Id> parentIds = new Set<Id>();
            List<Account_Relationship__c> directRelationships = [
                SELECT Payer_Account__c, SoldTo_Account__c 
                FROM Account_Relationship__c 
                WHERE SoldTo_Account__c IN :directAccountIds
            ];
            
            Map<Id, List<Id>> soldToToPayers = new Map<Id, List<Id>>();
            for (Account_Relationship__c rel : directRelationships) {
                if (rel.Payer_Account__c != null && rel.SoldTo_Account__c != null) {
                    parentIds.add(rel.Payer_Account__c);
                    if (!soldToToPayers.containsKey(rel.SoldTo_Account__c)) {
                        soldToToPayers.put(rel.SoldTo_Account__c, new List<Id>());
                    }
                    soldToToPayers.get(rel.SoldTo_Account__c).add(rel.Payer_Account__c);
                }
            }

            Map<Id, Account> parentPayers = new Map<Id, Account>();
            if (!parentIds.isEmpty()) {
                parentPayers = new Map<Id, Account>([
                    SELECT Id, Type, AccountNumber, account_id__c, sales_organization__c, distribution_channel__c, 
                           division__c, company_code__c, Name, BillingCity, BillingStreet, BillingPostalCode, 
                           BillingStateCode, BillingCountryCode, District__c, Phone
                    FROM Account 
                    WHERE Id IN :parentIds
                ]);
            }

            Set<Id> allPayerIds = new Set<Id>();
            for (Account acc : allDirectAccounts.values()) {
                if (acc.Type == 'Payer') {
                    allPayerIds.add(acc.Id);
                }
            }
            allPayerIds.addAll(parentIds);

            Map<Id, List<Account>> childSoldTos = new Map<Id, List<Account>>();
            if (!allPayerIds.isEmpty()) {
                List<Account_Relationship__c> payerRelationships = [
                    SELECT Payer_Account__c, SoldTo_Account__c 
                    FROM Account_Relationship__c 
                    WHERE Payer_Account__c IN :allPayerIds
                ];
                Set<Id> childSoldToIds = new Set<Id>();
                Map<Id, List<Id>> payerToSoldToIds = new Map<Id, List<Id>>();
                for (Account_Relationship__c rel : payerRelationships) {
                    if (rel.Payer_Account__c != null && rel.SoldTo_Account__c != null) {
                        childSoldToIds.add(rel.SoldTo_Account__c);
                        if (!payerToSoldToIds.containsKey(rel.Payer_Account__c)) {
                            payerToSoldToIds.put(rel.Payer_Account__c, new List<Id>());
                        }
                        payerToSoldToIds.get(rel.Payer_Account__c).add(rel.SoldTo_Account__c);
                    }
                }
                
                if (!childSoldToIds.isEmpty()) {
                    Map<Id, Account> childrenMap = new Map<Id, Account>([
                        SELECT Id, OwnerId, Type, AccountNumber, account_id__c, sales_organization__c, distribution_channel__c, 
                               division__c, Name, BillingCity, BillingStreet, BillingPostalCode, BillingStateCode, BillingCountryCode, District__c
                        FROM Account 
                        WHERE Id IN :childSoldToIds AND Type = 'Sold-To'
                    ]);
                    
                    for (Id payerId : payerToSoldToIds.keySet()) {
                        childSoldTos.put(payerId, new List<Account>());
                        for (Id soldToId : payerToSoldToIds.get(payerId)) {
                            if (childrenMap.containsKey(soldToId)) {
                                childSoldTos.get(payerId).add(childrenMap.get(soldToId));
                            }
                        }
                    }
                }
            }

            List<Contact> allContacts = new List<Contact>();
            if (!allPayerIds.isEmpty()) {
                allContacts = [
                    SELECT Id, AccountId, Phone
                    FROM Contact
                    WHERE AccountId IN :allPayerIds
                ];
            }
            Map<Id, List<Contact>> contactsMap = new Map<Id, List<Contact>>();
            for(Contact con : allContacts) {
                if(!contactsMap.containsKey(con.AccountId)) {
                    contactsMap.put(con.AccountId, new List<Contact>());
                }
                contactsMap.get(con.AccountId).add(con);
            }
            
            List<Payment_Method__c> allCards = new List<Payment_Method__c>();
            if (!allPayerIds.isEmpty()) {
                allCards = [
                    SELECT Id, Account__c, Card_Type__c, Card_Token__c, Cardholder_Name__c, Valid_From__c, Valid_To__c, Is_Default__c, Last_Four__c 
                    FROM Payment_Method__c 
                    WHERE Account__c IN :allPayerIds
                ];
            }
            Map<Id, List<Payment_Method__c>> cardsMap = new Map<Id, List<Payment_Method__c>>();
            for(Payment_Method__c c : allCards) {
                if(!cardsMap.containsKey(c.Account__c)) {
                    cardsMap.put(c.Account__c, new List<Payment_Method__c>());
                }
                cardsMap.get(c.Account__c).add(c);
            }
            
            List<Auto_Pay_Enrollment__c> allAutoPays = new List<Auto_Pay_Enrollment__c>();
            if (!allPayerIds.isEmpty()) {
                allAutoPays = [
                    SELECT Id, Account__c, Company_Code__c, Payment_Type__c, Is_Enrolled__c, Payment_Method__r.Card_Token__c 
                    FROM Auto_Pay_Enrollment__c 
                    WHERE Account__c IN :allPayerIds
                ];
            }
            Map<Id, List<Auto_Pay_Enrollment__c>> autoPayMap = new Map<Id, List<Auto_Pay_Enrollment__c>>();
            for(Auto_Pay_Enrollment__c ap : allAutoPays) {
                if(!autoPayMap.containsKey(ap.Account__c)) {
                    autoPayMap.put(ap.Account__c, new List<Auto_Pay_Enrollment__c>());
                }
                autoPayMap.get(ap.Account__c).add(ap);
            }

            List<DataWrapper> dataList = new List<DataWrapper>();

            for(Application_User_Account__c aua : junctionRecords) {
                Account directAcc = allDirectAccounts.get(aua.Account__c);
                if (directAcc == null) {
                    continue;
                }

                if (directAcc.Type != null && directAcc.Type.equalsIgnoreCase('Sold-To')) {
                    Boolean belongsToDirectPayer = false;
                    if (soldToToPayers.containsKey(directAcc.Id)) {
                        for (Id pId : soldToToPayers.get(directAcc.Id)) {
                            if (directAccountIds.contains(pId)) {
                                belongsToDirectPayer = true;
                                break;
                            }
                        }
                    }
                    if (belongsToDirectPayer) {
                        continue;
                    }
                }

                Boolean isPayer = (directAcc.Type != null && directAcc.Type.equalsIgnoreCase('Payer'));
                
                List<Account> payersToProcess = new List<Account>();
                if (isPayer) {
                    payersToProcess.add(directAcc);
                } else {
                    if (soldToToPayers.containsKey(directAcc.Id)) {
                        for (Id pId : soldToToPayers.get(directAcc.Id)) {
                            if (parentPayers.containsKey(pId)) {
                                payersToProcess.add(parentPayers.get(pId));
                            }
                        }
                    }
                    if (payersToProcess.isEmpty()) {
                        payersToProcess.add(directAcc);
                    }
                }

                for (Account payerAcc : payersToProcess) {
                    DataWrapper dataNode = new DataWrapper();
                    dataNode.application_id = 'CNBSMV01R';
                    dataNode.account_id = directAcc.Name;
                    dataNode.user_id = userId;
                    dataNode.account_type = String.isNotBlank(primaryAccountType) 
                        ? primaryAccountType 
                        : directAcc.Type;
                    dataNode.primary_account = directAcc.AccountNumber;
                    dataNode.sales_organization = directAcc.sales_organization__c;
                    dataNode.distribution_channel = directAcc.distribution_channel__c;
                    dataNode.division = directAcc.division__c;
                    dataNode.company_code = directAcc.company_code__c;

                    PayerDetWrapper payerDet = new PayerDetWrapper();
                
                // Address Data
                AddressDataWrapper addr = new AddressDataWrapper();
                addr.name = payerAcc.Name;
                addr.city = payerAcc.BillingCity;
                addr.street = payerAcc.BillingStreet;
                addr.postal_code_city = payerAcc.BillingPostalCode;
                addr.region = payerAcc.BillingStateCode;
                addr.country = payerAcc.BillingCountryCode;
                addr.district = payerAcc.District__c;
                payerDet.address_data = addr;

                // Communication Data
                CommunicationDataWrapper comm = new CommunicationDataWrapper();
                comm.phone = new List<PhoneWrapper>();
                if(contactsMap.containsKey(payerAcc.Id)) {
                    for(Contact con : contactsMap.get(payerAcc.Id)) {
                        if(con.Phone != null) {
                            PhoneWrapper pw = new PhoneWrapper();
                            pw.country_code = payerAcc.BillingCountryCode;
                            pw.standard = 'X';
                            pw.telephone = con.Phone;
                            comm.phone.add(pw);
                        }
                    }
                }
                if (comm.phone.isEmpty() && payerAcc.Phone != null) {
                    PhoneWrapper pw = new PhoneWrapper();
                    pw.country_code = payerAcc.BillingCountryCode;
                    pw.standard = 'X';
                    pw.telephone = payerAcc.Phone;
                    comm.phone.add(pw);
                }
                payerDet.communcation_data = comm;

                // Company Data
                payerDet.company_data = new List<CompanyDataWrapper>();
                if(payerAcc.company_code__c != null) {
                    CompanyDataWrapper cdw = new CompanyDataWrapper();
                    cdw.data = new CompanyCodeWrapper();
                    cdw.data.company_code = payerAcc.company_code__c;
                    payerDet.company_data.add(cdw);
                }

                // Payment Cards
                payerDet.payment_cards = new List<PaymentCardWrapper>();
                if(cardsMap.containsKey(payerAcc.Id)) {
                    for(Payment_Method__c c : cardsMap.get(payerAcc.Id)) {
                        PaymentCardWrapper pcw = new PaymentCardWrapper();
                        pcw.payment_card_type = c.Card_Type__c;
                        pcw.payment_card_token = c.Card_Token__c;
                        pcw.payment_card_name = c.Cardholder_Name__c;
                        pcw.last_four = c.Last_Four__c;
                        pcw.default_x = c.Is_Default__c ? 'X' : '';
                        
                        if (c.Valid_From__c != null) {
                            Datetime dtFrom = Datetime.newInstance(c.Valid_From__c.year(), c.Valid_From__c.month(), c.Valid_From__c.day());
                            pcw.valid_from = dtFrom.format('MM-dd-yyyy');
                        }
                        if (c.Valid_To__c != null) {
                            Datetime dtTo = Datetime.newInstance(c.Valid_To__c.year(), c.Valid_To__c.month(), c.Valid_To__c.day());
                            pcw.valid_to = dtTo.format('MM-dd-yyyy');
                        }
                        payerDet.payment_cards.add(pcw);
                    }
                }

                // Sold-To List
                payerDet.soldto_list = new List<SoldToWrapper>();
                Boolean useAllSoldTos = (primaryAccountType == 'Payer' || (String.isBlank(primaryAccountType) && isPayer));
                if (useAllSoldTos) {
                    if (childSoldTos.containsKey(payerAcc.Id)) {
                        for (Account st : childSoldTos.get(payerAcc.Id)) {
                            payerDet.soldto_list.add(buildSoldToWrapper(st, payerAcc));
                        }
                    }
                } else {
                    for (Account acc : allDirectAccounts.values()) {
                        if (acc.Type != null && acc.Type.equalsIgnoreCase('Sold-To')) {
                            Boolean linkedToThisPayer = false;
                            if (acc.Id == payerAcc.Id) {
                                linkedToThisPayer = true;
                            } else if (soldToToPayers.containsKey(acc.Id) && soldToToPayers.get(acc.Id).contains(payerAcc.Id)) {
                                linkedToThisPayer = true;
                            }
                            if (linkedToThisPayer) {
                                payerDet.soldto_list.add(buildSoldToWrapper(acc, payerAcc));
                            }
                        }
                    }
                }

                // Auto Pay Status
                payerDet.auto_pay_status = new List<AutoPayStatusWrapper>();
                if(autoPayMap.containsKey(payerAcc.Id)) {
                    for(Auto_Pay_Enrollment__c ap : autoPayMap.get(payerAcc.Id)) {
                        AutoPayStatusWrapper apw = new AutoPayStatusWrapper();
                        apw.company_code = ap.Company_Code__c;
                        apw.payment_method = ap.Payment_Type__c;
                        apw.enrolled = ap.Is_Enrolled__c;
                        apw.payment_card_token = ap.Payment_Method__r.Card_Token__c;
                        payerDet.auto_pay_status.add(apw);
                    }
                }

                dataNode.payer_det = payerDet;
                dataList.add(dataNode);
            }
        }

            responseObj.data = dataList;

            StatusWrapper stat = new StatusWrapper();
            stat.message_type = 'S';
            stat.message_identification = '/CNBS/X_API';
            stat.message_number = 10;
            stat.message_line_string = 'Request successfully processed';
            responseObj.status = stat;

        } catch (Exception e) {
            responseObj = new ResponseWrapper();
            StatusWrapper stat = new StatusWrapper();
            stat.message_type = 'E';
            stat.message_identification = '/CNBS/X_API';
            stat.message_number = 500;
            stat.message_line_string = e.getMessage();
            responseObj.status = stat;
        }
        
        if (res != null) {
            res.addHeader('Content-Type', 'application/json');
            String jsonString = JSON.serialize(responseObj).replace('\"default_x\":', '\"default\":');
            res.responseBody = Blob.valueOf(jsonString);
        }
    }

    private static SoldToWrapper buildSoldToWrapper(Account child, Account payer) {
        SoldToWrapper stw = new SoldToWrapper();
        stw.customer_number = child.AccountNumber;
        
        stw.sales_area_data = new SalesAreaDataWrapper();
        stw.sales_area_data.sales_organization = child.sales_organization__c != null ? child.sales_organization__c : payer.sales_organization__c;
        stw.sales_area_data.distribution_channel = child.distribution_channel__c != null ? child.distribution_channel__c : payer.distribution_channel__c;
        stw.sales_area_data.division = child.division__c != null ? child.division__c : payer.division__c;

        stw.address_data = new AddressDataWrapper();
        stw.address_data.name = child.Name;
        stw.address_data.city = child.BillingCity;
        stw.address_data.street = child.BillingStreet;
        stw.address_data.postal_code_city = child.BillingPostalCode;
        stw.address_data.region = child.BillingStateCode;
        stw.address_data.country = child.BillingCountryCode;
        stw.address_data.district = child.District__c;
        return stw;
    }
}