@IsTest
private class CustomizingAPITest {
    @IsTest
    static void shouldReturnCustomizingPayloadWithExpectedTopLevelKeys() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/customizing';
        req.httpMethod = 'GET';
        req.params.put('sap-client', '800');
        req.params.put('sap-language', 'EN');
        req.params.put('apiid', 'CNBSMV01R');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        CustomizingAPI.getCustomizingData();
        Test.stopTest();

        System.assertEquals(200, res.statusCode, 'The API should return HTTP 200.');
        System.assertNotEquals(null, res.responseBody, 'The response body should be populated.');

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals('CNBSMV01R', payload.get('application_id'), 'The application id should match the request.');
        System.assertEquals('D', payload.get('sap_system_type'), 'The SAP system type should be present.');
        System.assertNotEquals(null, payload.get('general_data'), 'The general data payload should be present.');
        System.assertNotEquals(null, payload.get('company_codes'), 'The company codes collection should be present.');
        System.assertNotEquals(null, payload.get('sales_area_data'), 'The sales area collection should be present.');
        System.assertNotEquals(null, payload.get('document_types'), 'The document types collection should be present.');
        System.assertNotEquals(null, payload.get('document_status'), 'The document status collection should be present.');
        System.assertNotEquals(null, payload.get('payment_types'), 'The payment types collection should be present.');
        System.assertNotEquals(null, payload.get('payment_methodes'), 'The payment methods collection should be present.');
        System.assertNotEquals(null, payload.get('payment_provider'), 'The payment provider collection should be present.');
        System.assertNotEquals(null, payload.get('payment_reason_codes'), 'The payment reason codes collection should be present.');
        System.assertNotEquals(null, payload.get('payment_cards'), 'The payment cards collection should be present.');
        System.assertNotEquals(null, payload.get('function_modules'), 'The function modules collection should be present.');
        System.assertNotEquals(null, payload.get('parameters'), 'The parameters collection should be present.');
        System.assertNotEquals(null, payload.get('logging_events'), 'The logging events collection should be present.');
        System.assertNotEquals(null, payload.get('sapcust'), 'The SAP customizing node should be present.');
        System.assertNotEquals(null, payload.get('release_information'), 'The release information node should be present.');
        System.assertNotEquals(null, payload.get('status'), 'The status node should be present.');
    }
}