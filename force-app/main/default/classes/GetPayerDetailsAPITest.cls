@IsTest
private class GetPayerDetailsAPITest {

    @IsTest
    static void testGetPayerDetailsReturnsContractShape() {
        Account payerAcc = new Account(
            Name = 'Payer Account',
            AccountNumber = '4000',
            account_id__c = '4000',
            sales_organization__c = '1000',
            distribution_channel__c = '10',
            division__c = '00',
            company_code__c = '1000',
            BillingCity = 'San Francisco',
            BillingStreet = '123 Test St',
            BillingPostalCode = '94105',
            BillingStateCode = 'CA',
            BillingCountryCode = 'US',
            District__c = 'COOK',
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
            AccountId = payerAcc.Id,
            Phone = '(312)450-BUSH',
            Email = 'demo@cnbssoftware.com'
        );

        insert new Payment_Method__c(
            Account__c = payerAcc.Id,
            Card_Type__c = 'VISA',
            Card_Token__c = 'tok_12345',
            Cardholder_Name__c = 'John Doe',
            Valid_From__c = Date.today(),
            Valid_To__c = Date.today().addYears(4),
            Is_Default__c = true,
            Last_Four__c = '1111'
        );

        insert new Auto_Pay_Enrollment__c(
            Account__c = payerAcc.Id,
            Company_Code__c = '1000',
            Payment_Type__c = 'CC',
            Is_Enrolled__c = true
        );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/getPayerDetails';
        req.params.put('customer_number', '4000');
        req.params.put('company_code', '1000');
        req.params.put('payer_det_action', '01');
        req.params.put('sales_organization', '1000');
        req.params.put('distribution_channel', '10');
        req.params.put('division', '00');
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetPayerDetailsAPI.getPayerDetails();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'Expected HTTP 200');
        System.assertNotEquals(null, res.responseBody, 'Expected response body');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> detail = (Map<String, Object>) responseMap.get('detail');
        Map<String, Object> status = (Map<String, Object>) responseMap.get('status');
        Map<String, Object> addressData = (Map<String, Object>) detail.get('address_data');
        Map<String, Object> communicationData = (Map<String, Object>) detail.get('communication_data');
        List<Object> companyData = (List<Object>) detail.get('company_data');
        List<Object> paymentCards = (List<Object>) detail.get('payment_cards');
        List<Object> soldToList = (List<Object>) detail.get('soldto_list');
        List<Object> autoPayStatus = (List<Object>) detail.get('auto_pay_status');

        System.assertEquals('S', status.get('message_type'), 'Expected success message type');
        System.assertEquals('Payer Account', addressData.get('name'), 'Expected payer name');
        System.assertEquals('COOK', addressData.get('district'), 'Expected district to map from Account');
        System.assertEquals(1, companyData.size(), 'Expected company data');
        System.assertEquals(1, paymentCards.size(), 'Expected one payment card');
        System.assertEquals(1, soldToList.size(), 'Expected one sold-to relation');
        System.assertEquals(1, autoPayStatus.size(), 'Expected one auto-pay status entry');
    }
}