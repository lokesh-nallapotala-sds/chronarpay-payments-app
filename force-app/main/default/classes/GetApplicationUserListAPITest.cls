@IsTest
private class GetApplicationUserListAPITest {

    @IsTest
    static void testGetApplicationUsers() {
        // Find standard user or create one
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        // Use unique username to avoid conflicts
        String orgId = UserInfo.getOrganizationId();
        String dateString = String.valueOf(Datetime.now().getTime());
        String uniqueName = 'userlistapi' + orgId + dateString + '@test.com';
        
        User testUser = new User(
            Username = uniqueName,
            LastName = 'Demo',
            FirstName = 'Christian',
            Email = 'demo@demo.com',
            Alias = 'admdm',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US',
            CompanyName = 'CNBS-IT',
            primary_account_type__c = 'Payer'
        );
        insert testUser;

        // Create Accounts
        Account acc1 = new Account(
            Name = 'Smith Inc. LLC',
            AccountNumber = '3000',
            account_id__c = '3000'
        );
        Account acc2 = new Account(
            Name = 'North Energy Ltd',
            AccountNumber = '4000',
            account_id__c = '4000'
        );
        insert new List<Account>{ acc1, acc2 };

        // Create Junction records
        Application_User_Account__c aua1 = new Application_User_Account__c(
            User__c = testUser.Id,
            Account__c = acc1.Id,
            Is_Primary__c = true
        );
        Application_User_Account__c aua2 = new Application_User_Account__c(
            User__c = testUser.Id,
            Account__c = acc2.Id,
            Is_Primary__c = false
        );
        insert new List<Application_User_Account__c>{ aua1, aua2 };

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/getApplicationUserList';
        req.params.put('user_id', testUser.Id);
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetApplicationUserListAPI.getApplicationUsers();
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody);
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<Object> data = (List<Object>) responseMap.get('data');
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');

        System.assertEquals('S', status.get('message_type'));
        System.assertEquals(1, data.size());

        Map<String, Object> userData = (Map<String, Object>) data[0];
        System.assertEquals('CNBSMV01R', userData.get('application_id'));
        System.assertEquals(testUser.Id, userData.get('user_id'));
        System.assertEquals('Christian', userData.get('first_name'));
        System.assertEquals('Demo', userData.get('last_name'));
        System.assertEquals('Payer', userData.get('primary_account_type_id'));

        List<Object> linkedAccs = (List<Object>) userData.get('linked_accounts');
        System.assertEquals(2, linkedAccs.size());

        Set<String> primaryAccounts = new Set<String>();
        Set<String> names = new Set<String>();
        for (Object laObj : linkedAccs) {
            Map<String, Object> la = (Map<String, Object>) laObj;
            primaryAccounts.add((String) la.get('primary_account'));
            names.add((String) la.get('name'));
        }
        System.assert(primaryAccounts.contains('3000'), 'Should contain account 3000');
        System.assert(primaryAccounts.contains('4000'), 'Should contain account 4000');
        System.assert(names.contains('Smith Inc. LLC'), 'Should contain Smith Inc. LLC');
        System.assert(names.contains('North Energy Ltd'), 'Should contain North Energy Ltd');
    }
}