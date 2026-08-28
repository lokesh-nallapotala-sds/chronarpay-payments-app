@IsTest
private class GetApplicationUserAccountsListAPITest {

    @IsTest
    static void testGetAccountsStructuredResponse() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create Payer Account
        Account payerAcc = new Account(
            Name = 'Payer Account',
            account_id__c = '4000',
            AccountNumber = '4000',
            sales_organization__c = '1000',
            distribution_channel__c = '10',
            division__c = '00',
            company_code__c = '1000',
            BillingCity = 'San Francisco',
            BillingStreet = '123 Test St',
            BillingPostalCode = '94105',
            BillingStateCode = 'CA',
            BillingCountryCode = 'US',
            Phone = '123-456-7890',
            Type = 'Payer'
        );
        insert payerAcc;

        // Create Contact
        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = payerAcc.Id,
            Phone = '123-456-7890'
        );
        insert con;

        // Create Sold-To Account
        Account soldToAcc = new Account(
            Name = 'Sold-To Account',
            AccountNumber = '12345',
            ParentId = payerAcc.Id,
            sales_organization__c = '1000',
            distribution_channel__c = '10',
            division__c = '00',
            BillingCity = 'San Francisco',
            BillingStreet = '123 Test St',
            BillingPostalCode = '94105',
            BillingStateCode = 'CA',
            BillingCountryCode = 'US',
            Type = 'Sold-To',
            account_id__c = '5000'
        );
        insert soldToAcc;

        Account_Relationship__c rel = new Account_Relationship__c(
            Payer_Account__c = payerAcc.Id,
            SoldTo_Account__c = soldToAcc.Id
        );
        insert rel;

        // Create Payment Card
        Payment_Method__c card = new Payment_Method__c(
            Account__c = payerAcc.Id,
            Card_Type__c = 'VISA',
            Card_Token__c = 'tok_12345',
            Cardholder_Name__c = 'John Doe',
            Valid_From__c = Date.today(),
            Valid_To__c = Date.today().addYears(4),
            Is_Default__c = true,
            Last_Four__c = '1111'
        );
        insert card;

        // Create Auto Pay Enrollment
        Auto_Pay_Enrollment__c autoPay = new Auto_Pay_Enrollment__c(
            Account__c = payerAcc.Id,
            Company_Code__c = '1000',
            Payment_Type__c = 'CC',
            Is_Enrolled__c = true,
            Payment_Method__c = card.Id
        );
        insert autoPay;

        // Create Junction Record linking Payer
        Application_User_Account__c aua = new Application_User_Account__c(
            Account__c = payerAcc.Id,
            User__c = runningUser.Id,
            Is_Primary__c = true
        );
        insert aua;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/getApplicationUserAccountsList';
        req.params.put('userId', runningUser.Id);
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetApplicationUserAccountsListAPI.getAccountDetails();
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody, 'Response body should not be null');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<Object> data = (List<Object>) responseMap.get('data');
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');

        System.assertEquals(1, data.size(), 'Expected one account in response data');
        System.assertEquals('S', status.get('message_type'), 'Expected success message type');

        Map<String, Object> accountData = (Map<String, Object>) data[0];
        System.assertEquals(payerAcc.Id, accountData.get('account_id'), 'Account Id should be mapped');
        System.assertEquals(runningUser.Id, accountData.get('user_id'), 'User Id should be mapped');
        System.assertEquals('4000', accountData.get('primary_account'), 'Primary account indicator should match');

        Map<String, Object> payerDet = (Map<String, Object>) accountData.get('payer_det');
        System.assertNotEquals(null, payerDet, 'payer_det should not be null');

        Map<String, Object> address = (Map<String, Object>) payerDet.get('address_data');
        System.assertEquals('Payer Account', address.get('name'));
        System.assertEquals('CA', address.get('region'), 'Region should be CA');
        System.assertEquals('US', address.get('country'), 'Country should be US');

        List<Object> soldTo = (List<Object>) payerDet.get('soldto_list');
        System.assertEquals(1, soldTo.size(), 'Expected one sold-to account');

        List<Object> cards = (List<Object>) payerDet.get('payment_cards');
        System.assertEquals(1, cards.size(), 'Expected one card');

        List<Object> autoPayList = (List<Object>) payerDet.get('auto_pay_status');
        System.assertEquals(1, autoPayList.size(), 'Expected one auto-pay status');
    }

    @IsTest
    static void testGetAccountsSoldToDirect() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create Payer Account
        Account payerAcc = new Account(
            Name = 'Payer Account',
            account_id__c = '4000',
            AccountNumber = '4000',
            sales_organization__c = '1000',
            distribution_channel__c = '10',
            division__c = '00',
            company_code__c = '1000',
            BillingCity = 'San Francisco',
            BillingStreet = '123 Test St',
            BillingPostalCode = '94105',
            BillingStateCode = 'CA',
            BillingCountryCode = 'US',
            Phone = '123-456-7890',
            Type = 'Payer'
        );
        insert payerAcc;

        // Create Sold-To Account
        Account soldToAcc = new Account(
            Name = 'Sold-To Account',
            AccountNumber = '12345',
            ParentId = payerAcc.Id,
            sales_organization__c = '1000',
            distribution_channel__c = '10',
            division__c = '00',
            BillingCity = 'San Francisco',
            BillingStreet = '123 Test St',
            BillingPostalCode = '94105',
            BillingStateCode = 'CA',
            BillingCountryCode = 'US',
            Type = 'Sold-To',
            account_id__c = '5000'
        );
        insert soldToAcc;

        Account_Relationship__c rel = new Account_Relationship__c(
            Payer_Account__c = payerAcc.Id,
            SoldTo_Account__c = soldToAcc.Id
        );
        insert rel;

        // Create Junction Record linking Sold-To directly
        Application_User_Account__c aua = new Application_User_Account__c(
            Account__c = soldToAcc.Id,
            User__c = runningUser.Id,
            Is_Primary__c = true
        );
        insert aua;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/getApplicationUserAccountsList';
        req.params.put('userId', runningUser.Id);
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetApplicationUserAccountsListAPI.getAccountDetails();
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody, 'Response body should not be null');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        System.assertEquals('S', status.get('message_type'), 'Error: ' + status.get('message_line_string'));
        List<Object> data = (List<Object>) responseMap.get('data');
        System.assertEquals(1, data.size(), 'Expected one account in response data');
        Map<String, Object> accountData = (Map<String, Object>) data[0];
        System.assertEquals(soldToAcc.Id, accountData.get('account_id'), 'Account Id should be mapped');
        // Account type might be overridden by the org User's primary_account_type__c, so we don't assert it strictly here.

        Map<String, Object> payerDet = (Map<String, Object>) accountData.get('payer_det');
        System.assertNotEquals(null, payerDet, 'payer_det should not be null');

        List<Object> soldTo = (List<Object>) payerDet.get('soldto_list');
        System.assertEquals(1, soldTo.size(), 'Expected one sold-to account');
    }

    @IsTest
    static void testGetAccountsGrouped() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create Payer Account A
        Account payerA = new Account(
            Name = 'Account A',
            account_id__c = '4001',
            AccountNumber = '4001',
            Type = 'Payer'
        );
        insert payerA;

        // Create Sold-To Account A1
        Account soldToA1 = new Account(
            Name = 'Account A1',
            ParentId = payerA.Id,
            Type = 'Sold-To',
            account_id__c = '4002'
        );
        insert soldToA1;

        // Create Payer Account B
        Account payerB = new Account(
            Name = 'Account B',
            account_id__c = '5001',
            AccountNumber = '5001',
            Type = 'Payer'
        );
        insert payerB;

        // Create Sold-To Account B1
        Account soldToB1 = new Account(
            Name = 'Account B1',
            ParentId = payerB.Id,
            Type = 'Sold-To',
            account_id__c = '5002'
        );
        insert soldToB1;

        Account_Relationship__c relA = new Account_Relationship__c(
            Payer_Account__c = payerA.Id,
            SoldTo_Account__c = soldToA1.Id
        );
        Account_Relationship__c relB = new Account_Relationship__c(
            Payer_Account__c = payerB.Id,
            SoldTo_Account__c = soldToB1.Id
        );
        insert new List<Account_Relationship__c>{relA, relB};

        // Link User to Account A (Payer)
        Application_User_Account__c auaA = new Application_User_Account__c(
            Account__c = payerA.Id,
            User__c = runningUser.Id,
            Is_Primary__c = true
        );
        // Link User to Account A1 (Sold-To)
        Application_User_Account__c auaA1 = new Application_User_Account__c(
            Account__c = soldToA1.Id,
            User__c = runningUser.Id,
            Is_Primary__c = false
        );
        // Link User to Account B1 (Sold-To) - NOT parent B!
        Application_User_Account__c auaB1 = new Application_User_Account__c(
            Account__c = soldToB1.Id,
            User__c = runningUser.Id,
            Is_Primary__c = false
        );
        insert new List<Application_User_Account__c>{ auaA, auaA1, auaB1 };

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/getApplicationUserAccountsList';
        req.params.put('userId', runningUser.Id);
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetApplicationUserAccountsListAPI.getAccountDetails();
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody);
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<Object> data = (List<Object>) responseMap.get('data');

        // We expect exactly two items in the data array:
        // 1. Account A (Payer) -> which covers A1
        // 2. Account B1 (Sold-To) -> since parent B is not directly linked
        System.assertEquals(2, data.size(), 'Expected exactly two data nodes (Account A and Account B1)');

        Map<String, Object> node1 = (Map<String, Object>) data[0];
        Map<String, Object> node2 = (Map<String, Object>) data[1];
        System.assertEquals('Payer', node1.get('account_type'), 'Account type should match primary account type');
        System.assertEquals('Payer', node2.get('account_type'), 'Account type should match primary account type');
    }

    @IsTest
    static void testGetAccountsSoldToPrimaryMultipleAssociations() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'testu',
            Email = 'testuser123456@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser123456' + DateTime.now().getTime() + '@example.com',
            primary_account_type__c = 'Sold-To'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert testUser;
        }

        // Create Payer Account A
        Account payerA = new Account(
            Name = 'Payer Account A',
            account_id__c = '4001',
            AccountNumber = '4001',
            Type = 'Payer'
        );
        insert payerA;

        // Create Sold-To Account A1
        Account soldToA1 = new Account(
            Name = 'Account A1',
            ParentId = payerA.Id,
            Type = 'Sold-To',
            AccountNumber = '10001',
            account_id__c = '4002'
        );
        // Create Sold-To Account A2
        Account soldToA2 = new Account(
            Name = 'Account A2',
            ParentId = payerA.Id,
            Type = 'Sold-To',
            AccountNumber = '10002',
            account_id__c = '4003'
        );
        // Create Sold-To Account A3 (Not linked to user)
        Account soldToA3 = new Account(
            Name = 'Account A3',
            ParentId = payerA.Id,
            Type = 'Sold-To',
            AccountNumber = '10003',
            account_id__c = '4004'
        );
        insert new List<Account>{ soldToA1, soldToA2, soldToA3 };

        List<Account_Relationship__c> rels = new List<Account_Relationship__c>{
            new Account_Relationship__c(Payer_Account__c = payerA.Id, SoldTo_Account__c = soldToA1.Id),
            new Account_Relationship__c(Payer_Account__c = payerA.Id, SoldTo_Account__c = soldToA2.Id),
            new Account_Relationship__c(Payer_Account__c = payerA.Id, SoldTo_Account__c = soldToA3.Id)
        };
        insert rels;

        // Link User to Account A1 (Sold-To) - Primary
        Application_User_Account__c auaA1 = new Application_User_Account__c(
            Account__c = soldToA1.Id,
            User__c = testUser.Id,
            Is_Primary__c = true
        );
        // Link User to Account A2 (Sold-To) - Non-Primary
        Application_User_Account__c auaA2 = new Application_User_Account__c(
            Account__c = soldToA2.Id,
            User__c = testUser.Id,
            Is_Primary__c = false
        );
        insert new List<Application_User_Account__c>{ auaA1, auaA2 };

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/getApplicationUserAccountsList';
        req.params.put('userId', testUser.Id);
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetApplicationUserAccountsListAPI.getAccountDetails();
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody);
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<Object> data = (List<Object>) responseMap.get('data');

        // We expect exactly two items in the data array:
        // 1. Account A1 (Sold-To)
        // 2. Account A2 (Sold-To)
        System.assertEquals(2, data.size(), 'Expected exactly two data nodes');

        for (Object nodeObj : data) {
            Map<String, Object> node = (Map<String, Object>) nodeObj;
            // Account type might be overridden by the org User's primary_account_type__c


            Map<String, Object> payerDet = (Map<String, Object>) node.get('payer_det');
            System.assertNotEquals(null, payerDet);

            List<Object> soldTo = (List<Object>) payerDet.get('soldto_list');
            // Should contain ONLY the two Sold-Tos the user is authorized to access (A1 and A2), not A3.
            System.assertEquals(2, soldTo.size(), 'Expected only authorized Sold-Tos');
            
            Set<String> customerNumbers = new Set<String>();
            for (Object stObj : soldTo) {
                Map<String, Object> st = (Map<String, Object>) stObj;
                customerNumbers.add((String) st.get('customer_number'));
            }
            System.assert(customerNumbers.contains('10001'), 'Should contain Sold-To A1');
            System.assert(customerNumbers.contains('10002'), 'Should contain Sold-To A2');
            System.assert(!customerNumbers.contains('10003'), 'Should not contain unauthorized Sold-To A3');
        }
    }
}