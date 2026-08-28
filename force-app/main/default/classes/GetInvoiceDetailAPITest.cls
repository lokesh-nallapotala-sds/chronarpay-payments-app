@IsTest
private class GetInvoiceDetailAPITest {

    @TestSetup
    static void setupTestData() {
        // Create an Account (Payer / Customer)
        Account acc = new Account(
            Name = 'Smith Inc. LLC',
            Name_2__c = 'Test',
            AccountNumber = '0000003000',
            BillingCity = 'MAYWOOD',
            District__c = 'COOK',
            BillingStreet = '1 2800 South 25th Ave',
            BillingPostalCode = '60153',
            BillingState = 'Illinois',
            BillingCountry = 'United States'
        );
        insert acc;

        // Create an Invoice__c
        Invoice__c inv = new Invoice__c(
            Payer_Account__c = acc.Id,
            Billing_Document_Number__c = '90041011',
            Billing_Document_Type__c = 'F2',
            Sales_Organization__c = '3000',
            Distribution_Channel__c = '10',
            Division__c = '00',
            Company_Code__c = '3000',
            Currency_Key__c = 'USD',
            Document_Date__c = Date.newInstance(2026, 4, 4),
            Due_Date__c = Date.newInstance(2026, 5, 4),
            Total_Amount__c = 90.00,
            Open_Amount__c = 90.00,
            Document_Status__c = '01',
            Debit_Credit_Flag__c = 'D',
            Document_Type__c = '01'
        );
        insert inv;

        // Create an Invoice_Line_Item__c
        Invoice_Line_Item__c item = new Invoice_Line_Item__c(
            Invoice__c = inv.Id,
            Line_Number__c = 10,
            Material_Number__c = 'A10007',
            Description__c = 'Apple AirPods',
            Billed_Quantity__c = 1.000,
            Sales_Unit__c = 'ST',
            Base_Unit__c = 'EA',
            Pricing_Unit__c = 'ST',
            Currency_Key__c = 'USD',
            Total_Amount__c = 90.00,
            Open_Amount__c = 90.00,
            Paid_Amount__c = 0.00
        );
        insert item;

        // Create an Invoice_Partner__c
        Invoice_Partner__c partner = new Invoice_Partner__c(
            Invoice__c = inv.Id,
            Account__c = acc.Id,
            Partner_Function__c = 'AG'
        );
        insert partner;
    }

    @IsTest
    static void testGetInvoiceDetailSuccess() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/cnbs/v1/invoices/id';
        req.httpMethod = 'GET';
        req.params.put('billing_document_number', '90041011');
        req.params.put('document_type', '01');

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetInvoiceDetailAPI.getInvoiceDetail();
        Test.stopTest();

        Assert.areEqual(200, res.statusCode, 'Expected HTTP 200 OK');
        String responseBodyStr = res.responseBody.toString();
        Assert.isNotNull(responseBodyStr, 'Response body should not be null');

        // Deserialize response
        GetInvoiceDetailAPI.CNBSInvoiceResponse response = 
            (GetInvoiceDetailAPI.CNBSInvoiceResponse) JSON.deserialize(responseBodyStr, GetInvoiceDetailAPI.CNBSInvoiceResponse.class);

        Assert.isNotNull(response.detail, 'Detail should not be null');
        Assert.isNotNull(response.detail.header_data, 'Header data should not be null');
        Assert.areEqual('90041011', response.detail.header_data.billing_document_number);
        Assert.areEqual('F2', response.detail.header_data.billing_document_type);
        Assert.areEqual('0000003000', response.detail.header_data.soldto_number);
        Assert.areEqual('04-04-2026', response.detail.header_data.document_date);
        Assert.areEqual('05-04-2026', response.detail.header_data.due_date);
        Assert.areEqual(90.00, response.detail.header_data.total_amount);

        Assert.isNotNull(response.detail.item_data, 'Item data should not be empty');
        Assert.areEqual(1, response.detail.item_data.size());
        Assert.areEqual('A10007', response.detail.item_data[0].material_number);
        Assert.areEqual(90.00, response.detail.item_data[0].open_amount);

        Assert.isNotNull(response.detail.partner_data, 'Partner data should not be empty');
        Assert.areEqual(1, response.detail.partner_data.size());
        Assert.areEqual('AG', response.detail.partner_data[0].partner_function);
        Assert.areEqual('0000003000', response.detail.partner_data[0].partner_number);
        Assert.areEqual('Smith Inc. LLC', response.detail.partner_data[0].address_data.name);
        Assert.areEqual('Test', response.detail.partner_data[0].address_data.name_2);
        Assert.areEqual('COOK', response.detail.partner_data[0].address_data.district);

        Assert.isNotNull(response.status, 'Status should not be null');
        Assert.areEqual('S', response.status.message_type);
    }

    @IsTest
    static void testGetInvoiceDetailSuccessWithCustomerNumberFilter() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/getInvoicesDetailsAPI/id';
        req.httpMethod = 'GET';
        req.params.put('billing_document_number', '90041011');
        req.params.put('document_type', '01');
        req.params.put('customer_number', '0000003000');

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetInvoiceDetailAPI.getInvoiceDetail();
        Test.stopTest();

        Assert.areEqual(200, res.statusCode, 'Expected HTTP 200 OK');
    }

    @IsTest
    static void testGetInvoiceDetailMissingParameter() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/getInvoicesDetailsAPI/id';
        req.httpMethod = 'GET';
        // billing_document_number parameter is missing

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetInvoiceDetailAPI.getInvoiceDetail();
        Test.stopTest();

        Assert.areEqual(400, res.statusCode, 'Expected HTTP 400 Bad Request');
        
        GetInvoiceDetailAPI.CNBSInvoiceResponse response = 
            (GetInvoiceDetailAPI.CNBSInvoiceResponse) JSON.deserialize(res.responseBody.toString(), GetInvoiceDetailAPI.CNBSInvoiceResponse.class);
        Assert.areEqual('E', response.status.message_type);
        Assert.isTrue(response.status.message_line_string.contains('required'), 'Message should contain "required"');
    }

    @IsTest
    static void testGetInvoiceDetailNotFound() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/getInvoicesDetailsAPI/id';
        req.httpMethod = 'GET';
        req.params.put('billing_document_number', 'NON_EXISTENT_DOC');

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GetInvoiceDetailAPI.getInvoiceDetail();
        Test.stopTest();

        Assert.areEqual(404, res.statusCode, 'Expected HTTP 404 Not Found');
        
        GetInvoiceDetailAPI.CNBSInvoiceResponse response = 
            (GetInvoiceDetailAPI.CNBSInvoiceResponse) JSON.deserialize(res.responseBody.toString(), GetInvoiceDetailAPI.CNBSInvoiceResponse.class);
        Assert.areEqual('E', response.status.message_type);
        Assert.areEqual('Invoice not found.', response.status.message_line_string);
    }
}