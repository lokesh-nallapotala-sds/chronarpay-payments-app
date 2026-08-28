@IsTest
private class ApplicationUserDetailAPITest {

    @IsTest
    static void testGetApplicationUserDetailReturnsSingleRecord() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueName = 'appuserdetailget' + String.valueOf(Datetime.now().getTime()) + '@test.com';

        User testUser = new User(
            Username = uniqueName,
            LastName = 'Detail',
            FirstName = 'Get',
            Email = 'getdetail@test.com',
            Alias = 'gdtl',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US',
            CompanyName = 'CNBS'
        );
        insert testUser;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/applicationUserDetail';
        req.params.put('user_id', testUser.Id);
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ApplicationUserDetailAPI.getApplicationUser();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<Object> dataList = (List<Object>) responseMap.get('data');
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        System.assertEquals(1, dataList.size());
        System.assertEquals('S', status.get('message_type'));

        Map<String, Object> detail = (Map<String, Object>) dataList[0];
        System.assertEquals(testUser.Id, detail.get('user_id'));
        System.assertEquals('Get', detail.get('first_name'));
        System.assertEquals('Detail', detail.get('last_name'));
        System.assertEquals('CNBSMV01R', detail.get('application_id'));
    }

    @IsTest
    static void testPostCreateApplicationUser() {
        String uniqueName = 'appuserdetailcreate' + String.valueOf(Datetime.now().getTime()) + '@test.com';
        String requestBody = '{"action":"create","data":{"user_id":"","login":"' + uniqueName + '","first_name":"Postman","last_name":"User","company":"CNBS","email":"postman@test.com","status":"active","primary_account_type_id":"Payer","user_role":"User"}}';

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/applicationUserDetail';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ApplicationUserDetailAPI.processRequest();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<Object> dataList = (List<Object>) responseMap.get('data');
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        System.assertEquals('S', status.get('message_type'));
        System.assertEquals(1, dataList.size());

        Map<String, Object> detail = (Map<String, Object>) dataList[0];
        System.assert(String.isNotBlank((String) detail.get('user_id')));
        System.assertEquals('Postman', detail.get('first_name'));
        System.assertEquals('User', detail.get('last_name'));
    }
}