@IsTest
private class ApplicationUserAccountDetailAPITest {

    private static Chronarpay_User__c createChronarpayUser(String accountType) {
        Chronarpay_User__c userRecord = new Chronarpay_User__c();
        userRecord.Name = 'TestUser' + String.valueOf(Crypto.getRandomLong());
        userRecord.First_Name__c = 'Test';
        userRecord.Last_Name__c = 'User';
        userRecord.Email__c = 'test' + String.valueOf(Crypto.getRandomLong()) + '@example.com';
        userRecord.Primary_Account_Type__c = accountType;
        insert userRecord;
        return userRecord;
    }

    @IsTest
    static void testCreateActionReturnsStructuredResponse() {
        Chronarpay_User__c runningUser = createChronarpayUser('PostmanType');

        Account linkedAccount = new Account(Name = 'Linked Account');
        linkedAccount.Type = 'PostmanType';
        linkedAccount.Sales_Organization__c = '3000';
        linkedAccount.distribution_channel__c = '10';
        linkedAccount.division__c = '00';
        linkedAccount.company_code__c = '1000';
        insert linkedAccount;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/applicationUserAccountDetail/' + runningUser.Id;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'action' => 'create',
            'data' => new Map<String, Object>{
                'user_id' => runningUser.Id,
                'account_type' => 'PostmanType',
                'primary_account' => 'FrontUser',
                'sales_organization' => '3000',
                'distribution_channel' => '10',
                'division' => '00',
                'company_code' => '1000',
                'allow_payments' => 'X',
                'allow_deposits' => 'X'
            }
        }));
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ApplicationUserAccountDetailAPI.processRequest();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected success status code');
        System.assertNotEquals(null, res.responseBody, 'Response body should not be null');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<Object> data = (List<Object>) responseMap.get('data');
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');

        System.assertEquals(1, data.size(), 'Expected one account in response data');
        System.assertEquals('S', status.get('message_type'), 'Expected success message type');

        Map<String, Object> accountData = (Map<String, Object>) data[0];
        System.assertEquals(runningUser.Id, accountData.get('user_id'), 'Chronarpay user Id should be mapped');
        System.assertEquals('PostmanType', accountData.get('account_type'), 'Account type should be mapped');
        System.assertEquals('FrontUser', accountData.get('primary_account'), 'Primary account should be mapped');

        List<Application_User_Account__c> createdJunctions = [
            SELECT Id, Chronarpay_User__c, Account__c
            FROM Application_User_Account__c
            WHERE Chronarpay_User__c = :runningUser.Id
            LIMIT 1
        ];
        System.assertEquals(linkedAccount.Id, accountData.get('account_id'), 'Account Id should be returned instead of the junction record Id');
        System.assertEquals(1, createdJunctions.size(), 'Expected one junction record to be created');
    }

    @IsTest
    static void testModifyActionUpdatesExistingRelationUsingAccountId() {
        Chronarpay_User__c runningUser = createChronarpayUser('PostmanType');

        Account existingAccount = new Account(Name = 'Existing Account');
        existingAccount.Type = 'PostmanType';
        existingAccount.Sales_Organization__c = '3000';
        existingAccount.distribution_channel__c = '10';
        existingAccount.division__c = '00';
        existingAccount.company_code__c = '1000';
        insert existingAccount;

        Account replacementAccount = new Account(Name = 'Replacement Account');
        replacementAccount.Type = 'PostmanType';
        replacementAccount.Sales_Organization__c = '3000';
        replacementAccount.distribution_channel__c = '10';
        replacementAccount.division__c = '00';
        replacementAccount.company_code__c = '1000';
        insert replacementAccount;

        insert new Application_User_Account__c(
            Chronarpay_User__c = runningUser.Id,
            Account__c = existingAccount.Id,
            Is_Primary__c = true
        );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/applicationUserAccountDetail/' + runningUser.Id;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'action' => 'modify',
            'data' => new Map<String, Object>{
                'user_id' => runningUser.Id,
                'account_id' => replacementAccount.Id,
                'account_type' => 'PostmanType',
                'primary_account' => 'FrontUser',
                'sales_organization' => '3000',
                'distribution_channel' => '10',
                'division' => '00',
                'company_code' => '1000'
            }
        }));
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ApplicationUserAccountDetailAPI.processRequest();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected success status code for modify');

        Application_User_Account__c refreshedJunction = [
            SELECT Account__c
            FROM Application_User_Account__c
            WHERE Chronarpay_User__c = :runningUser.Id
            LIMIT 1
        ];
        System.assertEquals(replacementAccount.Id, refreshedJunction.Account__c, 'Modify should update the junction to the supplied account id');
    }

    @IsTest
    static void testCreateActionFailsWhenRelationAlreadyExists() {
        Chronarpay_User__c runningUser = createChronarpayUser('PostmanType');

        Account linkedAccount = new Account(Name = 'Linked Account');
        linkedAccount.Type = 'PostmanType';
        linkedAccount.Sales_Organization__c = '3000';
        linkedAccount.distribution_channel__c = '10';
        linkedAccount.division__c = '00';
        linkedAccount.company_code__c = '1000';
        insert linkedAccount;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/applicationUserAccountDetail/' + runningUser.Id;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'action' => 'create',
            'data' => new Map<String, Object>{
                'user_id' => runningUser.Id,
                'account_type' => 'PostmanType',
                'primary_account' => 'FrontUser',
                'sales_organization' => '3000',
                'distribution_channel' => '10',
                'division' => '00',
                'company_code' => '1000',
                'allow_payments' => 'X',
                'allow_deposits' => 'X'
            }
        }));
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ApplicationUserAccountDetailAPI.processRequest();
        ApplicationUserAccountDetailAPI.processRequest();
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'Expected 400 status code when the user-account relation already exists');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        System.assertEquals('E', status.get('message_type'), 'Expected error message type');
        System.assertEquals('Relation already exists for the supplied user and sales area', status.get('message_line_string'), 'Expected duplicate relation message');
    }

    @IsTest
    static void testMissingUserIdReturnsError() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/applicationUserAccountDetail';
        req.httpMethod = 'POST';
        Account existingAccount = new Account(Name = 'Existing Account');
        insert existingAccount;

        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'action' => 'create',
            'data' => new Map<String, Object>{
                'account_id' => existingAccount.Id,
                'account_type' => 'PostmanType'
            }
        }));
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ApplicationUserAccountDetailAPI.processRequest();
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'Expected 400 status code when user_id is missing');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        System.assertEquals('E', status.get('message_type'), 'Expected error message type');
    }

    @IsTest
    static void testCreateActionFailsWhenAccountTypeMismatch() {
        Chronarpay_User__c runningUser = createChronarpayUser('PostmanType');

        Account linkedAccount = new Account(Name = 'Linked Account');
        linkedAccount.Type = 'OtherType';
        linkedAccount.Sales_Organization__c = '3000';
        linkedAccount.distribution_channel__c = '10';
        linkedAccount.division__c = '00';
        linkedAccount.company_code__c = '1000';
        insert linkedAccount;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/applicationUserAccountDetail/' + runningUser.Id;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'action' => 'create',
            'data' => new Map<String, Object>{
                'user_id' => runningUser.Id,
                'account_type' => 'PostmanType',
                'primary_account' => 'FrontUser',
                'sales_organization' => '3000',
                'distribution_channel' => '10',
                'division' => '00',
                'company_code' => '1000',
                'allow_payments' => 'X',
                'allow_deposits' => 'X'
            }
        }));
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ApplicationUserAccountDetailAPI.processRequest();
        Test.stopTest();

        System.assertEquals(400, res.statusCode, 'Expected 400 status code when account type does not match');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        System.assertEquals('E', status.get('message_type'), 'Expected error message type');
        System.assertEquals('No matching account found for supplied sales area and primary account type', status.get('message_line_string'), 'Expected primary account type mismatch message');
    }
}