@IsTest
private class GetSoldToDetailsAPITest {

    @IsTest
    static void testGetSoldToDetailsReturnsContractShape() {
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

        Account soldToAcc = new Account(
            Name = 'Sold-To Account',
            AccountNumber = '12345',
            ParentId = payerAcc.Id,
            sales_organization__c = '1000',
            distribution_channel__c = '10',
            division__c = '00',
            company_code__c = '1000',
            BillingCity = 'MAYWOOD',
            BillingStreet = '1 2800 South 25th Ave',
            BillingPostalCode = '60153',
            BillingStateCode = 'IL',
            BillingCountryCode = 'US',
            District__c = 'COOK',
            Type = 'Sold-To',
            account_id__c = '5000'
        );
        insert soldToAcc;

        insert new Account_Relationship__c(
            Payer_Account__c = payerAcc.Id,
            SoldTo_Account__c = soldToAcc.Id
        );

        insert new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = soldToAcc.Id,
            Phone = '(312)450-BUSH',
            Email = 'demo@cnbssoftware.com'
        );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/getSoldToDetails';
        req.params.put('customer_number', '12345');
        req.params.put('sales_organization', '1000');
        req.params.put('distribution_channel', '10');
        req.params.put('division', '00');
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetSoldToDetailsAPI.getSoldToDetails();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected HTTP 200');
        System.assertNotEquals(null, res.responseBody, 'Expected response body');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> detail = (Map<String, Object>) responseMap.get('detail');
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        Map<String, Object> addressData = (Map<String, Object>) detail.get('address_data');
        Map<String, Object> communicationData = (Map<String, Object>) detail.get('communication_data');
        List<Object> phoneList = (List<Object>) communicationData.get('phone');
        List<Object> salesData = (List<Object>) detail.get('sales_data');

        System.assertEquals('S', status.get('message_type'), 'Expected success message type');
        System.assertEquals('Sold-To Account', addressData.get('name'), 'Expected sold-to name');
        System.assertEquals('MAYWOOD', addressData.get('city'), 'Expected city to map from Account');
        System.assertEquals('COOK', addressData.get('district'), 'Expected district to map from Account');
        System.assertEquals('US', addressData.get('country'), 'Expected country to map from Account');
        System.assertEquals(1, phoneList.size(), 'Expected one phone entry');
        System.assertEquals('US', ((Map<String, Object>) phoneList[0]).get('country_code'), 'Expected country code');
        System.assertEquals('X', ((Map<String, Object>) phoneList[0]).get('standard'), 'Expected standard flag');
        System.assertEquals('(312)450-BUSH', ((Map<String, Object>) phoneList[0]).get('telephone'), 'Expected telephone to map from Contact');
        System.assertEquals(1, salesData.size(), 'Expected one sales-data block');
        Map<String, Object> salesDataNode = (Map<String, Object>) salesData[0];
        Map<String, Object> salesNodeData = (Map<String, Object>) salesDataNode.get('data');
        System.assertEquals('1000', salesNodeData.get('sales_organization'), 'Expected sales organization');
        System.assertEquals('10', salesNodeData.get('distribution_channel'), 'Expected distribution channel');
        System.assertEquals('00', salesNodeData.get('division'), 'Expected division');
        System.assertEquals('1000', salesNodeData.get('company_code'), 'Expected company code');
    }
}