@IsTest
private class GetUserAccountsAPITest {

    @IsTest
    static void testGetAccountsPayer() {
        // Query System Administrator Profile
        Profile p = [SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1];
        
        // Create test user
        User u = new User(
            Alias = 'testusr',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'testuser_apipoc@example.com',
            CompanyName = 'Test Company'
        );
        insert u;

        // Create Parent Account
        Account parentAcc = new Account(
            Name = 'Parent Account LLC',
            account_id__c = '9508',
            AccountNumber = '9508'
        );
        insert parentAcc;

        // Create Directly Associated Account (Child of parentAcc)
        Account associatedAcc = new Account(
            Name = 'Directly Associated Account',
            account_id__c = '4000',
            AccountNumber = '4000',
            Type = 'Payer',
            ParentId = parentAcc.Id
        );
        insert associatedAcc;

        // Create Child Account of associatedAcc
        Account childAcc = new Account(
            Name = 'Child Account LLC',
            account_id__c = '3000',
            AccountNumber = '4000',
            Type = 'Sold-To',
            ParentId = associatedAcc.Id
        );
        insert childAcc;

        // Create Junction Record linking User and associatedAcc
        Application_User_Account__c aua = new Application_User_Account__c(
            User__c = u.Id,
            Account__c = associatedAcc.Id,
            Is_Primary__c = true
        );
        insert aua;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/getUserAccounts/' + u.Id;
        req.httpMethod = 'GET';

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetUserAccountsAPI.getAccounts();
        Test.stopTest();

        Assert.areEqual(200, res.statusCode, 'Expected HTTP 200 OK');
        String responseBodyStr = res.responseBody.toString();
        Assert.isNotNull(responseBodyStr, 'Response body should not be null');

        // Deserialize response
        GetUserAccountsAPI.UserResponse response = 
            (GetUserAccountsAPI.UserResponse) JSON.deserialize(responseBodyStr, GetUserAccountsAPI.UserResponse.class);

        Assert.areEqual(u.Id, response.userId);
        Assert.areEqual('Payer', response.primaryAccountType);
        Assert.areEqual('admin', response.role);
        Assert.areEqual('active', response.status);
        Assert.areEqual('nu', response.regionalFormat);
        
        // Should contain all three accounts (Parent, Direct, Child) because type is Payer
        Assert.areEqual(3, response.linkedAccounts.size(), 'Expected 3 linked accounts');
    }

    @IsTest
    static void testGetAccountsNonPayer() {
        // Query Standard User Profile or system administrator
        Profile p = [SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1];
        
        User u = new User(
            Alias = 'testusr2',
            Email = 'testuser2@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing2',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'testuser2_apipoc@example.com',
            CompanyName = 'Test Company 2'
        );
        insert u;

        // Create Parent Account
        Account parentAcc = new Account(
            Name = 'Parent Account LLC',
            account_id__c = '9508',
            AccountNumber = '9508'
        );
        insert parentAcc;

        // Create Associated Account (Sold-To, not Payer)
        Account associatedAcc = new Account(
            Name = 'Directly Associated Account',
            account_id__c = '4000',
            AccountNumber = '4000',
            Type = 'Sold-To',
            ParentId = parentAcc.Id
        );
        insert associatedAcc;

        // Create Junction Record linking User and associatedAcc
        Application_User_Account__c aua = new Application_User_Account__c(
            User__c = u.Id,
            Account__c = associatedAcc.Id,
            Is_Primary__c = true
        );
        insert aua;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/getUserAccounts';
        req.params.put('userId', u.Id);
        req.httpMethod = 'GET';

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetUserAccountsAPI.getAccounts();
        Test.stopTest();

        Assert.areEqual(200, res.statusCode);
        String responseBodyStr = res.responseBody.toString();
        GetUserAccountsAPI.UserResponse response = 
            (GetUserAccountsAPI.UserResponse) JSON.deserialize(responseBodyStr, GetUserAccountsAPI.UserResponse.class);

        // Since it's Sold-To (not Payer), parents/children should not be expanded, so only 1 account
        Assert.areEqual(1, response.linkedAccounts.size(), 'Expected only 1 linked account');
        Assert.areEqual('Directly Associated Account', response.linkedAccounts[0].name);
    }

    @IsTest
    static void testUserNotFound() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        // Use a valid format ID but dummy one that doesn't exist
        String dummyId = '005000000000000AAA';
        req.requestURI = '/services/apexrest/getUserAccounts/' + dummyId;
        req.httpMethod = 'GET';

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetUserAccountsAPI.getAccounts();
        Test.stopTest();

        Assert.areEqual(404, res.statusCode);
    }

    @IsTest
    static void testInvalidUserId() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/getUserAccounts/invalidid';
        req.httpMethod = 'GET';

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetUserAccountsAPI.getAccounts();
        Test.stopTest();

        Assert.areEqual(400, res.statusCode);
    }

    @IsTest
    static void testMissingUserId() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/getUserAccounts/';
        req.httpMethod = 'GET';

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetUserAccountsAPI.getAccounts();
        Test.stopTest();

        Assert.areEqual(400, res.statusCode);
    }
}