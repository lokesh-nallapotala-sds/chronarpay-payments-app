@IsTest
private class paymentServiesTest {

    @IsTest
    static void testProcessPaymentSuccess() {
        // Set up RestContext mock request and response
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/SAPPayment/';
        req.httpMethod = 'POST';
        
        // Define the JSON payload matching the user request
        String jsonPayload = '{"selectedAccount":"3000","payer":"3000","invoices":[{"documentNumberFinance":"1400000022","lineItemInTheRelevantInvoice":1,"fiscalYearOfTheRelevantInvoice":2026,"openAmount":9199.89,"paymentAmount":10,"currencyKey":"EUR","reason":"PP","description":"","referenceNumber":"0090041013","billingDocumentNumber":"0090041013","documentDate":"2026-04-10T00:00:00","soldtoNumber":"0000003000","payerNumber":"3000"}],"cardinalData":{"secure3DSVersion":null,"enrolled":"U","eciFlag":null,"transactionId":"RdedgCYjAe5z50uYcHK3","cavv":null,"paresStatus":null},"paymentMethod":{"name":"SDS Test","dropDownDisplayName":"MC **** 8210 - SDS Test","key":"","cardType":"MC","sapCardType":"MC","gatewayCardType":"MC","default":false,"token":"v2:f6WpqzB7v2Y8hK0HZDA7tw==!d4O6LVx55jK9aqq4Ea2+qWCSGLbmrMWkgLTnqyJw/lU=","validFrom":"06-01-2026","validTo":"10-31-2034","isSession":false,"cardLast4Digit":"8210"},"vRef":"v2:NWdSGArqcAxcjfzc14DNhg==!daeoFAjAKKBlFh6HAMdtHQ==","companyCode":"1000"}';
        req.requestBody = Blob.valueOf(jsonPayload);
        
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        paymentServies.processPayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'REST response status code should be 200');
        System.assertNotEquals(null, res.responseBody, 'Response body should not be null');
        
        // Parse response body to verify transactionId is populated
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> cardinalData = (Map<String, Object>) responseMap.get('cardinalData');
        System.assertNotEquals(null, cardinalData, 'cardinalData block should not be null');
        
        String transactionId = (String) cardinalData.get('transactionId');
        System.assertNotEquals(null, transactionId, 'Transaction ID should be populated');
        System.assert(transactionId.startsWith('001') || transactionId.length() > 0, 'Transaction ID should be populated with Payment/Mock ID');
    }
    
    @IsTest
    static void testProcessPaymentError() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/SAPPayment/';
        req.httpMethod = 'POST';
        
        // Invalid payload to trigger error / exception
        String invalidPayload = '{"payer":""'; // malformed JSON
        req.requestBody = Blob.valueOf(invalidPayload);
        
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        paymentServies.processPayment();
        Test.stopTest();
        
        System.assertEquals(400, res.statusCode, 'Error status code should be 400');
        System.assertNotEquals(null, res.responseBody, 'Error response body should not be null');
    }

    @IsTest
    static void testProcessPaymentAlternativeFlow() {
        RestRequest req = new RestRequest();
        
        req.requestURI = '/services/apexrest/SAPPayment/';
        req.httpMethod = 'POST';
        
        // Define payload with missing payer, missing cardinalData, and a different validTo format (or missing)
        String jsonPayload = '{"selectedAccount":"3000","invoices":[{"documentNumberFinance":"1400000022","lineItemInTheRelevantInvoice":1,"fiscalYearOfTheRelevantInvoice":2026,"openAmount":9199.89,"paymentAmount":10,"currencyKey":"EUR","reason":"PP","description":"","referenceNumber":"0090041013","billingDocumentNumber":"0090041013","documentDate":"2026-04-10T00:00:00","soldtoNumber":"0000003000","payerNumber":"3000"}],"paymentMethod":{"name":"SDS Test","dropDownDisplayName":"MC **** 8210 - SDS Test","key":"","cardType":"MC","sapCardType":"MC","gatewayCardType":"MC","default":false,"token":"v2:f6WpqzB7v2Y8hK0HZDA7tw==!d4O6LVx55jK9aqq4Ea2+qWCSGLbmrMWkgLTnqyJw/lU=","validFrom":"06-01-2026","validTo":"10-34","isSession":false,"cardLast4Digit":"8210"},"vRef":"v2:NWdSGArqcAxcjfzc14DNhg==!daeoFAjAKKBlFh6HAMdtHQ==","companyCode":"1000"}';
        req.requestBody = Blob.valueOf(jsonPayload);
        
        RestContext.request = req;
        RestContext.response = null; // Set to null to test the null-check instantiation
        
        Test.startTest();
        paymentServies.processPayment();
        Test.stopTest();
        
        RestResponse res = RestContext.response;
        System.assertNotEquals(null, res, 'Response should have been instantiated');
        System.assertEquals(200, res.statusCode, 'REST response status code should be 200');
        
        // Parse response body to verify transactionId is populated in a new cardinalData block
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Map<String, Object> cardinalData = (Map<String, Object>) responseMap.get('cardinalData');
        System.assertNotEquals(null, cardinalData, 'cardinalData block should have been initialized');
        
        String transactionId = (String) cardinalData.get('transactionId');
        System.assertNotEquals(null, transactionId, 'Transaction ID should be populated');
    }

    @IsTest
    static void testProcessPaymentExistingAccountAndBlankDoc() {
        // Pre-create the account to cover line 177: accId = accs[0].Id;
        Account acc = new Account(Name = 'SAP Payer 3000');
        insert acc;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/SAPPayment/';
        req.httpMethod = 'POST';
        
        // Define payload with missing payer (so it falls back to 'SAP Payer ' + selectedAccount)
        // and blank/missing billingDocumentNumber (to cover line 108: return;)
        String jsonPayload = '{"selectedAccount":"3000","invoices":[{"documentNumberFinance":"1400000022","lineItemInTheRelevantInvoice":1,"fiscalYearOfTheRelevantInvoice":2026,"openAmount":9199.89,"paymentAmount":10,"currencyKey":"EUR","reason":"PP","description":"","referenceNumber":"0090041013","billingDocumentNumber":"","documentDate":"2026-04-10T00:00:00","soldtoNumber":"0000003000","payerNumber":"3000"}],"paymentMethod":{"name":"SDS Test","dropDownDisplayName":"MC **** 8210 - SDS Test","key":"","cardType":"MC","sapCardType":"MC","gatewayCardType":"MC","default":false,"token":"v2:f6WpqzB7v2Y8hK0HZDA7tw==!d4O6LVx55jK9aqq4Ea2+qWCSGLbmrMWkgLTnqyJw/lU=","validFrom":"06-01-2026","validTo":"","isSession":false,"cardLast4Digit":"8210"},"vRef":"v2:NWdSGArqcAxcjfzc14DNhg==!daeoFAjAKKBlFh6HAMdtHQ==","companyCode":"1000"}';
        req.requestBody = Blob.valueOf(jsonPayload);
        
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        paymentServies.processPayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'REST response status code should be 200');
    }
}